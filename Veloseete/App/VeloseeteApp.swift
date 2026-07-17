import SwiftUI
import FirebaseCore
import UIKit

@main
struct VeloseeteApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var dataStore = DataStore.shared
    @StateObject private var tripPermissions = TripPermissionsManager()
    @StateObject private var tripPermissionsStore = TripPermissionsStore.shared
    private let tripRecorder = TripRecordingService.shared
    @State private var isShowingSplash = true

    init() {
        FirebaseBootstrap.configure()
        Self.configureChrome()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                VeloseeteBackground()
                RootView()

                if isShowingSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.35)) {
                            isShowingSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .environmentObject(authService)
            .environmentObject(dataStore)
            .environmentObject(tripPermissions)
            .environmentObject(tripPermissionsStore)
            .environmentObject(tripRecorder)
            .preferredColorScheme(.dark)
            .tint(VS.Color.accent)
        }
    }

    private static func configureChrome() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(VS.Color.bgPrimary)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont(name: "SpaceGrotesk-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont(name: "SpaceGrotesk-Bold", size: 28) ?? .systemFont(ofSize: 28, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(VS.Color.accent)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(VS.Color.navPill)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UITableView.appearance().backgroundColor = UIColor(VS.Color.bgPrimary)
        UICollectionView.appearance().backgroundColor = UIColor(VS.Color.bgPrimary)
    }
}
