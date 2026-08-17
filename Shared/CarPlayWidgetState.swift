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
    var estimatedOdometerKm: Double?
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
    var lastStationName: String?
    var totalDistanceKm: Double
    var efficiencyLPer100Km: Double?
    var monthlySpend: Double
    var currency: String
    /// `"L"` or `"gal"` for the active vehicle. Volumes remain stored as litres.
    var fuelVolumeUnit: String
    var recentRoute: [CarPlayWidgetRoutePoint]
    var pendingRefuelAt: Date?
    var pendingTripCount: Int
    var updatedAt: Date

    static let empty = CarPlayWidgetSnapshot(
        vehicleID: nil,
        vehicleName: "Veloseete",
        odometerKm: 0,
        estimatedOdometerKm: nil,
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
        lastStationName: nil,
        totalDistanceKm: 0,
        efficiencyLPer100Km: nil,
        monthlySpend: 0,
        currency: "QAR",
        fuelVolumeUnit: "L",
        recentRoute: [],
        pendingRefuelAt: nil,
        pendingTripCount: 0,
        updatedAt: .distantPast
    )

    var daysSinceLastFuel: Int? {
        guard let lastFuelDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: lastFuelDate, to: Date()).day ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case vehicleID, vehicleName, odometerKm, estimatedOdometerKm
        case trackingState, autoTrackingEnabled, tripStartedAt
        case distanceKm, durationSec, currentSpeedKmh
        case lastFuelVolume, lastFuelTotalCost, lastFuelCurrency, lastFuelDate, lastStationName
        case totalDistanceKm, efficiencyLPer100Km, monthlySpend, currency, fuelVolumeUnit
        case recentRoute, pendingRefuelAt, pendingTripCount, updatedAt
    }

    init(
        vehicleID: String?,
        vehicleName: String,
        odometerKm: Double,
        estimatedOdometerKm: Double?,
        trackingState: CarPlayWidgetTrackingState,
        autoTrackingEnabled: Bool,
        tripStartedAt: Date?,
        distanceKm: Double,
        durationSec: Double,
        currentSpeedKmh: Double,
        lastFuelVolume: Double?,
        lastFuelTotalCost: Double?,
        lastFuelCurrency: String?,
        lastFuelDate: Date?,
        lastStationName: String?,
        totalDistanceKm: Double,
        efficiencyLPer100Km: Double?,
        monthlySpend: Double,
        currency: String,
        fuelVolumeUnit: String,
        recentRoute: [CarPlayWidgetRoutePoint],
        pendingRefuelAt: Date?,
        pendingTripCount: Int,
        updatedAt: Date
    ) {
        self.vehicleID = vehicleID
        self.vehicleName = vehicleName
        self.odometerKm = odometerKm
        self.estimatedOdometerKm = estimatedOdometerKm
        self.trackingState = trackingState
        self.autoTrackingEnabled = autoTrackingEnabled
        self.tripStartedAt = tripStartedAt
        self.distanceKm = distanceKm
        self.durationSec = durationSec
        self.currentSpeedKmh = currentSpeedKmh
        self.lastFuelVolume = lastFuelVolume
        self.lastFuelTotalCost = lastFuelTotalCost
        self.lastFuelCurrency = lastFuelCurrency
        self.lastFuelDate = lastFuelDate
        self.lastStationName = lastStationName
        self.totalDistanceKm = totalDistanceKm
        self.efficiencyLPer100Km = efficiencyLPer100Km
        self.monthlySpend = monthlySpend
        self.currency = currency
        self.fuelVolumeUnit = fuelVolumeUnit
        self.recentRoute = recentRoute
        self.pendingRefuelAt = pendingRefuelAt
        self.pendingTripCount = pendingTripCount
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vehicleID = try c.decodeIfPresent(String.self, forKey: .vehicleID)
        vehicleName = try c.decodeIfPresent(String.self, forKey: .vehicleName) ?? "Veloseete"
        odometerKm = try c.decodeIfPresent(Double.self, forKey: .odometerKm) ?? 0
        estimatedOdometerKm = try c.decodeIfPresent(Double.self, forKey: .estimatedOdometerKm)
        trackingState = try c.decodeIfPresent(CarPlayWidgetTrackingState.self, forKey: .trackingState) ?? .idle
        autoTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoTrackingEnabled) ?? false
        tripStartedAt = try c.decodeIfPresent(Date.self, forKey: .tripStartedAt)
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm) ?? 0
        durationSec = try c.decodeIfPresent(Double.self, forKey: .durationSec) ?? 0
        currentSpeedKmh = try c.decodeIfPresent(Double.self, forKey: .currentSpeedKmh) ?? 0
        lastFuelVolume = try c.decodeIfPresent(Double.self, forKey: .lastFuelVolume)
        lastFuelTotalCost = try c.decodeIfPresent(Double.self, forKey: .lastFuelTotalCost)
        lastFuelCurrency = try c.decodeIfPresent(String.self, forKey: .lastFuelCurrency)
        lastFuelDate = try c.decodeIfPresent(Date.self, forKey: .lastFuelDate)
        lastStationName = try c.decodeIfPresent(String.self, forKey: .lastStationName)
        totalDistanceKm = try c.decodeIfPresent(Double.self, forKey: .totalDistanceKm) ?? 0
        efficiencyLPer100Km = try c.decodeIfPresent(Double.self, forKey: .efficiencyLPer100Km)
        monthlySpend = try c.decodeIfPresent(Double.self, forKey: .monthlySpend) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "QAR"
        fuelVolumeUnit = try c.decodeIfPresent(String.self, forKey: .fuelVolumeUnit) ?? "L"
        recentRoute = try c.decodeIfPresent([CarPlayWidgetRoutePoint].self, forKey: .recentRoute) ?? []
        pendingRefuelAt = try c.decodeIfPresent(Date.self, forKey: .pendingRefuelAt)
        pendingTripCount = try c.decodeIfPresent(Int.self, forKey: .pendingTripCount) ?? 0
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

struct CarPlayRefuelDraft: Codable, Identifiable {
    let id: UUID
    let vehicleID: String
    let vehicleName: String
    let createdAt: Date
    let estimatedOdometer: Double
}

enum CarPlayWidgetStateStore {
    static let appGroupID = "group.com.veloseete.shared"
    static let widgetKind = "VeloseeteCarPlayWidget"
    static let fuelWidgetKind = "VeloseeteFuelPulseWidget"
    static let driveWidgetKind = "VeloseeteLiveDriveWidget"
    static let reviewWidgetKind = "VeloseeteReviewQueueWidget"
    static let refuelDraftCreated = Notification.Name("CarPlayRefuelDraftCreated")

    static var allWidgetKinds: [String] {
        [widgetKind, fuelWidgetKind, driveWidgetKind, reviewWidgetKind]
    }

    private static let snapshotKey = "carPlay.widgetSnapshot"
    private static let refuelDraftKey = "carPlay.pendingRefuelDraft"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// Shared container for app ↔ widgets. Falls back only if App Groups aren't entitled.
    private static var defaults: UserDefaults {
        if let suite = UserDefaults(suiteName: appGroupID) {
            return suite
        }
        print("[WidgetStore] App Group \(appGroupID) unavailable — widgets won't sync")
        return .standard
    }

    static var isAppGroupAvailable: Bool {
        UserDefaults(suiteName: appGroupID) != nil
    }

    static func loadSnapshot() -> CarPlayWidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey) else { return .empty }
        if let snapshot = try? decoder.decode(CarPlayWidgetSnapshot.self, from: data) {
            return snapshot
        }
        // Migrate older deferred-date payloads written before secondsSince1970.
        if let snapshot = try? JSONDecoder().decode(CarPlayWidgetSnapshot.self, from: data) {
            save(snapshot, reloadTimeline: false)
            return snapshot
        }
        print("[WidgetStore] snapshot decode failed")
        return .empty
    }

    static func updateVehicle(
        id: String,
        name: String,
        odometerKm: Double,
        estimatedOdometerKm: Double?,
        autoTrackingEnabled: Bool,
        lastFuelVolume: Double?,
        lastFuelTotalCost: Double?,
        lastFuelCurrency: String?,
        lastFuelDate: Date?,
        lastStationName: String?,
        totalDistanceKm: Double,
        efficiencyLPer100Km: Double?,
        monthlySpend: Double,
        currency: String,
        fuelVolumeUnit: String,
        recentRoute: [CarPlayWidgetRoutePoint],
        pendingTripCount: Int
    ) {
        var snapshot = loadSnapshot()
        snapshot.vehicleID = id
        snapshot.vehicleName = name
        snapshot.odometerKm = odometerKm
        snapshot.estimatedOdometerKm = estimatedOdometerKm
        snapshot.autoTrackingEnabled = autoTrackingEnabled
        snapshot.lastFuelVolume = lastFuelVolume
        snapshot.lastFuelTotalCost = lastFuelTotalCost
        snapshot.lastFuelCurrency = lastFuelCurrency
        snapshot.lastFuelDate = lastFuelDate
        snapshot.lastStationName = lastStationName
        snapshot.totalDistanceKm = totalDistanceKm
        snapshot.efficiencyLPer100Km = efficiencyLPer100Km
        snapshot.monthlySpend = monthlySpend
        snapshot.currency = currency
        snapshot.fuelVolumeUnit = fuelVolumeUnit
        snapshot.recentRoute = recentRoute
        snapshot.pendingTripCount = pendingTripCount
        save(snapshot, reloadTimeline: true)
    }

    static func updatePendingTripCount(_ count: Int) {
        var snapshot = loadSnapshot()
        guard snapshot.pendingTripCount != count else { return }
        snapshot.pendingTripCount = count
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
        reloadAllTimelines()
    }

    static func reloadAllTimelines() {
        for kind in allWidgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    @discardableResult
    static func createRefuelDraft() -> CarPlayRefuelDraft? {
        let snapshot = loadSnapshot()
        guard let vehicleID = snapshot.vehicleID else { return nil }
        return createRefuelDraft(
            vehicleID: vehicleID,
            vehicleName: snapshot.vehicleName,
            estimatedOdometer: (snapshot.estimatedOdometerKm ?? snapshot.odometerKm) + snapshot.distanceKm
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
        guard let data = try? encoder.encode(draft) else { return nil }
        defaults.set(data, forKey: refuelDraftKey)
        var snapshot = loadSnapshot()
        snapshot.pendingRefuelAt = createdAt
        save(snapshot, reloadTimeline: true)
        NotificationCenter.default.post(name: refuelDraftCreated, object: nil)
        return draft
    }

    static func consumePendingRefuelDraft() -> CarPlayRefuelDraft? {
        guard let data = defaults.data(forKey: refuelDraftKey) else { return nil }
        let draft = (try? decoder.decode(CarPlayRefuelDraft.self, from: data))
            ?? (try? JSONDecoder().decode(CarPlayRefuelDraft.self, from: data))
        guard let draft else { return nil }
        defaults.removeObject(forKey: refuelDraftKey)
        var snapshot = loadSnapshot()
        snapshot.pendingRefuelAt = nil
        save(snapshot, reloadTimeline: true)
        return draft
    }

    private static func save(_ snapshot: CarPlayWidgetSnapshot, reloadTimeline: Bool) {
        var updated = snapshot
        updated.updatedAt = Date()
        guard let data = try? encoder.encode(updated) else {
            print("[WidgetStore] snapshot encode failed")
            return
        }
        // UserDefaults already flushes asynchronously — synchronize() was
        // forcing main-thread I/O on every drive tick.
        defaults.set(data, forKey: snapshotKey)
        if reloadTimeline {
            reloadAllTimelines()
        }
    }
}
