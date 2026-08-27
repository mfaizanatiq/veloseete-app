import MapKit
import SwiftUI

#if DEBUG
/// Portfolio hero — pitched MapKit over downtown SF (real 3D buildings).
/// Launch Simulator with: `-MapHeroPreview`
struct MapHeroPreview: View {
    private static var cameraDistance: CLLocationDistance {
        UIDevice.current.userInterfaceIdiom == .pad ? 3_600 : 2_800
    }

    @State private var position = MapCameraPosition.camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.7925, longitude: -122.4020),
            distance: cameraDistance,
            heading: 35,
            pitch: 58
        )
    )

    var body: some View {
        Map(position: $position, interactionModes: [])
            .mapStyle(
                .standard(
                    elevation: .realistic,
                    pointsOfInterest: .excludingAll,
                    showsTraffic: false
                )
            )
            .mapControlVisibility(.hidden)
            .preferredColorScheme(.dark)
            .ignoresSafeArea()
    }
}

#Preview("Map hero · SF 3D") {
    MapHeroPreview()
}
#endif
