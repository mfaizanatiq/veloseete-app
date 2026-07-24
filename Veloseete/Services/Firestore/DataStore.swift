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
    /// Active garage vehicles only (not archived).
    @Published private(set) var vehicles: [Vehicle] = []
    /// Soft-removed cars — history stays attached to these IDs.
    @Published private(set) var archivedVehicles: [Vehicle] = []
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

    var activeVehicleIds: Set<String> { Set(vehicles.map(\.id)) }

    /// Trips for active cars only — archived vehicles keep their own history separately.
    var tripsForActiveVehicles: [Trip] {
        let ids = activeVehicleIds
        return trips.filter { ids.contains($0.vehicleId) }
    }

    var fuelLogsForActiveVehicles: [FuelLog] {
        let ids = activeVehicleIds
        return fuelLogs.filter { ids.contains($0.vehicleId) }
    }

    var serviceLogsForActiveVehicles: [ServiceLog] {
        let ids = activeVehicleIds
        return serviceLogs.filter { ids.contains($0.vehicleId) }
    }

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
        // Hard timeouts keep VPN / dead routes from freezing launch on a black loader.
        do {
            userDocument = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchUser(userId: userId)
            }
        } catch {
            loadWarnings.append("Profile: \(error.localizedDescription)")
            print("[DataStore] user fetch failed: \(error)")
        }

        do {
            let allVehicles = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchVehicles(userId: userId)
            }
            applyVehicleLists(allVehicles)
            print("[DataStore] vehicles: \(vehicles.count) active, \(archivedVehicles.count) archived")
        } catch {
            loadWarnings.append("Vehicles: \(error.localizedDescription)")
            print("[DataStore] vehicles fetch failed: \(error)")
        }

        do {
            fuelLogs = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchFuelLogs(userId: userId)
            }
            print("[DataStore] fuelLogs: \(fuelLogs.count)")
        } catch {
            loadWarnings.append("Fuel logs: \(error.localizedDescription)")
            print("[DataStore] fuelLogs fetch failed: \(error)")
        }

        do {
            serviceLogs = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchServiceLogs(userId: userId)
            }
            print("[DataStore] serviceLogs: \(serviceLogs.count)")
        } catch {
            // Soft — don't surface as red banner; fuel is primary
            print("[DataStore] serviceLogs fetch failed: \(error)")
            serviceLogs = []
        }

        do {
            trips = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchTrips(userId: userId)
            }
            print("[DataStore] trips: \(trips.count)")
        } catch {
            print("[DataStore] trips fetch failed: \(error)")
            trips = []
        }

        if vehicles.isEmpty && fuelLogs.isEmpty && !loadWarnings.isEmpty {
            loadError = loadWarnings.joined(separator: "\n")
        }

        // If currentVehicleId points at an archived/missing car, point at an active one.
        await reconcileCurrentVehicleIfNeeded(userId: userId)

        if let vehicle = currentVehicle {
            await refreshManufacturerStandard(for: vehicle)
        }
        publishCarPlayWidgetState()
    }

    private func fetchWithTimeout<T: Sendable>(
        seconds: TimeInterval = 12,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await AsyncTimeout.run(seconds: seconds, operation: operation)
    }

    private func applyVehicleLists(_ all: [Vehicle]) {
        vehicles = all.filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
        archivedVehicles = all.filter(\.isArchived).sorted {
            ($0.archivedAt ?? $0.createdAt) > ($1.archivedAt ?? $1.createdAt)
        }
    }

    private func reconcileCurrentVehicleIfNeeded(userId: String) async {
        let currentId = userDocument?.currentVehicleId
        let currentStillActive = currentId.map { id in vehicles.contains(where: { $0.id == id }) } ?? false
        guard !currentStillActive else { return }

        let nextId = vehicles.first?.id
        do {
            try await FirestoreRepository.shared.updateUserProfile(
                userId: userId,
                currentVehicleId: nextId,
                clearCurrentVehicle: nextId == nil
            )
            if var document = userDocument {
                document.currentVehicleId = nextId
                userDocument = document
            }
        } catch {
            print("[DataStore] could not reconcile currentVehicleId: \(error)")
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
            createdAt: Date(),
            isArchived: false,
            archivedAt: nil
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
        publishCarPlayWidgetState()
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
        publishCarPlayWidgetState()
    }

    func updateVehicle(_ vehicle: Vehicle) async throws {
        try await FirestoreRepository.shared.updateVehicle(vehicle: vehicle)
        if vehicle.isArchived {
            vehicles.removeAll { $0.id == vehicle.id }
            if let index = archivedVehicles.firstIndex(where: { $0.id == vehicle.id }) {
                archivedVehicles[index] = vehicle
            } else {
                archivedVehicles.insert(vehicle, at: 0)
            }
        } else {
            archivedVehicles.removeAll { $0.id == vehicle.id }
            if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
                vehicles[index] = vehicle
            } else {
                vehicles.insert(vehicle, at: 0)
            }
            if currentVehicle?.id == vehicle.id {
                await refreshManufacturerStandard(for: vehicle)
            }
        }
        publishCarPlayWidgetState()
    }

    /// Archives a vehicle from the garage without deleting its fuel, service, or trip history.
    /// The active vehicle cannot be archived — switch to another car first.
    func archiveVehicle(_ vehicleId: String) async throws {
        guard AuthService.shared.userId != nil else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let vehicle = vehicles.first(where: { $0.id == vehicleId }) else {
            throw NSError(domain: "Veloseete", code: 404, userInfo: [NSLocalizedDescriptionKey: "Vehicle not found"])
        }
        if currentVehicle?.id == vehicleId {
            throw NSError(
                domain: "Veloseete",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Make another vehicle active before archiving this one."]
            )
        }

        try await FirestoreRepository.shared.setVehicleArchived(vehicleId: vehicleId, archived: true)

        var archived = vehicle
        archived.isArchived = true
        archived.archivedAt = Date()
        vehicles.removeAll { $0.id == vehicleId }
        archivedVehicles.insert(archived, at: 0)
        publishCarPlayWidgetState()
    }

    /// Restores an archived vehicle to the active garage. History was never deleted.
    func restoreVehicle(_ vehicleId: String) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let vehicle = archivedVehicles.first(where: { $0.id == vehicleId }) else {
            throw NSError(domain: "Veloseete", code: 404, userInfo: [NSLocalizedDescriptionKey: "Archived vehicle not found"])
        }

        try await FirestoreRepository.shared.setVehicleArchived(vehicleId: vehicleId, archived: false)

        var restored = vehicle
        restored.isArchived = false
        restored.archivedAt = nil
        archivedVehicles.removeAll { $0.id == vehicleId }
        vehicles.insert(restored, at: 0)

        if userDocument?.currentVehicleId == nil {
            try await selectVehicle(vehicleId)
        } else {
            publishCarPlayWidgetState()
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
        publishCarPlayWidgetState()
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
            publishCarPlayWidgetState()
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
        publishCarPlayWidgetState()
        return trip
    }

    func clear() {
        userDocument = nil
        vehicles = []
        archivedVehicles = []
        fuelLogs = []
        serviceLogs = []
        trips = []
        manufacturerStandard = nil
        isLoaded = false
        loadError = nil
        loadWarnings = []
        CarPlayWidgetStateStore.clearUserData()
    }

    private func publishCarPlayWidgetState() {
        guard let vehicle = currentVehicle else { return }
        let lastFuel = fuelLogs
            .filter { $0.vehicleId == vehicle.id }
            .max { $0.timestamp < $1.timestamp }
        let metrics = MetricsCalculator.compute(vehicle: vehicle, logs: fuelLogs)
        let totalDistance = InsightGenerator.totalKilometersDriven(
            trips: trips,
            logs: fuelLogs,
            vehicleId: vehicle.id
        )
        let recentRoute = trips
            .filter { $0.vehicleId == vehicle.id && !$0.route.isEmpty }
            .max { $0.endedAt < $1.endedAt }
            .map { TripTrackingLogic.downsample($0.route, maximum: 40) }
            ?? []
        CarPlayWidgetStateStore.updateVehicle(
            id: vehicle.id,
            name: vehicle.nickname,
            odometerKm: vehicle.currentOdometer,
            autoTrackingEnabled: TripRecordingService.shared.autoTrackingEnabled,
            lastFuelVolume: lastFuel?.fuelVolume,
            lastFuelTotalCost: lastFuel?.totalCost,
            lastFuelCurrency: lastFuel?.currency,
            lastFuelDate: lastFuel?.timestamp,
            totalDistanceKm: totalDistance,
            efficiencyLPer100Km: metrics.current,
            monthlySpend: metrics.monthlySpend,
            currency: vehicle.currency,
            recentRoute: recentRoute.map {
                CarPlayWidgetRoutePoint(latitude: $0.latitude, longitude: $0.longitude)
            }
        )
    }
}
