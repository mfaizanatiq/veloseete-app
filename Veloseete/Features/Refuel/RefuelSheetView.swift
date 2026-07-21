import SwiftUI

struct RefuelSheetView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: String
    let carPlayDraft: CarPlayRefuelDraft?

    @State private var totalCost = ""
    @State private var liters = ""
    @State private var odometer = ""
    @State private var isFullTank = true
    @State private var selectedDate = Date()
    @State private var selectedCurrency = "QAR"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let entryCurrencies = ["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"]

    init(vehicleId: String, carPlayDraft: CarPlayRefuelDraft? = nil) {
        self.vehicleId = vehicleId
        self.carPlayDraft = carPlayDraft
        _selectedDate = State(initialValue: carPlayDraft?.createdAt ?? Date())
        _odometer = State(
            initialValue: carPlayDraft.map { String(format: "%.0f", $0.estimatedOdometer) } ?? ""
        )
    }

    private var vehicle: Vehicle? {
        store.vehicles.first { $0.id == vehicleId }
    }

    private var defaultCurrency: String {
        vehicle?.currency ?? "QAR"
    }

    private var lastOdometer: Double {
        let logs = store.fuelLogs
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.timestamp > $1.timestamp }
        return logs.first?.odometerReading ?? vehicle?.currentOdometer ?? 0
    }

    private var estimate: OdometerEstimate? {
        store.odometerEstimate(vehicleId: vehicleId, through: selectedDate)
    }

    private var enteredOdometer: Double? { Double(odometer) }

    private var varianceKm: Double? {
        guard let enteredOdometer, let estimate else { return nil }
        return enteredOdometer - estimate.estimatedKm
    }

    private var pricePerLiter: Double? {
        guard let cost = Double(totalCost), let vol = Double(liters), vol > 0, cost > 0 else { return nil }
        return cost / vol
    }

    private var canSubmit: Bool {
        guard let cost = Double(totalCost), let vol = Double(liters), let enteredOdometer else { return false }
        return cost > 0 && vol > 0 && enteredOdometer >= lastOdometer
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let carPlayDraft {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "car.side.fill")
                                .foregroundStyle(VS.Color.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Continued from CarPlay")
                                    .font(VS.Typography.body(13, weight: .semibold))
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text("Time and estimated odometer are ready for \(carPlayDraft.vehicleName). Add the exact receipt values below.")
                                    .font(VS.Typography.body(12))
                                    .foregroundStyle(VS.Color.textTertiary)
                            }
                        }
                        .padding(14)
                        .glassCard(radius: 12)
                    }

                    HStack(spacing: 12) {
                        costField
                        litersField
                    }

                    if let price = pricePerLiter {
                        Text(String(format: "%@ %.3f / L", CurrencyFormat.symbols[selectedCurrency] ?? selectedCurrency, price))
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.accentSecondary)
                    }

                    currencyPicker

                    odometerSection

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
            .veloseetePage()
            .navigationTitle("Add Refuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryCTAButton(
                    title: "Save refuel",
                    icon: .gasPump,
                    isLoading: isSubmitting,
                    isEnabled: canSubmit
                ) {
                    Task { await submit() }
                }
                .padding(20)
                .background(VS.Color.bgPrimary.opacity(0.96))
            }
            .onAppear {
                selectedCurrency = defaultCurrency
                if odometer.isEmpty, let estimate {
                    odometer = String(format: "%.0f", estimate.estimatedKm)
                } else if odometer.isEmpty, lastOdometer > 0 {
                    odometer = String(format: "%.0f", lastOdometer)
                }
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var odometerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                fieldLabel("Dashboard odometer (km)")
                Spacer()
                if let estimate {
                    Text("Estimate " + String(format: "%.0f", estimate.estimatedKm))
                        .font(VS.Typography.body(11, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                }
            }

            TextField(lastOdometer > 0 ? String(format: "%.0f", lastOdometer) : "0", text: $odometer)
                .keyboardType(.numberPad)
                .font(VS.Typography.heading(26, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .padding(14)
                .glassCard(radius: 12, elevated: true)

            Text("Enter the number physically shown in your vehicle. This becomes the new verified reading.")
                .font(VS.Typography.body(12))
                .foregroundStyle(VS.Color.textTertiary)

            if let varianceKm {
                HStack(spacing: 9) {
                    VSIcon(
                        icon: abs(varianceKm) <= 2 ? .checkCircle : .warningCircle,
                        size: 18,
                        weight: .fill,
                        tint: abs(varianceKm) <= 2 ? VS.Color.success : VS.Color.warning
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(abs(varianceKm) <= 2 ? "Tracking matches closely" : "Reconciles GPS variance")
                            .font(VS.Typography.body(12, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(String(format: "%@%.1f km versus the trip estimate", varianceKm >= 0 ? "+" : "", varianceKm))
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                }
                .padding(12)
                .metricInset()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.28), value: varianceKm)
    }

    private var costField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Total Cost")
            HStack {
                TextField("0.00", text: $totalCost)
                    .keyboardType(.decimalPad)
                    .font(VS.Typography.heading(20, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(selectedCurrency)
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(14)
            .glassCard(radius: 12)
        }
    }

    private var currencyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                fieldLabel("Currency for this fill")
                Spacer()
                if selectedCurrency == defaultCurrency {
                    Text("Vehicle default")
                        .font(VS.Typography.body(11, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entryCurrencies, id: \.self) { code in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedCurrency = code
                        } label: {
                            Text(code)
                                .font(VS.Typography.body(13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(selectedCurrency == code ? VS.Color.accent : VS.Color.chip)
                                )
                                .foregroundStyle(selectedCurrency == code ? VS.Color.navPill : VS.Color.textSecondary)
                                .overlay(
                                    Capsule().stroke(
                                        code == defaultCurrency && selectedCurrency != code
                                            ? VS.Color.accent.opacity(0.35)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Defaults to \(defaultCurrency). Switch when you fill up in KSA, UAE, or elsewhere — only this entry changes.")
                .font(VS.Typography.body(12))
                .foregroundStyle(VS.Color.textTertiary)
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
                currency: selectedCurrency,
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
