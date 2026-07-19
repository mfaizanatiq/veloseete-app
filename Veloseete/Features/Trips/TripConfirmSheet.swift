import SwiftUI

struct TripConfirmSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var recorder: TripRecordingService
    @Environment(\.dismiss) private var dismiss

    let pending: PendingTripSave

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Confirm drive")
                        .font(VS.Typography.heading(26, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)

                    Text(pending.vehicleName)
                        .font(VS.Typography.body(14, weight: .medium))
                        .foregroundStyle(VS.Color.textSecondary)

                    HStack(spacing: 12) {
                        confirmMetric(String(format: "%.1f", pending.distanceKm), "km")
                        confirmMetric(formatDuration(pending.durationSec), "duration")
                        confirmMetric(String(format: "%.0f", pending.maxSpeedKmh), "max km/h")
                    }

                    HStack(spacing: 12) {
                        VSIcon(icon: .gauge, size: 22, weight: .duotone, tint: VS.Color.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Adds to your estimate")
                                .font(VS.Typography.heading(15))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text("Your verified odometer changes only when you enter the number shown in your car, usually at the next refuel.")
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .glassCard()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    PrimaryCTAButton(
                        title: "Save drive",
                        icon: .checkCircle,
                        isLoading: isSaving
                    ) {
                        Task { await save() }
                    }

                    Button("Discard") {
                        recorder.discardPending()
                        dismiss()
                    }
                    .font(VS.Typography.body(14, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        .veloseeteSheet()
    }

    private func confirmMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label.uppercased())
                .font(VS.Typography.body(11, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricInset()
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await store.saveTrip(pending, odometer: pending.suggestedOdometer, applyOdometer: false)
            recorder.discardPending()
            if recorder.autoTrackingEnabled {
                recorder.setAutoTracking(true)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
