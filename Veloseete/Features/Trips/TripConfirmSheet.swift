import SwiftUI

struct TripConfirmSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var recorder: TripRecordingService
    @Environment(\.dismiss) private var dismiss

    let pending: PendingTripSave

    @State private var odometerText = ""
    @State private var applyOdometer = true
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("New odometer")
                            .font(VS.Typography.body(12, weight: .semibold))
                            .foregroundStyle(VS.Color.textTertiary)
                        TextField("Odometer", text: $odometerText)
                            .keyboardType(.decimalPad)
                            .font(VS.Typography.heading(22, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                            .vsInputField()

                        Toggle(isOn: $applyOdometer) {
                            Text("Apply to vehicle odometer")
                                .font(VS.Typography.body(14))
                                .foregroundStyle(VS.Color.textSecondary)
                        }
                        .tint(VS.Color.accent)
                    }
                    .padding(14)
                    .glassCard()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(VS.Color.navPill) }
                            Text("Save drive")
                                .font(VS.Typography.heading(17))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VS.Color.accent, in: RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                        .foregroundStyle(VS.Color.navPill)
                    }
                    .disabled(isSaving)
                    .buttonStyle(ScaleButtonStyle())

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
            .background(VS.Color.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        VSIcon(icon: .x, size: 16, weight: .bold, tint: VS.Color.textSecondary)
                    }
                }
            }
            .onAppear {
                odometerText = String(format: "%.1f", pending.suggestedOdometer)
            }
        }
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
        guard let odo = Double(odometerText), odo >= 0 else {
            errorMessage = "Enter a valid odometer reading"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            _ = try await store.saveTrip(pending, odometer: odo, applyOdometer: applyOdometer)
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
