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
    static func compute(vehicle: Vehicle, logs: [FuelLog]) -> EfficiencyMetrics {
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
        let now = Date()
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
            return ("Add refuels to unlock comparison", .learning)
        }
        guard sampleCount >= 2 else {
            return ("Based on 1 interval — add another full tank", .learning)
        }
        guard let standard else { return ("No verified manufacturer spec", .learning) }
        let deviation = ((efficiency - standard) / standard) * 100
        let abs = Int(abs(deviation).rounded())
        if deviation <= 0 { return ("\(abs)% better than spec", .excellent) }
        if deviation <= 15 { return ("\(abs)% above spec — still in range", .good) }
        if deviation <= 25 { return ("\(abs)% above spec", .neutral) }
        return ("\(abs)% above spec — worth a check", .watch)
    }

    static func spendTrend(_ change: Double?) -> String {
        guard let change else { return "No prior month to compare" }
        if abs(change) < 1 { return "Flat vs last month" }
        let absVal = Int(abs(change).rounded())
        return change < 0 ? "↓ \(absVal)% vs last month" : "↑ \(absVal)% vs last month"
    }
}
