import SwiftUI

// MARK: - Driver card

/// Identity hero: who you are behind the wheel, built from real patterns. Shareable.
struct DriverIdentityCard: View {
    let snapshot: DriverProfileSnapshot
    let displayName: String
    let unit: String
    /// nil when rendered for the share image.
    var onShare: (() -> Void)? = nil

    private var sinceLabel: String {
        guard let since = snapshot.driverSince else { return "NEW DRIVER" }
        return "DRIVER SINCE \(since.formatted(.dateTime.month(.abbreviated).year()).uppercased())"
    }

    private var isShareImage: Bool { onShare == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: isShareImage ? 18 : 20) {
            if isShareImage {
                HStack {
                    Text(sinceLabel)
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.accent)
                    Spacer(minLength: 8)
                    Text("VELOSEETE")
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }

            // One job in the app: who you are behind the wheel.
            VStack(alignment: .leading, spacing: 6) {
                if isShareImage {
                    Text(displayName)
                        .font(VS.TextStyle.callout(.semibold))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                Text(snapshot.archetype?.title ?? "Finding your style")
                    .font(VS.TextStyle.title())
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    // Clear the corner share button without giving up the title's width.
                    .padding(.trailing, isShareImage ? 0 : 40)
                Text(snapshot.archetype?.reason ?? "A few more drives and Tracky will know your rhythm.")
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if let onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(VS.Color.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Share driver card")
                }
            }

            // Lifetime totals sit in the page header in-app; the share image needs them.
            if isShareImage {
                HStack(alignment: .top, spacing: 0) {
                    lifetimeStat(value: lifetimeDistance, unit: unit == "mi" ? "mi" : "km", label: "Lifetime")
                    divider
                    lifetimeStat(value: snapshot.lifetimeDrives.formatted(), unit: nil, label: "Drives")
                    divider
                    lifetimeStat(value: DriverProfileFormat.hours(snapshot.lifetimeSeconds), unit: nil, label: "At the wheel")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                DriverStyleSpectrumBar(thirst: snapshot.styleScore)
                HStack {
                    Text("Calm")
                    Spacer(minLength: 0)
                    Text("Spirited")
                }
                .font(VS.TextStyle.caption(.medium))
                .foregroundStyle(VS.Color.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Driving style, \(Int(snapshot.styleScore * 100)) percent toward spirited")
        }
        .padding(VS.Spacing.card + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same surface as every other card — no one-off decoration.
        .glassCard(elevated: true)
    }

    private var lifetimeDistance: String {
        let value = unit == "mi" ? snapshot.lifetimeKm * 0.621371 : snapshot.lifetimeKm
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func lifetimeStat(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(VS.TextStyle.title2().monospacedDigit())
                    .foregroundStyle(VS.Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(VS.TextStyle.caption(.semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(VS.TextStyle.label())
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(VS.Color.hairline)
            .frame(width: 1, height: 34)
            .padding(.trailing, 14)
    }
}

// MARK: - Rhythm heatmap

/// GitHub-style grid of the last weeks: one cell per day, brighter = more distance.
struct DriverRhythmCard: View {
    let snapshot: DriverProfileSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthLabels

            HStack(alignment: .top, spacing: 4) {
                ForEach(snapshot.heatWeeks.indices, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            cell(snapshot.heatWeeks[week][day])
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Driving calendar: \(snapshot.activeDaysInWindow) active days in the last \(DriverProfileSnapshot.heatmapWeeks) weeks")

            HStack(alignment: .top, spacing: 0) {
                stat("\(snapshot.currentWeekStreak)", unit: snapshot.currentWeekStreak == 1 ? "wk" : "wks", label: "Streak")
                stat("\(snapshot.bestWeekStreak)", unit: snapshot.bestWeekStreak == 1 ? "wk" : "wks", label: "Best")
                stat("\(snapshot.activeDaysInWindow)", unit: "days", label: "Active")
                legend
            }
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    /// Month initials above the column where each month starts.
    private var monthLabels: some View {
        HStack(spacing: 4) {
            ForEach(snapshot.heatWeeks.indices, id: \.self) { week in
                let first = snapshot.heatWeeks[week].compactMap { $0 }.first?.date
                let label: String? = {
                    guard let first else { return nil }
                    let previous = week > 0 ? snapshot.heatWeeks[week - 1].compactMap({ $0 }).first?.date : nil
                    let month = Calendar.current.component(.month, from: first)
                    if let previous, Calendar.current.component(.month, from: previous) == month { return nil }
                    return first.formatted(.dateTime.month(.abbreviated))
                }()
                Text(label ?? " ")
                    .font(VS.TextStyle.label(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(_ day: DriverProfileSnapshot.HeatDay?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            if let day {
                shape
                    .fill(color(for: day.level))
                    .overlay(day.isToday ? shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1) : nil)
            } else {
                shape.fill(Color.clear)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.06)
        case 1: return VS.Color.accent.opacity(0.28)
        case 2: return VS.Color.accent.opacity(0.5)
        case 3: return VS.Color.accent.opacity(0.75)
        default: return VS.Color.accent
        }
    }

    private func stat(_ value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(VS.TextStyle.title3().monospacedDigit())
                    .foregroundStyle(VS.Color.textPrimary)
                Text(unit)
                    .font(VS.TextStyle.caption(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            Text(label.uppercased())
                .font(VS.TextStyle.label())
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: 8, height: 8)
                }
            }
            Text("LESS · MORE")
                .font(VS.TextStyle.label(.medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Last 30 days

struct DriverLast30Card: View {
    let snapshot: DriverProfileSnapshot
    let unit: String

    private var trend: (text: String, up: Bool)? {
        guard snapshot.prev30Km > 5, snapshot.last30Km > 0 else { return nil }
        let change = (snapshot.last30Km - snapshot.prev30Km) / snapshot.prev30Km * 100
        if abs(change) < 3 { return ("Steady vs prior 30 days", true) }
        let value = Int(abs(change).rounded())
        return change > 0 ? ("↑ \(value)% vs prior 30 days", true) : ("↓ \(value)% vs prior 30 days", false)
    }

    var body: some View {
        if snapshot.last30Drives == 0 {
            quietStretch
        } else {
            active
        }
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.gutter) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DISTANCE")
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(distanceValue(snapshot.last30Km))
                        .font(VS.TextStyle.display())
                        .foregroundStyle(VS.Color.textPrimary)
                        .contentTransition(.numericText())
                    Text(unit == "mi" ? "mi" : "km")
                        .font(VS.TextStyle.title3())
                        .foregroundStyle(VS.Color.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                if let trend {
                    Text(trend.text)
                        .font(VS.TextStyle.caption(.semibold))
                        .foregroundStyle(trend.up ? VS.Color.accent : VS.Color.textSecondary)
                }
            }
            .padding(VS.Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(elevated: true)

            HStack(spacing: VS.Spacing.gutter) {
                DriverStatChip(icon: .car, value: "\(snapshot.last30Drives)", label: "Drives")
                DriverStatChip(icon: .roadHorizon, value: DriverProfileFormat.hours(snapshot.last30Seconds), label: "At the wheel")
                DriverStatChip(
                    icon: .gauge,
                    value: speedValue(snapshot.last30TopKmh),
                    label: unit == "mi" ? "Top mph" : "Top km/h"
                )
            }
        }
    }

    /// Honest empty state: when you last drove, not a wall of dashes.
    private var quietStretch: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VS.Color.accent)
                .frame(width: 44, height: 44)
                .background(VS.Color.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Quiet stretch")
                    .font(VS.TextStyle.headline())
                    .foregroundStyle(VS.Color.textPrimary)
                Text(lastDriveLine)
                    .font(VS.TextStyle.footnote())
                    .foregroundStyle(VS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private var lastDriveLine: String {
        guard let last = snapshot.lastDriveDate else { return "Your first drive will show up here." }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return "Last drive \(last.formatted(.dateTime.month(.abbreviated).day())) · \(days) day\(days == 1 ? "" : "s") ago"
    }

    private func distanceValue(_ km: Double) -> String {
        let value = unit == "mi" ? km * 0.621371 : km
        return value.formatted(.number.precision(.fractionLength(value >= 100 ? 0 : 1)))
    }

    private func speedValue(_ kmh: Double) -> String {
        (unit == "mi" ? kmh * 0.621371 : kmh).formatted(.number.precision(.fractionLength(0)))
    }
}

// MARK: - Personal records

struct DriverRecordsRow: View {
    let records: [DriverProfileSnapshot.Record]
    let onSelect: (DriverProfileSnapshot.Record) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VS.Spacing.gutter) {
                ForEach(records) { record in
                    Button {
                        onSelect(record)
                    } label: {
                        card(record)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(record.tripId == nil)
                }
            }
            .padding(.horizontal, VS.Spacing.pageInset)
        }
        .padding(.horizontal, -VS.Spacing.pageInset)
    }

    private func card(_ record: DriverProfileSnapshot.Record) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: record.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(VS.Color.navPill)
                .frame(width: 32, height: 32)
                .background(VS.Color.accent, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(record.label.uppercased())
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(record.value)
                        .font(VS.TextStyle.title().monospacedDigit())
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(record.unit)
                        .font(VS.TextStyle.callout(.semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(record.detail)
                    .font(VS.TextStyle.caption(.medium))
                    .foregroundStyle(VS.Color.textSecondary)
            }
        }
        .padding(VS.Spacing.card)
        .frame(width: 168, alignment: .leading)
        .glassCard(elevated: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint(record.tripId == nil ? "" : "Opens this drive")
    }
}

// MARK: - Your hours

/// When you drive: one bar per hour of the day, the peak in accent.
struct DriverHoursCard: View {
    let hourCounts: [Int]
    let peakHour: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let peakHour {
                (Text("You usually head out around ")
                    .foregroundStyle(VS.Color.textSecondary)
                 + Text(Self.hourLabel(peakHour, style: .long))
                    .foregroundStyle(VS.Color.textPrimary))
                    .font(VS.TextStyle.callout(.semibold))
            }

            let peak = max(hourCounts.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    Capsule()
                        .fill(hour == peakHour ? VS.Color.accent : Color.white.opacity(hourCounts[hour] > 0 ? 0.28 : 0.08))
                        .frame(height: max(4, 64 * CGFloat(hourCounts[hour]) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(peakHour.map { "Most drives start around \(Self.hourLabel($0, style: .long))" } ?? "No drives yet")

            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(Self.hourLabel(hour, style: .short))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(VS.TextStyle.label(.medium))
            .foregroundStyle(VS.Color.textTertiary)
            .accessibilityHidden(true)
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    enum HourStyle { case short, long }

    static func hourLabel(_ hour: Int, style: HourStyle) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        switch style {
        case .short: return "\(twelve)\(suffix.lowercased().prefix(1))"
        case .long: return "\(twelve) \(suffix)"
        }
    }
}

enum DriverProfileFormat {
    /// "126 h", "9h 40m", "45m"
    static func hours(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        if hours >= 100 { return "\(hours) h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(max(minutes, 0))m"
    }
}
