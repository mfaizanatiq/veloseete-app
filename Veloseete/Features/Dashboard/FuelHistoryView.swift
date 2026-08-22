import SwiftUI

/// Full fill history for the current vehicle, grouped by month with per-month
/// spend / volume / distance subtotals. Rows open the fill detail sheet.
struct FuelHistoryView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLog: FuelLog?

    private var vehicle: Vehicle? { store.currentVehicle }

    private var volumeUnit: String {
        vehicle?.fuelVolumeUnit ?? VolumeFormat.liters
    }

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let logs: [FuelLog]
        let spend: Double
        let volume: Double
        let distance: Double
    }

    private var groups: [MonthGroup] {
        let logs = store.fuelLogsForCurrentVehicle.sorted { $0.timestamp > $1.timestamp }
        guard !logs.isEmpty else { return [] }

        // Distance credited to the month of the fill that closes each odometer interval.
        var distanceByLogId: [String: Double] = [:]
        let ascending = logs.sorted { $0.timestamp < $1.timestamp }
        for index in 1..<ascending.count {
            let delta = ascending[index].odometerReading - ascending[index - 1].odometerReading
            if delta > 0 { distanceByLogId[ascending[index].id] = delta }
        }

        let calendar = Calendar.current
        var ordered: [String] = []
        var bucket: [String: [FuelLog]] = [:]
        for log in logs {
            let comps = calendar.dateComponents([.year, .month], from: log.timestamp)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if bucket[key] == nil { ordered.append(key) }
            bucket[key, default: []].append(log)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        return ordered.compactMap { key in
            guard let monthLogs = bucket[key], let first = monthLogs.first else { return nil }
            return MonthGroup(
                id: key,
                title: formatter.string(from: first.timestamp),
                logs: monthLogs,
                spend: monthLogs.reduce(0) { $0 + $1.totalCost },
                volume: monthLogs.reduce(0) { $0 + $1.fuelVolume },
                distance: monthLogs.reduce(0) { $0 + (distanceByLogId[$1.id] ?? 0) }
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VS.Spacing.lg) {
                    if groups.isEmpty {
                        Text(TrackyVoice.Soft.emptyHistory)
                            .font(VS.Typography.body(14))
                            .foregroundStyle(VS.Color.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        lifetimeStrip

                        ForEach(groups) { group in
                            monthSection(group)
                        }
                    }
                }
                .padding(.horizontal, VS.Spacing.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle(TrackyVoice.Soft.fillHistory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
            .sheet(item: $selectedLog) { log in
                FillDetailSheet(log: log)
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var lifetimeStrip: some View {
        let logs = store.fuelLogsForCurrentVehicle
        let spend = logs.reduce(0) { $0 + $1.totalCost }
        let volume = logs.reduce(0) { $0 + $1.fuelVolume }
        let currency = vehicle?.currency ?? "QAR"

        return HStack(spacing: 0) {
            lifetimeStat(value: "\(logs.count)", label: "Fills")
            statDivider
            lifetimeStat(value: CurrencyFormat.format(spend, currency: currency), label: "Total spend")
            statDivider
            lifetimeStat(value: VolumeFormat.format(volume, unit: volumeUnit, decimals: 0), label: "Fuel")
        }
        .padding(.vertical, 14)
        .glassCard()
    }

    private var statDivider: some View {
        Rectangle()
            .fill(VS.Color.divider)
            .frame(width: 1, height: 30)
    }

    private func lifetimeStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(VS.Typography.heading(16, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(VS.Typography.body(10, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(monthSubtotal(group))
                    .font(VS.Typography.body(12))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(group.logs) { log in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedLog = log
                    } label: {
                        HStack(spacing: 10) {
                            RefuelRowView(
                                log: log,
                                distanceUnit: store.defaultDistanceUnit,
                                volumeUnit: volumeUnit
                            )
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VS.Color.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    if log.id != group.logs.last?.id {
                        Divider().overlay(VS.Color.divider)
                    }
                }
            }
            .padding(VS.Spacing.md)
            .glassCard()
        }
    }

    private func monthSubtotal(_ group: MonthGroup) -> String {
        let currency = vehicle?.currency ?? group.logs.first?.currency ?? "QAR"
        var parts = [
            CurrencyFormat.format(group.spend, currency: currency),
            VolumeFormat.format(group.volume, unit: volumeUnit)
        ]
        if group.distance > 0 {
            parts.append(DistanceFormat.formatDistance(group.distance, unit: store.defaultDistanceUnit))
        }
        return parts.joined(separator: " · ")
    }
}
