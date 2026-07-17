import Combine
import Foundation

@MainActor
final class TripPermissionsStore: ObservableObject {
    static let shared = TripPermissionsStore()

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hasCompletedOnboarding = "tripPermissions.hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func complete() {
        hasCompletedOnboarding = true
    }
}
