import Combine
import CoreLocation
import CoreMotion
import Foundation
import UIKit
@preconcurrency import UserNotifications

enum TripRecordingPhase: Equatable {
    case idle
    case watching
    case recording
    case confirming
}

struct ActiveTripSnapshot: Equatable {
    var startedAt: Date
    var distanceKm: Double
    var durationSec: Double
    var currentSpeedKmh: Double
    var maxSpeedKmh: Double
    var avgSpeedKmh: Double
    var routePointCount: Int
    var isPaused: Bool
    var source: String
    var vehicleId: String
    var vehicleName: String
    var route: [TripCoordinate]
}

struct PendingTripSave: Codable, Equatable, Identifiable {
    var id: UUID
    var vehicleId: String
    var vehicleName: String
    var startedAt: Date
    var endedAt: Date
    var distanceKm: Double
    var durationSec: Double
    var avgSpeedKmh: Double
    var maxSpeedKmh: Double
    var startCoordinate: TripCoordinate?
    var endCoordinate: TripCoordinate?
    var route: [TripCoordinate]
    var source: String
    var suggestedOdometer: Double
}

@MainActor
final class TripRecordingService: NSObject, ObservableObject {
    static let shared = TripRecordingService()

    @Published private(set) var phase: TripRecordingPhase = .idle
    @Published private(set) var autoTrackingEnabled = false
    @Published private(set) var snapshot: ActiveTripSnapshot?
    @Published private(set) var liveRoute: [TripCoordinate] = []
    @Published private(set) var lastLocationAccuracy: Double?
    /// Latest usable fix for the tracking map camera (watching or recording).
    @Published private(set) var followLatitude: Double?
    @Published private(set) var followLongitude: Double?
    /// Course in degrees clockwise from true north; negative when unknown.
    @Published private(set) var followCourseDegrees: Double = -1
    /// Bumps whenever follow pose changes so the map can re-pitch/follow.
    @Published private(set) var followTick: UInt = 0
    @Published private(set) var pendingSaves: [PendingTripSave] = []
    @Published var lastError: String?

    /// Kept for CarPlay and older call sites that act on the next trip in line.
    var pendingSave: PendingTripSave? { pendingSaves.first }

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var motionTimer: Timer?
    private var tickTimer: Timer?

    private var vehicleId: String?
    private var vehicleName: String = "Vehicle"
    private var driverName: String = ""
    private var baseOdometer: Double = 0
    private var source: String = "manual"
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var isPaused = false

    private var lastLocation: CLLocation?
    private var distanceMeters: Double = 0
    private var maxSpeedMps: Double = 0
    private var automotiveSince: Date?
    private var stationarySince: Date?
    private var lastLiveActivityUpdate = Date.distantPast

    /// Auto-start once automotive / speed holds for this long.
    private let autoStartHold: TimeInterval = 18
    /// Auto-end after this long of near-stationary movement.
    private let autoEndHold: TimeInterval = 180
    private let minSaveDistanceKm = 0.25
    private let drivingSpeedKmh = 12.0
    private let stationarySpeedKmh = 3.0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 8
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        autoTrackingEnabled = UserDefaults.standard.bool(forKey: Keys.autoTracking)
        restorePendingSaves()

        // Recording sessions are not restored after a terminated app, so any
        // surviving system activity would be stale while this service is idle.
        TripLiveActivityController.shared.cancel()
    }

    /// Call on launch / foreground so auto-detect survives app termination.
    func resumeBackgroundWatchingIfNeeded() {
        guard autoTrackingEnabled else { return }
        startWatchingIfNeeded()
    }

    /// Centers the Tracking map even when idle / waiting for the first fix.
    /// Seeds from Core Location's last known position, then requests a fresh update.
    func ensureMapFollowUpdates() {
        seedFollowFromLastKnownIfPossible()

        switch phase {
        case .watching, .recording:
            locationManager.requestLocation()
        case .idle, .confirming:
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 25
            locationManager.pausesLocationUpdatesAutomatically = true
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
        }
    }

    private enum Keys {
        static let autoTracking = "tripRecording.autoTrackingEnabled"
        static let pendingSaves = "tripRecording.pendingSaves.v1"
    }

    // MARK: - Public API

    func configure(vehicleId: String, vehicleName: String, currentOdometer: Double, driverName: String = "") {
        self.vehicleId = vehicleId
        self.vehicleName = vehicleName
        self.baseOdometer = currentOdometer
        self.driverName = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        if phase == .watching {
            // Keep watching with new vehicle context
        }
    }

    func setAutoTracking(_ enabled: Bool) {
        autoTrackingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.autoTracking)
        if enabled {
            startWatchingIfNeeded()
        } else if phase == .watching {
            stopWatching()
        }
    }

    func startManualTrip() {
        guard phase == .idle || phase == .watching else { return }
        guard vehicleId != nil else {
            lastError = "Pick a vehicle before starting a drive."
            return
        }
        beginRecording(source: "manual")
    }

    func pauseTrip() {
        guard phase == .recording, !isPaused else { return }
        isPaused = true
        pauseStartedAt = Date()
        publishSnapshot()
        updateLiveActivity(force: true)
    }

    func resumeTrip() {
        guard phase == .recording, isPaused else { return }
        if let pauseStartedAt {
            pausedAccumulated += Date().timeIntervalSince(pauseStartedAt)
        }
        pauseStartedAt = nil
        isPaused = false
        publishSnapshot()
        updateLiveActivity(force: true)
    }

    func endTrip() {
        guard phase == .recording else { return }
        finishRecording(autoEnded: false)
    }

    func discardPending(id: UUID? = nil) {
        let resolvedID = id ?? pendingSaves.first?.id
        guard let resolvedID else { return }
        pendingSaves.removeAll { $0.id == resolvedID }
        persistPendingSaves()
    }

    func markPendingSaved(id: UUID) {
        pendingSaves.removeAll { $0.id == id }
        persistPendingSaves()
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Watching / recording internals

    private func startWatchingIfNeeded() {
        guard autoTrackingEnabled else { return }
        guard phase == .idle || phase == .watching else { return }
        phase = .watching
        beginLocationUpdates(background: true)
        beginMotionUpdates()
    }

    private func stopWatching() {
        if phase == .watching {
            phase = .idle
        }
        if phase != .recording {
            stopLocationUpdates()
            stopMotionUpdates()
        }
    }

    private func beginRecording(source: String) {
        guard vehicleId != nil else {
            lastError = "Pick a vehicle so auto-detected drives can be saved."
            return
        }
        self.source = source
        startedAt = Date()
        pausedAccumulated = 0
        pauseStartedAt = nil
        isPaused = false
        lastLocation = nil
        liveRoute = []
        lastLocationAccuracy = nil
        distanceMeters = 0
        maxSpeedMps = 0
        automotiveSince = nil
        stationarySince = nil
        phase = .recording

        beginLocationUpdates(background: true)
        beginMotionUpdates()
        startTickTimer()

        let start = startedAt ?? Date()
        TripLiveActivityController.shared.start(vehicleName: vehicleName, startedAt: start)
        scheduleDriveNotification(
            title: personalized("your drive is now being tracked"),
            body: "\(vehicleName) started \(source == "auto" ? "automatically" : "manually"). Keep Veloseete running in the background—your route, distance and time are recording."
        )
        publishSnapshot()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func finishRecording(autoEnded: Bool) {
        tickTimer?.invalidate()
        tickTimer = nil

        let endedAt = Date()
        let started = startedAt ?? endedAt
        var duration = endedAt.timeIntervalSince(started) - pausedAccumulated
        if let pauseStartedAt, isPaused {
            duration -= endedAt.timeIntervalSince(pauseStartedAt)
        }
        duration = max(duration, 0)

        let distanceKm = distanceMeters / 1000
        let avgSpeed = duration > 0 ? (distanceKm / (duration / 3600)) : 0
        let maxSpeed = maxSpeedMps * 3.6

        stopLocationUpdates()
        stopMotionUpdates()

        TripLiveActivityController.shared.end(
            finalDistanceKm: distanceKm,
            durationSec: duration,
            maxSpeedKmh: maxSpeed
        )

        guard distanceKm >= minSaveDistanceKm else {
            lastError = autoEnded
                ? "Short movement ignored (< \(String(format: "%.1f", minSaveDistanceKm)) km)."
                : "Drive too short to save. Need at least \(String(format: "%.1f", minSaveDistanceKm)) km."
            scheduleDriveNotification(
                title: personalized("this drive wasn’t saved"),
                body: String(format: "%@ recorded %.1f km, below the %.1f km minimum. Your odometer was not changed.", vehicleName, distanceKm, minSaveDistanceKm)
            )
            resetSession()
            phase = autoTrackingEnabled ? .watching : .idle
            if autoTrackingEnabled { startWatchingIfNeeded() }
            return
        }

        let pending = PendingTripSave(
            id: UUID(),
            vehicleId: vehicleId ?? "",
            vehicleName: vehicleName,
            startedAt: started,
            endedAt: endedAt,
            distanceKm: distanceKm,
            durationSec: duration,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            startCoordinate: liveRoute.first,
            endCoordinate: liveRoute.last,
            route: downsample(liveRoute),
            source: source,
            suggestedOdometer: baseOdometer + distanceKm
        )
        pendingSaves.insert(pending, at: 0)
        persistPendingSaves()
        phase = autoTrackingEnabled ? .watching : .idle
        snapshot = nil
        liveRoute = []
        resetSession()

        if autoTrackingEnabled { startWatchingIfNeeded() }

        scheduleDriveNotification(
            title: personalized("your drive was added for review"),
            body: String(format: "%@ tracked %.1f km in %@. Review it anytime in My Drives; tracking remains ready for your next trip.", vehicleName, distanceKm, durationText(duration))
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)

    }

    private func restorePendingSaves() {
        guard let data = UserDefaults.standard.data(forKey: Keys.pendingSaves) else { return }
        do {
            pendingSaves = try JSONDecoder().decode([PendingTripSave].self, from: data)
                .sorted { $0.endedAt > $1.endedAt }
        } catch {
            print("[TripQueue] Could not restore pending trips: \(error.localizedDescription)")
        }
    }

    private func persistPendingSaves() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(pendingSaves), forKey: Keys.pendingSaves)
        } catch {
            print("[TripQueue] Could not persist pending trips: \(error.localizedDescription)")
        }
    }

    private func resetSession() {
        startedAt = nil
        pausedAccumulated = 0
        pauseStartedAt = nil
        isPaused = false
        lastLocation = nil
        distanceMeters = 0
        maxSpeedMps = 0
        automotiveSince = nil
        stationarySince = nil
        source = "manual"
    }

    private func beginLocationUpdates(background: Bool) {
        // Never let the system pause GPS while auto-detect is armed — paused
        // updates were a common reason long highway drives were never started
        // when the app had been killed or sitting in the background.
        locationManager.pausesLocationUpdatesAutomatically = false
        if phase == .recording {
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = 8
        } else {
            // Dense enough to catch highway merge / border runs without
            // turn-by-turn drain; significant-change monitoring covers cold starts.
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 40
        }
        locationManager.allowsBackgroundLocationUpdates = background
            && (locationManager.authorizationStatus == .authorizedAlways
                || locationManager.authorizationStatus == .authorizedWhenInUse)
        locationManager.startUpdatingLocation()
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    private func beginMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                self.handleMotion(activity)
            }
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopActivityUpdates()
    }

    private func startTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishSnapshot()
                self?.updateLiveActivity(force: false)
            }
        }
    }

    private func handleMotion(_ activity: CMMotionActivity) {
        let now = Date()
        if activity.automotive {
            if automotiveSince == nil { automotiveSince = now }
            stationarySince = nil
            if phase == .watching,
               let since = automotiveSince,
               now.timeIntervalSince(since) >= autoStartHold {
                beginRecording(source: "auto")
            }
        } else if activity.stationary || activity.walking || activity.running {
            automotiveSince = nil
            if phase == .recording, !isPaused {
                if stationarySince == nil { stationarySince = now }
                if let since = stationarySince, now.timeIntervalSince(since) >= autoEndHold {
                    finishRecording(autoEnded: true)
                }
            }
        }
    }

    private func ingest(_ location: CLLocation) {
        guard TripTrackingLogic.accepts(horizontalAccuracy: location.horizontalAccuracy) else { return }
        lastLocationAccuracy = location.horizontalAccuracy
        publishFollow(from: location)

        if phase == .watching {
            let speedKmh = max(0, location.speed) * 3.6
            if speedKmh >= drivingSpeedKmh {
                if automotiveSince == nil { automotiveSince = Date() }
                if let since = automotiveSince, Date().timeIntervalSince(since) >= autoStartHold {
                    beginRecording(source: "auto")
                }
            } else if speedKmh < stationarySpeedKmh {
                automotiveSince = nil
            }
            return
        }

        guard phase == .recording, !isPaused else { return }

        let acceptedSegment: Double
        if let last = lastLocation {
            acceptedSegment = TripTrackingLogic.acceptedSegmentDistance(from: last, to: location)
            distanceMeters += acceptedSegment
        } else {
            acceptedSegment = 0
        }

        let speed = max(0, location.speed)
        if speed > maxSpeedMps { maxSpeedMps = speed }

        // Auto-end by GPS when nearly stopped for a while
        let speedKmh = speed * 3.6
        if speedKmh < stationarySpeedKmh {
            if stationarySince == nil { stationarySince = Date() }
            if let since = stationarySince, Date().timeIntervalSince(since) >= autoEndHold {
                finishRecording(autoEnded: true)
                return
            }
        } else {
            stationarySince = nil
        }

        lastLocation = location
        let point = TripCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        // Keep the route and its distance calculation on the same acceptance path.
        // Previously rejected GPS jumps still appeared as sharp spikes on the map.
        let shouldAppendRoutePoint = liveRoute.isEmpty || acceptedSegment > 0
        let updatedRoute = shouldAppendRoutePoint
            ? TripTrackingLogic.appending(point, to: liveRoute)
            : liveRoute
        if updatedRoute.count != liveRoute.count {
            liveRoute = updatedRoute
            print("[TripRoute] accepted point \(liveRoute.count), accuracy \(Int(location.horizontalAccuracy))m")
        }
        publishSnapshot()
        updateLiveActivity(force: false)
    }

    private func seedFollowFromLastKnownIfPossible() {
        guard let location = locationManager.location else { return }
        // Looser than trip acceptance — map center can use a coarser last-known fix.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 250 else { return }
        publishFollow(from: location)
    }

    private func publishFollow(from location: CLLocation) {
        followLatitude = location.coordinate.latitude
        followLongitude = location.coordinate.longitude
        if location.course >= 0 {
            followCourseDegrees = location.course
        }
        followTick &+= 1
    }

    private func publishSnapshot() {
        guard phase == .recording, let startedAt else {
            snapshot = nil
            return
        }
        var duration = Date().timeIntervalSince(startedAt) - pausedAccumulated
        if let pauseStartedAt, isPaused {
            duration -= Date().timeIntervalSince(pauseStartedAt)
        }
        duration = max(duration, 0)
        let distanceKm = distanceMeters / 1000
        let avg = duration > 0 ? distanceKm / (duration / 3600) : 0
        snapshot = ActiveTripSnapshot(
            startedAt: startedAt,
            distanceKm: distanceKm,
            durationSec: duration,
            currentSpeedKmh: max(0, (lastLocation?.speed ?? 0) * 3.6),
            maxSpeedKmh: maxSpeedMps * 3.6,
            avgSpeedKmh: avg,
            routePointCount: liveRoute.count,
            isPaused: isPaused,
            source: source,
            vehicleId: vehicleId ?? "",
            vehicleName: vehicleName,
            route: liveRoute
        )
    }

    private func updateLiveActivity(force: Bool) {
        guard let snapshot else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveActivityUpdate) >= 2.5 else { return }
        lastLiveActivityUpdate = now
        TripLiveActivityController.shared.update(
            distanceKm: snapshot.distanceKm,
            durationSec: snapshot.durationSec,
            currentSpeedKmh: snapshot.currentSpeedKmh,
            maxSpeedKmh: snapshot.maxSpeedKmh,
            isPaused: snapshot.isPaused
        )
    }

    private func downsample(_ points: [TripCoordinate]) -> [TripCoordinate] {
        TripTrackingLogic.downsample(points)
    }

    private func scheduleDriveNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let deliver: () -> Void = {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.categoryIdentifier = "TRIP_STATUS"
                let request = UNNotificationRequest(
                    identifier: "trip-\(UUID().uuidString)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
                )
                center.add(request) { error in
                    if let error { print("[TripNotification] delivery failed: \(error)") }
                }
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                deliver()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted { deliver() }
                    if let error { print("[TripNotification] authorization failed: \(error)") }
                }
            case .denied:
                print("[TripNotification] notifications are disabled in Settings")
            @unknown default:
                break
            }
        }
    }

    private func personalized(_ message: String) -> String {
        driverName.isEmpty
            ? message.prefix(1).uppercased() + String(message.dropFirst())
            : "\(driverName), \(message)"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }
}

extension TripRecordingService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                self.ingest(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.phase == .watching || self.phase == .recording {
                self.beginLocationUpdates(background: true)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[TripLocation] update failed: \(error.localizedDescription)")
    }
}
