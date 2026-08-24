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

    var metaLine: String {
        let fuels = fuelCount == 1 ? "1 fuel" : "\(fuelCount) fuels"
        return "\(yearLabel)  ·  \(fuels)"
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
        HStack(spacing: 4) {
            ForEach(GarageFleetSegment.allCases) { item in
                Button {
                    guard segment != item else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.28)) {
                        segment = item
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(item.rawValue)
                            .font(VS.Typography.heading(14, weight: .semibold))
                        if item == .archived, archivedCount > 0 {
                            Text("\(archivedCount)")
                                .font(VS.Typography.mono(11, weight: .bold))
                                .foregroundStyle(segment == item ? VS.Color.navPill : VS.Color.textSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    (segment == item ? VS.Color.navPill.opacity(0.22) : VS.Color.chip),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(segment == item ? VS.Color.navPill : VS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(segment == item ? VS.Color.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(VS.Color.navPill.opacity(0.92))
                .overlay(Capsule().strokeBorder(VS.Color.hairline, lineWidth: 1))
        }
    }
}

// MARK: - Hero carousel

private struct GarageShowroomLayout {
    let cardHeight: CGFloat
    let carMaxHeight: CGFloat
    let cardGap: CGFloat = 16
    let carouselPeek: CGFloat = 20
    let actionSlotHeight: CGFloat = 58

    init(containerWidth: CGFloat, reservesActionSlot: Bool) {
        // Taller cards so the hero stage can hold a near-full-width car.
        cardHeight = min(max(containerWidth * 1.28, 560), 680)
        let infoBlock: CGFloat = 118
        let actionBlock = reservesActionSlot ? (actionSlotHeight + 10) : 0
        carMaxHeight = max(340, cardHeight - infoBlock - actionBlock - 20)
    }

    var carouselHeight: CGFloat { cardHeight + 26 }
}

struct GarageHeroCarousel: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var vehiclePhotos: VehiclePhotoStore

    @Binding var segment: GarageFleetSegment
    @Binding var page: Int
    var onAddVehicle: () -> Void
    var onEditVehicle: (Vehicle) -> Void
    var onRestoreVehicle: (Vehicle) -> Void

    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width - 40

    private var fleet: [Vehicle] {
        switch segment {
        case .active: store.vehicles
        case .archived: store.archivedVehicles
        }
    }

    private var reservesActionSlot: Bool {
        switch segment {
        case .archived:
            true
        case .active:
            fleet.contains { $0.id != store.currentVehicle?.id } || !fleet.isEmpty
        }
    }

    private var layout: GarageShowroomLayout {
        GarageShowroomLayout(
            containerWidth: containerWidth,
            reservesActionSlot: reservesActionSlot
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
            .padding(.horizontal, 12)

            if fleet.isEmpty {
                GarageShowroomEmptyCard(segment: segment, onAddVehicle: onAddVehicle)
                    .frame(height: layout.cardHeight)
                    .padding(.horizontal, layout.cardGap)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(fleet.enumerated()), id: \.element.id) { index, vehicle in
                        GarageShowroomCard(
                            vehicle: vehicle,
                            image: vehiclePhotos.image(for: vehicle.id),
                            snapshot: GarageHealthLogic.cardSnapshot(
                                for: vehicle,
                                store: store,
                                unit: store.defaultDistanceUnit
                            ),
                            statusLabel: cardStatusLabel(for: vehicle),
                            primaryAction: cardPrimaryAction(for: vehicle),
                            reservesActionSlot: reservesActionSlot,
                            cardHeight: layout.cardHeight,
                            carMaxHeight: layout.carMaxHeight,
                            actionSlotHeight: layout.actionSlotHeight,
                            onEdit: { onEditVehicle(vehicle) }
                        )
                        .padding(.horizontal, layout.cardGap / 2)
                        .tag(index)
                    }

                    if segment == .active {
                        GarageShowroomAddCard(
                            action: onAddVehicle,
                            cardHeight: layout.cardHeight
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
    }

    private func cardStatusLabel(for vehicle: Vehicle) -> String {
        switch segment {
        case .active:
            store.currentVehicle?.id == vehicle.id ? "Your active car" : "In your garage"
        case .archived:
            "Archived"
        }
    }

    private func cardPrimaryAction(for vehicle: Vehicle) -> GarageShowroomCardPrimaryAction {
        switch segment {
        case .active:
            if store.currentVehicle?.id == vehicle.id {
                return .none
            }
            return .setActive {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { try? await store.selectVehicle(vehicle.id) }
            }
        case .archived:
            return .restore {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRestoreVehicle(vehicle)
            }
        }
    }
}

private enum GarageShowroomCardPrimaryAction: Equatable {
    case none
    case setActive(() -> Void)
    case restore(() -> Void)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
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
            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                .fill(VS.Color.bgSecondary.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
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

private struct GarageShowroomCard: View {
    let vehicle: Vehicle
    let image: UIImage?
    let snapshot: GarageVehicleCardSnapshot
    var statusLabel: String
    var primaryAction: GarageShowroomCardPrimaryAction
    var reservesActionSlot: Bool
    var cardHeight: CGFloat
    var carMaxHeight: CGFloat
    var actionSlotHeight: CGFloat
    var onEdit: () -> Void

    private var paint: VehiclePaintColor { VehiclePaintColor.resolve(vehicle.paintColor) }
    private var makeModel: String {
        "\(vehicle.make) \(vehicle.model)".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    GarageCardTopGlow(accent: paint.swatch)

                    Ellipse()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: min(300, carMaxHeight * 0.85), height: 16)
                        .blur(radius: 16)
                        .padding(.bottom, 6)

                    garageCarVisual
                        .padding(.horizontal, 0)
                        .padding(.bottom, 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    garageInfoBlock
                        .padding(.horizontal, VS.Spacing.card)
                        .padding(.top, 10)

                    if reservesActionSlot {
                        Group {
                            if primaryAction != .none {
                                primaryActionView
                            } else {
                                Color.clear.frame(height: actionSlotHeight)
                            }
                        }
                        .padding(.horizontal, VS.Spacing.card)
                        .padding(.top, 10)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .background {
                RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.07),
                                VS.Color.bgSecondary.opacity(0.96),
                                VS.Color.bgSecondary
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                            .strokeBorder(VS.Color.hairline, lineWidth: 1)
                    )
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEdit()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(VS.Color.textSecondary)
                    .padding(10)
                    .background(.ultraThinMaterial.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityLabel("Edit \(vehicle.nickname)")
        }
        .accessibilityElement(children: .contain)
    }

    private var garageInfoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(statusLabel)
                    .font(VS.Typography.mono(10, weight: .bold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .textCase(.uppercase)

                Text(vehicle.nickname)
                    .font(VS.Typography.heading(26, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)

                Text(makeModel.isEmpty ? "—" : makeModel)
                    .font(VS.Typography.body(14, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.odometerLabel)
                        .font(VS.Typography.heading(24, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("estimated")
                        .font(VS.Typography.mono(10, weight: .bold))
                        .foregroundStyle(VS.Color.textTertiary)
                }

                Text(snapshot.metaLine)
                    .font(VS.Typography.mono(11, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var primaryActionView: some View {
        switch primaryAction {
        case .none:
            EmptyView()
        case .setActive(let action):
            PrimaryCTAButton(title: "Set active", icon: nil, action: action)
        case .restore(let action):
            PrimaryCTAButton(title: "Restore", icon: nil, action: action)
        }
    }

    @ViewBuilder
    private var garageCarVisual: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: side, height: side)
                } else {
                    // Fill the hero stage — no artificial 220pt cap (that made Higgsfield marks look tiny).
                    VehicleMark(
                        style: VehicleMarkStyle.resolve(vehicle.icon ?? "🚗"),
                        size: side,
                        paint: paint
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: carMaxHeight)
    }
}

/// Soft wash at the top of the vehicle card — no busy petals.
private struct GarageCardTopGlow: View {
    var accent: Color

    var body: some View {
        RadialGradient(
            colors: [
                accent.opacity(0.18),
                accent.opacity(0.06),
                Color.clear
            ],
            center: UnitPoint(x: 0.5, y: 0.15),
            startRadius: 8,
            endRadius: 180
        )
        .allowsHitTesting(false)
    }
}

private struct GarageShowroomAddCard: View {
    var action: () -> Void
    var cardHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                GarageCardTopGlow(accent: VS.Color.accent)
                Circle()
                    .strokeBorder(VS.Color.accent.opacity(0.35), lineWidth: 2)
                    .frame(width: 80, height: 80)
                VSIcon(icon: .plusCircle, size: 40, weight: .fill, tint: VS.Color.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add to garage")
                            .font(VS.Typography.mono(10, weight: .bold))
                            .foregroundStyle(VS.Color.textTertiary)
                            .textCase(.uppercase)

                        Text("Another car")
                            .font(VS.Typography.heading(26, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)

                        Text("Keep every car in one place")
                            .font(VS.Typography.body(14, weight: .medium))
                            .foregroundStyle(VS.Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VS.Spacing.card)
                .padding(.top, 10)

                PrimaryCTAButton(title: "Add car", icon: .plusCircle, action: action)
                    .padding(.horizontal, VS.Spacing.card)
                    .padding(.top, 10)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background {
            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.07),
                            VS.Color.bgSecondary.opacity(0.96),
                            VS.Color.bgSecondary
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                        .strokeBorder(VS.Color.hairline, lineWidth: 1)
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add vehicle")
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
