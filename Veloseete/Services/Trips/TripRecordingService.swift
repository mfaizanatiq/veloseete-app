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

    private static let pendingReviewPrefix = "veloseete.trip.pending."

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
    private var lastWidgetTrackingUpdate = Date.distantPast

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
        refreshPendingReviewReminders(forceReschedule: true)

        // Recording sessions are not restored after a terminated app, so any
        // surviving system activity would be stale while this service is idle.
        TripLiveActivityController.shared.cancel()
    }

    /// Call on launch / foreground so auto-detect survives app termination.
    func resumeBackgroundWatchingIfNeeded() {
        guard autoTrackingEnabled else { return }
        startWatchingIfNeeded()
    }

    /// Keeps (or clears) nudges for trips waiting in My Drives.
    /// Pass `forceReschedule` when the pending queue itself changed.
    func refreshPendingReviewReminders(forceReschedule: Bool = false) {
        let count = pendingSaves.count
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let existing = pending
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.pendingReviewPrefix) }

            if count == 0 {
                if !existing.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: existing)
                }
                return
            }

            // Foreground / launch: don't reset the clock if nudges are already queued.
            if !forceReschedule, !existing.isEmpty {
                return
            }

            if !existing.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: existing)
            }

            let copy = DriveNotificationCopy.pendingReview(count: count)
            Task { @MainActor in
                let title = self.personalized(copy.title)
                let body = copy.body
                center.getNotificationSettings { settings in
                    let deliver: () -> Void = {
                        let intervals: [(id: String, seconds: TimeInterval)] = [
                            ("soon", 60 * 60),
                            ("later", 6 * 60 * 60),
                            ("day", 24 * 60 * 60),
                        ]
                        for slot in intervals {
                            let content = UNMutableNotificationContent()
                            content.title = title
                            content.body = body
                            content.sound = .default
                            content.categoryIdentifier = "TRIP_PENDING_REVIEW"
                            let request = UNNotificationRequest(
                                identifier: Self.pendingReviewPrefix + slot.id,
                                content: content,
                                trigger: UNTimeIntervalNotificationTrigger(
                                    timeInterval: max(slot.seconds, 60),
                                    repeats: false
                                )
                            )
                            center.add(request) { error in
                                if let error {
                                    print("[TripNotification] pending review schedule failed: \(error)")
                                }
                            }
                        }
                    }

                    switch settings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        deliver()
                    case .notDetermined:
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            if granted { deliver() }
                        }
                    default:
                        break
                    }
                }
            }
        }
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
            startHeadingUpdatesIfAvailable()
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

    /// Clears queued trips / follow pose when the account is wiped.
    func wipeLocalStateForAccountDeletion() {
        pendingSaves = []
        persistPendingSaves()
        snapshot = nil
        liveRoute = []
        if phase == .recording {
            tickTimer?.invalidate()
            tickTimer = nil
            stopLocationUpdates()
            stopMotionUpdates()
            TripLiveActivityController.shared.cancel()
        }
        phase = .idle
        setAutoTracking(false)
        followLatitude = nil
        followLongitude = nil
        followCourseDegrees = -1
        resetSession()
        CarPlayWidgetStateStore.updateTracking(
            state: .idle,
            autoTrackingEnabled: false,
            reloadTimeline: true
        )
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
        let startCopy = DriveNotificationCopy.start(vehicleName: vehicleName)
        scheduleDriveNotification(
            title: personalized(startCopy.title),
            body: startCopy.body
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
            let shortCopy = DriveNotificationCopy.tooShort(
                distanceKm: distanceKm,
                minimumKm: minSaveDistanceKm
            )
            scheduleDriveNotification(
                title: personalized(shortCopy.title),
                body: shortCopy.body
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

        let doneCopy = DriveNotificationCopy.ready(
            distanceKm: distanceKm,
            duration: durationText(duration)
        )
        scheduleDriveNotification(
            title: personalized(doneCopy.title),
            body: doneCopy.body
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
        refreshPendingReviewReminders(forceReschedule: true)
        CarPlayWidgetStateStore.updatePendingTripCount(pendingSaves.count)
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
        startHeadingUpdatesIfAvailable()
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    private func startHeadingUpdatesIfAvailable() {
        guard CLLocationManager.headingAvailable() else { return }
        locationManager.headingFilter = 6
        locationManager.startUpdatingHeading()
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

    private func publishHeading(_ heading: CLHeading) {
        guard heading.headingAccuracy >= 0, heading.headingAccuracy <= 40 else { return }
        let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard degrees >= 0 else { return }

        // Prefer GPS course while moving — more stable than compass in a car.
        let reference = lastLocation ?? locationManager.location
        if let location = reference, location.course >= 0, location.speed >= 1.2 {
            return
        }

        let previous = followCourseDegrees
        followCourseDegrees = degrees
        // Don't bump followTick on every compass tick — only unlock the first heading
        // so the FOV cone can appear without yanking the camera.
        if previous < 0 {
            followTick &+= 1
        }
    }

    private func publishSnapshot() {
        guard phase == .recording, let startedAt else {
            snapshot = nil
            syncWidgetTracking(force: true)
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
        syncWidgetTracking(force: false)
    }

    private func syncWidgetTracking(force: Bool) {
        let state: CarPlayWidgetTrackingState
        switch phase {
        case .idle: state = .idle
        case .watching: state = .watching
        case .recording: state = isPaused ? .paused : .recording
        case .confirming: state = .confirming
        }

        let now = Date()
        let shouldReload = force || now.timeIntervalSince(lastWidgetTrackingUpdate) >= 30
        guard force || shouldReload || phase == .recording else { return }

        if phase == .recording, let snapshot {
            CarPlayWidgetStateStore.updateTracking(
                state: state,
                autoTrackingEnabled: autoTrackingEnabled,
                startedAt: snapshot.startedAt,
                distanceKm: snapshot.distanceKm,
                durationSec: snapshot.durationSec,
                currentSpeedKmh: snapshot.currentSpeedKmh,
                reloadTimeline: shouldReload
            )
        } else {
            CarPlayWidgetStateStore.updateTracking(
                state: state,
                autoTrackingEnabled: autoTrackingEnabled,
                reloadTimeline: shouldReload
            )
        }
        if shouldReload {
            lastWidgetTrackingUpdate = now
        }
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

/// Quirky co-pilot lines for trip notifications — short, personal, a little Veloseete.
private enum DriveNotificationCopy {
    struct Line {
        let title: String
        let body: String
    }

    static func start(vehicleName: String) -> Line {
        pick([
            Line(title: "Drive time! 🚗", body: "\(vehicleName) is on the move. I'm watching. I'm always watching."),
            Line(title: "There you are!", body: "I knew \(vehicleName) couldn't sit still. Tracking started — don't mess this up."),
            Line(title: "Ooh, we're moving!", body: "\(vehicleName) is rolling. Every km counts. I'm counting them."),
            Line(title: "Trip started!", body: "Me and \(vehicleName) are on it. You just drive. We believe in you. Mostly."),
        ])
    }

    static func tooShort(distanceKm: Double, minimumKm: Double) -> Line {
        let stats = String(format: "%.1f km · needs %.1f", distanceKm, minimumKm)
        return pick([
            Line(title: "That... was it?", body: "\(stats). I'm not mad. I'm just disappointed."),
            Line(title: "Hmm. That didn't count.", body: "\(stats). We don't talk about drives like that one."),
            Line(title: "So close! (Not really.)", body: "\(stats). Try an actual road next time."),
            Line(title: "I saw nothing.", body: "\(stats). Your secret is safe with me. This time."),
        ])
    }

    static func ready(distanceKm: Double, duration: String) -> Line {
        let stats = String(format: "%.1f km in %@", distanceKm, duration)
        return pick([
            Line(title: "Drive complete! 🎉", body: "\(stats). Now confirm it in My Drives. You wouldn't leave it hanging... right?"),
            Line(title: "Look at you go!", body: "\(stats). One tap in My Drives makes it official. Just one. Tiny. Tap."),
            Line(title: "You did it!", body: "\(stats). It's waiting in My Drives. Waiting. Patiently. For now."),
            Line(title: "Nailed it!", body: "\(stats). Confirm it in My Drives before I start sending sad notifications."),
        ])
    }

    static func pendingReview(count: Int) -> Line {
        if count == 1 {
            return pick([
                Line(title: "Your drive misses you 🥺", body: "It's been sitting in My Drives all alone. One tap. That's all it wants."),
                Line(title: "Still there. Still waiting.", body: "That drive isn't going to confirm itself. Believe me, I checked."),
                Line(title: "Knock knock.", body: "It's your unconfirmed drive. It knows you saw this notification."),
            ])
        }
        return pick([
            Line(title: "\(count) drives are crying 😢", body: "They just want to be confirmed. Are you really going to ignore them?"),
            Line(title: "This is getting awkward.", body: "\(count) drives in My Drives, still unconfirmed. I can't keep covering for you."),
            Line(title: "Fine. I'll say it.", body: "\(count) drives are waiting and you've been ignoring them. Tap My Drives. Do the right thing."),
        ])
    }

    private static func pick(_ lines: [Line]) -> Line {
        lines.randomElement() ?? lines[0]
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

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.publishHeading(newHeading)
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[TripLocation] update failed: \(error.localizedDescription)")
    }
}
