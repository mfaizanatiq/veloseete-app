import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var recorder: TripRecordingService
    var onComplete: (() -> Void)? = nil
    /// Full-screen first-run mode — warmer copy, no ops banner (account lives in parent chrome).
    var isFirstRun: Bool = false

    @State private var step = 1
    @State private var nickname = ""
    @State private var icon = "🚗"
    @State private var paint: VehiclePaintColor = .brand
    @State private var make = ""
    @State private var model = ""
    @State private var showMakeModel = false
    @State private var fuelType = "petrol"
    @State private var currency = "QAR"
    @State private var fuelVolumeUnit = VolumeFormat.liters
    @State private var odometer = ""
    @State private var tankCapacity = ""
    @State private var showTank = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isRetrying = false
    @State private var showOrphanLinkDialog = false
    @State private var pendingAddCompletion = false
    @State private var orphanLinkVehicle: Vehicle?
    @State private var orphanLinkSnapshot: (count: Int, totalKm: Double)?

    private struct OrphanLinkAction {
        var assignToVehicle: Bool
    }
    @State private var orphanLinkAction: OrphanLinkAction?

    private let fuelTypes = [
        ("petrol", "Petrol"),
        ("diesel", "Diesel"),
        ("hybrid", "Hybrid"),
        ("electric", "Electric")
    ]

    private let currencies = ["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"]

    private var isSheet: Bool { onComplete != nil }
    private var showsAccountBanner: Bool { !isSheet && !isFirstRun && store.vehicles.isEmpty }

    var body: some View {
        Group {
            if isSheet {
                NavigationStack { sheetBody }
                    .presentationDetents([.large])
                    .veloseeteSheet()
            } else {
                sheetBody
            }
        }
        .onAppear {
            currency = Locale.current.currency?.identifier == "USD" ? "USD"
                : Locale.current.region?.identifier == "AE" ? "AED"
                : Locale.current.region?.identifier == "SA" ? "SAR"
                : "QAR"
            fuelVolumeUnit = VolumeFormat.defaultUnit(currency: currency)
        }
    }

    private var sheetBody: some View {
        VStack(spacing: 0) {
            if showsAccountBanner {
                accountBanner
            }

            stepHeader

            ScrollView {
                Group {
                    switch step {
                    case 1: stepBasics
                    case 2: stepFuel
                    default: stepOdometer
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.error)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            PrimaryCTAButton(
                title: step == 3
                    ? (isFirstRun ? "Start tracking" : "Add vehicle")
                    : "Continue",
                icon: step == 3 ? .checkCircle : nil,
                isLoading: isSubmitting,
                isEnabled: canContinue
            ) {
                Task { await advance() }
            }
            .padding(20)
        }
        .veloseetePage()
        .navigationTitle(isSheet ? "Add vehicle" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onComplete {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onComplete() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .confirmationDialog(
            TrackyVoice.Calm.linkOrphanDrivesTitle,
            isPresented: $showOrphanLinkDialog,
            titleVisibility: .visible
        ) {
            if let vehicle = orphanLinkVehicle {
                Button(TrackyVoice.Calm.linkOrphanDrivesConfirm(vehicleName: vehicle.nickname)) {
                    orphanLinkAction = OrphanLinkAction(assignToVehicle: true)
                    showOrphanLinkDialog = false
                }
            }
            Button(TrackyVoice.Calm.linkOrphanDrivesSkip, role: .cancel) {
                orphanLinkAction = OrphanLinkAction(assignToVehicle: false)
                showOrphanLinkDialog = false
            }
        } message: {
            if let vehicle = orphanLinkVehicle, let snapshot = orphanLinkSnapshot {
                Text(
                    TrackyVoice.Calm.linkOrphanDrivesMessage(
                        count: snapshot.count,
                        distance: DistanceFormat.formatDistance(snapshot.totalKm, unit: store.defaultDistanceUnit),
                        vehicleName: vehicle.nickname
                    )
                )
            }
        }
        .onChange(of: showOrphanLinkDialog) { _, isShowing in
            guard !isShowing, pendingAddCompletion else { return }
            if orphanLinkAction?.assignToVehicle == true, let vehicle = orphanLinkVehicle {
                recorder.assignOrphanPending(to: vehicle.id, vehicleName: vehicle.nickname)
            }
            orphanLinkAction = nil
            orphanLinkVehicle = nil
            orphanLinkSnapshot = nil
            pendingAddCompletion = false
            onComplete?()
        }
    }

    private var stepHeader: some View {
        HStack {
            if step > 1 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        step -= 1
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(VS.Typography.body(14, weight: .semibold))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Step \(step) of 3")
                .font(VS.Typography.body(13, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, isSheet ? 8 : 12)
        .padding(.bottom, 4)
    }

    private var accountBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(auth.user?.email ?? "Signed in")
                .font(VS.Typography.body(13, weight: .semibold))
                .foregroundStyle(VS.Color.textPrimary)

            if !store.loadWarnings.isEmpty {
                Text(store.loadWarnings.joined(separator: "\n"))
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.warning)
            }

            HStack(spacing: 14) {
                Button {
                    Task {
                        isRetrying = true
                        if let uid = auth.userId {
                            await store.loadAll(userId: uid)
                        }
                        isRetrying = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRetrying { ProgressView().tint(VS.Color.accent) }
                        Text("Retry sync")
                            .font(VS.Typography.body(13, weight: .semibold))
                    }
                    .foregroundStyle(VS.Color.accent)
                }
                .buttonStyle(.plain)

                Button("Sign out") {
                    try? auth.signOut()
                }
                .font(VS.Typography.body(13, weight: .semibold))
                .foregroundStyle(VS.Color.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var canContinue: Bool {
        switch step {
        case 1: return !nickname.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return !fuelType.isEmpty && !currency.isEmpty
        default: return Double(odometer) != nil && (Double(odometer) ?? 0) >= 0
        }
    }

    private var stepBasics: some View {
        VStack(alignment: .leading, spacing: 22) {
            titleBlock(
                isFirstRun ? "Name your car" : (store.vehicles.isEmpty ? "Your first vehicle" : "New vehicle"),
                isFirstRun ? "A nickname and mark is enough to start" : "Name it, pick a mark"
            )

            glassTextField(label: "Name", placeholder: "My car", text: $nickname, large: true)

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Colour")
                VehiclePaintSwatchRow(paint: $paint)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Car mark")
                VehicleMarkCarousel(icon: $icon, paint: paint)
            }

            Button {
                withAnimation(.snappy(duration: 0.25)) { showMakeModel.toggle() }
            } label: {
                Text(showMakeModel ? "Hide make & model" : "Make & model (optional)")
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
            }
            .buttonStyle(.plain)

            if showMakeModel {
                glassTextField(label: "Make", placeholder: "Toyota", text: $make)
                VehicleMakeChipRow(make: $make)
                glassTextField(label: "Model", placeholder: "Camry", text: $model)
            }
        }
    }

    private var stepFuel: some View {
        VStack(alignment: .leading, spacing: 22) {
            titleBlock(
                isFirstRun ? "How you fill up" : "Fuel & currency",
                isFirstRun ? "Used for spends and efficiency" : "Used for fills and spend"
            )

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Fuel type")
                HStack(spacing: 8) {
                    ForEach(fuelTypes, id: \.0) { type in
                        capsuleChip(type.1, selected: fuelType == type.0) {
                            fuelType = type.0
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Currency")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(currencies, id: \.self) { code in
                            capsuleChip(code, selected: currency == code) {
                                currency = code
                                fuelVolumeUnit = VolumeFormat.defaultUnit(currency: code)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Fuel volume")
                HStack(spacing: 8) {
                    capsuleChip("Litres", selected: fuelVolumeUnit == VolumeFormat.liters) {
                        fuelVolumeUnit = VolumeFormat.liters
                    }
                    capsuleChip("Gallons", selected: fuelVolumeUnit == VolumeFormat.gallons) {
                        fuelVolumeUnit = VolumeFormat.gallons
                    }
                }
            }
        }
    }

    private var stepOdometer: some View {
        VStack(alignment: .leading, spacing: 22) {
            titleBlock(
                isFirstRun ? TrackyVoice.Soft.odometerStepTitle : TrackyVoice.Calm.currentOdometer,
                isFirstRun ? TrackyVoice.Soft.odometerStepBody : "Dashboard reading right now"
            )

            glassNumberField(
                label: "Current odometer",
                placeholder: "0",
                text: $odometer,
                suffix: "km",
                large: true
            )

            Button {
                withAnimation(.snappy(duration: 0.25)) { showTank.toggle() }
            } label: {
                Text(showTank ? "Hide tank capacity" : "Tank capacity (optional)")
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
            }
            .buttonStyle(.plain)

            if showTank {
                glassNumberField(
                    label: "Tank capacity",
                    placeholder: VolumeFormat.usesGallons(fuelVolumeUnit) ? "14.5" : "55",
                    text: $tankCapacity,
                    suffix: VolumeFormat.suffix(fuelVolumeUnit),
                    large: false
                )
            }
        }
    }

    private func titleBlock(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VS.Typography.heading(26, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(subtitle)
                .font(VS.Typography.body(14))
                .foregroundStyle(VS.Color.textSecondary)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.Typography.body(13, weight: .medium))
            .foregroundStyle(VS.Color.textTertiary)
    }

    private func glassTextField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        large: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .font(large ? VS.Typography.heading(24, weight: .semibold) : VS.Typography.heading(20, weight: .semibold))
                .foregroundStyle(VS.Color.textPrimary)
                .vsInputField()
        }
    }

    private func glassNumberField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        suffix: String,
        large: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(label)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(suffix == "km" ? .numberPad : .decimalPad)
                    .font(large ? VS.Typography.heading(32, weight: .bold) : VS.Typography.heading(22, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(suffix)
                    .font(VS.Typography.body(15, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .vsInputField()
        }
    }

    private func capsuleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        VSSelectableChip(title: title, selected: selected, action: action)
    }

    private func advance() async {
        errorMessage = nil
        if step < 3 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step += 1
            }
            return
        }

        guard let odo = Double(odometer) else {
            errorMessage = "Enter a valid odometer reading"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let tankLiters = Double(tankCapacity).map {
                VolumeFormat.toLiters($0, unit: fuelVolumeUnit)
            }
            let vehicle = try await store.addVehicle(
                nickname: nickname.trimmingCharacters(in: .whitespaces),
                make: make.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : make.trimmingCharacters(in: .whitespaces),
                model: model.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : model.trimmingCharacters(in: .whitespaces),
                fuelType: fuelType,
                currentOdometer: odo,
                currency: currency,
                icon: icon,
                paintColor: paint == .brand ? nil : paint.rawValue,
                fuelTankCapacity: tankLiters,
                fuelVolumeUnit: fuelVolumeUnit
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            let orphans = recorder.orphanPendingSaves
            if orphans.isEmpty {
                onComplete?()
            } else {
                orphanLinkVehicle = vehicle
                orphanLinkSnapshot = (
                    count: orphans.count,
                    totalKm: orphans.reduce(0) { $0 + $1.distanceKm }
                )
                pendingAddCompletion = true
                showOrphanLinkDialog = true
            }
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
