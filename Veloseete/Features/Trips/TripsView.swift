import SwiftUI
import MapKit

enum DriveSort: String, CaseIterable, Identifiable {
    case recent, oldest, fastest, longest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Latest"
        case .oldest: return "First drives"
        case .fastest: return "Top speed"
        case .longest: return "By distance"
        }
    }

    /// Chronological sorts group nicely by day; ranked sorts read as a flat leaderboard.
    var isChronological: Bool {
        self == .recent || self == .oldest
    }
}

private enum TripsMode: String, CaseIterable, Identifiable {
    case tracking = "Tracking"
    case drives = "My Drives"
    var id: String { rawValue }
}

private enum TrackingStatusPriority {
    case pending(count: Int, km: Double, samples: [PendingTripSave])
    case fuel(title: String, detail: String, tint: Color)
}

struct TripsView: View {
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tripPermissions: TripPermissionsManager
    @EnvironmentObject private var recorder: TripRecordingService
    /// Live window size — follows fold / unfold, unlike `UIScreen.main`.
    @Environment(\.windowSize) private var windowSize
    @State private var sort: DriveSort = .recent
    @State private var selectedVehicleId: String? = nil
    @State private var selectedTripId: String? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    /// After "Let's roll" prompts for When In Use, start the trip once granted.
    @State private var pendingManualStartAfterLocation = false
    @State private var reviewPendingTrip: PendingTripSave?
    @State private var isConfirmingAll = false
    @State private var detailTrip: Trip?
    @State private var mode: TripsMode = .tracking
    @State private var driveDrawerExpanded = false
    /// My Drives list + map routes, rebuilt only when their inputs change —
    /// never per body pass (GPS ticks, sheet updates, drawer settles).
    @State private var drives = DrivesListModel()
    /// Odometer / fuel maths for the tracking panel, cached per data change.
    @State private var tracking = TrackingInsights()
    let onProfile: () -> Void

    private func autoTrackNudgePromptedKey(for userId: String) -> String {
        "tripRecording.autoTrackPrompted.v1.\(userId)"
    }

    private var drivesInputs: DrivesInputs {
        DrivesInputs(
            trips: store.trips,
            vehicles: store.vehicles,
            archivedVehicles: store.archivedVehicles,
            pending: recorder.pendingSaves,
            fuelLogs: store.fuelLogs,
            manufacturerStandard: store.manufacturerStandard,
            selectedVehicleId: selectedVehicleId,
            sort: sort,
            unit: store.defaultDistanceUnit
        )
    }

    private var trackingInputs: TrackingInputs {
        TrackingInputs(
            vehicleId: trackingVehicle?.id,
            vehicles: store.vehicles,
            trips: store.trips,
            fuelLogs: store.fuelLogs,
            serviceLogs: store.serviceLogs,
            pending: recorder.pendingSaves,
            manufacturerStandard: store.manufacturerStandard,
            unit: store.defaultDistanceUnit
        )
    }

    /// How many drives have list rows so far — grows a page at a time on scroll.
    @State private var driveRowLimit = DrivesListModel.pageSize

    private func rebuildDrives() {
        drives = DrivesListModel.build(from: drivesInputs, revision: drives.revision &+ 1, rowLimit: driveRowLimit)
    }

    private func loadMoreDrives() {
        guard drives.hasMoreRows else { return }
        driveRowLimit += DrivesListModel.pageSize
        rebuildDrives()
    }

    private func rebuildTracking() {
        tracking = TrackingInsights.build(vehicle: trackingVehicle, store: store, pending: recorder.pendingSaves)
    }

    private var selectedTrip: Trip? {
        guard let id = selectedTripId else { return nil }
        return drives.trips.first(where: { $0.id == id })
    }

    /// Whole review queue for active cars, ignoring the car filter — drives the tab badge.
    private var reviewBadgeCount: Int {
        let activeIds = store.activeVehicleIds
        return recorder.pendingSaves.count { pending in
            pending.vehicleId.isEmpty || activeIds.contains(pending.vehicleId)
        }
    }

    private var mapVehicleStyle: VehicleMarkStyle {
        if let icon = store.currentVehicle?.icon {
            return VehicleMarkStyle.resolve(icon)
        }
        return .defaultMapStyle
    }

    private var mapVehiclePaint: VehiclePaintColor {
        VehiclePaintColor.resolve(store.currentVehicle?.paintColor)
    }

    /// Saves every visible pending drive with its suggested odometer — same flow
    /// as confirming one by one, without opening each sheet.
    private func confirmAllPending() async {
        guard !isConfirmingAll else { return }
        isConfirmingAll = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for pending in drives.pending {
            do {
                try await store.saveTrip(pending, odometer: pending.suggestedOdometer, applyOdometer: false)
                recorder.markPendingSaved(id: pending.id)
            } catch {
                // Stop on the first failure; the remaining drives stay queued for review.
                break
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isConfirmingAll = false
    }

    private func openTrip(id: String) {
        guard let trip = drives.trips.first(where: { $0.id == id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // The sheet covers the map, so no camera flight underneath it — animating
        // MapKit and the sheet together was what made opening a drive stutter.
        selectedTripId = trip.id
        detailTrip = trip
    }

    private func openPending(id: String) {
        guard let pending = drives.pending.first(where: { $0.id.uuidString == id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reviewPendingTrip = pending
    }

    private var usesLocationFocalMap: Bool {
        mode == .tracking || drives.overviewCoordinates.isEmpty
    }

    /// Prefer our recorder pose so the avatar stays locked to the live route tip
    /// (MapKit's `UserAnnotation` lags and doubles up with the tracker dot).
    private var mapCharacterCoordinate: CLLocationCoordinate2D? {
        if let lat = recorder.followLatitude, let lng = recorder.followLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let last = recorder.liveRoute.last {
            return CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
        }
        return nil
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                TripsMapCanvas(
                    routes: mode == .drives ? drives.mapRoutes : [],
                    selected: mode == .drives ? selectedTrip : nil,
                    activeRoute: recorder.phase == .recording ? [] : recorder.liveRoute,
                    isActivelyRecording: false,
                    showsUserCharacter: usesLocationFocalMap && recorder.phase != .recording,
                    courseDegrees: recorder.followCourseDegrees,
                    characterCoordinate: mapCharacterCoordinate,
                    vehicleStyle: mapVehicleStyle,
                    vehiclePaint: mapVehiclePaint,
                    locksMinimumPitch: mode == .tracking || selectedTrip != nil,
                    position: $mapPosition
                )
                // Skip MapKit content rebuilds when nothing the map draws changed.
                .equatable()
                // Oversize the map past the chrome so its centre lands in the visible gap
                // (below the top chips, above / beside the panel).
                .frame(
                    width: proxy.size.width + mapLeadingObstruction,
                    height: proxy.size.height + mapTopObstruction + mapBottomObstruction
                )
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

            if isWide {
                // Duo unfolded: one full-height panel on the left, the map to its right.
                HStack(spacing: 0) {
                    tripsPanel(edge: .leading)
                        .frame(width: VS.Layout.sidePanelWidth, height: sidePanelHeight, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous))
                        .padding(.leading, VS.Spacing.frameGutter)
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, VS.Spacing.frameGutter)
            } else {
                VStack(spacing: 0) {
                    // Must not eat taps meant for the map or the top segment.
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    tripsPanel(edge: .bottom)
                        // Measured from the bar itself, so there's always a gap above the nav.
                        .floatingInFrame(bottomClearance: BottomNavBar.occupiedHeight + BottomNavBar.panelGap)
                }
            }

            // Top chrome in the ZStack (not an overlay) so MapKit can't steal hits.
            // safeAreaPadding keeps Tracking / My Drives below the status bar.
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        modePicker
                            .frame(maxWidth: 255)

                        HStack(spacing: 7) {
                            Circle()
                                .fill(recorder.phase == .recording ? VS.Color.success : VS.Color.textTertiary)
                                .frame(width: 7, height: 7)
                            Text(TrackyVoice.mapChip(
                                recording: recorder.phase == .recording,
                                trackingMode: mode == .tracking
                            ))
                                .font(VS.TextStyle.caption2(.bold))
                        }
                        .foregroundStyle(VS.Color.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            Capsule()
                                .fill(.regularMaterial)
                                .overlay {
                                    Capsule()
                                        .fill(Color.black.opacity(0.42))
                                }
                                .overlay {
                                    Capsule()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                }
                        }
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
                    }

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    // Same cloud as every other tab's header.
                    SyncStatusBadge()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onProfile()
                    } label: {
                        ProfileAvatarView(image: avatarStore.image, size: 40)
                            .overlay(Circle().stroke(VS.Color.accent.opacity(0.24), lineWidth: 1))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Open profile")
                }
                .padding(.leading, VS.Spacing.frameGutter + 6)
                .padding(.trailing, 16)
                .padding(.top, 8)
                .safeAreaPadding(.top)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .zIndex(20)
        }
        .background(VS.Color.bgPrimary)
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: "portfolio.forceTripsMode"),
               let forced = TripsMode(rawValue: raw) {
                mode = forced
            }
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "portfolio.forceDriveSort"),
               let forced = DriveSort(rawValue: raw) {
                sort = forced
            }
            #endif
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
            tripPermissions.refreshStatuses()
            driveDrawerExpanded = false
            // Build caches before framing the camera — focusMap reads them.
            rebuildDrives()
            rebuildTracking()
            if mode == .tracking {
                recorder.ensureMapFollowUpdates()
                focusTrackingLocation()
            } else {
                recorder.stopMapFollowUpdates()
                focusMap()
            }

            // Auto-detect tip is the capsule only — no panel banner.
        }
        .onChange(of: tripPermissions.locationStatus) { _, status in
            guard pendingManualStartAfterLocation, status.isUsable else { return }
            pendingManualStartAfterLocation = false
            syncRecorderVehicle()
            recorder.startManualTrip()
        }
        .onDisappear {
            recorder.stopMapFollowUpdates()
            driveDrawerExpanded = false
        }
        .sheet(item: $reviewPendingTrip) { pending in
            TripConfirmSheet(pending: pending) { next in
                guard let next else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    reviewPendingTrip = next
                }
            }
        }
        .sheet(item: $detailTrip, onDismiss: {
            selectedTripId = nil
            if mode == .drives {
                withAnimation(.easeInOut(duration: 0.45)) {
                    focusMap()
                }
            }
        }) { trip in
            TripDetailView(trip: trip, unit: store.defaultDistanceUnit)
                .veloseeteSheet(allowsWide: true)
        }
        .onChange(of: drivesInputs) { old, new in
            let filterChanged = old.sort != new.sort || old.selectedVehicleId != new.selectedVehicleId
            // A new filter or sort starts back at the first page.
            if filterChanged { driveRowLimit = DrivesListModel.pageSize }
            rebuildDrives()
            if old.selectedVehicleId != new.selectedVehicleId {
                syncRecorderVehicle()
            }
            if filterChanged {
                selectedTripId = nil
                // Tracking keeps its live camera; only My Drives re-frames history.
                if mode == .drives { focusMap() }
            } else if old.trips.count != new.trips.count, mode == .drives, selectedTripId == nil {
                focusMap()
            }
        }
        .onChange(of: trackingInputs) { _, _ in
            rebuildTracking()
        }
        .onChange(of: recorder.followTick) { _, _ in
            guard mode == .tracking else { return }
            // Recording is HUD-first — never chase the camera (MapKit redraw = battery).
            guard recorder.phase != .recording else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                focusTrackingLocation()
            }
        }
        .onChange(of: recorder.phase) { _, phase in
            guard mode == .tracking else { return }
            if phase == .idle || phase == .watching {
                recorder.ensureMapFollowUpdates()
                withAnimation(.easeInOut(duration: 0.55)) {
                    focusTrackingLocation()
                }
            }
            // Entering recording: leave the map where it is — drawer owns the session.
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .drives {
                selectedTripId = nil
                recorder.stopMapFollowUpdates()
                focusMap()
            } else {
                // Collapse on the way out only — the pending rail opens My Drives expanded.
                driveDrawerExpanded = false
                recorder.ensureMapFollowUpdates()
                focusTrackingLocation()
            }
        }
        .onChange(of: store.currentVehicle?.id) { _, _ in
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
        }
    }

    private var isWide: Bool { VS.Layout.isWide(windowSize) }

    /// Tracking or My Drives, sliding in from the edge it lives on.
    private func tripsPanel(edge: Edge) -> some View {
        Group {
            if mode == .tracking {
                trackingMode
                    .transition(.move(edge: edge).combined(with: .opacity))
            } else {
                drivesMode
                    .transition(.move(edge: edge).combined(with: .opacity))
            }
        }
    }

    /// Wide mode: everything below the top chips, minus the bottom gutter.
    private var sidePanelHeight: CGFloat {
        max(320, windowSize.height - 150)
    }

    /// Wide mode keeps the panel on the left, so the map widens instead of growing down.
    private var mapLeadingObstruction: CGFloat {
        isWide ? VS.Layout.sidePanelWidth + VS.Spacing.frameGutter : 0
    }

    /// Keeps the camera focal point inside the map area that is actually visible
    /// between the top controls and the live bottom panel.
    private var mapTopObstruction: CGFloat { 148 }

    private var mapBottomObstruction: CGFloat {
        guard !isWide else { return 0 }
        let floatChrome = BottomNavBar.occupiedHeight + BottomNavBar.panelGap
        guard mode == .drives else { return trackingPanelHeight + floatChrome }
        // Always the collapsed height: expanding the drawer must never resize MapKit.
        // A map frame change inside the drawer spring was what made the sheet stutter.
        return (drives.isEmpty ? driveDrawerEmptyHeight : driveDrawerCollapsedHeight) + floatChrome
    }

    private var trackingPanelHeight: CGFloat {
        let railExtra: CGFloat = trackingStatusPriority != nil ? 56 : 0
        let errorExtra: CGFloat = recorder.lastError == nil ? 0 : 36
        if isWide, recorder.phase == .recording { return sidePanelHeight }
        switch recorder.phase {
        // ~60% of the screen — room for HUD without swallowing the map.
        case .recording:
            return windowSize.height * 0.60 + errorExtra
        case .confirming: return 320 + railExtra
        default: return 276 + railExtra
        }
    }

    /// One alert at a time — recording suppresses banners (live metrics own the panel).
    /// Priority: pending review → fuel watch. Auto-detect tip lives only on the capsule.
    private var trackingStatusPriority: TrackingStatusPriority? {
        guard recorder.phase != .recording else { return nil }
        guard let vehicleId = trackingVehicle?.id else { return nil }

        let pending = recorder.pendingSaves.filter { $0.vehicleId == vehicleId }
        if !pending.isEmpty {
            let km = pending.reduce(0.0) { $0 + $1.distanceKm }
            return .pending(count: pending.count, km: km, samples: pending)
        }
        if let warning = trackingFuelWarning {
            return .fuel(title: warning.title, detail: warning.detail, tint: warning.tint)
        }
        return nil
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(TripsMode.allCases) { item in
                Button {
                    guard mode != item else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.34, extraBounce: 0.06)) {
                        mode = item
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
                            .font(VS.TextStyle.subheadline(.semibold))
                        if item == .drives, reviewBadgeCount > 0 {
                            Text("\(reviewBadgeCount)")
                                .font(VS.TextStyle.caption2(.bold))
                                .foregroundStyle(VS.Color.navPill)
                                .frame(minWidth: 19, minHeight: 19)
                                .background(VS.Color.warning, in: Circle())
                        }
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
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.black.opacity(0.42))
                }
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .contentShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    private var trackingMode: some View {
        let recording = recorder.phase == .recording
        return VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, recording ? 16 : 12)

            trackingPanelBody
                .padding(.horizontal, 16)
                .padding(.bottom, recording ? 22 : 18)
                .frame(maxWidth: .infinity, maxHeight: recording ? .infinity : nil, alignment: .top)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: recording ? trackingPanelHeight : nil,
            maxHeight: recording ? trackingPanelHeight : nil,
            alignment: .top
        )
        // Idle / watching still hug content; recording uses ~60% of the screen.
        .fixedSize(horizontal: false, vertical: !recording)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous))
        .animation(.snappy(duration: 0.28), value: recorder.phase)
        .animation(.snappy(duration: 0.28), value: recorder.pendingSaves.count)
        .animation(.snappy(duration: 0.28), value: recorder.lastError)
    }

    private var trackingVehicle: Vehicle? {
        if let id = selectedVehicleId ?? store.currentVehicle?.id {
            return store.vehicles.first(where: { $0.id == id }) ?? store.currentVehicle
        }
        return store.currentVehicle
    }

    private var trackingFuelWarning: TrackingInsights.FuelWarning? {
        tracking.vehicleId == trackingVehicle?.id ? tracking.fuelWarning : nil
    }

    private var trackingPanelBody: some View {
        let vehicle = trackingVehicle
        // Cached per data change — this body re-runs on every GPS follow tick.
        let insights = tracking.vehicleId == vehicle?.id ? tracking : TrackingInsights()
        let estimate = insights.estimate
        let odoKm = estimate?.estimatedKm ?? vehicle?.currentOdometer ?? 0
        let usesMiles = store.defaultDistanceUnit == "mi"
        // Grouped digits: 61,780 reads at a glance; 61780 doesn't.
        let odoValue = (usesMiles ? odoKm * 0.621371 : odoKm).formatted(.number.precision(.fractionLength(0)))
        let odoUnit = usesMiles ? "mi" : "km"
        let monthLabel = DistanceFormat.formatDistance(insights.monthKm, unit: store.defaultDistanceUnit)

        return VStack(alignment: .leading, spacing: recorder.phase == .recording ? 14 : 14) {
            // Always visible — car + Auto OFF (never drop while recording)
            HStack(alignment: .top, spacing: 12) {
                trackingVehiclePicker(vehicle: vehicle)
                Spacer(minLength: 8)
                trackingAutoCapsule
            }

            if recorder.phase != .recording {
                // Hero odometer — idle / watching only (recording uses the performance HUD).
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(odoValue)
                            .font(VS.TextStyle.hero())
                            .foregroundStyle(VS.Color.textPrimary)
                            .minimumScaleFactor(0.48)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.22), value: odoValue)
                        Text(odoUnit)
                            .font(VS.TextStyle.heroUnit())
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    // One caption style; hierarchy comes from colour, not a size bump.
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TrackyVoice.monthLine(monthLabel))
                            .foregroundStyle(VS.Color.textSecondary)
                        Text(odometerCaption(estimate: estimate, liveKm: 0))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    .font(VS.TextStyle.footnote(.medium))
                }
            }

            // Single status rail (pending > fuel). Hidden while recording.
            if let rail = trackingStatusPriority {
                trackingStatusRail(rail)
            }

            if let snap = recorder.snapshot, recorder.phase == .recording {
                activeDrivePerformanceHUD(snap)
            }

            if let error = recorder.lastError {
                Text(error)
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.warning)
                    .onTapGesture { recorder.clearError() }
            }

            if recorder.phase == .recording {
                Spacer(minLength: 8)
            }

            trackingActionRow
        }
    }

    /// B1 wave pulse + B2 arc/blob — metrics own the session; map stays frozen.
    @ViewBuilder
    private func activeDrivePerformanceHUD(_ snap: ActiveTripSnapshot) -> some View {
        let mood = recorder.driveMood
        let vehicle = trackingVehicle
        let vehicleId = vehicle?.id ?? snap.vehicleId
        // Snapshot publishes every second — reuse the cached logs / baseline / odometer.
        let insights = tracking.vehicleId == vehicleId
            ? tracking
            : TrackingInsights.build(vehicle: vehicle, store: store, pending: recorder.pendingSaves)
        let vehicleLogs = insights.vehicleLogs
        let baseline = insights.baselineL100 ?? store.manufacturerStandard ?? 8.0
        let odoEstimate = insights.estimate
        let liveOdometer = (odoEstimate?.estimatedKm ?? vehicle?.currentOdometer ?? 0) + snap.distanceKm
        let intelligence = LiveDriveIntelligenceLogic.compute(
            logs: vehicleLogs,
            estimatedOdometer: liveOdometer,
            tankCapacityLiters: vehicle?.fuelTankCapacity,
            brochureL100km: store.manufacturerStandard,
            personalBaselineL100: baseline,
            liveEstL100: mood?.estL100 ?? baseline,
            thirst: mood?.thirst ?? 0.3,
            sessionAvgSpeedKmh: snap.avgSpeedKmh,
            distanceUnit: store.defaultDistanceUnit,
            learning: VehicleLearningStore.shared.state(for: vehicleId)
        )

        ActiveDriveHUDContent(
            model: ActiveDriveHUDModel(
                vehicleName: snap.vehicleName,
                speedKmh: snap.currentSpeedKmh,
                distanceKm: snap.distanceKm,
                durationSec: snap.durationSec,
                estL100: mood?.estL100 ?? store.manufacturerStandard ?? 0,
                avgSpeedKmh: snap.avgSpeedKmh,
                isPaused: snap.isPaused,
                driveScore: mood?.driveScore ?? 78,
                statusLabel: mood?.statusLabel ?? "Smooth",
                lastEvent: mood?.lastEvent ?? "",
                thirst: mood?.thirst ?? 0.3,
                efficiencyReserve: mood?.efficiencyReserve ?? 1,
                speedSamplesKmh: mood?.speedSamplesKmh ?? [],
                intelligence: intelligence,
                avatarImage: avatarStore.image,
                showsVehicleName: false
            ),
            pulseOpacity: pulseOpacity
        )
    }

    @ViewBuilder
    private func trackingStatusRail(_ rail: TrackingStatusPriority) -> some View {
        switch rail {
        case let .pending(count, km, samples):
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    mode = .drives
                    driveDrawerExpanded = true
                }
                if count == 1, let only = samples.first {
                    reviewPendingTrip = only
                }
            } label: {
                HStack(spacing: 10) {
                    VSIcon(icon: .roadHorizon, size: 16, weight: .fill, tint: VS.Color.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TrackyVoice.pendingTitle(count: count))
                            .font(VS.TextStyle.subheadline())
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(TrackyVoice.pendingSubtitle(
                            distanceLabel: DistanceFormat.formatDistance(km, unit: store.defaultDistanceUnit)
                        ))
                            .font(VS.TextStyle.caption(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(TrackyVoice.pendingCTA(count: count))
                        .font(VS.TextStyle.tag())
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(VS.Color.accent, in: Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(VS.Color.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VS.Color.warning.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TrackyVoice.Soft.pendingSection)

        case let .fuel(title, detail, tint):
            HStack(spacing: 10) {
                VSIcon(icon: .gasPump, size: 15, weight: .fill, tint: tint)
                Text(TrackyVoice.fuelTitle(title))
                    .font(VS.TextStyle.subheadline())
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer(minLength: 4)
                Text(detail)
                    .font(VS.TextStyle.caption(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(detail)")
        }
    }

    private func odometerCaption(estimate: OdometerEstimate?, liveKm: Double) -> String {
        TrackyVoice.odometerCaption(
            live: liveKm > 0.05,
            pendingIn: estimate?.includesPending == true,
            learning: estimate?.isLearning == true,
            calibrated: estimate?.isCalibrated == true
        )
    }

    private var pulseOpacity: Double {
        // Soft pulse without a Timer — snapshots land once a second, so flip on whole seconds.
        let tick = Int((recorder.snapshot?.durationSec ?? 0).rounded())
        return tick % 2 == 0 ? 1.0 : 0.45
    }

    private func trackingLivePill(paused: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(paused ? VS.Color.warning : VS.Color.accent)
                .frame(width: 6, height: 6)
                .opacity(paused ? 1 : pulseOpacity)
            Text(paused ? "PAUSED" : "LIVE")
                .font(VS.TextStyle.label())
                .foregroundStyle(paused ? VS.Color.warning : VS.Color.navPill)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            (paused ? VS.Color.warning : VS.Color.accent).opacity(paused ? 0.18 : 1),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                (paused ? VS.Color.warning : VS.Color.accent).opacity(paused ? 0.45 : 0),
                lineWidth: 1
            )
        )
        .accessibilityLabel(paused ? "Paused" : "Live recording")
    }

    private var trackingAutoCapsule: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            let newValue = !recorder.autoTrackingEnabled
            if newValue {
                tripPermissions.refreshStatuses()
                guard tripPermissions.locationStatus.supportsBackgroundAutoTrack else {
                    requestLocationAccess(for: .autoTrack)
                    return
                }
            }
            recorder.setAutoTracking(newValue)
            if newValue {
                markAutoTrackNudgePrompted()
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(recorder.autoTrackingEnabled ? VS.Color.accent : VS.Color.textTertiary.opacity(0.55))
                    .frame(width: 7, height: 7)
                Text(TrackyVoice.autoCapsule(isOn: recorder.autoTrackingEnabled))
                    .font(VS.TextStyle.caption(.bold))
            }
            .foregroundStyle(VS.Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(
                Capsule()
                    .strokeBorder(
                        recorder.autoTrackingEnabled
                            ? VS.Color.accent.opacity(0.55)
                            : Color.white.opacity(0.16),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TrackyVoice.autoAccessibility(isOn: recorder.autoTrackingEnabled))
        .accessibilityHint("Toggles automatic trip start. Requires Always location access.")
    }

    private func markAutoTrackNudgePrompted() {
        guard let uid = AuthService.shared.userId else { return }
        UserDefaults.standard.set(true, forKey: autoTrackNudgePromptedKey(for: uid))
    }

    private enum LocationAccessPurpose {
        /// Manual "Let's roll" — When In Use is enough.
        case manualStart
        /// Background auto-detect — needs Always.
        case autoTrack
    }

    /// Ask only for the missing system permission (or Settings if already denied).
    /// Never opens the full welcome onboarding from drive actions.
    private func requestLocationAccess(for purpose: LocationAccessPurpose) {
        tripPermissions.refreshStatuses()
        switch tripPermissions.locationStatus {
        case .notDetermined:
            tripPermissions.requestWhenInUseLocation()
        case .whenInUse:
            if purpose == .autoTrack {
                tripPermissions.requestAlwaysLocation()
            }
            // Manual start is already usable in whenInUse — caller shouldn't reach here.
        case .always:
            break
        case .denied, .restricted:
            tripPermissions.openSettings()
        }
    }

    @ViewBuilder
    private func trackingVehiclePicker(vehicle: Vehicle?) -> some View {
        Group {
            if store.vehicles.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    VehicleMark(style: .defaultMapStyle, size: 44, paint: .defaultMapPaint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your drive")
                            .font(VS.TextStyle.title2())
                            .foregroundStyle(VS.Color.textPrimary)
                            .lineLimit(1)
                        Text(trackingIdentitySubtitle(nil))
                            .font(VS.TextStyle.footnote(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                Menu {
                    ForEach(store.vehicles) { option in
                        Button {
                            selectedVehicleId = option.id
                        } label: {
                            Label {
                                Text(option.nickname)
                            } icon: {
                                VehicleMark(
                                    style: VehicleMarkStyle.resolve(option.icon),
                                    size: 18,
                                    paint: VehiclePaintColor.resolve(option.paintColor)
                                )
                            }
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        if let vehicle {
                            VehicleMark(
                                style: VehicleMarkStyle.resolve(vehicle.icon),
                                size: 44,
                                paint: VehiclePaintColor.resolve(vehicle.paintColor)
                            )
                        } else {
                            VehicleMark(style: .defaultMapStyle, size: 44, paint: .defaultMapPaint)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(vehicle?.nickname ?? "Select car")
                                    .font(VS.TextStyle.title2())
                                    .foregroundStyle(VS.Color.textPrimary)
                                    .lineLimit(1)
                                if store.vehicles.count > 1 {
                                    VSIcon(icon: .caretDown, size: 12, weight: .bold, tint: VS.Color.textTertiary)
                                }
                            }
                            Text(trackingIdentitySubtitle(vehicle))
                                .font(VS.TextStyle.footnote(.medium))
                                .foregroundStyle(VS.Color.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private func trackingIdentitySubtitle(_ vehicle: Vehicle?) -> String {
        guard let vehicle else {
            switch recorder.phase {
            case .idle, .watching:
                return "Default sedan · \(phaseTitle)"
            default:
                return phaseSubtitle
            }
        }
        let makeModel = [vehicle.make, vehicle.model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if makeModel.isEmpty {
            return phaseSubtitle
        }
        // Status rides with the car when idle/watching — keeps the hero number clear.
        switch recorder.phase {
        case .idle, .watching:
            return "\(makeModel) · \(phaseTitle)"
        default:
            return makeModel
        }
    }

    private var trackingActionRow: some View {
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
                            size: 18,
                            weight: .fill,
                            tint: VS.Color.textPrimary
                        )
                        Text(recorder.snapshot?.isPaused == true
                             ? TrackyVoice.resumeCTA()
                             : TrackyVoice.pauseCTA())
                            .font(VS.TextStyle.headline())
                    }
                    .foregroundStyle(VS.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VS.Color.divider, in: Capsule())
                }
                .buttonStyle(.plain)

                PrimaryCTAButton(title: TrackyVoice.endCTA(), icon: .stop) {
                    recorder.endTrip()
                }
            } else {
                PrimaryCTAButton(title: TrackyVoice.startCTA(), icon: .play) {
                    tripPermissions.refreshStatuses()
                    guard tripPermissions.locationStatus.isUsable else {
                        pendingManualStartAfterLocation = true
                        requestLocationAccess(for: .manualStart)
                        return
                    }
                    syncRecorderVehicle()
                    recorder.startManualTrip()
                }
            }
        }
    }

    private var drivesMode: some View {
        DrivesDrawer(
            model: drives,
            sort: sort,
            vehicleFilterLabel: vehicleFilterLabel,
            vehicles: store.vehicles,
            isConfirmingAll: isConfirmingAll,
            showsSetUpTracking: tripPermissions.locationStatus != .always,
            // Wide mode: a side panel is always fully open — no drag.
            collapsedHeight: isWide ? sidePanelHeight : (drives.isEmpty ? driveDrawerEmptyHeight : driveDrawerCollapsedHeight),
            expandedHeight: isWide ? sidePanelHeight : (drives.isEmpty ? driveDrawerEmptyHeight : driveDrawerExpandedHeight),
            expanded: $driveDrawerExpanded,
            actions: DrivesDrawer.Actions(
                selectVehicle: { selectedVehicleId = $0 },
                selectSort: { option in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        sort = option
                    }
                },
                openTrip: { openTrip(id: $0) },
                openPending: { openPending(id: $0) },
                confirmAll: { Task { await confirmAllPending() } },
                setUpTracking: { requestLocationAccess(for: .autoTrack) },
                loadMore: { loadMoreDrives() }
            )
        )
        // Recorder / GPS publishes re-run TripsView; the drawer only redraws when its data does.
        .equatable()
    }

    /// Collapsed sheet — keeps mode picker + bottom nav fully on screen.
    private var driveDrawerCollapsedHeight: CGFloat {
        min(300, windowSize.height * 0.36)
    }

    /// Largest sheet that never covers top chrome or the floating bottom nav.
    private var driveDrawerMaxHeight: CGFloat {
        let screen = windowSize.height
        let reservedTop: CGFloat = 132
        let reservedBottom = BottomNavBar.occupiedHeight + BottomNavBar.panelGap
        return max(driveDrawerCollapsedHeight, screen - reservedTop - reservedBottom)
    }

    private var driveDrawerExpandedHeight: CGFloat {
        max(driveDrawerCollapsedHeight, min(driveDrawerMaxHeight, windowSize.height * 0.56))
    }

    /// Empty state is fixed-height (nothing to scroll) but needs room for its CTA.
    private var driveDrawerEmptyHeight: CGFloat {
        max(driveDrawerCollapsedHeight, min(driveDrawerMaxHeight, windowSize.height * 0.48))
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
            .fill(Color(hex: 0x161916))
            .overlay(
                RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
                    .stroke(VS.Color.hairline, lineWidth: 1)
            )
    }

    private func syncRecorderVehicle() {
        if let vehicle = store.vehicles.first(where: { $0.id == selectedVehicleId }) ?? store.currentVehicle {
            recorder.configure(
                vehicleId: vehicle.id,
                vehicleName: vehicle.nickname,
                currentOdometer: vehicle.currentOdometer,
                driverName: store.userName,
                baselineL100: DriveMoodBaseline.resolve(
                    vehicle: vehicle,
                    logs: store.fuelLogs,
                    manufacturerStandard: store.manufacturerStandard
                )
            )
        } else {
            recorder.configureGuestTracking(driverName: store.userName)
        }
        if recorder.autoTrackingEnabled, recorder.phase == .idle {
            recorder.setAutoTracking(true)
        }
    }

    private var phaseTitle: String {
        TrackyVoice.phaseTitle(
            phase: recorder.phase,
            isPaused: recorder.snapshot?.isPaused == true
        )
    }

    private var phaseSubtitle: String {
        TrackyVoice.phaseSubtitle(
            phase: recorder.phase,
            autoOn: recorder.autoTrackingEnabled,
            source: recorder.snapshot?.source
        )
    }

    private func liveMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(VS.TextStyle.title2())
                .foregroundStyle(VS.Color.textPrimary)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(VS.TextStyle.label())
                .foregroundStyle(VS.Color.accent.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VS.Color.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func focusMap() {
        if let trip = selectedTrip, let region = drawerAwareRegion(for: trip, shiftForPitch: true) {
            mapPosition = .camera(Self.pitchedCamera(for: region, overview: false))
            return
        }

        if !drives.overviewCoordinates.isEmpty {
            // Wide historic overview — flat camera, no 9.5 km distance cap, no south shift
            // into empty water between cities (Dammam ↔ Doha).
            let region = drawerAwareRegion(for: drives.overviewCoordinates, shiftForPitch: false)
            mapPosition = .camera(Self.pitchedCamera(for: region, overview: true))
        } else if let lat = recorder.followLatitude, let lng = recorder.followLongitude {
            mapPosition = .camera(
                Self.pitchedCamera(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    distance: 1_200
                )
            )
        } else {
            mapPosition = .userLocation(followsHeading: false, fallback: .automatic)
        }
    }

    private func focusTrackingLocation() {
        // Pitched camera is required for 3D buildings / elevation — `.userLocation`
        // stays nearly top-down and hides extruded city models.
        let coordinate: CLLocationCoordinate2D?
        if let lat = recorder.followLatitude, let lng = recorder.followLongitude {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let last = recorder.liveRoute.last {
            coordinate = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
        } else {
            coordinate = nil
        }

        guard let coordinate else {
            mapPosition = .userLocation(followsHeading: false, fallback: .automatic)
            return
        }

        let heading = recorder.followCourseDegrees >= 0 ? recorder.followCourseDegrees : 0
        let distance: CLLocationDistance = recorder.phase == .recording ? 680 : 1_050
        // Sticky heading: only yaw the camera on throttled follow ticks (not every GPS hop).
        // Course still rotates the car mark via `bodyRotation`.
        mapPosition = .camera(
            Self.pitchedCamera(center: coordinate, distance: distance, heading: heading)
        )
    }

    /// Shared pitched camera so realistic elevation / 3D buildings actually render.
    private static let mapPitch: Double = 58

    private static func pitchedCamera(
        for region: MKCoordinateRegion,
        heading: CLLocationDirection = 0,
        overview: Bool = false
    ) -> MapCamera {
        let metersPerDegree: CLLocationDistance = 111_000
        let spanMeters = max(region.span.latitudeDelta, region.span.longitudeDelta) * metersPerDegree
        // Overview of multi-city history needs hundreds of km — the old 9.5 km cap
        // zoomed into empty gulf water between Doha and Dammam.
        let maxDistance: CLLocationDistance = overview ? 1_800_000 : 12_000
        let minDistance: CLLocationDistance = overview ? 4_000 : 520
        let distance = max(minDistance, min(spanMeters * (overview ? 1.25 : 1.55), maxDistance))
        return pitchedCamera(
            center: region.center,
            distance: distance,
            heading: heading,
            pitch: overview ? 0 : mapPitch
        )
    }

    private static func pitchedCamera(
        center: CLLocationCoordinate2D,
        distance: CLLocationDistance,
        heading: CLLocationDirection = 0,
        pitch: Double = mapPitch
    ) -> MapCamera {
        MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: heading,
            pitch: pitch
        )
    }

    private var vehicleFilterLabel: String {
        guard let id = selectedVehicleId,
              let v = store.vehicles.first(where: { $0.id == id }) else {
            return "All Cars"
        }
        return v.nickname
    }

    private func region(for trip: Trip) -> MKCoordinateRegion? {
        let coords = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 800)
        guard !coords.isEmpty else { return nil }
        return region(for: coords)
    }

    private func drawerAwareRegion(for trip: Trip, shiftForPitch: Bool = true) -> MKCoordinateRegion? {
        let coordinates = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 800)
        guard !coordinates.isEmpty else { return nil }
        return drawerAwareRegion(for: coordinates, shiftForPitch: shiftForPitch)
    }

    private func drawerAwareRegion(
        for coordinates: [TripCoordinate],
        shiftForPitch: Bool = true
    ) -> MKCoordinateRegion {
        let base = region(for: coordinates)
        let viewportHeight = max(windowSize.height, 1)
        let usableHeight = max(180, viewportHeight - mapTopObstruction - mapBottomObstruction)
        let mapCanvasHeight = viewportHeight + mapTopObstruction + mapBottomObstruction
        let fittedLatitudeDelta = base.span.latitudeDelta * mapCanvasHeight / usableHeight
        let fittedLongitudeDelta = max(
            base.span.longitudeDelta,
            base.span.longitudeDelta * mapCanvasHeight / usableHeight * 0.85
        )

        let center: CLLocationCoordinate2D
        if shiftForPitch {
            // Pitched single-drive focus: look-at sits low; nudge so the route clears the sheet.
            let bottomCover = mapBottomObstruction / mapCanvasHeight
            let shiftFraction = min(0.28, bottomCover * 0.35 + 0.1)
            center = CLLocationCoordinate2D(
                latitude: base.center.latitude - fittedLatitudeDelta * shiftFraction,
                longitude: base.center.longitude
            )
        } else {
            center = base.center
        }

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: fittedLatitudeDelta,
                longitudeDelta: fittedLongitudeDelta
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

struct TripsMapCanvas: View, Equatable {
    let routes: [DriveMapRoute]
    let selected: Trip?
    let activeRoute: [TripCoordinate]
    let isActivelyRecording: Bool
    let showsUserCharacter: Bool
    /// Degrees clockwise from true north; negative when unknown.
    let courseDegrees: Double
    /// Recorder follow pose — keeps the avatar on our route, not MapKit's lagging user location.
    let characterCoordinate: CLLocationCoordinate2D?
    /// Car mark for the live map puck (Uber-style top-down asset).
    var vehicleStyle: VehicleMarkStyle = .sedan
    /// Paint tint for the map puck — brand lime when unset.
    var vehiclePaint: VehiclePaintColor = .brand
    /// When false (historic overview), allow flat camera so multi-city history can fit.
    var locksMinimumPitch: Bool = true
    @Binding var position: MapCameraPosition
    /// Camera heading lives in its own object so continuous pan / rotate only
    /// redraws the car puck — not every polyline in the map content.
    @StateObject private var headingTracker = MapHeadingTracker()

    init(
        routes: [DriveMapRoute],
        selected: Trip?,
        activeRoute: [TripCoordinate],
        isActivelyRecording: Bool,
        showsUserCharacter: Bool,
        courseDegrees: Double,
        characterCoordinate: CLLocationCoordinate2D?,
        vehicleStyle: VehicleMarkStyle = .sedan,
        vehiclePaint: VehiclePaintColor = .brand,
        locksMinimumPitch: Bool = true,
        position: Binding<MapCameraPosition>
    ) {
        self.routes = routes
        self.selected = selected
        self.activeRoute = activeRoute
        self.isActivelyRecording = isActivelyRecording
        self.showsUserCharacter = showsUserCharacter
        self.courseDegrees = courseDegrees
        self.characterCoordinate = characterCoordinate
        self.vehicleStyle = vehicleStyle
        self.vehiclePaint = vehiclePaint
        self.locksMinimumPitch = locksMinimumPitch
        self._position = position
    }

    /// Convenience for previews that hold raw trips.
    init(
        trips: [Trip],
        selected: Trip?,
        activeRoute: [TripCoordinate],
        isActivelyRecording: Bool,
        showsUserCharacter: Bool,
        courseDegrees: Double,
        characterCoordinate: CLLocationCoordinate2D?,
        vehicleStyle: VehicleMarkStyle = .sedan,
        vehiclePaint: VehiclePaintColor = .brand,
        locksMinimumPitch: Bool = true,
        position: Binding<MapCameraPosition>
    ) {
        self.init(
            routes: trips.compactMap(DriveMapRoute.init(trip:)),
            selected: selected,
            activeRoute: activeRoute,
            isActivelyRecording: isActivelyRecording,
            showsUserCharacter: showsUserCharacter,
            courseDegrees: courseDegrees,
            characterCoordinate: characterCoordinate,
            vehicleStyle: vehicleStyle,
            vehiclePaint: vehiclePaint,
            locksMinimumPitch: locksMinimumPitch,
            position: position
        )
    }

    static func == (lhs: TripsMapCanvas, rhs: TripsMapCanvas) -> Bool {
        lhs.position == rhs.position
            && lhs.selected?.id == rhs.selected?.id
            && lhs.showsUserCharacter == rhs.showsUserCharacter
            && lhs.isActivelyRecording == rhs.isActivelyRecording
            && lhs.courseDegrees == rhs.courseDegrees
            && lhs.characterCoordinate?.latitude == rhs.characterCoordinate?.latitude
            && lhs.characterCoordinate?.longitude == rhs.characterCoordinate?.longitude
            && lhs.vehicleStyle == rhs.vehicleStyle
            && lhs.vehiclePaint == rhs.vehiclePaint
            && lhs.locksMinimumPitch == rhs.locksMinimumPitch
            && lhs.activeRoute == rhs.activeRoute
            && lhs.routes == rhs.routes
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .pitch, .rotate]) {
            if showsUserCharacter {
                if let characterCoordinate {
                    Annotation("You", coordinate: characterCoordinate, anchor: .center) {
                        VeloseeteMapCharacter(
                            isLive: isActivelyRecording,
                            courseDegrees: courseDegrees,
                            headingTracker: headingTracker,
                            vehicleStyle: vehicleStyle,
                            vehiclePaint: vehiclePaint
                        )
                    }
                } else {
                    UserAnnotation {
                        VeloseeteMapCharacter(
                            isLive: isActivelyRecording,
                            courseDegrees: courseDegrees,
                            headingTracker: headingTracker,
                            vehicleStyle: vehicleStyle,
                            vehiclePaint: vehiclePaint
                        )
                    }
                }
            }

            ForEach(routes) { route in
                let dim = selected?.id == route.id ? 0.35 : 1.0

                MapPolyline(coordinates: route.coordinates)
                    .stroke(
                        VS.Color.accent.opacity(0.22 * dim),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                    )
                MapPolyline(coordinates: route.coordinates)
                    .stroke(
                        Color.white.opacity(0.75 * dim),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
            }

            if let selected {
                let selectedRoute = TripTrackingLogic.mapDisplayRoute(
                    id: selected.id,
                    points: selected.route,
                    maximumPoints: 800
                )
                if selectedRoute.count >= 2 {
                    let coords = selectedRoute.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }

                    MapPolyline(coordinates: coords)
                        .stroke(
                            VS.Color.accent.opacity(0.28),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: coords)
                        .stroke(VS.Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: coords)
                        .stroke(
                            Color.white.opacity(0.95),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
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
                        RouteStopMarker(isFinish: true, size: 11)
                            .background(Circle().fill(Color(hex: 0x161916)))
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

            // Only show the tip dot when the character avatar isn't already covering it.
            if !showsUserCharacter, let current = activeRoute.last {
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
        .mapStyle(Self.lockedMapStyle)
        .mapControlVisibility(.hidden)
        .preferredColorScheme(.dark)
        .onMapCameraChange(frequency: .continuous) { context in
            // Only the puck counter-rotates; history overview has no puck to update.
            guard showsUserCharacter else { return }
            headingTracker.update(context.camera.heading)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            // Keep enough pitch for extruded buildings when tracking / single-drive focus.
            // Historic multi-city overview must stay flat or distance framing collapses.
            guard locksMinimumPitch, context.camera.pitch < Self.minimumPitch else { return }
            position = .camera(
                MapCamera(
                    centerCoordinate: context.camera.centerCoordinate,
                    distance: context.camera.distance,
                    heading: context.camera.heading,
                    pitch: Self.enforcedPitch
                )
            )
        }
        // Intentionally no `.animation` on character lat/lng — animating the annotation
        // while the camera also eases made the car skate relative to the map.
    }

    /// Street map only (never satellite/hybrid) with realistic elevation so
    /// pitched cameras reveal 3D buildings where Apple provides city data.
    private static let lockedMapStyle: MapStyle = .standard(
        elevation: .realistic,
        pointsOfInterest: .excludingAll,
        showsTraffic: false
    )
    private static let minimumPitch: Double = 48
    private static let enforcedPitch: Double = 58
}

/// Map camera heading, observed only by the car puck.
@MainActor
final class MapHeadingTracker: ObservableObject {
    @Published private(set) var heading: Double = 0

    func update(_ value: Double) {
        // Sub-degree jitter is invisible on the puck; skip the redraw.
        var delta = (value - heading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        guard abs(delta) >= 0.75 else { return }
        heading = value
    }
}

private struct VeloseeteMapCharacter: View {
    let isLive: Bool
    var courseDegrees: Double = -1
    @ObservedObject var headingTracker: MapHeadingTracker
    var vehicleStyle: VehicleMarkStyle = .sedan
    var vehiclePaint: VehiclePaintColor = .brand
    @State private var pulse = false

    private var showsHeading: Bool { courseDegrees >= 0 }

    /// Rotate absolute course into screen space (annotations stay upright).
    private var bodyRotation: Double { courseDegrees - headingTracker.heading }

    private var glow: Color {
        vehiclePaint == .brand ? VS.Color.accent : vehiclePaint.swatch
    }

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(glow.opacity(0.22))
                    .frame(width: 72, height: 72)
                    .scaleEffect(pulse ? 1.18 : 0.9)
                    .opacity(pulse ? 0.12 : 0.7)
            }

            VehicleMark(style: vehicleStyle, size: 64, viewpoint: .map, paint: vehiclePaint)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                .shadow(color: glow.opacity(0.2), radius: 8)
        }
        // Nose of the map asset points up; rotate so travel direction matches course.
        .rotationEffect(.degrees(showsHeading ? bodyRotation : 0))
        .onAppear {
            guard isLive else { return }
            withAnimation(.easeOut(duration: 1.25).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityLabel(
            isLive
                ? "\(vehiclePaint.label) \(vehicleStyle.label) live location"
                : "\(vehiclePaint.label) \(vehicleStyle.label) location"
        )
    }
}

private struct DriveListRow: View, Equatable {
    let row: DriveRowModel
    var isFirst = true
    var isLast = true
    var highlight: Color? = nil

    @State private var startPlace: TripPlaceNames.Place?
    @State private var endPlace: TripPlaceNames.Place?

    static func == (lhs: DriveListRow, rhs: DriveListRow) -> Bool {
        lhs.row == rhs.row && lhs.isFirst == rhs.isFirst
            && lhs.isLast == rhs.isLast && lhs.highlight == rhs.highlight
    }

    /// "Dubai Marina → Al Mustaqbal Street", "Around Dubai Marina", or "Morning drive".
    private var title: String {
        switch (startPlace.map { Self.compact($0.title) }, endPlace.map { Self.compact($0.title) }) {
        case let (start?, end?) where start == end: return "Around \(start)"
        case let (start?, end?): return "\(start) → \(end)"
        default: return row.fallbackTitle
        }
    }

    /// List titles are tight — "Al Mustaqbal Street" → "Al Mustaqbal St".
    private static func compact(_ name: String) -> String {
        let suffixes = [" Street": " St", " Road": " Rd", " Avenue": " Ave", " Drive": " Dr",
                        " Boulevard": " Blvd", " Highway": " Hwy", " Lane": " Ln"]
        for (long, short) in suffixes where name.hasSuffix(long) {
            return String(name.dropLast(long.count)) + short
        }
        return name
    }

    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = 20
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0,
            bottomLeadingRadius: isLast ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0,
            topTrailingRadius: isFirst ? radius : 0,
            style: .continuous
        )
    }

    /// Destination leads (ride-app convention); loops and unknowns fall back.
    private var headline: String {
        let start = startPlace.map { Self.compact($0.title) }
        let end = endPlace.map { Self.compact($0.title) }
        if let start, let end, start == end { return "Around \(start)" }
        return end ?? row.fallbackTitle
    }

    private var origin: String? {
        guard let start = startPlace.map({ Self.compact($0.title) }),
              let end = endPlace.map({ Self.compact($0.title) }),
              start != end else { return nil }
        return start
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MiniRoutePreview(route: row.route)
                .frame(width: 48, height: 48)
                .padding(.trailing, 2)

            // Two lines: where you went, then where from + when.
            VStack(alignment: .leading, spacing: 5) {
                Text(headline)
                    .font(VS.TextStyle.headline())
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                HStack(spacing: 0) {
                    if let note = row.note {
                        Text(note)
                            .font(VS.TextStyle.caption2(.bold))
                            .foregroundStyle(VS.Color.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VS.Color.warning.opacity(0.14), in: Capsule())
                            .fixedSize()
                            .padding(.trailing, 6)
                    }
                    if let origin {
                        // Lime start dot = "from", same marker as the thumbnail and maps.
                        RouteStopMarker(isFinish: false, size: 5)
                            .padding(.trailing, 5)
                            .accessibilityHidden(true)
                        // Origin gives way first; the time never truncates.
                        Text(origin)
                            .lineLimit(1)
                            .layoutPriority(0)
                            .accessibilityLabel("from \(origin)")
                        Text(" · ")
                            .fixedSize()
                    }
                    Text(row.timeLabel)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                }
                .font(VS.TextStyle.caption(.medium))
                .foregroundStyle(VS.Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(row.value)
                    .font(VS.TextStyle.headline())
                    .foregroundStyle(VS.Color.accent)
                    .fixedSize()
                Text(row.detail)
                    .font(VS.TextStyle.caption(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background((highlight?.opacity(0.08) ?? VS.Color.chip), in: shape)
        .overlay(alignment: .top) {
            // Hairline between rows of the same card, inset evenly from both edges.
            if !isFirst {
                Rectangle()
                    .fill(VS.Color.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 14)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(row.accessibilityLabel)")
        .accessibilityHint(row.accessibilityHint ?? "")
        .onAppear {
            // Instant from disk cache; only unseen spots hit the geocoder.
            if let start = row.startCoordinate { startPlace = TripPlaceNames.cached(for: start) }
            if let end = row.endCoordinate { endPlace = TripPlaceNames.cached(for: end) }
        }
        .task(id: row.id) {
            guard startPlace == nil || endPlace == nil else { return }
            let start = await row.startCoordinate.asyncMap { await TripPlaceNames.name(for: $0) } ?? nil
            let end = await row.endCoordinate.asyncMap { await TripPlaceNames.name(for: $0) } ?? nil
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                startPlace = start
                endPlace = end
            }
        }
    }
}

/// Header sparkline: one bar per recent drive, newest in accent.
private struct DriveSparkBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let peak = max(values.max() ?? 1, 0.1)
            let gap: CGFloat = 4
            let barWidth = max(2, (geo.size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(values.indices, id: \.self) { index in
                    let isLatest = index == values.count - 1
                    Capsule()
                        .fill(isLatest ? VS.Color.accent : Color.white.opacity(0.18))
                        .frame(
                            width: barWidth,
                            height: max(4, geo.size.height * CGFloat(values[index] / peak))
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
        }
        .animation(.snappy(duration: 0.35), value: values)
    }
}

/// Start = filled lime dot, finish = hollow neutral ring. Shared by list and detail.
struct RouteStopMarker: View {
    var isFinish: Bool
    var size: CGFloat

    var body: some View {
        if isFinish {
            Circle()
                .strokeBorder(Color.white.opacity(0.85), lineWidth: max(1.5, size * 0.2))
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(VS.Color.accent)
                .frame(width: size, height: size)
        }
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}

private struct MiniRoutePreview: View {
    /// Already simplified to the thumbnail budget by `DrivesListModel`.
    let route: [TripCoordinate]

    var body: some View {
        Canvas { context, size in
            let points = route
            guard points.count >= 2 else {
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.72))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.78, y: size.height * 0.28),
                    control: CGPoint(x: size.width * 0.48, y: size.height * 0.92)
                )
                context.stroke(path, with: .color(VS.Color.accent.opacity(0.7)), lineWidth: 2)
                return
            }

            var minLat = points[0].latitude, maxLat = minLat
            var minLng = points[0].longitude, maxLng = minLng
            for point in points {
                minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
                minLng = min(minLng, point.longitude); maxLng = max(maxLng, point.longitude)
            }
            let midLat = (minLat + maxLat) / 2
            let pad: CGFloat = 10
            let availW = max(size.width - pad * 2, 1)
            let availH = max(size.height - pad * 2, 1)
            let metersPerDegLat = 111_320.0
            let metersPerDegLng = max(1_000.0, 111_320.0 * cos(midLat * .pi / 180))
            let widthM = max((maxLng - minLng) * metersPerDegLng, 40)
            let heightM = max((maxLat - minLat) * metersPerDegLat, 40)
            let scale = min(availW / widthM, availH / heightM)
            let drawW = widthM * scale
            let drawH = heightM * scale
            let originX = (size.width - drawW) / 2
            let originY = (size.height - drawH) / 2

            func project(_ point: TripCoordinate) -> CGPoint {
                CGPoint(
                    x: originX + CGFloat((point.longitude - minLng) * metersPerDegLng * scale),
                    y: originY + CGFloat((maxLat - point.latitude) * metersPerDegLat * scale)
                )
            }

            var path = Path()
            for (i, point) in points.enumerated() {
                if i == 0 { path.move(to: project(point)) }
                else { path.addLine(to: project(point)) }
            }
            context.stroke(
                path,
                with: .color(VS.Color.accent),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )

            // Start: filled lime. Finish: neutral hollow ring — red read as an error.
            let startCenter = project(points[0])
            context.fill(
                Path(ellipseIn: CGRect(x: startCenter.x - 3, y: startCenter.y - 3, width: 6, height: 6)),
                with: .color(VS.Color.accent)
            )
            let endCenter = project(points[points.count - 1])
            let ring = Path(ellipseIn: CGRect(x: endCenter.x - 3, y: endCenter.y - 3, width: 6, height: 6))
            context.fill(ring, with: .color(Color(hex: 0x161916)))
            context.stroke(ring, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DataStore
    let trip: Trip
    let unit: String

    @State private var isPreparingShare = false
    @State private var shareImage: UIImage?
    @AppStorage("veloseete.tracky.mood") private var trackyMoodRaw: String = TrackyMood.chill.rawValue
    @State private var showShareSheet = false
    @State private var shareError: String?
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var routeRegion: MKCoordinateRegion {
        let coords = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 800)
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
        let midLat = (minLat + maxLat) / 2
        // Keep geographic aspect so short routes aren't crushed / off-center.
        let latDelta = max((maxLat - minLat) * 1.55, 0.02)
        let lngDeltaRaw = max((maxLng - minLng) * 1.55, 0.02)
        let cosLat = max(cos(midLat * .pi / 180), 0.2)
        let lngDelta = max(lngDeltaRaw, latDelta / cosLat * 0.55)
        // The route title covers the bottom ~40% of the hero, so give the map that
        // much extra room below the route and keep the line in the clear top part.
        let framedLatDelta = latDelta * 1.7
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: midLat - framedLatDelta * 0.16,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: framedLatDelta,
                longitudeDelta: lngDelta
            )
        )
    }

    private var vehicleName: String {
        store.vehicles.first(where: { $0.id == trip.vehicleId })?.nickname
            ?? store.archivedVehicles.first(where: { $0.id == trip.vehicleId })?.nickname
            ?? "Drive"
    }

    @State private var startPlace: TripPlaceNames.Place?
    @State private var endPlace: TripPlaceNames.Place?
    @State private var placesResolved = false

    private var vehicle: Vehicle? {
        store.vehicles.first(where: { $0.id == trip.vehicleId })
            ?? store.archivedVehicles.first(where: { $0.id == trip.vehicleId })
    }

    var body: some View {
        NavigationStack {
            detailLayout
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Destructive action tucked away, Strava-style — not a permanent button.
                    Menu {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete drive", systemImage: "trash")
                        }
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis")
                        }
                    }
                    .disabled(isDeleting || isPreparingShare)
                    .accessibilityLabel("More actions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await resolvePlaces() }
            .alert(TrackyVoice.Calm.deleteDriveTitle, isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button(TrackyVoice.Calm.deleteDrive, role: .destructive) {
                    Task { await deleteTrip() }
                }
            } message: {
                Text(TrackyVoice.Calm.deleteDriveMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareImage {
                    ActivityShareSheet(items: [shareImage]) {
                        showShareSheet = false
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: Layout

    @Environment(\.windowSize) private var windowSize

    /// Phone: map hero above a scrolling column. Wide (Duo unfolded): the map fills
    /// the left, details scroll in a column on the right.
    @ViewBuilder
    private var detailLayout: some View {
        if VS.Layout.isWide(windowSize) {
            HStack(spacing: 0) {
                routeHero(height: nil)
                    .ignoresSafeArea(.container, edges: [.top, .bottom, .leading])

                ScrollView {
                    detailsStack
                        .padding(.top, 64)
                }
                .scrollIndicators(.hidden)
                .frame(width: VS.Layout.sidePanelWidth + 40)
                .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    routeHero(height: 400)
                    detailsStack
                }
            }
            .scrollIndicators(.hidden)
            // Map runs edge-to-edge under the close button.
            .ignoresSafeArea(.container, edges: .top)
            // Fixed scrim so scrolled stats never sit naked under the toolbar buttons.
            .overlay(alignment: .top) {
                LinearGradient(colors: [VS.Color.bgPrimary.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            // Actions stay reachable at any scroll depth; content insets above them.
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
    }

    private var detailsStack: some View {
        VStack(alignment: .leading, spacing: 22) {
            metaRow
            statGrid
            paceCard
            fuelCard

            if let shareError {
                Text(shareError)
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.warning)
            }
            if let deleteError {
                Text(deleteError)
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.error)
            }
        }
        .padding(.horizontal, VS.Spacing.sheetInset)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    // MARK: Sections

    /// Map with the drive's story on it: where from, where to, when.
    /// `height: nil` fills whatever the layout gives it (wide mode).
    private func routeHero(height: CGFloat?) -> some View {
        routeMap
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: VS.Color.bgPrimary.opacity(0.85), location: 0.55),
                        .init(color: VS.Color.bgPrimary, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) { heroTitle }
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayLine.uppercased())
                .font(VS.TextStyle.label())
                .foregroundStyle(VS.Color.accent)

            // From → to, joined by one line like a trip itinerary.
            VStack(alignment: .leading, spacing: Self.stopSpacing) {
                placeLine(startPlace, time: trip.startedAt, isFinish: false)
                placeLine(endPlace, time: trip.endedAt, isFinish: true)
            }
            .background(alignment: .topLeading) {
                Rectangle()
                    .fill(VS.Color.hairlineStrong)
                    .frame(width: 2)
                    .padding(.leading, 5)
                    // Marker bottom of the first stop → marker top of the last.
                    .padding(.top, Self.markerTop + 12 + 3)
                    .padding(.bottom, Self.stopHeight - Self.markerTop + 3)
            }
        }
        .padding(.horizontal, VS.Spacing.sheetInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private static let stopHeight: CGFloat = 44
    private static let stopSpacing: CGFloat = 16
    private static let markerTop: CGFloat = 7

    private func placeLine(_ place: TripPlaceNames.Place?, time: Date, isFinish: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RouteStopMarker(isFinish: isFinish, size: 12)
                .padding(.top, Self.markerTop)
            VStack(alignment: .leading, spacing: 1) {
                Text(place?.title ?? (placesResolved ? (isFinish ? "Finish" : "Start") : "Finding place"))
                    .font(VS.TextStyle.title3())
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .redacted(reason: placesResolved ? [] : .placeholder)
                Text([isFinish ? "FINISH" : "START", place?.city?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(VS.TextStyle.callout(.semibold))
                .foregroundStyle(VS.Color.textSecondary)
                .padding(.top, 3)
        }
        .frame(height: Self.stopHeight, alignment: .top)
    }

    private var metaRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // A rental drive sits under your car in the log, but it wasn't your car.
                if let vehicle, trip.tripRole != .otherCar {
                    metaChip {
                        VehicleMark(
                            style: VehicleMarkStyle.resolve(vehicle.icon),
                            size: 18,
                            paint: VehiclePaintColor.resolve(vehicle.paintColor)
                        )
                    } text: { vehicle.nickname }
                }
                metaChip {
                    VSIcon(icon: roleIcon, size: 13, weight: .fill, tint: VS.Color.textSecondary)
                } text: { trip.tripRole.label }
                metaChip {
                    VSIcon(icon: trip.source == "auto" ? .target : .play, size: 13, weight: .fill, tint: VS.Color.textSecondary)
                } text: { trip.source == "auto" ? "Auto-tracked" : "Manual" }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Distance leads; time and pace sit beside it as equals.
    private var statGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                statTile(value: distanceValue, unit: unit == "mi" ? "mi" : "km", label: "Distance", icon: .vs(.roadHorizon), isHero: true)
                statTile(value: durationValue.value, unit: durationValue.unit, label: "Duration", icon: .system("timer"))
            }
            GridRow {
                statTile(value: speedValue(trip.avgSpeedKmh), unit: speedUnit, label: "Avg speed", icon: .vs(.gauge))
                statTile(value: speedValue(trip.maxSpeedKmh), unit: speedUnit, label: "Top speed", icon: .system("bolt.fill"))
            }
        }
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PACE")
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.textTertiary)
                    Text(paceHeadline)
                        .font(VS.TextStyle.headline())
                        .foregroundStyle(VS.Color.textPrimary)
                }
                Spacer()
                Text(unit == "mi" ? "MPH" : "KM/H")
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.textTertiary)
            }
            SpeedMixView(
                speedBuckets: trip.speedBuckets,
                avgSpeedKmh: trip.avgSpeedKmh,
                maxSpeedKmh: trip.maxSpeedKmh,
                unit: unit,
                showsHeader: false
            )
        }
        .padding(16)
        .detailCard()
    }

    private var fuelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let liters = estimatedLiters {
                HStack(spacing: 10) {
                    fuelTile(
                        icon: "fuelpump.fill",
                        value: "~" + VolumeFormat.format(liters, unit: vehicle?.fuelVolumeUnit ?? VolumeFormat.liters),
                        label: "Fuel used"
                    )
                    if let cost = estimatedCost(liters: liters) {
                        fuelTile(icon: "creditcard.fill", value: "~" + cost, label: "Est. cost")
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: odometerIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(trip.countsOnVehicle ? VS.Color.success : VS.Color.textTertiary)
                    .padding(.top, 1)
                Text(odometerNote)
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
    }

    private var actionBar: some View {
        HStack {
            PrimaryCTAButton(
                title: isPreparingShare ? "Preparing…" : TrackyVoice.Soft.shareDrive,
                icon: nil,
                isLoading: isPreparingShare
            ) {
                Task { await prepareShare() }
            }

        }
        .padding(.horizontal, VS.Spacing.sheetInset)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background {
            // Content fades out under the bar instead of a hard edge.
            LinearGradient(
                stops: [
                    .init(color: VS.Color.bgPrimary.opacity(0), location: 0),
                    .init(color: VS.Color.bgPrimary, location: 0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Building blocks

    private func metaChip<Icon: View>(@ViewBuilder icon: () -> Icon, text: () -> String) -> some View {
        HStack(spacing: 6) {
            icon()
            Text(text())
                .font(VS.TextStyle.footnote(.semibold))
                .foregroundStyle(VS.Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(VS.Color.chip, in: Capsule())
        .overlay(Capsule().stroke(VS.Color.hairline, lineWidth: 1))
    }

    private enum StatIcon {
        case vs(VSIconName)
        case system(String)
    }

    @ViewBuilder
    private func statIcon(_ icon: StatIcon, tint: Color) -> some View {
        switch icon {
        case .vs(let name):
            VSIcon(icon: name, size: 15, weight: .fill, tint: tint)
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        }
    }

    private func statTile(value: String, unit: String, label: String, icon: StatIcon, isHero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                statIcon(icon, tint: isHero ? VS.Color.navPill : VS.Color.accent)
                Text(label.uppercased())
                    .font(VS.TextStyle.label())
                    .foregroundStyle(isHero ? VS.Color.navPill.opacity(0.7) : VS.Color.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(VS.TextStyle.title())
                    .foregroundStyle(isHero ? VS.Color.navPill : VS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(VS.TextStyle.subheadline(.semibold))
                    .foregroundStyle(isHero ? VS.Color.navPill.opacity(0.7) : VS.Color.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isHero {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(VS.Color.accent)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(VS.Color.chip)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(VS.Color.hairline, lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fuelTile(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VS.Color.accent)
                .frame(width: 36, height: 36)
                .background(VS.Color.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(VS.TextStyle.headline())
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label.uppercased())
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Derived values

    private var dayLine: String {
        if Calendar.current.isDateInToday(trip.startedAt) { return "Today" }
        if Calendar.current.isDateInYesterday(trip.startedAt) { return "Yesterday" }
        return trip.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var timeRangeLine: String {
        let start = trip.startedAt.formatted(date: .omitted, time: .shortened)
        let end = trip.endedAt.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start) – \(end)"
    }

    private var distanceValue: String {
        let value = unit == "mi" ? trip.distanceKm * 0.621371 : trip.distanceKm
        return String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }

    private var durationValue: (value: String, unit: String) {
        let total = Int(trip.durationSec)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return ("\(hours):\(String(format: "%02d", minutes))", "h") }
        return ("\(max(minutes, 1))", "min")
    }

    private var speedUnit: String { unit == "mi" ? "mph" : "km/h" }

    private func speedValue(_ kmh: Double) -> String {
        String(format: "%.0f", unit == "mi" ? kmh * 0.621371 : kmh)
    }

    /// One plain-language read of the speed bands, so the bar has a takeaway.
    private var paceHeadline: String {
        let shares = SpeedBands.fractions(counts: trip.speedBuckets, avgKmh: trip.avgSpeedKmh, maxKmh: trip.maxSpeedKmh)
        guard let top = shares.indices.max(by: { shares[$0] < shares[$1] }), shares[top] > 0 else {
            return "Steady drive"
        }
        let fastShare = shares.dropFirst(3).reduce(0, +)
        if fastShare >= 0.25 { return "Plenty of highway speed" }
        switch top {
        case 0: return "Mostly city pace"
        case 1: return "Mostly open roads"
        case 2: return "Mostly highway cruising"
        default: return "A fast run"
        }
    }

    private var odometerIcon: String {
        if trip.countsOnVehicle { return "checkmark.circle.fill" }
        return trip.tripRole == .otherCar ? "car.fill" : "person.fill"
    }

    private var odometerNote: String {
        if trip.countsOnVehicle {
            return TrackyVoice.Soft.inEstimateBody(distance: DistanceFormat.formatDistance(trip.distanceKm, unit: unit))
        }
        if trip.tripRole == .otherCar {
            return "Rental or borrowed car. Counts toward your driving, not your car’s odometer or fuel."
        }
        return "Passenger trip. It stays in your log and off the odometer."
    }

    private var durationLabel: String {
        let total = Int(trip.durationSec)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1)) min"
    }

    private var vehicleLogs: [FuelLog] {
        store.fuelLogs.filter { $0.vehicleId == trip.vehicleId }
    }

    private var roleIcon: VSIconName {
        switch trip.tripRole {
        case .driver: .gauge
        case .passenger: .user
        case .otherCar: .car
        }
    }

    /// Rough fuel for this leg from the car's own consumption. Passenger legs are skipped.
    private var estimatedLiters: Double? {
        guard trip.countsOnVehicle, trip.distanceKm >= 0.2, let vehicle else { return nil }
        let litersPer100 = DriveMoodBaseline.resolve(
            vehicle: vehicle,
            logs: vehicleLogs,
            manufacturerStandard: store.manufacturerStandard
        )
        guard litersPer100 > 0 else { return nil }
        let liters = trip.distanceKm * litersPer100 / 100
        return liters >= 0.05 ? liters : nil
    }

    /// Priced from the most recent fill-up's per-litre cost.
    private func estimatedCost(liters: Double) -> String? {
        guard let last = vehicleLogs
            .filter({ $0.fuelVolume > 0 && $0.totalCost > 0 })
            .max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        return CurrencyFormat.format(liters * last.totalCost / last.fuelVolume, currency: last.currency)
    }

    private func resolvePlaces() async {
        guard !placesResolved else { return }
        let start = trip.startCoordinate ?? trip.route.first
        let end = trip.endCoordinate ?? trip.route.last
        // Sequential on purpose: CLGeocoder rejects overlapping requests.
        if let start { startPlace = await TripPlaceNames.name(for: start) }
        if let end { endPlace = await TripPlaceNames.name(for: end) }
        placesResolved = true
    }

    private func deleteTrip() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }
        do {
            try await store.deleteTrip(trip)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        shareError = nil
        let mood = TrackyMood(rawValue: trackyMoodRaw) ?? .chill
        let image = await TripShareComposer.render(
            trip: trip,
            unit: unit,
            vehicleName: vehicleName,
            trackyMood: mood
        )
        isPreparingShare = false
        if let image {
            shareImage = image
            presentSystemShare(image)
        } else {
            shareError = "Couldn’t build the share card. Try again."
        }
    }

    private func presentSystemShare(_ image: UIImage) {
        guard let root = UIApplication.shared.veloseeteTopViewController else {
            showShareSheet = true
            return
        }
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: 72, width: 1, height: 1)
            popover.permittedArrowDirections = .up
        }
        root.present(controller, animated: true)
    }

    private var routeMap: some View {
        TripDetailRouteMap(trip: trip, region: routeRegion)
            .equatable()
    }

}

/// The detail hero map, built once per drive. Its own Equatable view so place
/// lookups and store updates on the sheet never rebuild MapKit content.
private struct TripDetailRouteMap: View, Equatable {
    let tripId: String
    let region: MKCoordinateRegion
    let coordinates: [CLLocationCoordinate2D]
    let start: CLLocationCoordinate2D?
    let end: CLLocationCoordinate2D?

    init(trip: Trip, region: MKCoordinateRegion) {
        tripId = trip.id
        self.region = region
        coordinates = TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 800)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        start = (trip.startCoordinate ?? trip.route.first)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        end = (trip.endCoordinate ?? trip.route.last)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tripId == rhs.tripId && lhs.coordinates.count == rhs.coordinates.count
    }

    var body: some View {
        // Pinch to zoom only — panning would fight the page scroll.
        Map(initialPosition: .region(region), interactionModes: [.zoom]) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(VS.Color.accent.opacity(0.22), lineWidth: 12)
                MapPolyline(coordinates: coordinates)
                    .stroke(VS.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let start {
                Annotation("Start", coordinate: start) {
                    routeMarker(color: VS.Color.accent, icon: "play.fill")
                }
            }
            if let end {
                Annotation("Finish", coordinate: end) {
                    routeMarker(color: Color.white, icon: "flag.fill")
                }
            }
        }
        .mapStyle(Self.lockedMapStyle)
        .mapControlVisibility(.hidden)
        .preferredColorScheme(.dark)
    }

    // Flat: the hero is top-down, so 3D terrain cost GPU during the sheet slide without changing the look.
    private static let lockedMapStyle: MapStyle = .standard(
        elevation: .flat,
        pointsOfInterest: .excludingAll,
        showsTraffic: false
    )

    private func routeMarker(color: Color, icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(VS.Color.navPill)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2))
    }
}

// MARK: - My Drives data

/// Everything My Drives derives from the store. Compared each body pass (array
/// buffers short-circuit on identity), so the list rebuilds only on real changes.
struct DrivesInputs: Equatable {
    var trips: [Trip]
    var vehicles: [Vehicle]
    var archivedVehicles: [Vehicle]
    var pending: [PendingTripSave]
    var fuelLogs: [FuelLog]
    var manufacturerStandard: Double?
    var selectedVehicleId: String?
    var sort: DriveSort
    var unit: String
}

struct DriveRowModel: Identifiable, Equatable {
    let id: String
    /// Simplified to the thumbnail budget once, not per draw.
    let route: [TripCoordinate]
    /// Used to name the row "From → To" once places resolve.
    let startCoordinate: TripCoordinate?
    let endCoordinate: TripCoordinate?
    /// Shown until (or instead of) place names — "Morning drive".
    let fallbackTitle: String
    /// "3:20 AM · 18 min" — full line for accessibility.
    let meta: String
    /// "3:20 AM", or "Aug 21 · 3:20 AM" outside day groups.
    let timeLabel: String
    /// Trailing hero value — distance, or top speed on the speed leaderboard.
    let value: String
    /// Under the value: duration, or distance on the speed leaderboard.
    let detail: String
    let note: String?
    let accessibilityLabel: String
    let accessibilityHint: String?

    static func == (lhs: DriveRowModel, rhs: DriveRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.fallbackTitle == rhs.fallbackTitle
            && lhs.meta == rhs.meta
            && lhs.value == rhs.value
            && lhs.detail == rhs.detail
            && lhs.note == rhs.note
            && lhs.route.count == rhs.route.count
    }
}

struct DriveDayGroupModel: Identifiable, Equatable {
    let id: Date
    let title: String
    /// "2 drives · 25.4 km" — nil for single-drive days (the card already says it).
    let summary: String?
    let rows: [DriveRowModel]
}

/// Map-ready polyline for one historic drive.
struct DriveMapRoute: Identifiable, Equatable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]

    init?(trip: Trip) {
        let display: [TripCoordinate] = trip.route.count >= 2
            ? TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 160)
            : [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        guard display.count >= 2 else { return nil }
        id = trip.id
        coordinates = display.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    static func == (lhs: DriveMapRoute, rhs: DriveMapRoute) -> Bool {
        lhs.id == rhs.id && lhs.coordinates.count == rhs.coordinates.count
    }
}

struct DrivesListModel {
    /// Rows are built a page at a time as the list scrolls; the map still gets every drive.
    static let pageSize = 40

    var revision = 0
    var trips: [Trip] = []
    /// More drives exist beyond the rows built so far.
    var hasMoreRows = false
    var pending: [PendingTripSave] = []
    var pendingRows: [DriveRowModel] = []
    /// Day sections for chronological sorts.
    var groups: [DriveDayGroupModel] = []
    /// Flat leaderboard for ranked sorts.
    var flatRows: [DriveRowModel] = []
    var isChronological = true
    var mapRoutes: [DriveMapRoute] = []
    /// Start/end of every drive so the overview frames the full footprint.
    var overviewCoordinates: [TripCoordinate] = []
    var rollupLine = "Tap a drive to explore its route"
    /// Header hero: total distance, value and unit split for typography.
    var heroValue = "0"
    var heroUnit = "km"
    /// "10 drives · 2h 41m · 112 km/h top"
    var heroCaption = "No drives yet"
    /// Distance of the most recent drives, oldest → newest, for the header sparkline.
    var recentBars: [Double] = []

    var isEmpty: Bool { trips.isEmpty && pending.isEmpty }
    var totalCount: Int { trips.count + pending.count }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let groupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static func build(from input: DrivesInputs, revision: Int, rowLimit: Int = pageSize) -> DrivesListModel {
        var model = DrivesListModel()
        model.revision = revision
        model.isChronological = input.sort.isChronological

        // Active garage only — archived cars keep their history, but it
        // doesn't clutter My Drives (their cars aren't in the filter either).
        let activeIds = Set(input.vehicles.map(\.id))
        let selected = input.selectedVehicleId
        var trips = input.trips.filter { activeIds.contains($0.vehicleId) }
        if let selected {
            trips = trips.filter { $0.vehicleId == selected }
        }
        switch input.sort {
        case .recent: trips.sort { $0.startedAt > $1.startedAt }
        case .oldest: trips.sort { $0.startedAt < $1.startedAt }
        case .fastest: trips.sort { $0.maxSpeedKmh > $1.maxSpeedKmh }
        case .longest: trips.sort { $0.distanceKm > $1.distanceKm }
        }
        model.trips = trips
        // Only the first `rowLimit` drives get list rows (route thumbnail, labels);
        // totals, day summaries and map routes below still cover every drive.
        let listed = Array(trips.prefix(rowLimit))
        model.hasMoreRows = trips.count > listed.count

        model.pending = input.pending
            .filter { $0.vehicleId.isEmpty || activeIds.contains($0.vehicleId) }
            .filter { selected == nil || $0.vehicleId == selected || $0.vehicleId.isEmpty }
            .sorted { $0.endedAt > $1.endedAt }

        // Consumption per car once — MetricsCalculator is far too heavy to run per row.
        var fuelRates: [String: (litersPer100: Double, unit: String)?] = [:]
        func fuelLabel(distanceKm: Double, vehicleId: String, counts: Bool) -> String? {
            guard counts, distanceKm >= 0.2 else { return nil }
            if fuelRates[vehicleId] == nil {
                let vehicle = input.vehicles.first { $0.id == vehicleId }
                    ?? input.archivedVehicles.first { $0.id == vehicleId }
                fuelRates[vehicleId] = vehicle.map { vehicle in
                    let rate = DriveMoodBaseline.resolve(
                        vehicle: vehicle,
                        logs: input.fuelLogs.filter { $0.vehicleId == vehicle.id },
                        manufacturerStandard: input.manufacturerStandard
                    )
                    return (rate, vehicle.fuelVolumeUnit)
                }
            }
            guard let rate = fuelRates[vehicleId] ?? nil, rate.litersPer100 > 0 else { return nil }
            let liters = distanceKm * rate.litersPer100 / 100
            guard liters >= 0.05 else { return nil }
            return "~\(VolumeFormat.format(liters, unit: rate.unit))"
        }

        func timeOfDayTitle(_ date: Date) -> String {
            switch Calendar.current.component(.hour, from: date) {
            case 5..<12: return "Morning drive"
            case 12..<17: return "Afternoon drive"
            case 17..<21: return "Evening drive"
            default: return "Night drive"
            }
        }

        func speedLabel(_ kmh: Double) -> String {
            input.unit == "mi"
                ? String(format: "%.0f mph", kmh * 0.621371)
                : String(format: "%.0f km/h", kmh)
        }

        model.pendingRows = model.pending.map { pending in
            let id = pending.id.uuidString
            let day = dayFormatter.string(from: pending.startedAt)
            let duration = DriveListCopy.duration(pending.durationSec)
            let distance = DistanceFormat.formatDistance(pending.distanceKm, unit: input.unit)
            return DriveRowModel(
                id: id,
                route: TripTrackingLogic.mapDisplayRoute(id: id, points: pending.route, maximumPoints: 96),
                startCoordinate: pending.startCoordinate ?? pending.route.first,
                endCoordinate: pending.endCoordinate ?? pending.route.last,
                fallbackTitle: timeOfDayTitle(pending.startedAt),
                meta: "\(day) · \(pending.startedAt.formatted(date: .omitted, time: .shortened)) · \(duration)",
                timeLabel: "\(day) · \(pending.startedAt.formatted(date: .omitted, time: .shortened))",
                value: distance,
                detail: DriveListCopy.shortDuration(pending.durationSec),
                note: "Needs review",
                accessibilityLabel: "\(TrackyVoice.Soft.pendingSection). \(day), \(distance), \(duration)",
                accessibilityHint: "Opens this drive for confirmation"
            )
        }

        func row(_ trip: Trip, showsDay: Bool) -> DriveRowModel {
            let time = trip.startedAt.formatted(date: .omitted, time: .shortened)
            // Leaderboards care which day, not which minute — keeps room for the origin.
            var timeLabel = showsDay ? dayFormatter.string(from: trip.startedAt) : time
            if trip.tripRole != .driver { timeLabel += " · \(trip.tripRole.label)" }
            let meta = "\(timeLabel) · \(DriveListCopy.duration(trip.durationSec))"
            let distance = DistanceFormat.formatDistance(trip.distanceKm, unit: input.unit)
            let fuel = fuelLabel(distanceKm: trip.distanceKm, vehicleId: trip.vehicleId, counts: trip.countsOnVehicle)
            // The speed leaderboard leads with what it ranks by.
            let value = input.sort == .fastest ? speedLabel(trip.maxSpeedKmh) : distance
            let detail = input.sort == .fastest ? distance : DriveListCopy.shortDuration(trip.durationSec)
            return DriveRowModel(
                id: trip.id,
                route: TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 96),
                startCoordinate: trip.startCoordinate ?? trip.route.first,
                endCoordinate: trip.endCoordinate ?? trip.route.last,
                fallbackTitle: timeOfDayTitle(trip.startedAt),
                meta: meta,
                timeLabel: timeLabel,
                value: value,
                detail: detail,
                note: nil,
                accessibilityLabel: "\(meta), \(distance) driven, top \(speedLabel(trip.maxSpeedKmh))\(fuel.map { ", about \($0) fuel" } ?? "")",
                accessibilityHint: nil
            )
        }

        if input.sort.isChronological {
            let calendar = Calendar.current
            // `trips` is already date-sorted, so day order falls out of a single pass.
            var order: [Date] = []
            var byDay: [Date: [Trip]] = [:]
            for trip in trips {
                let day = calendar.startOfDay(for: trip.startedAt)
                if byDay[day] == nil { order.append(day) }
                byDay[day, default: []].append(trip)
            }
            let listedIds = Set(listed.map(\.id))
            let listedDays = order.filter { byDay[$0]?.contains { listedIds.contains($0.id) } ?? false }
            model.groups = listedDays.map { day in
                let dayTrips = byDay[day] ?? []
                let title: String
                if calendar.isDateInToday(day) {
                    title = "Today"
                } else if calendar.isDateInYesterday(day) {
                    title = "Yesterday"
                } else {
                    title = groupFormatter.string(from: day)
                }
                let total = DistanceFormat.formatDistance(dayTrips.reduce(0) { $0 + $1.distanceKm }, unit: input.unit)
                let count = dayTrips.count == 1 ? "1 drive" : "\(dayTrips.count) drives"
                return DriveDayGroupModel(
                    id: day,
                    title: title,
                    summary: dayTrips.count > 1 ? "\(count) · \(total)" : nil,
                    rows: dayTrips.filter { listedIds.contains($0.id) }.map { row($0, showsDay: false) }
                )
            }
        } else {
            model.flatRows = listed.map { row($0, showsDay: true) }
        }

        model.mapRoutes = trips.compactMap(DriveMapRoute.init(trip:))
        model.overviewCoordinates = trips.flatMap { trip -> [TripCoordinate] in
            [trip.startCoordinate, trip.endCoordinate, trip.route.first, trip.route.last].compactMap { $0 }
        }

        if !trips.isEmpty {
            let totalKm = trips.reduce(0) { $0 + $1.distanceKm }
            let topKmh = trips.map(\.maxSpeedKmh).max() ?? 0
            let distance = DistanceFormat.formatDistance(totalKm, unit: input.unit)
            let speed = input.unit == "mi"
                ? String(format: "%.0f mph top", topKmh * 0.621371)
                : String(format: "%.0f km/h top", topKmh)
            let count = trips.count == 1 ? "1 drive" : "\(trips.count) drives"
            model.rollupLine = "\(distance) · \(count) · \(speed)"
            let miles = input.unit == "mi"
            let distanceValue = miles ? totalKm * 0.621371 : totalKm
            model.heroValue = String(format: distanceValue >= 1_000 ? "%.0f" : "%.1f", distanceValue)
            model.heroUnit = miles ? "mi" : "km"
            let totalSeconds = Int(trips.reduce(0) { $0 + $1.durationSec })
            let hours = totalSeconds / 3600, minutes = (totalSeconds % 3600) / 60
            let time = hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, 1))m"
            model.heroCaption = "\(count) · \(time) · \(speed)"
            // Chronological regardless of sort — the sparkline is a timeline.
            model.recentBars = trips
                .sorted { $0.startedAt < $1.startedAt }
                .suffix(12)
                .map(\.distanceKm)
        }
        return model
    }
}

private enum DriveListCopy {
    /// Compact form for the list's right column: "18 min", "1h 5m".
    static func shortDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, 1)) min"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours) hr \(minutes) min" }
        if hours == 1 { return "1 hour" }
        if hours > 1 { return "\(hours) hours" }
        return "\(max(minutes, 1)) min"
    }
}

// MARK: - Tracking panel data

struct TrackingInputs: Equatable {
    var vehicleId: String?
    var vehicles: [Vehicle]
    var trips: [Trip]
    var fuelLogs: [FuelLog]
    var serviceLogs: [ServiceLog]
    var pending: [PendingTripSave]
    var manufacturerStandard: Double?
    var unit: String
}

/// Odometer, month total, fuel watch and consumption baseline for the tracked car.
/// The tracking panel re-renders on every GPS follow tick and HUD snapshot, so
/// these full-history scans run once per data change instead.
struct TrackingInsights {
    struct FuelWarning {
        let title: String
        let detail: String
        let tint: Color
    }

    var vehicleId: String?
    var estimate: OdometerEstimate?
    var monthKm: Double = 0
    var fuelWarning: FuelWarning?
    var vehicleLogs: [FuelLog] = []
    var baselineL100: Double?

    @MainActor
    static func build(vehicle: Vehicle?, store: DataStore, pending: [PendingTripSave]) -> TrackingInsights {
        guard let vehicle else { return TrackingInsights() }
        var insights = TrackingInsights()
        insights.vehicleId = vehicle.id
        insights.vehicleLogs = store.fuelLogs.filter { $0.vehicleId == vehicle.id }
        insights.baselineL100 = DriveMoodBaseline.resolve(
            vehicle: vehicle,
            logs: insights.vehicleLogs,
            manufacturerStandard: store.manufacturerStandard
        )
        let estimate = store.odometerEstimate(vehicleId: vehicle.id)
        insights.estimate = estimate

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let tripsKm = store.trips
            .filter { $0.vehicleId == vehicle.id && $0.startedAt >= monthStart }
            .reduce(0.0) { $0 + $1.distanceKm }
        let pendingKm = pending
            .filter { $0.vehicleId == vehicle.id && $0.startedAt >= monthStart }
            .reduce(0.0) { $0 + $1.distanceKm }
        insights.monthKm = tripsKm + pendingKm

        let prediction = FuelInsightLogic.predictNextFill(
            logs: insights.vehicleLogs,
            estimatedOdometer: estimate?.estimatedKm ?? vehicle.currentOdometer,
            tankCapacityLiters: vehicle.fuelTankCapacity,
            brochureL100km: store.manufacturerStandard,
            learning: VehicleLearningStore.shared.state(for: vehicle.id)
        )
        if let prediction, prediction.urgency >= .watch, prediction.confidence >= 0.4 {
            let range: String
            if let km = prediction.kmRemaining {
                range = DistanceFormat.formatDistance(km, unit: store.defaultDistanceUnit) + " left"
            } else {
                range = "\(prediction.daysRemaining)d left"
            }
            switch prediction.urgency {
            case .empty:
                insights.fuelWarning = FuelWarning(title: "Running on fumes", detail: range, tint: VS.Color.warning)
            case .low:
                insights.fuelWarning = FuelWarning(title: "Low fuel", detail: range, tint: VS.Color.warning)
            case .watch:
                insights.fuelWarning = FuelWarning(title: "Fuel watch", detail: range, tint: VS.Color.accentSecondary)
            case .none:
                break
            }
        }
        return insights
    }
}

// MARK: - My Drives drawer

/// Bottom sheet for My Drives. Owns its drag state so a live drag only re-renders
/// this view — never TripsView or MapKit. The panel is laid out once at its
/// expanded height and slid with a transform + reveal mask, so dragging and the
/// settle spring never re-layout the list.
private struct DrivesDrawer: View, Equatable {
    struct Actions {
        var selectVehicle: (String?) -> Void
        var selectSort: (DriveSort) -> Void
        var openTrip: (String) -> Void
        var openPending: (String) -> Void
        var confirmAll: () -> Void
        var setUpTracking: () -> Void
        var loadMore: () -> Void = {}
    }

    let model: DrivesListModel
    let sort: DriveSort
    let vehicleFilterLabel: String
    let vehicles: [Vehicle]
    let isConfirmingAll: Bool
    let showsSetUpTracking: Bool
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    @Binding var expanded: Bool
    let actions: Actions

    @State private var dragTranslation: CGFloat = 0
    @GestureState private var isDragging = false

    private static let settleSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    static func == (lhs: DrivesDrawer, rhs: DrivesDrawer) -> Bool {
        lhs.model.revision == rhs.model.revision
            && lhs.sort == rhs.sort
            && lhs.vehicleFilterLabel == rhs.vehicleFilterLabel
            && lhs.vehicles == rhs.vehicles
            && lhs.isConfirmingAll == rhs.isConfirmingAll
            && lhs.showsSetUpTracking == rhs.showsSetUpTracking
            && lhs.collapsedHeight == rhs.collapsedHeight
            && lhs.expandedHeight == rhs.expandedHeight
            && lhs.expanded == rhs.expanded
    }

    private var travel: CGFloat { max(0, expandedHeight - collapsedHeight) }

    /// How much of the panel is pushed below the visible area (0 = fully expanded).
    private var hiddenHeight: CGFloat {
        let resting = expanded ? 0 : travel
        return min(travel, max(0, resting + dragTranslation))
    }

    var body: some View {
        let hidden = hiddenHeight
        panel
            .frame(height: expandedHeight, alignment: .top)
            .offset(y: hidden)
            .clipShape(DrawerRevealShape(hiddenTop: hidden, cornerRadius: VS.Radius.panel))
            // Hidden rows sit under the nav; don't let them catch taps.
            .contentShape(DrawerRevealShape(hiddenTop: hidden, cornerRadius: VS.Radius.panel))
            .onChange(of: isDragging) { _, dragging in
                // A cancelled drag skips onEnded — never leave the sheet parked mid-way.
                guard !dragging, dragTranslation != 0 else { return }
                withAnimation(Self.settleSpring) { dragTranslation = 0 }
            }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .highPriorityGesture(dragGesture)

            if model.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
                .fill(Color(hex: 0x161916))
                .overlay(
                    RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
                        .stroke(VS.Color.hairline, lineWidth: 1)
                )
        )
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.26))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                // Overline: section + car filter inline, then status and sort.
                HStack(spacing: 8) {
                    Text("MY DRIVES")
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.textTertiary)
                    Text("·")
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.textTertiary)
                    vehicleMenu
                    Spacer(minLength: 8)
                    if !model.pending.isEmpty {
                        HStack(spacing: 5) {
                            Circle().fill(VS.Color.warning).frame(width: 6, height: 6)
                            Text("\(model.pending.count) to review")
                                .font(VS.TextStyle.caption(.bold))
                                .foregroundStyle(VS.Color.warning)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(VS.Color.warning.opacity(0.14), in: Capsule())
                    }
                    sortMenu
                }

                // Hero: the number is the headline.
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(model.heroValue)
                                .font(VS.TextStyle.display())
                                .foregroundStyle(VS.Color.textPrimary)
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(model.heroUnit)
                                .font(VS.TextStyle.title3())
                                .foregroundStyle(VS.Color.textTertiary)
                        }
                        Text(model.heroCaption)
                            .font(VS.TextStyle.footnote(.semibold))
                            .foregroundStyle(VS.Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(model.heroValue) \(model.heroUnit) total. \(model.heroCaption)")

                    Spacer(minLength: 8)

                    if model.recentBars.count >= 2 {
                        DriveSparkBars(values: model.recentBars)
                            .frame(width: 108, height: 40)
                            .padding(.bottom, 4)
                            .accessibilityLabel("Distance of your last \(model.recentBars.count) drives")
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .accessibilityHint(expanded ? "Collapses the drive list" : "Expands the drive list")
    }

    private var vehicleMenu: some View {
        Menu {
            Button("All Cars") { actions.selectVehicle(nil) }
            ForEach(vehicles) { vehicle in
                Button {
                    actions.selectVehicle(vehicle.id)
                } label: {
                    Label {
                        Text(vehicle.nickname)
                    } icon: {
                        VehicleMark(
                            style: VehicleMarkStyle.resolve(vehicle.icon),
                            size: 18,
                            paint: VehiclePaintColor.resolve(vehicle.paintColor)
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(vehicleFilterLabel.uppercased())
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(VS.Color.accent)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Car filter, \(vehicleFilterLabel)")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(DriveSort.allCases) { option in
                Button {
                    actions.selectSort(option)
                } label: {
                    if sort == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            // Lit when the list isn't in its default order, so a non-default sort is never hidden.
            let isDefault = sort == .recent
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isDefault ? VS.Color.textSecondary : VS.Color.navPill)
                .frame(width: 32, height: 32)
                .background(isDefault ? VS.Color.chip : VS.Color.accent, in: Circle())
                .overlay(Circle().stroke(isDefault ? VS.Color.hairline : .clear, lineWidth: 1))
        }
        .accessibilityLabel("Sort, \(sort.label)")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !model.pendingRows.isEmpty {
                    pendingHeader
                        .padding(.bottom, 10)

                    groupedRows(model.pendingRows, highlight: VS.Color.warning) { actions.openPending($0) }
                }

                if model.isChronological {
                    ForEach(model.groups) { group in
                        sectionHeader(group.title, trailing: group.summary)
                        groupedRows(group.rows) { actions.openTrip($0) }
                    }
                } else {
                    sectionHeader(sort.label, trailing: model.rollupLine)
                    groupedRows(model.flatRows) { actions.openTrip($0) }
                }

                if model.hasMoreRows {
                    // Lazy stack: this only appears near the end, then builds the next page.
                    ProgressView()
                        .tint(VS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .onAppear { actions.loadMore() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Rows fade under the header instead of being sliced by a hard edge.
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                Rectangle()
            }
        )
        .scrollDisabled(!expanded)
        // Collapsed: dragging the list pulls the sheet up. Expanded: the list scrolls.
        .simultaneousGesture(dragGesture, including: expanded ? .subviews : .all)
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(VS.TextStyle.subheadline())
                .foregroundStyle(VS.Color.textSecondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(VS.TextStyle.caption(.semibold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    /// One continuous card per section, but each row stays its own lazy item —
    /// only the outer corners round, so long histories never build off-screen rows.
    @ViewBuilder
    private func groupedRows(
        _ rows: [DriveRowModel],
        highlight: Color? = nil,
        open: @escaping (String) -> Void
    ) -> some View {
        let lastIndex = rows.count - 1
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            Button { open(row.id) } label: {
                DriveListRow(
                    row: row,
                    isFirst: index == 0,
                    isLast: index == lastIndex,
                    highlight: highlight
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var pendingHeader: some View {
        HStack(spacing: 8) {
            Text(TrackyVoice.reviewRequired())
                .font(VS.TextStyle.subheadline())
                .foregroundStyle(VS.Color.warning)
            Text("\(model.pendingRows.count)")
                .font(VS.TextStyle.tag())
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(VS.Color.warning, in: Capsule())
            Spacer()
            Button(action: actions.confirmAll) {
                HStack(spacing: 6) {
                    if isConfirmingAll {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(VS.Color.navPill)
                    } else {
                        VSIcon(icon: .checkCircle, size: 13, weight: .bold, tint: VS.Color.navPill)
                    }
                    Text(isConfirmingAll ? "Locking in…" : TrackyVoice.confirmAll())
                        .font(VS.TextStyle.tag())
                        .foregroundStyle(VS.Color.navPill)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(VS.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isConfirmingAll)
            .accessibilityLabel("Confirm all pending drives")
        }
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            VSIcon(icon: .mapTrifold, size: 40, weight: .regular, tint: VS.Color.accent)
            Text(TrackyVoice.emptyDrivesTitle())
                .font(VS.TextStyle.title3(.semibold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(TrackyVoice.emptyDrivesBody())
                .font(VS.TextStyle.footnote())
                .foregroundStyle(VS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if showsSetUpTracking {
                Button(action: actions.setUpTracking) {
                    HStack(spacing: 8) {
                        VSIcon(icon: .mapPin, size: 18, weight: .fill, tint: VS.Color.navPill)
                        Text(TrackyVoice.Soft.setUpTracking)
                            .font(VS.TextStyle.headline(.semibold))
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
        .padding(.bottom, 16)
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                guard travel > 0 else { return }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                settle(predictedTranslation: value.predictedEndTranslation.height)
            }
    }

    private func settle(predictedTranslation: CGFloat) {
        guard travel > 0 else {
            dragTranslation = 0
            return
        }
        let resting = expanded ? 0 : travel
        // Velocity-aware: a short flick carries through via the predicted end.
        let projected = min(travel, max(0, resting + predictedTranslation))
        let shouldExpand = projected < travel / 2
        if shouldExpand != expanded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(Self.settleSpring) {
            expanded = shouldExpand
            dragTranslation = 0
        }
    }

    private func toggle() {
        guard travel > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Self.settleSpring) {
            expanded.toggle()
        }
    }
}

/// Rounded rect covering only the revealed part of the drawer. Animatable, so the
/// mask tracks the slide offset frame-for-frame inside the same spring.
private struct DrawerRevealShape: Shape {
    var hiddenTop: CGFloat
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { hiddenTop }
        set { hiddenTop = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(max(0, hiddenTop), rect.height)
        let visible = CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: rect.height - top)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: visible)
    }
}

/// Reverse-geocoded start / finish names. Cached on disk per rounded coordinate,
/// so the drive list only geocodes a spot once, ever. Requests run one at a time:
/// CLGeocoder rejects overlapping calls and throttles bursts.
@MainActor
enum TripPlaceNames {
    struct Place: Equatable {
        /// Street or neighbourhood — the recognisable bit.
        let title: String
        let city: String?
    }

    private static let defaultsKey = "tripPlaceNames.v1"
    private static let maxEntries = 2_000
    private static var cache: [String: Place] = loadCache()
    private static let geocoder = CLGeocoder()
    private static var queueTail: Task<Void, Never>?

    static func cached(for coordinate: TripCoordinate) -> Place? {
        cache[key(for: coordinate)]
    }

    static func name(for coordinate: TripCoordinate) async -> Place? {
        let key = key(for: coordinate)
        if let cached = cache[key] { return cached }
        let previous = queueTail
        let lookup = Task { () -> Place? in
            await previous?.value
            if let cached = cache[key] { return cached }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
                  let title = placemark.thoroughfare ?? placemark.name ?? placemark.locality else { return nil }
            let place = Place(title: title, city: placemark.locality == title ? nil : placemark.locality)
            store(place, for: key)
            return place
        }
        queueTail = Task { _ = await lookup.value }
        return await lookup.value
    }

    private static func key(for coordinate: TripCoordinate) -> String {
        // ~11 m buckets: same driveway, same name.
        String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    private static func store(_ place: Place, for key: String) {
        if cache.count >= maxEntries { cache.removeAll(keepingCapacity: true) }
        cache[key] = place
        let encoded = cache.mapValues { [$0.title, $0.city ?? ""] }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }

    private static func loadCache() -> [String: Place] {
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] else { return [:] }
        return raw.compactMapValues { parts in
            guard let title = parts.first, !title.isEmpty else { return nil }
            let city = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            return Place(title: title, city: city)
        }
    }
}

private extension View {
    /// Single surface style for trip detail sections.
    func detailCard() -> some View {
        background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(VS.Color.hairline, lineWidth: 1)
            )
    }
}
