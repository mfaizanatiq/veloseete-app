import UIKit

/// Maps Tracky’s mood to the home-screen app icon.
/// Chill (and locked) use the primary eyes-on-lime mark; other moods use
/// `AppIcon-{mood}` alternate icons from the asset catalog.
enum TrackyAppIcon {
    private static let storageKey = "veloseete.tracky.mood"

    /// Alternate icon set name, or `nil` for the primary AppIcon.
    static func alternateIconName(for mood: TrackyMood) -> String? {
        switch mood {
        case .chill, .locked:
            return nil
        case .proud, .fueled, .focused, .night, .dawn, .grit, .legend, .cozy:
            return "AppIcon-\(mood.rawValue)"
        }
    }

    static func apply(mood: TrackyMood) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = alternateIconName(for: mood)
        let current = UIApplication.shared.alternateIconName
        guard current != target else { return }
        UIApplication.shared.setAlternateIconName(target) { error in
            if let error {
                #if DEBUG
                print("TrackyAppIcon: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Call on launch / foreground so the icon matches saved mood.
    static func syncFromStorage() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? TrackyMood.chill.rawValue
        apply(mood: TrackyMood(rawValue: raw) ?? .chill)
    }
}
