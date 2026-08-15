import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showPassword = false
    @State private var showForgot = false
    @State private var resetEmail = ""
    @State private var resetSuccess = false
    @State private var localError = ""
    @State private var appleNonceHash = ""
    @State private var legalDocument: AppLegal.Document?
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password, reset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Veloseete")
                        .font(VS.Typography.heading(32, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)

                    Text(isSignUp ? "Create your account" : "Welcome back")
                        .font(VS.Typography.body(15))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                .padding(.top, 48)

                socialButtons

                HStack(spacing: 12) {
                    Rectangle().fill(VS.Color.divider).frame(height: 1)
                    Text("or email")
                        .font(VS.Typography.body(12, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)
                    Rectangle().fill(VS.Color.divider).frame(height: 1)
                }

                if auth.pendingLinkEmail != nil || auth.errorMessage?.contains("link") == true {
                    pendingLinkBanner
                }

                VStack(spacing: 14) {
                    if isSignUp {
                        authField(
                            title: "Name",
                            text: $displayName,
                            field: .name,
                            placeholder: "Your name"
                        )
                    }

                    authField(
                        title: "Email",
                        text: $email,
                        field: .email,
                        placeholder: "you@email.com",
                        keyboard: .emailAddress
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(VS.Typography.body(12, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)

                        HStack {
                            Group {
                                if showPassword {
                                    TextField("", text: $password)
                                } else {
                                    SecureField("", text: $password)
                                }
                            }
                            .focused($focusedField, equals: .password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .font(VS.Typography.body(16))
                            .foregroundStyle(VS.Color.textPrimary)

                            Button {
                                showPassword.toggle()
                            } label: {
                                VSIcon(
                                    icon: showPassword ? .eyeSlash : .eye,
                                    size: 18,
                                    weight: .regular,
                                    tint: VS.Color.textTertiary
                                )
                            }
                        }
                        .vsInputField()
                    }
                }

                if !localError.isEmpty || auth.errorMessage != nil {
                    Text(localError.isEmpty ? (auth.errorMessage ?? "") : localError)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let info = auth.infoMessage {
                    Text(info)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.success)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if auth.isLoading {
                            ProgressView().tint(VS.Color.navPill)
                        }
                        Text(emailPrimaryTitle)
                            .font(VS.Typography.heading(17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VS.Color.accent)
                    .foregroundStyle(VS.Color.navPill)
                    .clipShape(RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                }
                .disabled(auth.isLoading)
                .buttonStyle(ScaleButtonStyle())

                if !isSignUp {
                    Button("Forgot password?") {
                        resetEmail = email
                        showForgot = true
                    }
                    .font(VS.Typography.body(14, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSignUp.toggle()
                        localError = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundStyle(VS.Color.textTertiary)
                        Text(isSignUp ? "Sign In" : "Sign Up")
                            .foregroundStyle(VS.Color.accent)
                            .fontWeight(.semibold)
                    }
                    .font(VS.Typography.body(14))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

                LegalLinksRow { legalDocument = $0 }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .veloseetePage()
        .sheet(isPresented: $showForgot) {
            forgotSheet
        }
        .sheet(item: $legalDocument) { doc in
            LegalDocumentView(document: doc)
        }
        .onAppear {
            if let pending = auth.pendingLinkEmail, email.isEmpty {
                email = pending
            }
        }
    }

    private var emailPrimaryTitle: String {
        if auth.pendingLinkEmail != nil {
            return isSignUp ? "Sign up & link" : "Sign in & link"
        }
        return isSignUp ? "Sign Up" : "Sign In"
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                appleNonceHash = auth.startAppleSignIn()
                request.requestedScopes = [.fullName, .email]
                request.nonce = appleNonceHash
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
            .disabled(auth.isLoading)

            Button {
                Task { await handleGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Continue with Google")
                        .font(VS.Typography.heading(16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(VS.Color.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                        .strokeBorder(VS.Color.divider, lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(auth.isLoading)
        }
    }

    private var pendingLinkBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Link your existing account")
                .font(VS.Typography.heading(14))
                .foregroundStyle(VS.Color.textPrimary)
            Text(
                auth.pendingLinkEmail.map {
                    "Sign in with \($0) below — Apple/Google will attach to this account."
                } ?? "Sign in with your email below — Apple/Google will attach to this account."
            )
            .font(VS.Typography.body(12))
            .foregroundStyle(VS.Color.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VS.Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous))
    }

    private var forgotSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reset password")
                    .font(VS.Typography.heading(22))
                Text("We'll send a reset link to your email.")
                    .font(VS.Typography.body(14))
                    .foregroundStyle(VS.Color.textSecondary)

                authField(title: "Email", text: $resetEmail, field: .reset, placeholder: "you@email.com", keyboard: .emailAddress)

                if resetSuccess {
                    Text("Check your inbox for the reset link.")
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.success)
                }

                Button {
                    Task {
                        do {
                            try await auth.resetPassword(email: resetEmail.trimmingCharacters(in: .whitespaces))
                            resetSuccess = true
                        } catch {
                            localError = auth.errorMessage ?? "Could not send reset email."
                        }
                    }
                } label: {
                    Text("Send reset link")
                        .font(VS.Typography.heading(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(VS.Color.accent)
                        .foregroundStyle(VS.Color.navPill)
                        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous))
                }

                Spacer()
            }
            .padding(20)
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { showForgot = false }
                }
            }
        }
        .presentationDetents([.medium])
        .veloseeteSheet()
    }

    private func authField(
        title: String,
        text: Binding<String>,
        field: Field,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)

            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(VS.Typography.body(16))
                .foregroundStyle(VS.Color.textPrimary)
                .vsInputField()
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        localError = ""
        switch result {
        case .success(let authorization):
            do {
                try await auth.completeAppleSignIn(authorization: authorization)
            } catch {
                if case AuthServiceError.needsLinkWithExistingAccount(let pending) = error,
                   let pending, email.isEmpty {
                    email = pending
                }
            }
        case .failure(let error):
            let ns = error as NSError
            if ns.code == ASAuthorizationError.canceled.rawValue { return }
            localError = error.localizedDescription
        }
    }

    private func handleGoogle() async {
        localError = ""
        do {
            try await auth.signInWithGoogle()
        } catch {
            if case AuthServiceError.needsLinkWithExistingAccount(let pending) = error,
               let pending, email.isEmpty {
                email = pending
            }
        }
    }

    private func submit() async {
        localError = ""
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            localError = "Please enter both email and password."
            return
        }
        if isSignUp {
            guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                localError = "Please enter your name."
                return
            }
            guard password.count >= 6 else {
                localError = "Password must be at least 6 characters long."
                return
            }
            do {
                try await auth.signUp(
                    email: trimmedEmail,
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespaces)
                )
            } catch {}
        } else {
            do {
                try await auth.signIn(email: trimmedEmail, password: password)
            } catch {}
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
