import SwiftUI
import FirebaseCore
import GoogleSignIn
import UIKit
import UserNotifications

final class VeloseeteAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct VeloseeteApp: App {
    @UIApplicationDelegateAdaptor(VeloseeteAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService: AuthService
    @StateObject private var dataStore = DataStore.shared
    @StateObject private var tripPermissions = TripPermissionsManager()
    @StateObject private var tripPermissionsStore = TripPermissionsStore.shared
    @StateObject private var profileAvatarStore = ProfileAvatarStore.shared
    @StateObject private var vehiclePhotoStore = VehiclePhotoStore.shared
    private let tripRecorder = TripRecordingService.shared
    @State private var isShowingSplash = true

    init() {
        FirebaseBootstrap.configure()
        _authService = StateObject(wrappedValue: AuthService.shared)
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
            .environmentObject(profileAvatarStore)
            .environmentObject(vehiclePhotoStore)
            .environmentObject(tripRecorder)
            .preferredColorScheme(.dark)
            .tint(VS.Color.accent)
            .toggleStyle(.veloseete)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .task(id: authService.userId) {
                profileAvatarStore.load(userId: authService.userId)
            }
            .onAppear {
                if authService.isAuthenticated {
                    tripRecorder.resumeBackgroundWatchingIfNeeded()
                }
                tripRecorder.refreshPendingReviewReminders()
                if dataStore.isLoaded {
                    VehicleInsightScheduler.shared.refresh(using: dataStore)
                    dataStore.refreshHomeWidgets()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if authService.isAuthenticated {
                    tripRecorder.resumeBackgroundWatchingIfNeeded()
                }
                tripRecorder.refreshPendingReviewReminders()
                if dataStore.isLoaded {
                    VehicleInsightScheduler.shared.refresh(using: dataStore)
                    dataStore.refreshHomeWidgets()
                }
            }
            .onChange(of: dataStore.isLoaded) { _, loaded in
                guard loaded else { return }
                VehicleInsightScheduler.shared.refresh(using: dataStore)
                dataStore.refreshHomeWidgets()
            }
            // The review queue changing (drive finished, confirmed, or
            // discarded) shifts the fuel-range picture too.
            .onChange(of: tripRecorder.pendingSaves) { _, _ in
                guard dataStore.isLoaded else { return }
                VehicleInsightScheduler.shared.refresh(using: dataStore)
            }
            .onChange(of: dataStore.currentVehicle?.id) { _, _ in
                guard let vehicle = dataStore.currentVehicle else { return }
                tripRecorder.configure(
                    vehicleId: vehicle.id,
                    vehicleName: vehicle.nickname,
                    currentOdometer: vehicle.currentOdometer,
                    driverName: dataStore.userName,
                    baselineL100: DriveMoodBaseline.resolve(
                        vehicle: vehicle,
                        logs: dataStore.fuelLogs,
                        manufacturerStandard: dataStore.manufacturerStandard
                    )
                )
                tripRecorder.resumeBackgroundWatchingIfNeeded()
                VehicleInsightScheduler.shared.refresh(using: dataStore)
                dataStore.refreshHomeWidgets()
            }
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

        // Lime track, black handle — never white-on-lime.
        UISwitch.appearance().onTintColor = UIColor(VS.Color.accent)
        UISwitch.appearance().thumbTintColor = UIColor(VS.Color.navPill)
    }
}
