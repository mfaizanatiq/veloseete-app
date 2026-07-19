import Foundation
import Combine

struct OdometerEstimate: Equatable {
    var verifiedKm: Double
    var verifiedAt: Date
    var verifiedSource: String
    var trackedSinceKm: Double

    var estimatedKm: Double { verifiedKm + trackedSinceKm }
}

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published private(set) var userDocument: UserDocument?
    @Published private(set) var vehicles: [Vehicle] = []
    @Published private(set) var fuelLogs: [FuelLog] = []
    @Published private(set) var serviceLogs: [ServiceLog] = []
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoaded = false
    @Published var loadError: String?
    @Published var manufacturerStandard: Double?
    /// Soft warnings (e.g. one collection failed) — data may still be partial.
    @Published var loadWarnings: [String] = []

    private init() {}

    var currentVehicle: Vehicle? {
        if let id = userDocument?.currentVehicleId,
           let match = vehicles.first(where: { $0.id == id }) {
            return match
        }
        return vehicles.first
    }

    var defaultDistanceUnit: String {
        userDocument?.profile.defaultDistanceUnit ?? "km"
    }

    var userName: String {
        userDocument?.profile.userName ?? AuthService.shared.user?.displayName ?? ""
    }

    var fuelLogsForCurrentVehicle: [FuelLog] {
        guard let id = currentVehicle?.id else { return [] }
        return fuelLogs.filter { $0.vehicleId == id }
    }

    /// Physical fuel/service readings are anchors. GPS trips only advance an estimate.
    func odometerEstimate(vehicleId: String, through date: Date = Date()) -> OdometerEstimate? {
        guard let vehicle = vehicles.first(where: { $0.id == vehicleId }) else { return nil }

        let fuelAnchors = fuelLogs
            .filter { $0.vehicleId == vehicleId && $0.timestamp <= date }
            .map { ($0.timestamp, $0.odometerReading, "Fuel entry") }
        let serviceAnchors = serviceLogs
            .filter { $0.vehicleId == vehicleId && $0.timestamp <= date }
            .map { ($0.timestamp, $0.odometerReading, "Service entry") }
        let anchor = (fuelAnchors + serviceAnchors).max { $0.0 < $1.0 }
        let verifiedAt = anchor?.0 ?? vehicle.createdAt
        let verifiedKm = anchor?.1 ?? vehicle.currentOdometer
        let source = anchor?.2 ?? "Vehicle reading"
        let tracked = trips
            .filter { $0.vehicleId == vehicleId && $0.endedAt > verifiedAt && $0.endedAt <= date }
            .reduce(0) { $0 + $1.distanceKm }

        return OdometerEstimate(
            verifiedKm: verifiedKm,
            verifiedAt: verifiedAt,
            verifiedSource: source,
            trackedSinceKm: tracked
        )
    }

    func loadAll(userId: String) async {
        isLoading = true
        loadError = nil
        loadWarnings = []
        defer {
            isLoading = false
            isLoaded = true
        }

        print("[DataStore] Loading for user \(userId)")

        // Load independently so one failed collection doesn't wipe everything.
        do {
            userDocument = try await FirestoreRepository.shared.fetchUser(userId: userId)
        } catch {
            loadWarnings.append("Profile: \(error.localizedDescription)")
            print("[DataStore] user fetch failed: \(error)")
        }

        do {
            vehicles = try await FirestoreRepository.shared.fetchVehicles(userId: userId)
            print("[DataStore] vehicles: \(vehicles.count)")
        } catch {
            loadWarnings.append("Vehicles: \(error.localizedDescription)")
            print("[DataStore] vehicles fetch failed: \(error)")
        }

        do {
            fuelLogs = try await FirestoreRepository.shared.fetchFuelLogs(userId: userId)
            print("[DataStore] fuelLogs: \(fuelLogs.count)")
        } catch {
            loadWarnings.append("Fuel logs: \(error.localizedDescription)")
            print("[DataStore] fuelLogs fetch failed: \(error)")
        }

        do {
            serviceLogs = try await FirestoreRepository.shared.fetchServiceLogs(userId: userId)
            print("[DataStore] serviceLogs: \(serviceLogs.count)")
        } catch {
            // Soft — don't surface as red banner; fuel is primary
            print("[DataStore] serviceLogs fetch failed: \(error)")
            serviceLogs = []
        }

        do {
            trips = try await FirestoreRepository.shared.fetchTrips(userId: userId)
            print("[DataStore] trips: \(trips.count)")
        } catch {
            print("[DataStore] trips fetch failed: \(error)")
            trips = []
        }

        if vehicles.isEmpty && fuelLogs.isEmpty && !loadWarnings.isEmpty {
            loadError = loadWarnings.joined(separator: "\n")
        }

        // If currentVehicleId is stale, keep showing first vehicle (getter already falls back).
        if let vehicle = currentVehicle {
            await refreshManufacturerStandard(for: vehicle)
        }
    }

    func refreshManufacturerStandard(for vehicle: Vehicle) async {
        do {
            manufacturerStandard = try await FirestoreRepository.shared.fetchManufacturerStandard(
                make: vehicle.make,
                model: vehicle.model
            )
        } catch {
            manufacturerStandard = nil
        }
    }

    // MARK: - Writes

    func updateProfile(userName: String, currency: String, distanceUnit: String) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        try await FirestoreRepository.shared.updateUserProfile(
            userId: userId,
            userName: userName,
            currency: currency,
            distanceUnit: distanceUnit
        )

        if var document = userDocument {
            document.profile.userName = userName
            document.profile.defaultCurrency = currency
            document.profile.defaultDistanceUnit = distanceUnit
            userDocument = document
        }

        let change = AuthService.shared.user?.createProfileChangeRequest()
        change?.displayName = userName
        try await change?.commitChanges()
    }

    func addVehicle(
        nickname: String,
        make: String,
        model: String,
        fuelType: String,
        currentOdometer: Double,
        currency: String,
        icon: String?,
        fuelTankCapacity: Double?
    ) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let input = FirestoreRepository.NewVehicleInput(
            nickname: nickname,
            make: make,
            model: model,
            fuelType: fuelType,
            currentOdometer: currentOdometer,
            currency: currency,
            icon: icon,
            fuelTankCapacity: fuelTankCapacity
        )

        let id = try await FirestoreRepository.shared.addVehicle(userId: userId, input: input)

        let vehicle = Vehicle(
            id: id,
            nickname: nickname,
            make: make,
            model: model,
            fuelType: fuelType,
            currentOdometer: currentOdometer,
            fuelTankCapacity: fuelTankCapacity,
            currency: currency,
            icon: icon,
            createdAt: Date()
        )
        vehicles.insert(vehicle, at: 0)

        let shouldSetCurrent = userDocument?.currentVehicleId == nil
        try await FirestoreRepository.shared.updateUserProfile(
            userId: userId,
            currency: currency,
            currentVehicleId: shouldSetCurrent ? id : nil
        )

        if var doc = userDocument {
            doc.profile.defaultCurrency = currency
            if shouldSetCurrent {
                doc.currentVehicleId = id
            }
            userDocument = doc
        } else {
            userDocument = UserDocument(
                userId: userId,
                profile: UserProfile(userName: userName, defaultCurrency: currency, defaultDistanceUnit: "km"),
                currentVehicleId: id
            )
        }

        await refreshManufacturerStandard(for: vehicle)
    }

    func selectVehicle(_ vehicleId: String) async throws {
        guard let userId = AuthService.shared.userId,
              let vehicle = vehicles.first(where: { $0.id == vehicleId }) else {
            throw NSError(domain: "Veloseete", code: 404, userInfo: [NSLocalizedDescriptionKey: "Vehicle not found"])
        }

        try await FirestoreRepository.shared.updateUserProfile(
            userId: userId,
            currentVehicleId: vehicleId
        )
        if var document = userDocument {
            document.currentVehicleId = vehicleId
            userDocument = document
        }
        await refreshManufacturerStandard(for: vehicle)
    }

    func updateVehicle(_ vehicle: Vehicle) async throws {
        try await FirestoreRepository.shared.updateVehicle(vehicle: vehicle)
        vehicles = vehicles.map { $0.id == vehicle.id ? vehicle : $0 }
        if currentVehicle?.id == vehicle.id {
            await refreshManufacturerStandard(for: vehicle)
        }
    }

    func addFuelLog(
        vehicleId: String,
        odometerReading: Double,
        fuelVolume: Double,
        totalCost: Double,
        currency: String,
        isFullTank: Bool,
        timestamp: Date
    ) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let pricePerUnit = fuelVolume > 0 ? totalCost / fuelVolume : 0
        let input = FirestoreRepository.NewFuelLogInput(
            vehicleId: vehicleId,
            odometerReading: odometerReading,
            fuelVolume: fuelVolume,
            pricePerUnit: pricePerUnit,
            totalCost: totalCost,
            currency: currency,
            isFullTank: isFullTank,
            timestamp: timestamp
        )

        let id = try await FirestoreRepository.shared.addFuelLog(userId: userId, input: input)
        try await FirestoreRepository.shared.updateVehicleOdometer(vehicleId: vehicleId, odometer: odometerReading)

        let log = FuelLog(
            id: id,
            vehicleId: vehicleId,
            timestamp: timestamp,
            odometerReading: odometerReading,
            fuelVolume: fuelVolume,
            pricePerUnit: pricePerUnit,
            totalCost: totalCost,
            currency: currency,
            isFullTank: isFullTank
        )
        fuelLogs.insert(log, at: 0)
        vehicles = vehicles.map { v in
            guard v.id == vehicleId else { return v }
            var updated = v
            updated.currentOdometer = odometerReading
            return updated
        }
    }

    func saveServiceLog(id: String?, input: FirestoreRepository.ServiceLogInput) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let resolvedId: String
        if let id {
            try await FirestoreRepository.shared.updateServiceLog(serviceId: id, userId: userId, input: input)
            resolvedId = id
        } else {
            resolvedId = try await FirestoreRepository.shared.addServiceLog(userId: userId, input: input)
        }
        let saved = ServiceLog(
            id: resolvedId,
            vehicleId: input.vehicleId,
            timestamp: input.timestamp,
            odometerReading: input.odometerReading,
            serviceType: input.serviceType,
            description: input.description,
            cost: input.cost,
            currency: input.currency,
            nextServiceOdometer: input.nextServiceOdometer,
            nextServiceDate: input.nextServiceDate
        )
        serviceLogs.removeAll { $0.id == resolvedId }
        serviceLogs.append(saved)
        serviceLogs.sort { $0.timestamp > $1.timestamp }
    }

    func deleteServiceLog(_ log: ServiceLog) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        try await FirestoreRepository.shared.deleteServiceLog(serviceId: log.id, userId: userId)
        serviceLogs.removeAll { $0.id == log.id }
    }

    @discardableResult
    func saveTrip(_ pending: PendingTripSave, odometer: Double, applyOdometer: Bool) async throws -> Trip {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let input = FirestoreRepository.NewTripInput(
            vehicleId: pending.vehicleId,
            startedAt: pending.startedAt,
            endedAt: pending.endedAt,
            distanceKm: pending.distanceKm,
            durationSec: pending.durationSec,
            avgSpeedKmh: pending.avgSpeedKmh,
            maxSpeedKmh: pending.maxSpeedKmh,
            startCoordinate: pending.startCoordinate,
            endCoordinate: pending.endCoordinate,
            route: pending.route,
            source: pending.source
        )

        let id = try await FirestoreRepository.shared.createTrip(userId: userId, input: input)

        if applyOdometer {
            try await FirestoreRepository.shared.updateVehicleOdometer(
                vehicleId: pending.vehicleId,
                odometer: odometer
            )
            vehicles = vehicles.map { v in
                guard v.id == pending.vehicleId else { return v }
                var updated = v
                updated.currentOdometer = odometer
                return updated
            }
        }

        let trip = Trip(
            id: id,
            vehicleId: pending.vehicleId,
            startedAt: pending.startedAt,
            endedAt: pending.endedAt,
            distanceKm: pending.distanceKm,
            durationSec: pending.durationSec,
            avgSpeedKmh: pending.avgSpeedKmh,
            maxSpeedKmh: pending.maxSpeedKmh,
            startCoordinate: pending.startCoordinate,
            endCoordinate: pending.endCoordinate,
            route: pending.route,
            source: pending.source
        )
        trips.insert(trip, at: 0)
        return trip
    }

    func clear() {
        userDocument = nil
        vehicles = []
        fuelLogs = []
        serviceLogs = []
        trips = []
        manufacturerStandard = nil
        isLoaded = false
        loadError = nil
        loadWarnings = []
    }
}
