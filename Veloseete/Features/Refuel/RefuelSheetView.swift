import SwiftUI

struct RefuelSheetView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: String

    @State private var totalCost = ""
    @State private var liters = ""
    @State private var odometer = ""
    @State private var isFullTank = true
    @State private var selectedDate = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private var vehicle: Vehicle? {
        store.vehicles.first { $0.id == vehicleId }
    }

    private var currency: String {
        vehicle?.currency ?? "QAR"
    }

    private var lastOdometer: Double {
        let logs = store.fuelLogs
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.timestamp > $1.timestamp }
        return logs.first?.odometerReading ?? vehicle?.currentOdometer ?? 0
    }

    private var pricePerLiter: Double? {
        guard let cost = Double(totalCost), let vol = Double(liters), vol > 0, cost > 0 else { return nil }
        return cost / vol
    }

    private var canSubmit: Bool {
        guard let cost = Double(totalCost), let vol = Double(liters), Double(odometer) != nil else { return false }
        return cost > 0 && vol > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        costField
                        litersField
                    }

                    if let price = pricePerLiter {
                        Text(String(format: "%@ %.3f / L", CurrencyFormat.symbols[currency] ?? currency, price))
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.accentSecondary)
                    }

                    fieldLabel("Odometer (km)")
                    TextField(lastOdometer > 0 ? String(format: "%.0f", lastOdometer) : "0", text: $odometer)
                        .keyboardType(.numberPad)
                        .font(VS.Typography.heading(22, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                        .padding(14)
                        .glassCard(radius: 12)

                    if let entered = Double(odometer), entered < lastOdometer {
                        Text("Lower than last reading (\(DistanceFormat.formatOdometer(lastOdometer, unit: "km")))")
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.warning)
                    }

                    Toggle(isOn: $isFullTank) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full tank")
                                .font(VS.Typography.heading(15))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text("Needed for accurate efficiency")
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.textTertiary)
                        }
                    }
                    .tint(VS.Color.accent)
                    .padding(14)
                    .glassCard()

                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(VS.Color.accent)
                        .padding(14)
                        .glassCard()
                        .foregroundStyle(VS.Color.textPrimary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    if showSuccess {
                        Text("Refuel entry added successfully")
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.success)
                    }
                }
                .padding(20)
            }
            .background(VS.Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Add Refuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        VSIcon(icon: .x, size: 16, weight: .bold, tint: VS.Color.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isSubmitting { ProgressView().tint(VS.Color.navPill) }
                        Text("Save refuel")
                            .font(VS.Typography.heading(17))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSubmit ? VS.Color.accent : VS.Color.accent.opacity(0.35))
                    .foregroundStyle(VS.Color.navPill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!canSubmit || isSubmitting)
                .buttonStyle(ScaleButtonStyle())
                .padding(20)
                .background(VS.Color.bgPrimary.opacity(0.95))
            }
            .onAppear {
                if odometer.isEmpty, lastOdometer > 0 {
                    odometer = String(format: "%.0f", lastOdometer)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var costField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Total Cost")
            HStack {
                TextField("0.00", text: $totalCost)
                    .keyboardType(.decimalPad)
                    .font(VS.Typography.heading(20, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(currency)
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(14)
            .glassCard(radius: 12)
        }
    }

    private var litersField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Litres")
            HStack {
                TextField("0.0", text: $liters)
                    .keyboardType(.decimalPad)
                    .font(VS.Typography.heading(20, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text("L")
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(14)
            .glassCard(radius: 12)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.Typography.body(12, weight: .medium))
            .foregroundStyle(VS.Color.textTertiary)
    }

    private func submit() async {
        guard let cost = Double(totalCost),
              let vol = Double(liters),
              let odo = Double(odometer) else { return }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            var stamp = selectedDate
            let now = Date()
            let cal = Calendar.current
            stamp = cal.date(
                bySettingHour: cal.component(.hour, from: now),
                minute: cal.component(.minute, from: now),
                second: 0,
                of: stamp
            ) ?? stamp

            try await store.addFuelLog(
                vehicleId: vehicleId,
                odometerReading: odo,
                fuelVolume: vol,
                totalCost: cost,
                currency: currency,
                isFullTank: isFullTank,
                timestamp: stamp
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showSuccess = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
