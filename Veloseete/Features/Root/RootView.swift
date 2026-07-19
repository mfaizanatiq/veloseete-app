import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tripPermissionsStore: TripPermissionsStore

    var body: some View {
        ZStack {
            Group {
                if auth.isCheckingAuth {
                    LoadingView()
                } else if !auth.isAuthenticated {
                    AuthView()
                } else if store.isLoading && !store.isLoaded {
                    LoadingView()
                } else if store.vehicles.isEmpty && store.isLoaded {
                    VStack(spacing: 0) {
                        if let loadError = store.loadError {
                            Text(loadError)
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.error)
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(VS.Color.error.opacity(0.12))
                        }
                        GarageView()
                    }
                } else if !tripPermissionsStore.hasCompletedOnboarding {
                    TripPermissionsOnboardingView()
                } else {
                    MainTabShell()
                }
            }
        }
        .task(id: auth.user?.uid) {
            guard let uid = auth.user?.uid else {
                store.clear()
                return
            }
            await store.loadAll(userId: uid)
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            VeloseeteBackground()

            Image("VeloseeteMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityLabel("Veloseete is loading")
        }
    }
}
