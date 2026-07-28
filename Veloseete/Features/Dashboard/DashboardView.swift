import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    var onProfile: () -> Void

    @State private var showRefuel = false

    private var vehicle: Vehicle? { store.currentVehicle }

    private var metrics: EfficiencyMetrics? {
        guard let vehicle else { return nil }
        return MetricsCalculator.compute(vehicle: vehicle, logs: store.fuelLogs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VS.Spacing.section) {
                topBar

                if !store.loadWarnings.isEmpty {
                    Text(store.loadWarnings.joined(separator: "\n"))
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.warning)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: 12)
                }

                syncStatusChip

                if let vehicle, let metrics {
                    HeroCard(
                        vehicle: vehicle,
                        efficiency: metrics.current,
                        manufacturerStandard: store.manufacturerStandard,
                        refuelCount: metrics.efficiencySampleCount,
                        distanceUnit: store.defaultDistanceUnit
                    )

                    PrimaryCTAButton {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showRefuel = true
                    }

                    MetricsRow(metrics: metrics, currency: vehicle.currency, unit: store.defaultDistanceUnit)

                    recentSection(metrics.recentLogs)
                } else {
                    ProgressView().tint(VS.Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, VS.Spacing.pageInset)
            .padding(.bottom, 110)
            .tracksBottomNavScroll()
        }
        .veloseetePage()
        .refreshable {
            if let uid = AuthService.shared.userId {
                await store.loadAll(userId: uid)
            }
        }
        .sheet(isPresented: $showRefuel) {
            if let vehicle {
                RefuelSheetView(vehicleId: vehicle.id)
            }
        }
    }

    private var syncStatusChip: some View {
        let vehicleLogs = store.fuelLogsForCurrentVehicle
        return HStack(spacing: 8) {
            VSIcon(icon: .cloud, size: 12, weight: .bold, tint: VS.Color.textTertiary)
            Text("\(store.vehicles.count) cars · \(vehicleLogs.count) refuels synced")
                .font(VS.Typography.body(11, weight: .medium))
            Spacer()
            if let email = AuthService.shared.user?.email {
                Text(email)
                    .font(VS.Typography.body(10))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(VS.Color.textTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(radius: 12)
    }

    private var topBar: some View {
        MainTabHeader(
            "Fuels",
            subtitle: vehicle.map { "\($0.nickname) · fill & spend" } ?? "Fill & spend",
            onProfile: onProfile
        )
    }

    private func recentSection(_ logs: [FuelLog]) -> some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "Recent fills")

            if logs.isEmpty {
                VStack(spacing: 14) {
                    FluentEmojiView(emoji: "⛽", size: 48)
                    Text("First fill’s the charm")
                        .font(VS.Typography.heading(16))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("Track a refill — spend and efficiency kick in.")
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(logs) { log in
                        RefuelRowView(
                            log: log,
                            distanceUnit: store.defaultDistanceUnit,
                            volumeUnit: vehicle?.fuelVolumeUnit ?? VolumeFormat.liters
                        )
                        if log.id != logs.last?.id {
                            Divider().overlay(VS.Color.divider)
                        }
                    }
                }
                .padding(VS.Spacing.md)
                .glassCard()
            }
        }
    }
}

struct HeroCard: View {
    let vehicle: Vehicle
    let efficiency: Double?
    let manufacturerStandard: Double?
    let refuelCount: Int
    let distanceUnit: String

    private var vibe: EfficiencyVibe {
        DashboardCopy.vibe(efficiency: efficiency, standard: manufacturerStandard, refuelCount: refuelCount)
    }

    private var status: (text: String, tone: EfficiencyVibe.Tone) {
        DashboardCopy.status(efficiency: efficiency, standard: manufacturerStandard, sampleCount: refuelCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            tonePill(emoji: vibe.emoji, text: vibe.label, tone: vibe.tone)

            Text(vehicle.nickname)
                .font(VS.Typography.heading(22, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)

            Text("\(vehicle.make) \(vehicle.model)")
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textTertiary)

            HStack(spacing: 12) {
                metricTile(
                    icon: .gauge,
                    label: "Efficiency",
                    value: efficiency.map { String(format: "%.1f" , $0) } ?? "—",
                    unit: "L/100km"
                )
                metricTile(
                    icon: .car,
                    label: "Odometer",
                    value: DistanceFormat.formatOdometer(vehicle.currentOdometer, unit: distanceUnit),
                    unit: nil
                )
            }

            tonePill(emoji: nil, text: status.text, tone: status.tone)

            if refuelCount < 3 && efficiency == nil {
                Text("A few fills and this car’s personality shows up.")
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textTertiary)
            }
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private func metricTile(icon: VSIconName, label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                VSIcon(icon: icon, size: 12, weight: .regular, tint: VS.Color.textTertiary)
                Text(label.uppercased())
                    .font(VS.Typography.body(11, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(VS.Typography.heading(28, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(VS.Typography.body(13, weight: .semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricInset()
    }

    private func tonePill(emoji: String?, text: String, tone: EfficiencyVibe.Tone) -> some View {
        let colors = toneColors(tone)
        return HStack(spacing: 6) {
            if let emoji { FluentEmojiView(emoji: emoji, size: 16) }
            Text(text)
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(colors.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(colors.bg)
                .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
                .shadow(color: colors.text.opacity(0.15), radius: 6, y: 1)
        )
    }

    private func toneColors(_ tone: EfficiencyVibe.Tone) -> (bg: Color, border: Color, text: Color) {
        switch tone {
        case .excellent:
            return (VS.Color.accent.opacity(0.15), VS.Color.accent.opacity(0.35), VS.Color.accent)
        case .good:
            return (VS.Color.accentSecondary.opacity(0.15), VS.Color.accentSecondary.opacity(0.35), VS.Color.accentSecondary)
        case .neutral:
            return (Color.white.opacity(0.06), Color.white.opacity(0.12), VS.Color.textSecondary)
        case .watch:
            return (VS.Color.warning.opacity(0.12), VS.Color.warning.opacity(0.3), VS.Color.warning)
        case .learning:
            return (Color.white.opacity(0.06), Color.white.opacity(0.12), VS.Color.textTertiary)
        }
    }
}

struct MetricsRow: View {
    let metrics: EfficiencyMetrics
    let currency: String
    let unit: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCard(
                    label: "This month",
                    value: CurrencyFormat.format(metrics.monthlySpend, currency: currency),
                    helper: DashboardCopy.spendTrend(metrics.spendChange)
                )
                metricCard(
                    label: "Avg efficiency",
                    value: metrics.avgEfficiency.map { String(format: "%.1f L/100", $0) } ?? "—",
                    helper: metrics.efficiencySampleCount == 0
                        ? "Needs two full-tank fills"
                        : "\(metrics.efficiencySampleCount) valid interval\(metrics.efficiencySampleCount == 1 ? "" : "s")"
                )
            }
            metricCard(
                label: "Distance driven",
                value: metrics.totalDistance > 0
                    ? DistanceFormat.formatDistance(metrics.totalDistance, unit: unit)
                    : "—",
                helper: "This month"
            )
        }
    }

    private func metricCard(label: String, value: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(VS.Typography.body(11, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
            Text(value)
                .font(VS.Typography.heading(18, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(helper)
                .font(VS.Typography.body(12))
                .foregroundStyle(VS.Color.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(elevated: false)
    }
}

struct RefuelRowView: View {
    let log: FuelLog
    let distanceUnit: String
    var volumeUnit: String = VolumeFormat.liters

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.timestamp.formatted(date: .abbreviated, time: .omitted))
                    .font(VS.Typography.heading(14))
                    .foregroundStyle(VS.Color.textPrimary)
                Text("\(VolumeFormat.format(log.fuelVolume, unit: volumeUnit)) · \(DistanceFormat.formatOdometer(log.odometerReading, unit: distanceUnit))")
                    .font(VS.Typography.body(12))
                    .foregroundStyle(VS.Color.textTertiary)
                if let station = log.stationName, !station.isEmpty {
                    Text(station)
                        .font(VS.Typography.body(11, weight: .medium))
                        .foregroundStyle(VS.Color.accentSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(CurrencyFormat.format(log.totalCost, currency: log.currency))
                .font(VS.Typography.heading(15))
                .foregroundStyle(VS.Color.textPrimary)
        }
        .padding(.vertical, 10)
    }
}
