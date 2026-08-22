import SwiftUI

/// Veloseete car marks — flat silhouette set for garage representation.
/// Stored value stays emoji (web parity); iOS always renders these marks.
enum VehicleMarkStyle: String, CaseIterable, Identifiable {
    case sedan
    case suv
    case hatch
    case coupe
    case pickup
    case van
    case truck
    case taxi
    case sport
    case moto
    case scooter
    case ev

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedan: return "Sedan"
        case .suv: return "SUV"
        case .hatch: return "Hatch"
        case .coupe: return "Coupe"
        case .pickup: return "Pickup"
        case .van: return "Van"
        case .truck: return "Truck"
        case .taxi: return "Taxi"
        case .sport: return "Sport"
        case .moto: return "Moto"
        case .scooter: return "Scooter"
        case .ev: return "EV"
        }
    }

    /// Emoji token persisted on `Vehicle.icon` for web/shared storage.
    var storageToken: String {
        switch self {
        case .sedan: return "🚗"
        case .suv: return "🚙"
        case .hatch: return "🚎"
        case .coupe: return "🚘"
        case .pickup: return "🛻"
        case .van: return "🚐"
        case .truck: return "🚚"
        case .taxi: return "🚕"
        case .sport: return "🏎️"
        case .moto: return "🏍️"
        case .scooter: return "🛵"
        case .ev: return "⚡"
        }
    }

    /// Styles shown in the garage picker.
    static var selectable: [VehicleMarkStyle] {
        [.sedan, .suv, .hatch, .coupe, .sport, .ev, .pickup, .van, .truck, .taxi, .moto, .scooter]
    }

    static func resolve(_ stored: String?) -> VehicleMarkStyle {
        guard let raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .sedan
        }
        if let byId = VehicleMarkStyle(rawValue: raw) { return byId }
        let token = raw.replacingOccurrences(of: "\u{FE0F}", with: "")
        switch token {
        case "🚗": return .sedan
        case "🚙": return .suv
        case "🚎", "🚌": return .hatch
        case "🚘": return .coupe
        case "🛻": return .pickup
        case "🚐", "🚒", "🚑": return .van
        case "🚚", "🚛": return .truck
        case "🚕", "🚓": return .taxi
        case "🏎", "🏎️": return .sport
        case "🏍", "🏍️": return .moto
        case "🛵": return .scooter
        case "⚡", "🔋": return .ev
        case "🚜": return .truck
        default: return .sedan
        }
    }
}

/// Veloseete car marks — soft matte lime 3D icons (brand lime + black glass/wheels).
/// Prefers assets `vehicle-{style}` (picker) or `vehicle-{style}-map` (Uber-style top-down for maps).
struct VehicleMark: View {
    enum Viewpoint {
        /// Garage / picker — front three-quarter.
        case mark
        /// Live map puck — bird’s-eye top-down (Uber-style), nose = travel direction.
        case map
    }

    var style: VehicleMarkStyle = .sedan
    var size: CGFloat = 44
    var viewpoint: Viewpoint = .mark

    var body: some View {
        Group {
            if let uiImage = UIImage(named: resolvedAssetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Canvas { context, canvasSize in
                    let s = min(canvasSize.width, canvasSize.height)
                    let origin = CGPoint(
                        x: (canvasSize.width - s) / 2,
                        y: (canvasSize.height - s) / 2
                    )
                    draw(style, in: &context, origin: origin, s: s)
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(style.label)
    }

    /// Prefer map asset; fall back to garage front-three-quarter mark (never Tracky).
    private var resolvedAssetName: String {
        let mapName = "vehicle-\(style.rawValue)-map"
        if viewpoint == .map, UIImage(named: mapName) != nil {
            return mapName
        }
        return "vehicle-\(style.rawValue)"
    }

    private var bodyFill: Color { Color(hex: 0x0A0C0A) }
    private var glass: Color { VS.Color.accent.opacity(0.92) }
    private var accentSoft: Color { VS.Color.accent.opacity(0.55) }
    private var wheel: Color { Color(hex: 0x1A1C1A) }
    private var wheelRim: Color { VS.Color.accent.opacity(0.35) }
    private var outline: Color { Color.white.opacity(0.14) }

    private func draw(
        _ style: VehicleMarkStyle,
        in context: inout GraphicsContext,
        origin: CGPoint,
        s: CGFloat
    ) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * s, y: origin.y + y * s)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * s, y: origin.y + y * s, width: w * s, height: h * s)
        }

        switch style {
        case .sedan, .taxi, .coupe, .hatch, .ev:
            drawCarBody(
                context: &context,
                p: p,
                r: r,
                cabinHeight: style == .coupe || style == .sport ? 0.22 : 0.26,
                cabinInset: style == .hatch ? 0.18 : (style == .coupe ? 0.28 : 0.22),
                rearDrop: style == .hatch || style == .coupe,
                taxiSign: style == .taxi,
                bolt: style == .ev
            )
        case .sport:
            drawCarBody(
                context: &context,
                p: p,
                r: r,
                cabinHeight: 0.18,
                cabinInset: 0.32,
                rearDrop: true,
                taxiSign: false,
                bolt: false,
                low: true
            )
        case .suv:
            drawSUV(context: &context, p: p, r: r)
        case .pickup:
            drawPickup(context: &context, p: p, r: r)
        case .van:
            drawVan(context: &context, p: p, r: r)
        case .truck:
            drawTruck(context: &context, p: p, r: r)
        case .moto:
            drawMoto(context: &context, p: p, r: r)
        case .scooter:
            drawScooter(context: &context, p: p, r: r)
        }
    }

    private func drawCarBody(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        cabinHeight: CGFloat,
        cabinInset: CGFloat,
        rearDrop: Bool,
        taxiSign: Bool,
        bolt: Bool,
        low: Bool = false
    ) {
        let deckY: CGFloat = low ? 0.58 : 0.54
        var body = Path()
        body.move(to: p(0.12, deckY))
        body.addLine(to: p(0.18, 0.40))
        body.addLine(to: p(cabinInset, 0.40 - cabinHeight))
        if rearDrop {
            body.addLine(to: p(0.72, 0.40 - cabinHeight * 0.85))
            body.addLine(to: p(0.86, deckY - 0.04))
        } else {
            body.addLine(to: p(0.78 - cabinInset + 0.22, 0.40 - cabinHeight))
            body.addLine(to: p(0.86, 0.40))
        }
        body.addLine(to: p(0.90, deckY))
        body.addLine(to: p(0.90, 0.72))
        body.addLine(to: p(0.12, 0.72))
        body.closeSubpath()
        context.fill(body, with: .color(bodyFill))
        context.stroke(body, with: .color(outline), lineWidth: 1)

        // Glass band
        var glassPath = Path()
        glassPath.move(to: p(cabinInset + 0.02, 0.42 - cabinHeight + 0.04))
        glassPath.addLine(to: p(rearDrop ? 0.70 : 0.74, 0.42 - cabinHeight + 0.04))
        glassPath.addLine(to: p(rearDrop ? 0.78 : 0.82, 0.42))
        glassPath.addLine(to: p(cabinInset + 0.06, 0.42))
        glassPath.closeSubpath()
        context.fill(glassPath, with: .color(glass))

        // Headlight
        context.fill(Path(ellipseIn: r(0.84, deckY + 0.02, 0.06, 0.05)), with: .color(accentSoft))
        // Taillight
        context.fill(Path(roundedRect: r(0.12, deckY + 0.02, 0.05, 0.045), cornerRadius: 1), with: .color(VS.Color.routeEnd.opacity(0.85)))

        drawWheel(context: &context, rect: r(0.24, 0.68, 0.16, 0.16))
        drawWheel(context: &context, rect: r(0.62, 0.68, 0.16, 0.16))

        if taxiSign {
            context.fill(Path(roundedRect: r(0.42, 0.18, 0.16, 0.07), cornerRadius: 2), with: .color(glass))
        }
        if bolt {
            var boltPath = Path()
            boltPath.move(to: p(0.48, 0.48))
            boltPath.addLine(to: p(0.54, 0.48))
            boltPath.addLine(to: p(0.50, 0.56))
            boltPath.addLine(to: p(0.56, 0.56))
            boltPath.addLine(to: p(0.46, 0.68))
            boltPath.addLine(to: p(0.50, 0.58))
            boltPath.addLine(to: p(0.44, 0.58))
            boltPath.closeSubpath()
            context.fill(boltPath, with: .color(glass))
        }
    }

    private func drawSUV(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect
    ) {
        var body = Path()
        body.move(to: p(0.10, 0.56))
        body.addLine(to: p(0.16, 0.34))
        body.addLine(to: p(0.22, 0.22))
        body.addLine(to: p(0.78, 0.22))
        body.addLine(to: p(0.88, 0.34))
        body.addLine(to: p(0.92, 0.56))
        body.addLine(to: p(0.92, 0.74))
        body.addLine(to: p(0.10, 0.74))
        body.closeSubpath()
        context.fill(body, with: .color(bodyFill))
        context.stroke(body, with: .color(outline), lineWidth: 1)

        context.fill(Path(roundedRect: r(0.26, 0.28, 0.22, 0.16), cornerRadius: 3), with: .color(glass))
        context.fill(Path(roundedRect: r(0.52, 0.28, 0.22, 0.16), cornerRadius: 3), with: .color(glass))
        context.fill(Path(ellipseIn: r(0.86, 0.58, 0.06, 0.05)), with: .color(accentSoft))

        drawWheel(context: &context, rect: r(0.20, 0.68, 0.18, 0.18))
        drawWheel(context: &context, rect: r(0.64, 0.68, 0.18, 0.18))
    }

    private func drawPickup(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect
    ) {
        var cab = Path()
        cab.move(to: p(0.12, 0.56))
        cab.addLine(to: p(0.18, 0.36))
        cab.addLine(to: p(0.24, 0.24))
        cab.addLine(to: p(0.52, 0.24))
        cab.addLine(to: p(0.58, 0.36))
        cab.addLine(to: p(0.58, 0.72))
        cab.addLine(to: p(0.12, 0.72))
        cab.closeSubpath()
        context.fill(cab, with: .color(bodyFill))

        var bed = Path()
        bed.move(to: p(0.58, 0.46))
        bed.addLine(to: p(0.90, 0.46))
        bed.addLine(to: p(0.90, 0.72))
        bed.addLine(to: p(0.58, 0.72))
        bed.closeSubpath()
        context.fill(bed, with: .color(bodyFill))
        context.stroke(cab, with: .color(outline), lineWidth: 1)
        context.stroke(bed, with: .color(outline), lineWidth: 1)

        context.fill(Path(roundedRect: r(0.28, 0.30, 0.22, 0.14), cornerRadius: 3), with: .color(glass))
        drawWheel(context: &context, rect: r(0.22, 0.68, 0.16, 0.16))
        drawWheel(context: &context, rect: r(0.68, 0.68, 0.16, 0.16))
    }

    private func drawVan(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect
    ) {
        var body = Path()
        body.move(to: p(0.10, 0.58))
        body.addLine(to: p(0.16, 0.28))
        body.addLine(to: p(0.22, 0.18))
        body.addLine(to: p(0.86, 0.18))
        body.addLine(to: p(0.92, 0.28))
        body.addLine(to: p(0.92, 0.74))
        body.addLine(to: p(0.10, 0.74))
        body.closeSubpath()
        context.fill(body, with: .color(bodyFill))
        context.stroke(body, with: .color(outline), lineWidth: 1)
        context.fill(Path(roundedRect: r(0.24, 0.26, 0.18, 0.20), cornerRadius: 3), with: .color(glass))
        context.fill(Path(roundedRect: r(0.48, 0.26, 0.34, 0.12), cornerRadius: 2), with: .color(accentSoft.opacity(0.45)))
        drawWheel(context: &context, rect: r(0.22, 0.68, 0.16, 0.16))
        drawWheel(context: &context, rect: r(0.66, 0.68, 0.16, 0.16))
    }

    private func drawTruck(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect
    ) {
        var cab = Path()
        cab.move(to: p(0.08, 0.52))
        cab.addLine(to: p(0.14, 0.28))
        cab.addLine(to: p(0.20, 0.18))
        cab.addLine(to: p(0.40, 0.18))
        cab.addLine(to: p(0.46, 0.30))
        cab.addLine(to: p(0.46, 0.74))
        cab.addLine(to: p(0.08, 0.74))
        cab.closeSubpath()
        context.fill(cab, with: .color(bodyFill))

        var trailer = Path()
        trailer.addRoundedRect(in: r(0.46, 0.30, 0.46, 0.40), cornerSize: CGSize(width: 4, height: 4))
        context.fill(trailer, with: .color(bodyFill))
        context.stroke(cab, with: .color(outline), lineWidth: 1)
        context.stroke(trailer, with: .color(outline), lineWidth: 1)
        context.fill(Path(roundedRect: r(0.22, 0.26, 0.16, 0.16), cornerRadius: 2), with: .color(glass))

        drawWheel(context: &context, rect: r(0.16, 0.68, 0.14, 0.14))
        drawWheel(context: &context, rect: r(0.58, 0.68, 0.14, 0.14))
        drawWheel(context: &context, rect: r(0.74, 0.68, 0.14, 0.14))
    }

    private func drawMoto(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect
    ) {
        drawWheel(context: &context, rect: r(0.16, 0.58, 0.22, 0.22))
        drawWheel(context: &context, rect: r(0.62, 0.58, 0.22, 0.22))

        var frame = Path()
        frame.move(to: p(0.28, 0.62))
        frame.addLine(to: p(0.48, 0.42))
        frame.addLine(to: p(0.70, 0.62))
        context.stroke(frame, with: .color(bodyFill), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        var tank = Path()
        tank.addEllipse(in: r(0.40, 0.40, 0.20, 0.12))
        context.fill(tank, with: .color(bodyFill))
        context.fill(Path(ellipseIn: r(0.44, 0.42, 0.10, 0.06)), with: .color(glass))

        var seat = Path()
        seat.addRoundedRect(in: r(0.52, 0.46, 0.16, 0.06), cornerSize: CGSize(width: 3, height: 3))
        context.fill(seat, with: .color(bodyFill))
    }

    private func drawScooter(
        context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect
    ) {
        drawWheel(context: &context, rect: r(0.18, 0.62, 0.18, 0.18))
        drawWheel(context: &context, rect: r(0.64, 0.62, 0.18, 0.18))

        var deck = Path()
        deck.addRoundedRect(in: r(0.28, 0.58, 0.42, 0.06), cornerSize: CGSize(width: 3, height: 3))
        context.fill(deck, with: .color(bodyFill))

        var stem = Path()
        stem.move(to: p(0.30, 0.60))
        stem.addLine(to: p(0.30, 0.30))
        stem.addLine(to: p(0.42, 0.26))
        context.stroke(stem, with: .color(bodyFill), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        context.fill(Path(ellipseIn: r(0.52, 0.44, 0.18, 0.12)), with: .color(bodyFill))
        context.fill(Path(ellipseIn: r(0.56, 0.46, 0.10, 0.06)), with: .color(glass))
    }

    private func drawWheel(context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(ellipseIn: rect), with: .color(wheel))
        let inset = rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28)
        context.fill(Path(ellipseIn: inset), with: .color(wheelRim))
        context.stroke(Path(ellipseIn: rect), with: .color(outline), lineWidth: 1)
    }
}

/// Picker cell — glorified mark, single lime selection ring (no dual borders).
struct VehicleMarkPickerCell: View {
    let style: VehicleMarkStyle
    let selected: Bool
    var action: () -> Void

    private let tile: CGFloat = 96
    private let mark: CGFloat = 84

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(spacing: 6) {
                VehicleMark(style: style, size: mark)
                    .frame(width: tile, height: tile)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(VS.Color.navPill.opacity(0.88))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                selected ? VS.Color.accent : VS.Color.hairline.opacity(0.55),
                                lineWidth: selected ? 2.5 : 1
                            )
                    }
                    .opacity(selected ? 1 : 0.55)
                    .saturation(selected ? 1 : 0.75)

                Text(style.label)
                    .font(VS.Typography.heading(13, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? VS.Color.accent : VS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
