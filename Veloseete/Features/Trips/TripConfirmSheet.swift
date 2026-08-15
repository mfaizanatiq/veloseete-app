import MapKit
import SwiftUI

struct TripConfirmSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var recorder: TripRecordingService
    @Environment(\.dismiss) private var dismiss

    let pending: PendingTripSave

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var distanceValue: String {
        let km = pending.distanceKm
        return String(format: km >= 100 ? "%.0f" : "%.1f", km)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !pending.route.isEmpty || pending.startCoordinate != nil || pending.endCoordinate != nil {
                        PendingTripRouteMap(pending: pending)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                                    .stroke(VS.Color.hairline, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(pending.vehicleName)
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.textTertiary)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(distanceValue)
                                .font(VS.Typography.heading(56, weight: .bold))
                                .foregroundStyle(VS.Color.textPrimary)
                                .minimumScaleFactor(0.55)
                                .lineLimit(1)
                            Text("km")
                                .font(VS.Typography.heading(20, weight: .bold))
                                .foregroundStyle(VS.Color.textTertiary)
                        }

                        Text("Review drive")
                            .font(VS.Typography.heading(18, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)

                        Text("\(pending.startedAt.formatted(date: .abbreviated, time: .shortened)) – \(pending.endedAt.formatted(date: .omitted, time: .shortened))")
                            .font(VS.Typography.body(14, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    HStack(spacing: 10) {
                        confirmMetric(formatDuration(pending.durationSec), "Duration")
                        confirmMetric(String(format: "%.0f", pending.avgSpeedKmh), "Avg km/h")
                        confirmMetric(String(format: "%.0f", pending.maxSpeedKmh), "Top km/h")
                    }

                    HStack(spacing: 12) {
                        VSIcon(icon: .gauge, size: 22, weight: .duotone, tint: VS.Color.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adds to your estimate")
                                .font(VS.Typography.heading(15, weight: .bold))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text("Verified odometer only changes when you enter the number in your car — usually at the next refuel.")
                                .font(VS.Typography.body(13, weight: .medium))
                                .foregroundStyle(VS.Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(VS.Color.hairline, lineWidth: 1)
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13, weight: .medium))
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
                    .font(VS.Typography.heading(15, weight: .bold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(.horizontal, VS.Spacing.sheetInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
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
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VS.Color.hairline, lineWidth: 1)
        )
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            _ = try await store.saveTrip(pending, odometer: pending.suggestedOdometer, applyOdometer: false)
            recorder.markPendingSaved(id: pending.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
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
        let midLat = (minLatitude + maxLatitude) / 2
        let latDelta = max((maxLatitude - minLatitude) * 1.55, 0.02)
        let lngDeltaRaw = max((maxLongitude - minLongitude) * 1.55, 0.02)
        let cosLat = max(cos(midLat * .pi / 180), 0.2)
        let lngDelta = max(lngDeltaRaw, latDelta / cosLat * 0.55)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: midLat,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latDelta,
                longitudeDelta: lngDelta
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
