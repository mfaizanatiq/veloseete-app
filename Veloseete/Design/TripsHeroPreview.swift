#if DEBUG
import MapKit
import SwiftUI

/// Portfolio hero — real Trips map + ride HUD (tracking) or My Drives with routes.
/// Launch Simulator with: `-TripsHeroPreview` or `-TripsHeroPreviewDrives`
struct TripsHeroPreview: View {
    private var showDrives: Bool {
        ProcessInfo.processInfo.arguments.contains("-TripsHeroPreviewDrives")
    }

    @State private var tick = 0
    @State private var mapPosition: MapCameraPosition

    init() {
        let drives = ProcessInfo.processInfo.arguments.contains("-TripsHeroPreviewDrives")
        _mapPosition = State(
            initialValue: .camera(
                MapCamera(
                    centerCoordinate: CLLocationCoordinate2D(latitude: 24.8135, longitude: 67.0308),
                    distance: drives ? 4_200 : 1_100,
                    heading: drives ? 18 : 42,
                    pitch: 58
                )
            )
        )
    }

    private var demoTrips: [Trip] { Self.karachiDemoTrips }
    private var liveRoute: [TripCoordinate] { Self.liveRideRoute }
    private var character: CLLocationCoordinate2D {
        let last = liveRoute.last!
        return CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
    }

    private var hudModel: ActiveDriveHUDModel {
        var base = ActiveDriveHUDModel.preview
        let wave = sin(Double(tick) * 0.35) * 9
        base.speedKmh = 64 + wave
        let drain = (sin(Double(tick) * 0.22) + 1) / 2
        base.efficiencyReserve = max(0.18, 1 - drain * 0.45)
        base.durationSec = 1_524 + Double(tick) * 10
        base.thirst = 0.16 + drain * 0.32
        var intel = base.intelligence
        intel.tankFillLevel = max(0.2, 0.68 - drain * 0.4)
        base.intelligence = intel
        return base
    }

    var body: some View {
        ZStack {
            TripsMapCanvas(
                trips: showDrives ? demoTrips : [],
                selected: showDrives ? demoTrips.first : nil,
                activeRoute: showDrives ? [] : liveRoute,
                isActivelyRecording: !showDrives,
                showsUserCharacter: !showDrives,
                courseDegrees: 48,
                characterCoordinate: showDrives ? nil : character,
                vehicleStyle: .suv,
                vehiclePaint: .brand,
                locksMinimumPitch: true,
                position: $mapPosition
            )
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.38), .clear, .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if showDrives {
                    drivesSheet
                        .padding(.horizontal, 14)
                        .padding(.bottom, 18)
                } else {
                    rideSheet
                        .padding(.horizontal, 14)
                        .padding(.bottom, 18)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()) { _ in
            guard !showDrives else { return }
            tick += 1
        }
    }

    private var topChrome: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    chip("Tracking", active: !showDrives)
                    chip("My Drives", active: showDrives)
                }
                .padding(3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))

                HStack(spacing: 7) {
                    Circle()
                        .fill(showDrives ? VS.Color.textTertiary : VS.Color.success)
                        .frame(width: 7, height: 7)
                    Text(showDrives ? "3 drives on map" : "Recording · Coolray")
                        .font(VS.Typography.body(10, weight: .bold))
                }
                .foregroundStyle(VS.Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay { Capsule().fill(Color.black.opacity(0.42)) }
                        .overlay { Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(VS.Typography.body(12, weight: .semibold))
            .foregroundStyle(active ? VS.Color.navPill : VS.Color.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if active {
                    Capsule().fill(VS.Color.accent)
                }
            }
    }

    private var rideSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            ActiveDriveHUDContent(
                model: hudModel,
                pulseOpacity: tick % 2 == 0 ? 1 : 0.45
            )

            HStack(spacing: 10) {
                Text("Pause")
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VS.Color.divider, in: Capsule())

                Text("End drive")
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VS.Color.accent, in: Capsule())
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var drivesSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("My Drives")
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)

            ForEach(Array(demoTrips.prefix(3).enumerated()), id: \.element.id) { index, trip in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(index == 0 ? VS.Color.accent : VS.Color.textSecondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(index == 0 ? "Clifton → Sea View" : index == 1 ? "DHA Phase 5 loop" : "Korangi morning")
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(String(format: "%.1f km · %@", trip.distanceKm, trip.durationFormatted))
                            .font(VS.Typography.body(12, weight: .medium))
                            .foregroundStyle(VS.Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(trip.maxSpeedKmh)) max")
                        .font(VS.Typography.mono(12, weight: .bold))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(index == 0 ? 0.1 : 0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    index == 0 ? VS.Color.accent.opacity(0.45) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        }
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

// MARK: - Demo routes (Karachi)

private extension TripsHeroPreview {
    /// Live ride polyline along Sea View / Clifton
    static let liveRideRoute: [TripCoordinate] = [
        .init(latitude: 24.8068, longitude: 67.0282),
        .init(latitude: 24.8084, longitude: 67.0291),
        .init(latitude: 24.8102, longitude: 67.0300),
        .init(latitude: 24.8120, longitude: 67.0308),
        .init(latitude: 24.8136, longitude: 67.0314),
        .init(latitude: 24.8152, longitude: 67.0318),
        .init(latitude: 24.8168, longitude: 67.0320),
    ]

    static var karachiDemoTrips: [Trip] {
        let now = Date()
        return [
            Trip(
                id: "demo-clifton",
                vehicleId: "coolray",
                startedAt: now.addingTimeInterval(-3_600),
                endedAt: now.addingTimeInterval(-2_400),
                distanceKm: 12.4,
                durationSec: 1_524,
                avgSpeedKmh: 29,
                maxSpeedKmh: 68,
                startCoordinate: liveRideRoute.first,
                endCoordinate: liveRideRoute.last,
                route: liveRideRoute,
                source: "auto"
            ),
            Trip(
                id: "demo-dha",
                vehicleId: "coolray",
                startedAt: now.addingTimeInterval(-86_400),
                endedAt: now.addingTimeInterval(-85_200),
                distanceKm: 8.1,
                durationSec: 1_120,
                avgSpeedKmh: 26,
                maxSpeedKmh: 54,
                startCoordinate: .init(latitude: 24.8120, longitude: 67.0450),
                endCoordinate: .init(latitude: 24.8205, longitude: 67.0520),
                route: [
                    .init(latitude: 24.8120, longitude: 67.0450),
                    .init(latitude: 24.8145, longitude: 67.0475),
                    .init(latitude: 24.8170, longitude: 67.0495),
                    .init(latitude: 24.8205, longitude: 67.0520),
                ],
                source: "auto"
            ),
            Trip(
                id: "demo-korangi",
                vehicleId: "coolray",
                startedAt: now.addingTimeInterval(-172_800),
                endedAt: now.addingTimeInterval(-171_600),
                distanceKm: 18.6,
                durationSec: 2_100,
                avgSpeedKmh: 32,
                maxSpeedKmh: 72,
                startCoordinate: .init(latitude: 24.8250, longitude: 67.0900),
                endCoordinate: .init(latitude: 24.8400, longitude: 67.1100),
                route: [
                    .init(latitude: 24.8250, longitude: 67.0900),
                    .init(latitude: 24.8300, longitude: 67.0970),
                    .init(latitude: 24.8350, longitude: 67.1040),
                    .init(latitude: 24.8400, longitude: 67.1100),
                ],
                source: "manual"
            ),
        ]
    }
}

#Preview("Trips hero · Tracking") {
    TripsHeroPreview()
}
#endif
