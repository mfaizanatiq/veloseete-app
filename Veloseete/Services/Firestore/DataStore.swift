import Foundation
import Combine

struct OdometerEstimate: Equatable {
    var verifiedKm: Double
    var verifiedAt: Date
    var verifiedSource: String
    /// Confirmed (saved) GPS trips since the verified anchor.
    var confirmedTrackedKm: Double
    /// Finished drives waiting in My Drives — real km, not yet in history.
    var pendingTrackedKm: Double

    /// Confirmed + pending distance since the last fuel/service reading.
    var trackedSinceKm: Double { confirmedTrackedKm + pendingTrackedKm }

    /// Best live picture of the dash: verified reading + all GPS since then.
    var estimatedKm: Double { verifiedKm + trackedSinceKm }

    /// True when unconfirmed drives are part of the estimate.
    var includesPending: Bool { pendingTrackedKm > 0.05 }
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

    /// Bumped on every `loadAll` / `clear` so in-flight awaits cannot paint a previous account.
    private var loadGeneration = 0

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

    /// Physical fuel/service readings are anchors. GPS trips (confirmed + pending
    /// review) advance the estimate so a day of driving still tracks the dash
    /// before you confirm every leg.
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

        let confirmed = trips
            .filter { $0.vehicleId == vehicleId && $0.endedAt > verifiedAt && $0.endedAt <= date }
            .reduce(0) { $0 + $1.distanceKm }

        let pending = TripRecordingService.shared.pendingSaves
            .filter { $0.vehicleId == vehicleId && $0.endedAt > verifiedAt && $0.endedAt <= date }
            .reduce(0) { $0 + $1.distanceKm }

        return OdometerEstimate(
            verifiedKm: verifiedKm,
            verifiedAt: verifiedAt,
            verifiedSource: source,
            confirmedTrackedKm: confirmed,
            pendingTrackedKm: pending
        )
    }

    func loadAll(userId: String) async {
        loadGeneration += 1
        let generation = loadGeneration
        func stillCurrent() -> Bool {
            generation == loadGeneration && AuthService.shared.userId == userId
        }

        isLoading = true
        loadError = nil
        loadWarnings = []

        print("[DataStore] Loading for user \(userId)")

        // Instant hydrate from the on-device Firestore cache. This is what
        // keeps the app usable on a VPN / flaky network — we don't wait for
        // Google before painting the garage.
        let hadCache = await hydrateFromLocalCache(userId: userId, stillCurrent: stillCurrent)
        guard stillCurrent() else { return }
        if hadCache {
            isLoading = false
            isLoaded = true
            await reconcileCurrentVehicleIfNeeded(userId: userId)
            guard stillCurrent() else { return }
            publishCarPlayWidgetState()
            VehicleInsightScheduler.shared.refresh(using: self)
            print("[DataStore] Opened from local cache — refreshing from server in background")
        }

        defer {
            if stillCurrent() {
                isLoading = false
                isLoaded = true
            }
        }

        // Server refresh. Failures only warn — never wipe the cache-hydrated state.
        do {
            let document = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchUser(userId: userId)
            }
            guard stillCurrent() else { return }
            userDocument = document
        } catch {
            guard stillCurrent() else { return }
            if !hadCache {
                loadWarnings.append("Profile: \(error.localizedDescription)")
            }
            print("[DataStore] user fetch failed: \(error)")
        }

        do {
            let allVehicles = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchVehicles(userId: userId)
            }
            guard stillCurrent() else { return }
            applyVehicleLists(allVehicles)
            print("[DataStore] vehicles: \(vehicles.count) active, \(archivedVehicles.count) archived")
            TripRecordingService.shared.prunePendingSaves(activeVehicleIds: activeVehicleIds)
        } catch {
            guard stillCurrent() else { return }
            if !hadCache {
                loadWarnings.append("Vehicles: \(error.localizedDescription)")
            }
            print("[DataStore] vehicles fetch failed: \(error)")
        }

        do {
            let logs = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchFuelLogs(userId: userId)
            }
            guard stillCurrent() else { return }
            fuelLogs = logs
            print("[DataStore] fuelLogs: \(fuelLogs.count)")
        } catch {
            guard stillCurrent() else { return }
            if !hadCache {
                loadWarnings.append("Fuel logs: \(error.localizedDescription)")
            }
            print("[DataStore] fuelLogs fetch failed: \(error)")
        }

        do {
            let logs = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchServiceLogs(userId: userId)
            }
            guard stillCurrent() else { return }
            serviceLogs = logs
            print("[DataStore] serviceLogs: \(serviceLogs.count)")
        } catch {
            guard stillCurrent() else { return }
            print("[DataStore] serviceLogs fetch failed: \(error)")
            if !hadCache { serviceLogs = [] }
        }

        do {
            let loadedTrips = try await fetchWithTimeout {
                try await FirestoreRepository.shared.fetchTrips(userId: userId)
            }
            guard stillCurrent() else { return }
            trips = loadedTrips
            print("[DataStore] trips: \(trips.count)")
        } catch {
            guard stillCurrent() else { return }
            print("[DataStore] trips fetch failed: \(error)")
            if !hadCache { trips = [] }
        }

        if vehicles.isEmpty && fuelLogs.isEmpty && !loadWarnings.isEmpty {
            loadError = loadWarnings.joined(separator: "\n")
        }

        await reconcileCurrentVehicleIfNeeded(userId: userId)
        guard stillCurrent() else { return }

        if let vehicle = currentVehicle {
            await refreshManufacturerStandard(for: vehicle)
            guard stillCurrent() else { return }
        }
        publishCarPlayWidgetState()
        VehicleInsightScheduler.shared.refresh(using: self)
    }

    /// Pull last-known data from Firestore's on-device cache. Returns true if
    /// enough data was found to unlock the UI without waiting on the network.
    private func hydrateFromLocalCache(
        userId: String,
        stillCurrent: () -> Bool
    ) async -> Bool {
        var found = false

        if let user = try? await FirestoreRepository.shared.fetchUser(userId: userId, source: .cache) {
            guard stillCurrent() else { return false }
            userDocument = user
            found = true
        }

        if let cachedVehicles = try? await FirestoreRepository.shared.fetchVehicles(userId: userId, source: .cache),
           !cachedVehicles.isEmpty {
            guard stillCurrent() else { return false }
            applyVehicleLists(cachedVehicles)
            TripRecordingService.shared.prunePendingSaves(activeVehicleIds: activeVehicleIds)
            found = true
        }

        if let cachedFuel = try? await FirestoreRepository.shared.fetchFuelLogs(userId: userId, source: .cache) {
            guard stillCurrent() else { return false }
            fuelLogs = cachedFuel
            if !cachedFuel.isEmpty { found = true }
        }

        if let cachedServices = try? await FirestoreRepository.shared.fetchServiceLogs(userId: userId, source: .cache) {
            guard stillCurrent() else { return false }
            serviceLogs = cachedServices
        }

        if let cachedTrips = try? await FirestoreRepository.shared.fetchTrips(userId: userId, source: .cache) {
            guard stillCurrent() else { return false }
            trips = cachedTrips
        }

        return stillCurrent() ? found : false
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

    @discardableResult
    func addVehicle(
        nickname: String,
        make: String,
        model: String,
        fuelType: String,
        currentOdometer: Double,
        currency: String,
        icon: String?,
        paintColor: String? = nil,
        fuelTankCapacity: Double?,
        fuelVolumeUnit: String
    ) async throws -> Vehicle {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let volumeUnit = VolumeFormat.normalize(fuelVolumeUnit) ?? VolumeFormat.defaultUnit(currency: currency)
        let resolvedPaint = VehiclePaintColor.resolve(paintColor)
        let paintToken = resolvedPaint == .brand ? nil : resolvedPaint.rawValue
        let input = FirestoreRepository.NewVehicleInput(
            nickname: nickname,
            make: make,
            model: model,
            fuelType: fuelType,
            currentOdometer: currentOdometer,
            currency: currency,
            icon: icon,
            paintColor: paintToken,
            fuelTankCapacity: fuelTankCapacity,
            fuelVolumeUnit: volumeUnit
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
            fuelVolumeUnit: volumeUnit,
            icon: icon,
            paintColor: paintToken,
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
        return vehicle
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
        // An archived car shouldn't keep nagging for drive reviews.
        TripRecordingService.shared.prunePendingSaves(activeVehicleIds: activeVehicleIds)
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
        timestamp: Date,
        stationName: String? = nil,
        stationLatitude: Double? = nil,
        stationLongitude: Double? = nil
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
            timestamp: timestamp,
            stationName: stationName,
            stationLatitude: stationLatitude,
            stationLongitude: stationLongitude
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
            isFullTank: isFullTank,
            stationName: stationName,
            stationLatitude: stationLatitude,
            stationLongitude: stationLongitude
        )
        fuelLogs.insert(log, at: 0)
        vehicles = vehicles.map { v in
            guard v.id == vehicleId else { return v }
            var updated = v
            updated.currentOdometer = odometerReading
            return updated
        }
        publishCarPlayWidgetState()
        VehicleInsightScheduler.shared.refresh(using: self)
    }

    func updateFuelLog(_ log: FuelLog) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        var updated = log
        updated.pricePerUnit = log.fuelVolume > 0 ? log.totalCost / log.fuelVolume : 0

        let input = FirestoreRepository.NewFuelLogInput(
            vehicleId: updated.vehicleId,
            odometerReading: updated.odometerReading,
            fuelVolume: updated.fuelVolume,
            pricePerUnit: updated.pricePerUnit,
            totalCost: updated.totalCost,
            currency: updated.currency,
            isFullTank: updated.isFullTank,
            timestamp: updated.timestamp,
            stationName: updated.stationName,
            stationLatitude: updated.stationLatitude,
            stationLongitude: updated.stationLongitude
        )
        try await FirestoreRepository.shared.updateFuelLog(logId: updated.id, userId: userId, input: input)

        if let index = fuelLogs.firstIndex(where: { $0.id == updated.id }) {
            fuelLogs[index] = updated
        }
        fuelLogs.sort { $0.timestamp > $1.timestamp }

        await syncVehicleOdometerWithLogs(vehicleId: updated.vehicleId)
        publishCarPlayWidgetState()
        VehicleInsightScheduler.shared.refresh(using: self)
    }

    func deleteFuelLog(_ log: FuelLog) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        try await FirestoreRepository.shared.deleteFuelLog(logId: log.id, userId: userId)
        fuelLogs.removeAll { $0.id == log.id }

        await syncVehicleOdometerWithLogs(vehicleId: log.vehicleId)
        publishCarPlayWidgetState()
        VehicleInsightScheduler.shared.refresh(using: self)
    }

    /// After an edit/delete, re-anchor the vehicle odometer to the most recent fuel log
    /// so a corrected reading propagates (fills are the strongest odometer anchors).
    private func syncVehicleOdometerWithLogs(vehicleId: String) async {
        guard let vehicle = vehicles.first(where: { $0.id == vehicleId }) else { return }
        guard let latest = fuelLogs
            .filter({ $0.vehicleId == vehicleId })
            .max(by: { $0.timestamp < $1.timestamp }) else { return }
        guard latest.odometerReading > 0, latest.odometerReading != vehicle.currentOdometer else { return }

        do {
            try await FirestoreRepository.shared.updateVehicleOdometer(
                vehicleId: vehicleId,
                odometer: latest.odometerReading
            )
            vehicles = vehicles.map { v in
                guard v.id == vehicleId else { return v }
                var updated = v
                updated.currentOdometer = latest.odometerReading
                return updated
            }
        } catch {
            print("[DataStore] odometer re-sync failed: \(error)")
        }
    }

    /// Saves a service record only. Never updates `vehicle.currentOdometer`.
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
            brand: input.brand,
            cost: input.cost,
            currency: input.currency,
            nextServiceOdometer: input.nextServiceOdometer,
            nextServiceDate: input.nextServiceDate
        )
        serviceLogs.removeAll { $0.id == resolvedId }
        serviceLogs.append(saved)
        serviceLogs.sort { $0.timestamp > $1.timestamp }
        VehicleInsightScheduler.shared.refresh(using: self)
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

        let resolvedVehicleId: String
        if pending.vehicleId.isEmpty {
            guard let vehicle = currentVehicle else {
                throw NSError(
                    domain: "Veloseete",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Add a car in Garage to save this drive."]
                )
            }
            resolvedVehicleId = vehicle.id
        } else {
            resolvedVehicleId = pending.vehicleId
        }

        let input = FirestoreRepository.NewTripInput(
            vehicleId: resolvedVehicleId,
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
                vehicleId: resolvedVehicleId,
                odometer: odometer
            )
            vehicles = vehicles.map { v in
                guard v.id == resolvedVehicleId else { return v }
                var updated = v
                updated.currentOdometer = odometer
                return updated
            }
            publishCarPlayWidgetState()
        }

        let trip = Trip(
            id: id,
            vehicleId: resolvedVehicleId,
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
        // Driven km change the fuel-range picture, so re-evaluate reminders.
        VehicleInsightScheduler.shared.refresh(using: self)
        return trip
    }

    func deleteTrip(_ trip: Trip) async throws {
        guard let userId = AuthService.shared.userId else {
            throw NSError(domain: "Veloseete", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        try await FirestoreRepository.shared.deleteTrip(tripId: trip.id, userId: userId)
        trips.removeAll { $0.id == trip.id }
        publishCarPlayWidgetState()
        VehicleInsightScheduler.shared.refresh(using: self)
    }

    func clear() {
        loadGeneration += 1
        userDocument = nil
        vehicles = []
        archivedVehicles = []
        fuelLogs = []
        serviceLogs = []
        trips = []
        manufacturerStandard = nil
        isLoading = false
        isLoaded = false
        loadError = nil
        loadWarnings = []
        CarPlayWidgetStateStore.clearUserData()
    }

    /// Push the latest vehicle stats into the App Group for home-screen widgets.
    func refreshHomeWidgets() {
        publishCarPlayWidgetState()
        CarPlayWidgetStateStore.reloadAllTimelines()
    }

    private func publishCarPlayWidgetState() {
        guard let vehicle = currentVehicle else {
            CarPlayWidgetStateStore.reloadAllTimelines()
            return
        }
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
            estimatedOdometerKm: odometerEstimate(vehicleId: vehicle.id)?.estimatedKm,
            autoTrackingEnabled: TripRecordingService.shared.autoTrackingEnabled,
            lastFuelVolume: lastFuel?.fuelVolume,
            lastFuelTotalCost: lastFuel?.totalCost,
            lastFuelCurrency: lastFuel?.currency,
            lastFuelDate: lastFuel?.timestamp,
            lastStationName: lastFuel?.stationName,
            totalDistanceKm: totalDistance,
            efficiencyLPer100Km: metrics.current,
            monthlySpend: metrics.monthlySpend,
            currency: vehicle.currency,
            fuelVolumeUnit: vehicle.fuelVolumeUnit,
            recentRoute: recentRoute.map {
                CarPlayWidgetRoutePoint(latitude: $0.latitude, longitude: $0.longitude)
            },
            pendingTripCount: TripRecordingService.shared.pendingSaves.count
        )
    }
}
