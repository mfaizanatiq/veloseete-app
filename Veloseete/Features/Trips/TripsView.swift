import SwiftUI
import MapKit

enum DriveSort: String, CaseIterable, Identifiable {
    case recent, oldest, fastest, longest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        case .fastest: return "Fastest"
        case .longest: return "Longest"
        }
    }
}

struct TripsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tripPermissions: TripPermissionsManager
    @EnvironmentObject private var recorder: TripRecordingService
    @State private var sort: DriveSort = .recent
    @State private var selectedVehicleId: String? = nil
    @State private var selectedTripId: String? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showTripPermissions = false
    @State private var showConfirm = false

    private var filteredTrips: [Trip] {
        var list = store.trips
        if let selectedVehicleId {
            list = list.filter { $0.vehicleId == selectedVehicleId }
        }
        switch sort {
        case .recent: return list.sorted { $0.startedAt > $1.startedAt }
        case .oldest: return list.sorted { $0.startedAt < $1.startedAt }
        case .fastest: return list.sorted { $0.maxSpeedKmh > $1.maxSpeedKmh }
        case .longest: return list.sorted { $0.distanceKm > $1.distanceKm }
        }
    }

    private var selectedTrip: Trip? {
        if let id = selectedTripId, let match = filteredTrips.first(where: { $0.id == id }) {
            return match
        }
        return filteredTrips.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TripsMapCanvas(
                    trips: filteredTrips,
                    selected: selectedTrip,
                    position: $mapPosition
                )
                .frame(height: 280)

                HStack(spacing: 8) {
                    VSIcon(icon: .car, size: 14, weight: .fill, tint: VS.Color.textPrimary)
                    Text("Veloseete")
                        .font(VS.Typography.heading(13))
                }
                .foregroundStyle(VS.Color.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .padding(.leading, 16)
                .padding(.top, 12)
            }

            VStack(alignment: .leading, spacing: 14) {
                recordingControls
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                HStack {
                    Text("My Drives")
                        .font(VS.Typography.heading(26, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Spacer()
                    Text("\(filteredTrips.count)")
                        .font(VS.Typography.body(13, weight: .semibold))
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(VS.Color.accent, in: Capsule())
                }
                .padding(.horizontal, 16)

                filterBar
                    .padding(.horizontal, 16)

                if let error = recorder.lastError {
                    Text(error)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.warning)
                        .padding(.horizontal, 16)
                        .onTapGesture { recorder.clearError() }
                }

                if filteredTrips.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTrips) { trip in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        selectedTripId = trip.id
                                        if let region = region(for: trip) {
                                            mapPosition = .region(region)
                                        }
                                    }
                                } label: {
                                    DriveRowView(
                                        trip: trip,
                                        unit: store.defaultDistanceUnit,
                                        isSelected: selectedTrip?.id == trip.id
                                    )
                                }
                                .buttonStyle(.plain)

                                Divider().overlay(Color.white.opacity(0.06))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 110)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(VS.Color.bgPrimary)
        }
        .background(VS.Color.bgPrimary.ignoresSafeArea())
        .onAppear {
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
            tripPermissions.refreshStatuses()
            focusMap()
            if recorder.pendingSave != nil {
                showConfirm = true
            }
        }
        .sheet(isPresented: $showTripPermissions) {
            TripPermissionsOnboardingView {
                showTripPermissions = false
            }
        }
        .sheet(isPresented: $showConfirm) {
            if let pending = recorder.pendingSave {
                TripConfirmSheet(pending: pending)
            }
        }
        .onChange(of: selectedVehicleId) { _, _ in
            selectedTripId = filteredTrips.first?.id
            syncRecorderVehicle()
            focusMap()
        }
        .onChange(of: sort) { _, _ in
            selectedTripId = filteredTrips.first?.id
            focusMap()
        }
        .onChange(of: recorder.pendingSave) { _, pending in
            showConfirm = pending != nil
        }
        .onChange(of: store.currentVehicle?.id) { _, _ in
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
        }
    }

    private func syncRecorderVehicle() {
        let vehicle = store.vehicles.first(where: { $0.id == selectedVehicleId }) ?? store.currentVehicle
        guard let vehicle else { return }
        recorder.configure(
            vehicleId: vehicle.id,
            vehicleName: vehicle.nickname,
            currentOdometer: vehicle.currentOdometer
        )
        if recorder.autoTrackingEnabled, recorder.phase == .idle {
            recorder.setAutoTracking(true)
        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phaseTitle)
                        .font(VS.Typography.heading(15))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(phaseSubtitle)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { recorder.autoTrackingEnabled },
                    set: { recorder.setAutoTracking($0) }
                ))
                .labelsHidden()
                .tint(VS.Color.accent)
            }

            if let snap = recorder.snapshot, recorder.phase == .recording {
                HStack(spacing: 10) {
                    liveMetric(String(format: "%.1f", snap.distanceKm), "km")
                    liveMetric(formatDuration(snap.durationSec), "time")
                    liveMetric(String(format: "%.0f", snap.currentSpeedKmh), "km/h")
                }
            }

            HStack(spacing: 10) {
                if recorder.phase == .recording {
                    Button {
                        if recorder.snapshot?.isPaused == true {
                            recorder.resumeTrip()
                        } else {
                            recorder.pauseTrip()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            VSIcon(
                                icon: recorder.snapshot?.isPaused == true ? .play : .pause,
                                size: 16,
                                weight: .fill,
                                tint: VS.Color.textPrimary
                            )
                            Text(recorder.snapshot?.isPaused == true ? "Resume" : "Pause")
                                .font(VS.Typography.heading(14))
                        }
                        .foregroundStyle(VS.Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }

                    Button {
                        recorder.endTrip()
                    } label: {
                        HStack(spacing: 8) {
                            VSIcon(icon: .stop, size: 16, weight: .fill, tint: VS.Color.navPill)
                            Text("End drive")
                                .font(VS.Typography.heading(14))
                        }
                        .foregroundStyle(VS.Color.navPill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VS.Color.accent, in: Capsule())
                    }
                } else {
                    Button {
                        guard tripPermissions.locationStatus.isUsable else {
                            showTripPermissions = true
                            return
                        }
                        syncRecorderVehicle()
                        recorder.startManualTrip()
                    } label: {
                        HStack(spacing: 8) {
                            VSIcon(icon: .play, size: 16, weight: .fill, tint: VS.Color.navPill)
                            Text("Start drive")
                                .font(VS.Typography.heading(14))
                        }
                        .foregroundStyle(VS.Color.navPill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VS.Color.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .glassCard(elevated: recorder.phase == .recording)
    }

    private var phaseTitle: String {
        switch recorder.phase {
        case .idle: return "Trip tracking"
        case .watching: return "Watching for drives"
        case .recording: return recorder.snapshot?.isPaused == true ? "Paused" : "Recording"
        case .confirming: return "Confirm drive"
        }
    }

    private var phaseSubtitle: String {
        switch recorder.phase {
        case .idle:
            return recorder.autoTrackingEnabled
                ? "Auto-detect is on — waiting for motion/GPS"
                : "Manual start, or toggle auto-detect"
        case .watching:
            return "Starts automatically when you begin driving"
        case .recording:
            return "Live Activity + GPS route · \(recorder.snapshot?.source ?? "manual")"
        case .confirming:
            return "Review distance and odometer"
        }
    }

    private func liveMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(VS.Typography.heading(18, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label.uppercased())
                .font(VS.Typography.body(10, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .metricInset()
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func focusMap() {
        if let trip = selectedTrip, let region = region(for: trip) {
            mapPosition = .region(region)
        } else {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310),
                    span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
                )
            )
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All Cars") { selectedVehicleId = nil }
                    ForEach(store.vehicles) { vehicle in
                        Button("\(vehicle.icon ?? "🚗") \(vehicle.nickname)") {
                            selectedVehicleId = vehicle.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        VSIcon(icon: .car, size: 12, weight: .fill, tint: VS.Color.textSecondary)
                        Text(vehicleFilterLabel)
                            .font(VS.Typography.body(13, weight: .semibold))
                        VSIcon(icon: .caretDown, size: 10, weight: .bold, tint: VS.Color.textSecondary)
                    }
                    .foregroundStyle(VS.Color.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                ForEach(DriveSort.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            sort = option
                        }
                    } label: {
                        Text(option.label)
                            .font(VS.Typography.body(13, weight: .semibold))
                            .foregroundStyle(sort == option ? VS.Color.navPill : VS.Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(sort == option ? VS.Color.accent : Color.white.opacity(0.06))
                            )
                    }
                }
            }
        }
    }

    private var vehicleFilterLabel: String {
        guard let id = selectedVehicleId,
              let v = store.vehicles.first(where: { $0.id == id }) else {
            return "All Cars"
        }
        return v.nickname
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            VSIcon(icon: .mapTrifold, size: 40, weight: .regular, tint: VS.Color.accent)
            Text("No drives yet")
                .font(VS.Typography.heading(18))
                .foregroundStyle(VS.Color.textPrimary)
            Text("Start a drive or turn on auto-detect — routes, distance, and top speed land here.")
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if tripPermissions.locationStatus != .always {
                Button {
                    showTripPermissions = true
                } label: {
                    HStack(spacing: 8) {
                        VSIcon(icon: .mapPin, size: 18, weight: .fill, tint: VS.Color.navPill)
                        Text("Set up trip tracking")
                            .font(VS.Typography.heading(15))
                    }
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(VS.Color.accent, in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 110)
    }

    private func region(for trip: Trip) -> MKCoordinateRegion? {
        let coords = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : trip.route
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.04),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.04)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct TripsMapCanvas: View {
    let trips: [Trip]
    let selected: Trip?
    @Binding var position: MapCameraPosition

    var body: some View {
        Map(position: $position) {
            ForEach(trips) { trip in
                if trip.route.count >= 2 {
                    MapPolyline(coordinates: trip.route.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(
                        VS.Color.accent.opacity(selected?.id == trip.id ? 0.2 : 0.4),
                        lineWidth: selected?.id == trip.id ? 5 : 10
                    )
                }
            }

            if let selected, selected.route.count >= 2 {
                MapPolyline(coordinates: selected.route.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent, lineWidth: 4)

                if let start = selected.startCoordinate ?? selected.route.first {
                    Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)) {
                        Circle()
                            .fill(VS.Color.accent)
                            .frame(width: 10, height: 10)
                    }
                }
                if let end = selected.endCoordinate ?? selected.route.last {
                    Annotation("End", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)) {
                        Circle()
                            .fill(Color(hex: 0xFF6B4A))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .preferredColorScheme(.dark)
    }
}

struct DriveRowView: View {
    let trip: Trip
    let unit: String
    var isSelected: Bool = false

    private var dayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: trip.startedAt)
    }

    var body: some View {
        HStack(spacing: 14) {
            MiniRoutePreview(route: trip.route)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(dayTitle)
                    .font(VS.Typography.heading(16))
                    .foregroundStyle(VS.Color.textPrimary)

                Text("\(trip.startedAt.formatted(date: .omitted, time: .shortened)) – \(trip.endedAt.formatted(date: .omitted, time: .shortened))")
                    .font(VS.Typography.body(12))
                    .foregroundStyle(VS.Color.textTertiary)

                Text("\(DistanceFormat.formatDistance(trip.distanceKm, unit: unit)) · \(trip.durationFormatted)")
                    .font(VS.Typography.body(12, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(speedLabel)
                    .font(VS.Typography.heading(22, weight: .bold))
                    .foregroundStyle(VS.Color.accent)
                Text(unit == "mi" ? "mph" : "km/h")
                    .font(VS.Typography.body(10, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? VS.Color.accent.opacity(0.08) : .clear)
        )
    }

    private var speedLabel: String {
        if unit == "mi" {
            return String(format: "%.0f", trip.maxSpeedKmh * 0.621371)
        }
        return String(format: "%.0f", trip.maxSpeedKmh)
    }
}

struct MiniRoutePreview: View {
    let route: [TripCoordinate]

    var body: some View {
        Canvas { context, size in
            guard route.count >= 2 else {
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.7))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.8, y: size.height * 0.3),
                    control: CGPoint(x: size.width * 0.5, y: size.height * 0.9)
                )
                context.stroke(path, with: .color(VS.Color.textSecondary.opacity(0.5)), lineWidth: 2)
                return
            }

            let lats = route.map(\.latitude)
            let lngs = route.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLng = lngs.min()!, maxLng = lngs.max()!
            let dLat = max(maxLat - minLat, 0.0001)
            let dLng = max(maxLng - minLng, 0.0001)

            var path = Path()
            for (i, point) in route.enumerated() {
                let x = ((point.longitude - minLng) / dLng) * (size.width - 8) + 4
                let y = (1 - ((point.latitude - minLat) / dLat)) * (size.height - 8) + 4
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(
                path,
                with: .color(VS.Color.accent),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
