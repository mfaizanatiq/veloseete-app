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
        currency: String? = nil,
        distanceUnit: String? = nil,
        currentVehicleId: String? = nil,
        clearCurrentVehicle: Bool = false
    ) async throws {
        var data: [String: Any] = [
            "metadata.lastSync": FieldValue.serverTimestamp()
        ]
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
    }

    func addVehicle(userId: String, input: NewVehicleInput) async throws -> String {
        let ref = db.collection("vehicles").document()
        var data: [String: Any] = [
            "userId": userId,
            "nickname": input.nickname,
            "make": input.make,
            "model": input.model,
            "fuelType": input.fuelType,
            "currentOdometer": input.currentOdometer,
            "currency": input.currency,
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
    }

    func addFuelLog(userId: String, input: NewFuelLogInput) async throws -> String {
        let ref = db.collection("fuelLogs").document()
        let data: [String: Any] = [
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
        let snap = try await db.collection("manufacturerStandards")
            .whereField("manufacturer", isEqualTo: make)
            .limit(to: 25)
            .getDocuments()

        let match = snap.documents.first { doc in
            let data = doc.data()
            let m = (data["model"] as? String ?? "").lowercased()
            return m.contains(model.lowercased()) || model.lowercased().contains(m)
        }

        guard let data = match?.data() else { return nil }
        if let avg = FirestoreDecode.optionalDouble(data["avgFuelConsumptionL100km"]), avg > 0 {
            return avg
        }
        return FirestoreDecode.optionalDouble(data["fuelConsumptionL100km"])
    }
}
