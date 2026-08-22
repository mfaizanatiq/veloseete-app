import SwiftUI

struct RefuelSheetView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: String
    let carPlayDraft: CarPlayRefuelDraft?
    /// When set, the sheet edits this log in place instead of creating a new one.
    let existingLog: FuelLog?

    @State private var totalCost = ""
    @State private var liters = ""
    @State private var odometer = ""
    @State private var isFullTank = true
    @State private var selectedDate = Date()
    @State private var selectedCurrency = "QAR"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var station: StationLookup.Station?
    @State private var nearbyStations: [StationLookup.Station] = []
    @State private var isResolvingStation = false
    @State private var stationLookupFailed = false
    @State private var stationSkipped = false
    @State private var showStationMap = false

    private let entryCurrencies = ["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"]

    private var resolvedStationForSave: (name: String, latitude: Double?, longitude: Double?)? {
        if stationSkipped { return nil }
        guard let station else { return nil }
        // A station carried over from an edited log may have no stored coordinates.
        if station.latitude == 0, station.longitude == 0 {
            return (station.name, nil, nil)
        }
        return (station.name, station.latitude, station.longitude)
    }

    init(vehicleId: String, carPlayDraft: CarPlayRefuelDraft? = nil, editing log: FuelLog? = nil) {
        self.vehicleId = vehicleId
        self.carPlayDraft = carPlayDraft
        self.existingLog = log

        if let log {
            _selectedDate = State(initialValue: log.timestamp)
            _odometer = State(initialValue: String(format: "%.0f", log.odometerReading))
            _totalCost = State(initialValue: String(format: "%.2f", log.totalCost))
            _isFullTank = State(initialValue: log.isFullTank)
            if let name = log.stationName, !name.isEmpty {
                _station = State(initialValue: StationLookup.Station(
                    name: name,
                    latitude: log.stationLatitude ?? 0,
                    longitude: log.stationLongitude ?? 0
                ))
            }
        } else {
            _selectedDate = State(initialValue: carPlayDraft?.createdAt ?? Date())
            _odometer = State(
                initialValue: carPlayDraft.map { String(format: "%.0f", $0.estimatedOdometer) } ?? ""
            )
        }
    }

    private var isEditing: Bool { existingLog != nil }

    private var vehicle: Vehicle? {
        store.vehicles.first { $0.id == vehicleId }
    }

    private var volumeUnit: String {
        vehicle?.fuelVolumeUnit ?? VolumeFormat.liters
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

    private var pricePerUnit: Double? {
        guard let cost = Double(totalCost), let vol = Double(liters), vol > 0, cost > 0 else { return nil }
        return cost / vol
    }

    private var canSubmit: Bool {
        guard let cost = Double(totalCost), let vol = Double(liters), let enteredOdometer else { return false }
        // Editing an older fill legitimately carries an odometer below the latest reading.
        let odometerOK = isEditing ? enteredOdometer > 0 : enteredOdometer >= lastOdometer
        return cost > 0 && vol > 0 && odometerOK
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if carPlayDraft != nil {
                        Label("From CarPlay", systemImage: "car.side.fill")
                            .font(VS.Typography.body(13, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }

                    // Receipt amounts
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            costField
                            litersField
                        }

                        if let price = pricePerUnit {
                            Text(String(
                                format: "%@ %.3f / %@",
                                CurrencyFormat.symbols[selectedCurrency] ?? selectedCurrency,
                                price,
                                VolumeFormat.suffix(volumeUnit)
                            ))
                                .font(VS.Typography.body(13, weight: .medium))
                                .foregroundStyle(VS.Color.accentSecondary)
                        }

                        currencyPicker
                    }

                    // Odometer
                    VStack(alignment: .leading, spacing: 12) {
                        odometerSection

                        if !isEditing, let entered = Double(odometer), entered < lastOdometer {
                            Text("Below last reading (\(DistanceFormat.formatOdometer(lastOdometer, unit: "km")))")
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.warning)
                        }
                    }

                    // Fill details
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Full tank", isOn: $isFullTank)
                            .font(VS.Typography.heading(15))
                            .foregroundStyle(VS.Color.textPrimary)
                            .tint(VS.Color.accent)
                            .padding(14)
                            .glassCard()

                        stationCard

                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(VS.Color.accent)
                            .padding(14)
                            .glassCard()
                            .foregroundStyle(VS.Color.textPrimary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    if showSuccess {
                        Text("Saved")
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.success)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle(isEditing ? TrackyVoice.Calm.editFillNav : TrackyVoice.Calm.addFillNav)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryCTAButton(
                    title: isEditing ? TrackyVoice.Calm.saveFillChanges : TrackyVoice.Calm.saveFill,
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
                if let existingLog {
                    selectedCurrency = existingLog.currency
                    if liters.isEmpty {
                        let display = VolumeFormat.toDisplay(existingLog.fuelVolume, unit: volumeUnit)
                        liters = String(format: "%.2f", display)
                    }
                } else {
                    selectedCurrency = defaultCurrency
                    if odometer.isEmpty, let estimate {
                        odometer = String(format: "%.0f", estimate.estimatedKm)
                    } else if odometer.isEmpty, lastOdometer > 0 {
                        odometer = String(format: "%.0f", lastOdometer)
                    }
                }
            }
            .task {
                await resolveStation()
            }
            .sheet(isPresented: $showStationMap) {
                StationMapPickerView(
                    initialStations: nearbyStations,
                    initialSelection: station
                ) { picked in
                    station = picked
                    if !nearbyStations.contains(where: { $0.id == picked.id }) {
                        nearbyStations.insert(picked, at: 0)
                    }
                    stationSkipped = false
                }
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var stationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(VS.Color.accent)
                Text("Station")
                    .font(VS.Typography.body(12, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
                Text("Optional")
                    .font(VS.Typography.body(10, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary.opacity(0.75))
                Spacer(minLength: 0)
                if isResolvingStation {
                    ProgressView()
                        .controlSize(.small)
                        .tint(VS.Color.accent)
                } else if let station, !stationSkipped, station.distanceMeters > 0 {
                    Text(distanceLabel(for: station))
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }

            if let station, !stationSkipped {
                Text(station.name)
                    .font(VS.Typography.heading(15))
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
            }

            if stationLookupFailed, station == nil, !isResolvingStation {
                HStack(spacing: 10) {
                    Text("Couldn’t find stations nearby.")
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textTertiary)
                    Button("Retry") {
                        Task { await resolveStation(forceRefresh: true) }
                    }
                    .font(VS.Typography.body(12, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
                }
            }

            if !nearbyStations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(nearbyStations) { candidate in
                            let selected = station?.id == candidate.id && !stationSkipped
                            VSSelectableChip(title: candidate.name, selected: selected) {
                                station = candidate
                                stationSkipped = false
                            }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                Button(station == nil || stationSkipped ? "Skip" : "Clear") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    stationSkipped = true
                    station = nil
                }
                .font(VS.Typography.body(13, weight: .semibold))
                .foregroundStyle(VS.Color.textSecondary)

                Button {
                    showStationMap = true
                } label: {
                    Label("Map", systemImage: "map")
                        .font(VS.Typography.body(13, weight: .semibold))
                }
                .foregroundStyle(VS.Color.accent)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .glassCard()
    }

    private func distanceLabel(for station: StationLookup.Station) -> String {
        if station.distanceMeters < 80 {
            return "At the pump"
        }
        if station.distanceMeters < 1_000 {
            return String(format: "%.0f m away", station.distanceMeters)
        }
        return String(format: "%.1f km away", station.distanceMeters / 1_000)
    }

    private func resolveStation(forceRefresh: Bool = false) async {
        isResolvingStation = true
        stationLookupFailed = false
        defer { isResolvingStation = false }

        let found = await StationLookup.nearbyPetrolStations(limit: 8)
        nearbyStations = found
        stationLookupFailed = found.isEmpty

        if stationSkipped, !forceRefresh { return }

        if forceRefresh {
            stationSkipped = false
        }

        // Editing an old fill from wherever the user is now — never overwrite its station.
        if isEditing { return }

        if let auto = found.first(where: { $0.distanceMeters <= StationLookup.autoSelectMaxMeters }) {
            if forceRefresh || station == nil {
                station = auto
                stationSkipped = false
            }
        } else if forceRefresh || station != nil {
            // Far from pumps — leave unset so Skip / map pick stay optional.
            station = nil
        }
    }

    private var odometerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("Odometer (km)")
                Spacer()
                if let estimate {
                    Text("~" + String(format: "%.0f", estimate.estimatedKm))
                        .font(VS.Typography.body(11, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                }
            }

            TextField(lastOdometer > 0 ? String(format: "%.0f", lastOdometer) : "0", text: $odometer)
                .keyboardType(.numberPad)
                .font(VS.Typography.heading(32, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .vsInputField()

            if let estimate, estimate.includesPending {
                Text(TrackyVoice.Calm.estimateIncludesPending)
                    .font(VS.Typography.body(12, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            if let varianceKm {
                HStack(spacing: 8) {
                    VSIcon(
                        icon: abs(varianceKm) <= 2 ? .checkCircle : .warningCircle,
                        size: 16,
                        weight: .fill,
                        tint: abs(varianceKm) <= 2 ? VS.Color.success : VS.Color.warning
                    )
                    Text(String(format: "%@%.1f km vs estimate", varianceKm >= 0 ? "+" : "", varianceKm))
                        .font(VS.Typography.body(12, weight: .medium))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .metricInset()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.28), value: varianceKm)
    }

    private var costField: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Cost")
            HStack {
                TextField("0.00", text: $totalCost)
                    .keyboardType(.decimalPad)
                    .font(VS.Typography.heading(22, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(selectedCurrency)
                    .font(VS.Typography.body(15, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .vsInputField()
        }
    }

    private var currencyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Currency")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(entryCurrencies, id: \.self) { code in
                        VSSelectableChip(title: code, selected: selectedCurrency == code) {
                            selectedCurrency = code
                        }
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    code == defaultCurrency && selectedCurrency != code
                                        ? VS.Color.accent.opacity(0.35)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
        }
    }

    private var litersField: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(VolumeFormat.label(volumeUnit))
            HStack {
                TextField("0.0", text: $liters)
                    .keyboardType(.decimalPad)
                    .font(VS.Typography.heading(22, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(VolumeFormat.suffix(volumeUnit))
                    .font(VS.Typography.body(15, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .vsInputField()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.Typography.body(13, weight: .medium))
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
            let cal = Calendar.current
            // Keep the original fill time when editing; stamp new fills with the current time.
            let timeSource = existingLog?.timestamp ?? Date()
            stamp = cal.date(
                bySettingHour: cal.component(.hour, from: timeSource),
                minute: cal.component(.minute, from: timeSource),
                second: 0,
                of: stamp
            ) ?? stamp

            let resolved = resolvedStationForSave
            let volumeLiters = VolumeFormat.toLiters(vol, unit: volumeUnit)
            if let existingLog {
                var updated = existingLog
                updated.timestamp = stamp
                updated.odometerReading = odo
                updated.fuelVolume = volumeLiters
                updated.totalCost = cost
                updated.currency = selectedCurrency
                updated.isFullTank = isFullTank
                updated.stationName = resolved?.name
                updated.stationLatitude = resolved?.latitude
                updated.stationLongitude = resolved?.longitude
                try await store.updateFuelLog(updated)
            } else {
                try await store.addFuelLog(
                    vehicleId: vehicleId,
                    odometerReading: odo,
                    fuelVolume: volumeLiters,
                    totalCost: cost,
                    currency: selectedCurrency,
                    isFullTank: isFullTank,
                    timestamp: stamp,
                    stationName: resolved?.name,
                    stationLatitude: resolved?.latitude,
                    stationLongitude: resolved?.longitude
                )
            }
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
