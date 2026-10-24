import Foundation
@preconcurrency import UserNotifications

/// Schedules quirky local reminders for upcoming fuel fills and service due dates.
@MainActor
final class VehicleInsightScheduler {
    static let shared = VehicleInsightScheduler()

    private let fuelPrefix = "veloseete.insight.fuel."
    private let servicePrefix = "veloseete.insight.service."

    private init() {}

    func refresh(using store: DataStore) {
        Task {
            await refreshAsync(using: store)
        }
    }

    func refreshAsync(using store: DataStore) async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            return
        }

        await cancelPendingInsights(center: center)

        guard let vehicle = store.currentVehicle else { return }
        let vehicleName = vehicle.nickname
        let driverName = store.userName
        let logs = store.fuelLogs.filter { $0.vehicleId == vehicle.id }.sorted { $0.timestamp < $1.timestamp }
        let estimate = store.odometerEstimate(vehicleId: vehicle.id)
        let services = store.serviceLogs.filter { $0.vehicleId == vehicle.id }

        // Estimate already credits pending review km — use it directly for fuel/service.
        let estimatedOdometer = estimate?.estimatedKm

        if let fuel = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: estimatedOdometer,
            tankCapacityLiters: vehicle.fuelTankCapacity,
            brochureL100km: store.manufacturerStandard,
            learning: VehicleLearningStore.shared.state(for: vehicle.id)
        ), fuel.shouldNotify {
            await scheduleFuel(fuel, vehicleName: vehicleName, driverName: driverName, center: center)
        }

        if let service = FuelInsightLogic.predictServiceDue(
            services: services,
            estimatedOdometer: estimatedOdometer ?? vehicle.currentOdometer
        ) {
            await scheduleService(service, vehicleName: vehicleName, driverName: driverName, center: center)
        }
    }

    private func cancelPendingInsights(center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(fuelPrefix) || $0.hasPrefix(servicePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func scheduleFuel(
        _ prediction: FuelInsightLogic.FuelPrediction,
        vehicleName: String,
        driverName: String,
        center: UNUserNotificationCenter
    ) async {
        let decision = FuelNotifyCooldown.decision(
            vehicleId: prediction.vehicleScopedId,
            fillId: prediction.fillId,
            urgency: prediction.urgency,
            proposedFireDate: prediction.fireDate
        )
        guard case let .schedule(fireDate) = decision else {
            print("[Insights] fuel ping suppressed (already delivered for this fill/\(prediction.urgency))")
            return
        }
        guard fireDate > Date().addingTimeInterval(60) else { return }

        let copy = InsightNotificationCopy.fuel(
            vehicleName: vehicleName,
            urgency: prediction.urgency,
            daysRemaining: prediction.daysRemaining,
            kmRemaining: prediction.kmRemaining,
            tankPercent: prediction.tankPercentRemaining
        )
        let content = UNMutableNotificationContent()
        content.title = personalized(copy.title, driverName: driverName)
        content.body = copy.body
        content.sound = .default
        content.categoryIdentifier = "VEHICLE_INSIGHT"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = fuelPrefix + prediction.vehicleScopedId
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        FuelNotifyCooldown.markScheduled(
            vehicleId: prediction.vehicleScopedId,
            fillId: prediction.fillId,
            urgency: prediction.urgency,
            fireDate: fireDate
        )
        print("[Insights] fuel ping for \(vehicleName) at \(fireDate) urgency=\(prediction.urgency) kmLeft=\(prediction.kmRemaining.map { String(format: "%.0f", $0) } ?? "?") conf=\(String(format: "%.2f", prediction.confidence))")
    }

    private func scheduleService(
        _ prediction: FuelInsightLogic.ServicePrediction,
        vehicleName: String,
        driverName: String,
        center: UNUserNotificationCenter
    ) async {
        let fireDate = prediction.fireDate
        guard fireDate > Date().addingTimeInterval(60) else { return }

        let copy = InsightNotificationCopy.service(
            vehicleName: vehicleName,
            serviceType: prediction.serviceType,
            daysRemaining: prediction.daysRemaining,
            kmRemaining: prediction.kmRemaining
        )
        let content = UNMutableNotificationContent()
        content.title = personalized(copy.title, driverName: driverName)
        content.body = copy.body
        content.sound = .default
        content.categoryIdentifier = "VEHICLE_INSIGHT"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = servicePrefix + prediction.vehicleScopedId
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        print("[Insights] service ping for \(vehicleName) at \(fireDate)")
    }

    private func personalized(_ message: String, driverName: String) -> String {
        let trimmed = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return message.prefix(1).uppercased() + String(message.dropFirst())
        }
        return "\(trimmed), \(message)"
    }
}

enum FuelInsightLogic {
    enum FuelUrgency: String, Comparable {
        case none
        case watch
        case low
        case empty

        private var rank: Int {
            switch self {
            case .none: return 0
            case .watch: return 1
            case .low: return 2
            case .empty: return 3
            }
        }

        static func < (lhs: FuelUrgency, rhs: FuelUrgency) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    struct FuelPrediction: Equatable {
        var vehicleScopedId: String
        var fillId: String
        var daysRemaining: Int
        var kmRemaining: Double?
        var tankPercentRemaining: Double?
        var confidence: Double
        var urgency: FuelUrgency
        var fireDate: Date

        /// Only schedule a notification when the tank is actually low/empty
        /// with enough evidence — no early "heads up in 5 days" spam.
        var shouldNotify: Bool {
            confidence >= 0.55 && (urgency == .low || urgency == .empty)
        }
    }

    struct ServicePrediction: Equatable {
        var vehicleScopedId: String
        var serviceType: String
        var daysRemaining: Int?
        var kmRemaining: Double?
        var fireDate: Date
    }

    /// Physical low-fuel detector: a litre ledger, not a guess from habit.
    ///
    /// The tank is full (capacity) at the last full-tank fill; every later fill
    /// adds its litres, and every km driven burns the measured L/100km. What's
    /// left is real fuel in the tank, so:
    /// - topping up at half a tank no longer teaches us the tank is "half size"
    /// - a 15 L fill-to-full doesn't shrink range to 15 L worth of km
    /// - a partial top-up keeps the fuel that was already in the tank
    ///
    /// Calendar cadence alone never triggers a notification — without a km
    /// signal we refuse to cry wolf.
    static func predictNextFill(
        logs: [FuelLog],
        estimatedOdometer: Double?,
        tankCapacityLiters: Double? = nil,
        brochureL100km: Double? = nil,
        learning: VehicleLearningState = .default,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FuelPrediction? {
        let sorted = logs.filter { $0.fuelVolume > 0 }.sorted { $0.timestamp < $1.timestamp }
        guard let last = sorted.last else { return nil }
        guard let odometer = estimatedOdometer else {
            // No odometer picture at all → we cannot know the tank state.
            return nil
        }

        let kmSince = max(0, odometer - last.odometerReading)
        let daysSince = max(now.timeIntervalSince(last.timestamp) / 86_400, 0.01)

        let measured = measuredEfficiency(from: sorted)
        let efficiency = measured?.litersPer100km
            ?? brochureL100km
            ?? defaultEfficiencyFallback
        guard let tank = tankState(
            logs: sorted,
            kmSinceLastFill: kmSince,
            litersPer100km: efficiency,
            tankCapacityLiters: tankCapacityLiters
        ) else { return nil }

        let fullRangeKm = tank.capacityLiters / efficiency * 100
        guard fullRangeKm > 30 else { return nil }
        let kmLeft = tank.litersLeft / efficiency * 100
        let fractionLeft = tank.litersLeft / tank.capacityLiters
        let tankPercent = fractionLeft * 100

        let confidence = tankConfidence(
            capacityIsSpec: tank.capacityIsSpec,
            anchoredOnFullTank: tank.anchoredOnFullTank,
            measuredIntervals: measured?.intervals ?? 0,
            hasBrochure: brochureL100km != nil
        )

        // Pace: trust observed driving more as this tank ages.
        let pattern = fillPattern(from: sorted)
        let historicalPace = max(pattern.typicalDailyKm ?? (fullRangeKm / max(pattern.typicalDays ?? 7, 1)), 5)
        let actualPace = kmSince / daysSince
        let paceConfidence = min(daysSince / 2.5, 1)
        let dailyKm = max(actualPace * paceConfidence + historicalPace * (1 - paceConfidence), 3)

        let daysRemaining: Int
        if kmLeft <= 0 {
            daysRemaining = 0
        } else {
            daysRemaining = max(Int((kmLeft / dailyKm).rounded()), 0)
        }

        let urgency = classifyUrgency(
            fractionLeft: fractionLeft,
            kmLeft: kmLeft,
            confidence: confidence
        )

        let fire = notificationFireDate(
            urgency: urgency,
            daysRemaining: daysRemaining,
            now: now,
            calendar: calendar
        )

        return FuelPrediction(
            vehicleScopedId: last.vehicleId,
            fillId: last.id,
            daysRemaining: daysRemaining,
            kmRemaining: max(kmLeft, 0),
            tankPercentRemaining: tankPercent,
            confidence: confidence,
            urgency: urgency,
            fireDate: fire
        )
    }

    // MARK: - Tank ledger

    struct TankState: Equatable {
        var litersLeft: Double
        var capacityLiters: Double
        /// False when capacity was inferred from the biggest fill (a lower bound).
        var capacityIsSpec: Bool
        /// False when no full-tank fill exists, so the starting level is a guess.
        var anchoredOnFullTank: Bool
    }

    /// Litres in the tank right now, replayed from the last full-tank fill.
    static func tankState(
        logs sorted: [FuelLog],
        kmSinceLastFill: Double,
        litersPer100km: Double,
        tankCapacityLiters: Double?
    ) -> TankState? {
        guard !sorted.isEmpty, litersPer100km > 0 else { return nil }
        let biggestFill = sorted.map(\.fuelVolume).max() ?? 0
        let spec = tankCapacityLiters.flatMap { $0 > 5 ? $0 : nil }
        // A fill bigger than the spec means the spec is off — never claim less room than we've seen poured in.
        let capacity = max(spec ?? 0, biggestFill)
        guard capacity > 5 else { return nil }

        let anchorIndex = sorted.lastIndex(where: \.isFullTank)
        let startIndex = anchorIndex ?? 0
        // Without a full tank on record, the first fill's litres are all we can vouch for.
        var liters = anchorIndex != nil ? capacity : min(sorted[startIndex].fuelVolume, capacity)
        var previousOdo = sorted[startIndex].odometerReading

        for log in sorted[(startIndex + 1)...] {
            let driven = max(0, log.odometerReading - previousOdo)
            liters = max(0, liters - driven * litersPer100km / 100)
            liters = min(capacity, liters + log.fuelVolume)
            previousOdo = log.odometerReading
        }
        liters = max(0, liters - max(0, kmSinceLastFill) * litersPer100km / 100)

        return TankState(
            litersLeft: liters,
            capacityLiters: capacity,
            capacityIsSpec: spec != nil,
            anchoredOnFullTank: anchorIndex != nil
        )
    }

    private static func tankConfidence(
        capacityIsSpec: Bool,
        anchoredOnFullTank: Bool,
        measuredIntervals: Int,
        hasBrochure: Bool
    ) -> Double {
        var confidence = capacityIsSpec ? 0.45 : 0.25
        if anchoredOnFullTank { confidence += 0.2 }
        if measuredIntervals >= 3 {
            confidence += 0.25
        } else if measuredIntervals >= 1 {
            confidence += 0.15
        } else if hasBrochure {
            confidence += 0.05
        }
        // Inferred capacity is a lower bound (you may never fill from empty) —
        // good enough for the in-app gauge, not for a push alert.
        if !capacityIsSpec { confidence = min(confidence, 0.5) }
        return min(confidence, 0.95)
    }

    // MARK: - Pattern

    private struct FillPattern {
        var typicalRangeKm: Double?
        var typicalDays: Double?
        var typicalDailyKm: Double?
        var sampleCount: Int
    }

    private static let defaultEfficiencyFallback = 8.5

    /// Prefer full→full intervals; fall back to any fill-to-fill gaps.
    /// Habit only sets the driving pace — it never decides how big the tank is.
    private static func fillPattern(from sorted: [FuelLog]) -> FillPattern {
        guard sorted.count >= 2 else { return FillPattern(sampleCount: 0) }
        var fullKm: [Double] = []
        var fullDays: [Double] = []
        var anyKm: [Double] = []
        var anyDays: [Double] = []

        var lastFull: FuelLog?
        for log in sorted {
            if let prev = lastFull, log.isFullTank {
                let km = log.odometerReading - prev.odometerReading
                let days = log.timestamp.timeIntervalSince(prev.timestamp) / 86_400
                if km > 30 { fullKm.append(km) }
                if days > 0.5 { fullDays.append(days) }
            }
            if log.isFullTank { lastFull = log }
        }

        let windowStart = max(sorted.count - 8, 1)
        for index in windowStart..<sorted.count {
            let newer = sorted[index]
            let older = sorted[index - 1]
            let km = newer.odometerReading - older.odometerReading
            let days = newer.timestamp.timeIntervalSince(older.timestamp) / 86_400
            if km > 20 { anyKm.append(km) }
            if days > 0.5 { anyDays.append(days) }
        }

        let rangeSamples = fullKm.count >= 2 ? fullKm : anyKm
        let daySamples = fullDays.count >= 2 ? fullDays : anyDays
        let typicalRange = median(rangeSamples)
        let typicalDays = median(daySamples)
        let daily: Double? = {
            guard let r = typicalRange, let d = typicalDays, d > 0 else { return nil }
            return r / d
        }()

        return FillPattern(
            typicalRangeKm: typicalRange,
            typicalDays: typicalDays,
            typicalDailyKm: daily,
            sampleCount: rangeSamples.count
        )
    }

    private static func measuredEfficiency(from sorted: [FuelLog]) -> (litersPer100km: Double, intervals: Int)? {
        // Same measured tanks the Fuels tab shows — partials included, typos filtered.
        let recent = MetricsCalculator.fullTankIntervals(in: sorted).suffix(5)
        let totalKm = recent.reduce(0.0) { $0 + $1.distanceKm }
        let totalFuel = recent.reduce(0.0) { $0 + $1.fuelLiters }
        guard totalKm > 80, totalFuel > 0 else { return nil }
        return (totalFuel / totalKm * 100, recent.count)
    }

    private static func classifyUrgency(
        fractionLeft: Double,
        kmLeft: Double,
        confidence: Double
    ) -> FuelUrgency {
        // Need real evidence before declaring low/empty.
        guard confidence >= 0.55 else { return .none }

        if kmLeft <= 15 || fractionLeft <= 0.05 {
            return .empty
        }
        if kmLeft <= 45 || fractionLeft <= 0.15 {
            return .low
        }
        if kmLeft <= 80 || fractionLeft <= 0.25 {
            return .watch
        }
        return .none
    }

    /// Only schedule when urgency is low/empty — no multi-day advance pings.
    private static func notificationFireDate(
        urgency: FuelUrgency,
        daysRemaining: Int,
        now: Date,
        calendar: Calendar
    ) -> Date {
        switch urgency {
        case .empty:
            // Soon, but not immediately on every refresh (cooldown handles repeats).
            return now.addingTimeInterval(15 * 60)
        case .low:
            if daysRemaining <= 0 {
                return now.addingTimeInterval(30 * 60)
            }
            // Next calm morning if there's still a day of range left.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return morning(of: tomorrow, calendar: calendar)
        case .watch, .none:
            // Won't be scheduled (shouldNotify == false); placeholder only.
            return now.addingTimeInterval(86_400 * 30)
        }
    }

    static func predictServiceDue(
        services: [ServiceLog],
        estimatedOdometer: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ServicePrediction? {
        // Prefer the soonest upcoming reminder across recent service entries.
        let candidates: [ServicePrediction] = services.compactMap { log in
            var byDate: (days: Int, fire: Date)?
            if let due = log.nextServiceDate {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
                byDate = (days, fireDate(forDaysRemaining: max(days, 0), now: now, calendar: calendar))
            }

            var byKm: (km: Double, fire: Date)?
            if let nextOdo = log.nextServiceOdometer {
                let kmLeft = nextOdo - estimatedOdometer
                // ~assume 40 km/day when translating odo into a ping window.
                let days = Int((kmLeft / 40).rounded())
                byKm = (kmLeft, fireDate(forDaysRemaining: max(days, 0), now: now, calendar: calendar))
            }

            guard byDate != nil || byKm != nil else { return nil }

            // Fire at the earlier of date / km-derived reminders.
            let fire: Date
            let daysRemaining: Int?
            let kmRemaining: Double?
            switch (byDate, byKm) {
            case let (d?, k?):
                if d.fire <= k.fire {
                    fire = d.fire
                    daysRemaining = d.days
                    kmRemaining = k.km
                } else {
                    fire = k.fire
                    daysRemaining = d.days
                    kmRemaining = k.km
                }
            case let (d?, nil):
                fire = d.fire
                daysRemaining = d.days
                kmRemaining = nil
            case let (nil, k?):
                fire = k.fire
                daysRemaining = nil
                kmRemaining = k.km
            case (nil, nil):
                return nil
            }

            // Skip if clearly far away (> 45 days and > 1500 km).
            if let daysRemaining, daysRemaining > 45, (kmRemaining ?? 0) > 1_500 {
                return nil
            }
            if daysRemaining == nil, let kmRemaining, kmRemaining > 1_500 {
                return nil
            }

            return ServicePrediction(
                vehicleScopedId: log.vehicleId + "-" + log.id,
                serviceType: log.serviceType,
                daysRemaining: daysRemaining,
                kmRemaining: kmRemaining,
                fireDate: fire
            )
        }

        return candidates.min(by: { $0.fireDate < $1.fireDate })
    }

    /// Morning-ish local ping; sooner when already due. (Service reminders.)
    static func fireDate(forDaysRemaining days: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if days <= 0 {
            return now.addingTimeInterval(2 * 60 * 60)
        }
        if days == 1 {
            return morning(of: calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar: calendar)
        }
        let targetDay = calendar.date(byAdding: .day, value: max(days - 1, 1), to: now) ?? now
        return morning(of: targetDay, calendar: calendar)
    }

    private static func morning(of date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 15
        return calendar.date(from: components) ?? date
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

/// Remembers the last fuel alert we scheduled so the same fill cycle
/// can't re-spam every time the app foregrounds — while still restoring
/// a pending alert that refresh cancelled.
enum FuelNotifyCooldown {
    private static let prefix = "veloseete.fuelNotify."

    enum Decision: Equatable {
        case schedule(Date)
        case skip
    }

    private struct Record: Codable {
        var fillId: String
        var urgency: String
        var fireEpoch: TimeInterval
    }

    static func decision(
        vehicleId: String,
        fillId: String,
        urgency: FuelInsightLogic.FuelUrgency,
        proposedFireDate: Date,
        now: Date = Date()
    ) -> Decision {
        guard let data = UserDefaults.standard.data(forKey: prefix + vehicleId),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              let previous = FuelInsightLogic.FuelUrgency(rawValue: record.urgency) else {
            return .schedule(proposedFireDate)
        }

        let storedFire = Date(timeIntervalSince1970: record.fireEpoch)

        // New fill → fresh cycle.
        if record.fillId != fillId {
            return .schedule(proposedFireDate)
        }

        // Same fill, same urgency: restore pending if it hasn't fired yet;
        // otherwise stay quiet (stops the empty-spam loop).
        if urgency == previous {
            if storedFire > now.addingTimeInterval(60) {
                return .schedule(storedFire)
            }
            return .skip
        }

        // Escalation only (e.g. low → empty).
        if urgency > previous {
            return .schedule(proposedFireDate)
        }

        return .skip
    }

    static func markScheduled(
        vehicleId: String,
        fillId: String,
        urgency: FuelInsightLogic.FuelUrgency,
        fireDate: Date
    ) {
        let record = Record(
            fillId: fillId,
            urgency: urgency.rawValue,
            fireEpoch: fireDate.timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: prefix + vehicleId)
        }
    }
}

private enum InsightNotificationCopy {
    struct Line {
        let title: String
        let body: String
    }

    static func fuel(
        vehicleName: String,
        urgency: FuelInsightLogic.FuelUrgency,
        daysRemaining: Int,
        kmRemaining: Double?,
        tankPercent: Double?
    ) -> Line {
        let rangeNote: String = {
            if let km = kmRemaining, let pct = tankPercent {
                return String(format: " About %.0f km left (~%.0f%% of the tank).", max(km, 0), max(pct, 0))
            }
            if let km = kmRemaining {
                return String(format: " Roughly %.0f km left in the tank.", max(km, 0))
            }
            return ""
        }()

        switch urgency {
        case .empty:
            return pick([
                Line(title: "\(vehicleName) — tank’s almost empty", body: "Based on km since your last fill.\(rangeNote) Stop for fuel soon."),
                Line(title: "Fuel now on \(vehicleName)", body: "Pattern says there’s almost nothing left.\(rangeNote)"),
            ])
        case .low:
            return pick([
                Line(title: "Low fuel on \(vehicleName)", body: "You’re in the low zone.\(rangeNote) Plan a stop."),
                Line(title: "Tank’s getting light", body: "\(vehicleName) is on the last stretch of this fill.\(rangeNote)"),
            ])
        case .watch, .none:
            return Line(
                title: "Fuel check",
                body: "\(vehicleName) still has range.\(rangeNote)"
            )
        }
    }

    static func service(
        vehicleName: String,
        serviceType: String,
        daysRemaining: Int?,
        kmRemaining: Double?
    ) -> Line {
        let type = serviceType.lowercased()
        if let daysRemaining, daysRemaining <= 0 {
            return pick([
                Line(title: "\(type.capitalized) is overdue", body: "\(vehicleName) is due. Book it when you can."),
                Line(title: "\(vehicleName) needs \(type)", body: "This one’s past due — don’t leave it hanging."),
            ])
        }
        if let kmRemaining, kmRemaining <= 150 {
            return pick([
                Line(title: "Almost \(type) time", body: String(format: "~%.0f km left on %@. Don’t ghost it now.", max(kmRemaining, 0), vehicleName)),
            ])
        }
        if let daysRemaining {
            return pick([
                Line(title: "\(type.capitalized) in ~\(daysRemaining) days", body: "\(vehicleName) has a \(type) coming up. Heads-up."),
            ])
        }
        return Line(title: "Service coming up", body: "\(vehicleName) has a \(type) on the horizon.")
    }

    private static func pick(_ lines: [Line]) -> Line {
        lines.randomElement() ?? lines[0]
    }
}
