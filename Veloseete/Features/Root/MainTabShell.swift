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
    @EnvironmentObject private var auth: AuthService
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
                    DetailsListView(
                        onProfile: { showProfile = true },
                        onSwitchTab: { tab = $0 }
                    )
                case .driver:
                    DriverProfileView(onProfile: { showProfile = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "bottomNavScroll")

            BottomNavBar(active: $tab)
        }
        // Always fill the home-indicator region so Drives (map ignoresSafeArea)
        // and every other tab share the same bottom-nav baseline.
        .ignoresSafeArea(.container, edges: .bottom)
        .environmentObject(navChrome)
        .onChange(of: tab) { _, _ in
            navChrome.reset()
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            guard !isAuthenticated else { return }
            showProfile = false
            carPlayRefuelDraft = nil
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
struct MainTabHeader<Accessory: View>: View {
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    let title: String
    let subtitle: String?
    let onProfile: () -> Void
    var accessory: Accessory

    init(
        _ title: String,
        subtitle: String? = nil,
        onProfile: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onProfile = onProfile
        self.accessory = accessory()
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
            accessory
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
        .padding(.top, VS.Spacing.xs)
        .padding(.bottom, 0)
    }
}

extension MainTabHeader where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil, onProfile: @escaping () -> Void) {
        self.init(title, subtitle: subtitle, onProfile: onProfile) { EmptyView() }
    }
}

struct BottomNavBar: View {
    @Binding var active: AppTab
    @EnvironmentObject private var navChrome: BottomNavChrome

    /// Matches web DashboardV2 (`#101012` selected pill, lime icon circle).
    private let selectedPill = VS.Color.navActive
    private let outerPill = VS.Color.navPill

    private var isCompact: Bool {
        // Drives map + drawer already fight for vertical space — keep the pill full-size.
        active == .trips ? false : navChrome.isCompact
    }

    private var iconSize: CGFloat { isCompact ? 18 : 22 }
    private var circleSize: CGFloat { isCompact ? 34 : 40 }
    private var itemMinHeight: CGFloat { isCompact ? 40 : 48 }
    private var outerPadding: CGFloat { isCompact ? 6 : 10 }
    private var horizontalInset: CGFloat { isCompact ? 28 : 16 }
    /// How far the pill dips into the home-indicator region (same on every tab).
    private var homeIndicatorDip: CGFloat { isCompact ? 14 : 18 }

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
        // Parent shell always ignores the bottom safe area, so pad from the
        // physical bottom using the window inset — identical on Drives + others.
        .padding(.bottom, max(Self.homeIndicatorInset - homeIndicatorDip, 6))
    }

    /// Stable home-indicator height from the key window (not affected by tab layout).
    private static var homeIndicatorInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets.bottom ?? 34
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
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var vehiclePhotos: VehiclePhotoStore
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    let onProfile: () -> Void
    var onSwitchTab: (AppTab) -> Void = { _ in }
    @State private var showAddVehicle = false
    @State private var editingVehicle: Vehicle?
    @State private var vehiclePendingArchive: Vehicle?
    @State private var archiveError: String?
    @State private var isArchiving = false
    @State private var garageSegment: GarageFleetSegment = .active
    @State private var heroPage = 0

    private var currentVehicle: Vehicle? { store.currentVehicle }

    var body: some View {
        garageScrollContent
            .sheet(isPresented: $showAddVehicle) {
            GarageView(onComplete: {
                showAddVehicle = false
            })
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
            syncHeroPageToActiveVehicle()
        }
        .onChange(of: store.vehicles.map(\.id) + store.archivedVehicles.map(\.id)) { _, ids in
            vehiclePhotos.load(vehicleIds: ids)
            syncHeroPageToActiveVehicle()
        }
        .onChange(of: store.currentVehicle?.id) { _, _ in
            guard garageSegment == .active else { return }
            syncHeroPageToActiveVehicle()
        }
        .onChange(of: garageSegment) { _, segment in
            guard segment == .active else { return }
            syncHeroPageToActiveVehicle()
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            guard !isAuthenticated else { return }
            showAddVehicle = false
            editingVehicle = nil
            vehiclePendingArchive = nil
        }
    }

    private var garageScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VS.Spacing.floatStack) {
                MainTabHeader(
                    "Garage",
                    subtitle: garageSubtitle,
                    onProfile: onProfile
                ) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showAddVehicle = true
                    } label: {
                        VSIcon(icon: .plusCircle, size: 20, weight: .regular, tint: VS.Color.accent)
                            .frame(width: 40, height: 40)
                            .background(VS.Color.chip, in: Circle())
                            .overlay(Circle().strokeBorder(VS.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Add car")
                }

                garageErrorBanner

                GarageHeroCarousel(
                    segment: $garageSegment,
                    page: $heroPage,
                    onAddVehicle: { showAddVehicle = true },
                    onEditVehicle: { editingVehicle = $0 },
                    onRestoreVehicle: { vehicle in
                        Task { await restoreArchivedVehicle(vehicle) }
                    }
                )
                .padding(.horizontal, -VS.Spacing.pageInset)
            }
            .padding(.horizontal, VS.Spacing.pageInset)
            .padding(.bottom, 110)
            .tracksBottomNavScroll()
        }
        .veloseetePage()
    }

    private func syncHeroPageToActiveVehicle() {
        guard garageSegment == .active else { return }
        guard !store.vehicles.isEmpty else {
            heroPage = 0
            return
        }
        if let activeId = store.currentVehicle?.id,
           let index = store.vehicles.firstIndex(where: { $0.id == activeId }) {
            heroPage = index
        } else {
            heroPage = min(heroPage, store.vehicles.count)
        }
    }

    private func restoreArchivedVehicle(_ vehicle: Vehicle) async {
        do {
            archiveError = nil
            try await store.restoreVehicle(vehicle.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.snappy(duration: 0.28)) {
                garageSegment = .active
                heroPage = 0
            }
            syncHeroPageToActiveVehicle()
        } catch {
            archiveError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var garageErrorBanner: some View {
        if let archiveError {
            Text(archiveError)
                .font(VS.Typography.body(12))
                .foregroundStyle(VS.Color.error)
        }
    }

    private var garageSubtitle: String {
        let count = store.vehicles.count
        if count == 0 { return TrackyVoice.Soft.garageSubtitle }
        if count == 1, let vehicle = store.currentVehicle {
            return vehicle.nickname
        }
        if let active = store.currentVehicle?.nickname {
            return "\(count) cars · \(active) active"
        }
        return "\(count) cars"
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

    private func garageBentoStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(VS.Typography.heading(26, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func garageBentoCount(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value)")
                .font(VS.Typography.heading(32, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label)
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
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
    @State private var paint: VehiclePaintColor
    @State private var usePhoto: Bool
    @State private var draftPhoto: UIImage?
    @State private var removeExistingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropDraft: AvatarCropDraft?
    @State private var isPreparingCrop = false
    @State private var isSaving = false
    @State private var isSettingActive = false
    @State private var errorMessage: String?

    private let fuelTypes = [
        ("petrol", "Petrol"),
        ("diesel", "Diesel"),
        ("hybrid", "Hybrid"),
        ("electric", "Electric")
    ]
    private let currencies = ["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"]

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
        _paint = State(initialValue: VehiclePaintColor.resolve(vehicle.paintColor))
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
                        VehicleMakeChipRow(make: $make)
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle(vehicle.nickname)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    PrimaryCTAButton(
                        title: "Save changes",
                        icon: .checkCircle,
                        isLoading: isSaving,
                        isEnabled: canSave && !isPreparingCrop && !isSettingActive
                    ) {
                        Task { await save() }
                    }

                    if !isActiveVehicle {
                        Button {
                            Task { await setActive() }
                        } label: {
                            HStack {
                                if isSettingActive {
                                    ProgressView().tint(VS.Color.textPrimary)
                                }
                                Text("Set as active")
                                    .font(VS.Typography.heading(15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(VS.Color.chip, in: Capsule())
                            .foregroundStyle(VS.Color.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || isSettingActive)

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
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || isSettingActive)
                    } else if store.vehicles.count > 1 {
                        Text("Set another car active before archiving this one.")
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
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
                vehicleAppearancePreview(
                    image: usePhoto ? previewImage : nil,
                    emoji: icon,
                    paint: paint,
                    size: 72
                )

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text(previewImage == nil ? "Add car photo" : "Change photo")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                    .disabled(isPreparingCrop)

                    if usePhoto, previewImage != nil {
                        Button("Use car mark instead") {
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
                fieldLabel("Colour")
                VehiclePaintSwatchRow(paint: $paint)

                fieldLabel("Car mark")
                VehicleMarkCarousel(icon: $icon, paint: paint) {
                    usePhoto = false
                    removeExistingPhoto = true
                    draftPhoto = nil
                }
            }
        }
    }

    private var canSave: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(odometer) != nil
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

    private func setActive() async {
        guard !isActiveVehicle else { return }
        isSettingActive = true
        errorMessage = nil
        defer { isSettingActive = false }
        do {
            try await store.selectVehicle(vehicle.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
        updated.paintColor = paint == .brand ? nil : paint.rawValue
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

private func vehicleAppearancePreview(
    image: UIImage?,
    emoji: String,
    paint: VehiclePaintColor = .brand,
    size: CGFloat,
    well: Color = VS.Color.accent.opacity(0.16),
    stroke: Color = Color.white.opacity(0.12)
) -> some View {
    let mark = VehicleMarkStyle.resolve(emoji)
    return Group {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            VehicleMark(style: mark, size: size * 0.88, paint: paint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(well)
                )
        }
    }
    .overlay(
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .stroke(stroke, lineWidth: 1)
    )
}

struct DriverProfileView: View {
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var showBadges = false
    @State private var selectedBadge: DriverAchievement?

    private var unit: String { store.defaultDistanceUnit }
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
            vehicleCreatedDates: store.vehicles.map(\.createdAt),
            vehicleId: nil,
            unit: unit,
            manufacturerStandard: store.manufacturerStandard
        )
    }

    private var unlockedCount: Int { achievements.filter(\.unlocked).count }

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

    private var driverHeaderSubtitle: String {
        let drives = store.tripsForActiveVehicles.count
        let road = DistanceFormat.formatDistance(totalKm, unit: unit)
        if drives == 0 { return "\(road) all-time · start a drive" }
        return "\(drives) drive\(drives == 1 ? "" : "s") · \(road) all-time"
    }

    private var monthTrips: [Trip] {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return store.tripsForActiveVehicles.filter { $0.startedAt >= start }
    }

    private var monthKm: Double {
        monthTrips.reduce(0) { $0 + max(0, $1.distanceKm) }
    }

    private var lastMonthKm: Double {
        let cal = Calendar.current
        guard let thisStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())),
              let lastStart = cal.date(byAdding: .month, value: -1, to: thisStart) else { return 0 }
        return store.tripsForActiveVehicles
            .filter { $0.startedAt >= lastStart && $0.startedAt < thisStart }
            .reduce(0) { $0 + max(0, $1.distanceKm) }
    }

    private var monthKmTrend: String? {
        guard lastMonthKm > 5, monthKm > 0 else { return nil }
        let change = ((monthKm - lastMonthKm) / lastMonthKm) * 100
        if abs(change) < 3 { return "Holding steady vs last month" }
        let absVal = Int(abs(change).rounded())
        return change > 0 ? "↑ \(absVal)% vs last month" : "↓ \(absVal)% vs last month"
    }

    /// 0 = calm, 1 = spirited — from recent trip top speeds (driver style, not car thirst).
    private var driverStyleScore: Double {
        let recent = Array(monthTrips.suffix(12))
        guard !recent.isEmpty else { return 0.22 }
        let avgTop = recent.map(\.maxSpeedKmh).reduce(0, +) / Double(recent.count)
        return min(max((avgTop - 45) / 85, 0.08), 1)
    }

    private var monthRoadHours: Double {
        monthTrips.reduce(0) { $0 + $1.durationSec } / 3600
    }

    private var monthTopSpeedKmh: Double {
        monthTrips.map(\.maxSpeedKmh).max() ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VS.Spacing.floatStack) {
                    MainTabHeader(
                        displayName,
                        subtitle: driverHeaderSubtitle,
                        onProfile: onProfile
                    ) {
                        Button {
                            showBadges = true
                        } label: {
                            Text("\(unlockedCount)/\(achievements.count)")
                                .font(VS.Typography.mono(11, weight: .bold))
                                .foregroundStyle(VS.Color.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(VS.Color.chip, in: Capsule())
                                .overlay(Capsule().strokeBorder(VS.Color.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(unlockedCount) of \(achievements.count) badges")
                    }

                    driverStatusCard
                    driverMonthSection
                    TrackyInlineMoodRow()
                    topInsightSection
                    badgesHubPreview
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
            .sheet(item: $selectedBadge) { badge in
                BadgeDetailDrawer(badge: badge)
                    .presentationDetents([.medium, .large])
                    .veloseeteSheet()
            }
        }
    }

    /// How you’re driving — activity + style. Car fuel lives in Garage.
    private var driverStatusCard: some View {
        let vibe = driverActivityVibe
        let toneColor: Color = {
            switch vibe.tone {
            case .excellent, .good: return VS.Color.accent
            case .watch: return VS.Color.warning
            case .learning, .neutral: return VS.Color.textSecondary
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(vibe.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your driving")
                        .font(VS.Typography.body(10, weight: .bold))
                        .foregroundStyle(VS.Color.textTertiary)
                    Text(vibe.label)
                        .font(VS.Typography.heading(18, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(vibe.detail)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(toneColor.opacity(0.95))
                }
                Spacer(minLength: 0)
            }

            DriverStyleSpectrumBar(thirst: driverStyleScore)

            HStack {
                Label("Calm", systemImage: "leaf.fill")
                    .font(VS.Typography.body(9, weight: .bold))
                    .foregroundStyle(VS.Color.accent.opacity(0.85))
                Spacer(minLength: 0)
                Label("Spirited", systemImage: "bolt.fill")
                    .font(VS.Typography.body(9, weight: .bold))
                    .foregroundStyle(VS.Color.routeEnd.opacity(0.9))
            }
        }
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private var driverActivityVibe: (label: String, emoji: String, detail: String, tone: EfficiencyVibe.Tone) {
        let count = monthTrips.count
        let hours = monthRoadHours
        let hoursText = hours < 1
            ? (count == 0 ? "No drives yet this month" : "Under an hour on the road")
            : String(format: "%.0fh on the road this month", hours)

        if count == 0 {
            return ("Ready when you are", "👋", "Log a drive to see your style", .learning)
        }
        if count == 1 {
            return ("First miles in", "🛣️", hoursText, .good)
        }
        if count < 5 {
            return ("Easing into the month", "🧭", "\(count) drives · \(hoursText)", .neutral)
        }
        if count < 12 {
            return ("Building a rhythm", "🎯", "\(count) drives · \(hoursText)", .good)
        }
        if driverStyleScore >= 0.7 {
            return ("Spirited month", "⚡", "\(count) drives · higher top speeds", .watch)
        }
        return ("Road regular", "🏆", "\(count) drives · \(hoursText)", .excellent)
    }

    /// This month — your road time, not the car’s thirst.
    private var driverMonthSection: some View {
        let drivenDetail = monthTrips.isEmpty
            ? "No drives yet this month"
            : "\(monthTrips.count) drive\(monthTrips.count == 1 ? "" : "s") · \(monthRoadHours < 1 ? "<1h" : String(format: "%.0fh", monthRoadHours)) on road"
        let topSpeedText: String = {
            guard monthTopSpeedKmh > 0 else { return "—" }
            if unit == "mi" {
                return String(format: "%.0f", monthTopSpeedKmh * 0.621371)
            }
            return String(format: "%.0f", monthTopSpeedKmh)
        }()
        let topSpeedUnit = unit == "mi" ? "mph" : "km/h"
        let hoursValue = monthTrips.isEmpty
            ? "—"
            : (monthRoadHours < 1 ? "<1" : String(format: "%.0f", monthRoadHours))

        return VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "This month", subtitle: "Your time on the road")

            VStack(alignment: .leading, spacing: 6) {
                Text("Distance")
                    .font(VS.Typography.body(11, weight: .bold))
                    .foregroundStyle(VS.Color.textTertiary)
                Text(monthKm > 0 ? DistanceFormat.formatDistance(monthKm, unit: unit) : "—")
                    .font(VS.Typography.heading(44, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if let trend = monthKmTrend {
                    Text(trend)
                        .font(VS.Typography.body(12, weight: .semibold))
                        .foregroundStyle(trend.contains("↑") ? VS.Color.accent : VS.Color.textSecondary)
                } else {
                    Text(drivenDetail)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .padding(VS.Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(elevated: true)

            HStack(spacing: VS.Spacing.gutter) {
                DriverStatChip(
                    icon: .car,
                    value: monthTrips.isEmpty ? "—" : "\(monthTrips.count)",
                    label: "Drives",
                    detail: monthTrips.isEmpty ? "Track a trip" : drivenDetail
                )
                DriverStatChip(
                    icon: .roadHorizon,
                    value: hoursValue,
                    label: "Hours",
                    detail: monthTrips.isEmpty ? "No road time yet" : "Time behind the wheel"
                )
                DriverStatChip(
                    icon: .gauge,
                    value: topSpeedText,
                    label: "Top \(topSpeedUnit)",
                    detail: monthTopSpeedKmh > 0 ? "Peak this month" : "Needs a drive"
                )
            }
        }
    }

    private var topInsightSection: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "For you", subtitle: "One thing worth knowing")

            if let insight = funInsights.first {
                funInsightCard(insight)
                    .glassCard(elevated: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TrackyVoice.Soft.emptyInsightsTitle)
                        .font(VS.Typography.heading(16))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(TrackyVoice.Soft.emptyInsightsBody)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VS.Spacing.card)
                .glassCard(elevated: true)
            }
        }
    }

    private var badgesHubPreview: some View {
        DriverBadgesShelfSection(achievements: achievements) {
            showBadges = true
        } onSelectBadge: { badge in
            selectedBadge = badge
        }
    }

    private func funInsightCard(_ insight: FunInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insightKindLabel(insight.kind))
                .font(VS.Typography.body(11, weight: .medium))
                .foregroundStyle(insightTint(insight.kind))
            Text(insight.title)
                .font(VS.Typography.body(15, weight: .semibold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(insight.message)
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VS.Spacing.md)
        .padding(.vertical, 14)
    }

    private func insightKindLabel(_ kind: FunInsight.Kind) -> String {
        switch kind {
        case .celebrate: return "Nice"
        case .tip: return "Tip"
        case .watch: return "Watch"
        }
    }

    private func insightTint(_ kind: FunInsight.Kind) -> Color {
        switch kind {
        case .celebrate: return VS.Color.accent
        case .tip: return VS.Color.textSecondary
        case .watch: return VS.Color.warning
        }
    }
}

/// Full badge collection — achievements only. Tracky lives on the Driver tab.
struct DriverBadgesView: View {
    @Environment(\.dismiss) private var dismiss
    let achievements: [DriverAchievement]
    @State private var filter: BadgeFilter = .all
    @State private var selectedBadge: DriverAchievement?

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

    private var closestQuest: DriverAchievement? {
        achievements
            .filter { !$0.unlocked }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
                return lhs.title < rhs.title
            }
            .first
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
            VStack(alignment: .leading, spacing: VS.Spacing.floatStack) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Collection")
                        .font(VS.Typography.heading(28, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("\(unlockedCount) of \(achievements.count) unlocked")
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)
                }

                filterBar

                if case .all = filter, let quest = closestQuest {
                    featuredNext(quest)
                }

                if case .all = filter {
                    ForEach(sectioned, id: \.0) { category, items in
                        categoryBlock(category: category, items: items)
                    }
                } else if case .category(let category) = filter {
                    categoryBlock(category: category, items: filtered)
                }
            }
            .padding(.horizontal, VS.Spacing.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .veloseetePage()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    ModalBackButton(title: "Driver") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    ModalBackButton(title: "Driver") { dismiss() }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailDrawer(badge: badge)
                .presentationDetents([.medium, .large])
                .veloseeteSheet()
        }
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(filters, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { filter = option }
                } label: {
                    Text(option.title)
                        .font(VS.Typography.body(13, weight: filter == option ? .semibold : .medium))
                        .foregroundStyle(filter == option ? VS.Color.textPrimary : VS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(filter == option ? VS.Color.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(VS.Color.divider).frame(height: 1)
        }
    }

    private func featuredNext(_ quest: DriverAchievement) -> some View {
        Button {
            selectedBadge = quest
        } label: {
            HStack(spacing: 16) {
                BadgeHexMark(badge: quest, size: 84)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Closest")
                        .font(VS.Typography.body(11, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)
                    Text(quest.title)
                        .font(VS.Typography.heading(18, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(quest.detail)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(VS.Color.chip)
                            Rectangle()
                                .fill(VS.Color.accent.opacity(0.85))
                                .frame(width: max(2, geo.size.width * quest.progress))
                        }
                    }
                    .frame(height: 2)

                    Text(quest.progressLabel)
                        .font(VS.Typography.mono(12, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(VS.Spacing.card)
            .glassCard(elevated: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Closest badge, \(quest.title), \(quest.progressLabel)")
    }

    private func categoryBlock(category: DriverAchievement.Category, items: [DriverAchievement]) -> some View {
        let earned = items.filter(\.unlocked).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.label)
                    .font(VS.Typography.heading(17))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer()
                Text("\(earned)/\(items.count)")
                    .font(VS.Typography.mono(12, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            GeometryReader { geo in
                let progress = items.isEmpty ? 0 : Double(earned) / Double(items.count)
                ZStack(alignment: .leading) {
                    Rectangle().fill(VS.Color.chip)
                    Rectangle()
                        .fill(VS.Color.accent.opacity(0.7))
                        .frame(width: max(earned > 0 ? 3 : 0, geo.size.width * progress))
                }
            }
            .frame(height: 2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 18
            ) {
                ForEach(items) { badge in
                    hexCell(badge)
                }
            }
        }
    }

    private func hexCell(_ badge: DriverAchievement) -> some View {
        Button {
            selectedBadge = badge
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    BadgeHexMark(badge: badge, size: 86)
                    if !badge.unlocked, badge.progress > 0 {
                        Text("\(Int((badge.progress * 100).rounded()))%")
                            .font(VS.Typography.mono(9, weight: .bold))
                            .foregroundStyle(VS.Color.navPill)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VS.Color.accent, in: Capsule())
                            .offset(y: 6)
                    }
                }
                .padding(.bottom, badge.unlocked || badge.progress == 0 ? 0 : 4)

                Text(badge.title)
                    .font(VS.Typography.body(12, weight: .semibold))
                    .foregroundStyle(badge.unlocked ? VS.Color.textPrimary : VS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(badge.unlocked ? badge.detail : badge.progressLabel)
                    .font(VS.Typography.body(10))
                    .foregroundStyle(VS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            badge.unlocked
                ? "\(badge.title), unlocked. \(badge.detail)"
                : "\(badge.title), locked. \(badge.progressLabel)"
        )
    }
}

struct ServiceListView: View {
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var editingLog: ServiceLog?
    @State private var showEditor = false
    @State private var typeFilter: String?

    private var logs: [ServiceLog] {
        store.serviceLogs.filter { $0.vehicleId == store.currentVehicle?.id }.sorted { $0.timestamp > $1.timestamp }
    }

    private var filterTypes: [String] {
        let present = Set(logs.map(\.serviceType))
        let known = ServiceLog.knownTypes.filter { present.contains($0) }
        let extras = present.subtracting(ServiceLog.knownTypes).sorted()
        return known + extras
    }

    private var visibleLogs: [ServiceLog] {
        guard let typeFilter else { return logs }
        return logs.filter { $0.serviceType == typeFilter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VS.Spacing.floatStack) {
                MainTabHeader("Service", subtitle: store.currentVehicle?.nickname ?? TrackyVoice.Soft.serviceSubtitle, onProfile: onProfile)

                serviceTrendCard

                PrimaryCTAButton(title: TrackyVoice.Soft.logServiceCTA, icon: .wrench) {
                    editingLog = nil; showEditor = true
                }

                VSSection(title: "History") {
                    if logs.isEmpty {
                        Button { showEditor = true } label: {
                            VStack(spacing: 14) {
                                VSIcon(icon: .wrench, size: 34, weight: .regular, tint: VS.Color.accent)
                                Text(TrackyVoice.Soft.emptyServiceTitle)
                                    .font(VS.Typography.heading(16))
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text(TrackyVoice.Soft.emptyServiceBody)
                                    .font(VS.Typography.body(13))
                                    .foregroundStyle(VS.Color.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(VS.Spacing.card)
                            .glassCard(elevated: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                            historyFilterChips

                            if visibleLogs.isEmpty {
                                Text(TrackyVoice.Soft.emptyServiceFilter(typeFilter ?? TrackyVoice.Soft.serviceFilterAll))
                                    .font(VS.Typography.body(13))
                                    .foregroundStyle(VS.Color.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(VS.Spacing.card)
                                    .glassCard(elevated: true)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(visibleLogs) { log in
                                        Button {
                                            editingLog = log
                                            showEditor = true
                                        } label: {
                                            serviceRow(log)
                                        }
                                        .buttonStyle(.plain)

                                        if log.id != visibleLogs.last?.id {
                                            Divider().overlay(VS.Color.divider)
                                        }
                                    }
                                }
                                .padding(VS.Spacing.card)
                                .glassCard(elevated: true)
                            }
                        }
                    }
                }
            }.padding(.horizontal, VS.Spacing.pageInset).padding(.bottom, 110).tracksBottomNavScroll()
        }
        .veloseetePage()
        .sheet(isPresented: $showEditor) { ServiceEditorSheet(log: editingLog) }
        .onChange(of: store.currentVehicle?.id) { _, _ in
            typeFilter = nil
        }
        .onChange(of: filterTypes) { _, types in
            if let typeFilter, !types.contains(typeFilter) {
                self.typeFilter = nil
            }
        }
    }

    private var historyFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                VSSelectableChip(title: TrackyVoice.Soft.serviceFilterAll, selected: typeFilter == nil, compact: true) {
                    withAnimation(.snappy(duration: 0.22)) {
                        typeFilter = nil
                    }
                }
                ForEach(filterTypes, id: \.self) { type in
                    VSSelectableChip(title: type, selected: typeFilter == type, compact: true) {
                        withAnimation(.snappy(duration: 0.22)) {
                            typeFilter = typeFilter == type ? nil : type
                        }
                    }
                }
            }
        }
    }

    private var serviceTrendCard: some View {
        let latest = logs.first
        return VStack(alignment: .leading, spacing: 14) {
            Label("Service trend", systemImage: "chart.line.uptrend.xyaxis").font(VS.Typography.heading(17)).foregroundStyle(VS.Color.textPrimary)
            serviceFact("Current odometer", store.currentVehicle.map { DistanceFormat.formatOdometer($0.currentOdometer, unit: store.defaultDistanceUnit) } ?? "—")
            serviceFact("Last service", latest.map { "\($0.serviceType) · \($0.timestamp.formatted(date: .abbreviated, time: .omitted))" } ?? "No records yet")
            if let latest { serviceDueRow(latest) }
        }.padding(VS.Spacing.card).glassCard(elevated: true)
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
        let unit = store.defaultDistanceUnit
        let currentKm = store.currentVehicle.flatMap { store.odometerEstimate(vehicleId: $0.id)?.estimatedKm }
            ?? store.currentVehicle?.currentOdometer
        let kmSince: Int? = {
            guard let currentKm else { return nil }
            return max(0, Int((currentKm - log.odometerReading).rounded()))
        }()

        return HStack(alignment: .top, spacing: 12) {
            VSIcon(icon: .wrench, size: 18, weight: .regular, tint: VS.Color.accent)
                .frame(width: 36, height: 36)
                .background(VS.Color.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(log.serviceType)
                    .font(VS.Typography.heading(15))
                    .foregroundStyle(VS.Color.textPrimary)
                if let brand = log.brand, !brand.isEmpty {
                    Text(brand)
                        .font(VS.Typography.body(12, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                }
                Text("\(log.timestamp.formatted(date: .abbreviated, time: .omitted)) · \(DistanceFormat.formatOdometer(log.odometerReading, unit: unit))")
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.textTertiary)
                if let kmSince {
                    Text("\(DistanceFormat.formatDistance(Double(kmSince), unit: unit)) since this service")
                        .font(VS.Typography.body(11, weight: .medium))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                if let description = log.description {
                    Text(description)
                        .font(VS.Typography.body(11))
                        .foregroundStyle(VS.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let cost = log.cost {
                Text(CurrencyFormat.format(cost, currency: log.currency))
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct ServiceEditorSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let log: ServiceLog?

    @State private var serviceType = "Oil Change"
    @State private var customType = ""
    @State private var tireBrand = "Michelin"
    @State private var customTireBrand = ""
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

    private let types = ServiceLog.knownTypes

    private var vehicle: Vehicle? { store.currentVehicle }
    private var currencyCode: String { vehicle?.currency ?? "QAR" }
    private var isNewTires: Bool { serviceType == "New Tires" }
    private var isOtherType: Bool { serviceType == "Other" }

    private var finalType: String {
        isOtherType
            ? customType.trimmingCharacters(in: .whitespacesAndNewlines)
            : serviceType
    }

    private var finalBrand: String? {
        guard isNewTires else { return nil }
        if tireBrand == "Other" {
            let custom = customTireBrand.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? nil : custom
        }
        return tireBrand
    }

    private var canSave: Bool {
        guard !finalType.isEmpty, (Double(odometer) ?? 0) > 0 else { return false }
        if isNewTires { return finalBrand != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    typeSection

                    if isNewTires {
                        tireBrandSection
                    }

                    HStack(spacing: 12) {
                        numberField(
                            label: "Odometer at service",
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

                    Text("Saved on this service only — won’t change your car’s current odometer.")
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textTertiary)

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
                        .glassCard(elevated: true)

                        Text("Backdate anytime — past tire/service work is fine.")
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Notes")
                        TextField("What was done?", text: $notes, axis: .vertical)
                            .lineLimit(3...5)
                            .font(VS.Typography.body(15))
                            .foregroundStyle(VS.Color.textPrimary)
                            .padding(14)
                            .glassCard(elevated: true)
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
                        .glassCard(elevated: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle(log == nil ? TrackyVoice.Soft.logServiceNav : TrackyVoice.Soft.editServiceNav)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryCTAButton(
                    title: log == nil ? TrackyVoice.Soft.saveService : TrackyVoice.Calm.saveFillChanges,
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
                Text(TrackyVoice.Calm.deleteServiceMessage)
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

            if isOtherType {
                TextField("Custom type", text: $customType)
                    .font(VS.Typography.heading(18, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .padding(14)
                    .glassCard(elevated: true)
            }
        }
    }

    private var tireBrandSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(TireBrandCatalog.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel(section.title)
                    FlowChipWrap(items: section.brands, selected: tireBrand) { brand in
                        UISelectionFeedbackGenerator().selectionChanged()
                        tireBrand = brand
                    }
                }
            }

            if tireBrand == "Other" {
                TextField("Custom tire brand", text: $customTireBrand)
                    .font(VS.Typography.heading(18, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .padding(14)
                    .glassCard(elevated: true)
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
                .glassCard(elevated: true)

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
                .glassCard(elevated: true)
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
            .glassCard(elevated: true)
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
        if serviceType == "New Tires" {
            let known = TireBrandCatalog.allBrands
            if let brand = log.brand, known.contains(brand) {
                tireBrand = brand
            } else if let brand = log.brand, !brand.isEmpty {
                tireBrand = "Other"
                customTireBrand = brand
            }
        }
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
                brand: finalBrand,
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

// MARK: - Tire brands + chip wrap

private enum TireBrandCatalog {
    struct Section {
        var title: String
        var brands: [String]
    }

    static let sections: [Section] = [
        Section(
            title: "Popular",
            brands: [
                "Michelin", "Bridgestone", "Goodyear", "Continental", "Pirelli",
                "Dunlop", "Hankook", "Yokohama", "Toyo", "Falken",
                "Kumho", "Nexen", "Maxxis", "BFGoodrich", "Cooper", "Firestone"
            ]
        ),
        Section(
            title: "Thai & SE Asia",
            brands: ["Deestone", "Otani", "Leopold", "General Tire"]
        ),
        Section(
            title: "Chinese",
            brands: [
                "Triangle", "Linglong", "Sailun", "Giti", "Double Coin", "Wanli",
                "Goodride", "Westlake", "Chaoyang", "Prinx", "Sentury", "Aeolus",
                "Landsail", "Infinity", "Sunny"
            ]
        ),
        Section(
            title: "India & others",
            brands: ["MRF", "Apollo", "CEAT", "JK Tyre", "Other"]
        )
    ]

    static var allBrands: [String] {
        sections.flatMap(\.brands).filter { $0 != "Other" }
    }
}

/// Simple wrapping chip row without a third-party flow layout.
private struct FlowChipWrap: View {
    let items: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        let isOn = selected == item
                        Button {
                            onSelect(item)
                        } label: {
                            Text(item)
                                .font(VS.Typography.body(12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(isOn ? VS.Color.accent : VS.Color.chip))
                                .foregroundStyle(isOn ? VS.Color.navPill : VS.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Rough wrap by character budget so chips don’t overflow on small phones.
    private var rows: [[String]] {
        var result: [[String]] = [[]]
        var lineWidth = 0
        let budget = 34
        for item in items {
            let cost = item.count + 4
            if lineWidth + cost > budget, !result[result.count - 1].isEmpty {
                result.append([item])
                lineWidth = cost
            } else {
                result[result.count - 1].append(item)
                lineWidth += cost
            }
        }
        return result
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
    @State private var showFeedback = false
    @State private var showRoadmap = false

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
                                Text(TrackyVoice.Calm.managePermissions).foregroundStyle(VS.Color.textPrimary)
                                Text(TrackyVoice.Calm.managePermissionsDetail)
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
                                Text(TrackyVoice.Calm.replayOnboarding).foregroundStyle(VS.Color.textPrimary)
                                Text(TrackyVoice.Calm.replayOnboardingDetail)
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .roadHorizon, size: 20, weight: .regular, tint: VS.Color.accent)
                        }
                    }
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section("Veloseete") {
                    Button {
                        showFeedback = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(TrackyVoice.Calm.leaveFeedback).foregroundStyle(VS.Color.textPrimary)
                                Text(TrackyVoice.Calm.leaveFeedbackDetail)
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .fileText, size: 20, weight: .regular, tint: VS.Color.accent)
                        }
                    }

                    Button {
                        showRoadmap = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(TrackyVoice.Calm.roadmap).foregroundStyle(VS.Color.textPrimary)
                                Text(TrackyVoice.Calm.roadmapDetail)
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .chartLine, size: 20, weight: .regular, tint: VS.Color.accent)
                        }
                    }
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section("Legal") {
                    Button("Privacy Policy") { legalDocument = .privacy }
                    Button("Terms of Use") { legalDocument = .terms }
                    Link("Contact support", destination: AppLegal.supportMailtoURL)
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    Button(TrackyVoice.Calm.signOut, role: .destructive) {
                        try? auth.signOut()
                    }
                    Button(role: .destructive) {
                        showDeleteAccountConfirm = true
                    } label: {
                        if isDeletingAccount {
                            ProgressView()
                                .tint(VS.Color.error)
                        } else {
                            Text(TrackyVoice.Calm.deleteAccount)
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
            .sheet(isPresented: $showFeedback) {
                FeedbackComposerView()
            }
            .sheet(isPresented: $showRoadmap) {
                RoadmapView()
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
            .alert(TrackyVoice.Calm.deleteAccountTitle, isPresented: $showDeleteAccountConfirm) {
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
                            .clipShape(RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous))
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
                        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous))

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
                            .glassCard(elevated: true)
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
    /// Keep garage heroes sharp on Pro Max (~3x · ~360pt stage needs ~1080px+).
    private let maxDimension: CGFloat = 1600

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
        guard let jpeg = normalized.jpegData(compressionQuality: 0.9) else {
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

    /// Clears in-memory photos on sign-out without deleting on-disk files
    /// (vehicle ids are unique; returning users keep their local photos).
    func clearSession() {
        images.removeAll()
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
    private var boundUserId: String?
    private let fileManager = FileManager.default
    private let maxDimension: CGFloat = 800

    private init() {}

    func load(userId: String?) {
        // Never wipe the on-screen avatar mid change/crop.
        guard !isReplacing else { return }

        boundUserId = userId
        guard let userId else {
            image = nil
            replacementBackup = nil
            return
        }

        let url = fileURL(for: userId)
        guard fileManager.fileExists(atPath: url.path) else {
            // Account changed or first launch — don't keep another user's photo.
            image = nil
            return
        }

        // Decode via Data so the bitmap is not purgeable under memory pressure.
        guard let data = try? Data(contentsOf: url),
              let loaded = UIImage(data: data)?.stableCopy() else {
            print("[Avatar] Could not decode avatar for \(userId.prefix(6))…")
            return
        }
        image = loaded
    }

    /// Re-read from disk when the UI avatar is missing but a file should exist
    /// (memory pressure, sign-in race, or returning from background).
    func reloadIfNeeded(userId: String?) {
        guard !isReplacing else { return }
        guard let userId, !userId.isEmpty else { return }
        if image != nil, boundUserId == userId { return }
        load(userId: userId)
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
        let directory = avatarDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        let url = fileURL(for: userId)
        try jpeg.write(to: url, options: .atomic)
        boundUserId = userId
        self.image = normalized
    }

    func remove(userId: String) throws {
        let url = fileURL(for: userId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        if boundUserId == userId {
            boundUserId = nil
        }
        image = nil
        replacementBackup = nil
        isReplacing = false
    }

    /// Clears the on-screen avatar for the signed-out session; disk files stay per uid.
    func clearSession() {
        boundUserId = nil
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

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
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
