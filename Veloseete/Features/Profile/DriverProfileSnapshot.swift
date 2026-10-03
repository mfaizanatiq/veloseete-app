import Foundation

/// Everything the Driver tab shows, derived once per data change from drives you drove
/// (passenger legs aren't your stats). Rolling windows, not calendar months, so the
/// profile never goes blank just because a new month started.
struct DriverProfileSnapshot: Equatable {
    struct Archetype: Equatable {
        /// "Night-owl Commuter"
        let title: String
        /// "82% of drives start after 9 pm · typical drive 12.7 km"
        let reason: String
    }

    struct Record: Identifiable, Equatable {
        enum Kind: String { case longest, fastest, longestTime, biggestDay }
        let kind: Kind
        let label: String
        let value: String
        let unit: String
        let detail: String
        let systemImage: String
        /// Opens the drive; nil for day-level records.
        let tripId: String?
        var id: String { kind.rawValue }
    }

    struct HeatDay: Equatable {
        let date: Date
        let km: Double
        /// 0 = no drive, 1…4 = share of the window's busiest day.
        let level: Int
        let isToday: Bool
    }

    static let heatmapWeeks = 18

    var driverSince: Date?
    var lifetimeKm: Double = 0
    var lifetimeDrives = 0
    var lifetimeSeconds: Double = 0
    var archetype: Archetype?
    /// 0 calm … 1 spirited, from the last 30 drives' top speeds.
    var styleScore: Double = 0.22

    /// Columns of seven days, oldest week first; nil marks days still ahead this week.
    var heatWeeks: [[HeatDay?]] = []
    var currentWeekStreak = 0
    var bestWeekStreak = 0
    var activeDaysInWindow = 0

    var last30Km: Double = 0
    var prev30Km: Double = 0
    var last30Drives = 0
    var last30Seconds: Double = 0
    var last30TopKmh: Double = 0
    var lastDriveDate: Date?

    var records: [Record] = []
    /// Drives started in each hour of the day, 0…23.
    var hourCounts: [Int] = Array(repeating: 0, count: 24)

    var peakHour: Int? {
        guard let max = hourCounts.max(), max > 0 else { return nil }
        return hourCounts.firstIndex(of: max)
    }

    static func build(
        trips allTrips: [Trip],
        lifetimeKm: Double,
        unit: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DriverProfileSnapshot {
        var snapshot = DriverProfileSnapshot()
        let trips = allTrips.filter(\.countsAsDriven).sorted { $0.startedAt < $1.startedAt }
        snapshot.lifetimeKm = lifetimeKm
        snapshot.lifetimeDrives = trips.count
        snapshot.lifetimeSeconds = trips.reduce(0) { $0 + $1.durationSec }
        snapshot.driverSince = trips.first?.startedAt
        snapshot.lastDriveDate = trips.last?.startedAt

        // Style from recent behaviour, whatever month it was.
        let recent = trips.suffix(30)
        if !recent.isEmpty {
            let avgTop = recent.map(\.maxSpeedKmh).reduce(0, +) / Double(recent.count)
            snapshot.styleScore = min(max((avgTop - 45) / 85, 0.08), 1)
        }

        for trip in trips {
            snapshot.hourCounts[calendar.component(.hour, from: trip.startedAt)] += 1
        }
        snapshot.archetype = archetype(for: trips, unit: unit, calendar: calendar)

        // Rolling 30 days vs the 30 before.
        let day: TimeInterval = 86_400
        let last30 = trips.filter { $0.startedAt > now.addingTimeInterval(-30 * day) }
        let prev30 = trips.filter {
            $0.startedAt > now.addingTimeInterval(-60 * day) && $0.startedAt <= now.addingTimeInterval(-30 * day)
        }
        snapshot.last30Km = last30.reduce(0) { $0 + $1.distanceKm }
        snapshot.prev30Km = prev30.reduce(0) { $0 + $1.distanceKm }
        snapshot.last30Drives = last30.count
        snapshot.last30Seconds = last30.reduce(0) { $0 + $1.durationSec }
        snapshot.last30TopKmh = last30.map(\.maxSpeedKmh).max() ?? 0

        // Distance per calendar day — shared by the heatmap and "biggest day".
        var kmByDay: [Date: Double] = [:]
        for trip in trips {
            kmByDay[calendar.startOfDay(for: trip.startedAt), default: 0] += trip.distanceKm
        }

        buildHeatmap(into: &snapshot, kmByDay: kmByDay, now: now, calendar: calendar)
        buildStreaks(into: &snapshot, trips: trips, now: now, calendar: calendar)
        snapshot.records = records(trips: trips, kmByDay: kmByDay, unit: unit, now: now, calendar: calendar)
        return snapshot
    }

    // MARK: - Pieces

    private static func archetype(for trips: [Trip], unit: String, calendar: Calendar) -> Archetype? {
        guard trips.count >= 3 else { return nil }
        let count = Double(trips.count)
        // Median, not mean: a few long road trips shouldn't redefine your usual drive.
        let lengths = trips.map(\.distanceKm).sorted()
        let mid = lengths.count / 2
        let typicalKm = lengths.count.isMultiple(of: 2) ? (lengths[mid - 1] + lengths[mid]) / 2 : lengths[mid]
        let typicalLabel = "typical drive \(DistanceFormat.formatDistance(typicalKm, unit: unit))"

        let lengthWord: String
        switch typicalKm {
        case ..<6: lengthWord = "City Hopper"
        case ..<25: lengthWord = "Commuter"
        case ..<60: lengthWord = "Cruiser"
        default: lengthWord = "Road Tripper"
        }

        let weekendShare = Double(trips.filter { calendar.isDateInWeekend($0.startedAt) }.count) / count
        if weekendShare >= 0.6 {
            return Archetype(
                title: "Weekend \(lengthWord)",
                reason: "\(percent(weekendShare)) of drives on weekends · \(typicalLabel)"
            )
        }

        // (label, phrase, hours)
        let windows: [(String, String, Range<Int>)] = [
            ("Early-bird", "start before 10 am", 5..<10),
            ("Daytime", "start between 10 am and 4 pm", 10..<16),
            ("Rush-hour", "start between 4 and 9 pm", 16..<21)
        ]
        let hours = trips.map { calendar.component(.hour, from: $0.startedAt) }
        let nightShare = Double(hours.filter { $0 >= 21 || $0 < 5 }.count) / count
        var best: (label: String, phrase: String, share: Double) = ("Night-owl", "start after 9 pm", nightShare)
        for (label, phrase, range) in windows {
            let share = Double(hours.filter { range.contains($0) }.count) / count
            if share > best.share { best = (label, phrase, share) }
        }

        if best.share >= 0.5 {
            return Archetype(
                title: "\(best.label) \(lengthWord)",
                reason: "\(percent(best.share)) of drives \(best.phrase) · \(typicalLabel)"
            )
        }
        return Archetype(title: "All-hours \(lengthWord)", reason: "No fixed schedule · \(typicalLabel)")
    }

    private static func buildHeatmap(
        into snapshot: inout DriverProfileSnapshot,
        kmByDay: [Date: Double],
        now: Date,
        calendar: Calendar
    ) {
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(heatmapWeeks - 1), to: thisWeek) else { return }

        let windowKm = kmByDay.filter { $0.key >= firstWeek && $0.key <= today }
        let peak = max(windowKm.values.max() ?? 0, 0.1)
        snapshot.activeDaysInWindow = windowKm.count

        snapshot.heatWeeks = (0..<heatmapWeeks).map { week in
            (0..<7).map { offset -> HeatDay? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: firstWeek),
                      date <= today else { return nil }
                let km = windowKm[date] ?? 0
                let level: Int
                switch km / peak {
                case 0: level = 0
                case ..<0.25: level = 1
                case ..<0.5: level = 2
                case ..<0.75: level = 3
                default: level = 4
                }
                return HeatDay(date: date, km: km, level: km > 0 ? max(level, 1) : 0, isToday: date == today)
            }
        }
    }

    /// Week streaks: a week counts if it has at least one drive. The current streak stays
    /// alive through this week until it ends, so Monday doesn't reset it to zero.
    private static func buildStreaks(
        into snapshot: inout DriverProfileSnapshot,
        trips: [Trip],
        now: Date,
        calendar: Calendar
    ) {
        let weeks = Set(trips.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start })
        guard !weeks.isEmpty, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return }

        var best = 0, run = 0
        var previous: Date?
        for week in weeks.sorted() {
            if let previous, calendar.date(byAdding: .weekOfYear, value: 1, to: previous) == week {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = week
        }
        snapshot.bestWeekStreak = best

        var cursor = weeks.contains(thisWeek)
            ? thisWeek
            : calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)
        var current = 0
        while let week = cursor, weeks.contains(week) {
            current += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: week)
        }
        snapshot.currentWeekStreak = current
    }

    private static func records(
        trips: [Trip],
        kmByDay: [Date: Double],
        unit: String,
        now: Date,
        calendar: Calendar
    ) -> [Record] {
        guard !trips.isEmpty else { return [] }
        let miles = unit == "mi"

        func dateLabel(_ date: Date) -> String {
            calendar.isDate(date, equalTo: now, toGranularity: .year)
                ? date.formatted(.dateTime.month(.abbreviated).day())
                : date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        func distance(_ km: Double) -> (String, String) {
            let value = miles ? km * 0.621371 : km
            return (value.formatted(.number.precision(.fractionLength(value >= 100 ? 0 : 1))), miles ? "mi" : "km")
        }

        var result: [Record] = []
        if let longest = trips.max(by: { $0.distanceKm < $1.distanceKm }) {
            let (value, unitLabel) = distance(longest.distanceKm)
            result.append(Record(
                kind: .longest, label: "Longest drive", value: value, unit: unitLabel,
                detail: dateLabel(longest.startedAt), systemImage: "arrow.left.and.right", tripId: longest.id
            ))
        }
        if let fastest = trips.max(by: { $0.maxSpeedKmh < $1.maxSpeedKmh }), fastest.maxSpeedKmh > 0 {
            let speed = miles ? fastest.maxSpeedKmh * 0.621371 : fastest.maxSpeedKmh
            result.append(Record(
                kind: .fastest, label: "Top speed", value: speed.formatted(.number.precision(.fractionLength(0))),
                unit: miles ? "mph" : "km/h", detail: dateLabel(fastest.startedAt),
                systemImage: "gauge.with.dots.needle.67percent", tripId: fastest.id
            ))
        }
        if let marathon = trips.max(by: { $0.durationSec < $1.durationSec }) {
            let minutes = Int(marathon.durationSec / 60)
            let (value, unitLabel) = minutes >= 60
                ? ("\(minutes / 60)h \(minutes % 60)", "m")
                : ("\(max(minutes, 1))", "min")
            result.append(Record(
                kind: .longestTime, label: "Longest at the wheel", value: value, unit: unitLabel,
                detail: dateLabel(marathon.startedAt), systemImage: "timer", tripId: marathon.id
            ))
        }
        if let (day, km) = kmByDay.max(by: { $0.value < $1.value }) {
            let (value, unitLabel) = distance(km)
            result.append(Record(
                kind: .biggestDay, label: "Biggest day", value: value, unit: unitLabel,
                detail: dateLabel(day), systemImage: "calendar", tripId: nil
            ))
        }
        return result
    }

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
