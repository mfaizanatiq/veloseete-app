import Combine
import CoreLocation
import CoreMotion
import Foundation
import UIKit
import UserNotifications

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
}

struct PendingTripSave: Equatable {
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
    @Published var pendingSave: PendingTripSave?
    @Published var lastError: String?

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var motionTimer: Timer?
    private var tickTimer: Timer?

    private var vehicleId: String?
    private var vehicleName: String = "Vehicle"
    private var baseOdometer: Double = 0
    private var source: String = "manual"
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var isPaused = false

    private var lastLocation: CLLocation?
    private var route: [TripCoordinate] = []
    private var distanceMeters: Double = 0
    private var maxSpeedMps: Double = 0
    private var automotiveSince: Date?
    private var stationarySince: Date?
    private var lastLiveActivityUpdate = Date.distantPast

    /// Auto-start once automotive / speed holds for this long.
    private let autoStartHold: TimeInterval = 25
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
    }

    private enum Keys {
        static let autoTracking = "tripRecording.autoTrackingEnabled"
    }

    // MARK: - Public API

    func configure(vehicleId: String, vehicleName: String, currentOdometer: Double) {
        self.vehicleId = vehicleId
        self.vehicleName = vehicleName
        self.baseOdometer = currentOdometer
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

    func discardPending() {
        pendingSave = nil
        phase = autoTrackingEnabled ? .watching : .idle
        if autoTrackingEnabled { startWatchingIfNeeded() }
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
        self.source = source
        startedAt = Date()
        pausedAccumulated = 0
        pauseStartedAt = nil
        isPaused = false
        lastLocation = nil
        route = []
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
            title: "Drive started",
            body: "Veloseete is tracking \(vehicleName)."
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
            resetSession()
            phase = autoTrackingEnabled ? .watching : .idle
            if autoTrackingEnabled { startWatchingIfNeeded() }
            return
        }

        let pending = PendingTripSave(
            vehicleId: vehicleId ?? "",
            vehicleName: vehicleName,
            startedAt: started,
            endedAt: endedAt,
            distanceKm: distanceKm,
            durationSec: duration,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: downsample(route),
            source: source,
            suggestedOdometer: baseOdometer + distanceKm
        )
        pendingSave = pending
        phase = .confirming
        snapshot = nil
        resetSession()

        scheduleDriveNotification(
            title: "Drive ready",
            body: String(format: "%.1f km recorded — confirm to update odometer.", distanceKm)
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if autoTrackingEnabled {
            // Resume watching after confirm/dismiss
        }
    }

    private func resetSession() {
        startedAt = nil
        pausedAccumulated = 0
        pauseStartedAt = nil
        isPaused = false
        lastLocation = nil
        route = []
        distanceMeters = 0
        maxSpeedMps = 0
        automotiveSince = nil
        stationarySince = nil
        source = "manual"
    }

    private func beginLocationUpdates(background: Bool) {
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
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 45 else { return }

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

        if let last = lastLocation {
            let delta = location.distance(from: last)
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            if delta > 2, delta < 200, dt > 0, dt < 30 {
                distanceMeters += delta
            }
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
        if route.last != point {
            route.append(point)
        }
        publishSnapshot()
        updateLiveActivity(force: false)
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
            routePointCount: route.count,
            isPaused: isPaused,
            source: source,
            vehicleId: vehicleId ?? "",
            vehicleName: vehicleName
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
        guard points.count > 200 else { return points }
        let step = max(1, points.count / 180)
        var reduced: [TripCoordinate] = []
        for (idx, point) in points.enumerated() where idx % step == 0 {
            reduced.append(point)
        }
        if let last = points.last, reduced.last != last {
            reduced.append(last)
        }
        return reduced
    }

    private func scheduleDriveNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "trip-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

extension TripRecordingService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.ingest(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.phase == .watching || self.phase == .recording {
                self.beginLocationUpdates(background: true)
            }
        }
    }
}
