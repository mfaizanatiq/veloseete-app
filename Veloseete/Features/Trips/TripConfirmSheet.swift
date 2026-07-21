import MapKit
import SwiftUI

struct TripConfirmSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var recorder: TripRecordingService
    @Environment(\.dismiss) private var dismiss

    let pending: PendingTripSave

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Review drive")
                        .font(VS.Typography.heading(26, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)

                    Text(pending.vehicleName)
                        .font(VS.Typography.body(14, weight: .medium))
                        .foregroundStyle(VS.Color.textSecondary)

                    if !pending.route.isEmpty || pending.startCoordinate != nil || pending.endCoordinate != nil {
                        PendingTripRouteMap(pending: pending)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    HStack(spacing: 12) {
                        confirmMetric(String(format: "%.1f", pending.distanceKm), "km")
                        confirmMetric(formatDuration(pending.durationSec), "duration")
                        confirmMetric(String(format: "%.0f", pending.maxSpeedKmh), "max km/h")
                    }

                    HStack(spacing: 12) {
                        VSIcon(icon: .gauge, size: 22, weight: .duotone, tint: VS.Color.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Adds to your estimate")
                                .font(VS.Typography.heading(15))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text("Your verified odometer changes only when you enter the number shown in your car, usually at the next refuel.")
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .glassCard()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.error)
                    }

                    PrimaryCTAButton(
                        title: "Confirm & save",
                        icon: .checkCircle,
                        isLoading: isSaving
                    ) {
                        Task { await save() }
                    }

                    Button("Discard") {
                        recorder.discardPending(id: pending.id)
                        dismiss()
                    }
                    .font(VS.Typography.body(14, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        .veloseeteSheet()
    }

    private func confirmMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label.uppercased())
                .font(VS.Typography.body(11, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricInset()
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await store.saveTrip(pending, odometer: pending.suggestedOdometer, applyOdometer: false)
            recorder.markPendingSaved(id: pending.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct PendingTripRouteMap: View {
    let pending: PendingTripSave

    private var coordinates: [TripCoordinate] {
        pending.route.isEmpty
            ? [pending.startCoordinate, pending.endCoordinate].compactMap { $0 }
            : TripTrackingLogic.cleanedForDisplay(pending.route)
    }

    private var routeRegion: MKCoordinateRegion {
        let points = coordinates
        guard let first = points.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.55, 0.02),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.55, 0.02)
            )
        )
    }

    var body: some View {
        Map(initialPosition: .region(routeRegion), interactionModes: []) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let start = coordinates.first {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)) {
                    Circle()
                        .fill(VS.Color.accent)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }

            if let end = coordinates.last, end != coordinates.first {
                Annotation("End", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)) {
                    Circle()
                        .fill(VS.Color.routeEnd)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .preferredColorScheme(.dark)
        .accessibilityLabel("Recorded trip route")
    }
}
