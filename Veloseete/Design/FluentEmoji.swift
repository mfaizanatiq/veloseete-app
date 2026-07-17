import SwiftUI
import UIKit

/// Microsoft Fluent 3D emoji assets (bundled under Resources/FluentEmoji).
/// Unicode glyphs are still stored in Firestore for web parity; iOS renders the 3D PNGs.
enum FluentEmoji {
    /// Asset filename (without .png) for a unicode emoji glyph.
    static func assetName(for emoji: String) -> String? {
        switch normalize(emoji) {
        case "🚗": return "car"
        case "🚙": return "suv"
        case "🚕": return "taxi"
        case "🚌": return "bus"
        case "🚐": return "minibus"
        case "🏎": return "racing_car"
        case "🚓": return "police_car"
        case "🚑": return "ambulance"
        case "🚒": return "fire_engine"
        case "🚚": return "delivery_truck"
        case "🚛": return "articulated_lorry"
        case "🛻": return "pickup"
        case "🏍": return "motorcycle"
        case "🛵": return "motor_scooter"
        case "🚜": return "tractor"
        case "🚎": return "trolleybus"
        case "⛽": return "fuel_pump"
        case "👋": return "waving_hand"
        case "⚡": return "high_voltage"
        case "🛣": return "motorway"
        case "💧": return "droplet"
        case "🏆": return "trophy"
        case "✨": return "sparkles"
        case "🎯": return "direct_hit"
        case "🔧": return "wrench"
        case "🩺": return "stethoscope"
        default: return nil
        }
    }

    static func uiImage(for emoji: String) -> UIImage? {
        guard let name = assetName(for: emoji) else { return nil }
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "FluentEmoji") {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(named: name)
    }

    private static func normalize(_ emoji: String) -> String {
        emoji
            .replacingOccurrences(of: "\u{FE0F}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct FluentEmojiView: View {
    let emoji: String
    var size: CGFloat = 24

    var body: some View {
        if let image = FluentEmoji.uiImage(for: emoji) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityLabel(Text(emoji))
        } else {
            Text(emoji)
                .font(.system(size: size * 0.85))
                .frame(width: size, height: size)
        }
    }
}
