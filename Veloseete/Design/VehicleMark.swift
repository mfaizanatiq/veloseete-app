import SwiftUI
import UIKit

/// Common car paint colours. Assets stay brand-lime; tint is applied at render time.
/// Nil / unknown / `.brand` keeps the natural Veloseete lime with no filter.
enum VehiclePaintColor: String, CaseIterable, Identifiable, Equatable {
    case brand
    case white
    case black
    case silver
    case gray
    case red
    case blue
    case navy
    case green
    case yellow
    case orange
    case brown
    case beige

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brand: return "Brand"
        case .white: return "White"
        case .black: return "Black"
        case .silver: return "Silver"
        case .gray: return "Gray"
        case .red: return "Red"
        case .blue: return "Blue"
        case .navy: return "Navy"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .brown: return "Brown"
        case .beige: return "Beige"
        }
    }

    /// Swatch shown in the colour picker (not the filtered asset).
    var swatch: Color {
        switch self {
        case .brand: return VS.Color.accent
        case .white: return Color(hex: 0xF4F4F2)
        case .black: return Color(hex: 0x1A1A1A)
        case .silver: return Color(hex: 0xC5C8CE)
        case .gray: return Color(hex: 0x6B7280)
        case .red: return Color(hex: 0xDC2626)
        case .blue: return Color(hex: 0x2563EB)
        case .navy: return Color(hex: 0x1E3A5F)
        case .green: return Color(hex: 0x166534)
        case .yellow: return Color(hex: 0xEAB308)
        case .orange: return Color(hex: 0xEA580C)
        case .brown: return Color(hex: 0x7C4A2D)
        case .beige: return Color(hex: 0xD4C4A8)
        }
    }

    static func resolve(_ stored: String?) -> VehiclePaintColor {
        guard let raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .brand
        }
        return VehiclePaintColor(rawValue: raw) ?? .brand
    }

    /// Default paint when no car is in the garage yet.
    static let defaultMapPaint: VehiclePaintColor = .brand

    /// Brand lime hue in degrees — source of the asset paint.
    fileprivate static let brandHueDegrees: Double = {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: 217 / 255, green: 252 / 255, blue: 85 / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h) * 360
    }()

    fileprivate var hueRotationDegrees: Double {
        switch self {
        case .brand, .white, .black, .silver, .gray, .beige:
            return 0
        case .red: return 0 - Self.brandHueDegrees
        case .orange: return 28 - Self.brandHueDegrees
        case .yellow: return 50 - Self.brandHueDegrees
        case .green: return 140 - Self.brandHueDegrees
        case .blue: return 215 - Self.brandHueDegrees
        case .navy: return 228 - Self.brandHueDegrees
        case .brown: return 30 - Self.brandHueDegrees
        }
    }

    fileprivate var saturationFactor: Double {
        switch self {
        case .brand: return 1
        case .white: return 0.06
        case .black: return 0.22
        case .silver: return 0.1
        case .gray: return 0.16
        case .beige: return 0.28
        case .brown: return 0.75
        case .navy: return 0.9
        case .green: return 0.85
        case .red, .blue, .yellow, .orange: return 1.12
        }
    }

    fileprivate var brightnessDelta: Double {
        switch self {
        case .brand: return 0
        case .white: return 0.4
        case .black: return -0.44
        case .silver: return 0.2
        case .gray: return -0.06
        case .beige: return 0.18
        case .brown: return -0.12
        case .navy: return -0.18
        case .green: return -0.1
        default: return 0
        }
    }
}

private struct VehiclePaintFilter: ViewModifier {
    let paint: VehiclePaintColor

    func body(content: Content) -> some View {
        if paint == .brand {
            content
        } else {
            content
                .hueRotation(.degrees(paint.hueRotationDegrees))
                .saturation(paint.saturationFactor)
                .brightness(paint.brightnessDelta)
        }
    }
}

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

    /// Default puck when no car is in the garage yet.
    static let defaultMapStyle: VehicleMarkStyle = .sedan

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
/// Optional `paint` shifts hue/saturation on the same assets — no new images required.
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
    var paint: VehiclePaintColor = .brand

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
        .modifier(VehiclePaintFilter(paint: paint))
        .frame(width: size, height: size)
        .accessibilityLabel("\(paint.label) \(style.label)")
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
    private var glass: Color { paint == .brand ? VS.Color.accent.opacity(0.92) : paint.swatch.opacity(0.92) }
    private var accentSoft: Color { (paint == .brand ? VS.Color.accent : paint.swatch).opacity(0.55) }
    private var wheel: Color { Color(hex: 0x1A1C1A) }
    private var wheelRim: Color { (paint == .brand ? VS.Color.accent : paint.swatch).opacity(0.35) }
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
    var paint: VehiclePaintColor = .brand
    var action: () -> Void

    private let tile: CGFloat = 88
    private let mark: CGFloat = 76

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(spacing: 6) {
                VehicleMark(style: style, size: mark, paint: paint)
                    .frame(width: tile, height: tile)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(VS.Color.navPill.opacity(selected ? 0.92 : 0.72))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                selected ? VS.Color.accent : VS.Color.hairline.opacity(0.45),
                                lineWidth: selected ? 2.5 : 1
                            )
                    }
                    .shadow(color: selected ? VS.Color.accent.opacity(0.22) : .clear, radius: 10, y: 2)

                Text(style.label)
                    .font(VS.Typography.heading(12, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? VS.Color.accent : VS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: tile + 8)
            .scaleEffect(selected ? 1 : 0.9)
            .opacity(selected ? 1 : 0.5)
            .animation(.snappy(duration: 0.28), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Horizontal carousel — scroll to browse marks; selected item stays centred and focused.
struct VehicleMarkCarousel: View {
    @Binding var icon: String
    var paint: VehiclePaintColor = .brand
    var onSelect: (() -> Void)? = nil

    private var selectedStyle: VehicleMarkStyle {
        VehicleMarkStyle.resolve(icon)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(VehicleMarkStyle.selectable) { style in
                        VehicleMarkPickerCell(
                            style: style,
                            selected: selectedStyle == style,
                            paint: paint
                        ) {
                            icon = style.storageToken
                            onSelect?()
                            scrollTo(style, proxy: proxy)
                        }
                        .id(style)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onAppear {
                scrollTo(selectedStyle, proxy: proxy, animated: false)
            }
            .onChange(of: icon) { _, _ in
                scrollTo(selectedStyle, proxy: proxy)
            }
        }
        .padding(.horizontal, -4)
    }

    private func scrollTo(_ style: VehicleMarkStyle, proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.snappy(duration: 0.35)) {
                proxy.scrollTo(style, anchor: .center)
            }
        } else {
            proxy.scrollTo(style, anchor: .center)
        }
    }
}

/// Horizontal paint swatches — Brand (lime) first, then common car colours.
struct VehiclePaintSwatchRow: View {
    @Binding var paint: VehiclePaintColor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(VehiclePaintColor.allCases) { color in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        paint = color
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(color.swatch)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                Color.white.opacity(color == .white || color == .beige ? 0.35 : 0.18),
                                                lineWidth: 1
                                            )
                                    }
                                if paint == color {
                                    Circle()
                                        .strokeBorder(VS.Color.accent, lineWidth: 2.5)
                                        .frame(width: 42, height: 42)
                                }
                            }
                            .frame(width: 42, height: 42)

                            Text(color.label)
                                .font(VS.Typography.body(10, weight: paint == color ? .bold : .medium))
                                .foregroundStyle(paint == color ? VS.Color.accent : VS.Color.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(width: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.label)
                    .accessibilityAddTraits(paint == color ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}
