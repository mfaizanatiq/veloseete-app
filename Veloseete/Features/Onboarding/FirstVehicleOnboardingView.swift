import SwiftUI

/// First-run vehicle gate — welcome beat, then the existing 3-step garage wizard.
/// Matches the trip-permissions onboarding rhythm so new users don't land on a cold form.
struct FirstVehicleOnboardingView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case welcome
        case restore
        case setup
    }

    @State private var phase: Phase = .welcome
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var markPulse = false

    private var hasArchived: Bool { !store.archivedVehicles.isEmpty }

    var body: some View {
        ZStack {
            VeloseeteBackground()
            ambientGlow

            VStack(spacing: 0) {
                topBar

                Group {
                    switch phase {
                    case .welcome:
                        welcomePage
                    case .restore:
                        restorePage
                    case .setup:
                        GarageView(isFirstRun: true)
                    }
                }
                .id(phase)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    markPulse = true
                }
            }
        }
    }

    private var ambientGlow: some View {
        Circle()
            .fill(VS.Color.accent.opacity(0.10))
            .frame(width: 330, height: 330)
            .blur(radius: 90)
            .offset(x: 160, y: phase == .setup ? 280 : -160)
            .animation(.easeInOut(duration: 0.7), value: phase)
            .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image("VeloseeteMark")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            Spacer()

            if phase != .welcome {
                phaseDots
            }

            Menu {
                if let email = auth.user?.email {
                    Text(email)
                }
                if store.loadError != nil || !store.loadWarnings.isEmpty {
                    Button("Retry sync") {
                        Task {
                            if let uid = auth.userId {
                                await store.loadAll(userId: uid)
                            }
                        }
                    }
                }
                Button("Sign out", role: .destructive) {
                    try? auth.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
                    .frame(width: 44, height: 32, alignment: .trailing)
            }
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var phaseDots: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(phase == .restore || phase == .setup ? VS.Color.accent : Color.white.opacity(0.16))
                .frame(width: phase == .restore || phase == .setup ? 24 : 7, height: 7)
            if hasArchived {
                Capsule()
                    .fill(phase == .setup ? VS.Color.accent : Color.white.opacity(0.16))
                    .frame(width: phase == .setup ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: phase)
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)

            markVisual
                .frame(maxWidth: .infinity)
                .frame(height: 280)

            Spacer(minLength: 16)

            Text("START HERE")
                .font(VS.Typography.body(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(VS.Color.accent)

            Text("Add the car\nyou’ll track.")
                .font(VS.Typography.heading(39, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(VS.Color.textPrimary)
                .padding(.top, 10)

            Text("Nickname it, pick a mark, and Veloseete can remember every drive, fill, and service from here.")
                .font(VS.Typography.body(15))
                .foregroundStyle(VS.Color.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                PrimaryCTAButton(title: "Add your car", icon: nil) {
                    goToSetup()
                }

                if hasArchived {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                            phase = .restore
                        }
                    } label: {
                        Text("Restore an archived car")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private var markVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(VS.Color.divider, lineWidth: 1)
                }
                .rotationEffect(.degrees(-3))

            HStack(spacing: 18) {
                ForEach([VehicleMarkStyle.sedan, .suv, .sport], id: \.self) { style in
                    VehicleMark(style: style, size: 72)
                        .scaleEffect(markPulse && style == .suv ? 1.06 : 1)
                        .opacity(style == .suv ? 1 : 0.55)
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.horizontal, 8)
    }

    private var restorePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    phase = .welcome
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(VS.Typography.body(14, weight: .semibold))
                    .foregroundStyle(VS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 4)

            Text("RESTORE")
                .font(VS.Typography.body(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(VS.Color.accent)
                .padding(.horizontal, 24)
                .padding(.top, 22)

            Text("Bring a car back.")
                .font(VS.Typography.heading(32, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(VS.Color.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            Text("History stays intact — you only need to restore it to the garage.")
                .font(VS.Typography.body(15))
                .foregroundStyle(VS.Color.textSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            if let restoreError {
                Text(restoreError)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.error)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.archivedVehicles) { vehicle in
                        Button {
                            Task { await restore(vehicle.id) }
                        } label: {
                            HStack(spacing: 14) {
                                VehicleMark(style: VehicleMarkStyle.resolve(vehicle.icon), size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vehicle.nickname.isEmpty ? "\(vehicle.make) \(vehicle.model)" : vehicle.nickname)
                                        .font(VS.Typography.heading(17, weight: .bold))
                                        .foregroundStyle(VS.Color.textPrimary)
                                    Text("\(vehicle.make) \(vehicle.model)")
                                        .font(VS.Typography.body(13))
                                        .foregroundStyle(VS.Color.textTertiary)
                                }
                                Spacer()
                                if isRestoring {
                                    ProgressView().tint(VS.Color.accent)
                                } else {
                                    Text("Restore")
                                        .font(VS.Typography.body(13, weight: .semibold))
                                        .foregroundStyle(VS.Color.navPill)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(VS.Color.accent, in: Capsule())
                                }
                            }
                            .padding(14)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoring)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }

            PrimaryCTAButton(title: "Add a new car instead", icon: nil) {
                goToSetup()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func goToSetup() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            phase = .setup
        }
    }

    private func restore(_ vehicleId: String) async {
        restoreError = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restoreVehicle(vehicleId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            restoreError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Sync-failure recovery when the garage looks empty but load failed.
struct FirstVehicleSyncRecoveryView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var auth: AuthService
    let onRetry: () -> Void
    let onContinueEmpty: () -> Void

    var body: some View {
        ZStack {
            VeloseeteBackground()

            VStack(spacing: 0) {
                Spacer()

                Image("VeloseeteMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                Text("Couldn’t load your garage")
                    .font(VS.Typography.heading(28, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                Text(store.loadError ?? "Check your connection and try again.")
                    .font(VS.Typography.body(15))
                    .foregroundStyle(VS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                Spacer()

                VStack(spacing: 12) {
                    PrimaryCTAButton(title: "Retry", icon: nil, action: onRetry)

                    Button(action: onContinueEmpty) {
                        Text("Set up a new car")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Button("Sign out", role: .destructive) {
                        try? auth.signOut()
                    }
                    .font(VS.Typography.body(14, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
}
