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
    /// `-ShotSheet`: open Add fill on launch, to check sheet sizing per screen.
    @State private var showSheet = ProcessInfo.processInfo.arguments.contains("-ShotSheet")
    @Environment(\.windowSize) private var windowSize

    private var isWide: Bool { VS.Layout.isWide(windowSize) }

    init() {
        // Seed before first body render — Driver achievements crash on empty logs.
        DataStore.shared.seedProductShots()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ShotFuels") || args.contains("-ShotFuelsEarly") {
            _tab = State(initialValue: .fuel)
        } else if args.contains("-ShotDriver") {
            _tab = State(initialValue: .driver)
        } else if args.contains("-ShotService") {
            _tab = State(initialValue: .service)
        } else if args.contains("-ShotTrips") {
            _tab = State(initialValue: .trips)
        } else {
            _tab = State(initialValue: .details)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The app root paints this behind every tab — the margins beside the
            // centred column need it too.
            VeloseeteBackground()
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
            // Same width rule as MainTabShell, so shots match the real app.
            .tabContentWidth(fullBleed: tab == .trips, twoColumn: isWide && tab != .details)
            .padding(.horizontal, isWide && tab != .trips ? VS.Spacing.frameGutter : 0)

            if isWide {
                NavRailLayer(active: $tab)
            } else {
                // Tappable, so the demo build can be driven tab to tab like the real app.
                BottomNavBar(active: $tab)
            }
        }
        // Same as MainTabShell: measure the bottom bar from the physical edge.
        .ignoresSafeArea(.container, edges: .bottom)
        .environmentObject(store)
        .environmentObject(navChrome)
        .environmentObject(avatarStore)
        .environmentObject(vehiclePhotos)
        .environmentObject(AuthService.shared)
        .environmentObject(TripPermissionsManager())
        .environmentObject(TripRecordingService.shared)
        .preferredColorScheme(.dark)
        .tint(VS.Color.accent)
        .sheet(isPresented: $showSheet) {
            if let vehicle = store.currentVehicle {
                RefuelSheetView(vehicleId: vehicle.id)
                    .environmentObject(store)
            }
        }
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
