import Foundation
import FirebaseFirestore
import FirebaseAuth

final class FirestoreRepository {
    static let shared = FirestoreRepository()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - User

    func createUserDocument(userId: String, userName: String, currency: String) async throws {
        let data: [String: Any] = [
            "userId": userId,
            "profile": [
                "userName": userName,
                "defaultCurrency": currency,
                "defaultDistanceUnit": "km",
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ],
            "currentVehicleId": NSNull(),
            "metadata": [
                "lastSync": FieldValue.serverTimestamp()
            ]
        ]
        try await db.collection("users").document(userId).setData(data, merge: true)
    }

    func fetchUser(userId: String) async throws -> UserDocument? {
        let snap = try await db.collection("users").document(userId).getDocument()
        guard let data = snap.data() else { return nil }
        return UserDocument.from(userId: userId, data: data)
    }

    func updateUserProfile(
        userId: String,
        userName: String? = nil,
        currency: String? = nil,
        distanceUnit: String? = nil,
        currentVehicleId: String? = nil,
        clearCurrentVehicle: Bool = false
    ) async throws {
        var data: [String: Any] = [
            "metadata.lastSync": FieldValue.serverTimestamp()
        ]
        if let userName {
            data["profile.userName"] = userName
            data["profile.updatedAt"] = FieldValue.serverTimestamp()
        }
        if let currency {
            data["profile.defaultCurrency"] = currency
            data["profile.updatedAt"] = FieldValue.serverTimestamp()
        }
        if let distanceUnit {
            data["profile.defaultDistanceUnit"] = distanceUnit
            data["profile.updatedAt"] = FieldValue.serverTimestamp()
        }
        if clearCurrentVehicle {
            data["currentVehicleId"] = NSNull()
        } else if let currentVehicleId {
            data["currentVehicleId"] = currentVehicleId
        }
        try await db.collection("users").document(userId).setData(data, merge: true)
    }

    // MARK: - Vehicles

    func fetchVehicles(userId: String) async throws -> [Vehicle] {
        do {
            let snap = try await db.collection("vehicles")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            return snap.documents.map { Vehicle.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] vehicles ordered query failed, falling back: \(error)")
            let snap = try await db.collection("vehicles")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            return snap.documents
                .map { Vehicle.from(document: $0.documentID, data: $0.data()) }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    struct NewVehicleInput {
        var nickname: String
        var make: String
        var model: String
        var fuelType: String
        var currentOdometer: Double
        var currency: String
        var icon: String?
        var fuelTankCapacity: Double?
        var fuelVolumeUnit: String
    }

    func addVehicle(userId: String, input: NewVehicleInput) async throws -> String {
        let ref = db.collection("vehicles").document()
        let volumeUnit = VolumeFormat.normalize(input.fuelVolumeUnit) ?? VolumeFormat.defaultUnit(currency: input.currency)
        var data: [String: Any] = [
            "userId": userId,
            "nickname": input.nickname,
            "make": input.make,
            "model": input.model,
            "fuelType": input.fuelType,
            "currentOdometer": input.currentOdometer,
            "currency": input.currency,
            "fuelVolumeUnit": volumeUnit,
            "isArchived": false,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let icon = input.icon, !icon.isEmpty {
            data["icon"] = icon
        }
        if let tank = input.fuelTankCapacity {
            data["fuelTankCapacity"] = tank
        }
        try await ref.setData(data)
        return ref.documentID
    }

    func updateVehicleOdometer(vehicleId: String, odometer: Double) async throws {
        try await db.collection("vehicles").document(vehicleId).updateData([
            "currentOdometer": odometer,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func updateVehicle(vehicle: Vehicle) async throws {
        let volumeUnit = VolumeFormat.normalize(vehicle.fuelVolumeUnit)
            ?? VolumeFormat.defaultUnit(currency: vehicle.currency)
        var data: [String: Any] = [
            "nickname": vehicle.nickname,
            "make": vehicle.make,
            "model": vehicle.model,
            "fuelType": vehicle.fuelType,
            "currentOdometer": vehicle.currentOdometer,
            "currency": vehicle.currency,
            "fuelVolumeUnit": volumeUnit,
            "isArchived": vehicle.isArchived,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        data["fuelTankCapacity"] = vehicle.fuelTankCapacity.map { $0 as Any } ?? NSNull()
        data["icon"] = vehicle.icon.map { $0 as Any } ?? NSNull()
        data["archivedAt"] = vehicle.archivedAt.map { $0 as Any } ?? NSNull()
        try await db.collection("vehicles").document(vehicle.id).updateData(data)
    }

    /// Soft-remove from the garage. Does not delete fuel, service, or trip history for this vehicle.
    func setVehicleArchived(vehicleId: String, archived: Bool) async throws {
        var data: [String: Any] = [
            "isArchived": archived,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        data["archivedAt"] = archived ? FieldValue.serverTimestamp() : NSNull()
        try await db.collection("vehicles").document(vehicleId).updateData(data)
    }

    // MARK: - Fuel logs

    func fetchFuelLogs(userId: String) async throws -> [FuelLog] {
        do {
            let snap = try await db.collection("fuelLogs")
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            return snap.documents.map { FuelLog.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] fuelLogs ordered query failed, falling back: \(error)")
            let snap = try await db.collection("fuelLogs")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            return snap.documents
                .map { FuelLog.from(document: $0.documentID, data: $0.data()) }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }

    struct NewFuelLogInput {
        var vehicleId: String
        var odometerReading: Double
        var fuelVolume: Double
        var pricePerUnit: Double
        var totalCost: Double
        var currency: String
        var isFullTank: Bool
        var timestamp: Date
        var stationName: String? = nil
        var stationLatitude: Double? = nil
        var stationLongitude: Double? = nil
    }

    func addFuelLog(userId: String, input: NewFuelLogInput) async throws -> String {
        let ref = db.collection("fuelLogs").document()
        var data: [String: Any] = [
            "userId": userId,
            "vehicle_id": input.vehicleId,
            "odometer_reading": input.odometerReading,
            "fuel_volume": input.fuelVolume,
            "price_per_unit": input.pricePerUnit,
            "total_cost": input.totalCost,
            "currency": input.currency,
            "is_full_tank": input.isFullTank,
            "timestamp": Timestamp(date: input.timestamp),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let stationName = input.stationName, !stationName.isEmpty {
            data["station_name"] = stationName
        }
        if let lat = input.stationLatitude, let lng = input.stationLongitude {
            data["station_lat"] = lat
            data["station_lng"] = lng
        }
        try await ref.setData(data)
        return ref.documentID
    }

    // MARK: - Service logs

    func fetchServiceLogs(userId: String) async throws -> [ServiceLog] {
        do {
            let snap = try await db.collection("serviceLogs")
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            return snap.documents.map { ServiceLog.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] serviceLogs ordered query failed, falling back: \(error)")
            // Soft-fail empty if permissions missing — don't block fuel data UX
            do {
                let snap = try await db.collection("serviceLogs")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments()
                return snap.documents
                    .map { ServiceLog.from(document: $0.documentID, data: $0.data()) }
                    .sorted { $0.timestamp > $1.timestamp }
            } catch {
                print("[Firestore] serviceLogs unavailable: \(error)")
                return []
            }
        }
    }

    struct ServiceLogInput {
        var vehicleId: String
        var timestamp: Date
        var odometerReading: Double
        var serviceType: String
        var description: String?
        var cost: Double?
        var currency: String
        var nextServiceOdometer: Double?
        var nextServiceDate: Date?
    }

    func addServiceLog(userId: String, input: ServiceLogInput) async throws -> String {
        let ref = db.collection("serviceLogs").document()
        try await ref.setData(serviceData(userId: userId, input: input, includeCreatedAt: true))
        return ref.documentID
    }

    func updateServiceLog(serviceId: String, userId: String, input: ServiceLogInput) async throws {
        let ref = db.collection("serviceLogs").document(serviceId)
        let snapshot = try await ref.getDocument()
        guard snapshot.data()?["userId"] as? String == userId else {
            throw NSError(domain: "Veloseete", code: 403, userInfo: [NSLocalizedDescriptionKey: "This service record does not belong to your account."])
        }
        try await ref.setData(serviceData(userId: userId, input: input, includeCreatedAt: false), merge: true)
    }

    func deleteServiceLog(serviceId: String, userId: String) async throws {
        let ref = db.collection("serviceLogs").document(serviceId)
        let snapshot = try await ref.getDocument()
        guard snapshot.data()?["userId"] as? String == userId else {
            throw NSError(domain: "Veloseete", code: 403, userInfo: [NSLocalizedDescriptionKey: "This service record does not belong to your account."])
        }
        try await ref.delete()
    }

    private func serviceData(userId: String, input: ServiceLogInput, includeCreatedAt: Bool) -> [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "vehicle_id": input.vehicleId,
            "timestamp": Timestamp(date: input.timestamp),
            "odometer_reading": input.odometerReading,
            "service_type": input.serviceType,
            "currency": input.currency,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if includeCreatedAt { data["createdAt"] = FieldValue.serverTimestamp() }
        func optional(_ key: String, _ value: Any?) {
            if let value { data[key] = value }
            else if !includeCreatedAt { data[key] = FieldValue.delete() }
        }
        optional("description", input.description)
        optional("cost", input.cost)
        optional("next_service_odometer", input.nextServiceOdometer)
        optional("next_service_date", input.nextServiceDate.map(Timestamp.init(date:)))
        return data
    }

    // MARK: - Trips

    struct NewTripInput {
        var vehicleId: String
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
    }

    func createTrip(userId: String, input: NewTripInput) async throws -> String {
        let ref = db.collection("trips").document()
        var data: [String: Any] = [
            "userId": userId,
            "vehicle_id": input.vehicleId,
            "startedAt": Timestamp(date: input.startedAt),
            "endedAt": Timestamp(date: input.endedAt),
            "distanceKm": input.distanceKm,
            "durationSec": input.durationSec,
            "avgSpeedKmh": input.avgSpeedKmh,
            "maxSpeedKmh": input.maxSpeedKmh,
            "route": input.route.map { ["lat": $0.latitude, "lng": $0.longitude] },
            "source": input.source,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let start = input.startCoordinate {
            data["startCoord"] = ["lat": start.latitude, "lng": start.longitude]
        }
        if let end = input.endCoordinate {
            data["endCoord"] = ["lat": end.latitude, "lng": end.longitude]
        }
        try await ref.setData(data)
        return ref.documentID
    }

    func fetchTrips(userId: String) async throws -> [Trip] {
        do {
            let snap = try await db.collection("trips")
                .whereField("userId", isEqualTo: userId)
                .order(by: "startedAt", descending: true)
                .getDocuments()
            return snap.documents.map { Trip.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] trips ordered query failed, falling back: \(error)")
            do {
                let snap = try await db.collection("trips")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments()
                return snap.documents
                    .map { Trip.from(document: $0.documentID, data: $0.data()) }
                    .sorted { $0.startedAt > $1.startedAt }
            } catch {
                print("[Firestore] trips unavailable: \(error)")
                return []
            }
        }
    }

    // MARK: - Manufacturer standards

    func fetchManufacturerStandard(make: String, model: String) async throws -> Double? {
        let normalizedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMake.isEmpty,
              !normalizedModel.isEmpty,
              normalizedMake.lowercased() != "unknown",
              normalizedModel.lowercased() != "unknown" else { return nil }
        let snap = try await db.collection("manufacturerStandards")
            .whereField("manufacturer", isEqualTo: normalizedMake)
            .limit(to: 25)
            .getDocuments()

        let match = snap.documents.first { doc in
            let data = doc.data()
            let m = (data["model"] as? String ?? "").lowercased()
            guard !m.isEmpty else { return false }
            let requested = normalizedModel.lowercased()
            return m == requested || m.contains(requested) || requested.contains(m)
        }

        guard let data = match?.data() else { return nil }
        if let avg = FirestoreDecode.optionalDouble(data["avgFuelConsumptionL100km"]), avg > 0 {
            return avg
        }
        return FirestoreDecode.optionalDouble(data["fuelConsumptionL100km"])
    }

    // MARK: - Account deletion

    /// Deletes Firestore documents owned by this user (vehicles, logs, trips, profile).
    func deleteAllUserData(userId: String) async throws {
        let collections = ["vehicles", "fuelLogs", "serviceLogs", "trips"]
        for name in collections {
            try await deleteCollectionDocuments(collection: name, userId: userId)
        }
        try await db.collection("users").document(userId).delete()
    }

    private func deleteCollectionDocuments(collection: String, userId: String) async throws {
        let snap = try await db.collection(collection)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        guard !snap.documents.isEmpty else { return }

        var batch = db.batch()
        var pending = 0
        for doc in snap.documents {
            batch.deleteDocument(doc.reference)
            pending += 1
            if pending >= 400 {
                try await batch.commit()
                batch = db.batch()
                pending = 0
            }
        }
        if pending > 0 {
            try await batch.commit()
        }
    }
}
