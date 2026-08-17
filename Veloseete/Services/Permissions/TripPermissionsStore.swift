import Combine
import Foundation

@MainActor
final class TripPermissionsStore: ObservableObject {
    static let shared = TripPermissionsStore()

    @Published private(set) var hasCompletedOnboarding: Bool = false

    private let defaults: UserDefaults
    private var boundUserId: String?

    private enum Keys {
        /// Legacy device-global flag (pre per-account scoping).
        static let legacyHasCompletedOnboarding = "tripPermissions.hasCompletedOnboarding"
        static func completed(for userId: String) -> String {
            "tripPermissions.hasCompletedOnboarding.\(userId)"
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Bind onboarding completion to the signed-in account so another login
    /// on this device does not inherit (or skip) permissions onboarding.
    func bind(userId: String?) {
        boundUserId = userId
        guard let userId else {
            hasCompletedOnboarding = false
            return
        }

        let key = Keys.completed(for: userId)
        if defaults.object(forKey: key) != nil {
            hasCompletedOnboarding = defaults.bool(forKey: key)
            return
        }

        // One-time migrate: if this device already completed onboarding before
        // per-uid keys existed, credit the first account that signs in.
        if defaults.bool(forKey: Keys.legacyHasCompletedOnboarding) {
            defaults.set(true, forKey: key)
            defaults.removeObject(forKey: Keys.legacyHasCompletedOnboarding)
            hasCompletedOnboarding = true
            return
        }

        hasCompletedOnboarding = false
    }

    func complete() {
        guard let userId = boundUserId else {
            hasCompletedOnboarding = true
            return
        }
        defaults.set(true, forKey: Keys.completed(for: userId))
        hasCompletedOnboarding = true
    }

    /// Clears the in-memory flag for the signed-out session (disk keys stay per uid).
    func clearSession() {
        boundUserId = nil
        hasCompletedOnboarding = false
    }

    /// Removes the stored completion flag when the account is deleted.
    func reset(for userId: String) {
        defaults.removeObject(forKey: Keys.completed(for: userId))
        if boundUserId == userId {
            hasCompletedOnboarding = false
        }
    }
}
