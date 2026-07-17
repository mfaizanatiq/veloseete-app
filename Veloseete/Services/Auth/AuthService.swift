import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var user: User?
    @Published private(set) var isCheckingAuth = true
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isCheckingAuth = false
            }
        }
    }

    var isAuthenticated: Bool { user != nil }
    var userId: String? { user?.uid }

    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = Self.mapError(error)
            throw error
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()

            try await FirestoreRepository.shared.createUserDocument(
                userId: result.user.uid,
                userName: displayName,
                currency: "QAR"
            )
        } catch {
            errorMessage = Self.mapError(error)
            throw error
        }
    }

    func resetPassword(email: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = Self.mapError(error)
            throw error
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
        DataStore.shared.clear()
    }

    private static func mapError(_ error: Error) -> String {
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
            return "An account with this email already exists."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .networkError:
            return "Network error. Check your connection."
        default:
            return error.localizedDescription
        }
    }
}
