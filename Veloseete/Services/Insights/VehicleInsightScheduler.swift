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

        if let fuel = FuelInsightLogic.predictNextFill(logs: logs, estimatedOdometer: estimate?.estimatedKm) {
            await scheduleFuel(fuel, vehicleName: vehicleName, driverName: driverName, center: center)
        }

        if let service = FuelInsightLogic.predictServiceDue(
            services: services,
            estimatedOdometer: estimate?.estimatedKm ?? vehicle.currentOdometer
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
            daysRemaining: prediction.daysRemaining
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
        var fireDate: Date
    }

    struct ServicePrediction: Equatable {
        var vehicleScopedId: String
        var serviceType: String
        var daysRemaining: Int?
        var kmRemaining: Double?
        var fireDate: Date
    }

    /// Blend fill cadence + km-between-fills to guess the next tank.
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
        guard let avgDays = average(dayGaps), avgDays > 0.5 else { return nil }

        let daysSince = now.timeIntervalSince(last.timestamp) / 86_400
        var remainingByCalendar = avgDays - daysSince

        if let avgKm = average(kmGaps), avgKm > 10, let odo = estimatedOdometer {
            let kmSince = max(0, odo - last.odometerReading)
            let kmLeft = max(0, avgKm - kmSince)
            let dailyKm = avgKm / avgDays
            if dailyKm > 1 {
                let remainingByKm = kmLeft / dailyKm
                // Lean slightly early so the ping lands before you're empty.
                remainingByCalendar = min(remainingByCalendar, remainingByKm) * 0.9
            }
        }

        let daysRemaining = Int(remainingByCalendar.rounded())
        let fireDate = fireDate(forDaysRemaining: max(daysRemaining, 0), now: now, calendar: calendar)
        return FuelPrediction(
            vehicleScopedId: last.vehicleId,
            daysRemaining: max(daysRemaining, 0),
            fireDate: fireDate
        )
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

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private enum InsightNotificationCopy {
    struct Line {
        let title: String
        let body: String
    }

    static func fuel(vehicleName: String, daysRemaining: Int) -> Line {
        if daysRemaining <= 0 {
            return pick([
                Line(title: "tank's getting dramatic", body: "\(vehicleName) is due a fill. Don't make me say I told you so."),
                Line(title: "thirsty vibes", body: "\(vehicleName) wants petrol. Soon-ish. Like, now-ish."),
            ])
        }
        if daysRemaining == 1 {
            return pick([
                Line(title: "fuel run tomorrow?", body: "Your rhythm says \(vehicleName) is almost empty. Plan a pit stop."),
                Line(title: "one sleep from empty", body: "\(vehicleName) usually drinks tomorrow. Keep a station in mind."),
            ])
        }
        return pick([
            Line(title: "fuel window incoming", body: "\(vehicleName) usually fills in about \(daysRemaining) days. I've got my eye on it."),
            Line(title: "calendar vs carburetor", body: "Based on your cadence, \(vehicleName) wants a top-up in ~\(daysRemaining) days."),
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
                Line(title: "service is tapping its watch", body: "\(vehicleName)'s \(type) is due. Book it before it gets loud."),
                Line(title: "spanner o'clock", body: "\(type.capitalized) reminder for \(vehicleName) — you're in the window."),
            ])
        }
        if let kmRemaining, kmRemaining <= 150 {
            return pick([
                Line(title: "service almost in reach", body: String(format: "%@ has ~%.0f km until %@. Easy does it.", vehicleName, max(kmRemaining, 0), type)),
            ])
        }
        if let daysRemaining {
            return pick([
                Line(title: "service on the horizon", body: "\(vehicleName)'s \(type) is ~\(daysRemaining) days out. Future-you says thanks."),
            ])
        }
        return Line(title: "service nudge", body: "\(vehicleName) has a \(type) coming up. Worth a glance.")
    }

    private static func pick(_ lines: [Line]) -> Line {
        lines.randomElement() ?? lines[0]
    }
}
