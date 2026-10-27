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
    /// Optional paint id (`VehiclePaintColor.rawValue`). Nil / unknown → brand lime.
    var paintColor: String?
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
    /// Optional parts brand (e.g. tire maker on “New Tires”).
    var brand: String?
    var cost: Double?
    var currency: String
    var nextServiceOdometer: Double?
    var nextServiceDate: Date?
}

struct TripCoordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
}

/// Who was behind the wheel. New drives only ever store `driver` or `passenger`;
/// `otherCar` is the legacy value from when "which car" was folded into the role.
enum TripRole: String, Codable, Equatable {
    case driver
    case passenger
    /// Legacy: you drove a car that isn't in the garage.
    case otherCar

    var label: String {
        switch self {
        case .driver: "Driver"
        case .passenger: "Passenger"
        case .otherCar: "Driver"
        }
    }
}

/// Which vehicle moved. Independent of who drove: your wife driving your car is
/// still your car's kilometres; you riding in an Uber never are.
enum TripVehicle: String, Codable, Equatable {
    /// One of your garage cars — its odometer and fuel follow these drives.
    case garage
    /// A rental, a friend's car, a taxi — anything not in your garage.
    case other

    var label: String {
        switch self {
        case .garage: "My car"
        case .other: "Another vehicle"
        }
    }
}

/// The two facts a drive review asks for, and what each combination means.
enum TripContext {
    static func countsAsDriven(role: TripRole) -> Bool { role != .passenger }

    /// Legacy rows have no stored vehicle: "driver" meant a garage car, anything else meant "keep it off my car".
    static func vehicle(stored: String?, role: TripRole) -> TripVehicle {
        if let stored, let known = TripVehicle(rawValue: stored) { return known }
        return role == .driver ? .garage : .other
    }

    /// What to pre-select when reviewing a drive.
    struct Suggestion: Equatable {
        var role: TripRole
        var vehicle: TripVehicle
        /// When the earlier drive this follows ended — nil when it's just the default.
        var followsDriveEndedAt: Date?
    }

    /// A rental stays a rental for the day: if the last drive you made was in another vehicle
    /// within `stickyWindow`, the next one defaults to it too. Riding as a passenger or someone
    /// else driving your car are one-offs, so they never carry over.
    static let stickyWindow: TimeInterval = 18 * 3_600

    static func suggest(startedAt: Date, recentTrips: [Trip]) -> Suggestion {
        let previous = recentTrips
            .filter { $0.endedAt <= startedAt && startedAt.timeIntervalSince($0.endedAt) <= stickyWindow }
            .max { $0.endedAt < $1.endedAt }
        if let previous, previous.tripVehicle == .other, previous.countsAsDriven {
            return Suggestion(role: .driver, vehicle: .other, followsDriveEndedAt: previous.endedAt)
        }
        return Suggestion(role: .driver, vehicle: .garage, followsDriveEndedAt: nil)
    }

    /// Short note for list rows and chips; nil for the ordinary case (you, your car).
    static func note(role: TripRole, vehicle: TripVehicle) -> String? {
        switch (role == .passenger, vehicle) {
        case (false, .garage): nil
        case (true, .garage): "Someone else drove"
        case (false, .other): "Another vehicle"
        case (true, .other): "Passenger · another vehicle"
        }
    }
}

/// Time spent in each speed band. Counts are GPS samples; an empty set falls back to avg/max.
enum SpeedBands {
    static let labels = ["<50", "50–80", "80–110", "110–160", "160+"]

    static func index(for kmh: Double) -> Int {
        if kmh < 50 { return 0 }
        if kmh < 80 { return 1 }
        if kmh < 110 { return 2 }
        if kmh < 160 { return 3 }
        return 4
    }

    static func fractions(counts: [Int], avgKmh: Double, maxKmh: Double) -> [Double] {
        let padded = (counts + [0, 0, 0, 0, 0]).prefix(5)
        let total = padded.reduce(0, +)
        if total > 0 {
            return padded.map { Double($0) / Double(total) }
        }
        return estimated(avgKmh: avgKmh, maxKmh: max(maxKmh, avgKmh))
    }

    /// Older drives have no sample histogram. Shape one around the recorded average and top speed.
    private static func estimated(avgKmh: Double, maxKmh: Double) -> [Double] {
        var weights = [Double](repeating: 0.04, count: 5)
        let avg = index(for: avgKmh)
        let top = index(for: maxKmh)
        weights[avg] += 0.62
        if avg > 0 { weights[avg - 1] += 0.14 }
        if avg < 4 { weights[avg + 1] += 0.1 }
        if top != avg { weights[top] += 0.16 }
        let sum = weights.reduce(0, +)
        return weights.map { $0 / max(sum, 0.001) }
    }
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
    /// Who drove: "driver" or "passenger" ("otherCar" on drives saved before the split).
    var role: String = TripRole.driver.rawValue
    /// Five speed-band sample counts. Empty on trips recorded before the histogram.
    var speedBuckets: [Int] = []
    /// Which vehicle: "garage" or "other". Nil on drives saved before the split.
    var vehicleKind: String? = nil

    var tripRole: TripRole { TripRole(rawValue: role) ?? .driver }
    var tripVehicle: TripVehicle { TripContext.vehicle(stored: vehicleKind, role: tripRole) }
    /// You were behind the wheel — counts toward your driving stats, in any car.
    var countsAsDriven: Bool { TripContext.countsAsDriven(role: tripRole) }
    /// A garage car moved these kilometres (whoever drove) — its odometer and fuel follow them.
    var countsOnVehicle: Bool { tripVehicle == .garage }
    /// "Someone else drove", "Another vehicle"… nil for the ordinary case.
    var contextNote: String? { TripContext.note(role: tripRole, vehicle: tripVehicle) }
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
            source: FirestoreDecode.string(data["source"], fallback: "manual"),
            role: FirestoreDecode.string(data["role"], fallback: TripRole.driver.rawValue),
            speedBuckets: FirestoreDecode.intArray(data["speedBuckets"]),
            vehicleKind: {
                let value = FirestoreDecode.string(data["vehicleKind"])
                return value.isEmpty ? nil : value
            }()
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

    static func intArray(_ any: Any?) -> [Int] {
        guard let values = any as? [Any] else { return [] }
        return values.map { Int(double($0).rounded()) }
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

    static func optionalDate(_ any: Any?) -> Date? {
        guard let any, !(any is NSNull) else { return nil }
        if let timestamp = any as? Timestamp { return timestamp.dateValue() }
        if let date = any as? Date { return date }
        return nil
    }

    static func int(_ any: Any?, fallback: Int = 0) -> Int {
        if let number = any as? NSNumber { return number.intValue }
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let text = any as? String, let value = Int(text) { return value }
        return fallback
    }

    static func stringArray(_ any: Any?) -> [String] {
        (any as? [Any])?.compactMap { string($0) }.filter { !$0.isEmpty } ?? []
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
            paintColor: data["paintColor"] as? String,
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
    /// Most-common first. Stored as plain strings, so older entries keep working.
    static let knownTypes = [
        "Oil Change", "Tire Rotation", "Wheel Alignment", "New Tires", "Brake Service",
        "Air Filter", "Cabin Filter", "AC Service", "Battery Replacement", "Wiper Blades",
        "Spark Plugs", "Coolant Flush", "Brake Fluid", "Transmission Service", "Timing Belt",
        "General Inspection", "Registration", "Other"
    ]

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
            brand: {
                let value = FirestoreDecode.string(data["brand"])
                return value.isEmpty ? nil : value
            }(),
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

enum RoadmapStatus: String, CaseIterable, Identifiable, Hashable {
    case upcoming
    case planned
    case released

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .planned: return "Planned"
        case .released: return "Released"
        }
    }
}

struct RoadmapItem: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var status: RoadmapStatus
    var voteCount: Int
    var createdAt: Date
    var releasedAt: Date?
    var sourceRequestId: String?

    static func from(document id: String, data: [String: Any]) -> RoadmapItem {
        RoadmapItem(
            id: id,
            title: FirestoreDecode.string(data["title"], fallback: "Feature"),
            detail: FirestoreDecode.string(data["detail"]),
            status: RoadmapStatus(rawValue: FirestoreDecode.string(data["status"])) ?? .upcoming,
            voteCount: max(0, FirestoreDecode.int(data["voteCount"])),
            createdAt: FirestoreDecode.date(data["createdAt"]),
            releasedAt: FirestoreDecode.optionalDate(data["releasedAt"]),
            sourceRequestId: {
                let value = FirestoreDecode.string(data["sourceRequestId"])
                return value.isEmpty ? nil : value
            }()
        )
    }
}

struct FeatureRequest: Identifiable, Hashable {
    enum Status: String, Hashable {
        case open
        case promoted
        case declined
    }

    var id: String
    var userId: String
    var authorName: String
    var title: String
    var detail: String
    var createdAt: Date
    var status: Status
    var promotedItemId: String?

    static func from(document id: String, data: [String: Any]) -> FeatureRequest {
        FeatureRequest(
            id: id,
            userId: FirestoreDecode.string(data["userId"]),
            authorName: FirestoreDecode.string(data["authorName"], fallback: "Driver"),
            title: FirestoreDecode.string(data["title"], fallback: "Request"),
            detail: FirestoreDecode.string(data["detail"]),
            createdAt: FirestoreDecode.date(data["createdAt"]),
            status: Status(rawValue: FirestoreDecode.string(data["status"])) ?? .open,
            promotedItemId: {
                let value = FirestoreDecode.string(data["promotedItemId"])
                return value.isEmpty ? nil : value
            }()
        )
    }
}

struct ProductFeedback: Identifiable, Hashable {
    var id: String
    var userId: String
    var authorName: String
    var message: String
    var createdAt: Date
}

struct ModeratorConfig {
    var emails: Set<String>
    var userIds: Set<String>

    static func from(data: [String: Any]?) -> ModeratorConfig {
        let emails = FirestoreDecode.stringArray(data?["emails"]).map { $0.lowercased() }
        let userIds = FirestoreDecode.stringArray(data?["userIds"])
        return ModeratorConfig(emails: Set(emails), userIds: Set(userIds))
    }
}

enum ProductModeration {
    /// Owner accounts that can moderate even before `appConfig/moderators` exists.
    static let ownerEmails: Set<String> = [
        "mfaizanattique@gmail.com",
        "mfaizanatiq@outlook.com.qa"
    ]

    static func isModerator(email: String?, userId: String?, config: ModeratorConfig?) -> Bool {
        if let email {
            let normalized = email.lowercased()
            if ownerEmails.contains(normalized) { return true }
            if config?.emails.contains(normalized) == true { return true }
        }
        if let userId, config?.userIds.contains(userId) == true { return true }
        return false
    }
}

/// Typical intervals and "what's due next" across a car's service history.
enum ServiceSchedule {
    struct Interval: Equatable {
        var km: Double?
        var months: Int?
    }

    /// Common-sense defaults — the owner's manual always wins, so these only prefill.
    static func suggestedInterval(for type: String) -> Interval? {
        switch type {
        case "Oil Change": Interval(km: 10_000, months: 12)
        case "Tire Rotation": Interval(km: 10_000, months: nil)
        case "Wheel Alignment": Interval(km: 20_000, months: 12)
        case "New Tires": Interval(km: 50_000, months: 60)
        case "Brake Service": Interval(km: 30_000, months: 24)
        case "Air Filter": Interval(km: 20_000, months: 24)
        case "Cabin Filter": Interval(km: 15_000, months: 12)
        case "AC Service": Interval(km: nil, months: 12)
        case "Battery Replacement": Interval(km: nil, months: 36)
        case "Wiper Blades": Interval(km: nil, months: 12)
        case "Spark Plugs": Interval(km: 50_000, months: nil)
        case "Coolant Flush": Interval(km: 50_000, months: 36)
        case "Brake Fluid": Interval(km: nil, months: 24)
        case "Transmission Service": Interval(km: 60_000, months: nil)
        case "Timing Belt": Interval(km: 100_000, months: 72)
        case "General Inspection", "Registration": Interval(km: nil, months: 12)
        default: nil
        }
    }

    /// Picker sections — every known type appears exactly once.
    static let groups: [(title: String, types: [String])] = [
        ("Routine", ["Oil Change", "Tire Rotation", "Air Filter", "Cabin Filter", "Wiper Blades", "General Inspection"]),
        ("Tires & brakes", ["New Tires", "Wheel Alignment", "Brake Service", "Brake Fluid"]),
        ("Engine & drivetrain", ["Spark Plugs", "Coolant Flush", "Transmission Service", "Timing Belt"]),
        ("Electrical & comfort", ["Battery Replacement", "AC Service"]),
        ("Paperwork", ["Registration"]),
        ("Something else", ["Other"])
    ]

    /// "Every 10,000 km or 1 year" — nil when there's no sensible default.
    static func intervalSummary(for type: String) -> String? {
        guard let interval = suggestedInterval(for: type) else { return nil }
        let parts = [
            interval.km.map { DistanceFormat.formatOdometer($0, unit: "km") },
            interval.months.map { $0 % 12 == 0 ? "\($0 / 12) year\($0 == 12 ? "" : "s")" : "\($0) months" }
        ].compactMap { $0 }
        return "Every " + parts.joined(separator: " or ")
    }

    enum Status: Equatable { case onTrack, dueSoon, overdue }

    struct NextUp: Equatable {
        var log: ServiceLog
        var kmLeft: Double?
        var daysLeft: Int?
        /// 0…1 of the way from that service to its reminder.
        var progress: Double
        var status: Status
    }

    /// Rough km/day used to compare a km reminder with a date reminder.
    static let assumedDailyKm: Double = 40

    /// The most urgent reminder, using only the latest entry of each service type.
    static func nextUp(
        logs: [ServiceLog],
        currentKm: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NextUp? {
        var latestByType: [String: ServiceLog] = [:]
        for log in logs where (latestByType[log.serviceType]?.timestamp ?? .distantPast) < log.timestamp {
            latestByType[log.serviceType] = log
        }

        let candidates: [(NextUp, urgency: Double)] = latestByType.values.compactMap { log in
            let kmLeft = log.nextServiceOdometer.map { $0 - currentKm }
            let daysLeft = log.nextServiceDate.map {
                calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: $0)).day ?? 0
            }
            guard kmLeft != nil || daysLeft != nil else { return nil }

            let kmProgress: Double? = log.nextServiceOdometer.flatMap { next in
                let span = next - log.odometerReading
                return span > 0 ? (currentKm - log.odometerReading) / span : nil
            }
            let dateProgress: Double? = log.nextServiceDate.flatMap { due in
                let span = due.timeIntervalSince(log.timestamp)
                return span > 0 ? now.timeIntervalSince(log.timestamp) / span : nil
            }
            let progress = min(max([kmProgress, dateProgress].compactMap { $0 }.max() ?? 0, 0), 1)

            let overdue = (kmLeft ?? 1) < 0 || (daysLeft ?? 1) < 0
            let soon = (kmLeft.map { $0 <= 500 } ?? false) || (daysLeft.map { $0 <= 14 } ?? false)
            let urgency = min(kmLeft.map { $0 / assumedDailyKm } ?? .infinity, daysLeft.map(Double.init) ?? .infinity)
            return (
                NextUp(
                    log: log,
                    kmLeft: kmLeft,
                    daysLeft: daysLeft,
                    progress: progress,
                    status: overdue ? .overdue : (soon ? .dueSoon : .onTrack)
                ),
                urgency
            )
        }
        return candidates.min { $0.urgency < $1.urgency }?.0
    }
}
