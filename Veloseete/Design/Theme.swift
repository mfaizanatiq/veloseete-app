import SwiftUI

/// Design tokens mirrored 1:1 from Velocity-app (`tailwind.config.ts` + `globals.css`)
enum VS {
    enum Color {
        static let bgPrimary = SwiftUI.Color(hex: 0x0B0E0B)
        static let bgSecondary = SwiftUI.Color(hex: 0x12160E)
        static let bgTertiary = SwiftUI.Color(hex: 0x2A2F4A)
        static let input = SwiftUI.Color(hex: 0x020206)
        static let accent = SwiftUI.Color(hex: 0xD9FC55)
        static let accentSecondary = SwiftUI.Color(hex: 0x5FED9A)
        static let textPrimary = SwiftUI.Color.white
        static let textSecondary = SwiftUI.Color(hex: 0xB8C5D6)
        static let textTertiary = SwiftUI.Color(hex: 0x7A8A9E)
        static let success = SwiftUI.Color(hex: 0x4ADE80)
        static let error = SwiftUI.Color(hex: 0xF87171)
        static let warning = SwiftUI.Color(hex: 0xFBBF24)
        static let routeEnd = SwiftUI.Color(hex: 0xFF6B4A)
        static let navPill = SwiftUI.Color(hex: 0x020206)
        static let navActive = SwiftUI.Color(hex: 0x101012)
        /// web `bg-white/5`
        static let metricInset = SwiftUI.Color.white.opacity(0.05)
        /// web `border-white/10`
        static let hairline = SwiftUI.Color.white.opacity(0.10)
        static let hairlineStrong = SwiftUI.Color.white.opacity(0.14)
        static let sheen = SwiftUI.Color.white.opacity(0.08)
        static let divider = SwiftUI.Color.white.opacity(0.08)
        static let chip = SwiftUI.Color.white.opacity(0.06)
        static let controlDisabled = SwiftUI.Color.white.opacity(0.04)
    }

    enum Radius {
        /// Soft glass surfaces
        static let glass: CGFloat = 32
        /// Primary cards / panels — squircle language from product refs
        static let card: CGFloat = 32
        /// Large floating drawers / map sheets
        static let panel: CGFloat = 36
        /// Nested metric tiles inside cards
        static let metric: CGFloat = 20
        static let input: CGFloat = 26
        static let pill: CGFloat = 999
        static let sheet: CGFloat = 40
        /// Selectable chips / segmented controls
        static let chip: CGFloat = 20
    }

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        /// Page vertical rhythm — between header, cards, and titled sections
        static let module: CGFloat = 28
        /// Alias used by tab page stacks
        static let floatStack: CGFloat = module
        /// Between major titled blocks (same as module for one consistent beat)
        static let section: CGFloat = module
        /// Title → content inside a section
        static let stack: CGFloat = 12
        /// Card internal padding
        static let card: CGFloat = 22
        /// Dense list / row vertical padding
        static let row: CGFloat = 14
        /// Narrow scrim between floating surfaces and the device frame
        static let frameGutter: CGFloat = 10
        /// Page content inset (matches floating scrim language)
        static let pageInset: CGFloat = 10
        static let sheetInset: CGFloat = 20
        /// Gap between sibling floating cards in a row
        static let gutter: CGFloat = 12
    }

    enum Typography {
        static func heading(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> Font {
            let name: String
            switch weight {
            case .bold, .heavy, .black: name = "SpaceGrotesk-Bold"
            case .semibold: name = "SpaceGrotesk-SemiBold"
            case .medium: name = "SpaceGrotesk-Medium"
            default: name = "SpaceGrotesk-Regular"
            }
            return .custom(name, size: size)
        }

        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> Font {
            let name: String
            switch weight {
            case .bold, .heavy, .black: name = "Inter-Bold"
            case .semibold: name = "Inter-SemiBold"
            case .medium: name = "Inter-Medium"
            default: name = "Inter-Regular"
            }
            return .custom(name, size: size)
        }

        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Flat card surface — solid fill, large radius, no ambient glass.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = VS.Radius.card
    var elevated: Bool = false
    var bordered: Bool = false

    private var fill: Color {
        elevated ? Color(hex: 0x1C1C1E) : Color(hex: 0x161618)
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// web metric tile: `bg-white/5 border border-white/10 rounded-xl`
struct MetricInset: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                    .fill(VS.Color.metricInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                    .strokeBorder(VS.Color.hairline, lineWidth: 1)
            )
    }
}

/// web input `#020206` with optional lime focus ring — large touch targets
struct VSInputField: ViewModifier {
    var focused: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: VS.Radius.input, style: .continuous)
                    .fill(VS.Color.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VS.Radius.input, style: .continuous)
                    .strokeBorder(
                        focused ? VS.Color.accent : Color.white.opacity(0.08),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
    }
}

/// Shared selectable chip — roomy for forms (fuel, garage, profile).
struct VSSelectableChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(title)
                .font(VS.Typography.body(15, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Capsule(style: .continuous).fill(selected ? VS.Color.accent : VS.Color.chip))
                .foregroundStyle(selected ? VS.Color.navPill : VS.Color.textSecondary)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selected ? Color.clear : VS.Color.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Lime track + black handle — white thumbs on accent look washed out.
struct VSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            toggleTrack(isOn: configuration.isOn)
                .onTapGesture {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.22)) {
                        configuration.isOn.toggle()
                    }
                }
                .accessibilityAddTraits(.isButton)
        }
    }

    private func toggleTrack(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? VS.Color.accent : Color.white.opacity(0.14))
                .frame(width: 52, height: 32)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? Color.clear : VS.Color.hairline, lineWidth: 1)
                )

            Circle()
                .fill(VS.Color.navPill)
                .frame(width: 26, height: 26)
                .padding(3)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 52, height: 32)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == VSToggleStyle {
    static var veloseete: VSToggleStyle { VSToggleStyle() }
}

/// Lime primary CTA — flat pill, no ambient glow stack.
struct PrimaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Canonical Veloseete primary action. Fuel established this visual language;
/// every feature uses this component instead of recreating a lime button.
struct PrimaryCTAButton: View {
    let title: String
    var icon: VSIconName? = nil
    var isLoading = false
    var isEnabled = true
    var action: () -> Void

    init(
        title: String = "+ Add Refuel",
        icon: VSIconName? = .gasPump,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView().tint(VS.Color.navPill)
                } else if let icon {
                    VSIcon(icon: icon, size: 22, weight: .fill, tint: VS.Color.navPill)
                }
                Text(title)
                    .font(VS.Typography.heading(18))
            }
            .foregroundStyle(VS.Color.navPill)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(VS.Color.accent.opacity(isEnabled ? 1 : 0.35))
            )
        }
        .buttonStyle(PrimaryCTAStyle())
        .disabled(!isEnabled || isLoading)
    }
}

extension View {
    func glassCard(radius: CGFloat = VS.Radius.card, elevated: Bool = false, bordered: Bool = true) -> some View {
        modifier(GlassCard(cornerRadius: radius, elevated: elevated, bordered: bordered))
    }

    func metricInset() -> some View {
        modifier(MetricInset())
    }

    func vsInputField(focused: Bool = false) -> some View {
        modifier(VSInputField(focused: focused))
    }

    /// Standard atmospheric surface for every full-screen app destination.
    func veloseetePage() -> some View {
        background { VeloseeteBackground() }
    }

    /// Float a surface inside the frame scrim (narrow gutter on all sides).
    func floatingInFrame(
        radius: CGFloat = VS.Radius.panel,
        bottomClearance: CGFloat = VS.Spacing.frameGutter
    ) -> some View {
        modifier(FloatingInFrame(radius: radius, bottomClearance: bottomClearance))
    }

    /// Standard presentation chrome shared by all sheets and modals.
    func veloseeteSheet() -> some View {
        presentationBackground(Color(hex: 0x0B0E0B))
            .presentationCornerRadius(VS.Radius.sheet)
            .presentationDragIndicator(.visible)
    }
}

/// Insets a panel so map / page chrome shows as a narrow scrim around it.
private struct FloatingInFrame: ViewModifier {
    var radius: CGFloat
    var bottomClearance: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .padding(.horizontal, VS.Spacing.frameGutter)
            .padding(.bottom, bottomClearance)
    }
}

/// Shared section title for tab screens — keeps vertical rhythm consistent.
struct VSSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Title + content with the shared section stack rhythm.
struct VSSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: title, subtitle: subtitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Page chrome — flat charcoal, no ambient wash.
struct VeloseeteBackground: View {
    var body: some View {
        VS.Color.bgPrimary.ignoresSafeArea()
    }
}

/// System toolbar close — lets iOS apply liquid glass; don’t wrap in custom chrome.
struct ModalCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
    }
}

/// Back control for pushed screens. Capsule chip so liquid-glass toolbar
/// circles can’t clip the title (e.g. “Driver” → “Dr”).
struct ModalBackButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(VS.Typography.body(15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(VS.Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(VS.Color.chip))
            .overlay(Capsule(style: .continuous).strokeBorder(VS.Color.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}
