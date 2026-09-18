import Foundation

/// Persists per-vehicle learning state in the App Group (widgets share the same scale).
@MainActor
final class VehicleLearningStore {
    static let shared = VehicleLearningStore()

    private let defaults: UserDefaults
    private let prefix = "veloseete.vehicleLearning."
    private var memory: [String: VehicleLearningState] = [:]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: CarPlayWidgetStateStore.appGroupID)
            ?? .standard
    }

    func state(for vehicleId: String) -> VehicleLearningState {
        if let cached = memory[vehicleId] { return cached }
        let key = prefix + vehicleId
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(VehicleLearningState.self, from: data) {
            memory[vehicleId] = decoded
            return decoded
        }
        return .default
    }

    func save(_ state: VehicleLearningState, for vehicleId: String) {
        memory[vehicleId] = state
        let key = prefix + vehicleId
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }

    func reset(vehicleId: String) {
        memory.removeValue(forKey: vehicleId)
        defaults.removeObject(forKey: prefix + vehicleId)
    }

    /// Apply a refill observation using GPS tracked since the previous anchor.
    @discardableResult
    func learnFromRefill(
        vehicleId: String,
        previousDashKm: Double,
        newDashKm: Double,
        gpsTrackedKm: Double,
        actualRangeKm: Double?,
        fuelLiters: Double,
        isFullTankCycle: Bool,
        predictedBudgetKm: Double?,
        now: Date = Date()
    ) -> VehicleLearningState {
        var state = state(for: vehicleId)

        let scaleResult = VehicleLearningModel.observeScale(
            .init(
                previousDashKm: previousDashKm,
                newDashKm: newDashKm,
                gpsTrackedKm: gpsTrackedKm
            ),
            state: state,
            now: now
        )
        switch scaleResult {
        case .applied(_, let next):
            state = next
        case .rejected(_, let same):
            state = same
        }

        if let actualRangeKm {
            state = VehicleLearningModel.observeRange(
                .init(
                    actualRangeKm: actualRangeKm,
                    fuelLiters: fuelLiters,
                    isFullTankCycle: isFullTankCycle,
                    predictedBudgetKm: predictedBudgetKm
                ),
                state: state,
                now: now
            )
        }

        save(state, for: vehicleId)
        return state
    }
}
