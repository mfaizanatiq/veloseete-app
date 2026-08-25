import SwiftUI
import UIKit

// MARK: - Card stats

enum GarageHealthLogic {
    @MainActor
    static func cardSnapshot(for vehicle: Vehicle, store: DataStore, unit: String) -> GarageVehicleCardSnapshot {
        let estimate = store.odometerEstimate(vehicleId: vehicle.id)
        let odoKm = estimate?.estimatedKm ?? vehicle.currentOdometer
        let year = Calendar.current.component(.year, from: vehicle.createdAt)
        let fuelCount = store.fuelLogs.filter { $0.vehicleId == vehicle.id }.count
        return GarageVehicleCardSnapshot(
            odometerLabel: DistanceFormat.formatOdometer(odoKm, unit: unit),
            yearLabel: String(year),
            fuelCount: fuelCount
        )
    }
}

struct GarageVehicleCardSnapshot: Equatable {
    var odometerLabel: String
    var yearLabel: String
    var fuelCount: Int

    /// Figma meta row: `143000 km  EST  2023  24 fuels`
    var metaLine: String {
        let fuels = fuelCount == 1 ? "1 fuel" : "\(fuelCount) fuels"
        return "\(odometerLabel)  EST  \(yearLabel)  \(fuels)"
    }
}

// MARK: - Fleet segment

enum GarageFleetSegment: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"

    var id: String { rawValue }
}

struct GarageFleetSegmentPicker: View {
    @Binding var segment: GarageFleetSegment
    var archivedCount: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GarageFleetSegment.allCases) { item in
                Button {
                    guard segment != item else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.28)) {
                        segment = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.rawValue)
                            .font(VS.Typography.heading(12, weight: .semibold))
                        if item == .archived, archivedCount > 0 {
                            Text("\(archivedCount)")
                                .font(VS.Typography.mono(9, weight: .bold))
                                .foregroundStyle(segment == item ? VS.Color.navPill : VS.Color.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    (segment == item ? VS.Color.navPill.opacity(0.22) : VS.Color.chip),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(segment == item ? VS.Color.navPill : VS.Color.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(segment == item ? VS.Color.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(VS.Color.navPill.opacity(0.92))
                .overlay(Capsule().strokeBorder(VS.Color.hairline, lineWidth: 1))
        }
    }
}

// MARK: - Hero carousel

/// Responsive showroom metrics — Figma aspect when it fits, otherwise shrink to the device viewport
/// so info + actions stay above the tab field and never clip off-screen.
private struct GarageShowroomLayout {
    let cardHeight: CGFloat
    let cardWidth: CGFloat
    let cardGap: CGFloat = 16
    let carouselPeek: CGFloat = 20
    let cardRadius: CGFloat = VS.Radius.sheet
    /// Reserved band for make/model, nickname, meta, and action row.
    let bottomChromeHeight: CGFloat
    /// Vehicle mark side length inside the stage.
    let carSide: CGFloat
    /// Top inset for the vehicle mark within the card.
    let carTop: CGFloat

    init(containerWidth: CGFloat, viewportHeight: CGFloat) {
        let width = max(containerWidth, 280)
        cardWidth = width

        // Taller showroom — closer to Figma 1.70 so studio + info have room.
        let aspect: CGFloat = 1.58
        let ideal = width * aspect
        let minHeight = max(440, width * 1.34)
        let maxHeight = max(minHeight, viewportHeight)
        cardHeight = min(min(ideal, 660), maxHeight)

        // Compact info + badge/actions band.
        bottomChromeHeight = min(140, max(112, cardHeight * 0.20))

        // Stage owns most of the card — leave vertical room for shadow + mirror under the car.
        let stageBudget = max(240, cardHeight - bottomChromeHeight)
        let widthSide = width * 0.94
        carSide = min(widthSide, stageBudget * 0.80)
        // Sit a bit lower on the floor plane / diorama stage.
        carTop = max(40, stageBudget * 0.28)
    }

    /// Visible height left for Garage after header / segment / tab / safe areas.
    static func viewportBudget(containerWidth: CGFloat) -> CGFloat {
        let screen = UIScreen.main.bounds.height
        let safe = keyWindowSafeInsets
        // Header ~88, segment+gap ~70, page dots ~22, floating tab clearance ~110, vertical padding ~20.
        let reserved = safe.top + safe.bottom + 88 + 70 + 22 + 110 + 20
        let budget = screen - reserved
        // Also keep a width-relative floor so ultra-short windows don't collapse the stage.
        return max(budget, containerWidth * 1.20)
    }

    private static var keyWindowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }
}

struct GarageHeroCarousel: View {
    @EnvironmentObject private var store: DataStore

    @Binding var segment: GarageFleetSegment
    @Binding var page: Int
    var onAddVehicle: () -> Void
    var onEditVehicle: (Vehicle) -> Void
    var onRestoreVehicle: (Vehicle) -> Void

    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width - 40
    @State private var activeSnack: GarageActiveCarSnack?
    @State private var snackDismissTask: Task<Void, Never>?

    private var fleet: [Vehicle] {
        switch segment {
        case .active: store.vehicles
        case .archived: store.archivedVehicles
        }
    }

    private var layout: GarageShowroomLayout {
        GarageShowroomLayout(
            containerWidth: containerWidth,
            viewportHeight: GarageShowroomLayout.viewportBudget(containerWidth: containerWidth)
        )
    }

    private var pageCount: Int {
        switch segment {
        case .active:
            max(fleet.count, 1) + (fleet.isEmpty ? 0 : 1)
        case .archived:
            max(fleet.count, 1)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            GarageFleetSegmentPicker(
                segment: $segment,
                archivedCount: store.archivedVehicles.count
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.cardGap)

            if fleet.isEmpty {
                GarageShowroomEmptyCard(segment: segment, onAddVehicle: onAddVehicle)
                    .frame(height: layout.cardHeight)
                    .padding(.horizontal, layout.cardGap)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(fleet.enumerated()), id: \.element.id) { index, vehicle in
                        GarageShowroomCard(
                            vehicle: vehicle,
                            snapshot: GarageHealthLogic.cardSnapshot(
                                for: vehicle,
                                store: store,
                                unit: store.defaultDistanceUnit
                            ),
                            primaryAction: cardPrimaryAction(for: vehicle),
                            layout: layout,
                            onEdit: { onEditVehicle(vehicle) }
                        )
                        .padding(.horizontal, layout.cardGap / 2)
                        .tag(index)
                    }

                    if segment == .active {
                        GarageShowroomAddCard(
                            action: onAddVehicle,
                            layout: layout
                        )
                        .padding(.horizontal, layout.cardGap / 2)
                        .tag(fleet.count)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .contentMargins(.horizontal, layout.carouselPeek, for: .scrollContent)
                .frame(height: layout.cardHeight)
                .background(GaragePageTabClearBackground())
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: GarageCarouselWidthKey.self,
                            value: geo.size.width
                        )
                    }
                }
                .background(Color.clear)
                .id(segment)

                if pageCount > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Circle()
                                .fill(index == page ? VS.Color.accent : Color.white.opacity(0.18))
                                .frame(width: index == page ? 7 : 5, height: index == page ? 7 : 5)
                                .animation(.snappy(duration: 0.2), value: page)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let activeSnack {
                GarageActiveCarSnackBar(snack: activeSnack)
                    .padding(.horizontal, layout.cardGap)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(GarageCarouselWidthKey.self) { width in
            guard width > 0 else { return }
            containerWidth = width
        }
        .onChange(of: segment) { _, _ in
            page = 0
        }
        .onChange(of: page) { _, _ in
            guard !fleet.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onDisappear {
            snackDismissTask?.cancel()
        }
    }

    private func cardPrimaryAction(for vehicle: Vehicle) -> GarageShowroomCardPrimaryAction {
        switch segment {
        case .active:
            if store.currentVehicle?.id == vehicle.id {
                return .active
            }
            return .setActive {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    do {
                        try await store.selectVehicle(vehicle.id)
                        await MainActor.run {
                            presentActiveSnack(for: vehicle)
                        }
                    } catch {
                        // Keep silent here — garage error banner covers persistent failures elsewhere.
                    }
                }
            }
        case .archived:
            return .restore {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRestoreVehicle(vehicle)
            }
        }
    }

    private func presentActiveSnack(for vehicle: Vehicle) {
        snackDismissTask?.cancel()
        withAnimation(.snappy(duration: 0.32)) {
            activeSnack = GarageActiveCarSnack(
                nickname: vehicle.nickname,
                icon: vehicle.icon,
                paintColor: vehicle.paintColor
            )
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        snackDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.28)) {
                activeSnack = nil
            }
        }
    }
}

private struct GarageActiveCarSnack: Equatable {
    var nickname: String
    var icon: String?
    var paintColor: String?
}

private struct GarageActiveCarSnackBar: View {
    let snack: GarageActiveCarSnack

    private var paint: VehiclePaintColor { VehiclePaintColor.resolve(snack.paintColor) }
    private var markStyle: VehicleMarkStyle { VehicleMarkStyle.resolve(snack.icon ?? "🚗") }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(VS.Color.chip)
                VehicleMark(style: markStyle, size: 34, paint: paint)
            }
            .frame(width: 44, height: 44)
            .overlay(Circle().strokeBorder(VS.Color.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(snack.nickname)
                    .font(VS.Typography.heading(15, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                Text("Now your active car")
                    .font(VS.Typography.body(12))
                    .foregroundStyle(VS.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("Active")
                .font(VS.Typography.heading(12, weight: .bold))
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(VS.Color.accent, in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(VS.Color.navPill.opacity(0.96))
                .overlay(Capsule(style: .continuous).strokeBorder(VS.Color.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snack.nickname) is now your active car")
    }
}

private enum GarageShowroomCardPrimaryAction: Equatable {
    case active
    case setActive(() -> Void)
    case restore(() -> Void)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.active, .active): true
        case (.setActive, .setActive): true
        case (.restore, .restore): true
        default: false
        }
    }
}

private struct GarageShowroomEmptyCard: View {
    var segment: GarageFleetSegment
    var onAddVehicle: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text(segment == .active ? "No cars yet" : "No archived cars")
                .font(VS.Typography.heading(22, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(
                segment == .active
                    ? "Add your first car to start tracking drives and fuel."
                    : "Cars you archive will show up here."
            )
            .font(VS.Typography.body(14))
            .foregroundStyle(VS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            if segment == .active {
                PrimaryCTAButton(title: "Add car", icon: .plusCircle, action: onAddVehicle)
                    .padding(.horizontal, VS.Spacing.card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 28)
        .background {
            RoundedRectangle(cornerRadius: VS.Radius.sheet, style: .continuous)
                .fill(Color(hex: 0x161916))
                .overlay(
                    RoundedRectangle(cornerRadius: VS.Radius.sheet, style: .continuous)
                        .strokeBorder(VS.Color.hairline, lineWidth: 1)
                )
        }
    }
}

private struct GarageCarouselWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Garage hero card — Figma `Type=Default` (`74:75`): studio bg, vehicle + floor mirror, info, Active Car + sliders.
private struct GarageShowroomCard: View {
    let vehicle: Vehicle
    let snapshot: GarageVehicleCardSnapshot
    var primaryAction: GarageShowroomCardPrimaryAction
    var layout: GarageShowroomLayout
    var onEdit: () -> Void

    private var paint: VehiclePaintColor { VehiclePaintColor.resolve(vehicle.paintColor) }
    private var makeModel: String {
        "\(vehicle.make) \(vehicle.model)".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GarageShowroomCardBackdrop(markStyle: VehicleMarkStyle.resolve(vehicle.icon ?? "🚗"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GarageShowroomCardStage(
                markStyle: VehicleMarkStyle.resolve(vehicle.icon ?? "🚗"),
                paint: paint,
                carSide: layout.carSide,
                carTop: layout.carTop
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Leave room under the mark for contact shadow + floor mirror before the info band.
            .padding(.bottom, layout.bottomChromeHeight * 0.42)

            // Soften so the floor mirror still reads above the chrome.
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.bottomChromeHeight + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                garageInfoBlock
                garageActionRow
            }
            .padding(.horizontal, VS.Spacing.card)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardRadius, style: .continuous)
                .strokeBorder(VS.Color.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var garageInfoBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(makeModel.isEmpty ? "—" : makeModel)
                .font(VS.Typography.heading(13, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)

            Text(vehicle.nickname)
                .font(VS.Typography.heading(layout.cardHeight < 520 ? 24 : 28, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(snapshot.metaLine)
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var garageActionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            primaryActionView
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEdit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(VS.Color.accent, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(vehicle.nickname)")
        }
    }

    @ViewBuilder
    private var primaryActionView: some View {
        switch primaryAction {
        case .active:
            // Status badge — compact, not a CTA.
            Text("Active Car")
                .font(VS.Typography.heading(16, weight: .bold))
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(VS.Color.accent, in: Capsule(style: .continuous))
                .accessibilityLabel("Active car")
        case .setActive(let action):
            // CTA — same 56pt height as the settings control.
            Button(action: action) {
                Text("Set active")
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(VS.Color.accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set active car")
        case .restore(let action):
            Button(action: action) {
                Text("Restore")
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(VS.Color.accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restore car")
        }
    }
}

/// Contextual showroom plate per vehicle type — same horizon lock, Higgsfield environments.
/// New / empty slot cards use the original studio plate.
private struct GarageShowroomCardBackdrop: View {
    /// `nil` → classic empty studio (for Add car).
    var markStyle: VehicleMarkStyle? = nil

    private let studioScaleX: CGFloat = 409.675 / 366.0
    private let studioScaleY: CGFloat = 734.002 / 621.0
    private let studioOffsetX: CGFloat = -23.508 / 366.0
    // Nudge plate up so the shared horizon / ground plane lands under the car.
    private let studioOffsetY: CGFloat = -130.0 / 621.0

    private var studioAssetName: String {
        markStyle?.showroomEnvironmentAssetName ?? "GarageCardStudio"
    }

    var body: some View {
        // Color anchors size so GeometryReader cannot collapse inside TabView/ZStack.
        Color(hex: 0x161916)
            .overlay {
                GeometryReader { geo in
                    let studioW = geo.size.width * studioScaleX
                    let studioH = geo.size.height * studioScaleY

                    Image(studioAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: studioW, height: studioH)
                        .position(
                            x: geo.size.width * 0.5 + geo.size.width * studioOffsetX * 0.5,
                            y: geo.size.height * 0.5 + geo.size.height * studioOffsetY * 0.5
                        )
                        .id(studioAssetName)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear,
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.35), value: markStyle)
    }
}

private extension VehicleMarkStyle {
    /// Higgsfield contextual environment for this mark (locked horizon).
    var showroomEnvironmentAssetName: String {
        "GarageEnv-\(rawValue)"
    }
}

/// Vehicle mark + soft contact shadow + vertically flipped floor mirror (Figma opacity 0.3 + linear fade).
private struct GarageShowroomCardStage: View {
    let markStyle: VehicleMarkStyle
    let paint: VehiclePaintColor
    var carSide: CGFloat
    var carTop: CGFloat

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    let side = min(carSide, geo.size.width * 0.96)
                    let top = min(carTop, max(12, geo.size.height * 0.32))
                    // Flip around the tire line so the mirror starts flush with the wheels (no float gap).
                    let wheelY = side * Self.wheelContactFraction(for: markStyle)
                    // Sweet spot: short enough to avoid float, long enough to read as floor glass.
                    let mirrorFade = min(side * 0.24, max(48, geo.size.height - top - wheelY))
                    // Pull the reflection up into the tire contact.
                    let mirrorLift = side * 0.022

                    ZStack(alignment: .top) {
                        // Soft ambient ground shadow — wide, diffused.
                        Ellipse()
                            .fill(Color.black.opacity(0.42))
                            .frame(width: side * 0.82, height: side * 0.10)
                            .blur(radius: 22)
                            .offset(y: wheelY - side * 0.01)
                            .allowsHitTesting(false)

                        // Mid shadow — broader falloff under the chassis.
                        Ellipse()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: side * 0.68, height: side * 0.055)
                            .blur(radius: 14)
                            .offset(y: wheelY - side * 0.012)
                            .allowsHitTesting(false)

                        // Core contact shadow — still soft, but denser at the tires.
                        Ellipse()
                            .fill(Color.black.opacity(0.72))
                            .frame(width: side * 0.52, height: side * 0.028)
                            .blur(radius: 8)
                            .offset(y: wheelY - side * 0.016)
                            .allowsHitTesting(false)

                        // Floor mirror — lifted into the tires, soft linear fade.
                        vehicleLayer(side: side)
                            .scaleEffect(x: 1, y: -1, anchor: UnitPoint(x: 0.5, y: wheelY / side))
                            .opacity(0.26)
                            .mask(
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: max(0, wheelY - mirrorLift))
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(1.0), location: 0),
                                            .init(color: .white.opacity(0.48), location: 0.30),
                                            .init(color: .white.opacity(0.12), location: 0.70),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: mirrorFade)
                                    Spacer(minLength: 0)
                                }
                                .frame(width: side, height: side, alignment: .top)
                            )
                            .offset(y: -mirrorLift)
                            .allowsHitTesting(false)

                        vehicleLayer(side: side)
                    }
                    .frame(width: side, height: wheelY + mirrorFade, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, top)
                }
            }
    }

    private func vehicleLayer(side: CGFloat) -> some View {
        VehicleMark(style: markStyle, size: side, paint: paint)
            .frame(width: side, height: side)
    }

    /// Bottom of the opaque silhouette inside the 1024 mark square.
    private static func wheelContactFraction(for style: VehicleMarkStyle) -> CGFloat {
        switch style {
        case .suv, .van, .truck, .pickup: return 0.72
        case .moto, .scooter: return 0.68
        default: return 0.625
        }
    }
}

private struct GarageShowroomAddCard: View {
    var action: () -> Void
    var layout: GarageShowroomLayout

    var body: some View {
        ZStack(alignment: .bottom) {
            GarageShowroomCardBackdrop()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GarageAddCarRevealStage(carSide: layout.carSide, carTop: layout.carTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, layout.bottomChromeHeight * 0.42)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.bottomChromeHeight + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add to garage")
                        .font(VS.Typography.heading(13, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)

                    Text("Another car")
                        .font(VS.Typography.heading(layout.cardHeight < 520 ? 24 : 28, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)

                    Text("Keep every car in one place")
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryCTAButton(title: "Add car", icon: .plusCircle, action: action)
            }
            .padding(.horizontal, VS.Spacing.card)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardRadius, style: .continuous)
                .strokeBorder(VS.Color.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add vehicle")
    }
}

/// Covered car with contour lines — empty-slot illustration for the garage carousel.
private struct GarageAddCarRevealStage: View {
    var carSide: CGFloat
    var carTop: CGFloat

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    let side = min(carSide, geo.size.width * 0.96)
                    let top = min(carTop, max(12, geo.size.height * 0.32))
                    let wheelY = side * 0.625
                    let mirrorFade = min(side * 0.24, max(48, geo.size.height - top - wheelY))
                    let mirrorLift = side * 0.022

                    ZStack(alignment: .top) {
                        Ellipse()
                            .fill(Color.black.opacity(0.40))
                            .frame(width: side * 0.82, height: side * 0.10)
                            .blur(radius: 22)
                            .offset(y: wheelY - side * 0.01)
                            .allowsHitTesting(false)

                        Ellipse()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: side * 0.68, height: side * 0.055)
                            .blur(radius: 14)
                            .offset(y: wheelY - side * 0.012)
                            .allowsHitTesting(false)

                        Ellipse()
                            .fill(Color.black.opacity(0.70))
                            .frame(width: side * 0.52, height: side * 0.028)
                            .blur(radius: 8)
                            .offset(y: wheelY - side * 0.016)
                            .allowsHitTesting(false)

                        revealMark(side: side)
                            .scaleEffect(x: 1, y: -1, anchor: UnitPoint(x: 0.5, y: wheelY / side))
                            .opacity(0.26)
                            .mask(
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: max(0, wheelY - mirrorLift))
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(1.0), location: 0),
                                            .init(color: .white.opacity(0.48), location: 0.30),
                                            .init(color: .white.opacity(0.12), location: 0.70),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: mirrorFade)
                                    Spacer(minLength: 0)
                                }
                                .frame(width: side, height: side, alignment: .top)
                            )
                            .offset(y: -mirrorLift)
                            .allowsHitTesting(false)

                        revealMark(side: side)
                    }
                    .frame(width: side, height: wheelY + mirrorFade, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, top)
                }
            }
            .allowsHitTesting(false)
    }

    private func revealMark(side: CGFloat) -> some View {
        Image("GarageAddCarReveal")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Clears UIKit page controller grey backing inside SwiftUI `TabView`.
private struct GaragePageTabClearBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            var parent = view.superview
            while let current = parent {
                current.backgroundColor = .clear
                parent = current.superview
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.backgroundColor = .clear
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
