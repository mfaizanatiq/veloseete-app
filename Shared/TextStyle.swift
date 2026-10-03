import SwiftUI

/// Veloseete's type scale — the only way text gets a font, in the app and its widgets.
///
/// Large, airy display numbers are the brand: this scale keeps them big and consistent,
/// it never shrinks them. Tokens fix the *size*; weight stays a per-use choice.
/// App code reaches it as `VS.TextStyle`.
enum VSTextStyle {
    // Display — Space Grotesk, tabular digits so live numbers don't jitter.
    // Fixed size: already huge, and scaling them with Dynamic Type breaks layouts.
    /// 64 — odometer, fuel dashboard hero.
    static func hero(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { display(64, weight) }
    /// 48 — drive totals, trip distance.
    static func display(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { display(48, weight) }
    /// 40 — onboarding and secondary heroes.
    static func displaySmall(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { display(40, weight) }

    // Titles & headings — Space Grotesk.
    /// 32 — screen titles.
    static func largeTitle(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(32, weight: weight) }
    /// 28 — sheet titles, big secondary numbers.
    static func title(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(28, weight: weight) }
    /// 22 — card titles, car name.
    static func title2(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(22, weight: weight) }
    /// 18 — CTAs, units beside display numbers.
    static func title3(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(18, weight: weight) }
    /// 16 — row titles, stat values.
    static func headline(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(16, weight: weight) }
    /// 14 — section headers, chip titles.
    static func subheadline(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(14, weight: weight) }
    /// 12 — compact pill / badge titles.
    static func tag(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(12, weight: weight) }
    /// 24 — unit next to a `hero` number.
    static func heroUnit(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { spaceGrotesk(24, weight: weight) }

    // Text — Inter.
    /// 16 — prominent body.
    static func bodyLarge(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { inter(16, weight: weight) }
    /// 15 — paragraphs.
    static func body(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { inter(15, weight: weight) }
    /// 14 — secondary paragraphs.
    static func callout(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { inter(14, weight: weight) }
    /// 13 — captions, supporting lines.
    static func footnote(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { inter(13, weight: weight) }
    /// 12 — meta lines (time · duration).
    static func caption(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { inter(12, weight: weight) }
    /// 11 — smallest readable text; badges.
    static func caption2(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { inter(11, weight: weight) }

    // Labels — SF Mono. One overline style everywhere.
    /// 10 — uppercase overlines and stat labels.
    static func label(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { sfMono(10, weight: weight) }
    /// 12 — mono figures that need more presence.
    static func labelLarge(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { sfMono(12, weight: weight) }

    /// Text drawn *as part of artwork* that scales with its container (badge faces).
    /// Not for UI text — use a scale token.
    static func artwork(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
        SwiftUI.Font.custom(spaceGroteskName(weight), fixedSize: size)
    }

    // MARK: Font construction (private — the scale above is the only public API)

    private static func display(_ size: CGFloat, _ weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
        SwiftUI.Font.custom(spaceGroteskName(weight), fixedSize: size).monospacedDigit()
    }

    private static func spaceGrotesk(_ size: CGFloat, weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
        .custom(spaceGroteskName(weight), size: size)
    }

    private static func inter(_ size: CGFloat, weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Inter-Bold"
        case .semibold: name = "Inter-SemiBold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size)
    }

    private static func sfMono(_ size: CGFloat, weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func spaceGroteskName(_ weight: SwiftUI.Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "SpaceGrotesk-Bold"
        case .semibold: return "SpaceGrotesk-SemiBold"
        case .medium: return "SpaceGrotesk-Medium"
        default: return "SpaceGrotesk-Regular"
        }
    }
}
