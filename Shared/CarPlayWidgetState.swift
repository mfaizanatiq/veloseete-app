import Foundation
import WidgetKit

enum CarPlayWidgetTrackingState: String, Codable {
    case idle
    case watching
    case recording
    case paused
    case confirming
}

struct CarPlayWidgetRoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct CarPlayWidgetSnapshot: Codable, Equatable {
    var vehicleID: String?
    var vehicleName: String
    var odometerKm: Double
    var trackingState: CarPlayWidgetTrackingState
    var autoTrackingEnabled: Bool
    var tripStartedAt: Date?
    var distanceKm: Double
    var durationSec: Double
    var currentSpeedKmh: Double
    var lastFuelVolume: Double?
    var lastFuelTotalCost: Double?
    var lastFuelCurrency: String?
    var lastFuelDate: Date?
    var totalDistanceKm: Double
    var efficiencyLPer100Km: Double?
    var monthlySpend: Double
    var currency: String
    var recentRoute: [CarPlayWidgetRoutePoint]
    var pendingRefuelAt: Date?
    var updatedAt: Date

    static let empty = CarPlayWidgetSnapshot(
        vehicleID: nil,
        vehicleName: "Veloseete",
        odometerKm: 0,
        trackingState: .idle,
        autoTrackingEnabled: false,
        tripStartedAt: nil,
        distanceKm: 0,
        durationSec: 0,
        currentSpeedKmh: 0,
        lastFuelVolume: nil,
        lastFuelTotalCost: nil,
        lastFuelCurrency: nil,
        lastFuelDate: nil,
        totalDistanceKm: 0,
        efficiencyLPer100Km: nil,
        monthlySpend: 0,
        currency: "QAR",
        recentRoute: [],
        pendingRefuelAt: nil,
        updatedAt: .distantPast
    )
}

struct CarPlayRefuelDraft: Codable, Identifiable {
    let id: UUID
    let vehicleID: String
    let vehicleName: String
    let createdAt: Date
    let estimatedOdometer: Double
}

enum CarPlayWidgetStateStore {
    static let appGroupID = "group.com.veloseete.app"
    static let widgetKind = "VeloseeteCarPlayWidget"
    static let refuelDraftCreated = Notification.Name("CarPlayRefuelDraftCreated")

    private static let snapshotKey = "carPlay.widgetSnapshot"
    private static let refuelDraftKey = "carPlay.pendingRefuelDraft"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func loadSnapshot() -> CarPlayWidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(CarPlayWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func updateVehicle(
        id: String,
        name: String,
        odometerKm: Double,
        autoTrackingEnabled: Bool,
        lastFuelVolume: Double?,
        lastFuelTotalCost: Double?,
        lastFuelCurrency: String?,
        lastFuelDate: Date?,
        totalDistanceKm: Double,
        efficiencyLPer100Km: Double?,
        monthlySpend: Double,
        currency: String,
        recentRoute: [CarPlayWidgetRoutePoint]
    ) {
        var snapshot = loadSnapshot()
        snapshot.vehicleID = id
        snapshot.vehicleName = name
        snapshot.odometerKm = odometerKm
        snapshot.autoTrackingEnabled = autoTrackingEnabled
        snapshot.lastFuelVolume = lastFuelVolume
        snapshot.lastFuelTotalCost = lastFuelTotalCost
        snapshot.lastFuelCurrency = lastFuelCurrency
        snapshot.lastFuelDate = lastFuelDate
        snapshot.totalDistanceKm = totalDistanceKm
        snapshot.efficiencyLPer100Km = efficiencyLPer100Km
        snapshot.monthlySpend = monthlySpend
        snapshot.currency = currency
        snapshot.recentRoute = recentRoute
        save(snapshot, reloadTimeline: true)
    }

    static func updateTracking(
        state: CarPlayWidgetTrackingState,
        autoTrackingEnabled: Bool,
        startedAt: Date? = nil,
        distanceKm: Double = 0,
        durationSec: Double = 0,
        currentSpeedKmh: Double = 0,
        reloadTimeline: Bool
    ) {
        var snapshot = loadSnapshot()
        snapshot.trackingState = state
        snapshot.autoTrackingEnabled = autoTrackingEnabled
        snapshot.tripStartedAt = startedAt
        snapshot.distanceKm = distanceKm
        snapshot.durationSec = durationSec
        snapshot.currentSpeedKmh = currentSpeedKmh
        save(snapshot, reloadTimeline: reloadTimeline)
    }

    static func clearUserData() {
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: refuelDraftKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    @discardableResult
    static func createRefuelDraft() -> CarPlayRefuelDraft? {
        let snapshot = loadSnapshot()
        guard let vehicleID = snapshot.vehicleID else { return nil }
        return createRefuelDraft(
            vehicleID: vehicleID,
            vehicleName: snapshot.vehicleName,
            estimatedOdometer: snapshot.odometerKm + snapshot.distanceKm
        )
    }

    @discardableResult
    static func createRefuelDraft(
        vehicleID: String,
        vehicleName: String,
        estimatedOdometer: Double
    ) -> CarPlayRefuelDraft? {
        let createdAt = Date()
        let draft = CarPlayRefuelDraft(
            id: UUID(),
            vehicleID: vehicleID,
            vehicleName: vehicleName,
            createdAt: createdAt,
            estimatedOdometer: estimatedOdometer
        )
        guard let data = try? JSONEncoder().encode(draft) else { return nil }
        defaults.set(data, forKey: refuelDraftKey)
        var snapshot = loadSnapshot()
        snapshot.pendingRefuelAt = createdAt
        save(snapshot, reloadTimeline: true)
        NotificationCenter.default.post(name: refuelDraftCreated, object: nil)
        return draft
    }

    static func consumePendingRefuelDraft() -> CarPlayRefuelDraft? {
        guard let data = defaults.data(forKey: refuelDraftKey),
              let draft = try? JSONDecoder().decode(CarPlayRefuelDraft.self, from: data) else {
            return nil
        }
        defaults.removeObject(forKey: refuelDraftKey)
        var snapshot = loadSnapshot()
        snapshot.pendingRefuelAt = nil
        save(snapshot, reloadTimeline: true)
        return draft
    }

    private static func save(_ snapshot: CarPlayWidgetSnapshot, reloadTimeline: Bool) {
        var updated = snapshot
        updated.updatedAt = Date()
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: snapshotKey)
        if reloadTimeline {
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }
}
