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
    let spendChange: Double
    let avgEfficiency: Double
    let totalDistance: Double
    let refuelCount: Int
    let recentLogs: [FuelLog]
}

enum MetricsCalculator {
    static func compute(vehicle: Vehicle, logs: [FuelLog]) -> EfficiencyMetrics {
        let vehicleLogs = logs
            .filter { $0.vehicleId == vehicle.id }
            .sorted { $0.timestamp < $1.timestamp }

        var current: Double?
        if vehicleLogs.count >= 2 {
            var intervals: [Double] = []
            for i in 1..<vehicleLogs.count {
                let prev = vehicleLogs[i - 1]
                let curr = vehicleLogs[i]
                let distance = curr.odometerReading - prev.odometerReading
                let fuel = curr.fuelVolume
                guard distance > 0, fuel > 0 else { continue }
                let shouldCalculate = vehicleLogs.count == 2
                    ? true
                    : (curr.isFullTank && prev.isFullTank)
                if shouldCalculate {
                    intervals.append((fuel / distance) * 100)
                }
            }
            current = intervals.last
        }

        let cal = Calendar.current
        let now = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfMonth) ?? now
        let endOfLastMonth = cal.date(byAdding: .day, value: -1, to: startOfMonth) ?? now

        let monthLogs = vehicleLogs.filter { $0.timestamp >= startOfMonth }
        let lastMonthLogs = vehicleLogs.filter { $0.timestamp >= startOfLastMonth && $0.timestamp <= endOfLastMonth }

        let totalSpent = monthLogs.reduce(0) { $0 + $1.totalCost }
        let lastSpent = lastMonthLogs.reduce(0) { $0 + $1.totalCost }
        let spendChange = lastSpent > 0 ? ((totalSpent - lastSpent) / lastSpent) * 100 : 0

        let sorted = monthLogs.sorted { $0.odometerReading < $1.odometerReading }
        let totalDistance = sorted.count > 1
            ? sorted.last!.odometerReading - sorted.first!.odometerReading
            : 0
        let totalLiters = monthLogs.reduce(0) { $0 + $1.fuelVolume }
        let avgEfficiency = totalDistance > 0 && totalLiters > 0
            ? (totalLiters / totalDistance) * 100
            : 0

        let recent = Array(vehicleLogs.reversed().prefix(5))

        return EfficiencyMetrics(
            current: current,
            monthlySpend: totalSpent,
            spendChange: spendChange,
            avgEfficiency: avgEfficiency,
            totalDistance: totalDistance,
            refuelCount: monthLogs.count,
            recentLogs: recent
        )
    }
}

struct EfficiencyVibe {
    let label: String
    let emoji: String
    let tone: Tone

    enum Tone { case excellent, good, neutral, watch, learning }
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

    static func status(efficiency: Double?, standard: Double?) -> (text: String, tone: EfficiencyVibe.Tone) {
        guard let efficiency, let standard else {
            return ("Add refuels to unlock comparison", .learning)
        }
        let deviation = ((efficiency - standard) / standard) * 100
        let abs = Int(abs(deviation).rounded())
        if deviation <= 0 { return ("\(abs)% better than spec", .excellent) }
        if deviation <= 15 { return ("\(abs)% above spec — still in range", .good) }
        if deviation <= 25 { return ("\(abs)% above spec", .neutral) }
        return ("\(abs)% above spec — worth a check", .watch)
    }

    static func spendTrend(_ change: Double) -> String {
        if abs(change) < 1 { return "Flat vs last month" }
        let absVal = Int(abs(change).rounded())
        return change < 0 ? "↓ \(absVal)% vs last month" : "↑ \(absVal)% vs last month"
    }
}
