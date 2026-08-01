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

        // Drives still waiting for review in My Drives are real driving the
        // confirmed-trip estimate can't see yet. Count them toward the fuel
        // range so a backlog of unreviewed trips doesn't silently delay the
        // reminder past an empty tank.
        let anchorDate = estimate?.verifiedAt ?? .distantPast
        let unreviewedKm = TripRecordingService.shared.pendingSaves
            .filter { $0.vehicleId == vehicle.id && $0.endedAt > anchorDate }
            .reduce(0) { $0 + $1.distanceKm }
        let estimatedOdometer = (estimate?.estimatedKm).map { $0 + unreviewedKm }

        if let fuel = FuelInsightLogic.predictNextFill(logs: logs, estimatedOdometer: estimatedOdometer) {
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
        let fireDate = prediction.fireDate
        guard fireDate > Date().addingTimeInterval(60) else { return }

        let copy = InsightNotificationCopy.fuel(
            vehicleName: vehicleName,
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
        let id = fuelPrefix + prediction.vehicleScopedId
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        print("[Insights] fuel ping for \(vehicleName) at \(fireDate)")
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
    struct FuelPrediction: Equatable {
        var vehicleScopedId: String
        var daysRemaining: Int
        var kmRemaining: Double?
        var fireDate: Date
    }

    struct ServicePrediction: Equatable {
        var vehicleScopedId: String
        var serviceType: String
        var daysRemaining: Int?
        var kmRemaining: Double?
        var fireDate: Date
    }

    /// Range-based next-fill prediction. The tank is modeled in kilometers:
    /// how far the last fill should carry the car, how much of that has
    /// actually been driven (fuel/service entries anchor the odometer, GPS
    /// trips advance it), and the driver's *current* pace. Barely driving
    /// pushes the reminder out; a road-trip week pulls it in. Fill cadence
    /// is only a fallback when there's no usable km signal.
    static func predictNextFill(
        logs: [FuelLog],
        estimatedOdometer: Double?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FuelPrediction? {
        let sorted = logs.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2, let last = sorted.last else { return nil }

        var dayGaps: [Double] = []
        var kmGaps: [Double] = []
        let window = min(sorted.count - 1, 7)
        for index in (sorted.count - window)..<(sorted.count) where index > 0 {
            let newer = sorted[index]
            let older = sorted[index - 1]
            let days = newer.timestamp.timeIntervalSince(older.timestamp) / 86_400
            if days > 0.5 { dayGaps.append(days) }
            let km = newer.odometerReading - older.odometerReading
            if km > 5 { kmGaps.append(km) }
        }
        guard let typicalDays = median(dayGaps), typicalDays > 0.5 else { return nil }

        let daysSince = now.timeIntervalSince(last.timestamp) / 86_400
        let daysRemaining: Int
        var kmRemaining: Double?

        if let typicalKm = median(kmGaps), typicalKm > 10, let odometer = estimatedOdometer {
            let kmSince = max(0, odometer - last.odometerReading)

            // How far the last fill should carry the car: full tanks get the
            // typical fill-to-fill distance, partial fills only a
            // volume-proportional slice of it.
            var kmBudget = typicalKm
            if !last.isFullTank,
               let litersPer100 = overallLitersPer100km(sorted), litersPer100 > 0 {
                kmBudget = min(typicalKm, last.fuelVolume / litersPer100 * 100)
            }

            let reserve = max(kmBudget * 0.1, 15)
            let kmLeft = kmBudget - kmSince
            kmRemaining = max(kmLeft, 0)

            if kmLeft <= reserve {
                daysRemaining = 0
            } else {
                // Trust the observed pace since the fill more the longer
                // we've watched it; fall back to the historical pace early on.
                let historicalPace = typicalKm / typicalDays
                var dailyKm = historicalPace
                if daysSince >= 1 {
                    let actualPace = kmSince / daysSince
                    let confidence = min(daysSince / 3, 1)
                    dailyKm = actualPace * confidence + historicalPace * (1 - confidence)
                }
                dailyKm = max(dailyKm, 1)
                let daysUntilReserve = min((kmLeft - reserve) / dailyKm, 45)
                daysRemaining = max(Int(daysUntilReserve.rounded()), 0)
            }
        } else {
            // No odometer/km signal at all — cadence is the only guess left.
            daysRemaining = max(Int((typicalDays - daysSince).rounded()), 0)
        }

        let fireDate = fireDate(forDaysRemaining: daysRemaining, now: now, calendar: calendar)
        return FuelPrediction(
            vehicleScopedId: last.vehicleId,
            daysRemaining: daysRemaining,
            kmRemaining: kmRemaining,
            fireDate: fireDate
        )
    }

    /// Rough whole-history consumption used to size partial fills.
    private static func overallLitersPer100km(_ sorted: [FuelLog]) -> Double? {
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let km = last.odometerReading - first.odometerReading
        guard km > 50 else { return nil }
        let liters = sorted.dropFirst().reduce(0) { $0 + $1.fuelVolume }
        guard liters > 0 else { return nil }
        return liters / km * 100
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

    /// Morning-ish local ping; sooner when already due.
    static func fireDate(forDaysRemaining days: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if days <= 0 {
            return now.addingTimeInterval(2 * 60 * 60)
        }
        if days == 1 {
            return morning(of: calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar: calendar)
        }
        // Nudge a day early so you're not surprised at empty.
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

private enum InsightNotificationCopy {
    struct Line {
        let title: String
        let body: String
    }

    static func fuel(vehicleName: String, daysRemaining: Int, kmRemaining: Double? = nil) -> Line {
        let rangeNote = kmRemaining.map { String(format: " Roughly %.0f km left in the tank.", max($0, 0)) } ?? ""
        if daysRemaining <= 0 {
            return pick([
                Line(title: "\(vehicleName) is THIRSTY 😰", body: "The tank is due a fill. Right now. This is not a drill." + rangeNote),
                Line(title: "Uh oh.", body: "\(vehicleName) needed fuel, like, yesterday.\(rangeNote) Please don't test how far 'empty' goes."),
            ])
        }
        if daysRemaining == 1 {
            return pick([
                Line(title: "Tomorrow. Fuel. Don't forget.", body: "\(vehicleName) is almost running on hopes and dreams.\(rangeNote) Plan a pit stop."),
                Line(title: "One day left ⛽", body: "\(vehicleName) will want a drink tomorrow.\(rangeNote) I'll remember if you forget. I always remember."),
            ])
        }
        return pick([
            Line(title: "Fuel check in \(daysRemaining) days!", body: "At your current pace, \(vehicleName) will want a top-up in about \(daysRemaining) days.\(rangeNote)"),
            Line(title: "Heads up! ⛽", body: "\(vehicleName) should be good for about \(daysRemaining) more days the way you're driving.\(rangeNote)"),
        ])
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
