import SwiftUI
import PhotosUI
import UIKit
import Charts
import AuthenticationServices

enum AppTab: String, CaseIterable {
    case trips, fuel, service, details, driver

    var label: String {
        switch self {
        case .trips: return "Drives"
        case .fuel: return "Fuels"
        case .service: return "Service"
        case .details: return "Garage"
        case .driver: return "Driver"
        }
    }

    /// Same Phosphor set as web DashboardV2 bottom nav (+ map for Trips).
    var icon: VSIconName {
        switch self {
        case .trips: return .mapTrifold
        case .fuel: return .gasPump
        case .service: return .wrench
        case .details: return .car
        case .driver: return .baseballHelmet
        }
    }
}

struct MainTabShell: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navChrome = BottomNavChrome()
    @State private var tab: AppTab = .trips
    @State private var showProfile = false
    @State private var carPlayRefuelDraft: CarPlayRefuelDraft?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .trips:
                    TripsView(onProfile: { showProfile = true })
                case .fuel:
                    DashboardView(onProfile: { showProfile = true })
                case .service:
                    ServiceListView(onProfile: { showProfile = true })
                case .details:
                    DetailsListView(onProfile: { showProfile = true })
                case .driver:
                    DriverProfileView(onProfile: { showProfile = true })
                }
            }
            .coordinateSpace(name: "bottomNavScroll")

            BottomNavBar(active: $tab)
        }
        .environmentObject(navChrome)
        .onChange(of: tab) { _, _ in
            navChrome.reset()
        }
        .sheet(isPresented: $showProfile, onDismiss: presentPendingCarPlayRefuel) {
            ProfileView()
        }
        .sheet(item: $carPlayRefuelDraft) { draft in
            RefuelSheetView(vehicleId: draft.vehicleID, carPlayDraft: draft)
        }
        .onAppear {
            applyPortfolioTabOverrideIfNeeded()
            presentPendingCarPlayRefuel()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            applyPortfolioTabOverrideIfNeeded()
            presentPendingCarPlayRefuel()
        }
        .onReceive(NotificationCenter.default.publisher(for: CarPlayRefuelHandoff.draftCreated)) { _ in
            presentPendingCarPlayRefuel()
        }
    }

    /// Debug/portfolio helper: `defaults write com.veloseete.app portfolio.forceTab fuel`
    /// then foreground the app. Values: trips | fuel | service | details | driver
    private func applyPortfolioTabOverrideIfNeeded() {
        guard let raw = UserDefaults.standard.string(forKey: "portfolio.forceTab"),
              let forced = AppTab(rawValue: raw) else { return }
        if tab != forced {
            tab = forced
        }
    }

    private func presentPendingCarPlayRefuel() {
        guard !showProfile,
              carPlayRefuelDraft == nil,
              let draft = CarPlayRefuelHandoff.consumePendingDraft(),
              store.vehicles.contains(where: { $0.id == draft.vehicleID }) else { return }
        tab = .fuel
        carPlayRefuelDraft = draft
    }
}

/// Shared top alignment for every primary tab. The trailing space is reserved for
/// the profile avatar supplied by `MainTabShell`, so local actions never collide.
struct MainTabHeader: View {
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    let title: String
    let subtitle: String?
    let onProfile: () -> Void

    init(_ title: String, subtitle: String? = nil, onProfile: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onProfile = onProfile
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(VS.Typography.heading(28, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onProfile()
            } label: {
                ProfileAvatarView(image: avatarStore.image, size: 40)
                    .overlay(Circle().stroke(VS.Color.accent.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Open profile")
        }
        .frame(minHeight: 52, alignment: .top)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

struct BottomNavBar: View {
    @Binding var active: AppTab
    @EnvironmentObject private var navChrome: BottomNavChrome

    /// Matches web DashboardV2 (`#101012` selected pill, lime icon circle).
    private let selectedPill = VS.Color.navActive
    private let outerPill = VS.Color.navPill

    private var isCompact: Bool { navChrome.isCompact }

    private var iconSize: CGFloat { isCompact ? 18 : 22 }
    private var circleSize: CGFloat { isCompact ? 34 : 40 }
    private var itemMinHeight: CGFloat { isCompact ? 40 : 48 }
    private var outerPadding: CGFloat { isCompact ? 6 : 10 }
    private var horizontalInset: CGFloat { isCompact ? 28 : 16 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        active = item
                    }
                } label: {
                    HStack(spacing: isCompact ? 0 : 10) {
                        NavIconBubble(
                            icon: item.icon,
                            isActive: active == item,
                            iconSize: iconSize,
                            circleSize: circleSize,
                            activeTint: outerPill
                        )

                        if active == item && !isCompact {
                            Text(item.label)
                                .font(VS.Typography.heading(14))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(.horizontal, active == item && !isCompact ? 10 : (isCompact ? 4 : 6))
                    .frame(minHeight: itemMinHeight)
                    .background(
                        Capsule().fill(active == item ? selectedPill : .clear)
                    )
                }
                .buttonStyle(.plain)

                if index < AppTab.allCases.count - 1 {
                    Spacer(minLength: isCompact ? 6 : 4)
                }
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: 420)
        .background(
            Capsule()
                .fill(outerPill)
                .shadow(color: .black.opacity(0.4), radius: isCompact ? 12 : 16, y: 4)
        )
        .padding(.horizontal, horizontalInset)
        // Native floating tab bars dip into the bottom safe area and hug the home
        // indicator; staying fully above it left a visible dead strip under the pill.
        .offset(y: isCompact ? 14 : 18)
    }
}

/// Lime circle + icon with a light pop when selected.
private struct NavIconBubble: View {
    let icon: VSIconName
    let isActive: Bool
    let iconSize: CGFloat
    let circleSize: CGFloat
    let activeTint: Color

    @State private var pop = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? VS.Color.accent : .clear)
                .frame(width: circleSize, height: circleSize)
                .scaleEffect(pop ? 1.08 : 1.0)

            VSIcon(
                icon: icon,
                size: iconSize,
                weight: isActive ? .fill : .regular,
                tint: isActive ? activeTint : VS.Color.textSecondary
            )
            .scaleEffect(pop ? 1.12 : 1.0)
            .rotationEffect(.degrees(pop ? -6 : 0))
        }
        .onChange(of: isActive) { _, active in
            guard active else {
                pop = false
                return
            }
            // Quick pop in, then settle — keeps it alive without bouncing forever.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                pop = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                    pop = false
                }
            }
        }
    }
}

struct PlaceholderPane: View {
    let title: String
    let subtitle: String
    let icon: VSIconName

    var body: some View {
        VStack(spacing: 12) {
            VSIcon(icon: icon, size: 40, weight: .regular, tint: VS.Color.accent)
            Text(title)
                .font(VS.Typography.heading(22))
                .foregroundStyle(VS.Color.textPrimary)
            Text(subtitle)
                .font(VS.Typography.body(14))
                .foregroundStyle(VS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 90)
        .veloseetePage()
    }
}

struct DetailsListView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var vehiclePhotos: VehiclePhotoStore
    let onProfile: () -> Void
    @State private var showAddVehicle = false
    @State private var editingVehicle: Vehicle?
    @State private var selectionError: String?
    @State private var vehiclePendingArchive: Vehicle?
    @State private var archiveError: String?
    @State private var isArchiving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VS.Spacing.section) {
                MainTabHeader("Garage", subtitle: "Cars in the mix", onProfile: onProfile)

                HStack {
                    Spacer()
                    Button {
                        showAddVehicle = true
                    } label: {
                        HStack(spacing: 7) {
                            VSIcon(icon: .plusCircle, size: 17, weight: .fill, tint: VS.Color.navPill)
                            Text("Add vehicle")
                                .font(VS.Typography.body(13, weight: .bold))
                        }
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(VS.Color.accent, in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Add vehicle")
                }

                if let selectionError {
                    Text(selectionError)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.error)
                }
                if let archiveError {
                    Text(archiveError)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.error)
                }

                if store.vehicles.isEmpty {
                    VStack(spacing: 14) {
                        VSIcon(icon: .car, size: 40, weight: .regular, tint: VS.Color.accent)
                        Text("Garage’s empty")
                            .font(VS.Typography.heading(18))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Add a car to connect drives, fuel, and service.")
                            .font(VS.Typography.body(14))
                            .foregroundStyle(VS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Add your first car") { showAddVehicle = true }
                            .font(VS.Typography.heading(14))
                            .foregroundStyle(VS.Color.navPill)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(VS.Color.accent, in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .glassCard(elevated: true)
                } else {
                    ForEach(store.vehicles) { vehicle in
                        garageVehicleCard(vehicle)
                    }
                }

                if !store.archivedVehicles.isEmpty {
                    VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                        VSSectionHeader(title: "Archived", subtitle: "Hidden from the garage — history stays put")

                        ForEach(store.archivedVehicles) { vehicle in
                            archivedVehicleCard(vehicle)
                        }
                    }
                }
            }
            .padding(.horizontal, VS.Spacing.pageInset)
            .padding(.bottom, 110)
            .tracksBottomNavScroll()
        }
        .veloseetePage()
        .sheet(isPresented: $showAddVehicle) {
            GarageView(onComplete: { showAddVehicle = false })
        }
        .sheet(item: $editingVehicle) { vehicle in
            VehicleEditorView(vehicle: vehicle) { vehiclePendingArchive = $0 }
                .environmentObject(vehiclePhotos)
        }
        .confirmationDialog(
            "Archive \(vehiclePendingArchive?.nickname ?? "vehicle")?",
            isPresented: Binding(
                get: { vehiclePendingArchive != nil },
                set: { if !$0 { vehiclePendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive vehicle", role: .destructive) {
                guard let vehicle = vehiclePendingArchive else { return }
                Task { await archiveVehicle(vehicle) }
            }
            Button("Cancel", role: .cancel) {
                vehiclePendingArchive = nil
            }
        } message: {
            Text("Removes it from your garage only. Fuel, drives and service for this car stay saved — other vehicles are not changed.")
        }
        .onAppear {
            vehiclePhotos.load(vehicleIds: (store.vehicles + store.archivedVehicles).map(\.id))
        }
        .onChange(of: store.vehicles.map(\.id) + store.archivedVehicles.map(\.id)) { _, ids in
            vehiclePhotos.load(vehicleIds: ids)
        }
    }

    private func garageVehicleCard(_ vehicle: Vehicle) -> some View {
        let isCurrent = store.currentVehicle?.id == vehicle.id
        let refuels = store.fuelLogs.filter { $0.vehicleId == vehicle.id }.count
        let services = store.serviceLogs.filter { $0.vehicleId == vehicle.id }.count
        let drives = store.trips.filter { $0.vehicleId == vehicle.id }.count

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                vehicleAppearancePreview(
                    image: vehiclePhotos.image(for: vehicle.id),
                    emoji: vehicle.icon ?? "🚗",
                    size: 54
                )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(vehicle.nickname)
                            .font(VS.Typography.heading(19, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        if isCurrent {
                            Text("ACTIVE")
                                .font(VS.Typography.body(8, weight: .bold))
                                .tracking(0.7)
                                .foregroundStyle(VS.Color.navPill)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(VS.Color.accent, in: Capsule())
                        }
                    }
                    Text("\(vehicle.make) \(vehicle.model) · \(vehicle.fuelType.capitalized)")
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                Spacer()
                Button { editingVehicle = vehicle } label: {
                    Text("Edit")
                        .font(VS.Typography.body(12, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(VS.Color.chip, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                garageMetric(DistanceFormat.formatOdometer(vehicle.currentOdometer, unit: store.defaultDistanceUnit), "ODOMETER")
                garageMetric(VolumeFormat.formatTank(vehicle.fuelTankCapacity, unit: vehicle.fuelVolumeUnit), "TANK")
            }

            HStack(spacing: 0) {
                garageCount(drives, "Drives")
                Divider().overlay(VS.Color.divider)
                garageCount(refuels, "Refuels")
                Divider().overlay(VS.Color.divider)
                garageCount(services, "Services")
            }
            .frame(height: 42)

            if !isCurrent {
                Button {
                    Task {
                        do {
                            selectionError = nil
                            try await store.selectVehicle(vehicle.id)
                            UISelectionFeedbackGenerator().selectionChanged()
                        } catch {
                            selectionError = error.localizedDescription
                        }
                    }
                } label: {
                    Text("Make active vehicle")
                        .font(VS.Typography.heading(13))
                        .foregroundStyle(VS.Color.navPill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(VS.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(elevated: isCurrent)
    }

    private func archivedVehicleCard(_ vehicle: Vehicle) -> some View {
        let refuels = store.fuelLogs.filter { $0.vehicleId == vehicle.id }.count
        let drives = store.trips.filter { $0.vehicleId == vehicle.id }.count

        return HStack(spacing: 12) {
            vehicleAppearancePreview(
                image: vehiclePhotos.image(for: vehicle.id),
                emoji: vehicle.icon ?? "🚗",
                size: 48
            )
            .opacity(0.7)

            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.nickname)
                    .font(VS.Typography.heading(16))
                    .foregroundStyle(VS.Color.textPrimary)
                Text("\(vehicle.make) \(vehicle.model) · \(drives) drives · \(refuels) fills")
                    .font(VS.Typography.body(12))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    do {
                        archiveError = nil
                        try await store.restoreVehicle(vehicle.id)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } catch {
                        archiveError = error.localizedDescription
                    }
                }
            } label: {
                Text("Restore")
                    .font(VS.Typography.body(12, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(VS.Color.chip, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard()
    }

    private func archiveVehicle(_ vehicle: Vehicle) async {
        isArchiving = true
        archiveError = nil
        defer {
            isArchiving = false
            vehiclePendingArchive = nil
        }
        do {
            try await store.archiveVehicle(vehicle.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            archiveError = error.localizedDescription
        }
    }

    private func garageMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(VS.Typography.heading(17))
                .foregroundStyle(VS.Color.textPrimary)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(VS.Typography.body(9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func garageCount(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(VS.Typography.heading(15)).foregroundStyle(VS.Color.textPrimary)
            Text(label).font(VS.Typography.body(10)).foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VehicleEditorView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var vehiclePhotos: VehiclePhotoStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    var onRequestArchive: ((Vehicle) -> Void)?

    @State private var nickname: String
    @State private var make: String
    @State private var model: String
    @State private var fuelType: String
    @State private var odometer: String
    @State private var tankCapacity: String
    @State private var currency: String
    @State private var fuelVolumeUnit: String
    @State private var icon: String
    @State private var usePhoto: Bool
    @State private var draftPhoto: UIImage?
    @State private var removeExistingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropDraft: AvatarCropDraft?
    @State private var isPreparingCrop = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showAdvanced = false

    private let fuelTypes = [
        ("petrol", "Petrol"),
        ("diesel", "Diesel"),
        ("hybrid", "Hybrid"),
        ("electric", "Electric")
    ]
    private let popularMakes = [
        "Toyota", "Honda", "Ford", "BMW", "Mercedes-Benz", "Audi",
        "Volkswagen", "Nissan", "Hyundai", "Kia", "Mazda", "Lexus"
    ]
    private let currencies = ["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"]
    private let icons = ["🚗", "🚙", "🚕", "🚌", "🚐", "🏎️", "🚓", "🚑", "🚒", "🚚", "🚛", "🛻", "🏍️", "🛵", "🚜", "🚎"]

    private var isActiveVehicle: Bool {
        store.currentVehicle?.id == vehicle.id
    }

    init(vehicle: Vehicle, onRequestArchive: ((Vehicle) -> Void)? = nil) {
        self.vehicle = vehicle
        self.onRequestArchive = onRequestArchive
        _nickname = State(initialValue: vehicle.nickname)
        _make = State(initialValue: vehicle.make)
        _model = State(initialValue: vehicle.model)
        _fuelType = State(initialValue: vehicle.fuelType)
        _odometer = State(initialValue: String(format: "%.0f", vehicle.currentOdometer))
        let volumeUnit = VolumeFormat.normalize(vehicle.fuelVolumeUnit)
            ?? VolumeFormat.defaultUnit(currency: vehicle.currency)
        _fuelVolumeUnit = State(initialValue: volumeUnit)
        _tankCapacity = State(
            initialValue: vehicle.fuelTankCapacity.map {
                String(format: "%.1f", VolumeFormat.toDisplay($0, unit: volumeUnit))
            } ?? ""
        )
        _currency = State(initialValue: vehicle.currency)
        _icon = State(initialValue: vehicle.icon ?? "🚗")
        let hasPhoto = VehiclePhotoStore.shared.image(for: vehicle.id) != nil
        _usePhoto = State(initialValue: hasPhoto)
        _draftPhoto = State(initialValue: VehiclePhotoStore.shared.image(for: vehicle.id))
    }

    private var previewImage: UIImage? {
        if removeExistingPhoto { return draftPhoto }
        return draftPhoto ?? vehiclePhotos.image(for: vehicle.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    appearanceSection

                    glassTextField(label: "Name", placeholder: "My car", text: $nickname, large: true)

                    VStack(alignment: .leading, spacing: 10) {
                        glassTextField(label: "Make", placeholder: "Toyota", text: $make)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(popularMakes, id: \.self) { m in
                                    capsuleChip(m, selected: make == m) { make = m }
                                }
                            }
                        }
                        glassTextField(label: "Model", placeholder: "Camry", text: $model)
                    }

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
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel("Fuel volume")
                        HStack(spacing: 8) {
                            capsuleChip("Litres", selected: fuelVolumeUnit == VolumeFormat.liters) {
                                convertTankDisplay(to: VolumeFormat.liters)
                            }
                            capsuleChip("Gallons", selected: fuelVolumeUnit == VolumeFormat.gallons) {
                                convertTankDisplay(to: VolumeFormat.gallons)
                            }
                        }
                    }

                    glassNumberField(
                        label: "Current odometer",
                        placeholder: "0",
                        text: $odometer,
                        suffix: "km",
                        large: true
                    )

                    glassNumberField(
                        label: "Tank capacity",
                        placeholder: "Optional",
                        text: $tankCapacity,
                        suffix: VolumeFormat.suffix(fuelVolumeUnit),
                        large: false
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    advancedSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle("Edit vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryCTAButton(
                    title: "Save changes",
                    icon: .checkCircle,
                    isLoading: isSaving,
                    isEnabled: canSave && !isPreparingCrop
                ) {
                    Task { await save() }
                }
                .padding(20)
                .background(VS.Color.bgPrimary.opacity(0.96))
            }
            .onAppear {
                vehiclePhotos.load(vehicleId: vehicle.id)
                if draftPhoto == nil, let existing = vehiclePhotos.image(for: vehicle.id) {
                    draftPhoto = existing
                    usePhoto = true
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await loadPhotoForCrop(item) }
            }
            .fullScreenCover(item: $cropDraft) { draft in
                ProfilePhotoCropView(
                    image: draft.image,
                    title: "Reframe your car",
                    subtitle: "Move and zoom until it feels right",
                    footer: "Only the circular area will show in Garage",
                    onUse: { cropped in
                        draftPhoto = cropped
                        usePhoto = true
                        removeExistingPhoto = false
                        cropDraft = nil
                        selectedPhoto = nil
                    },
                    onCancel: {
                        cropDraft = nil
                        selectedPhoto = nil
                    }
                )
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldLabel("Appearance")

            HStack(spacing: 14) {
                vehicleAppearancePreview(image: usePhoto ? previewImage : nil, emoji: icon, size: 72)

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text(previewImage == nil ? "Add car photo" : "Change photo")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                    .disabled(isPreparingCrop)

                    if usePhoto, previewImage != nil {
                        Button("Use emoji instead") {
                            usePhoto = false
                            removeExistingPhoto = true
                            draftPhoto = nil
                        }
                        .font(VS.Typography.body(13, weight: .medium))
                        .foregroundStyle(VS.Color.textSecondary)
                    }

                    if isPreparingCrop {
                        ProgressView("Opening photo…")
                            .font(VS.Typography.body(12))
                            .tint(VS.Color.accent)
                    }
                }
                Spacer(minLength: 0)
            }

            if !usePhoto || previewImage == nil {
                fieldLabel("Emoji")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(icons, id: \.self) { item in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            icon = item
                            usePhoto = false
                            removeExistingPhoto = true
                            draftPhoto = nil
                        } label: {
                            FluentEmojiView(emoji: item, size: 26)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(icon == item && !usePhoto ? VS.Color.accent : VS.Color.chip)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showAdvanced.toggle() }
            } label: {
                Text(showAdvanced ? "Hide advanced" : "Advanced")
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
            }
            .buttonStyle(.plain)

            if showAdvanced {
                if isActiveVehicle {
                    Text("Switch active in Garage before you can archive this car.")
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                } else {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onRequestArchive?(vehicle)
                        }
                    } label: {
                        Text("Archive vehicle")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassCard(radius: 12)
                    }
                    .buttonStyle(.plain)

                    Text("Hides this car from the garage. Drives, fuel and service stay saved.")
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }
        }
    }

    private var canSave: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(odometer) != nil
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.Typography.body(12, weight: .medium))
            .foregroundStyle(VS.Color.textTertiary)
    }

    private func glassTextField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        large: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .font(large ? VS.Typography.heading(20, weight: .semibold) : VS.Typography.heading(18, weight: .semibold))
                .foregroundStyle(VS.Color.textPrimary)
                .padding(14)
                .glassCard(radius: 12)
        }
    }

    private func glassNumberField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        suffix: String,
        large: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(suffix == "km" ? .numberPad : .decimalPad)
                    .font(large ? VS.Typography.heading(28, weight: .bold) : VS.Typography.heading(20, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(suffix)
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(14)
            .glassCard(radius: 12, elevated: large)
        }
    }

    private func capsuleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(title)
                .font(VS.Typography.body(13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(selected ? VS.Color.accent : VS.Color.chip))
                .foregroundStyle(selected ? VS.Color.navPill : VS.Color.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func convertTankDisplay(to newUnit: String) {
        guard newUnit != fuelVolumeUnit else { return }
        if let value = Double(tankCapacity) {
            let liters = VolumeFormat.toLiters(value, unit: fuelVolumeUnit)
            tankCapacity = String(format: "%.1f", VolumeFormat.toDisplay(liters, unit: newUnit))
        }
        fuelVolumeUnit = newUnit
    }

    private func loadPhotoForCrop(_ item: PhotosPickerItem) async {
        isPreparingCrop = true
        defer { isPreparingCrop = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "That photo could not be opened."
                selectedPhoto = nil
                return
            }
            cropDraft = AvatarCropDraft(image: image)
        } catch {
            errorMessage = error.localizedDescription
            selectedPhoto = nil
        }
    }

    private func save() async {
        guard let odometerValue = Double(odometer) else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = vehicle
        updated.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.fuelType = fuelType
        updated.currentOdometer = odometerValue
        updated.fuelTankCapacity = Double(tankCapacity).map {
            VolumeFormat.toLiters($0, unit: fuelVolumeUnit)
        }
        updated.currency = currency
        updated.fuelVolumeUnit = fuelVolumeUnit
        updated.icon = icon
        do {
            if usePhoto, let draftPhoto {
                try vehiclePhotos.save(image: draftPhoto, vehicleId: vehicle.id)
            } else if removeExistingPhoto || !usePhoto {
                try vehiclePhotos.remove(vehicleId: vehicle.id)
            }
            try await store.updateVehicle(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func vehicleAppearancePreview(image: UIImage?, emoji: String, size: CGFloat) -> some View {
    Group {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            FluentEmojiView(emoji: emoji, size: size * 0.55)
                .frame(width: size, height: size)
                .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        }
    }
    .overlay(
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
}

private enum AnalyticsPeriod: String, CaseIterable {
    case week, month, year, all
    var title: String { rawValue.capitalized }
    var days: Int? { self == .week ? 7 : self == .month ? 30 : self == .year ? 365 : nil }
}

private struct AnalyticsPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct DriverHubStory: Identifiable {
    let id: String
    let emoji: String
    let eyebrow: String
    let value: String
    let title: String
    let detail: String
}

private struct DriverHubPurpose: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let value: String
    let subtitle: String
}

struct DriverProfileView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    let onProfile: () -> Void
    @State private var period: AnalyticsPeriod = .month
    @State private var showBadges = false

    private var unit: String { store.defaultDistanceUnit }
    private var currency: String { store.currentVehicle?.currency ?? "QAR" }
    private var displayName: String {
        let name = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Driver" : name
    }

    private var totalKm: Double {
        InsightGenerator.totalKilometersDriven(
            trips: store.tripsForActiveVehicles,
            logs: store.fuelLogsForActiveVehicles,
            vehicleId: nil
        )
    }

    private var vehicleTrips: [Trip] {
        guard let id = store.currentVehicle?.id else { return store.trips }
        return store.trips.filter { $0.vehicleId == id }
    }

    private var lifetimeFuelLogs: [FuelLog] {
        guard let vehicleId = store.currentVehicle?.id else { return store.fuelLogs }
        return store.fuelLogs.filter { $0.vehicleId == vehicleId }.sorted { $0.timestamp < $1.timestamp }
    }

    private var logs: [FuelLog] {
        let all = lifetimeFuelLogs
        guard let days = period.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return all }
        return all.filter { $0.timestamp >= cutoff }
    }

    private var periodDistance: Double {
        guard let first = logs.first, let last = logs.last else { return 0 }
        return max(0, last.odometerReading - first.odometerReading)
    }

    private var spent: Double { logs.reduce(0) { $0 + $1.totalCost } }
    private var liters: Double { logs.reduce(0) { $0 + $1.fuelVolume } }
    private var efficiency: Double? { periodDistance > 0 ? liters / periodDistance * 100 : nil }

    private var vehicleMetrics: EfficiencyMetrics? {
        guard let vehicle = store.currentVehicle else { return nil }
        return MetricsCalculator.compute(vehicle: vehicle, logs: store.fuelLogs)
    }

    private var achievements: [DriverAchievement] {
        InsightGenerator.achievements(
            trips: store.tripsForActiveVehicles,
            logs: store.fuelLogsForActiveVehicles,
            serviceLogs: store.serviceLogsForActiveVehicles,
            vehicleCount: store.vehicles.count,
            vehicleId: nil,
            unit: unit,
            manufacturerStandard: store.manufacturerStandard
        )
    }

    private var unlockedCount: Int { achievements.filter(\.unlocked).count }

    /// Closest-to-done first so “what to chase next” is obvious.
    private var questBadges: [DriverAchievement] {
        achievements
            .filter { !$0.unlocked }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
                return lhs.title < rhs.title
            }
    }

    private var funInsights: [FunInsight] {
        guard let vehicle = store.currentVehicle, let metrics = vehicleMetrics else { return [] }
        return InsightGenerator.funInsights(
            logs: store.fuelLogs,
            vehicleId: vehicle.id,
            currency: vehicle.currency,
            unit: unit,
            metrics: metrics,
            manufacturerStandard: store.manufacturerStandard
        )
    }

    private var monthlySpend: [AnalyticsPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.timestamp)) ?? $0.timestamp
        }
        return grouped
            .map { AnalyticsPoint(date: $0.key, value: $0.value.reduce(0) { $0 + $1.totalCost }) }
            .sorted { $0.date < $1.date }
    }

    private var efficiencyTrend: [AnalyticsPoint] {
        guard logs.count > 1 else { return [] }
        return (1..<logs.count).compactMap { index in
            let previous = logs[index - 1]
            let current = logs[index]
            let interval = current.odometerReading - previous.odometerReading
            guard interval > 0, current.isFullTank, previous.isFullTank else { return nil }
            return AnalyticsPoint(date: current.timestamp, value: current.fuelVolume / interval * 100)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VS.Spacing.section) {
                    MainTabHeader(
                        "Driver",
                        subtitle: store.currentVehicle.map { "\($0.nickname)’s pulse" } ?? "Your driving pulse",
                        onProfile: onProfile
                    )

                    driverHeroCard
                    driverHubGrid
                    badgesHubPreview
                    insightsSection
                    analyticsSection
                }
                .padding(.horizontal, VS.Spacing.pageInset)
                .padding(.bottom, 110)
                .tracksBottomNavScroll()
            }
            .veloseetePage()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showBadges) {
                DriverBadgesView(achievements: achievements)
            }
        }
    }

    private var driverHeroCard: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            HStack(spacing: 14) {
                ProfileAvatarView(image: avatarStore.image, size: 72)
                    .overlay(Circle().stroke(VS.Color.accent.opacity(0.35), lineWidth: 2))

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(VS.Typography.heading(24, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(store.currentVehicle.map { "\($0.make) \($0.model)" } ?? "Add a car to personalize")
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textTertiary)
                    Button {
                        showBadges = true
                    } label: {
                        Text("\(unlockedCount) badges unlocked")
                            .font(VS.Typography.body(13, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ALL-TIME ROAD")
                    .font(VS.Typography.body(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(VS.Color.textTertiary)
                Text(DistanceFormat.formatDistance(totalKm, unit: unit))
                    .font(VS.Typography.heading(36, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
            }
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    /// Featured status, story carousel, then purposeful rows.
    private var driverHubGrid: some View {
        let metrics = vehicleMetrics
        let monthTrips = tripsThisMonth
        let roadHours = monthTrips.reduce(0) { $0 + $1.durationSec } / 3600
        let monthKm = monthTrips.reduce(0) { $0 + max(0, $1.distanceKm) }
        let avgCruise = {
            let speeds = monthTrips.map(\.avgSpeedKmh).filter { $0 > 0 }
            guard !speeds.isEmpty else { return 0.0 }
            return speeds.reduce(0, +) / Double(speeds.count)
        }()
        let longestMonth = monthTrips.map(\.distanceKm).max() ?? 0
        let costPerKm: Double? = {
            guard let metrics, metrics.totalDistance > 1, metrics.monthlySpend > 0 else { return nil }
            return metrics.monthlySpend / metrics.totalDistance
        }()
        let fillGapDays = averageFillGapDays
        let vibe = DashboardCopy.vibe(
            efficiency: metrics?.current ?? metrics?.avgEfficiency,
            standard: store.manufacturerStandard,
            refuelCount: metrics?.efficiencySampleCount ?? 0
        )
        let status = DashboardCopy.status(
            efficiency: metrics?.current ?? metrics?.avgEfficiency,
            standard: store.manufacturerStandard,
            sampleCount: metrics?.efficiencySampleCount ?? 0
        )
        let stories = hubStories(
            monthKm: monthKm,
            roadHours: roadHours,
            tripCount: monthTrips.count,
            costPerKm: costPerKm,
            monthlySpend: metrics?.monthlySpend ?? 0,
            spendTrend: DashboardCopy.spendTrend(metrics?.spendChange),
            fillGapDays: fillGapDays,
            vibe: vibe
        )
        let purposeRows = hubPurposeRows(
            avgCruise: avgCruise,
            longestMonth: longestMonth,
            fillGapDays: fillGapDays,
            metrics: metrics
        )

        return VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "This month", subtitle: "Road, spend, rhythm")

            hubStatusBanner(vibe: vibe, status: status)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(stories) { story in
                        hubStoryCard(story)
                    }
                }
                .padding(.vertical, 2)
            }

            VStack(spacing: 0) {
                ForEach(Array(purposeRows.enumerated()), id: \.element.id) { index, row in
                    hubPurposeRow(row)
                    if index < purposeRows.count - 1 {
                        Divider().overlay(VS.Color.divider)
                    }
                }
            }
            .glassCard()
        }
    }

    private var tripsThisMonth: [Trip] {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return store.trips.filter { $0.startedAt >= start }
    }

    private var averageFillGapDays: Double? {
        let fills = lifetimeFuelLogs
        guard fills.count >= 2 else { return nil }
        var gaps: [Double] = []
        for index in 1..<min(fills.count, 8) {
            let newer = fills[fills.count - index]
            let older = fills[fills.count - index - 1]
            let days = newer.timestamp.timeIntervalSince(older.timestamp) / 86_400
            if days > 0.5 { gaps.append(days) }
        }
        guard !gaps.isEmpty else { return nil }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    private func hubStories(
        monthKm: Double,
        roadHours: Double,
        tripCount: Int,
        costPerKm: Double?,
        monthlySpend: Double,
        spendTrend: String,
        fillGapDays: Double?,
        vibe: EfficiencyVibe
    ) -> [DriverHubStory] {
        [
            DriverHubStory(
                id: "road",
                emoji: "🛣",
                eyebrow: "ON THE ROAD",
                value: monthKm > 0 ? DistanceFormat.formatDistance(monthKm, unit: unit) : "—",
                title: "Miles that matter",
                detail: tripCount == 0
                    ? "No drives logged yet"
                    : "\(tripCount) drive\(tripCount == 1 ? "" : "s") · \(roadHours < 1 ? "<1h" : String(format: "%.0fh", roadHours))"
            ),
            DriverHubStory(
                id: "cost",
                emoji: "⛽",
                eyebrow: "COST TO MOVE",
                value: costPerKm.map { CurrencyFormat.format($0, currency: currency) + "/\(unit)" } ?? "—",
                title: "Every \(unit)’s price tag",
                detail: monthlySpend > 0
                    ? "\(CurrencyFormat.format(monthlySpend, currency: currency)) · \(spendTrend)"
                    : "Log a fill to price the ride"
            ),
            DriverHubStory(
                id: "rhythm",
                emoji: vibe.emoji,
                eyebrow: "FUEL RHYTHM",
                value: fillGapDays.map { String(format: "%.0fd", $0) } ?? "—",
                title: "Fill-up cadence",
                detail: fillGapDays == nil
                    ? "A few fills unlock your pattern"
                    : "Avg gap · \(vibe.label.lowercased())"
            )
        ]
    }

    private func hubPurposeRows(
        avgCruise: Double,
        longestMonth: Double,
        fillGapDays: Double?,
        metrics: EfficiencyMetrics?
    ) -> [DriverHubPurpose] {
        [
            DriverHubPurpose(
                id: "efficiency",
                emoji: "🎯",
                title: "Efficiency",
                value: metrics?.avgEfficiency.map { String(format: "%.1f L/100", $0) } ?? "Learning",
                subtitle: metrics?.avgEfficiency == nil
                    ? "Two full tanks unlock the real number"
                    : "Rolling average of recent full tanks"
            ),
            DriverHubPurpose(
                id: "cruise",
                emoji: "🚗",
                title: "Typical cruise",
                value: avgCruise > 0 ? String(format: "%.0f km/h", avgCruise) : "—",
                subtitle: avgCruise > 0 ? "Your month’s average pace" : "Track a drive to learn it"
            ),
            DriverHubPurpose(
                id: "longest",
                emoji: "🏆",
                title: "Longest run",
                value: longestMonth > 0 ? DistanceFormat.formatDistance(longestMonth, unit: unit) : "—",
                subtitle: longestMonth > 0 ? "Biggest single drive this month" : "Your next haul lands here"
            ),
            DriverHubPurpose(
                id: "next-fill",
                emoji: "⚡",
                title: "Next fill",
                value: {
                    guard let fillGapDays, let last = lifetimeFuelLogs.last else { return "—" }
                    let daysSince = Calendar.current.dateComponents([.day], from: last.timestamp, to: Date()).day ?? 0
                    let left = max(0, Int((fillGapDays - Double(daysSince)).rounded()))
                    return left == 0 ? "Soon" : "~\(left)d"
                }(),
                subtitle: fillGapDays == nil
                    ? "Learns from your refill habit"
                    : "Based on your \(String(format: "%.0f", fillGapDays!))-day cycle"
            )
        ]
    }

    private func hubStatusBanner(
        vibe: EfficiencyVibe,
        status: (text: String, tone: EfficiencyVibe.Tone)
    ) -> some View {
        HStack(spacing: 14) {
            FluentEmojiView(emoji: vibe.emoji, size: 36)
                .frame(width: 56, height: 56)
                .background(toneColor(status.tone).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("DRIVER STATUS")
                    .font(VS.Typography.body(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(VS.Color.textTertiary)
                Text(vibe.label)
                    .font(VS.Typography.heading(20, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(status.text)
                    .font(VS.Typography.body(14))
                    .foregroundStyle(toneColor(status.tone))
            }
            Spacer(minLength: 0)
        }
        .padding(VS.Spacing.card)
        .background(
            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                .fill(toneColor(status.tone).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                .strokeBorder(toneColor(status.tone).opacity(0.28), lineWidth: 1)
        )
    }

    private func hubStoryCard(_ story: DriverHubStory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FluentEmojiView(emoji: story.emoji, size: 22)
                Spacer(minLength: 0)
                Text(story.eyebrow)
                    .font(VS.Typography.body(10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(VS.Color.textTertiary)
            }
            Text(story.value)
                .font(VS.Typography.heading(28, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(story.title)
                .font(VS.Typography.heading(15))
                .foregroundStyle(VS.Color.textPrimary)
            Text(story.detail)
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(VS.Spacing.card)
        .frame(width: 228, height: 168, alignment: .topLeading)
        .glassCard(elevated: true)
    }

    private func hubPurposeRow(_ row: DriverHubPurpose) -> some View {
        HStack(spacing: 14) {
            FluentEmojiView(emoji: row.emoji, size: 26)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(VS.Typography.body(12, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary)
                Text(row.value)
                    .font(VS.Typography.heading(18, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(row.subtitle)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VS.Spacing.md)
        .padding(.vertical, 18)
    }

    private func toneColor(_ tone: EfficiencyVibe.Tone) -> Color {
        switch tone {
        case .excellent: return VS.Color.accent
        case .good: return VS.Color.accentSecondary
        case .neutral: return VS.Color.textSecondary
        case .watch: return VS.Color.warning
        case .learning: return VS.Color.textTertiary
        }
    }

    private var badgesHubPreview: some View {
        let previewQuests = Array(questBadges.prefix(3))
        let moreCount = max(0, achievements.count - previewQuests.count)

        return VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges")
                    .font(VS.Typography.heading(20, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer()
                Text("\(unlockedCount)/\(achievements.count)")
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
            }

            VStack(spacing: 0) {
                if previewQuests.isEmpty {
                    HStack(spacing: 14) {
                        FluentEmojiView(emoji: "🏆", size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Board cleared")
                                .font(VS.Typography.heading(16))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text("Peek at every badge you’ve earned")
                                .font(VS.Typography.body(13))
                                .foregroundStyle(VS.Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(VS.Spacing.card)
                } else {
                    ForEach(Array(previewQuests.enumerated()), id: \.element.id) { index, badge in
                        compactQuestRow(badge)
                        if index < previewQuests.count - 1 {
                            Divider().overlay(VS.Color.divider)
                        }
                    }
                }

                Button {
                    showBadges = true
                } label: {
                    HStack {
                        Text(moreCount > 0 ? "View \(moreCount) more" : "See all badges")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                    .padding(.horizontal, VS.Spacing.md)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    Divider().overlay(VS.Color.divider)
                }
            }
            .glassCard()
        }
    }

    private func compactQuestRow(_ badge: DriverAchievement) -> some View {
        HStack(alignment: .center, spacing: 14) {
            FluentEmojiView(emoji: badge.emoji, size: 26)
                .opacity(0.7)
                .saturation(0.45)
                .frame(width: 48, height: 48)
                .background(
                    Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(badge.title)
                    .font(VS.Typography.heading(16))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(badge.detail)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(VS.Color.chip)
                            Capsule()
                                .fill(VS.Color.accent.opacity(0.85))
                                .frame(width: max(4, geo.size.width * badge.progress))
                        }
                    }
                    .frame(height: 6)
                    Text(badge.progressLabel)
                        .font(VS.Typography.body(11, weight: .semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                        .lineLimit(1)
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
        }
        .padding(VS.Spacing.card)
    }

    private var insightsSection: some View {
        let preview = Array(funInsights.prefix(2))
        return VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "Nuggets")

            if preview.isEmpty {
                VStack(spacing: 12) {
                    FluentEmojiView(emoji: "✨", size: 36)
                    Text("Drive a bit — nuggets show up")
                        .font(VS.Typography.heading(16))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("A few fills and tracked drives unlock the fun stuff.")
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .glassCard()
            } else {
                ForEach(preview) { insight in
                    funInsightCard(insight)
                }
            }
        }
    }

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "Trends")

            HStack(spacing: 8) {
                ForEach(AnalyticsPeriod.allCases, id: \.self) { option in
                    Button(option.title) { period = option }
                        .font(VS.Typography.body(13, weight: .semibold))
                        .foregroundStyle(period == option ? VS.Color.navPill : VS.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(period == option ? VS.Color.accent : VS.Color.chip, in: Capsule())
                }
            }

            HStack(spacing: 14) {
                analyticsMetric(CurrencyFormat.format(spent, currency: currency), "SPENT")
                analyticsMetric(DistanceFormat.formatDistance(periodDistance, unit: unit), "DRIVEN")
            }

            HStack {
                summaryRow(
                    "Cost / \(unit)",
                    periodDistance > 0 ? CurrencyFormat.format(spent / periodDistance, currency: currency) : "—"
                )
                Divider().overlay(VS.Color.divider)
                summaryRow("Avg efficiency", efficiency.map { String(format: "%.1f L/100", $0) } ?? "—")
            }
            .padding(VS.Spacing.card)
            .glassCard()

            if monthlySpend.isEmpty {
                analyticsEmptyState
            } else {
                chartCard(title: "Monthly spend") {
                    Chart(monthlySpend) { point in
                        AreaMark(x: .value("Month", point.date), y: .value("Cost", point.value))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [VS.Color.accent.opacity(0.55), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        LineMark(x: .value("Month", point.date), y: .value("Cost", point.value))
                            .foregroundStyle(VS.Color.accent)
                            .lineStyle(.init(lineWidth: 2.5))
                        PointMark(x: .value("Month", point.date), y: .value("Cost", point.value))
                            .foregroundStyle(VS.Color.accent)
                    }
                }

                if !efficiencyTrend.isEmpty {
                    chartCard(title: "Efficiency") {
                        Chart(efficiencyTrend) { point in
                            LineMark(x: .value("Date", point.date), y: .value("L/100 km", point.value))
                                .foregroundStyle(VS.Color.success)
                                .lineStyle(.init(lineWidth: 2.5))
                            PointMark(x: .value("Date", point.date), y: .value("L/100 km", point.value))
                                .foregroundStyle(VS.Color.success)
                        }
                    }
                }
            }
        }
    }

    private func funInsightCard(_ insight: FunInsight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            FluentEmojiView(emoji: insight.emoji, size: 28)
                .frame(width: 44, height: 44)
                .background(
                    insightTint(insight.kind).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(VS.Typography.heading(16))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(insight.message)
                    .font(VS.Typography.body(14))
                    .foregroundStyle(VS.Color.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(VS.Spacing.card)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                .strokeBorder(insightTint(insight.kind).opacity(0.22), lineWidth: 1)
        )
    }

    private func insightTint(_ kind: FunInsight.Kind) -> Color {
        switch kind {
        case .celebrate: return VS.Color.accent
        case .tip: return VS.Color.accentSecondary
        case .watch: return VS.Color.warning
        }
    }

    private func analyticsMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(VS.Typography.heading(24, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(VS.Typography.body(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(VS.Typography.body(12)).foregroundStyle(VS.Color.textTertiary)
            Text(value).font(VS.Typography.heading(16)).foregroundStyle(VS.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            Text(title).font(VS.Typography.heading(17)).foregroundStyle(VS.Color.textSecondary)
            chart()
                .frame(height: 210)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading) }
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private var analyticsEmptyState: some View {
        VStack(spacing: 12) {
            FluentEmojiView(emoji: "⛽", size: 40)
            Text("A couple of fills unlock trends")
                .font(VS.Typography.heading(16))
                .foregroundStyle(VS.Color.textPrimary)
            Text("Spend and efficiency charts land here.")
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .glassCard()
    }
}

/// Full badge collection — Mobbin refs: Withings category chips, Lyft/OLIO 3-col grid,
/// Tripadvisor category progress, Duolingo locked vs earned contrast.
struct DriverBadgesView: View {
    @Environment(\.dismiss) private var dismiss
    let achievements: [DriverAchievement]
    @State private var filter: BadgeFilter = .all

    private enum BadgeFilter: Hashable {
        case all
        case category(DriverAchievement.Category)

        var title: String {
            switch self {
            case .all: return "All"
            case .category(let category): return category.label
            }
        }
    }

    private var unlockedCount: Int { achievements.filter(\.unlocked).count }

    private var filters: [BadgeFilter] {
        [.all] + DriverAchievement.Category.allCases.map { .category($0) }
    }

    private var filtered: [DriverAchievement] {
        let base: [DriverAchievement]
        switch filter {
        case .all:
            base = achievements
        case .category(let category):
            base = achievements.filter { $0.category == category }
        }
        return base.sorted { lhs, rhs in
            if lhs.unlocked != rhs.unlocked { return lhs.unlocked && !rhs.unlocked }
            if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
            return lhs.title < rhs.title
        }
    }

    private var sectioned: [(DriverAchievement.Category, [DriverAchievement])] {
        DriverAchievement.Category.allCases.compactMap { category in
            let items = filtered.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Badges")
                        .font(VS.Typography.heading(28, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("\(unlockedCount) of \(achievements.count) unlocked")
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { option in
                            Button {
                                filter = option
                            } label: {
                                Text(option.title)
                                    .font(VS.Typography.body(13, weight: .semibold))
                                    .foregroundStyle(filter == option ? VS.Color.navPill : VS.Color.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        filter == option ? VS.Color.accent : VS.Color.chip,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if case .all = filter {
                    ForEach(sectioned, id: \.0) { category, items in
                        categoryBlock(category: category, items: items)
                    }
                } else if case .category(let category) = filter {
                    categoryBlock(category: category, items: filtered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .veloseetePage()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        VSIcon(icon: .caretLeft, size: 18, weight: .bold, tint: VS.Color.textSecondary)
                        Text("Driver")
                            .font(VS.Typography.body(15, weight: .semibold))
                            .foregroundStyle(VS.Color.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func categoryBlock(category: DriverAchievement.Category, items: [DriverAchievement]) -> some View {
        let earned = items.filter(\.unlocked).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.label)
                    .font(VS.Typography.heading(17))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer()
                Text("Unlocked \(earned)/\(items.count)")
                    .font(VS.Typography.body(12, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            GeometryReader { geo in
                let progress = items.isEmpty ? 0 : Double(earned) / Double(items.count)
                ZStack(alignment: .leading) {
                    Capsule().fill(VS.Color.chip)
                    Capsule()
                        .fill(VS.Color.accent.opacity(0.75))
                        .frame(width: max(earned > 0 ? 8 : 0, geo.size.width * progress))
                }
            }
            .frame(height: 4)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(items) { badge in
                    badgeCell(badge)
                }
            }
        }
    }

    private func badgeCell(_ badge: DriverAchievement) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.unlocked ? VS.Color.accent.opacity(0.14) : Color.white.opacity(0.04))
                    .frame(width: 72, height: 72)
                FluentEmojiView(emoji: badge.emoji, size: 34)
                    .opacity(badge.unlocked ? 1 : 0.35)
                    .saturation(badge.unlocked ? 1 : 0.15)
            }
            .overlay(alignment: .bottom) {
                if !badge.unlocked {
                    Text(shortProgress(badge))
                        .font(VS.Typography.body(9, weight: .bold))
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VS.Color.accent, in: Capsule())
                        .offset(y: 6)
                }
            }

            Text(badge.title)
                .font(VS.Typography.heading(12))
                .foregroundStyle(badge.unlocked ? VS.Color.textPrimary : VS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 4)

            Text(badge.unlocked ? badge.detail : badge.progressLabel)
                .font(VS.Typography.body(10))
                .foregroundStyle(VS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .top)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(badge.unlocked ? VS.Color.accent.opacity(0.07) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    badge.unlocked ? VS.Color.accent.opacity(0.25) : VS.Color.divider,
                    lineWidth: 1
                )
        )
    }

    private func shortProgress(_ badge: DriverAchievement) -> String {
        let pct = Int((badge.progress * 100).rounded())
        if pct > 0 { return "\(pct)%" }
        return "0%"
    }
}

struct ServiceListView: View {
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var editingLog: ServiceLog?
    @State private var showEditor = false

    private var logs: [ServiceLog] {
        store.serviceLogs.filter { $0.vehicleId == store.currentVehicle?.id }.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VS.Spacing.section) {
                MainTabHeader("Service", subtitle: store.currentVehicle?.nickname ?? "Keep it healthy", onProfile: onProfile)

                serviceTrendCard

                PrimaryCTAButton(title: "Log service", icon: .wrench) {
                    editingLog = nil; showEditor = true
                }

                VSSectionHeader(title: "History")
                if logs.isEmpty {
                    Button { showEditor = true } label: {
                        VStack(spacing: 14) {
                            VSIcon(icon: .wrench, size: 34, weight: .regular, tint: VS.Color.accent)
                            Text("Log your first service")
                                .font(VS.Typography.heading(16))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text("Oil, brakes, whatever’s due — keep a trail.")
                                .font(VS.Typography.body(13))
                                .foregroundStyle(VS.Color.textSecondary)
                        }.frame(maxWidth: .infinity).padding(34).glassCard()
                    }.buttonStyle(.plain)
                } else {
                    VStack(spacing: 0) {
                        ForEach(logs) { log in
                            Button { editingLog = log; showEditor = true } label: { serviceRow(log) }.buttonStyle(.plain)
                            if log.id != logs.last?.id { Divider().overlay(VS.Color.divider) }
                        }
                    }.padding(.horizontal, 14).glassCard()
                }
            }.padding(.horizontal, VS.Spacing.pageInset).padding(.bottom, 110).tracksBottomNavScroll()
        }
        .veloseetePage()
        .sheet(isPresented: $showEditor) { ServiceEditorSheet(log: editingLog) }
    }

    private var serviceTrendCard: some View {
        let latest = logs.first
        return VStack(alignment: .leading, spacing: 14) {
            Label("Service trend", systemImage: "chart.line.uptrend.xyaxis").font(VS.Typography.heading(17)).foregroundStyle(VS.Color.textPrimary)
            serviceFact("Current odometer", store.currentVehicle.map { DistanceFormat.formatOdometer($0.currentOdometer, unit: store.defaultDistanceUnit) } ?? "—")
            serviceFact("Last service", latest.map { "\($0.serviceType) · \($0.timestamp.formatted(date: .abbreviated, time: .omitted))" } ?? "No records yet")
            if let latest { serviceDueRow(latest) }
        }.padding(16).glassCard(elevated: true)
    }

    private func serviceFact(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(VS.Typography.body(12)).foregroundStyle(VS.Color.textTertiary); Spacer(); Text(value).font(VS.Typography.body(13, weight: .semibold)).foregroundStyle(VS.Color.textPrimary) }
        .padding(13).metricInset()
    }

    @ViewBuilder private func serviceDueRow(_ log: ServiceLog) -> some View {
        if let date = log.nextServiceDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
            serviceStatus(label: "Next service", value: days < 0 ? "Overdue by \(-days) days" : "Due in \(days) days", warning: days <= 7)
        } else if let next = log.nextServiceOdometer, let current = store.currentVehicle?.currentOdometer {
            let remaining = Int(next - current)
            serviceStatus(label: "Next service", value: remaining < 0 ? "Overdue by \(-remaining) km" : "\(remaining) km remaining", warning: remaining <= 500)
        }
    }

    private func serviceStatus(label: String, value: String, warning: Bool) -> some View {
        HStack { Text(label); Spacer(); Text(value).fontWeight(.semibold) }
            .font(VS.Typography.body(12)).foregroundStyle(warning ? VS.Color.warning : VS.Color.accent)
            .padding(13).background((warning ? VS.Color.warning : VS.Color.accent).opacity(0.09), in: RoundedRectangle(cornerRadius: VS.Radius.metric))
    }

    private func serviceRow(_ log: ServiceLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VSIcon(icon: .wrench, size: 18, weight: .regular, tint: VS.Color.accent).frame(width: 36, height: 36).background(VS.Color.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(log.serviceType).font(VS.Typography.heading(15)).foregroundStyle(VS.Color.textPrimary)
                Text("\(log.timestamp.formatted(date: .abbreviated, time: .omitted)) · \(DistanceFormat.formatOdometer(log.odometerReading, unit: store.defaultDistanceUnit))")
                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                if let description = log.description { Text(description).font(VS.Typography.body(11)).foregroundStyle(VS.Color.textSecondary).lineLimit(2) }
            }
            Spacer()
            if let cost = log.cost { Text(CurrencyFormat.format(cost, currency: log.currency)).font(VS.Typography.body(13, weight: .semibold)).foregroundStyle(VS.Color.textPrimary) }
        }.padding(.vertical, 14)
    }
}

struct ServiceEditorSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let log: ServiceLog?

    @State private var serviceType = "Oil Change"
    @State private var customType = ""
    @State private var odometer = ""
    @State private var cost = ""
    @State private var notes = ""
    @State private var serviceDate = Date()
    @State private var nextOdometer = ""
    @State private var nextDate = Date()
    @State private var hasNextDate = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    private let types = [
        "Oil Change", "Tire Rotation", "Brake Service", "Air Filter",
        "Battery Replacement", "Transmission Service", "General Inspection", "Other"
    ]
    private var vehicle: Vehicle? { store.currentVehicle }
    private var currencyCode: String { vehicle?.currency ?? "QAR" }
    private var finalType: String {
        serviceType == "Other"
            ? customType.trimmingCharacters(in: .whitespacesAndNewlines)
            : serviceType
    }
    private var canSave: Bool { !finalType.isEmpty && (Double(odometer) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    typeSection

                    HStack(spacing: 12) {
                        numberField(
                            label: "Odometer",
                            placeholder: "0",
                            text: $odometer,
                            suffix: "km"
                        )
                        numberField(
                            label: "Cost",
                            placeholder: "Optional",
                            text: $cost,
                            suffix: currencyCode
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Date")
                        DatePicker(
                            "Service date",
                            selection: $serviceDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(VS.Color.accent)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: 12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Notes")
                        TextField("What was done?", text: $notes, axis: .vertical)
                            .lineLimit(3...5)
                            .font(VS.Typography.body(15))
                            .foregroundStyle(VS.Color.textPrimary)
                            .padding(14)
                            .glassCard(radius: 12)
                    }

                    reminderSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    if log != nil {
                        Button("Delete service entry", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .font(VS.Typography.body(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassCard(radius: 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle(log == nil ? "Log Service" : "Edit Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryCTAButton(
                    title: log == nil ? "Save service" : "Save changes",
                    icon: .wrench,
                    isLoading: saving,
                    isEnabled: canSave
                ) {
                    Task { await save() }
                }
                .padding(20)
                .background(VS.Color.bgPrimary.opacity(0.96))
            }
            .onAppear { populate() }
            .alert("Delete service entry?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) { Task { await delete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the record from both iOS and the web app.")
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Service type")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types, id: \.self) { type in
                        let selected = serviceType == type
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            serviceType = type
                        } label: {
                            Text(type)
                                .font(VS.Typography.body(13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(selected ? VS.Color.accent : VS.Color.chip))
                                .foregroundStyle(selected ? VS.Color.navPill : VS.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if serviceType == "Other" {
                TextField("Custom type", text: $customType)
                    .font(VS.Typography.heading(18, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .padding(14)
                    .glassCard(radius: 12)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("Next reminder")
            numberField(
                label: "Next odometer",
                placeholder: "Optional",
                text: $nextOdometer,
                suffix: "km"
            )

            Toggle("Due date", isOn: $hasNextDate)
                .font(VS.Typography.heading(15))
                .foregroundStyle(VS.Color.textPrimary)
                .tint(VS.Color.accent)
                .padding(14)
                .glassCard(radius: 12)

            if hasNextDate {
                DatePicker(
                    "Due date",
                    selection: $nextDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(VS.Color.accent)
                .padding(14)
                .glassCard(radius: 12)
                .foregroundStyle(VS.Color.textPrimary)
            }
        }
    }

    private func numberField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .font(VS.Typography.heading(20, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(suffix)
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

    private func populate() {
        guard let log else {
            odometer = vehicle.map { String(format: "%.0f", $0.currentOdometer) } ?? ""
            return
        }
        serviceType = types.contains(log.serviceType) ? log.serviceType : "Other"
        customType = serviceType == "Other" ? log.serviceType : ""
        odometer = String(format: "%.0f", log.odometerReading)
        cost = log.cost.map { String(format: "%.2f", $0) } ?? ""
        notes = log.description ?? ""
        serviceDate = log.timestamp
        nextOdometer = log.nextServiceOdometer.map { String(format: "%.0f", $0) } ?? ""
        if let date = log.nextServiceDate {
            hasNextDate = true
            nextDate = date
        }
    }

    private func save() async {
        guard let vehicle, let odo = Double(odometer) else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let input = FirestoreRepository.ServiceLogInput(
                vehicleId: vehicle.id,
                timestamp: serviceDate,
                odometerReading: odo,
                serviceType: finalType,
                description: notes.isEmpty ? nil : notes,
                cost: Double(cost),
                currency: vehicle.currency,
                nextServiceOdometer: Double(nextOdometer),
                nextServiceDate: hasNextDate ? nextDate : nil
            )
            try await store.saveServiceLog(id: log?.id, input: input)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        guard let log else { return }
        do {
            try await store.deleteServiceLog(log)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarError: String?
    @State private var isPreparingCrop = false
    @State private var isSavingAvatar = false
    @State private var cropDraft: AvatarCropDraft?
    /// Frozen UI avatar for the whole change/crop session — never follows drafts.
    @State private var displayAvatar: UIImage?
    @State private var draftName = ""
    @State private var draftCurrency = "QAR"
    @State private var draftDistance = "km"
    @State private var isSavingDetails = false
    @State private var profileError: String?
    @State private var showEditAccount = false
    @State private var showReplayOnboarding = false
    @State private var showPermissionManager = false
    @State private var showLinkEmail = false
    @State private var showLinkApple = false
    @State private var linkEmail = ""
    @State private var linkPassword = ""
    @State private var linkError: String?
    @State private var isLinking = false
    @State private var appleLinkNonce = ""
    @State private var legalDocument: AppLegal.Document?
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    /// What the profile header shows: locked display during replace, else store.
    private var headerAvatar: UIImage? {
        displayAvatar ?? avatarStore.image
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatarView(image: headerAvatar, size: 104)

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                VSIcon(icon: .plusCircle, size: 20, weight: .fill, tint: VS.Color.navPill)
                                    .frame(width: 34, height: 34)
                                    .background(VS.Color.accent, in: Circle())
                                    .overlay(Circle().stroke(VS.Color.bgSecondary, lineWidth: 3))
                            }
                            .accessibilityLabel(headerAvatar == nil ? "Add profile photo" : "Change profile photo")
                            .disabled(isPreparingCrop || isSavingAvatar || avatarStore.isReplacing)
                        }

                        VStack(spacing: 4) {
                            Text(store.userName.isEmpty ? "Your profile" : store.userName)
                                .font(VS.Typography.heading(20, weight: .bold))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text(headerAvatar == nil ? "Add a photo from your library" : "Saved on this iPhone")
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.textTertiary)
                        }

                        if isSavingAvatar {
                            ProgressView("Saving photo…")
                                .font(VS.Typography.body(12))
                                .tint(VS.Color.accent)
                        } else if isPreparingCrop {
                            ProgressView("Opening photo…")
                                .font(VS.Typography.body(12))
                                .tint(VS.Color.accent)
                        } else if headerAvatar != nil {
                            HStack(spacing: 18) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Text("Change photo")
                                }
                                Button("Remove", role: .destructive) {
                                    guard let userId = auth.userId else { return }
                                    do {
                                        try avatarStore.remove(userId: userId)
                                        displayAvatar = nil
                                    } catch {
                                        avatarError = error.localizedDescription
                                    }
                                }
                            }
                            .font(VS.Typography.body(13, weight: .semibold))
                        }

                        if let avatarError {
                            Text(avatarError)
                                .font(VS.Typography.body(11))
                                .foregroundStyle(VS.Color.error)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    LabeledContent("Name", value: store.userName.isEmpty ? "—" : store.userName)
                    LabeledContent("Currency", value: store.userDocument?.profile.defaultCurrency ?? "QAR")
                    LabeledContent("Distance", value: store.defaultDistanceUnit == "mi" ? "Miles" : "Kilometres")

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Email", value: auth.user?.email ?? "Hidden / not shared")
                        Text("Managed by your linked sign-in methods.")
                            .font(VS.Typography.body(10))
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    Button {
                        prepareProfileDrafts()
                        profileError = nil
                        showEditAccount = true
                    } label: {
                        Label("Edit account", systemImage: "pencil")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                } header: {
                    Text("Account")
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    ForEach(AuthProviderKind.allCases) { provider in
                        HStack(spacing: 12) {
                            Image(systemName: providerIcon(provider))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(VS.Color.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.title)
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text(auth.isLinked(provider) ? "Connected" : "Not linked")
                                    .font(VS.Typography.body(11))
                                    .foregroundStyle(VS.Color.textTertiary)
                            }

                            Spacer()

                            if auth.isLinked(provider) {
                                if auth.linkedProviders.count > 1 {
                                    Button("Unlink") {
                                        Task {
                                            do { try await auth.unlink(provider) }
                                            catch { linkError = auth.errorMessage ?? error.localizedDescription }
                                        }
                                    }
                                    .font(VS.Typography.body(13, weight: .semibold))
                                    .foregroundStyle(VS.Color.error)
                                } else {
                                    Text("Primary")
                                        .font(VS.Typography.body(12, weight: .semibold))
                                        .foregroundStyle(VS.Color.textTertiary)
                                }
                            } else {
                                Button("Link") {
                                    Task { await linkProvider(provider) }
                                }
                                .font(VS.Typography.body(13, weight: .semibold))
                                .foregroundStyle(VS.Color.accent)
                                .disabled(isLinking)
                            }
                        }
                    }

                    if let linkError {
                        Text(linkError)
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.error)
                    }
                    if let info = auth.infoMessage {
                        Text(info)
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.success)
                    }
                } header: {
                    Text("Sign-in methods")
                } footer: {
                    Text("Link Apple, Google, or email so you can open the same Veloseete account with any of them.")
                        .font(VS.Typography.body(11))
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section("App setup") {
                    Button {
                        showPermissionManager = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Manage trip permissions").foregroundStyle(VS.Color.textPrimary)
                                Text("Location, motion and notifications")
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .target, size: 20, weight: .regular, tint: VS.Color.accent)
                        }
                    }

                    Button {
                        showReplayOnboarding = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Replay onboarding").foregroundStyle(VS.Color.textPrimary)
                                Text("See the Veloseete introduction again")
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .roadHorizon, size: 20, weight: .regular, tint: VS.Color.accent)
                        }
                    }
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section("Legal") {
                    Button("Privacy Policy") { legalDocument = .privacy }
                    Button("Terms of Use") { legalDocument = .terms }
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    Button("Sign out", role: .destructive) {
                        try? auth.signOut()
                        dismiss()
                    }
                    Button(role: .destructive) {
                        showDeleteAccountConfirm = true
                    } label: {
                        if isDeletingAccount {
                            ProgressView()
                                .tint(VS.Color.error)
                        } else {
                            Text("Delete account")
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text("Deletes your Veloseete cloud data and sign-in on this account. This can’t be undone.")
                        .font(VS.Typography.body(11))
                }
                .listRowBackground(VS.Color.bgSecondary)

                if let deleteAccountError {
                    Section {
                        Text(deleteAccountError)
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.error)
                    }
                    .listRowBackground(VS.Color.bgSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .veloseetePage()
            .foregroundStyle(VS.Color.textPrimary)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .sheet(item: $legalDocument) { doc in
                LegalDocumentView(document: doc)
            }
            .sheet(isPresented: $showEditAccount) {
                EditAccountDrawer(
                    draftName: $draftName,
                    draftCurrency: $draftCurrency,
                    draftDistance: $draftDistance,
                    isSaving: isSavingDetails,
                    errorMessage: profileError
                ) {
                    Task {
                        await saveProfileDetails()
                        if profileError == nil {
                            showEditAccount = false
                        }
                    }
                }
            }
            .alert("Delete account?", isPresented: $showDeleteAccountConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete forever", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This removes your vehicles, fuel, service, trips, and sign-in. Photos saved only on this iPhone are cleared too.")
            }
            .fullScreenCover(item: $cropDraft, onDismiss: {
                abandonAvatarReplacementIfNeeded()
            }) { draft in
                ProfilePhotoCropView(image: draft.image) { cropped in
                    commitCroppedAvatar(cropped)
                } onCancel: {
                    cropDraft = nil
                }
            }
            .fullScreenCover(isPresented: $showReplayOnboarding) {
                TripPermissionsOnboardingView {
                    showReplayOnboarding = false
                }
            }
            .fullScreenCover(isPresented: $showPermissionManager) {
                TripPermissionsOnboardingView(startAtPermissions: true) {
                    showPermissionManager = false
                }
            }
            .sheet(isPresented: $showLinkEmail) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Link email & password")
                            .font(VS.Typography.heading(22))
                        Text("Add email sign-in to this account so you can open Veloseete without Apple or Google.")
                            .font(VS.Typography.body(14))
                            .foregroundStyle(VS.Color.textSecondary)

                        TextField("Email", text: $linkEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .vsInputField()

                        SecureField("Password (min 6 characters)", text: $linkPassword)
                            .vsInputField()

                        if let linkError {
                            Text(linkError)
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.error)
                        }

                        Button {
                            Task {
                                isLinking = true
                                linkError = nil
                                defer { isLinking = false }
                                do {
                                    try await auth.linkEmailPassword(
                                        email: linkEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                                        password: linkPassword
                                    )
                                    showLinkEmail = false
                                    linkPassword = ""
                                } catch {
                                    linkError = auth.errorMessage ?? error.localizedDescription
                                }
                            }
                        } label: {
                            HStack {
                                if isLinking { ProgressView().tint(VS.Color.navPill) }
                                Text("Link email")
                                    .font(VS.Typography.heading(16))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(VS.Color.accent)
                            .foregroundStyle(VS.Color.navPill)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isLinking)

                        Spacer()
                    }
                    .padding(20)
                    .veloseetePage()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showLinkEmail = false }
                        }
                    }
                }
                .presentationDetents([.medium])
                .veloseeteSheet()
            }
            .sheet(isPresented: $showLinkApple) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Link Apple")
                            .font(VS.Typography.heading(22))
                        Text("Connect Sign in with Apple to this Veloseete account.")
                            .font(VS.Typography.body(14))
                            .foregroundStyle(VS.Color.textSecondary)

                        SignInWithAppleButton(.continue) { request in
                            appleLinkNonce = auth.startAppleSignIn()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = appleLinkNonce
                        } onCompletion: { result in
                            Task {
                                isLinking = true
                                linkError = nil
                                defer { isLinking = false }
                                switch result {
                                case .success(let authorization):
                                    do {
                                        try await auth.completeAppleSignIn(authorization: authorization, linking: true)
                                        showLinkApple = false
                                    } catch {
                                        linkError = auth.errorMessage ?? error.localizedDescription
                                    }
                                case .failure(let error):
                                    let ns = error as NSError
                                    if ns.code != ASAuthorizationError.canceled.rawValue {
                                        linkError = error.localizedDescription
                                    }
                                }
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if let linkError {
                            Text(linkError)
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.error)
                        }

                        Spacer()
                    }
                    .padding(20)
                    .veloseetePage()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showLinkApple = false }
                        }
                    }
                }
                .presentationDetents([.medium])
                .veloseeteSheet()
            }
            .onAppear {
                // Seed the frozen header from whatever is already committed.
                if displayAvatar == nil {
                    displayAvatar = avatarStore.image
                }
            }
            .onChange(of: avatarStore.image) { _, newValue in
                // Outside a replace session, keep the header in sync with the store.
                if !avatarStore.isReplacing {
                    displayAvatar = newValue
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                beginAvatarReplacement()
                isPreparingCrop = true
                avatarError = nil
                Task {
                    defer {
                        isPreparingCrop = false
                        selectedPhoto = nil
                    }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw ProfileAvatarError.invalidImage
                        }
                        guard let image = UIImage(data: data) else { throw ProfileAvatarError.invalidImage }
                        // Header stays on displayAvatar / store backup — only cropper gets the draft.
                        cropDraft = AvatarCropDraft(image: image)
                    } catch {
                        avatarError = error.localizedDescription
                        abandonAvatarReplacementIfNeeded()
                    }
                }
            }
        }
        .veloseeteSheet()
    }

    private func beginAvatarReplacement() {
        // Freeze whatever is currently shown so PhotosPicker / memory pressure cannot blank it.
        let committed = displayAvatar ?? avatarStore.image
        displayAvatar = committed?.stableCopy() ?? committed
        avatarStore.beginReplacement(preserving: displayAvatar)
    }

    private func commitCroppedAvatar(_ cropped: UIImage) {
        guard let userId = auth.userId else {
            cropDraft = nil
            abandonAvatarReplacementIfNeeded()
            avatarError = "Sign in again to save your photo."
            return
        }
        isSavingAvatar = true
        avatarError = nil
        defer { isSavingAvatar = false }
        do {
            try avatarStore.finishReplacement(image: cropped, userId: userId)
            displayAvatar = avatarStore.image
            cropDraft = nil
        } catch {
            cropDraft = nil
            abandonAvatarReplacementIfNeeded()
            avatarError = error.localizedDescription
        }
    }

    private func abandonAvatarReplacementIfNeeded() {
        // Only roll back when a replace session is still open (cancel / failed load).
        // Successful save clears `isReplacing` first so dismiss will not undo it.
        guard avatarStore.isReplacing else { return }
        displayAvatar = avatarStore.cancelReplacement()
    }

    private func prepareProfileDrafts() {
        draftName = store.userName
        draftCurrency = store.userDocument?.profile.defaultCurrency ?? "QAR"
        draftDistance = store.defaultDistanceUnit
        profileError = nil
    }

    private func saveProfileDetails() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingDetails = true
        profileError = nil
        defer { isSavingDetails = false }
        do {
            try await store.updateProfile(userName: name, currency: draftCurrency, distanceUnit: draftDistance)
        } catch {
            profileError = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }
        do {
            try await auth.deleteAccount()
            dismiss()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    private func providerIcon(_ provider: AuthProviderKind) -> String {
        switch provider {
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .password: return "envelope.fill"
        }
    }

    private func linkProvider(_ provider: AuthProviderKind) async {
        linkError = nil
        switch provider {
        case .apple:
            showLinkApple = true
        case .google:
            isLinking = true
            defer { isLinking = false }
            do {
                try await auth.signInWithGoogle(linking: true)
            } catch {
                linkError = auth.errorMessage ?? error.localizedDescription
            }
        case .password:
            linkEmail = auth.user?.email ?? ""
            linkPassword = ""
            showLinkEmail = true
        }
    }
}

private struct EditAccountDrawer: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draftName: String
    @Binding var draftCurrency: String
    @Binding var draftDistance: String
    let isSaving: Bool
    let errorMessage: String?
    let onSave: () -> Void

    private let currencies = ["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"]

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display name")
                            .font(VS.Typography.body(12, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        TextField("Your name", text: $draftName)
                            .font(VS.Typography.heading(18, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                            .padding(14)
                            .glassCard(radius: 12)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Currency")
                            .font(VS.Typography.body(12, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(currencies, id: \.self) { code in
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        draftCurrency = code
                                    } label: {
                                        Text(code)
                                            .font(VS.Typography.body(13, weight: .semibold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule().fill(draftCurrency == code ? VS.Color.accent : VS.Color.chip)
                                            )
                                            .foregroundStyle(draftCurrency == code ? VS.Color.navPill : VS.Color.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Distance")
                            .font(VS.Typography.body(12, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        HStack(spacing: 8) {
                            distanceChip("km", title: "Kilometres")
                            distanceChip("mi", title: "Miles")
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }
                }
                .padding(20)
            }
            .veloseetePage()
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onSave) {
                    HStack(spacing: 10) {
                        if isSaving { ProgressView().tint(VS.Color.navPill) }
                        Text("Save")
                            .font(VS.Typography.heading(16))
                    }
                    .foregroundStyle(VS.Color.navPill)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                            .fill(canSave ? VS.Color.accent : VS.Color.chip)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(20)
                .background(VS.Color.bgPrimary.opacity(0.96))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .veloseeteSheet()
    }

    private func distanceChip(_ tag: String, title: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            draftDistance = tag
        } label: {
            Text(title)
                .font(VS.Typography.body(13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(draftDistance == tag ? VS.Color.accent : VS.Color.chip)
                )
                .foregroundStyle(draftDistance == tag ? VS.Color.navPill : VS.Color.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

/// Holds a library photo while the cropper is open (does not replace the committed avatar).
struct AvatarCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Local car photos (same crop pipeline as profile avatars). Keyed by vehicle id.
@MainActor
final class VehiclePhotoStore: ObservableObject {
    static let shared = VehiclePhotoStore()

    @Published private(set) var images: [String: UIImage] = [:]

    private let fileManager = FileManager.default
    private let maxDimension: CGFloat = 800

    private init() {}

    func image(for vehicleId: String) -> UIImage? {
        images[vehicleId]
    }

    func load(vehicleId: String) {
        guard images[vehicleId] == nil else { return }
        let url = fileURL(for: vehicleId)
        guard let data = try? Data(contentsOf: url),
              let loaded = UIImage(data: data)?.stableCopy() else { return }
        images[vehicleId] = loaded
    }

    func load(vehicleIds: [String]) {
        for id in vehicleIds { load(vehicleId: id) }
    }

    func save(image source: UIImage, vehicleId: String) throws {
        let normalized = resizedImage(source).stableCopy()
        guard let jpeg = normalized.jpegData(compressionQuality: 0.82) else {
            throw ProfileAvatarError.processingFailed
        }
        try fileManager.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        try jpeg.write(to: fileURL(for: vehicleId), options: .atomic)
        images[vehicleId] = normalized
    }

    func remove(vehicleId: String) throws {
        let url = fileURL(for: vehicleId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        images[vehicleId] = nil
    }

    func removeAll() {
        images.removeAll()
        try? fileManager.removeItem(at: photoDirectory)
    }

    private var photoDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Veloseete/VehiclePhotos", isDirectory: true)
    }

    private func fileURL(for vehicleId: String) -> URL {
        let safeId = vehicleId.replacingOccurrences(of: "/", with: "_")
        return photoDirectory.appendingPathComponent("\(safeId).jpg")
    }

    private func resizedImage(_ source: UIImage) -> UIImage {
        let sourceSize = source.size
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > maxDimension else { return source.stableCopy() }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

@MainActor
final class ProfileAvatarStore: ObservableObject {
    static let shared = ProfileAvatarStore()

    @Published private(set) var image: UIImage?
    /// True while PhotosPicker / cropper is in progress — `load` will not clobber `image`.
    @Published private(set) var isReplacing = false

    private var replacementBackup: UIImage?
    private let fileManager = FileManager.default
    private let maxDimension: CGFloat = 800

    private init() {}

    func load(userId: String?) {
        // Never wipe the on-screen avatar mid change/crop.
        guard !isReplacing else { return }

        guard let userId else {
            image = nil
            replacementBackup = nil
            return
        }

        let url = fileURL(for: userId)
        // Decode via Data so the bitmap is not purgeable under memory pressure.
        guard let data = try? Data(contentsOf: url),
              let loaded = UIImage(data: data)?.stableCopy() else {
            // Failed read must not blank an avatar that is already showing.
            return
        }
        image = loaded
    }

    func beginReplacement(preserving committed: UIImage?) {
        if !isReplacing {
            replacementBackup = (committed ?? image)?.stableCopy()
            isReplacing = true
        }
        // Keep publishing the committed photo for dashboard / trips / profile.
        if let backup = replacementBackup {
            image = backup
        }
    }

    @discardableResult
    func cancelReplacement() -> UIImage? {
        let restored = replacementBackup?.stableCopy() ?? replacementBackup
        image = restored
        replacementBackup = nil
        isReplacing = false
        return restored
    }

    func finishReplacement(image newImage: UIImage, userId: String) throws {
        try save(image: newImage, userId: userId)
        replacementBackup = nil
        isReplacing = false
    }

    func save(data: Data, userId: String) throws {
        guard let source = UIImage(data: data) else {
            throw ProfileAvatarError.invalidImage
        }
        try save(image: source, userId: userId)
    }

    func save(image source: UIImage, userId: String) throws {
        let normalized = resizedImage(source).stableCopy()
        guard let jpeg = normalized.jpegData(compressionQuality: 0.82) else {
            throw ProfileAvatarError.processingFailed
        }
        try fileManager.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        try jpeg.write(to: fileURL(for: userId), options: .atomic)
        self.image = normalized
    }

    func remove(userId: String) throws {
        let url = fileURL(for: userId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        image = nil
        replacementBackup = nil
        isReplacing = false
    }

    private var avatarDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Veloseete/Avatars", isDirectory: true)
    }

    private func fileURL(for userId: String) -> URL {
        let safeId = userId.replacingOccurrences(of: "/", with: "_")
        return avatarDirectory.appendingPathComponent("\(safeId).jpg")
    }

    private func resizedImage(_ source: UIImage) -> UIImage {
        let sourceSize = source.size
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > maxDimension else { return source.stableCopy() }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

extension UIImage {
    /// Copies into a non-purgeable bitmap so the avatar does not vanish under memory pressure.
    func stableCopy() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let size = self.size
        guard size.width > 0, size.height > 0 else { return self }
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum ProfileAvatarError: LocalizedError {
    case invalidImage
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "That photo could not be opened. Please choose another image."
        case .processingFailed: return "The photo could not be prepared for saving."
        }
    }
}

struct ProfileAvatarView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Stable identity so SwiftUI does not drop the bitmap mid-picker.
                    .id(image.hashValue)
            } else {
                ZStack {
                    VS.Color.bgSecondary
                    VSIcon(icon: .user, size: size * 0.42, weight: .fill, tint: VS.Color.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: size > 60 ? 16 : 8, y: 5)
    }
}

struct ProfilePhotoCropView: View {
    let image: UIImage
    var title: String = "Reframe your photo"
    var subtitle: String = "Move and zoom until it feels right"
    var footer: String = "Only the circular area will appear in your profile"
    let onUse: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    private let cropSize: CGFloat = 310

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 7) {
                    Text(title)
                        .font(VS.Typography.heading(26, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(subtitle)
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)
                }

                cropCanvas

                HStack(spacing: 10) {
                    VSIcon(icon: .user, size: 15, weight: .regular, tint: VS.Color.textTertiary)
                    Slider(value: $zoom, in: 1...4)
                        .tint(VS.Color.accent)
                        .onChange(of: zoom) { _, newValue in
                            settledZoom = newValue
                            offset = constrained(offset, zoom: newValue)
                            settledOffset = offset
                        }
                    VSIcon(icon: .user, size: 22, weight: .fill, tint: VS.Color.textSecondary)
                }
                .padding(.horizontal, 26)

                Text(footer)
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.textTertiary)

                Spacer()

                Button {
                    onUse(renderCrop())
                } label: {
                    Text("Use this photo")
                        .font(VS.Typography.heading(17))
                        .foregroundStyle(VS.Color.navPill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VS.Color.accent, in: RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
            .padding(.top, 18)
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(VS.Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            zoom = 1
                            settledZoom = 1
                            offset = .zero
                            settledOffset = .zero
                        }
                    }
                    .foregroundStyle(VS.Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cropCanvas: some View {
        let base = baseImageSize
        return Image(uiImage: image)
            .resizable()
            .frame(width: base.width, height: base.height)
            .scaleEffect(zoom)
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = constrained(
                            CGSize(
                                width: settledOffset.width + value.translation.width,
                                height: settledOffset.height + value.translation.height
                            ),
                            zoom: zoom
                        )
                    }
                    .onEnded { _ in settledOffset = offset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = min(max(settledZoom * value, 1), 4)
                        offset = constrained(offset, zoom: zoom)
                    }
                    .onEnded { _ in
                        settledZoom = zoom
                        settledOffset = offset
                    }
            )
            .frame(width: cropSize, height: cropSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(VS.Color.accent, lineWidth: 3))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 8).padding(-7))
            .shadow(color: VS.Color.accent.opacity(0.18), radius: 24)
            .contentShape(Circle())
    }

    private var baseImageSize: CGSize {
        let source = image.size
        let scale = max(cropSize / source.width, cropSize / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private func constrained(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        let size = baseImageSize
        let maxX = max(0, (size.width * zoom - cropSize) / 2)
        let maxY = max(0, (size.height * zoom - cropSize) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func renderCrop() -> UIImage {
        let outputSize: CGFloat = 800
        let conversion = outputSize / cropSize
        let displayed = baseImageSize
        let drawSize = CGSize(
            width: displayed.width * zoom * conversion,
            height: displayed.height * zoom * conversion
        )
        let drawOrigin = CGPoint(
            x: ((cropSize - displayed.width * zoom) / 2 + offset.width) * conversion,
            y: ((cropSize - displayed.height * zoom) / 2 + offset.height) * conversion
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize), format: format).image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}
