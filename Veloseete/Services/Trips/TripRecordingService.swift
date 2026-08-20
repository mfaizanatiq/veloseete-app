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
    /// Downsampled polyline for the Tracking map — published on a throttle, not every GPS tick.
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
    private var lastLiveRoutePublish = Date.distantPast
    private var lastWidgetWriteState: CarPlayWidgetTrackingState?
    private var lastWidgetWriteDistanceKm = -1.0
    private var lastWidgetWriteDurationSec = -1.0
    private var driveMoodState = DriveMoodLogic.State()
    /// Typical tank L/100 used to scale the live efficiency estimate.
    private var baselineL100: Double = 8.0
    /// Full-fidelity route buffer for save — not published to SwiftUI.
    private var recordedRoute: [TripCoordinate] = []
    /// Continuous GPS while watching — only after motion/speed hints a drive.
    private var watchingGPSEscalated = false
    private var watchingIdleSince: Date?

    private let liveRoutePublishInterval: TimeInterval = 2.5
    private let liveRouteDisplayMax = 180
    private let recordedRouteSoftCap = 2_500
    private let recordedRouteCompacted = 1_200
    /// After this long below driving speed, drop continuous GPS back to coarse watch.
    private let watchingDeescalateHold: TimeInterval = 90

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
        // Auto-detect is restored per account in `bind(userId:)` — never from a
        // device-global flag, or account B inherits account A's watching.
        autoTrackingEnabled = false
        // Pending drives are restored in `bind(userId:)` so they stay per-account.

        // Recording sessions are not restored after a terminated app, so any
        // surviving system activity would be stale while this service is idle.
        TripLiveActivityController.shared.cancel()
    }

    /// Bind the pending-review queue + auto-detect preference to the signed-in account.
    /// Sign-out detaches memory only; the same user keeps their queue / preference on disk.
    func bind(userId: String?) {
        if boundUserId == userId {
            if userId != nil, pendingSaves.isEmpty {
                restorePendingSaves()
            }
            return
        }

        if boundUserId != nil {
            persistPendingSaves()
        }

        boundUserId = userId
        if let userId {
            restorePendingSaves()
            restoreAutoTrackingPreference(for: userId)
            // Do not start watching here — wait until `configure(vehicleId:)` so
            // auto-starts are never tagged to a previous account's car.
        } else {
            autoTrackingEnabled = false
            pendingSaves = []
            CarPlayWidgetStateStore.updatePendingTripCount(0)
            refreshPendingReviewReminders(forceReschedule: true)
        }
    }

    /// Call on launch / foreground so auto-detect survives app termination.
    /// No-ops until a vehicle is configured for the bound account.
    func resumeBackgroundWatchingIfNeeded() {
        guard autoTrackingEnabled, vehicleId != nil else { return }
        startWatchingIfNeeded()
    }

    /// Minimum unconfirmed drives before we schedule neglect nudges.
    /// One pending drive stays quiet in My Drives — no push until it piles up.
    private static let pendingReviewNudgeThreshold = 2

    /// Keeps (or clears) nudges for trips waiting in My Drives.
    /// Pass `forceReschedule` when the pending queue itself changed.
    func refreshPendingReviewReminders(forceReschedule: Bool = false) {
        let count = pendingSaves.count
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let existing = pending
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.pendingReviewPrefix) }

            // Quiet until the queue looks neglected (2+ waiting).
            guard count >= Self.pendingReviewNudgeThreshold else {
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
                        // Fewer, later nudges — not a 1-hour guilt trip.
                        let intervals: [(id: String, seconds: TimeInterval)] = [
                            ("later", 4 * 60 * 60),
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

    /// True while Tracking map owns continuous GPS/heading (idle / confirming only).
    /// Watching and recording own their own location session separately.
    private var mapFollowOwnedUpdates = false

    /// Centers the Tracking map even when idle / waiting for the first fix.
    /// Seeds from Core Location's last known position, then requests a fresh update.
    func ensureMapFollowUpdates() {
        seedFollowFromLastKnownIfPossible()

        switch phase {
        case .watching, .recording:
            // Session already owns GPS — nudge a fresh fix for the camera only.
            mapFollowOwnedUpdates = false
            locationManager.requestLocation()
        case .idle, .confirming:
            mapFollowOwnedUpdates = true
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 25
            locationManager.pausesLocationUpdatesAutomatically = true
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.startUpdatingLocation()
            startHeadingUpdatesIfAvailable()
            locationManager.requestLocation()
        }
    }

    /// Stops map-only GPS/heading when leaving Tracking.
    /// Never interrupts an active watching or recording session.
    func stopMapFollowUpdates() {
        guard mapFollowOwnedUpdates else { return }
        mapFollowOwnedUpdates = false
        guard phase == .idle || phase == .confirming else { return }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    private enum Keys {
        /// Legacy device-global auto-detect flag (pre per-account scoping).
        static let legacyAutoTracking = "tripRecording.autoTrackingEnabled"
        static func autoTracking(for userId: String) -> String {
            "tripRecording.autoTrackingEnabled.v1.\(userId)"
        }
        /// Legacy device-global queue (pre per-account scoping).
        static let legacyPendingSaves = "tripRecording.pendingSaves.v1"
        static func pendingSaves(for userId: String) -> String {
            "tripRecording.pendingSaves.v1.\(userId)"
        }
    }

    /// Account that owns the in-memory pending-review queue.
    private var boundUserId: String?

    // MARK: - Public API

    func configure(
        vehicleId: String,
        vehicleName: String,
        currentOdometer: Double,
        driverName: String = "",
        baselineL100: Double? = nil
    ) {
        self.vehicleId = vehicleId
        self.vehicleName = vehicleName
        self.baseOdometer = currentOdometer
        self.driverName = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let baselineL100, baselineL100 > 0 {
            self.baselineL100 = baselineL100
        }
        // Vehicle context is the gate for auto-detect — arm watching once we have it.
        if autoTrackingEnabled {
            startWatchingIfNeeded()
        }
    }

    func setAutoTracking(_ enabled: Bool) {
        autoTrackingEnabled = enabled
        persistAutoTrackingPreference()
        if enabled {
            startWatchingIfNeeded()
        } else if phase == .watching {
            stopWatching()
            syncWidgetTracking(force: true)
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

    /// Drops queued review drives for cars no longer in the active garage
    /// (archived or deleted), so they can't sit in My Drives forever.
    /// Persisting also clears their review reminders and the widget badge.
    func prunePendingSaves(activeVehicleIds: Set<String>) {
        let before = pendingSaves.count
        pendingSaves.removeAll { !activeVehicleIds.contains($0.vehicleId) }
        guard pendingSaves.count != before else { return }
        print("[TripQueue] Pruned \(before - pendingSaves.count) pending drive(s) for archived/removed cars")
        persistPendingSaves()
    }

    func clearError() {
        lastError = nil
    }

    /// Stops tracking and clears the on-screen session without deleting this
    /// account's pending drive reviews (they reload on the next sign-in).
    func detachSessionForSignOut() {
        // Prefer saving an in-progress drive into the per-uid review queue over
        // silently discarding it when the user signs out mid-trip.
        if phase == .recording {
            let keepAuto = autoTrackingEnabled
            autoTrackingEnabled = false
            finishRecording(autoEnded: false)
            autoTrackingEnabled = keepAuto
            persistAutoTrackingPreference()
        }
        if boundUserId != nil {
            persistPendingSaves()
        }
        // Stop GPS now, but do not wipe this account's auto-detect preference —
        // the same user should still be armed after the next sign-in.
        tearDownSessionHardware(clearAutoTracking: false)
        clearVehicleContext()
        autoTrackingEnabled = false
        pendingSaves = []
        boundUserId = nil
        CarPlayWidgetStateStore.updatePendingTripCount(0)
        refreshPendingReviewReminders(forceReschedule: true)
    }

    /// Permanently clears queued trips when the account is deleted.
    func wipeLocalStateForAccountDeletion() {
        if let uid = boundUserId {
            UserDefaults.standard.removeObject(forKey: Keys.pendingSaves(for: uid))
            UserDefaults.standard.removeObject(forKey: Keys.autoTracking(for: uid))
        }
        UserDefaults.standard.removeObject(forKey: Keys.legacyPendingSaves)
        UserDefaults.standard.removeObject(forKey: Keys.legacyAutoTracking)
        pendingSaves = []
        boundUserId = nil
        tearDownSessionHardware(clearAutoTracking: true)
        clearVehicleContext()
        CarPlayWidgetStateStore.updatePendingTripCount(0)
        refreshPendingReviewReminders(forceReschedule: true)
    }

    private func tearDownSessionHardware(clearAutoTracking: Bool) {
        snapshot = nil
        liveRoute = []
        recordedRoute = []

        // Always tear down hardware first. Watching and recording both leave
        // GPS/motion running; setting phase to .idle before setAutoTracking(false)
        // used to skip stopWatching() and leak location updates after sign-out.
        mapFollowOwnedUpdates = false
        tickTimer?.invalidate()
        tickTimer = nil
        stopLocationUpdates()
        stopMotionUpdates()
        TripLiveActivityController.shared.cancel()

        if clearAutoTracking {
            autoTrackingEnabled = false
            if let uid = boundUserId {
                UserDefaults.standard.set(false, forKey: Keys.autoTracking(for: uid))
            }
            UserDefaults.standard.removeObject(forKey: Keys.legacyAutoTracking)
        }
        phase = .idle

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

    private func clearVehicleContext() {
        vehicleId = nil
        vehicleName = "Vehicle"
        driverName = ""
        baseOdometer = 0
    }

    // MARK: - Watching / recording internals

    private func startWatchingIfNeeded() {
        guard autoTrackingEnabled, vehicleId != nil else { return }
        guard phase == .idle || phase == .watching else { return }
        // Session takes over GPS ownership from the map.
        mapFollowOwnedUpdates = false
        phase = .watching
        beginLocationUpdates(background: true)
        beginMotionUpdates()
        syncWidgetTracking(force: true)
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
        // Recording owns GPS — map follow must not think it still owns updates.
        mapFollowOwnedUpdates = false
        startedAt = Date()
        pausedAccumulated = 0
        pauseStartedAt = nil
        isPaused = false
        lastLocation = nil
        liveRoute = []
        recordedRoute = []
        lastLiveRoutePublish = .distantPast
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
        driveMoodState = DriveMoodLogic.State()
        TripLiveActivityController.shared.start(
            vehicleName: vehicleName,
            startedAt: start,
            baselineL100: baselineL100
        )
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

        let mood = DriveMoodLogic.finalSnapshot(
            state: driveMoodState,
            baselineL100: baselineL100,
            saved: distanceKm >= minSaveDistanceKm
        )
        TripLiveActivityController.shared.end(
            finalDistanceKm: distanceKm,
            durationSec: duration,
            maxSpeedKmh: maxSpeed,
            mood: mood
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
            liveRoute = []
            recordedRoute = []
            resetSession()
            phase = autoTrackingEnabled ? .watching : .idle
            if autoTrackingEnabled { startWatchingIfNeeded() }
            return
        }

        let routeForSave = downsample(recordedRoute)
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
            startCoordinate: recordedRoute.first,
            endCoordinate: recordedRoute.last,
            route: routeForSave,
            source: source,
            suggestedOdometer: baseOdometer + distanceKm
        )
        pendingSaves.insert(pending, at: 0)
        persistPendingSaves()
        phase = autoTrackingEnabled ? .watching : .idle
        snapshot = nil
        liveRoute = []
        recordedRoute = []
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
        guard let userId = boundUserId else {
            pendingSaves = []
            return
        }
        migrateLegacyPendingSavesIfNeeded(into: userId)

        guard let data = UserDefaults.standard.data(forKey: Keys.pendingSaves(for: userId)) else {
            pendingSaves = []
            CarPlayWidgetStateStore.updatePendingTripCount(0)
            refreshPendingReviewReminders(forceReschedule: true)
            return
        }
        do {
            pendingSaves = try JSONDecoder().decode([PendingTripSave].self, from: data)
                .sorted { $0.endedAt > $1.endedAt }
            CarPlayWidgetStateStore.updatePendingTripCount(pendingSaves.count)
            refreshPendingReviewReminders(forceReschedule: true)
            print("[TripQueue] Restored \(pendingSaves.count) pending drive(s) for user")
        } catch {
            print("[TripQueue] Could not restore pending trips: \(error.localizedDescription)")
            pendingSaves = []
        }
    }

    private func migrateLegacyPendingSavesIfNeeded(into userId: String) {
        let key = Keys.pendingSaves(for: userId)
        guard UserDefaults.standard.data(forKey: key) == nil,
              let legacy = UserDefaults.standard.data(forKey: Keys.legacyPendingSaves) else { return }
        UserDefaults.standard.set(legacy, forKey: key)
        UserDefaults.standard.removeObject(forKey: Keys.legacyPendingSaves)
        print("[TripQueue] Migrated legacy pending drives to account \(userId.prefix(6))…")
    }

    private func restoreAutoTrackingPreference(for userId: String) {
        let key = Keys.autoTracking(for: userId)
        if UserDefaults.standard.object(forKey: key) != nil {
            autoTrackingEnabled = UserDefaults.standard.bool(forKey: key)
            return
        }
        // One-time migrate: credit the first account that signs in after the
        // device-global flag era, then clear the global key so account B cannot inherit it.
        if UserDefaults.standard.object(forKey: Keys.legacyAutoTracking) != nil {
            let legacy = UserDefaults.standard.bool(forKey: Keys.legacyAutoTracking)
            UserDefaults.standard.set(legacy, forKey: key)
            UserDefaults.standard.removeObject(forKey: Keys.legacyAutoTracking)
            autoTrackingEnabled = legacy
            print("[TripQueue] Migrated legacy auto-detect=\(legacy) to account \(userId.prefix(6))…")
            return
        }
        autoTrackingEnabled = false
    }

    private func persistAutoTrackingPreference() {
        guard let userId = boundUserId else { return }
        UserDefaults.standard.set(autoTrackingEnabled, forKey: Keys.autoTracking(for: userId))
        UserDefaults.standard.removeObject(forKey: Keys.legacyAutoTracking)
    }

    private func persistPendingSaves() {
        guard let userId = boundUserId else { return }
        do {
            UserDefaults.standard.set(
                try JSONEncoder().encode(pendingSaves),
                forKey: Keys.pendingSaves(for: userId)
            )
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
        let status = locationManager.authorizationStatus
        locationManager.allowsBackgroundLocationUpdates = background
            && (status == .authorizedAlways || status == .authorizedWhenInUse)
        locationManager.activityType = .automotiveNavigation

        if phase == .recording {
            watchingGPSEscalated = false
            watchingIdleSince = nil
            applyRecordingGPSProfile()
            locationManager.startUpdatingLocation()
            startHeadingUpdatesIfAvailable()
            if status == .authorizedAlways {
                locationManager.startMonitoringSignificantLocationChanges()
            }
            return
        }

        // Watching needs a live location session. Significant-change alone
        // wakes too rarely (often after 500m+), and motion callbacks go quiet
        // once the app is suspended — so drives never reached the auto-start hold.
        watchingGPSEscalated = false
        watchingIdleSince = nil
        applyWatchingGPSProfile(escalated: false)
        locationManager.startUpdatingLocation()
        startHeadingUpdatesIfAvailable()
        if status == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    private func applyRecordingGPSProfile() {
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 8
    }

    private func applyWatchingGPSProfile(escalated: Bool) {
        // Never let iOS pause the watch session — paused GPS is why auto-start
        // silently died after the battery-saving pass.
        locationManager.pausesLocationUpdatesAutomatically = false
        if escalated {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 25
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager.distanceFilter = 50
        }
    }

    /// Tighten GPS while watching after a drive hint (motion / speed).
    private func escalateWatchingGPSIfNeeded() {
        guard phase == .watching, !watchingGPSEscalated else { return }
        watchingGPSEscalated = true
        watchingIdleSince = nil
        applyWatchingGPSProfile(escalated: true)
        locationManager.startUpdatingLocation()
        startHeadingUpdatesIfAvailable()
    }

    /// Drop back to coarse continuous GPS after sitting still, stay armed.
    private func deescalateWatchingGPSIfNeeded() {
        guard phase == .watching, watchingGPSEscalated else { return }
        watchingGPSEscalated = false
        watchingIdleSince = nil
        applyWatchingGPSProfile(escalated: false)
        locationManager.startUpdatingLocation()
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    private func stopLocationUpdates() {
        watchingGPSEscalated = false
        watchingIdleSince = nil
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
            watchingIdleSince = nil
            if phase == .watching {
                escalateWatchingGPSIfNeeded()
                if let since = automotiveSince,
                   now.timeIntervalSince(since) >= autoStartHold {
                    beginRecording(source: "auto")
                }
            }
        } else if activity.stationary || activity.walking || activity.running {
            automotiveSince = nil
            if phase == .recording, !isPaused {
                if stationarySince == nil { stationarySince = now }
                if let since = stationarySince, now.timeIntervalSince(since) >= autoEndHold {
                    finishRecording(autoEnded: true)
                }
            } else if phase == .watching, watchingGPSEscalated {
                if watchingIdleSince == nil { watchingIdleSince = now }
                if let since = watchingIdleSince,
                   now.timeIntervalSince(since) >= watchingDeescalateHold {
                    deescalateWatchingGPSIfNeeded()
                }
            }
        }
    }

    private func ingest(_ location: CLLocation) {
        if phase == .watching {
            ingestWatching(location)
            return
        }

        guard TripTrackingLogic.accepts(horizontalAccuracy: location.horizontalAccuracy) else { return }
        lastLocationAccuracy = location.horizontalAccuracy
        publishFollow(from: location)

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
        let shouldAppendRoutePoint = recordedRoute.isEmpty || acceptedSegment > 0
        if shouldAppendRoutePoint {
            recordedRoute = TripTrackingLogic.appending(point, to: recordedRoute)
            if recordedRoute.count > recordedRouteSoftCap {
                recordedRoute = TripTrackingLogic.downsample(
                    recordedRoute,
                    maximum: recordedRouteCompacted
                )
            }
            publishLiveRouteIfNeeded(force: false)
        }
        publishSnapshot()
        updateLiveActivity(force: false)
    }

    /// Watching accepts coarser fixes (significant-change is often >45m).
    private func ingestWatching(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else { return }
        lastLocationAccuracy = location.horizontalAccuracy
        if location.horizontalAccuracy <= 80 {
            publishFollow(from: location)
        }

        let hasSpeed = location.speed >= 0
        let speedKmh = hasSpeed ? location.speed * 3.6 : 0

        if hasSpeed, speedKmh >= drivingSpeedKmh {
            escalateWatchingGPSIfNeeded()
            watchingIdleSince = nil
            if automotiveSince == nil { automotiveSince = Date() }
            if let since = automotiveSince, Date().timeIntervalSince(since) >= autoStartHold {
                beginRecording(source: "auto")
            }
        } else if !hasSpeed {
            // Significant-change / coarse fix without speed — escalate to measure.
            escalateWatchingGPSIfNeeded()
        } else if speedKmh < stationarySpeedKmh {
            automotiveSince = nil
            if watchingGPSEscalated {
                if watchingIdleSince == nil { watchingIdleSince = Date() }
                if let since = watchingIdleSince,
                   Date().timeIntervalSince(since) >= watchingDeescalateHold {
                    deescalateWatchingGPSIfNeeded()
                }
            }
        } else {
            watchingIdleSince = nil
        }
    }

    /// Publishes a thinned polyline for the map at a low rate so SwiftUI/MapKit
    /// are not invalidated on every GPS fix.
    private func publishLiveRouteIfNeeded(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveRoutePublish) >= liveRoutePublishInterval else {
            return
        }
        lastLiveRoutePublish = now
        let display = TripTrackingLogic.downsample(recordedRoute, maximum: liveRouteDisplayMax)
        guard display != liveRoute else { return }
        liveRoute = display
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
            routePointCount: recordedRoute.count,
            isPaused: isPaused,
            source: source,
            vehicleId: vehicleId ?? "",
            vehicleName: vehicleName
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
        let distanceKm = snapshot?.distanceKm ?? 0
        let durationSec = snapshot?.durationSec ?? 0
        let meaningfulDelta =
            lastWidgetWriteState != state
            || abs(distanceKm - lastWidgetWriteDistanceKm) >= 0.1
            || abs(durationSec - lastWidgetWriteDurationSec) >= 5

        // Previously wrote + synchronized UserDefaults on every 1 Hz tick while
        // recording. Only persist on phase/pause changes, distance/time deltas,
        // forced sync, or the 30s widget timeline reload cadence.
        guard force || shouldReload || meaningfulDelta else { return }

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

        lastWidgetWriteState = state
        lastWidgetWriteDistanceKm = distanceKm
        lastWidgetWriteDurationSec = durationSec
        if shouldReload {
            lastWidgetTrackingUpdate = now
        }
    }

    private func updateLiveActivity(force: Bool) {
        guard let snapshot else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveActivityUpdate) >= 4.0 else { return }
        lastLiveActivityUpdate = now
        let mood = DriveMoodLogic.ingest(
            state: &driveMoodState,
            speedKmh: snapshot.currentSpeedKmh,
            at: now,
            isPaused: snapshot.isPaused,
            baselineL100: baselineL100
        )
        TripLiveActivityController.shared.update(
            distanceKm: snapshot.distanceKm,
            durationSec: snapshot.durationSec,
            currentSpeedKmh: snapshot.currentSpeedKmh,
            maxSpeedKmh: snapshot.maxSpeedKmh,
            isPaused: snapshot.isPaused,
            mood: mood
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
            Line(title: "Drive complete! 🎉", body: "\(stats). Saved to My Drives whenever you're ready."),
            Line(title: "Look at you go!", body: "\(stats). Nice one — review it in My Drives when you have a sec."),
            Line(title: "You did it!", body: "\(stats). It's in My Drives. No rush."),
            Line(title: "Nailed it!", body: "\(stats). Logged and waiting quietly in My Drives."),
        ])
    }

    static func pendingReview(count: Int) -> Line {
        if count == 1 {
            return pick([
                Line(title: "One drive still open", body: "Whenever you're free, confirm it in My Drives."),
                Line(title: "Quick reminder", body: "There's a drive in My Drives ready when you are."),
            ])
        }
        return pick([
            Line(title: "\(count) drives to confirm", body: "No rush — just a heads-up they're waiting in My Drives."),
            Line(title: "A few drives piled up", body: "\(count) in My Drives. Confirm when you get a chance."),
            Line(title: "My Drives needs a minute", body: "\(count) unconfirmed drives. Tap when you're ready."),
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
