import Foundation
import FirebaseFirestore

struct UserProfile: Equatable {
    var userName: String
    var defaultCurrency: String
    var defaultDistanceUnit: String
}

struct UserDocument: Equatable {
    var userId: String
    var profile: UserProfile
    var currentVehicleId: String?
}

struct Vehicle: Identifiable, Equatable {
    var id: String
    var nickname: String
    var make: String
    var model: String
    var fuelType: String
    var currentOdometer: Double
    /// Always stored in litres.
    var fuelTankCapacity: Double?
    var currency: String
    /// Display/entry unit for fuel volume: `"L"` or `"gal"` (US gallon). Stored litres stay canonical.
    var fuelVolumeUnit: String
    var icon: String?
    var createdAt: Date
    /// Soft-removed from the garage. History stays on this vehicleId; other cars are untouched.
    var isArchived: Bool
    var archivedAt: Date?
}

struct FuelLog: Identifiable, Equatable {
    var id: String
    var vehicleId: String
    var timestamp: Date
    var odometerReading: Double
    var fuelVolume: Double
    var pricePerUnit: Double
    var totalCost: Double
    var currency: String
    var isFullTank: Bool
    /// Nearest petrol station name when the fill was logged (optional).
    var stationName: String? = nil
    var stationLatitude: Double? = nil
    var stationLongitude: Double? = nil
}

struct ServiceLog: Identifiable, Equatable {
    var id: String
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

struct TripCoordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
}

struct Trip: Identifiable, Equatable {
    var id: String
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
    var source: String // "auto" | "manual"
}

extension Trip {
    var durationFormatted: String {
        let total = Int(durationSec)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    static func from(document id: String, data: [String: Any]) -> Trip {
        let routeRaw = data["route"] as? [[String: Any]] ?? []
        let route: [TripCoordinate] = routeRaw.compactMap { point in
            let lat = FirestoreDecode.double(point["lat"])
            let lng = FirestoreDecode.double(point["lng"])
            guard lat != 0 || lng != 0 else { return nil }
            return TripCoordinate(latitude: lat, longitude: lng)
        }

        func coord(_ key: String) -> TripCoordinate? {
            guard let dict = data[key] as? [String: Any] else { return nil }
            let lat = FirestoreDecode.double(dict["lat"])
            let lng = FirestoreDecode.double(dict["lng"])
            if lat == 0 && lng == 0 { return nil }
            return TripCoordinate(latitude: lat, longitude: lng)
        }

        return Trip(
            id: id,
            vehicleId: FirestoreDecode.string(data["vehicle_id"]).isEmpty
                ? FirestoreDecode.string(data["vehicleId"])
                : FirestoreDecode.string(data["vehicle_id"]),
            startedAt: FirestoreDecode.date(data["startedAt"]),
            endedAt: FirestoreDecode.date(data["endedAt"]),
            distanceKm: FirestoreDecode.double(data["distanceKm"]),
            durationSec: FirestoreDecode.double(data["durationSec"]),
            avgSpeedKmh: FirestoreDecode.double(data["avgSpeedKmh"]),
            maxSpeedKmh: FirestoreDecode.double(data["maxSpeedKmh"]),
            startCoordinate: coord("startCoord"),
            endCoordinate: coord("endCoord"),
            route: route,
            source: FirestoreDecode.string(data["source"], fallback: "manual")
        )
    }
}

enum FirestoreDecode {
    static func double(_ any: Any?) -> Double {
        if let n = any as? NSNumber { return n.doubleValue }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let i = any as? Int64 { return Double(i) }
        if let s = any as? String { return Double(s) ?? 0 }
        return 0
    }

    static func optionalDouble(_ any: Any?) -> Double? {
        guard let any else { return nil }
        if any is NSNull { return nil }
        return double(any)
    }

    static func string(_ any: Any?, fallback: String = "") -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return fallback
    }

    static func bool(_ any: Any?, fallback: Bool = false) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return fallback
    }

    static func date(_ any: Any?) -> Date {
        if let t = any as? Timestamp { return t.dateValue() }
        if let d = any as? Date { return d }
        if let s = any as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
        }
        return Date()
    }
}

extension Vehicle {
    static func from(document id: String, data: [String: Any]) -> Vehicle {
        let archived = FirestoreDecode.bool(data["isArchived"], fallback: false)
        return Vehicle(
            id: id,
            nickname: FirestoreDecode.string(data["nickname"], fallback: "Vehicle"),
            make: FirestoreDecode.string(data["make"], fallback: "Unknown"),
            model: FirestoreDecode.string(data["model"], fallback: "Unknown"),
            fuelType: FirestoreDecode.string(data["fuelType"], fallback: "petrol"),
            currentOdometer: FirestoreDecode.double(data["currentOdometer"]),
            fuelTankCapacity: data["fuelTankCapacity"] == nil ? nil : FirestoreDecode.optionalDouble(data["fuelTankCapacity"]),
            currency: FirestoreDecode.string(data["currency"], fallback: "QAR"),
            fuelVolumeUnit: VolumeFormat.normalize(
                FirestoreDecode.string(data["fuelVolumeUnit"], fallback: "")
            ) ?? VolumeFormat.defaultUnit(currency: FirestoreDecode.string(data["currency"], fallback: "QAR")),
            icon: data["icon"] as? String,
            createdAt: FirestoreDecode.date(data["createdAt"]),
            isArchived: archived,
            archivedAt: data["archivedAt"] == nil || data["archivedAt"] is NSNull
                ? nil
                : FirestoreDecode.date(data["archivedAt"])
        )
    }
}

extension FuelLog {
    static func from(document id: String, data: [String: Any]) -> FuelLog {
        let vehicleId = FirestoreDecode.string(data["vehicle_id"]).isEmpty
            ? FirestoreDecode.string(data["vehicleId"])
            : FirestoreDecode.string(data["vehicle_id"])

        return FuelLog(
            id: id,
            vehicleId: vehicleId,
            timestamp: FirestoreDecode.date(data["timestamp"]),
            odometerReading: FirestoreDecode.double(data["odometer_reading"]),
            fuelVolume: FirestoreDecode.double(data["fuel_volume"]),
            pricePerUnit: FirestoreDecode.double(data["price_per_unit"]),
            totalCost: FirestoreDecode.double(data["total_cost"]),
            currency: FirestoreDecode.string(data["currency"], fallback: "QAR"),
            isFullTank: FirestoreDecode.bool(data["is_full_tank"], fallback: true),
            stationName: {
                let name = FirestoreDecode.string(data["station_name"])
                return name.isEmpty ? nil : name
            }(),
            stationLatitude: data["station_lat"] == nil ? nil : FirestoreDecode.optionalDouble(data["station_lat"]),
            stationLongitude: data["station_lng"] == nil ? nil : FirestoreDecode.optionalDouble(data["station_lng"])
        )
    }
}

extension ServiceLog {
    static func from(document id: String, data: [String: Any]) -> ServiceLog {
        let vehicleId = FirestoreDecode.string(data["vehicle_id"]).isEmpty
            ? FirestoreDecode.string(data["vehicleId"])
            : FirestoreDecode.string(data["vehicle_id"])

        return ServiceLog(
            id: id,
            vehicleId: vehicleId,
            timestamp: FirestoreDecode.date(data["timestamp"]),
            odometerReading: FirestoreDecode.double(data["odometer_reading"]),
            serviceType: FirestoreDecode.string(data["service_type"], fallback: "service"),
            description: data["description"] as? String,
            cost: data["cost"] == nil ? nil : FirestoreDecode.optionalDouble(data["cost"]),
            currency: FirestoreDecode.string(data["currency"], fallback: "QAR"),
            nextServiceOdometer: data["next_service_odometer"] == nil ? nil : FirestoreDecode.optionalDouble(data["next_service_odometer"]),
            nextServiceDate: data["next_service_date"] == nil ? nil : FirestoreDecode.date(data["next_service_date"])
        )
    }
}

extension UserDocument {
    static func from(userId: String, data: [String: Any]) -> UserDocument {
        let profileData = data["profile"] as? [String: Any] ?? [:]
        let current = data["currentVehicleId"]
        let currentId: String? = {
            if current is NSNull || current == nil { return nil }
            let s = FirestoreDecode.string(current)
            return s.isEmpty ? nil : s
        }()

        return UserDocument(
            userId: userId,
            profile: UserProfile(
                userName: FirestoreDecode.string(profileData["userName"]),
                defaultCurrency: FirestoreDecode.string(profileData["defaultCurrency"], fallback: "QAR"),
                defaultDistanceUnit: FirestoreDecode.string(profileData["defaultDistanceUnit"], fallback: "km")
            ),
            currentVehicleId: currentId
        )
    }
}
