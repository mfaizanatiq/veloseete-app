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
        static let glass: CGFloat = 24
        /// web `rounded-2xl` / glass-frosted
        static let card: CGFloat = 16
        static let metric: CGFloat = 12
        static let input: CGFloat = 16
        static let pill: CGFloat = 999
        static let sheet: CGFloat = 32
    }

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let pageInset: CGFloat = 16
        static let sheetInset: CGFloat = 20
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

/// Soft card surface — olive base + light sheen + hairline (glass dialed back).
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = VS.Radius.card
    var elevated: Bool = false
    var bordered: Bool = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(elevated ? 0.05 : 0.03),
                                    VS.Color.bgSecondary,
                                    VS.Color.bgSecondary.opacity(0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(elevated ? 0.08 : 0.04),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.overlay)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    VS.Color.accent.opacity(elevated ? 0.04 : 0.02),
                                    .clear
                                ],
                                center: .topTrailing,
                                startRadius: 4,
                                endRadius: 140
                            )
                        )
                }
            }
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: elevated ? 14 : 8, x: 0, y: elevated ? 6 : 4)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
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

/// web input `#020206` with optional lime focus ring
struct VSInputField: ViewModifier {
    var focused: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: VS.Radius.input, style: .continuous)
                    .fill(VS.Color.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VS.Radius.input, style: .continuous)
                    .strokeBorder(
                        focused ? VS.Color.accent : Color.white.opacity(0.06),
                        lineWidth: focused ? 1 : 1
                    )
            )
            .shadow(color: focused ? VS.Color.accent.opacity(0.2) : .clear, radius: 6, y: 0)
    }
}

/// Lime primary CTA with depth like web `shadow-lg`
struct PrimaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .shadow(color: VS.Color.accent.opacity(configuration.isPressed ? 0.15 : 0.35), radius: configuration.isPressed ? 8 : 16, y: configuration.isPressed ? 2 : 6)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                    .fill(VS.Color.accent.opacity(isEnabled ? 1 : 0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isEnabled ? 0.25 : 0.08), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
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

    /// Standard presentation chrome shared by all sheets and modals.
    func veloseeteSheet() -> some View {
        presentationBackground(VS.Color.bgPrimary)
            .presentationCornerRadius(VS.Radius.sheet)
            .presentationDragIndicator(.visible)
    }
}

/// Page chrome: `#0B0E0B` + grain (web `body::after`) + soft vertical depth
struct VeloseeteBackground: View {
    var body: some View {
        ZStack {
            VS.Color.bgPrimary.ignoresSafeArea()

            // Soft vertical atmosphere (not flat void)
            LinearGradient(
                colors: [
                    Color(hex: 0x141A12),
                    VS.Color.bgPrimary,
                    Color(hex: 0x080A08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Lime wash top-right — subtle brand atmosphere
            RadialGradient(
                colors: [VS.Color.accent.opacity(0.04), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Canvas { context, size in
                let step: CGFloat = 2
                var path = Path()
                var x: CGFloat = 0
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(.white.opacity(0.02)), lineWidth: 0.5)

                for i in 0..<500 {
                    let nx = CGFloat((i * 37) % 220) / 220 * size.width
                    let ny = CGFloat((i * 91) % 220) / 220 * size.height
                    let r = CGFloat((i % 3) + 1) * 0.35
                    context.fill(
                        Path(ellipseIn: CGRect(x: nx, y: ny, width: r, height: r)),
                        with: .color(.white.opacity(0.045))
                    )
                }
            }
            .ignoresSafeArea()
            .opacity(0.35)
            .allowsHitTesting(false)
            .blendMode(.overlay)
        }
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
