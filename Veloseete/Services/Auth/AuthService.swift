import Foundation
import Combine
import UIKit
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
@preconcurrency import UserNotifications

enum AuthProviderKind: String, CaseIterable, Identifiable {
    case apple = "apple.com"
    case google = "google.com"
    case password = "password"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .password: return "Email"
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// Web OAuth client from Firebase (google.com IdP) — required so Google ID tokens are accepted by Firebase Auth.
    private static let googleServerClientID =
        "1090690719538-fh4fnp8n41i6pc7holn24gei5hm64k58.apps.googleusercontent.com"

    @Published private(set) var user: User?
    @Published private(set) var linkedProviders: [AuthProviderKind] = []
    @Published private(set) var isCheckingAuth = true
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// Set when Apple/Google hits an existing email account — sign in with email to auto-link.
    @Published private(set) var pendingLinkEmail: String?
    @Published var infoMessage: String?

    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private var pendingLinkCredential: AuthCredential?

    /// True while an Apple/Google credential is waiting to attach after email sign-in.
    var pendingLinkCredentialActive: Bool { pendingLinkCredential != nil }

    private init() {
        configureGoogleSignIn()
        // Keychain restore is synchronous — don't wait on the network for first paint.
        applyUser(Auth.auth().currentUser)
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.applyUser(user)
                self?.isCheckingAuth = false
            }
        }
        // Auth listener can delay on a slow network — don't hold the splash forever.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.isCheckingAuth else { return }
            self.applyUser(Auth.auth().currentUser)
            self.isCheckingAuth = false
            print("[Auth] Timed out waiting for auth listener — proceeding with cached session")
        }
    }

    var isAuthenticated: Bool { user != nil }
    var userId: String? { user?.uid }

    func isLinked(_ provider: AuthProviderKind) -> Bool {
        linkedProviders.contains(provider)
    }

    // MARK: - Email

    func signIn(email: String, password: String) async throws {
        try await runAuth {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            try await ensureUserDocument(for: result.user, displayNameHint: nil)
            try await finishPendingLinkIfNeeded(for: result.user)
            applyUser(Auth.auth().currentUser)
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        try await runAuth {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
            // Prefer ensureUserDocument so a transient Firestore miss is retried
            // and displayName fallbacks stay consistent with Apple/Google first sign-in.
            try await ensureUserDocument(for: result.user, displayNameHint: displayName)
            try await finishPendingLinkIfNeeded(for: result.user)
            applyUser(Auth.auth().currentUser)
        }
    }

    func resetPassword(email: String) async throws {
        try await runAuth {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        }
    }

    // MARK: - Apple

    func startAppleSignIn() -> String {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        return Self.sha256(nonce)
    }

    func completeAppleSignIn(authorization: ASAuthorization, linking: Bool = false) async throws {
        try await runAuth {
            guard
                let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = apple.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                throw AuthServiceError.invalidAppleCredential
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: apple.fullName
            )

            let preferredName = [
                apple.fullName?.givenName,
                apple.fullName?.familyName
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if linking {
                try await linkCredential(credential)
            } else {
                try await signIn(with: credential, displayNameHint: preferredName.isEmpty ? nil : preferredName)
            }
            currentNonce = nil
            applyUser(Auth.auth().currentUser)
        }
    }

    // MARK: - Google

    func signInWithGoogle(linking: Bool = false) async throws {
        try await runAuth {
            configureGoogleSignIn()
            guard let presenter = UIApplication.shared.veloseeteTopViewController else {
                throw AuthServiceError.missingPresenter
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthServiceError.invalidGoogleCredential
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let hint = result.user.profile?.name

            if linking {
                try await linkCredential(credential)
            } else {
                try await signIn(with: credential, displayNameHint: hint)
            }
            applyUser(Auth.auth().currentUser)
        }
    }

    // MARK: - Linking (signed-in account)

    func linkEmailPassword(email: String, password: String) async throws {
        try await runAuth {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await linkCredential(credential)
        }
    }

    func unlink(_ provider: AuthProviderKind) async throws {
        try await runAuth {
            guard let user = Auth.auth().currentUser else {
                throw AuthServiceError.notSignedIn
            }
            guard linkedProviders.count > 1 else {
                throw AuthServiceError.cannotUnlinkLastProvider
            }
            try await user.unlink(fromProvider: provider.rawValue)
            applyUser(Auth.auth().currentUser)
            infoMessage = "\(provider.title) disconnected."
        }
    }

    /// After signing in with the original method, attaches the Apple/Google credential that was pending.
    func finishPendingLink() async throws {
        guard let credential = pendingLinkCredential else { return }
        try await runAuth {
            guard let user = Auth.auth().currentUser else {
                throw AuthServiceError.notSignedIn
            }
            _ = try await user.link(with: credential)
            clearPendingLink()
            applyUser(Auth.auth().currentUser)
            infoMessage = "Accounts linked. You can use either sign-in next time."
        }
    }

    func clearPendingLink() {
        pendingLinkCredential = nil
        pendingLinkEmail = nil
    }

    func clearErrorMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    func signOut() throws {
        clearPendingLink()
        try? GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()

        // Drop session UI so the next account on this device cannot see it.
        // Pending drive reviews stay on disk for this uid and reload on sign-in.
        TripRecordingService.shared.detachSessionForSignOut()
        CarPlayWidgetStateStore.clearUserData()
        ProfileAvatarStore.shared.clearSession()
        VehiclePhotoStore.shared.clearSession()
        TripPermissionsStore.shared.clearSession()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        DataStore.shared.clear()
    }

    /// Deletes Firestore data + Firebase Auth user, then clears local state.
    ///
    /// Order matters: we refuse to wipe cloud data unless the session is fresh enough
    /// for Auth deletion (avoids erasing Firestore then failing on `requiresRecentLogin`).
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.notSignedIn
        }
        let uid = user.uid

        try await ensureRecentLoginForSensitiveAction(user)

        try await FirestoreRepository.shared.deleteAllUserData(userId: uid)

        try? ProfileAvatarStore.shared.remove(userId: uid)
        VehiclePhotoStore.shared.removeAll()
        TripRecordingService.shared.wipeLocalStateForAccountDeletion()
        CarPlayWidgetStateStore.clearUserData()
        TripPermissionsStore.shared.reset(for: uid)
        TripPermissionsStore.shared.clearSession()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        do {
            try await user.delete()
        } catch {
            let ns = error as NSError
            if AuthErrorCode(rawValue: ns.code) == .requiresRecentLogin {
                // Data is already wiped; sign out so a fresh sign-in can finish Auth removal if needed.
                clearPendingLink()
                try? GIDSignIn.sharedInstance.signOut()
                try? Auth.auth().signOut()
                DataStore.shared.clear()
                applyUser(nil)
                throw AuthServiceError.dataRemovedNeedsFreshSignIn
            }
            throw error
        }

        clearPendingLink()
        try? GIDSignIn.sharedInstance.signOut()
        DataStore.shared.clear()
        applyUser(nil)
    }

    /// Firebase requires a recent sign-in for account deletion. Check ID-token `authDate`
    /// before touching Firestore so a stale session cannot orphan the Auth user after a wipe.
    private func ensureRecentLoginForSensitiveAction(_ user: User) async throws {
        let token = try await user.getIDTokenResult(forcingRefresh: true)
        let age = Date().timeIntervalSince(token.authDate)
        // Firebase typically requires authentication within the last few minutes.
        if age > 4 * 60 {
            throw AuthServiceError.requiresRecentLogin
        }
    }

    // MARK: - Internals

    private func signIn(with credential: AuthCredential, displayNameHint: String?) async throws {
        do {
            let result = try await Auth.auth().signIn(with: credential)
            try await ensureUserDocument(for: result.user, displayNameHint: displayNameHint)
        } catch {
            try await handleSignInCollision(error, credential: credential)
        }
    }

    private func linkCredential(_ credential: AuthCredential) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.notSignedIn
        }
        do {
            _ = try await user.link(with: credential)
            applyUser(Auth.auth().currentUser)
            infoMessage = "Account linked successfully."
        } catch {
            let ns = error as NSError
            if AuthErrorCode(rawValue: ns.code) == .credentialAlreadyInUse {
                throw AuthServiceError.credentialAlreadyLinkedElsewhere
            }
            throw error
        }
    }

    private func finishPendingLinkIfNeeded(for user: User) async throws {
        guard let credential = pendingLinkCredential else { return }
        do {
            _ = try await user.link(with: credential)
            clearPendingLink()
            applyUser(Auth.auth().currentUser)
            infoMessage = "Accounts linked. You can use either sign-in next time."
        } catch {
            // Already linked or incompatible — clear pending so the user isn't stuck.
            clearPendingLink()
            let ns = error as NSError
            if AuthErrorCode(rawValue: ns.code) != .providerAlreadyLinked {
                throw error
            }
        }
    }

    private func handleSignInCollision(_ error: Error, credential: AuthCredential) async throws {
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain else { throw error }

        switch AuthErrorCode(rawValue: ns.code) {
        case .accountExistsWithDifferentCredential, .emailAlreadyInUse, .credentialAlreadyInUse:
            pendingLinkCredential = credential
            pendingLinkEmail = (ns.userInfo["FIRAuthErrorUserInfoEmailKey"] as? String)
                ?? (ns.userInfo["AuthErrorUserInfoEmailKey"] as? String)
            throw AuthServiceError.needsLinkWithExistingAccount(email: pendingLinkEmail)
        default:
            throw error
        }
    }

    private func ensureUserDocument(for user: User, displayNameHint: String?) async throws {
        let hint = displayNameHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = user.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let emailLocal = user.email?.split(separator: "@").first.map(String.init)
        let resolved = [hint, fallback, emailLocal, "Driver"]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? "Driver"

        var existing = try? await FirestoreRepository.shared.fetchUser(userId: user.uid)
        if existing == nil {
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    try await FirestoreRepository.shared.createUserDocument(
                        userId: user.uid,
                        userName: resolved,
                        currency: "QAR"
                    )
                    lastError = nil
                    existing = try? await FirestoreRepository.shared.fetchUser(userId: user.uid)
                    if existing != nil { break }
                } catch {
                    lastError = error
                    print("[Auth] createUserDocument attempt \(attempt) failed: \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
                }
            }
            if existing == nil, let lastError {
                throw lastError
            }
        }

        if (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let change = user.createProfileChangeRequest()
            change.displayName = resolved
            try? await change.commitChanges()
        }
    }

    private func applyUser(_ user: User?) {
        self.user = user
        linkedProviders = (user?.providerData ?? []).compactMap {
            AuthProviderKind(rawValue: $0.providerID)
        }
    }

    private func configureGoogleSignIn() {
        let clientID = FirebaseApp.app()?.options.clientID
            ?? Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let clientID, !clientID.isEmpty else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: Self.googleServerClientID
        )
    }

    private func runAuth(_ work: () async throws -> Void) async throws {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }
        do {
            try await work()
        } catch let error as AuthServiceError {
            errorMessage = error.localizedDescription
            throw error
        } catch {
            errorMessage = Self.mapError(error)
            throw error
        }
    }

    private static func mapError(_ error: Error) -> String {
        if let authError = error as? AuthServiceError {
            return authError.localizedDescription
        }
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain else {
            return error.localizedDescription
        }
        switch AuthErrorCode(rawValue: ns.code) {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found with this email."
        case .emailAlreadyInUse:
            return "An account with this email already exists. Sign in, then link Apple or Google in Profile."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .networkError:
            return "Network error. Check your connection."
        case .providerAlreadyLinked:
            return "That sign-in method is already connected."
        case .credentialAlreadyInUse:
            return "That Apple/Google account is already linked to another Veloseete user."
        default:
            return error.localizedDescription
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var byte: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
                return byte
            }
            for random in randoms {
                if remaining == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthServiceError: LocalizedError {
    case invalidAppleCredential
    case invalidGoogleCredential
    case missingPresenter
    case notSignedIn
    case cannotUnlinkLastProvider
    case credentialAlreadyLinkedElsewhere
    case needsLinkWithExistingAccount(email: String?)
    case requiresRecentLogin
    /// Cloud data wiped, but Auth deletion still needs a fresh sign-in.
    case dataRemovedNeedsFreshSignIn

    var errorDescription: String? {
        switch self {
        case .invalidAppleCredential:
            return "Apple Sign In didn’t return a valid credential. Try again."
        case .invalidGoogleCredential:
            return "Google Sign In didn’t return a valid credential. Try again."
        case .missingPresenter:
            return "Couldn’t present Google Sign In. Try again from the sign-in screen."
        case .notSignedIn:
            return "Sign in first, then link another method."
        case .cannotUnlinkLastProvider:
            return "Keep at least one sign-in method on your account."
        case .credentialAlreadyLinkedElsewhere:
            return "That Apple/Google account is already used by another Veloseete login."
        case .needsLinkWithExistingAccount(let email):
            if let email, !email.isEmpty {
                return "An account already exists for \(email). Sign in with that email and password to link Apple/Google."
            }
            return "An account already exists with this email. Sign in with email and password to link Apple/Google."
        case .requiresRecentLogin:
            return "For security, sign out, sign back in, then delete your account again. Nothing was removed yet."
        case .dataRemovedNeedsFreshSignIn:
            return "Your garage and cloud data were removed. Sign in once more if the account still appears, then delete again to finish closing it."
        }
    }
}

extension UIApplication {
    var veloseeteTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .veloseeteTopMost()
    }
}

private extension UIViewController {
    func veloseeteTopMost() -> UIViewController {
        if let presented = presentedViewController { return presented.veloseeteTopMost() }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.veloseeteTopMost()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.veloseeteTopMost()
        }
        return self
    }
}
