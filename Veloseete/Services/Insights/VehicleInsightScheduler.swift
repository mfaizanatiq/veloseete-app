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

        // Drives still waiting for review are real driving the confirmed
        // estimate can't see — but discount them slightly so a backlog of
        // noisy pending trips can't falsely declare the tank empty.
        let anchorDate = estimate?.verifiedAt ?? .distantPast
        let unreviewedKm = TripRecordingService.shared.pendingSaves
            .filter { $0.vehicleId == vehicle.id && $0.endedAt > anchorDate }
            .reduce(0) { $0 + $1.distanceKm }
        let creditedUnreviewed = unreviewedKm * 0.85
        let estimatedOdometer = (estimate?.estimatedKm).map { $0 + creditedUnreviewed }

        if let fuel = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: estimatedOdometer,
            tankCapacityLiters: vehicle.fuelTankCapacity,
            brochureL100km: store.manufacturerStandard
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

    /// Multi-signal low-fuel detector.
    ///
    /// Combines:
    /// - fill-to-fill km pattern (full tanks preferred)
    /// - liters put in × measured L/100km → range budget
    /// - tank capacity when known
    /// - brochure L/100km as a soft prior when history is thin
    /// - km actually driven since the last fill (odometer + trips)
    ///
    /// Calendar cadence alone never triggers a notification — without a km
    /// signal we refuse to cry wolf.
    static func predictNextFill(
        logs: [FuelLog],
        estimatedOdometer: Double?,
        tankCapacityLiters: Double? = nil,
        brochureL100km: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FuelPrediction? {
        let sorted = logs.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2, let last = sorted.last else { return nil }
        guard let odometer = estimatedOdometer else {
            // No odometer picture at all → we cannot know the tank state.
            return nil
        }

        let kmSince = max(0, odometer - last.odometerReading)
        let daysSince = max(now.timeIntervalSince(last.timestamp) / 86_400, 0.01)

        let pattern = fillPattern(from: sorted)
        let efficiency = measuredLitersPer100km(from: sorted)
            ?? brochureL100km
            ?? defaultEfficiencyFallback

        // Range this fill should cover.
        let budget = rangeBudget(
            lastFill: last,
            pattern: pattern,
            litersPer100km: efficiency,
            tankCapacityLiters: tankCapacityLiters
        )
        guard budget.km > 30 else { return nil }

        let kmLeft = budget.km - kmSince
        let fractionLeft = max(0, min(1, kmLeft / budget.km))
        let tankPercent = fractionLeft * 100

        // Pace: trust observed driving more as this tank ages.
        let historicalPace = max(pattern.typicalDailyKm ?? (budget.km / max(pattern.typicalDays ?? 7, 1)), 5)
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
            confidence: budget.confidence
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
            confidence: budget.confidence,
            urgency: urgency,
            fireDate: fire
        )
    }

    // MARK: - Pattern & budget

    private struct FillPattern {
        var typicalRangeKm: Double?
        var typicalDays: Double?
        var typicalDailyKm: Double?
        var sampleCount: Int
    }

    private struct RangeBudget {
        var km: Double
        var confidence: Double
    }

    private static let defaultEfficiencyFallback = 8.5

    /// Prefer full→full intervals; fall back to any fill-to-fill gaps.
    private static func fillPattern(from sorted: [FuelLog]) -> FillPattern {
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

    private static func measuredLitersPer100km(from sorted: [FuelLog]) -> Double? {
        // Distance-weighted over recent full-tank closed intervals.
        var distances: [Double] = []
        var fuels: [Double] = []
        var anchor: FuelLog?
        var fuelSince = 0.0

        for log in sorted {
            guard log.fuelVolume > 0 else { continue }
            guard let current = anchor else {
                if log.isFullTank { anchor = log }
                continue
            }
            fuelSince += log.fuelVolume
            guard log.isFullTank else { continue }
            let distance = log.odometerReading - current.odometerReading
            if distance > 40 {
                distances.append(distance)
                fuels.append(fuelSince)
            }
            anchor = log
            fuelSince = 0
        }

        let recent = zip(distances, fuels).suffix(5)
        let totalKm = recent.reduce(0.0) { $0 + $1.0 }
        let totalFuel = recent.reduce(0.0) { $0 + $1.1 }
        guard totalKm > 80, totalFuel > 0 else { return nil }
        return totalFuel / totalKm * 100
    }

    private static func rangeBudget(
        lastFill: FuelLog,
        pattern: FillPattern,
        litersPer100km: Double,
        tankCapacityLiters: Double?
    ) -> RangeBudget {
        let volumeRange = lastFill.fuelVolume / max(litersPer100km, 1) * 100
        var candidates: [(km: Double, weight: Double)] = []
        var confidence = 0.35

        if let typical = pattern.typicalRangeKm, typical > 30 {
            if lastFill.isFullTank {
                candidates.append((typical, 1.0))
                confidence = pattern.sampleCount >= 3 ? 0.85 : 0.65
            } else {
                // Partial: only claim the liters you actually put in.
                candidates.append((min(typical, volumeRange), 1.0))
                confidence = pattern.sampleCount >= 3 ? 0.7 : 0.55
            }
        } else {
            candidates.append((volumeRange, 0.8))
            confidence = 0.45
        }

        // Tank capacity caps a full fill's range (you can't go farther than a full tank).
        if lastFill.isFullTank, let tank = tankCapacityLiters, tank > 5 {
            let tankRange = tank / max(litersPer100km, 1) * 100
            candidates.append((tankRange, 0.7))
            confidence = max(confidence, 0.7)
        } else if !lastFill.isFullTank, let tank = tankCapacityLiters, tank > 5 {
            // Partial into unknown prior level — trust volume more than "typical tank".
            let capped = min(volumeRange, tank / max(litersPer100km, 1) * 100)
            candidates.append((capped, 1.0))
        }

        // Always consider the literal liters→km conversion.
        candidates.append((volumeRange, lastFill.isFullTank ? 0.5 : 1.0))

        let weighted = candidates.reduce(0.0) { $0 + $1.km * $1.weight }
        let weightSum = candidates.reduce(0.0) { $0 + $1.weight }
        let km = weightSum > 0 ? weighted / weightSum : volumeRange

        // Fresh fill with almost no driving history on this car stays low-confidence.
        if pattern.sampleCount < 2 { confidence = min(confidence, 0.5) }

        return RangeBudget(km: max(km, 20), confidence: confidence)
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
                Line(title: "\(vehicleName) is running on fumes", body: "Your driving pattern says the tank is essentially empty.\(rangeNote) Fill up before you push it."),
                Line(title: "Fuel now — not later", body: "\(vehicleName) has almost nothing left based on km since your last fill.\(rangeNote)"),
            ])
        case .low:
            return pick([
                Line(title: "Low fuel on \(vehicleName)", body: "Based on your fill history and km driven, you're in the low zone.\(rangeNote) Plan a stop soon."),
                Line(title: "Tank's getting light ⛽", body: "\(vehicleName) is down to the last stretch of this fill.\(rangeNote)"),
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
                Line(title: "It's \(type) time. It's overdue.", body: "\(vehicleName) has been very patient with you. Book it today?"),
                Line(title: "\(vehicleName) needs you 🔧", body: "The \(type) is due. Ignoring this notification won't fix the car. I checked."),
            ])
        }
        if let kmRemaining, kmRemaining <= 150 {
            return pick([
                Line(title: "Almost \(type) time!", body: String(format: "~%.0f km left on %@. So close. Don't ghost it now.", max(kmRemaining, 0), vehicleName)),
            ])
        }
        if let daysRemaining {
            return pick([
                Line(title: "\(type.capitalized) in ~\(daysRemaining) days", body: "\(vehicleName) is counting on you. Literally. I'm counting the days for it."),
            ])
        }
        return Line(title: "Service soon-ish 🔧", body: "\(vehicleName) has a \(type) coming up. You've been warned. Nicely. For now.")
    }

    private static func pick(_ lines: [Line]) -> Line {
        lines.randomElement() ?? lines[0]
    }
}
