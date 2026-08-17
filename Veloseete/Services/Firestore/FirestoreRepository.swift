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

    func fetchUser(userId: String, source: FirestoreSource = .default) async throws -> UserDocument? {
        let snap = try await db.collection("users").document(userId).getDocument(source: source)
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

    func fetchVehicles(userId: String, source: FirestoreSource = .default) async throws -> [Vehicle] {
        do {
            let snap = try await db.collection("vehicles")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments(source: source)
            return snap.documents.map { Vehicle.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] vehicles ordered query failed, falling back: \(error)")
            let snap = try await db.collection("vehicles")
                .whereField("userId", isEqualTo: userId)
                .getDocuments(source: source)
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

    func fetchFuelLogs(userId: String, source: FirestoreSource = .default) async throws -> [FuelLog] {
        do {
            let snap = try await db.collection("fuelLogs")
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .getDocuments(source: source)
            return snap.documents.map { FuelLog.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] fuelLogs ordered query failed, falling back: \(error)")
            let snap = try await db.collection("fuelLogs")
                .whereField("userId", isEqualTo: userId)
                .getDocuments(source: source)
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

    func updateFuelLog(logId: String, userId: String, input: NewFuelLogInput) async throws {
        let ref = db.collection("fuelLogs").document(logId)
        let snapshot = try await ref.getDocument()
        guard snapshot.data()?["userId"] as? String == userId else {
            throw NSError(domain: "Veloseete", code: 403, userInfo: [NSLocalizedDescriptionKey: "This fuel record does not belong to your account."])
        }
        var data: [String: Any] = [
            "vehicle_id": input.vehicleId,
            "odometer_reading": input.odometerReading,
            "fuel_volume": input.fuelVolume,
            "price_per_unit": input.pricePerUnit,
            "total_cost": input.totalCost,
            "currency": input.currency,
            "is_full_tank": input.isFullTank,
            "timestamp": Timestamp(date: input.timestamp),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let stationName = input.stationName, !stationName.isEmpty {
            data["station_name"] = stationName
        } else {
            data["station_name"] = FieldValue.delete()
        }
        if let lat = input.stationLatitude, let lng = input.stationLongitude {
            data["station_lat"] = lat
            data["station_lng"] = lng
        } else {
            data["station_lat"] = FieldValue.delete()
            data["station_lng"] = FieldValue.delete()
        }
        try await ref.setData(data, merge: true)
    }

    func deleteFuelLog(logId: String, userId: String) async throws {
        let ref = db.collection("fuelLogs").document(logId)
        let snapshot = try await ref.getDocument()
        guard snapshot.data()?["userId"] as? String == userId else {
            throw NSError(domain: "Veloseete", code: 403, userInfo: [NSLocalizedDescriptionKey: "This fuel record does not belong to your account."])
        }
        try await ref.delete()
    }

    // MARK: - Service logs

    func fetchServiceLogs(userId: String, source: FirestoreSource = .default) async throws -> [ServiceLog] {
        do {
            let snap = try await db.collection("serviceLogs")
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .getDocuments(source: source)
            return snap.documents.map { ServiceLog.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] serviceLogs ordered query failed, falling back: \(error)")
            // Soft-fail empty if permissions missing — don't block fuel data UX
            do {
                let snap = try await db.collection("serviceLogs")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments(source: source)
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

    func deleteTrip(tripId: String, userId: String) async throws {
        let ref = db.collection("trips").document(tripId)
        let snapshot = try await ref.getDocument()
        guard snapshot.data()?["userId"] as? String == userId else {
            throw NSError(
                domain: "Veloseete",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "This drive does not belong to your account."]
            )
        }
        try await ref.delete()
    }

    func fetchTrips(userId: String, source: FirestoreSource = .default) async throws -> [Trip] {
        do {
            let snap = try await db.collection("trips")
                .whereField("userId", isEqualTo: userId)
                .order(by: "startedAt", descending: true)
                .getDocuments(source: source)
            return snap.documents.map { Trip.from(document: $0.documentID, data: $0.data()) }
        } catch {
            print("[Firestore] trips ordered query failed, falling back: \(error)")
            do {
                let snap = try await db.collection("trips")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments(source: source)
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

        let makeKey = Self.standardsKey(normalizedMake)
        let modelKey = Self.standardsKey(normalizedModel)

        // Seeded docs (tools/manufacturer-standards) use "<makeKey>__<modelKey>"
        // IDs — an exact vehicle resolves with a single direct read.
        let direct = try await db.collection("manufacturerStandards")
            .document("\(makeKey)__\(modelKey)")
            .getDocument()
        if direct.exists, let value = Self.standardValue(direct.data() ?? [:]) {
            return value
        }

        var docsData = try await db.collection("manufacturerStandards")
            .whereField("manufacturerKey", isEqualTo: makeKey)
            .limit(to: 400)
            .getDocuments()
            .documents.map { $0.data() }

        // Legacy documents predate the key fields.
        if docsData.isEmpty {
            docsData = try await db.collection("manufacturerStandards")
                .whereField("manufacturer", isEqualTo: normalizedMake)
                .limit(to: 100)
                .getDocuments()
                .documents.map { $0.data() }
        }

        let requested = normalizedModel.lowercased()
        let candidates = docsData.compactMap { data -> (model: String, value: Double)? in
            let m = (data["model"] as? String ?? "").lowercased()
            guard !m.isEmpty, let value = Self.standardValue(data) else { return nil }
            guard m == requested || m.contains(requested) || requested.contains(m) else { return nil }
            return (m, value)
        }

        if let exact = candidates.first(where: { $0.model == requested }) {
            return exact.value
        }
        // Deterministic fuzzy pick: the candidate closest in length to the
        // requested name, ties broken alphabetically — so "Corolla" prefers
        // "Corolla" over "Corolla Cross Hybrid" regardless of query order.
        return candidates
            .sorted { lhs, rhs in
                let lhsDelta = abs(lhs.model.count - requested.count)
                let rhsDelta = abs(rhs.model.count - requested.count)
                return lhsDelta == rhsDelta ? lhs.model < rhs.model : lhsDelta < rhsDelta
            }
            .first?.value
    }

    /// Mirrors the key normalization in tools/manufacturer-standards:
    /// lowercase, non-alphanumeric runs collapse to a single "-".
    private static func standardsKey(_ text: String) -> String {
        var result = ""
        var previousWasDash = true
        for character in text.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                result.append(character)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }
        if result.hasSuffix("-") { result.removeLast() }
        return result
    }

    private static func standardValue(_ data: [String: Any]) -> Double? {
        if let avg = FirestoreDecode.optionalDouble(data["avgFuelConsumptionL100km"]), avg > 0 {
            return avg
        }
        if let fallback = FirestoreDecode.optionalDouble(data["fuelConsumptionL100km"]), fallback > 0 {
            return fallback
        }
        return nil
    }

    // MARK: - Account deletion

    /// Deletes Firestore documents owned by this user (garage, logs, trips, voice, profile).
    func deleteAllUserData(userId: String) async throws {
        try await deleteRoadmapVotes(userId: userId)

        let collections = [
            "vehicles",
            "fuelLogs",
            "serviceLogs",
            "trips",
            "productFeedback",
            "featureRequests"
        ]
        for name in collections {
            try await deleteCollectionDocuments(collection: name, userId: userId)
        }
        try await db.collection("users").document(userId).delete()
    }

    /// Removes the user's roadmap votes and decrements item counters when possible.
    private func deleteRoadmapVotes(userId: String) async throws {
        let snap = try await db.collection("roadmapVotes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        guard !snap.documents.isEmpty else { return }

        for doc in snap.documents {
            let itemId = doc.data()["itemId"] as? String
            try await doc.reference.delete()
            guard let itemId, !itemId.isEmpty else { continue }
            let itemRef = db.collection("roadmapItems").document(itemId)
            do {
                try await itemRef.updateData([
                    "voteCount": FieldValue.increment(Int64(-1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                // Item may already be gone; vote row is deleted either way.
                print("[Firestore] vote cleanup: could not decrement \(itemId): \(error.localizedDescription)")
            }
        }
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

    // MARK: - Product voice (feedback + roadmap)

    func fetchModeratorConfig() async -> ModeratorConfig {
        do {
            let snap = try await db.collection("appConfig").document("moderators").getDocument()
            return ModeratorConfig.from(data: snap.data())
        } catch {
            return ModeratorConfig(emails: [], userIds: [])
        }
    }

    func fetchRoadmapItems() async throws -> [RoadmapItem] {
        let snap = try await db.collection("roadmapItems").getDocuments()
        return snap.documents
            .map { RoadmapItem.from(document: $0.documentID, data: $0.data()) }
            .sorted(by: Self.roadmapSort)
    }

    func fetchVotedItemIds(userId: String) async throws -> Set<String> {
        let snap = try await db.collection("roadmapVotes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return Set(snap.documents.compactMap { $0.data()["itemId"] as? String })
    }

    func toggleRoadmapVote(itemId: String, userId: String) async throws -> Bool {
        let voteId = "\(itemId)_\(userId)"
        let voteRef = db.collection("roadmapVotes").document(voteId)
        let itemRef = db.collection("roadmapItems").document(itemId)
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let voteSnap = try transaction.getDocument(voteRef)
                let itemSnap = try transaction.getDocument(itemRef)
                guard itemSnap.exists else {
                    throw NSError(
                        domain: "Veloseete",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "That roadmap item is no longer available."]
                    )
                }
                if voteSnap.exists {
                    transaction.deleteDocument(voteRef)
                    transaction.updateData([
                        "voteCount": FieldValue.increment(Int64(-1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: itemRef)
                    return NSNumber(value: false)
                }
                transaction.setData([
                    "itemId": itemId,
                    "userId": userId,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: voteRef)
                transaction.updateData([
                    "voteCount": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: itemRef)
                return NSNumber(value: true)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return (result as? NSNumber)?.boolValue ?? false
    }

    func submitProductFeedback(userId: String, authorName: String, message: String) async throws {
        let ref = db.collection("productFeedback").document()
        try await ref.setData([
            "userId": userId,
            "authorName": authorName,
            "message": message,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func submitFeatureRequest(userId: String, authorName: String, title: String, detail: String) async throws {
        let ref = db.collection("featureRequests").document()
        try await ref.setData([
            "userId": userId,
            "authorName": authorName,
            "title": title,
            "detail": detail,
            "status": FeatureRequest.Status.open.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func fetchFeatureRequests(userId: String? = nil, status: FeatureRequest.Status? = .open) async throws -> [FeatureRequest] {
        var query: Query = db.collection("featureRequests")
        if let userId {
            query = query.whereField("userId", isEqualTo: userId)
        }
        if let status {
            query = query.whereField("status", isEqualTo: status.rawValue)
        }
        let snap = try await query.getDocuments()
        return snap.documents
            .map { FeatureRequest.from(document: $0.documentID, data: $0.data()) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func addRoadmapItem(
        title: String,
        detail: String,
        status: RoadmapStatus,
        sourceRequestId: String? = nil
    ) async throws -> String {
        let ref = db.collection("roadmapItems").document()
        var data: [String: Any] = [
            "title": title,
            "detail": detail,
            "status": status.rawValue,
            "voteCount": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if status == .released {
            data["releasedAt"] = FieldValue.serverTimestamp()
        }
        if let sourceRequestId {
            data["sourceRequestId"] = sourceRequestId
        }
        try await ref.setData(data)
        return ref.documentID
    }

    func updateRoadmapStatus(itemId: String, status: RoadmapStatus) async throws {
        var data: [String: Any] = [
            "status": status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        data["releasedAt"] = status == .released ? FieldValue.serverTimestamp() : NSNull()
        try await db.collection("roadmapItems").document(itemId).updateData(data)
    }

    func promoteFeatureRequest(_ request: FeatureRequest) async throws {
        let itemId = try await addRoadmapItem(
            title: request.title,
            detail: request.detail,
            status: .upcoming,
            sourceRequestId: request.id
        )
        try await db.collection("featureRequests").document(request.id).updateData([
            "status": FeatureRequest.Status.promoted.rawValue,
            "promotedItemId": itemId,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func declineFeatureRequest(requestId: String) async throws {
        try await db.collection("featureRequests").document(requestId).updateData([
            "status": FeatureRequest.Status.declined.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    private static func roadmapSort(_ lhs: RoadmapItem, _ rhs: RoadmapItem) -> Bool {
        let order: [RoadmapStatus: Int] = [.upcoming: 0, .planned: 1, .released: 2]
        let lhsRank = order[lhs.status] ?? 0
        let rhsRank = order[rhs.status] ?? 0
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.status == .released {
            let lhsDate = lhs.releasedAt ?? lhs.createdAt
            let rhsDate = rhs.releasedAt ?? rhs.createdAt
            return lhsDate > rhsDate
        }
        if lhs.voteCount != rhs.voteCount { return lhs.voteCount > rhs.voteCount }
        return lhs.createdAt > rhs.createdAt
    }
}
