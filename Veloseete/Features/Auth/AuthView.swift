import SwiftUI

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
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if auth.isLoading {
                            ProgressView().tint(VS.Color.navPill)
                        }
                        Text(isSignUp ? "Sign Up" : "Sign In")
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
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .veloseetePage()
        .sheet(isPresented: $showForgot) {
            forgotSheet
        }
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
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
