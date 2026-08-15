import Foundation

enum CurrencyFormat {
    static let symbols: [String: String] = [
        "QAR": "QR", "AED": "د.إ", "SAR": "﷼", "OMR": "ر.ع.",
        "BHD": ".د.ب", "KWD": "د.ك", "JOD": "د.ا", "EGP": "£",
        "ILS": "₪", "USD": "$", "EUR": "€", "GBP": "£",
        "PKR": "₨", "INR": "₹"
    ]

    static func format(_ amount: Double, currency: String = "QAR") -> String {
        let symbol = symbols[currency] ?? currency
        return String(format: "%@%.2f", symbol, amount)
    }
}

enum DistanceFormat {
    static func formatOdometer(_ km: Double, unit: String) -> String {
        if unit == "mi" {
            return String(format: "%.0f mi", km * 0.621371)
        }
        return String(format: "%.0f km", km)
    }

    static func formatDistance(_ km: Double, unit: String) -> String {
        if unit == "mi" {
            let mi = km * 0.621371
            return String(format: mi >= 100 ? "%.0f mi" : "%.1f mi", mi)
        }
        return String(format: km >= 100 ? "%.0f km" : "%.1f km", km)
    }
}

/// Fuel volume display/entry. Canonical storage is always litres.
enum VolumeFormat {
    static let liters = "L"
    static let gallons = "gal"
    /// US liquid gallon.
    private static let litersPerGallon = 3.785411784

    static func normalize(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "l", "liter", "liters", "litre", "litres": return liters
        case "gal", "gallon", "gallons", "us_gal", "us-gal": return gallons
        default: return nil
        }
    }

    static func defaultUnit(currency: String) -> String {
        switch currency.uppercased() {
        case "USD", "CAD": return gallons
        default:
            if Locale.current.measurementSystem == .us { return gallons }
            return liters
        }
    }

    static func usesGallons(_ unit: String) -> Bool {
        normalize(unit) == gallons
    }

    static func suffix(_ unit: String) -> String {
        usesGallons(unit) ? "gal" : "L"
    }

    static func label(_ unit: String) -> String {
        usesGallons(unit) ? "Gallons" : "Litres"
    }

    static func toDisplay(_ litersValue: Double, unit: String) -> Double {
        usesGallons(unit) ? litersValue / litersPerGallon : litersValue
    }

    static func toLiters(_ displayValue: Double, unit: String) -> Double {
        usesGallons(unit) ? displayValue * litersPerGallon : displayValue
    }

    static func format(_ litersValue: Double, unit: String, decimals: Int = 1) -> String {
        let value = toDisplay(litersValue, unit: unit)
        return String(format: "%.\(decimals)f %@", value, suffix(unit))
    }

    static func formatTank(_ litersValue: Double?, unit: String) -> String {
        guard let litersValue else { return "—" }
        let value = toDisplay(litersValue, unit: unit)
        return String(format: "%.0f %@", value, suffix(unit))
    }

    static func pricePerUnitLabel(currency: String, unit: String) -> String {
        let symbol = CurrencyFormat.symbols[currency] ?? currency
        return "\(symbol) / \(suffix(unit))"
    }
}

struct EfficiencyMetrics {
    let current: Double?
    let monthlySpend: Double
    let spendChange: Double?
    let avgEfficiency: Double?
    let totalDistance: Double
    let refuelCount: Int
    let efficiencySampleCount: Int
    let recentLogs: [FuelLog]
}

enum MetricsCalculator {
    static func compute(vehicle: Vehicle, logs: [FuelLog], now: Date = Date()) -> EfficiencyMetrics {
        let vehicleLogs = logs
            .filter { $0.vehicleId == vehicle.id }
            .sorted { $0.timestamp < $1.timestamp }

        let intervals = fullTankIntervals(in: vehicleLogs)
        // A rolling, distance-weighted result is less sensitive to one unusual fill
        // than comparing the brochure against only the latest interval.
        let recentIntervals = intervals.suffix(3)
        let recentDistance = recentIntervals.reduce(0) { $0 + $1.distance }
        let recentFuel = recentIntervals.reduce(0) { $0 + $1.fuel }
        let current = recentDistance > 0 ? (recentFuel / recentDistance) * 100 : nil

        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfMonth) ?? now
        let endOfLastMonth = cal.date(byAdding: .day, value: -1, to: startOfMonth) ?? now

        let monthLogs = vehicleLogs.filter { $0.timestamp >= startOfMonth }
        let lastMonthLogs = vehicleLogs.filter { $0.timestamp >= startOfLastMonth && $0.timestamp <= endOfLastMonth }

        let totalSpent = monthLogs.reduce(0) { $0 + $1.totalCost }
        let lastSpent = lastMonthLogs.reduce(0) { $0 + $1.totalCost }
        let spendChange = lastSpent > 0 ? ((totalSpent - lastSpent) / lastSpent) * 100 : nil

        // Attribute a fill-to-fill interval to the month in which its closing fill occurred.
        // This excludes the first fill (which has no measured distance) and all partial fills.
        let monthIntervals = intervals.filter { $0.endedAt >= startOfMonth }
        let totalDistance = monthIntervals.reduce(0) { $0 + $1.distance }
        let intervalFuel = monthIntervals.reduce(0) { $0 + $1.fuel }
        let avgEfficiency = totalDistance > 0 ? (intervalFuel / totalDistance) * 100 : nil

        let recent = Array(vehicleLogs.reversed().prefix(5))

        return EfficiencyMetrics(
            current: current,
            monthlySpend: totalSpent,
            spendChange: spendChange,
            avgEfficiency: avgEfficiency,
            totalDistance: totalDistance,
            refuelCount: monthLogs.count,
            efficiencySampleCount: intervals.count,
            recentLogs: recent
        )
    }

    private struct FullTankInterval {
        let endedAt: Date
        let distance: Double
        let fuel: Double
    }

    private static func fullTankIntervals(in logs: [FuelLog]) -> [FullTankInterval] {
        guard logs.count >= 2 else { return [] }
        var result: [FullTankInterval] = []
        var anchor: FuelLog?
        var fuelSinceAnchor = 0.0

        for log in logs {
            guard log.fuelVolume > 0 else { continue }
            guard let currentAnchor = anchor else {
                if log.isFullTank { anchor = log }
                continue
            }

            fuelSinceAnchor += log.fuelVolume
            guard log.isFullTank else { continue }
            let distance = log.odometerReading - currentAnchor.odometerReading
            if distance > 0 {
                result.append(FullTankInterval(endedAt: log.timestamp, distance: distance, fuel: fuelSinceAnchor))
            }
            anchor = log
            fuelSinceAnchor = 0
        }
        return result
    }
}

struct EfficiencyVibe {
    let label: String
    let emoji: String
    let tone: Tone

    enum Tone: Equatable { case excellent, good, neutral, watch, learning }
}

enum DashboardCopy {
    static func vibe(efficiency: Double?, standard: Double?, refuelCount: Int) -> EfficiencyVibe {
        guard let efficiency, refuelCount >= 2 else {
            return EfficiencyVibe(label: "Getting to know your car", emoji: "👋", tone: .learning)
        }
        guard let standard else {
            if efficiency < 7 { return EfficiencyVibe(label: "Running lean", emoji: "⚡", tone: .good) }
            if efficiency < 10 { return EfficiencyVibe(label: "Steady cruiser", emoji: "🛣️", tone: .neutral) }
            return EfficiencyVibe(label: "Thirsty lately", emoji: "💧", tone: .watch)
        }
        let deviation = ((efficiency - standard) / standard) * 100
        if deviation <= -10 { return EfficiencyVibe(label: "Efficiency legend", emoji: "🏆", tone: .excellent) }
        if deviation <= 0 { return EfficiencyVibe(label: "Beating the brochure", emoji: "✨", tone: .excellent) }
        if deviation <= 10 { return EfficiencyVibe(label: "Smooth operator", emoji: "🎯", tone: .good) }
        if deviation <= 20 { return EfficiencyVibe(label: "Room to tune up", emoji: "🔧", tone: .neutral) }
        return EfficiencyVibe(label: "Needs some love", emoji: "🩺", tone: .watch)
    }

    static func status(efficiency: Double?, standard: Double?, sampleCount: Int) -> (text: String, tone: EfficiencyVibe.Tone) {
        guard let efficiency else {
            return ("Fill up so we can compare", .learning)
        }
        guard sampleCount >= 2 else {
            return ("One more full tank to lock it in", .learning)
        }
        guard let standard else { return ("No brochure spec on file", .learning) }
        let deviation = ((efficiency - standard) / standard) * 100
        let abs = Int(abs(deviation).rounded())
        if deviation <= 0 { return ("\(abs)% better than brochure", .excellent) }
        if deviation <= 15 { return ("\(abs)% thirstier than brochure", .good) }
        if deviation <= 25 { return ("\(abs)% above brochure", .neutral) }
        return ("\(abs)% thirsty — worth a peek", .watch)
    }

    static func spendTrend(_ change: Double?) -> String {
        guard let change else { return "First month on the board" }
        if abs(change) < 1 { return "Holding steady" }
        let absVal = Int(abs(change).rounded())
        return change < 0 ? "↓ \(absVal)% vs last month" : "↑ \(absVal)% vs last month"
    }
}

struct PersonalHighlight: Identifiable {
    let id: String
    let emoji: String
    let label: String
    let value: String
}

struct DriverAchievement: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case road, fuel, efficiency, habit

        var label: String {
            switch self {
            case .road: return "Road"
            case .fuel: return "Fuel"
            case .efficiency: return "Efficiency"
            case .habit: return "Habits"
            }
        }
    }

    let id: String
    let emoji: String
    let title: String
    let detail: String
    let unlocked: Bool
    let category: Category
    /// 0...1 toward unlock (1 when earned).
    let progress: Double
    /// e.g. "7 / 10 fills"
    let progressLabel: String
    /// First moment the threshold was crossed, when we can infer it.
    let unlockedAt: Date?

    var achievedOnLabel: String? {
        guard unlocked, let unlockedAt else { return nil }
        return unlockedAt.formatted(date: .long, time: .omitted)
    }

    var shareCaption: String {
        if let achievedOnLabel {
            return "Unlocked \(title) on Veloseete — \(detail). \(achievedOnLabel)."
        }
        return "Unlocked \(title) on Veloseete — \(detail)."
    }
}

struct FunInsight: Identifiable {
    enum Kind { case celebrate, tip, watch }
    var id: String { title }
    let kind: Kind
    let emoji: String
    let title: String
    let message: String
}

enum InsightGenerator {
    /// Lifetime GPS trip distance, falling back to odometer span from fuel logs.
    static func totalKilometersDriven(trips: [Trip], logs: [FuelLog], vehicleId: String?) -> Double {
        let tripKm = trips
            .filter { vehicleId == nil || $0.vehicleId == vehicleId }
            .reduce(0) { $0 + max(0, $1.distanceKm) }

        let vehicleLogs = logs
            .filter { vehicleId == nil || $0.vehicleId == vehicleId }
            .sorted { $0.timestamp < $1.timestamp }
        let odoSpan: Double = {
            guard let first = vehicleLogs.first, let last = vehicleLogs.last else { return 0 }
            return max(0, last.odometerReading - first.odometerReading)
        }()

        return max(tripKm, odoSpan)
    }

    static func achievements(
        trips: [Trip],
        logs: [FuelLog],
        serviceLogs: [ServiceLog] = [],
        vehicleCount: Int = 1,
        vehicleCreatedDates: [Date] = [],
        vehicleId: String?,
        unit: String,
        manufacturerStandard: Double?
    ) -> [DriverAchievement] {
        let scopedTrips = trips.filter { vehicleId == nil || $0.vehicleId == vehicleId }
        let vehicleLogs = logs
            .filter { vehicleId == nil || $0.vehicleId == vehicleId }
            .sorted { $0.timestamp < $1.timestamp }
        let scopedServices = serviceLogs.filter { vehicleId == nil || $0.vehicleId == vehicleId }

        let totalKm = totalKilometersDriven(trips: trips, logs: logs, vehicleId: vehicleId)
        let driveCount = scopedTrips.count
        let longestTrip = scopedTrips.map(\.distanceKm).max() ?? 0
        let topSpeed = scopedTrips.map(\.maxSpeedKmh).max() ?? 0
        let fillCount = vehicleLogs.count
        let fullTankCount = vehicleLogs.filter(\.isFullTank).count
        let currencyCount = Set(vehicleLogs.map(\.currency)).count
        let gulfCurrencies = Set(vehicleLogs.map(\.currency)).intersection(["AED", "SAR", "QAR"])

        var bestEfficiency: Double?
        var longestFillStretch = 0.0
        var efficiencyIntervals: [Double] = []
        for index in 1..<vehicleLogs.count {
            let previous = vehicleLogs[index - 1]
            let current = vehicleLogs[index]
            let stretch = current.odometerReading - previous.odometerReading
            if stretch > longestFillStretch { longestFillStretch = stretch }
            guard current.isFullTank, previous.isFullTank else { continue }
            guard stretch > 0, current.fuelVolume > 0 else { continue }
            let efficiency = (current.fuelVolume / stretch) * 100
            efficiencyIntervals.append(efficiency)
            if bestEfficiency == nil || efficiency < bestEfficiency! {
                bestEfficiency = efficiency
            }
        }

        let activeMonths = Set(vehicleLogs.map {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.timestamp)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }).count

        let beatsSpec = bestEfficiency.map { efficiency in
            manufacturerStandard.map { efficiency <= $0 } ?? false
        } ?? false

        let avgEfficiency: Double? = {
            guard !efficiencyIntervals.isEmpty else { return nil }
            return efficiencyIntervals.reduce(0, +) / Double(efficiencyIntervals.count)
        }()

        let efficientKing: Bool = {
            if let manufacturerStandard, let avgEfficiency {
                return avgEfficiency <= manufacturerStandard * 0.95
            }
            return bestEfficiency.map { $0 <= 7.5 } ?? false
        }()

        let calendar = Calendar.current
        let earlyBirdDrives = scopedTrips.filter { calendar.component(.hour, from: $0.startedAt) < 7 }.count
        let nightOwlDrives = scopedTrips.filter { calendar.component(.hour, from: $0.startedAt) >= 22 }.count
        let weekendDrives = scopedTrips.filter { calendar.isDateInWeekend($0.startedAt) }.count
        // Meal-window “destination runs” until we store real places/restaurants.
        let mealRuns = scopedTrips.filter { trip in
            let hour = calendar.component(.hour, from: trip.startedAt)
            let mealWindow = (hour >= 11 && hour <= 14) || (hour >= 18 && hour <= 21)
            return mealWindow && trip.distanceKm >= 15
        }.count

        let roadHours = scopedTrips.reduce(0) { $0 + max(0, $1.durationSec) } / 3600
        let tripDates = scopedTrips.map(\.startedAt).sorted()
        let fillDates = vehicleLogs.map(\.timestamp)
        let fullTankDates = vehicleLogs.filter(\.isFullTank).map(\.timestamp)
        let serviceDates = scopedServices.map(\.timestamp).sorted()
        let vehicleDates = vehicleCreatedDates.sorted()

        func nthDate(_ dates: [Date], _ n: Int) -> Date? {
            guard n > 0, dates.count >= n else { return nil }
            return dates[n - 1]
        }

        func nthTrip(where pred: (Trip) -> Bool, n: Int) -> Date? {
            nthDate(scopedTrips.filter(pred).map(\.startedAt).sorted(), n)
        }

        func firstTrip(where pred: (Trip) -> Bool) -> Date? {
            nthTrip(where: pred, n: 1)
        }

        func dateWhenDistance(_ target: Double) -> Date? {
            var acc = 0.0
            for trip in scopedTrips.sorted(by: { $0.startedAt < $1.startedAt }) {
                acc += max(0, trip.distanceKm)
                if acc >= target { return trip.startedAt }
            }
            guard let origin = vehicleLogs.first?.odometerReading else { return nil }
            for log in vehicleLogs {
                if log.odometerReading - origin >= target { return log.timestamp }
            }
            return nil
        }

        func dateWhenHours(_ target: Double) -> Date? {
            var acc = 0.0
            for trip in scopedTrips.sorted(by: { $0.startedAt < $1.startedAt }) {
                acc += max(0, trip.durationSec) / 3600
                if acc >= target { return trip.endedAt }
            }
            return nil
        }

        func dateWhenNthMonth(_ n: Int) -> Date? {
            var seen = Set<String>()
            for log in vehicleLogs {
                let comps = calendar.dateComponents([.year, .month], from: log.timestamp)
                let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
                if seen.insert(key).inserted, seen.count >= n { return log.timestamp }
            }
            return nil
        }

        func dateWhenFillStretch(_ target: Double) -> Date? {
            for index in 1..<vehicleLogs.count {
                let stretch = vehicleLogs[index].odometerReading - vehicleLogs[index - 1].odometerReading
                if stretch >= target { return vehicleLogs[index].timestamp }
            }
            return nil
        }

        func dateWhenCurrencies(target: Int, allowed: Set<String>? = nil) -> Date? {
            var seen = Set<String>()
            for log in vehicleLogs {
                if let allowed, !allowed.contains(log.currency) { continue }
                if seen.insert(log.currency).inserted, seen.count >= target {
                    return log.timestamp
                }
            }
            return nil
        }

        func eachFullTankEfficiency(_ body: (Date, Double) -> Bool) -> Date? {
            for index in 1..<vehicleLogs.count {
                let previous = vehicleLogs[index - 1]
                let current = vehicleLogs[index]
                guard current.isFullTank, previous.isFullTank else { continue }
                let stretch = current.odometerReading - previous.odometerReading
                guard stretch > 0, current.fuelVolume > 0 else { continue }
                let efficiency = (current.fuelVolume / stretch) * 100
                if body(current.timestamp, efficiency) { return current.timestamp }
            }
            return nil
        }

        func dateWhenBestTank() -> Date? {
            var best: Double?
            var when: Date?
            _ = eachFullTankEfficiency { date, efficiency in
                if best == nil || efficiency < best! {
                    best = efficiency
                    when = date
                }
                return false
            }
            return when
        }

        func dateWhenEfficiency(_ predicate: (Double) -> Bool) -> Date? {
            eachFullTankEfficiency { _, efficiency in predicate(efficiency) }
        }

        func dateWhenAvgBeatsSpec() -> Date? {
            guard let manufacturerStandard, manufacturerStandard > 0 else {
                return dateWhenEfficiency { $0 <= 7.5 }
            }
            let goal = manufacturerStandard * 0.95
            var values: [Double] = []
            return eachFullTankEfficiency { _, efficiency in
                values.append(efficiency)
                let avg = values.reduce(0, +) / Double(values.count)
                return avg <= goal
            }
        }

        func quest(
            id: String,
            emoji: String,
            title: String,
            category: DriverAchievement.Category,
            current: Double,
            target: Double,
            unitLabel: String,
            earnedDetail: String,
            lockedDetail: String,
            unlockedAt: Date? = nil
        ) -> DriverAchievement {
            let safeTarget = max(target, 0.0001)
            let progress = min(max(current / safeTarget, 0), 1)
            let unlocked = current >= target
            let progressLabel: String = {
                if target >= 10, target == floor(target), current == floor(current) {
                    return "\(Int(min(current, target))) / \(Int(target)) \(unitLabel)"
                }
                if unitLabel == "km" {
                    return "\(DistanceFormat.formatDistance(min(current, target), unit: unit)) / \(DistanceFormat.formatDistance(target, unit: unit))"
                }
                return String(format: "%.0f / %.0f %@", min(current, target), target, unitLabel)
            }()
            return DriverAchievement(
                id: id,
                emoji: emoji,
                title: title,
                detail: unlocked ? earnedDetail : lockedDetail,
                unlocked: unlocked,
                category: category,
                progress: progress,
                progressLabel: progressLabel,
                unlockedAt: unlocked ? unlockedAt : nil
            )
        }

        return [
            // MARK: Road quests
            quest(
                id: "first-drive", emoji: "👋", title: "First drive", category: .road,
                current: Double(driveCount), target: 1, unitLabel: "drives",
                earnedDetail: "You’re on the board",
                lockedDetail: "Complete your first tracked drive",
                unlockedAt: nthDate(tripDates, 1)
            ),
            quest(
                id: "ten-trips", emoji: "🚗", title: "Trip taker", category: .road,
                current: Double(driveCount), target: 10, unitLabel: "drives",
                earnedDetail: "\(driveCount) drives logged",
                lockedDetail: "Log 10 tracked drives",
                unlockedAt: nthDate(tripDates, 10)
            ),
            quest(
                id: "twenty-five-trips", emoji: "🛣", title: "Road regular", category: .road,
                current: Double(driveCount), target: 25, unitLabel: "drives",
                earnedDetail: "\(driveCount) drives in the book",
                lockedDetail: "Hit 25 tracked drives",
                unlockedAt: nthDate(tripDates, 25)
            ),
            quest(
                id: "hundred-club", emoji: "🛣", title: "100 km club", category: .road,
                current: totalKm, target: 100, unitLabel: "km",
                earnedDetail: DistanceFormat.formatDistance(totalKm, unit: unit) + " lifetime",
                lockedDetail: "Reach 100 km of tracked driving",
                unlockedAt: dateWhenDistance(100)
            ),
            quest(
                id: "five-hundred-roads", emoji: "🎯", title: "500 km explorer", category: .road,
                current: totalKm, target: 500, unitLabel: "km",
                earnedDetail: DistanceFormat.formatDistance(totalKm, unit: unit) + " explored",
                lockedDetail: "Push lifetime distance to 500 km",
                unlockedAt: dateWhenDistance(500)
            ),
            quest(
                id: "thousand-roads", emoji: "🏆", title: "1,000 km roads", category: .road,
                current: totalKm, target: 1_000, unitLabel: "km",
                earnedDetail: DistanceFormat.formatDistance(totalKm, unit: unit) + " lifetime",
                lockedDetail: "Keep rolling toward 1,000 km",
                unlockedAt: dateWhenDistance(1_000)
            ),
            quest(
                id: "five-thousand-roads", emoji: "✨", title: "5,000 km legend", category: .road,
                current: totalKm, target: 5_000, unitLabel: "km",
                earnedDetail: "Highway royalty",
                lockedDetail: "Accumulate 5,000 km tracked",
                unlockedAt: dateWhenDistance(5_000)
            ),
            quest(
                id: "long-haul", emoji: "🎯", title: "Long haul", category: .road,
                current: longestTrip, target: 80, unitLabel: "km",
                earnedDetail: "Longest \(DistanceFormat.formatDistance(longestTrip, unit: unit))",
                lockedDetail: "Track a single 80+ km drive",
                unlockedAt: firstTrip { $0.distanceKm >= 80 }
            ),
            quest(
                id: "marathon-drive", emoji: "⚡", title: "Marathon drive", category: .road,
                current: longestTrip, target: 200, unitLabel: "km",
                earnedDetail: "Longest \(DistanceFormat.formatDistance(longestTrip, unit: unit))",
                lockedDetail: "One drive of 200+ km",
                unlockedAt: firstTrip { $0.distanceKm >= 200 }
            ),
            quest(
                id: "seat-time", emoji: "🚗", title: "Seat time", category: .road,
                current: roadHours, target: 10, unitLabel: "hours",
                earnedDetail: String(format: "%.0f hours behind the wheel", roadHours),
                lockedDetail: "Log 10 hours of tracked driving",
                unlockedAt: dateWhenHours(10)
            ),
            quest(
                id: "early-bird", emoji: "✨", title: "Early bird", category: .road,
                current: Double(earlyBirdDrives), target: 3, unitLabel: "drives",
                earnedDetail: "\(earlyBirdDrives) pre-7am starts",
                lockedDetail: "Start 3 drives before 7am",
                unlockedAt: nthTrip(where: { calendar.component(.hour, from: $0.startedAt) < 7 }, n: 3)
            ),
            quest(
                id: "night-owl", emoji: "⚡", title: "Night owl", category: .road,
                current: Double(nightOwlDrives), target: 3, unitLabel: "drives",
                earnedDetail: "\(nightOwlDrives) late-night runs",
                lockedDetail: "Start 3 drives after 10pm",
                unlockedAt: nthTrip(where: { calendar.component(.hour, from: $0.startedAt) >= 22 }, n: 3)
            ),
            quest(
                id: "weekend-warrior", emoji: "🛣", title: "Weekend warrior", category: .road,
                current: Double(weekendDrives), target: 5, unitLabel: "drives",
                earnedDetail: "\(weekendDrives) weekend drives",
                lockedDetail: "Track 5 weekend drives",
                unlockedAt: nthTrip(where: { calendar.isDateInWeekend($0.startedAt) }, n: 5)
            ),
            quest(
                id: "meal-runs", emoji: "🎯", title: "Meal-run circuit", category: .road,
                current: Double(mealRuns), target: 5, unitLabel: "runs",
                earnedDetail: "\(mealRuns) lunch/dinner hauls",
                lockedDetail: "5 drives of 15+ km in meal hours (restaurant runs)",
                unlockedAt: nthTrip(where: { trip in
                    let hour = calendar.component(.hour, from: trip.startedAt)
                    let mealWindow = (hour >= 11 && hour <= 14) || (hour >= 18 && hour <= 21)
                    return mealWindow && trip.distanceKm >= 15
                }, n: 5)
            ),
            quest(
                id: "pace-noted", emoji: "⚡", title: "Pace noted", category: .road,
                current: topSpeed, target: 120, unitLabel: "km/h",
                earnedDetail: String(format: "Top GPS %.0f km/h", topSpeed),
                lockedDetail: "Hit 120 km/h on a tracked drive",
                unlockedAt: firstTrip { $0.maxSpeedKmh >= 120 }
            ),

            // MARK: Fuel quests
            quest(
                id: "first-fill", emoji: "⛽", title: "First fill", category: .fuel,
                current: Double(fillCount), target: 1, unitLabel: "fills",
                earnedDetail: "Pump logged",
                lockedDetail: "Log your first refuel",
                unlockedAt: nthDate(fillDates, 1)
            ),
            quest(
                id: "five-fills", emoji: "⛽", title: "Pump starter", category: .fuel,
                current: Double(fillCount), target: 5, unitLabel: "fills",
                earnedDetail: "\(fillCount) refuels logged",
                lockedDetail: "Log 5 refuels",
                unlockedAt: nthDate(fillDates, 5)
            ),
            quest(
                id: "ten-fills", emoji: "⛽", title: "Fill ledger", category: .fuel,
                current: Double(fillCount), target: 10, unitLabel: "fills",
                earnedDetail: "\(fillCount) refuels in the book",
                lockedDetail: "Reach 10 refuel entries",
                unlockedAt: nthDate(fillDates, 10)
            ),
            quest(
                id: "twenty-five-fills", emoji: "🏆", title: "Pump regular", category: .fuel,
                current: Double(fillCount), target: 25, unitLabel: "fills",
                earnedDetail: "\(fillCount) fills strong",
                lockedDetail: "Log 25 refuels",
                unlockedAt: nthDate(fillDates, 25)
            ),
            quest(
                id: "fifty-fills", emoji: "✨", title: "Fuel historian", category: .fuel,
                current: Double(fillCount), target: 50, unitLabel: "fills",
                earnedDetail: "Half-century of fills",
                lockedDetail: "Hit 50 refuel logs",
                unlockedAt: nthDate(fillDates, 50)
            ),
            quest(
                id: "full-tank-discipline", emoji: "🎯", title: "Full-tank discipline", category: .fuel,
                current: Double(fullTankCount), target: 10, unitLabel: "full tanks",
                earnedDetail: "\(fullTankCount) full tanks",
                lockedDetail: "Mark 10 fills as full tank",
                unlockedAt: nthDate(fullTankDates, 10)
            ),
            quest(
                id: "fill-stretch", emoji: "🛣", title: "Stretch fill", category: .fuel,
                current: longestFillStretch, target: 400, unitLabel: "km",
                earnedDetail: "\(DistanceFormat.formatDistance(longestFillStretch, unit: unit)) between fills",
                lockedDetail: "Go 400+ km between consecutive fills",
                unlockedAt: dateWhenFillStretch(400)
            ),
            quest(
                id: "currency-hopper", emoji: "✨", title: "Currency hopper", category: .fuel,
                current: Double(currencyCount), target: 2, unitLabel: "currencies",
                earnedDetail: "Filled in \(currencyCount) currencies",
                lockedDetail: "Log fills in 2 different currencies (e.g. QAR + SAR)",
                unlockedAt: dateWhenCurrencies(target: 2)
            ),
            quest(
                id: "gulf-hopper", emoji: "🚗", title: "Gulf hopper", category: .fuel,
                current: Double(gulfCurrencies.count), target: 2, unitLabel: "GCC currencies",
                earnedDetail: "Cross-border fuel trail",
                lockedDetail: "Fill up using 2 GCC currencies (QAR / AED / SAR)",
                unlockedAt: dateWhenCurrencies(target: 2, allowed: ["AED", "SAR", "QAR"])
            ),

            // MARK: Efficiency quests
            quest(
                id: "best-tank", emoji: "🏆", title: "Best tank", category: .efficiency,
                current: bestEfficiency == nil ? 0 : 1, target: 1, unitLabel: "PB",
                earnedDetail: bestEfficiency.map { String(format: "%.1f L/100km personal best", $0) } ?? "Earned",
                lockedDetail: "Log two full tanks to set a personal best",
                unlockedAt: dateWhenBestTank()
            ),
            quest(
                id: "spec-beater", emoji: "✨", title: "Spec beater", category: .efficiency,
                current: beatsSpec ? 1 : 0, target: 1, unitLabel: "win",
                earnedDetail: "Under the factory brochure number",
                lockedDetail: "Beat manufacturer L/100km on a tank",
                unlockedAt: manufacturerStandard.flatMap { spec in dateWhenEfficiency { $0 <= spec } }
            ),
            {
                let kingProgress: Double = {
                    if efficientKing { return 1 }
                    guard let avgEfficiency else { return 0 }
                    if let manufacturerStandard, manufacturerStandard > 0 {
                        let goal = manufacturerStandard * 0.95
                        // Lower avg is better; 0% at 1.3× goal, 100% at goal.
                        let ceiling = goal * 1.3
                        return min(max((ceiling - avgEfficiency) / (ceiling - goal), 0), 0.99)
                    }
                    let goal = 7.5
                    let ceiling = 12.0
                    return min(max((ceiling - avgEfficiency) / (ceiling - goal), 0), 0.99)
                }()
                return DriverAchievement(
                    id: "efficient-king",
                    emoji: "👑",
                    title: "Efficient king",
                    detail: efficientKing
                        ? (avgEfficiency.map { String(format: "Avg %.1f L/100 — throne secured", $0) } ?? "Crowned")
                        : (manufacturerStandard != nil
                            ? "Average ≤ 95% of brochure spec"
                            : "Post a personal best at or under 7.5 L/100"),
                    unlocked: efficientKing,
                    category: .efficiency,
                    progress: kingProgress,
                    progressLabel: avgEfficiency.map { String(format: "Avg %.1f L/100", $0) } ?? "Need full-tank pairs",
                    unlockedAt: efficientKing ? dateWhenAvgBeatsSpec() : nil
                )
            }(),
            {
                let leanUnlocked = bestEfficiency.map { $0 <= 7.0 } ?? false
                let leanProgress: Double = {
                    guard let bestEfficiency else { return 0 }
                    if leanUnlocked { return 1 }
                    let goal = 7.0
                    let ceiling = 12.0
                    return min(max((ceiling - bestEfficiency) / (ceiling - goal), 0), 0.99)
                }()
                return DriverAchievement(
                    id: "lean-machine",
                    emoji: "💧",
                    title: "Lean machine",
                    detail: leanUnlocked
                        ? (bestEfficiency.map { String(format: "Best %.1f L/100km", $0) } ?? "Lean")
                        : "Land a tank at or under 7.0 L/100km",
                    unlocked: leanUnlocked,
                    category: .efficiency,
                    progress: leanProgress,
                    progressLabel: bestEfficiency.map { String(format: "Best %.1f · goal 7.0", $0) } ?? "Need full-tank pairs",
                    unlockedAt: leanUnlocked ? dateWhenEfficiency { $0 <= 7.0 } : nil
                )
            }(),

            // MARK: Habit quests
            quest(
                id: "consistent", emoji: "🔧", title: "Consistent logger", category: .habit,
                current: Double(activeMonths), target: 3, unitLabel: "months",
                earnedDetail: "\(activeMonths) active months",
                lockedDetail: "Log fuel across 3 different months",
                unlockedAt: dateWhenNthMonth(3)
            ),
            quest(
                id: "half-year", emoji: "🏆", title: "Half-year habit", category: .habit,
                current: Double(activeMonths), target: 6, unitLabel: "months",
                earnedDetail: "\(activeMonths) months strong",
                lockedDetail: "Stay active across 6 months",
                unlockedAt: dateWhenNthMonth(6)
            ),
            quest(
                id: "service-kept", emoji: "🩺", title: "Service kept", category: .habit,
                current: Double(scopedServices.count), target: 1, unitLabel: "services",
                earnedDetail: "Maintenance is on record",
                lockedDetail: "Log your first service entry",
                unlockedAt: nthDate(serviceDates, 1)
            ),
            quest(
                id: "service-pro", emoji: "🔧", title: "Service pro", category: .habit,
                current: Double(scopedServices.count), target: 5, unitLabel: "services",
                earnedDetail: "\(scopedServices.count) service logs",
                lockedDetail: "Build a 5-entry service history",
                unlockedAt: nthDate(serviceDates, 5)
            ),
            quest(
                id: "multi-car", emoji: "🚗", title: "Multi-car garage", category: .habit,
                current: Double(vehicleCount), target: 2, unitLabel: "cars",
                earnedDetail: "\(vehicleCount) vehicles in the garage",
                lockedDetail: "Add a second vehicle",
                unlockedAt: nthDate(vehicleDates, 2)
            )
        ]
    }

    static func personalHighlights(logs: [FuelLog], vehicleId: String, unit: String) -> [PersonalHighlight] {
        let vehicleLogs = logs
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.timestamp < $1.timestamp }

        var highlights: [PersonalHighlight] = []

        var bestEfficiency: Double?
        for index in 1..<vehicleLogs.count {
            let previous = vehicleLogs[index - 1]
            let current = vehicleLogs[index]
            guard current.isFullTank, previous.isFullTank else { continue }
            let distance = current.odometerReading - previous.odometerReading
            guard distance > 0, current.fuelVolume > 0 else { continue }
            let efficiency = (current.fuelVolume / distance) * 100
            if bestEfficiency == nil || efficiency < bestEfficiency! {
                bestEfficiency = efficiency
            }
        }
        if let bestEfficiency {
            highlights.append(
                PersonalHighlight(
                    id: "best-tank",
                    emoji: "🏆",
                    label: "Best tank",
                    value: String(format: "%.1f L/100km", bestEfficiency)
                )
            )
        }

        var longestKm = 0.0
        for index in 1..<vehicleLogs.count {
            let distance = vehicleLogs[index].odometerReading - vehicleLogs[index - 1].odometerReading
            if distance > longestKm { longestKm = distance }
        }
        if longestKm > 0 {
            highlights.append(
                PersonalHighlight(
                    id: "longest-run",
                    emoji: "🛣",
                    label: "Longest run",
                    value: DistanceFormat.formatDistance(longestKm, unit: unit)
                )
            )
        }

        let months = Set(vehicleLogs.map {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.timestamp)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        })
        if months.count >= 2 {
            highlights.append(
                PersonalHighlight(
                    id: "streak",
                    emoji: "⚡",
                    label: "Active months",
                    value: "\(months.count)"
                )
            )
        }

        return Array(highlights.prefix(3))
    }

    static func funInsights(
        logs: [FuelLog],
        vehicleId: String,
        currency: String,
        unit: String,
        metrics: EfficiencyMetrics,
        manufacturerStandard: Double?
    ) -> [FunInsight] {
        guard metrics.refuelCount > 0 || !logs.filter({ $0.vehicleId == vehicleId }).isEmpty else { return [] }

        let vehicleLogs = logs
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.timestamp > $1.timestamp }

        guard !vehicleLogs.isEmpty else { return [] }

        var insights: [FunInsight] = []

        if let spendChange = metrics.spendChange, abs(spendChange) >= 5 {
            if spendChange < 0 {
                insights.append(
                    FunInsight(
                        kind: .celebrate,
                        emoji: "✨",
                        title: "Lighter on the wallet",
                        message: "You spent \(Int(abs(spendChange).rounded()))% less on fuel this month than last. Nice."
                    )
                )
            } else {
                insights.append(
                    FunInsight(
                        kind: .watch,
                        emoji: "⛽",
                        title: "Spend crept up",
                        message: "Fuel spend is up \(Int(spendChange.rounded()))% vs last month — \(CurrencyFormat.format(metrics.monthlySpend, currency: currency)) so far."
                    )
                )
            }
        }

        if metrics.totalDistance > 50, metrics.monthlySpend > 0 {
            let costPerKm = metrics.monthlySpend / metrics.totalDistance
            insights.append(
                FunInsight(
                    kind: .tip,
                    emoji: "🎯",
                    title: "Your real cost to drive",
                    message: "About \(CurrencyFormat.format(costPerKm, currency: currency)) per km this month across \(DistanceFormat.formatDistance(metrics.totalDistance, unit: unit))."
                )
            )
        }

        if let current = metrics.current,
           let manufacturerStandard,
           current <= manufacturerStandard {
            let saved = manufacturerStandard - current
            insights.append(
                FunInsight(
                    kind: .celebrate,
                    emoji: "✨",
                    title: "Beating the factory number",
                    message: String(
                        format: "Your last tanks came in %.1f L/100km under the %.1f brochure spec.",
                        saved,
                        manufacturerStandard
                    )
                )
            )
        }

        if vehicleLogs.count >= 2 {
            let daysSince = Calendar.current.dateComponents([.day], from: vehicleLogs[0].timestamp, to: Date()).day ?? 0
            var gaps: [Double] = []
            for index in 0..<min(vehicleLogs.count - 1, 6) {
                let gap = vehicleLogs[index].timestamp.timeIntervalSince(vehicleLogs[index + 1].timestamp) / 86_400
                gaps.append(gap)
            }
            let avgGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
            if avgGap >= 3 {
                let daysLeft = max(0, Int((avgGap - Double(daysSince)).rounded()))
                if daysLeft <= 3, daysSince > 0 {
                    insights.append(
                        FunInsight(
                            kind: .tip,
                            emoji: "⛽",
                            title: "Fill-up radar",
                            message: "You usually refuel every ~\(Int(avgGap.rounded())) days. Based on your pattern, you might want fuel in the next \(max(daysLeft, 1)) day\(daysLeft == 1 ? "" : "s")."
                        )
                    )
                }
            }
        }

        if vehicleLogs.count >= 3 {
            let recent = Array(vehicleLogs.prefix(3))
            let avgRecent = recent.reduce(0) { $0 + $1.pricePerUnit } / Double(recent.count)
            let older = Array(vehicleLogs.dropFirst(3).prefix(3))
            if older.count >= 2 {
                let avgOlder = older.reduce(0) { $0 + $1.pricePerUnit } / Double(older.count)
                if avgOlder > 0 {
                    let priceChange = ((avgRecent - avgOlder) / avgOlder) * 100
                    if abs(priceChange) >= 3 {
                        insights.append(
                            FunInsight(
                                kind: priceChange > 0 ? .watch : .celebrate,
                                emoji: priceChange > 0 ? "⛽" : "🏆",
                                title: priceChange > 0 ? "Pump prices shifted" : "Cheaper fills lately",
                                message: "Your last 3 fills averaged \(CurrencyFormat.format(avgRecent, currency: currency))/L — \(Int(abs(priceChange).rounded()))% \(priceChange > 0 ? "higher" : "lower") than before."
                            )
                        )
                    }
                }
            }
        }

        if let current = metrics.current,
           let avg = metrics.avgEfficiency,
           avg > 0,
           metrics.efficiencySampleCount >= 2 {
            let diff = ((current - avg) / avg) * 100
            if diff <= -5 {
                insights.append(
                    FunInsight(
                        kind: .celebrate,
                        emoji: "💧",
                        title: "Greenest tank this month",
                        message: "Last interval was \(Int(abs(diff).rounded()))% more efficient than your monthly average."
                    )
                )
            }
        }

        let order: [FunInsight.Kind: Int] = [.celebrate: 0, .tip: 1, .watch: 2]
        return insights.sorted { (order[$0.kind] ?? 9) < (order[$1.kind] ?? 9) }.prefix(3).map { $0 }
    }
}
