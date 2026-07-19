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

private enum TripsMode: String, CaseIterable, Identifiable {
    case tracking = "Tracking"
    case drives = "My Drives"
    var id: String { rawValue }
}

struct TripsView: View {
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tripPermissions: TripPermissionsManager
    @EnvironmentObject private var recorder: TripRecordingService
    @State private var sort: DriveSort = .recent
    @State private var selectedVehicleId: String? = nil
    @State private var selectedTripId: String? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showTripPermissions = false
    @State private var showConfirm = false
    @State private var detailTrip: Trip?
    @State private var mode: TripsMode = .tracking
    @State private var driveDrawerExpanded = false
    @GestureState private var driveDrawerDrag: CGFloat = 0
    let onProfile: () -> Void

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
        return nil
    }

    private var driveMapCoordinates: [TripCoordinate] {
        filteredTrips.flatMap { trip in
            if !trip.route.isEmpty { return TripTrackingLogic.cleanedForDisplay(trip.route) }
            return [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        }
    }

    private var usesLocationFocalMap: Bool {
        mode == .tracking || driveMapCoordinates.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                TripsMapCanvas(
                    trips: mode == .drives ? filteredTrips : [],
                    selected: mode == .drives ? selectedTrip : nil,
                    activeRoute: recorder.liveRoute,
                    isActivelyRecording: recorder.phase == .recording,
                    showsUserCharacter: usesLocationFocalMap,
                    position: $mapPosition
                )
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height + mapTopObstruction + mapBottomObstruction
                )
                // GeometryReader anchors an oversized child at the top. Moving it up by
                // the complete bottom obstruction places MapKit's focal point at the
                // centre of the genuinely visible area above the drawer.
                .offset(y: -mapBottomObstruction)
            }
            .clipped()
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.32), .clear, .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                modePicker
                    .frame(maxWidth: 255)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.top, 10)

                HStack(spacing: 7) {
                    Circle()
                        .fill(recorder.phase == .recording ? VS.Color.success : VS.Color.textTertiary)
                        .frame(width: 7, height: 7)
                    Text(recorder.phase == .recording ? "LIVE ROUTE" : (mode == .tracking ? "READY TO TRACK" : "SELECT A DRIVE"))
                        .font(VS.Typography.body(10, weight: .bold))
                }
                .foregroundStyle(VS.Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .padding(.top, 10)

                Spacer(minLength: 100)

                Group {
                    if mode == .tracking {
                        trackingMode
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        drivesMode
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onProfile()
            } label: {
                ProfileAvatarView(image: avatarStore.image, size: 40)
                    .overlay(Circle().stroke(VS.Color.accent.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Open profile")
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .background(VS.Color.bgPrimary)
        .onAppear {
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
            tripPermissions.refreshStatuses()
            if mode == .tracking {
                focusTrackingLocation()
            } else {
                focusMap()
            }
            if recorder.pendingSave != nil {
                showConfirm = true
            }
        }
        .sheet(isPresented: $showTripPermissions) {
            TripPermissionsOnboardingView {
                showTripPermissions = false
            }
            .veloseeteSheet()
        }
        .sheet(isPresented: $showConfirm) {
            if let pending = recorder.pendingSave {
                TripConfirmSheet(pending: pending)
            }
        }
        .sheet(item: $detailTrip) { trip in
            TripDetailView(trip: trip, unit: store.defaultDistanceUnit)
                .veloseeteSheet()
        }
        .onChange(of: selectedVehicleId) { _, _ in
            selectedTripId = nil
            syncRecorderVehicle()
            focusMap()
        }
        .onChange(of: sort) { _, _ in
            selectedTripId = nil
            focusMap()
        }
        .onChange(of: recorder.pendingSave) { _, pending in
            showConfirm = pending != nil
        }
        .onChange(of: recorder.snapshot?.routePointCount) { _, count in
            guard recorder.phase == .recording,
                  (count ?? 0) >= 2 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                focusTrackingLocation()
            }
        }
        .onChange(of: store.trips.count) { _, _ in
            guard mode == .drives, selectedTripId == nil else { return }
            focusMap()
        }
        .onChange(of: driveDrawerExpanded) { _, _ in
            guard mode == .drives else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 360_000_000)
                guard mode == .drives else { return }
                focusMap()
            }
        }
        .onChange(of: store.currentVehicle?.id) { _, _ in
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
        }
    }

    /// Keeps the camera focal point inside the map area that is actually visible
    /// between the top controls and the live bottom panel.
    private var mapTopObstruction: CGFloat { 150 }

    private var mapBottomObstruction: CGFloat {
        guard mode == .drives else { return 395 }
        return driveDrawerExpanded ? driveDrawerExpandedHeight : driveDrawerCollapsedHeight
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(TripsMode.allCases) { item in
                Button {
                    guard mode != item else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.34, extraBounce: 0.06)) {
                        mode = item
                        if item == .drives {
                            focusMap()
                        } else {
                            focusTrackingLocation()
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        VSIcon(
                            icon: item == .tracking ? .navigationArrow : .roadHorizon,
                            size: 15,
                            weight: mode == item ? .fill : .regular,
                            tint: mode == item ? VS.Color.navPill : VS.Color.textTertiary
                        )
                        Text(item.rawValue)
                            .font(VS.Typography.heading(13))
                    }
                    .foregroundStyle(mode == item ? VS.Color.navPill : VS.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(mode == item ? VS.Color.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(VS.Color.chip, in: Capsule())
        .overlay(Capsule().stroke(VS.Color.hairline, lineWidth: 1))
    }

    private var trackingMode: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                recordingControls

                if let vehicleId = selectedVehicleId ?? store.currentVehicle?.id,
                   let estimate = store.odometerEstimate(vehicleId: vehicleId) {
                    odometerCard(estimate)
                }

                if let error = recorder.lastError {
                    Text(error)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.warning)
                        .onTapGesture { recorder.clearError() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 105)
        }
        .frame(maxHeight: 395)
        .background(panelBackground.ignoresSafeArea(edges: .bottom))
    }

    private var drivesMode: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                Capsule()
                    .fill(Color.white.opacity(0.26))
                    .frame(width: 42, height: 5)
                    .padding(.top, 8)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Drives")
                            .font(VS.Typography.heading(25, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Tap a drive to explore its route")
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    Spacer()
                    Text("\(filteredTrips.count)")
                        .font(VS.Typography.body(12, weight: .bold))
                        .foregroundStyle(VS.Color.navPill)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(VS.Color.accent, in: Circle())
                }
                .padding(.horizontal, 16)
            }
            .contentShape(Rectangle())
            .gesture(driveDrawerGesture)
            .onTapGesture {
                guard driveDrawerTravel > 0 else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                    driveDrawerExpanded.toggle()
                }
            }

            filterBar.padding(.horizontal, 16)

            if filteredTrips.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(driveDrawerGesture)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTrips) { trip in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.snappy(duration: 0.3)) {
                                    selectedTripId = trip.id
                                    if let region = drawerAwareRegion(for: trip) {
                                        mapPosition = .region(region)
                                    }
                                }
                                detailTrip = trip
                            } label: {
                                DriveRowView(
                                    trip: trip,
                                    unit: store.defaultDistanceUnit,
                                    isSelected: selectedTrip?.id == trip.id
                                )
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(VS.Color.divider)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                    .tracksBottomNavScroll()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: driveDrawerExpandedHeight)
        .background(panelBackground.ignoresSafeArea(edges: .bottom))
        .clipped()
        .offset(y: driveDrawerOffset)
    }

    private var driveDrawerCollapsedHeight: CGFloat {
        UIScreen.main.bounds.height * 0.46
    }

    private var driveDrawerExpandedHeight: CGFloat {
        UIScreen.main.bounds.height * (filteredTrips.isEmpty ? 0.62 : 0.72)
    }

    private var driveDrawerTravel: CGFloat {
        max(0, driveDrawerExpandedHeight - driveDrawerCollapsedHeight)
    }

    private var driveDrawerOffset: CGFloat {
        let restingOffset = driveDrawerExpanded ? 0 : driveDrawerTravel
        return min(driveDrawerTravel, max(0, restingOffset + driveDrawerDrag))
    }

    private var driveDrawerGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($driveDrawerDrag) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                guard driveDrawerTravel > 0 else { return }
                let restingOffset = driveDrawerExpanded ? 0 : driveDrawerTravel
                let projectedOffset = min(
                    driveDrawerTravel,
                    max(0, restingOffset + value.predictedEndTranslation.height)
                )
                let shouldExpand = projectedOffset < driveDrawerTravel / 2

                guard shouldExpand != driveDrawerExpanded else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                    driveDrawerExpanded = shouldExpand
                }
            }
    }

    private var panelBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
            .fill(VS.Color.bgPrimary.opacity(0.97))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 24, y: -8)
    }

    private func mapCanvas(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TripsMapCanvas(
                trips: mode == .drives ? filteredTrips : [],
                selected: mode == .drives ? selectedTrip : nil,
                activeRoute: recorder.liveRoute,
                isActivelyRecording: recorder.phase == .recording,
                showsUserCharacter: mode == .tracking,
                position: $mapPosition
            )
            .frame(height: height)

            HStack(spacing: 7) {
                Circle()
                    .fill(recorder.phase == .recording ? VS.Color.success : VS.Color.textTertiary)
                    .frame(width: 7, height: 7)
                Text(recorder.phase == .recording ? "LIVE ROUTE" : (mode == .tracking ? "READY TO TRACK" : "ROUTE MAP"))
                    .font(VS.Typography.body(10, weight: .bold))
            }
            .foregroundStyle(VS.Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func syncRecorderVehicle() {
        let vehicle = store.vehicles.first(where: { $0.id == selectedVehicleId }) ?? store.currentVehicle
        guard let vehicle else { return }
        recorder.configure(
            vehicleId: vehicle.id,
            vehicleName: vehicle.nickname,
            currentOdometer: vehicle.currentOdometer,
            driverName: store.userName
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

                HStack(spacing: 7) {
                    Circle()
                        .fill(recorder.liveRoute.isEmpty ? VS.Color.warning : VS.Color.success)
                        .frame(width: 7, height: 7)
                    Text(routeStatusText)
                        .font(VS.Typography.body(10, weight: .semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                    Spacer()
                    Text("\(recorder.liveRoute.count) points")
                        .font(VS.Typography.mono(10, weight: .semibold))
                        .foregroundStyle(VS.Color.textSecondary)
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
                        .background(VS.Color.divider, in: Capsule())
                    }

                    PrimaryCTAButton(title: "End drive", icon: .stop) {
                        recorder.endTrip()
                    }
                } else {
                    PrimaryCTAButton(title: "Start drive", icon: .play) {
                        guard tripPermissions.locationStatus.isUsable else {
                            showTripPermissions = true
                            return
                        }
                        syncRecorderVehicle()
                        recorder.startManualTrip()
                    }
                }
            }
        }
        .padding(14)
        .glassCard(elevated: recorder.phase == .recording)
    }

    private func odometerCard(_ estimate: OdometerEstimate) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(VS.Color.accent.opacity(0.12))
                VSIcon(icon: .gauge, size: 22, weight: .duotone, tint: VS.Color.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(String(format: "%.0f km", estimate.estimatedKm))
                        .font(VS.Typography.heading(21, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("EST.")
                        .font(VS.Typography.body(9, weight: .bold))
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(VS.Color.accent, in: Capsule())
                }
                Text(String(format: "%.0f verified + %.1f tracked", estimate.verifiedKm, estimate.trackedSinceKm))
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Verified")
                    .font(VS.Typography.body(10, weight: .semibold))
                    .foregroundStyle(VS.Color.success)
                Text(estimate.verifiedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(VS.Typography.body(10))
                    .foregroundStyle(VS.Color.textTertiary)
            }
        }
        .padding(14)
        .glassCard(elevated: true)
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

    private var routeStatusText: String {
        guard let accuracy = recorder.lastLocationAccuracy else { return "Acquiring precise GPS…" }
        if accuracy <= 15 { return "Strong GPS · ±\(Int(accuracy)) m" }
        if accuracy <= 30 { return "Good GPS · ±\(Int(accuracy)) m" }
        return "Weak GPS · ±\(Int(accuracy)) m"
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func focusMap() {
        if let trip = selectedTrip, let region = drawerAwareRegion(for: trip) {
            mapPosition = .region(region)
            return
        }

        if !driveMapCoordinates.isEmpty {
            mapPosition = .region(drawerAwareRegion(for: driveMapCoordinates))
        } else {
            mapPosition = .userLocation(followsHeading: false, fallback: .automatic)
        }
    }

    private func focusTrackingLocation() {
        mapPosition = .userLocation(
            followsHeading: recorder.phase == .recording,
            fallback: .automatic
        )
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
                    .background(VS.Color.chip, in: Capsule())
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
                                Capsule().fill(sort == option ? VS.Color.accent : VS.Color.chip)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.bottom, 82)
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

    private func drawerAwareRegion(for trip: Trip) -> MKCoordinateRegion? {
        let coordinates = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : TripTrackingLogic.cleanedForDisplay(trip.route)
        guard !coordinates.isEmpty else { return nil }
        return drawerAwareRegion(for: coordinates)
    }

    private func drawerAwareRegion(for coordinates: [TripCoordinate]) -> MKCoordinateRegion {
        let base = region(for: coordinates)
        let viewportHeight = max(UIScreen.main.bounds.height, 1)
        let usableHeight = max(180, viewportHeight - mapTopObstruction - mapBottomObstruction)
        let mapCanvasHeight = viewportHeight + mapTopObstruction + mapBottomObstruction
        let fittedLatitudeDelta = base.span.latitudeDelta * mapCanvasHeight / usableHeight

        return MKCoordinateRegion(
            center: base.center,
            span: MKCoordinateSpan(
                latitudeDelta: fittedLatitudeDelta,
                longitudeDelta: base.span.longitudeDelta
            )
        )
    }

    private func region(for coords: [TripCoordinate]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.8, 0.015),
                longitudeDelta: max((maxLng - minLng) * 1.8, 0.015)
            )
        )
    }
}

struct TripsMapCanvas: View {
    let trips: [Trip]
    let selected: Trip?
    let activeRoute: [TripCoordinate]
    let isActivelyRecording: Bool
    let showsUserCharacter: Bool
    @Binding var position: MapCameraPosition

    var body: some View {
        Map(position: $position) {
            if showsUserCharacter {
                UserAnnotation {
                    VeloseeteMapCharacter(isLive: isActivelyRecording)
                }
            }

            ForEach(trips) { trip in
                let displayRoute = TripTrackingLogic.cleanedForDisplay(trip.route)
                if displayRoute.count >= 2 {
                    MapPolyline(coordinates: displayRoute.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(
                        VS.Color.accent.opacity(selected?.id == trip.id ? 0.16 : 0.32),
                        style: StrokeStyle(
                            lineWidth: selected?.id == trip.id ? 4 : 6,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }

            if let selected {
                let selectedRoute = TripTrackingLogic.cleanedForDisplay(selected.route)
                if selectedRoute.count >= 2 {
                    MapPolyline(coordinates: selectedRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(VS.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

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
                            .fill(VS.Color.routeEnd)
                            .frame(width: 10, height: 10)
                    }
                }
            }

            if activeRoute.count >= 2 {
                MapPolyline(coordinates: activeRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent.opacity(0.18), lineWidth: 12)
                MapPolyline(coordinates: activeRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let current = activeRoute.last {
                Annotation(isActivelyRecording ? "Live" : "Last point", coordinate: CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude)) {
                    ZStack {
                        if isActivelyRecording {
                            Circle().fill(VS.Color.accent.opacity(0.2)).frame(width: 38, height: 38)
                        }
                        Circle().fill(VS.Color.accent).frame(width: 13, height: 13)
                        Circle().stroke(Color.white.opacity(0.9), lineWidth: 2).frame(width: 13, height: 13)
                    }
                    .shadow(color: VS.Color.accent.opacity(0.55), radius: 12)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .preferredColorScheme(.dark)
    }
}

private struct VeloseeteMapCharacter: View {
    let isLive: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(VS.Color.accent.opacity(0.24))
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulse ? 1.15 : 0.88)
                    .opacity(pulse ? 0.15 : 0.8)
            }

            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: 50, height: 50)

            Circle()
                .fill(VS.Color.accent)
                .frame(width: 44, height: 44)

            HStack(spacing: 11) {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 5.5, height: 7.7)
                Capsule()
                    .fill(Color.black)
                    .frame(width: 5.5, height: 7.7)
            }
        }
        .shadow(color: VS.Color.accent.opacity(0.34), radius: 11)
        .shadow(color: .black.opacity(0.45), radius: 7, y: 4)
        .onAppear {
            guard isLive else { return }
            withAnimation(.easeOut(duration: 1.25).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityLabel(isLive ? "Your live location" : "Your location")
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
                        .stroke(VS.Color.divider, lineWidth: 1)
                )
        )
    }
}

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let unit: String

    private var routeRegion: MKCoordinateRegion {
        let coords = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : trip.route
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310),
                span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
            )
        }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.5, 0.025),
                longitudeDelta: max((maxLng - minLng) * 1.5, 0.025)
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    routeMap
                        .frame(height: 320)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.startedAt.formatted(date: .complete, time: .omitted))
                                    .font(VS.Typography.heading(22, weight: .bold))
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text("\(trip.startedAt.formatted(date: .omitted, time: .shortened)) – \(trip.endedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(VS.Typography.body(13))
                                    .foregroundStyle(VS.Color.textTertiary)
                            }
                            Spacer()
                            Text(trip.source == "auto" ? "AUTO" : "MANUAL")
                                .font(VS.Typography.body(10, weight: .bold))
                                .foregroundStyle(VS.Color.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(VS.Color.accent.opacity(0.1), in: Capsule())
                        }

                        HStack(spacing: 10) {
                            stat(DistanceFormat.formatDistance(trip.distanceKm, unit: unit), "GPS distance")
                            stat(trip.durationFormatted, "Drive time")
                            stat(speed(trip.avgSpeedKmh), "Average")
                        }

                        HStack(spacing: 12) {
                            VSIcon(icon: .checkCircle, size: 21, weight: .fill, tint: VS.Color.success)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Included in odometer estimate")
                                    .font(VS.Typography.heading(14))
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text("This route adds \(DistanceFormat.formatDistance(trip.distanceKm, unit: unit)) until your next verified dashboard reading.")
                                    .font(VS.Typography.body(12))
                                    .foregroundStyle(VS.Color.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .glassCard()

                        HStack(spacing: 0) {
                            detailMetric(speed(trip.maxSpeedKmh), "Top speed", .gauge)
                            Rectangle().fill(VS.Color.divider).frame(width: 1, height: 42)
                            detailMetric("\(trip.route.count)", "Route points", .mapPin)
                            Rectangle().fill(VS.Color.divider).frame(width: 1, height: 42)
                            detailMetric(trip.route.count >= 10 ? "Good" : "Partial", "GPS quality", .target)
                        }
                        .padding(14)
                        .glassCard()
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .veloseetePage()
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
    }

    private var routeMap: some View {
        Map(initialPosition: .region(routeRegion)) {
            let displayRoute = TripTrackingLogic.cleanedForDisplay(trip.route)
            if displayRoute.count >= 2 {
                MapPolyline(coordinates: displayRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent.opacity(0.2), lineWidth: 10)
                MapPolyline(coordinates: displayRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let start = trip.startCoordinate ?? trip.route.first {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)) {
                    routeMarker(color: VS.Color.accent, icon: "play.fill")
                }
            }
            if let end = trip.endCoordinate ?? trip.route.last {
                Annotation("Finish", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)) {
                    routeMarker(color: VS.Color.routeEnd, icon: "flag.fill")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottomLeading) {
            Text("RECORDED ROUTE")
                .font(VS.Typography.body(10, weight: .bold))
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(VS.Color.accent, in: Capsule())
                .padding(16)
        }
    }

    private func routeMarker(color: Color, icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(VS.Color.navPill)
            .frame(width: 25, height: 25)
            .background(color, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
            .shadow(color: color.opacity(0.45), radius: 8)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(VS.Typography.heading(18, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(VS.Typography.body(10))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .metricInset()
    }

    private func detailMetric(_ value: String, _ label: String, _ icon: VSIconName) -> some View {
        VStack(spacing: 5) {
            VSIcon(icon: icon, size: 17, weight: .duotone, tint: VS.Color.accent)
            Text(value)
                .font(VS.Typography.heading(14))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label)
                .font(VS.Typography.body(9))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func speed(_ kmh: Double) -> String {
        unit == "mi"
            ? String(format: "%.0f mph", kmh * 0.621371)
            : String(format: "%.0f km/h", kmh)
    }
}
