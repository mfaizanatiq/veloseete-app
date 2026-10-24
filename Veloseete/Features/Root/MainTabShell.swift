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
    @Environment(\.windowSize) private var windowSize

    private var isWide: Bool { VS.Layout.isWide(windowSize) }

    var body: some View {
        ZStack(alignment: isWide ? .bottomTrailing : .bottom) {
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
            // Trips is a full-bleed map; every other tab is a centred column.
            .tabContentWidth(fullBleed: tab == .trips, twoColumn: isWide && tab != .details)
            // Wide mode: the rail lives in the status strip, so pages only add the
            // usual gutter on each side.
            .padding(.horizontal, isWide && tab != .trips ? VS.Spacing.frameGutter : 0)
            .coordinateSpace(name: "bottomNavScroll")

            if isWide {
                NavRailLayer(active: $tab)
            } else {
                BottomNavBar(active: $tab)
            }
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
                    .font(VS.TextStyle.title())
                    .foregroundStyle(VS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(VS.TextStyle.callout())
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
    /// 13 leaves the pill 21 pt off the bottom on Face ID iPhones — where iOS's
    /// own floating tab bar sits.
    private var homeIndicatorDip: CGFloat { isCompact ? 9 : 13 }

    var body: some View {
        // Narrow screens (iPhone Duo outer, SE) drop the active label rather than
        // truncate it to "Ser…" — the lime bubble still marks the tab.
        ViewThatFits(in: .horizontal) {
            bar(showsLabel: true)
            bar(showsLabel: false)
        }
        .padding(.horizontal, horizontalInset)
        // Parent shell always ignores the bottom safe area, so pad from the
        // physical bottom using the window inset — identical on Drives + others.
        .padding(.bottom, max(Self.homeIndicatorInset - homeIndicatorDip, 6))
    }

    private func bar(showsLabel: Bool) -> some View {
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

                        if active == item && !isCompact && showsLabel {
                            Text(item.label)
                                .font(VS.TextStyle.subheadline(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(.horizontal, active == item && !isCompact && showsLabel ? 10 : (isCompact ? 4 : 6))
                    .frame(minHeight: itemMinHeight)
                    .background(
                        Capsule().fill(active == item ? selectedPill : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(active == item ? .isSelected : [])

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

/// Wide-mode navigation (iPhone Duo unfolded). Sits where iOS puts its own tab bar
/// on this screen: a slim vertical pill in the right-hand status strip, pinned to
/// the bottom. Same Veloseete pill and lime bubbles as `BottomNavBar`.
struct NavRail: View {
    @Binding var active: AppTab

    var body: some View {
        VStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        active = item
                    }
                } label: {
                    NavIconBubble(
                        icon: item.icon,
                        isActive: active == item,
                        iconSize: 18,
                        circleSize: 36,
                        activeTint: VS.Color.navPill
                    )
                    // 44 pt keeps Apple's minimum tap target.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(active == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(VS.Color.navPill)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
    }

    static let width: CGFloat = 52
    /// 5 × 44 pt targets + 4 × 4 pt gaps + 2 × 4 pt padding.
    static var height: CGFloat { CGFloat(AppTab.allCases.count) * 44 + CGFloat(AppTab.allCases.count - 1) * 4 + 8 }
}

/// Places the rail in full-window coordinates — centred in the right-hand status
/// strip, pinned to the bottom — with `.position`, so the touch targets sit exactly
/// where the rail is drawn. (Pushing it into the strip with a safe-area override
/// drew it in one place and hit-tested it in another on the Duo's inner screen.)
struct NavRailLayer: View {
    @Binding var active: AppTab

    var body: some View {
        GeometryReader { proxy in
            // Inside an ignoresSafeArea reader the proxy reports zero insets, so read
            // the window's: right = the status strip, bottom = home-indicator zone.
            let insets = Self.windowInsets
            let full = proxy.size
            let trailingGap = max(6, (insets.right - NavRail.width) / 2)
            // Same lift iOS gives its own tab bar here (~28 pt off the bottom edge).
            let bottomGap = max(insets.bottom, 28)
            NavRail(active: $active)
                .position(
                    x: full.width - trailingGap - NavRail.width / 2,
                    y: full.height - bottomGap - NavRail.height / 2
                )
        }
        .ignoresSafeArea()
    }

    private static var windowInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
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
                .font(VS.TextStyle.title2(.semibold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(subtitle)
                .font(VS.TextStyle.callout())
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
                .font(VS.TextStyle.caption())
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
                .font(VS.TextStyle.title())
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(VS.TextStyle.caption(.medium))
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
                .font(VS.TextStyle.largeTitle())
                .foregroundStyle(VS.Color.textPrimary)
            Text(label)
                .font(VS.TextStyle.caption(.medium))
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
                            .font(VS.TextStyle.footnote())
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
                                    .font(VS.TextStyle.headline(.semibold))
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
                                .font(VS.TextStyle.callout(.semibold))
                                .foregroundStyle(VS.Color.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || isSettingActive)
                    } else if store.vehicles.count > 1 {
                        Text("Set another car active before archiving this one.")
                            .font(VS.TextStyle.caption())
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
                            .font(VS.TextStyle.callout(.semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                    .disabled(isPreparingCrop)

                    if usePhoto, previewImage != nil {
                        Button("Use car mark instead") {
                            usePhoto = false
                            removeExistingPhoto = true
                            draftPhoto = nil
                        }
                        .font(VS.TextStyle.footnote(.medium))
                        .foregroundStyle(VS.Color.textSecondary)
                    }

                    if isPreparingCrop {
                        ProgressView("Opening photo…")
                            .font(VS.TextStyle.caption())
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
            .font(VS.TextStyle.footnote(.medium))
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
                .font(large ? VS.TextStyle.title2(.semibold) : VS.TextStyle.title2(.semibold))
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
                    .font(large ? VS.TextStyle.largeTitle() : VS.TextStyle.title2(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(suffix)
                    .font(VS.TextStyle.body(.medium))
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

/// Cheap change detection for the driver snapshot (array buffers compare by identity first).
struct DriverSnapshotInputs: Equatable {
    var trips: [Trip]
    var vehicles: [Vehicle]
    var fuelLogs: [FuelLog]
    var unit: String
}

struct DriverProfileView: View {
    @Environment(\.isWideLayout) private var isWideLayout
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var showBadges = false
    @State private var selectedBadge: DriverAchievement?
    @State private var snapshot = DriverProfileSnapshot()
    @State private var recordTrip: Trip?

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
        let drives = snapshot.lifetimeDrives
        let road = DistanceFormat.formatOdometer(totalKm, unit: unit)
        if drives == 0 { return "\(road) all-time · start a drive" }
        // Lifetime totals live here once, so the driver card can stay about identity.
        let wheel = DriverProfileFormat.hours(snapshot.lifetimeSeconds)
        return "\(drives) drive\(drives == 1 ? "" : "s") · \(road) · \(wheel)"
    }

    private var snapshotInputs: DriverSnapshotInputs {
        DriverSnapshotInputs(trips: store.trips, vehicles: store.vehicles, fuelLogs: store.fuelLogs, unit: unit)
    }

    private func rebuildSnapshot() {
        snapshot = DriverProfileSnapshot.build(trips: store.tripsForActiveVehicles, lifetimeKm: totalKm, unit: unit)
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
                                .font(VS.TextStyle.label())
                                .foregroundStyle(VS.Color.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(VS.Color.chip, in: Capsule())
                                .overlay(Capsule().strokeBorder(VS.Color.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(unlockedCount) of \(achievements.count) badges")
                    }

                    // Phone: one column. Wide (Duo unfolded): who you are left, the numbers right.
                    AdaptiveColumns(leadingTitle: "Your style", leadingSubtitle: "Read from every drive so far") {
                    DriverIdentityCard(snapshot: snapshot, displayName: displayName, unit: unit) {
                        shareDriverCard()
                    }

                    VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                        VSSectionHeader(title: "Rhythm", subtitle: "Every drive, last \(DriverProfileSnapshot.heatmapWeeks) weeks")
                        DriverRhythmCard(snapshot: snapshot)
                    }

                    topInsightSection
                    } trailing: {

                    VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                        VSSectionHeader(title: "Last 30 days", subtitle: "Rolling, so it never resets on the 1st")
                        DriverLast30Card(snapshot: snapshot, unit: unit)
                    }

                    if !snapshot.records.isEmpty {
                        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                            VSSectionHeader(title: "Personal records", subtitle: "Tap one to relive the drive")
                            DriverRecordsRow(records: snapshot.records) { record in
                                guard let id = record.tripId else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                recordTrip = store.trips.first { $0.id == id }
                            }
                        }
                    }

                    if snapshot.peakHour != nil {
                        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                            VSSectionHeader(title: "Your hours", subtitle: "When you usually drive")
                            DriverHoursCard(hourCounts: snapshot.hourCounts, peakHour: snapshot.peakHour)
                        }
                    }

                    badgesHubPreview
                    }
                }
                .padding(.horizontal, VS.Spacing.pageInset)
                .padding(.bottom, 110)
                .tracksBottomNavScroll()
            }
            // Inside the stack, so UIKit's re-applied side safe area is ignored here.
            .wideTabSafeArea(isWideLayout)
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
            .sheet(item: $recordTrip) { trip in
                TripDetailView(trip: trip, unit: unit)
                    .veloseeteSheet(allowsWide: true)
            }
            .onAppear(perform: rebuildSnapshot)
            .onChange(of: snapshotInputs) { _, _ in rebuildSnapshot() }
        }
    }

    /// Renders the driver card as a standalone image — the thing people post.
    @MainActor
    private func shareDriverCard() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let card = DriverIdentityCard(snapshot: snapshot, displayName: displayName, unit: unit)
            .frame(width: 360)
            .padding(20)
            .background(VS.Color.bgPrimary)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage,
              let root = UIApplication.shared.veloseeteTopViewController else { return }
        // Present UIKit's share sheet directly; wrapped in a SwiftUI sheet it renders blank.
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = root.view
        root.present(controller, animated: true)
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
                        .font(VS.TextStyle.headline(.semibold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(TrackyVoice.Soft.emptyInsightsBody)
                        .font(VS.TextStyle.footnote())
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
                .font(VS.TextStyle.caption2(.medium))
                .foregroundStyle(insightTint(insight.kind))
            Text(insight.title)
                .font(VS.TextStyle.body(.semibold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(insight.message)
                .font(VS.TextStyle.footnote())
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
                        .font(VS.TextStyle.title())
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("\(unlockedCount) of \(achievements.count) unlocked")
                        .font(VS.TextStyle.callout())
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
                        .font(VS.TextStyle.footnote(filter == option ? .semibold : .medium))
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
                        .font(VS.TextStyle.caption2(.medium))
                        .foregroundStyle(VS.Color.textTertiary)
                    Text(quest.title)
                        .font(VS.TextStyle.title3())
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(quest.detail)
                        .font(VS.TextStyle.footnote())
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
                        .font(VS.TextStyle.labelLarge(.medium))
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
                    .font(VS.TextStyle.title3(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer()
                Text("\(earned)/\(items.count)")
                    .font(VS.TextStyle.labelLarge(.medium))
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
                            .font(VS.TextStyle.label())
                            .foregroundStyle(VS.Color.navPill)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VS.Color.accent, in: Capsule())
                            .offset(y: 6)
                    }
                }
                .padding(.bottom, badge.unlocked || badge.progress == 0 ? 0 : 4)

                Text(badge.title)
                    .font(VS.TextStyle.caption(.semibold))
                    .foregroundStyle(badge.unlocked ? VS.Color.textPrimary : VS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(badge.unlocked ? badge.detail : badge.progressLabel)
                    .font(VS.TextStyle.caption2())
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

    private var vehicle: Vehicle? { store.currentVehicle }

    private var logs: [ServiceLog] {
        store.serviceLogs.filter { $0.vehicleId == vehicle?.id }.sorted { $0.timestamp > $1.timestamp }
    }

    /// Live dash estimate — the same number the Trips tab shows.
    private var currentKm: Double {
        vehicle.flatMap { store.odometerEstimate(vehicleId: $0.id)?.estimatedKm } ?? vehicle?.currentOdometer ?? 0
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

    private var currency: String { vehicle?.currency ?? "QAR" }

    private func spent(since start: Date?) -> Double {
        logs
            .filter { log in log.currency == currency && (start.map { log.timestamp >= $0 } ?? true) }
            .reduce(0) { $0 + ($1.cost ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VS.Spacing.floatStack) {
                MainTabHeader(
                    "Service",
                    subtitle: vehicle.map { "\($0.nickname) · care & costs" } ?? TrackyVoice.Soft.serviceSubtitle,
                    onProfile: onProfile
                )

                summaryChip

                // Phone: one column. Wide (Duo unfolded): next-up + actions left, history right.
                AdaptiveColumns(leadingTitle: "Next up") {
                if vehicle != nil {
                    ServiceHeroCard(
                        logs: logs,
                        currentKm: currentKm,
                        unit: store.defaultDistanceUnit
                    )
                }

                PrimaryCTAButton(title: TrackyVoice.Soft.logServiceCTA, icon: .wrench) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    editingLog = nil
                    showEditor = true
                }

                if !logs.isEmpty {
                    HStack(spacing: VS.Spacing.gutter) {
                        BentoStatTile(
                            value: CurrencyFormat.format(spent(since: Calendar.current.dateInterval(of: .year, for: Date())?.start), currency: currency),
                            label: "Spent this year",
                            icon: .wrench
                        )
                        BentoStatTile(
                            value: logs.first.map {
                                DistanceFormat.formatOdometer(max(0, currentKm - $0.odometerReading), unit: store.defaultDistanceUnit)
                            } ?? "—",
                            label: "Since last service",
                            icon: .roadHorizon
                        )
                    }
                }

                } trailing: {
                    historySection
                }
            }
            .padding(.horizontal, VS.Spacing.pageInset)
            .padding(.bottom, 110)
            .tracksBottomNavScroll()
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

    private var summaryChip: some View {
        HStack(spacing: 8) {
            VSIcon(icon: .wrench, size: 12, weight: .bold, tint: VS.Color.textTertiary)
            Text(logs.isEmpty
                 ? "No services logged yet"
                 : "\(logs.count) service\(logs.count == 1 ? "" : "s") · \(CurrencyFormat.format(spent(since: nil), currency: currency)) all time")
                .font(VS.TextStyle.caption2(.medium))
            Spacer()
            Text(DistanceFormat.formatOdometer(currentKm, unit: store.defaultDistanceUnit))
                .font(VS.TextStyle.caption2(.semibold))
        }
        .foregroundStyle(VS.Color.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(elevated: true)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "History")

            if logs.isEmpty {
                Button { showEditor = true } label: {
                    VStack(spacing: 14) {
                        FluentEmojiView(emoji: "🔧", size: 48)
                        Text(TrackyVoice.Soft.emptyServiceTitle)
                            .font(VS.TextStyle.headline(.semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(TrackyVoice.Soft.emptyServiceBody)
                            .font(VS.TextStyle.footnote())
                            .foregroundStyle(VS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(VS.Spacing.card)
                    .glassCard(elevated: true)
                }
                .buttonStyle(.plain)
            } else {
                if filterTypes.count > 1 {
                    historyFilterChips
                }

                if visibleLogs.isEmpty {
                    Text(TrackyVoice.Soft.emptyServiceFilter(typeFilter ?? TrackyVoice.Soft.serviceFilterAll))
                        .font(VS.TextStyle.footnote())
                        .foregroundStyle(VS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(VS.Spacing.card)
                        .glassCard(elevated: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleLogs) { log in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                editingLog = log
                                showEditor = true
                            } label: {
                                HStack(spacing: 10) {
                                    serviceRow(log)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(VS.Color.textTertiary)
                                }
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

    /// Same rhythm as a fill row: what, when · where on the dash, detail line, cost.
    private func serviceRow(_ log: ServiceLog) -> some View {
        let unit = store.defaultDistanceUnit
        let detail = [log.brand, log.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.serviceType)
                    .font(VS.TextStyle.subheadline(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text("\(log.timestamp.formatted(date: .abbreviated, time: .omitted)) · \(DistanceFormat.formatOdometer(log.odometerReading, unit: unit))")
                    .font(VS.TextStyle.caption())
                    .foregroundStyle(VS.Color.textTertiary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(VS.TextStyle.caption2(.medium))
                        .foregroundStyle(VS.Color.accentSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let cost = log.cost {
                Text(CurrencyFormat.format(cost, currency: log.currency))
                    .font(VS.TextStyle.headline(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Lime hero for the Service tab — what's due next, in one number, like the Fuels hero.
struct ServiceHeroCard: View {
    let logs: [ServiceLog]
    let currentKm: Double
    let unit: String

    private var nextUp: ServiceSchedule.NextUp? {
        ServiceSchedule.nextUp(logs: logs, currentKm: currentKm)
    }

    private var statusLabel: String {
        guard let nextUp else { return logs.isEmpty ? "Start a log" : "No reminder" }
        switch nextUp.status {
        case .onTrack: return "On track"
        case .dueSoon: return "Due soon"
        case .overdue: return "Overdue"
        }
    }

    /// Big number + its unit, and the sentence under it.
    private var headline: (value: String, unit: String, caption: String) {
        if let nextUp {
            let type = nextUp.log.serviceType
            if let kmLeft = nextUp.kmLeft {
                let shown = unit == "mi" ? abs(kmLeft) * 0.621371 : abs(kmLeft)
                let unitLabel = unit == "mi" ? "mi" : "km"
                return kmLeft >= 0
                    ? (shown.formatted(.number.precision(.fractionLength(0))), "\(unitLabel) left", "until \(type)")
                    : (shown.formatted(.number.precision(.fractionLength(0))), "\(unitLabel) over", "\(type) is overdue")
            }
            let days = nextUp.daysLeft ?? 0
            return days >= 0
                ? ("\(days)", days == 1 ? "day left" : "days left", "until \(type)")
                : ("\(-days)", -days == 1 ? "day over" : "days over", "\(type) is overdue")
        }
        if let latest = logs.first {
            let since = max(0, currentKm - latest.odometerReading)
            let shown = unit == "mi" ? since * 0.621371 : since
            return (shown.formatted(.number.precision(.fractionLength(0))), unit == "mi" ? "mi" : "km", "since \(latest.serviceType) · add a reminder to track it")
        }
        return ("—", "", TrackyVoice.Soft.emptyServiceBody)
    }

    var body: some View {
        let head = headline
        // Compact on purpose: the header already names the car and History lists the
        // last service, so the card only answers "what's next, and how close is it".
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(nextUp == nil ? "SERVICE" : "NEXT UP")
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.navPill.opacity(0.6))
                Spacer(minLength: 12)
                Text(statusLabel)
                    .font(VS.TextStyle.caption(.semibold))
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(nextUp?.status == .overdue ? VS.Color.navPill.opacity(0.12) : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(VS.Color.navPill.opacity(0.35), lineWidth: 1.5))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(head.value)
                        .font(VS.TextStyle.display())
                        .foregroundStyle(VS.Color.navPill)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(head.unit)
                        .font(VS.TextStyle.title3())
                        .foregroundStyle(VS.Color.navPill.opacity(0.65))
                }
                Text(head.caption)
                    .font(VS.TextStyle.callout(.medium))
                    .foregroundStyle(VS.Color.navPill.opacity(0.75))
            }
            .accessibilityElement(children: .combine)

            if let nextUp {
                progressBar(nextUp)
            }
        }
        .padding(VS.Spacing.card)
        .background(
            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                .fill(VS.Color.accent)
        )
        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
    }

    /// Last service → reminder, filled by how far along the car is.
    private func progressBar(_ nextUp: ServiceSchedule.NextUp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(VS.Color.navPill.opacity(0.18))
                    Capsule()
                        .fill(VS.Color.navPill.opacity(nextUp.status == .onTrack ? 0.55 : 0.9))
                        .frame(width: max(10, geo.size.width * nextUp.progress))
                }
            }
            .frame(height: 10)

            HStack {
                Text("Last \(DistanceFormat.formatOdometer(nextUp.log.odometerReading, unit: unit))")
                    .font(VS.TextStyle.caption2(.semibold))
                    .foregroundStyle(VS.Color.navPill)
                Spacer()
                Text(dueLabel(nextUp))
                    .font(VS.TextStyle.caption2(.medium))
                    .foregroundStyle(VS.Color.navPill.opacity(0.55))
            }
        }
    }

    private func dueLabel(_ nextUp: ServiceSchedule.NextUp) -> String {
        if let next = nextUp.log.nextServiceOdometer {
            return "Due \(DistanceFormat.formatOdometer(next, unit: unit))"
        }
        if let date = nextUp.log.nextServiceDate {
            return "Due \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return ""
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
    /// Last reminder we prefilled; once the driver edits it, we stop overwriting.
    @State private var suggestedOdometer: String?
    @State private var suggestedDate: Date?
    @State private var showTypePicker = false

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
                        .font(VS.TextStyle.caption())
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
                            .font(VS.TextStyle.caption())
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Notes")
                        TextField("What was done?", text: $notes, axis: .vertical)
                            .lineLimit(3...5)
                            .font(VS.TextStyle.body())
                            .foregroundStyle(VS.Color.textPrimary)
                            .padding(14)
                            .glassCard(elevated: true)
                    }

                    reminderSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.TextStyle.footnote())
                            .foregroundStyle(VS.Color.error)
                    }

                    if log != nil {
                        Button("Delete service entry", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .font(VS.TextStyle.callout(.semibold))
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
            .onAppear {
                populate()
                applySuggestedReminder()
            }
            .onChange(of: serviceType) { _, _ in applySuggestedReminder() }
            .onChange(of: odometer) { _, _ in applySuggestedReminder() }
            .onChange(of: serviceDate) { _, _ in applySuggestedReminder() }
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
            // One row, one decision — the full list lives in a searchable sheet.
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showTypePicker = true
            } label: {
                HStack(spacing: 12) {
                    ServiceTypeIcon(type: serviceType, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(serviceType)
                            .font(VS.TextStyle.headline())
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(ServiceSchedule.intervalSummary(for: serviceType) ?? "Name it below")
                            .font(VS.TextStyle.caption())
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Text("Change")
                        .font(VS.TextStyle.footnote(.semibold))
                        .foregroundStyle(VS.Color.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                .padding(14)
                .glassCard(elevated: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Service type, \(serviceType)")
            .accessibilityHint("Opens the list of service types")
            .sheet(isPresented: $showTypePicker) {
                ServiceTypePickerSheet(
                    selected: serviceType,
                    recent: recentTypes
                ) { type in
                    serviceType = type
                }
            }

            if isOtherType {
                TextField("Custom type", text: $customType)
                    .font(VS.TextStyle.title3(.semibold))
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
                    .font(VS.TextStyle.title3(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .padding(14)
                    .glassCard(elevated: true)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("Next reminder")
            if let hint = intervalHint {
                Text(hint)
                    .font(VS.TextStyle.caption())
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            numberField(
                label: "Next odometer",
                placeholder: "Optional",
                text: $nextOdometer,
                suffix: "km"
            )

            Toggle("Due date", isOn: $hasNextDate)
                .font(VS.TextStyle.headline(.semibold))
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

    private var intervalHint: String? {
        guard let summary = ServiceSchedule.intervalSummary(for: serviceType) else { return nil }
        return "Typical for \(serviceType.lowercased()): \(summary.lowercased()). Your manual wins."
    }

    /// This car's last few distinct service types, newest first.
    private var recentTypes: [String] {
        var seen = Set<String>()
        return store.serviceLogs
            .filter { $0.vehicleId == vehicle?.id && types.contains($0.serviceType) }
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.serviceType)
            .filter { seen.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }

    /// Prefill the next reminder from the type's usual interval — new entries only,
    /// and never over a value the driver typed themselves.
    private func applySuggestedReminder() {
        guard log == nil else { return }
        let interval = ServiceSchedule.suggestedInterval(for: serviceType)

        let odometerIsOurs = nextOdometer.isEmpty || nextOdometer == suggestedOdometer
        if odometerIsOurs {
            if let km = interval?.km, let odo = Double(odometer), odo > 0 {
                let value = String(format: "%.0f", odo + km)
                nextOdometer = value
                suggestedOdometer = value
            } else {
                nextOdometer = ""
                suggestedOdometer = nil
            }
        }

        let dateIsOurs = !hasNextDate || nextDate == suggestedDate
        if dateIsOurs {
            if let months = interval?.months,
               let due = Calendar.current.date(byAdding: .month, value: months, to: serviceDate) {
                hasNextDate = true
                nextDate = due
                suggestedDate = due
            } else {
                hasNextDate = false
                suggestedDate = nil
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
                    .font(VS.TextStyle.title2(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(suffix)
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(14)
            .glassCard(elevated: true)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.TextStyle.caption(.medium))
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

// MARK: - Service type picker

/// Grouped, searchable list — replaces a wall of pills with rows you can scan.
struct ServiceTypePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selected: String
    let recent: [String]
    let onPick: (String) -> Void
    @State private var query = ""

    private var sections: [(title: String, types: [String])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            let hits = ServiceLog.knownTypes.filter { $0.localizedCaseInsensitiveContains(trimmed) }
            return hits.isEmpty ? [("No match — pick Other to name it", ["Other"])] : [("Results", hits)]
        }
        let recentSection: [(title: String, types: [String])] = recent.isEmpty ? [] : [("Recent on this car", recent)]
        return recentSection + ServiceSchedule.groups
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title.uppercased())
                                .font(VS.TextStyle.label())
                                .foregroundStyle(VS.Color.textTertiary)
                                .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(section.types, id: \.self) { type in
                                    row(type)
                                    if type != section.types.last {
                                        Divider().overlay(VS.Color.divider).padding(.leading, 66)
                                    }
                                }
                            }
                            .glassCard(elevated: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search services")
            .navigationTitle("Service type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private func row(_ type: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onPick(type)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ServiceTypeIcon(type: type, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type == "Other" ? "Other (name it)" : type)
                        .font(VS.TextStyle.subheadline(.semibold))
                        .foregroundStyle(VS.Color.textPrimary)
                    if let summary = ServiceSchedule.intervalSummary(for: type) {
                        Text(summary)
                            .font(VS.TextStyle.caption())
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                if type == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(VS.Color.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(type == selected ? .isSelected : [])
    }
}

/// Round tinted glyph per service type, so rows scan by shape, not just words.
struct ServiceTypeIcon: View {
    let type: String
    var size: CGFloat = 38

    private var symbol: String {
        switch type {
        case "Oil Change": "drop.fill"
        case "Tire Rotation": "arrow.triangle.2.circlepath"
        case "Wheel Alignment": "steeringwheel"
        case "New Tires": "circle.circle"
        case "Brake Service": "exclamationmark.brakesignal"
        case "Brake Fluid": "drop.halffull"
        case "Air Filter": "wind"
        case "Cabin Filter": "air.purifier.fill"
        case "AC Service": "snowflake"
        case "Battery Replacement": "minus.plus.batteryblock.fill"
        case "Wiper Blades": "windshield.front.and.wiper"
        case "Spark Plugs": "bolt.fill"
        case "Coolant Flush": "thermometer.medium"
        case "Transmission Service": "gearshift.layout.sixspeed"
        case "Timing Belt": "gearshape.2.fill"
        case "General Inspection": "checklist"
        case "Registration": "doc.text.fill"
        default: "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(VS.Color.accent)
            .frame(width: size, height: size)
            .background(VS.Color.accent.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
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

/// Wrapping chip rows, measured — each row fills to the edge before breaking.
private struct FlowChipWrap: View {
    let items: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let isOn = selected == item
                Button {
                    onSelect(item)
                } label: {
                    Text(item)
                        .font(VS.TextStyle.caption(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(isOn ? VS.Color.accent : VS.Color.chip))
                        .foregroundStyle(isOn ? VS.Color.navPill : VS.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Left-aligned flow layout: places subviews in rows, wrapping at the proposed width.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width = needed
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    @ObservedObject private var efficiencyUnit = EfficiencyUnitStore.shared
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
                                .font(VS.TextStyle.title2())
                                .foregroundStyle(VS.Color.textPrimary)
                            Text(headerAvatar == nil ? "Add a photo from your library" : "Saved on this iPhone")
                                .font(VS.TextStyle.caption())
                                .foregroundStyle(VS.Color.textTertiary)
                        }

                        if isSavingAvatar {
                            ProgressView("Saving photo…")
                                .font(VS.TextStyle.caption())
                                .tint(VS.Color.accent)
                        } else if isPreparingCrop {
                            ProgressView("Opening photo…")
                                .font(VS.TextStyle.caption())
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
                            .font(VS.TextStyle.footnote(.semibold))
                        }

                        if let avatarError {
                            Text(avatarError)
                                .font(VS.TextStyle.caption2())
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fuel efficiency")
                            .font(VS.TextStyle.footnote())
                            .foregroundStyle(VS.Color.textSecondary)
                        EfficiencyUnitToggle()
                        Text(efficiencyUnit.unit.higherIsBetter
                            ? "Higher km/L is better"
                            : "Lower L/100km is better")
                            .font(VS.TextStyle.caption2())
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Email", value: auth.user?.email ?? "Hidden / not shared")
                        Text("Managed by your linked sign-in methods.")
                            .font(VS.TextStyle.caption2())
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    Button {
                        prepareProfileDrafts()
                        profileError = nil
                        showEditAccount = true
                    } label: {
                        Label("Edit account", systemImage: "pencil")
                            .font(VS.TextStyle.callout(.semibold))
                            .foregroundStyle(VS.Color.accent)
                    }
                } header: {
                    Text("Account")
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    TrackyInlineMoodRow(embedded: true)
                } header: {
                    Text("App icon")
                } footer: {
                    Text("Tracky's mood sets your Home Screen icon.")
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
                                    .font(VS.TextStyle.caption2())
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
                                    .font(VS.TextStyle.footnote(.semibold))
                                    .foregroundStyle(VS.Color.error)
                                } else {
                                    Text("Primary")
                                        .font(VS.TextStyle.caption(.semibold))
                                        .foregroundStyle(VS.Color.textTertiary)
                                }
                            } else {
                                Button("Link") {
                                    Task { await linkProvider(provider) }
                                }
                                .font(VS.TextStyle.footnote(.semibold))
                                .foregroundStyle(VS.Color.accent)
                                .disabled(isLinking)
                            }
                        }
                    }

                    if let linkError {
                        Text(linkError)
                            .font(VS.TextStyle.caption2())
                            .foregroundStyle(VS.Color.error)
                    }
                    if let info = auth.infoMessage {
                        Text(info)
                            .font(VS.TextStyle.caption2())
                            .foregroundStyle(VS.Color.success)
                    }
                } header: {
                    Text("Sign-in methods")
                } footer: {
                    Text("Link Apple, Google, or email so you can open the same Veloseete account with any of them.")
                        .font(VS.TextStyle.caption2())
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
                                    .font(VS.TextStyle.caption2()).foregroundStyle(VS.Color.textTertiary)
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
                                    .font(VS.TextStyle.caption2()).foregroundStyle(VS.Color.textTertiary)
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
                                    .font(VS.TextStyle.caption2()).foregroundStyle(VS.Color.textTertiary)
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
                                    .font(VS.TextStyle.caption2()).foregroundStyle(VS.Color.textTertiary)
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
                        .font(VS.TextStyle.caption2())
                }
                .listRowBackground(VS.Color.bgSecondary)

                if let deleteAccountError {
                    Section {
                        Text(deleteAccountError)
                            .font(VS.TextStyle.caption())
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
                            .font(VS.TextStyle.title2(.semibold))
                        Text("Add email sign-in to this account so you can open Veloseete without Apple or Google.")
                            .font(VS.TextStyle.callout())
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
                                .font(VS.TextStyle.caption())
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
                                    .font(VS.TextStyle.headline(.semibold))
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
                            .font(VS.TextStyle.title2(.semibold))
                        Text("Connect Sign in with Apple to this Veloseete account.")
                            .font(VS.TextStyle.callout())
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
                                .font(VS.TextStyle.caption())
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
    @ObservedObject private var efficiencyUnit = EfficiencyUnitStore.shared
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
                            .font(VS.TextStyle.caption(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        TextField("Your name", text: $draftName)
                            .font(VS.TextStyle.title3(.semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                            .padding(14)
                            .glassCard(elevated: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Currency")
                            .font(VS.TextStyle.caption(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(currencies, id: \.self) { code in
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        draftCurrency = code
                                    } label: {
                                        Text(code)
                                            .font(VS.TextStyle.footnote(.semibold))
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
                            .font(VS.TextStyle.caption(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        HStack(spacing: 8) {
                            distanceChip("km", title: "Kilometres")
                            distanceChip("mi", title: "Miles")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fuel efficiency")
                            .font(VS.TextStyle.caption(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        EfficiencyUnitToggle()
                        Text(efficiencyUnit.unit.higherIsBetter
                            ? "Higher numbers mean better economy"
                            : "Lower numbers mean better economy")
                            .font(VS.TextStyle.caption2())
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.TextStyle.footnote())
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
                            .font(VS.TextStyle.headline(.semibold))
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
                .font(VS.TextStyle.footnote(.semibold))
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
                        .font(VS.TextStyle.title())
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(subtitle)
                        .font(VS.TextStyle.callout())
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
                    .font(VS.TextStyle.caption2())
                    .foregroundStyle(VS.Color.textTertiary)

                Spacer()

                Button {
                    onUse(renderCrop())
                } label: {
                    Text("Use this photo")
                        .font(VS.TextStyle.title3(.semibold))
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
