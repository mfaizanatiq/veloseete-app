import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tripPermissionsStore: TripPermissionsStore
    @State private var showSlowLoadHint = false

    var body: some View {
        ZStack {
            Group {
                if auth.isCheckingAuth {
                    LoadingView(
                        message: showSlowLoadHint
                            ? "Still signing you in…"
                            : nil
                    )
                } else if !auth.isAuthenticated {
                    AuthView()
                } else if store.isLoading && !store.isLoaded {
                    LoadingView(
                        message: showSlowLoadHint
                            ? "Still reaching Veloseete.\nYou can retry if this is taking too long."
                            : nil,
                        retryTitle: showSlowLoadHint ? "Retry" : nil,
                        onRetry: showSlowLoadHint ? { Task { await reload() } } : nil
                    )
                } else if store.vehicles.isEmpty && store.isLoaded {
                    VStack(spacing: 0) {
                        if let loadError = store.loadError {
                            connectionBanner(loadError, retry: { Task { await reload() } })
                        } else if !store.loadWarnings.isEmpty {
                            connectionBanner(
                                store.loadWarnings.joined(separator: "\n"),
                                retry: { Task { await reload() } }
                            )
                        }
                        GarageView()
                    }
                } else if !tripPermissionsStore.hasCompletedOnboarding {
                    TripPermissionsOnboardingView()
                } else {
                    VStack(spacing: 0) {
                        if !store.loadWarnings.isEmpty, store.vehicles.isEmpty == false,
                           store.loadWarnings.contains(where: { $0.localizedCaseInsensitiveContains("timed out") || $0.localizedCaseInsensitiveContains("network") }) {
                            connectionBanner(
                                store.loadWarnings.joined(separator: "\n"),
                                retry: { Task { await reload() } }
                            )
                        }
                        MainTabShell()
                    }
                }
            }
        }
        .task(id: auth.user?.uid) {
            showSlowLoadHint = false
            guard let uid = auth.user?.uid else {
                store.clear()
                return
            }
            await store.loadAll(userId: uid)
        }
        .task(id: loadingIdentity) {
            showSlowLoadHint = false
            guard isBlockingOnNetwork else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, isBlockingOnNetwork else { return }
            showSlowLoadHint = true
        }
    }

    private var loadingIdentity: String {
        "\(auth.isCheckingAuth)-\(store.isLoading)-\(store.isLoaded)-\(auth.user?.uid ?? "none")"
    }

    private var isBlockingOnNetwork: Bool {
        auth.isCheckingAuth || (auth.isAuthenticated && store.isLoading && !store.isLoaded)
    }

    private func reload() async {
        guard let uid = auth.user?.uid else { return }
        showSlowLoadHint = false
        await store.loadAll(userId: uid)
    }

    private func connectionBanner(_ text: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text)
                .font(VS.Typography.body(12))
                .foregroundStyle(VS.Color.error)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .font(VS.Typography.body(12, weight: .semibold))
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(VS.Color.accent, in: Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(VS.Color.error.opacity(0.12))
    }
}

private struct LoadingView: View {
    var message: String? = nil
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        ZStack {
            VeloseeteBackground()

            VStack(spacing: 18) {
                Image("VeloseeteMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityLabel("Veloseete is loading")

                if let message {
                    Text(message)
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }

                if let retryTitle, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .font(VS.Typography.body(14, weight: .semibold))
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(VS.Color.accent, in: Capsule())
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: message != nil)
    }
}
