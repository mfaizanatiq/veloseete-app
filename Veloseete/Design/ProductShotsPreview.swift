#if DEBUG
import SwiftUI

/// Portfolio product shots — Garage / Fuels / Driver with seeded demo data.
/// Launch: `-ShotGarage` | `-ShotFuels` | `-ShotDriver`
struct ProductShotsPreview: View {
    @StateObject private var store = DataStore.shared
    @StateObject private var navChrome = BottomNavChrome()
    @StateObject private var avatarStore = ProfileAvatarStore.shared
    @StateObject private var vehiclePhotos = VehiclePhotoStore.shared
    @State private var tab: AppTab

    init() {
        // Seed before first body render — Driver achievements crash on empty logs.
        DataStore.shared.seedProductShots()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ShotFuels") {
            _tab = State(initialValue: .fuel)
        } else if args.contains("-ShotDriver") {
            _tab = State(initialValue: .driver)
        } else {
            _tab = State(initialValue: .details)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .fuel:
                    DashboardView(onProfile: {})
                case .driver:
                    DriverProfileView(onProfile: {})
                case .details:
                    DetailsListView(onProfile: {}, onSwitchTab: { tab = $0 })
                case .trips:
                    TripsView(onProfile: {})
                case .service:
                    ServiceListView(onProfile: {})
                }
            }

            BottomNavBar(active: $tab)
                .allowsHitTesting(false)
        }
        .environmentObject(store)
        .environmentObject(navChrome)
        .environmentObject(avatarStore)
        .environmentObject(vehiclePhotos)
        .environmentObject(AuthService.shared)
        .environmentObject(TripPermissionsManager())
        .environmentObject(TripRecordingService.shared)
        .preferredColorScheme(.dark)
        .tint(VS.Color.accent)
        .onAppear {
            store.seedProductShots()
            avatarStore.load(userId: "portfolio-demo")
            vehiclePhotos.load(vehicleIds: store.vehicles.map(\.id))
        }
    }
}

#Preview("Product · Garage") {
    ProductShotsPreview()
}
#endif
