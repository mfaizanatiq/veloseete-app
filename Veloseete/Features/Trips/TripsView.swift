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

private enum DriveDrawerGestureOwner {
    case handle
    case content
    case scrolling
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
    @State private var sort: DriveSort = .recent
    @State private var selectedVehicleId: String? = nil
    @State private var selectedTripId: String? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showTripPermissions = false
    @State private var reviewPendingTrip: PendingTripSave?
    @State private var isConfirmingAll = false
    @State private var detailTrip: Trip?
    @State private var mode: TripsMode = .tracking
    @State private var driveDrawerExpanded = false
    @State private var driveDrawerDragOffset: CGFloat = 0
    @State private var driveDrawerGestureOwner: DriveDrawerGestureOwner?
    let onProfile: () -> Void

    private func autoTrackNudgePromptedKey(for userId: String) -> String {
        "tripRecording.autoTrackPrompted.v1.\(userId)"
    }

    private var filteredTrips: [Trip] {
        // Active garage only — archived cars keep their history, but it
        // doesn't clutter My Drives (their cars aren't in the filter either).
        var list = store.tripsForActiveVehicles
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

    private var filteredPendingTrips: [PendingTripSave] {
        let activeIds = store.activeVehicleIds
        return recorder.pendingSaves
            .filter { activeIds.contains($0.vehicleId) }
            .filter { selectedVehicleId == nil || $0.vehicleId == selectedVehicleId }
            .sorted { $0.endedAt > $1.endedAt }
    }

    /// Whole review queue for active cars, ignoring the car filter — drives the tab badge.
    private var reviewBadgeCount: Int {
        let activeIds = store.activeVehicleIds
        return recorder.pendingSaves.count { activeIds.contains($0.vehicleId) }
    }

    /// Saves every visible pending drive with its suggested odometer — same flow
    /// as confirming one by one, without opening each sheet.
    private func confirmAllPending() async {
        guard !isConfirmingAll else { return }
        isConfirmingAll = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for pending in filteredPendingTrips {
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

    private struct DriveDayGroup: Identifiable {
        let id: Date
        let title: String
        let totalKm: Double
        let trips: [Trip]
    }

    private var groupedTrips: [DriveDayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: filteredTrips) { calendar.startOfDay(for: $0.startedAt) }
        let orderedDays = sort == .oldest ? byDay.keys.sorted() : byDay.keys.sorted(by: >)
        return orderedDays.map { day in
            let trips = byDay[day] ?? []
            return DriveDayGroup(
                id: day,
                title: dayGroupTitle(day),
                totalKm: trips.reduce(0) { $0 + $1.distanceKm },
                trips: trips
            )
        }
    }

    private func dayGroupTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day)
    }

    private var driveRollupLine: String {
        guard !filteredTrips.isEmpty else { return "Tap a drive to explore its route" }
        let totalKm = filteredTrips.reduce(0) { $0 + $1.distanceKm }
        let topKmh = filteredTrips.map(\.maxSpeedKmh).max() ?? 0
        let distance = DistanceFormat.formatDistance(totalKm, unit: store.defaultDistanceUnit)
        let speed = store.defaultDistanceUnit == "mi"
            ? String(format: "%.0f mph top", topKmh * 0.621371)
            : String(format: "%.0f km/h top", topKmh)
        let drives = filteredTrips.count == 1 ? "1 drive" : "\(filteredTrips.count) drives"
        return "\(distance) · \(drives) · \(speed)"
    }

    @ViewBuilder
    private func driveRow(_ trip: Trip, showsDay: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy(duration: 0.3)) {
                selectedTripId = trip.id
                if let region = drawerAwareRegion(for: trip, shiftForPitch: true) {
                    mapPosition = .camera(Self.pitchedCamera(for: region, overview: false))
                }
            }
            detailTrip = trip
        } label: {
            DriveRowView(
                trip: trip,
                unit: store.defaultDistanceUnit,
                showsDay: showsDay
            )
        }
        .buttonStyle(.plain)
    }

    private var driveMapCoordinates: [TripCoordinate] {
        // Bounding samples only — start/end of every drive so overview frames
        // the full historic footprint (e.g. Doha + Dammam), not a subset.
        filteredTrips.flatMap { trip -> [TripCoordinate] in
            var points: [TripCoordinate] = []
            if let start = trip.startCoordinate { points.append(start) }
            if let end = trip.endCoordinate { points.append(end) }
            if let first = trip.route.first { points.append(first) }
            if let last = trip.route.last { points.append(last) }
            return points
        }
    }

    private var usesLocationFocalMap: Bool {
        mode == .tracking || driveMapCoordinates.isEmpty
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
                    trips: mode == .drives ? filteredTrips : [],
                    selected: mode == .drives ? selectedTrip : nil,
                    activeRoute: recorder.liveRoute,
                    isActivelyRecording: recorder.phase == .recording,
                    showsUserCharacter: usesLocationFocalMap,
                    courseDegrees: recorder.followCourseDegrees,
                    characterCoordinate: mapCharacterCoordinate,
                    vehicleStyle: VehicleMarkStyle.resolve(store.currentVehicle?.icon),
                    locksMinimumPitch: mode == .tracking || selectedTrip != nil,
                    position: $mapPosition
                )
                .frame(
                    width: proxy.size.width,
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

            VStack(spacing: 0) {
                // Must not eat taps meant for the map or the top segment.
                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                Group {
                    if mode == .tracking {
                        trackingMode
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        drivesMode
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .floatingInFrame(bottomClearance: VS.Spacing.frameGutter + 78)
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
                                .font(VS.Typography.body(10, weight: .bold))
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
            if selectedVehicleId == nil {
                selectedVehicleId = store.currentVehicle?.id
            }
            syncRecorderVehicle()
            tripPermissions.refreshStatuses()
            driveDrawerExpanded = false
            driveDrawerDragOffset = 0
            if mode == .tracking {
                recorder.ensureMapFollowUpdates()
                focusTrackingLocation()
            } else {
                recorder.stopMapFollowUpdates()
                focusMap()
            }

            // Auto-detect tip is the capsule only — no panel banner.
        }
        .onDisappear {
            recorder.stopMapFollowUpdates()
            driveDrawerExpanded = false
            driveDrawerDragOffset = 0
        }
        .sheet(isPresented: $showTripPermissions) {
            TripPermissionsOnboardingView {
                showTripPermissions = false
            }
            .veloseeteSheet()
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
        .onChange(of: recorder.followTick) { _, _ in
            guard mode == .tracking else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                focusTrackingLocation()
            }
        }
        .onChange(of: recorder.phase) { _, phase in
            guard mode == .tracking else { return }
            if phase == .idle || phase == .watching {
                recorder.ensureMapFollowUpdates()
            }
            withAnimation(.easeInOut(duration: 0.55)) {
                focusTrackingLocation()
            }
        }
        .onChange(of: store.trips.count) { _, _ in
            guard mode == .drives, selectedTripId == nil else { return }
            focusMap()
        }
        .onChange(of: mode) { _, newMode in
            driveDrawerExpanded = false
            driveDrawerDragOffset = 0
            if newMode == .drives {
                selectedTripId = nil
                recorder.stopMapFollowUpdates()
                focusMap()
            } else {
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

    /// Keeps the camera focal point inside the map area that is actually visible
    /// between the top controls and the live bottom panel.
    private var mapTopObstruction: CGFloat { 148 }

    private var mapBottomObstruction: CGFloat {
        let floatChrome = VS.Spacing.frameGutter * 2 + 78
        guard mode == .drives else { return trackingPanelHeight + floatChrome }
        // Resting height only — live drag must NOT resize MapKit every frame (watchdog kill).
        let resting = driveDrawerExpanded ? driveDrawerExpandedHeight : driveDrawerCollapsedHeight
        return resting + floatChrome
    }

    private var trackingPanelHeight: CGFloat {
        let railExtra: CGFloat = trackingStatusPriority != nil ? 56 : 0
        let errorExtra: CGFloat = recorder.lastError == nil ? 0 : 36
        switch recorder.phase {
        // Room for metrics + GPS line + optional error + Pause/End — never clip CTAs.
        case .recording: return 448 + errorExtra
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
                            .font(VS.Typography.heading(13))
                        if item == .drives, reviewBadgeCount > 0 {
                            Text("\(reviewBadgeCount)")
                                .font(VS.Typography.body(10, weight: .bold))
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
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 12)

            trackingPanelBody
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        // Size to content — fixed height was clipping Pause / End when GPS error showed.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
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

    private var trackingFuelWarning: (title: String, detail: String, tint: Color)? {
        guard let vehicle = trackingVehicle else { return nil }
        let estimate = store.odometerEstimate(vehicleId: vehicle.id)
        let prediction = FuelInsightLogic.predictNextFill(
            logs: store.fuelLogs.filter { $0.vehicleId == vehicle.id },
            estimatedOdometer: estimate?.estimatedKm ?? vehicle.currentOdometer,
            tankCapacityLiters: vehicle.fuelTankCapacity,
            brochureL100km: store.manufacturerStandard
        )
        guard let prediction, prediction.urgency >= .watch, prediction.confidence >= 0.4 else {
            return nil
        }
        let range: String = {
            if let km = prediction.kmRemaining {
                return DistanceFormat.formatDistance(km, unit: store.defaultDistanceUnit) + " left"
            }
            return "\(prediction.daysRemaining)d left"
        }()
        switch prediction.urgency {
        case .empty:
            return ("Running on fumes", range, VS.Color.warning)
        case .low:
            return ("Low fuel", range, VS.Color.warning)
        case .watch:
            return ("Fuel watch", range, VS.Color.accentSecondary)
        case .none:
            return nil
        }
    }

    private func monthDrivenKm(for vehicleId: String) -> Double {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let tripsKm = store.trips
            .filter { $0.vehicleId == vehicleId && $0.startedAt >= start }
            .reduce(0.0) { $0 + $1.distanceKm }
        let pendingKm = recorder.pendingSaves
            .filter { $0.vehicleId == vehicleId && $0.startedAt >= start }
            .reduce(0.0) { $0 + $1.distanceKm }
        return tripsKm + pendingKm
    }

    private var trackingPanelBody: some View {
        let vehicle = trackingVehicle
        let vehicleId = vehicle?.id
        let estimate = vehicleId.flatMap { store.odometerEstimate(vehicleId: $0) }
        let liveKm = recorder.phase == .recording ? (recorder.snapshot?.distanceKm ?? 0) : 0
        let odoKm = (estimate?.estimatedKm ?? vehicle?.currentOdometer ?? 0) + liveKm
        let usesMiles = store.defaultDistanceUnit == "mi"
        let odoValue = String(format: "%.0f", usesMiles ? odoKm * 0.621371 : odoKm)
        let odoUnit = usesMiles ? "mi" : "km"
        let monthKm = vehicleId.map(monthDrivenKm(for:)) ?? 0
        let monthLabel = DistanceFormat.formatDistance(monthKm, unit: store.defaultDistanceUnit)

        return VStack(alignment: .leading, spacing: 14) {
            // Identity — car + auto-detect capsule only
            HStack(alignment: .top, spacing: 12) {
                trackingVehiclePicker(vehicle: vehicle)
                Spacer(minLength: 8)
                trackingAutoCapsule
            }

            // Hero odometer — big type owns the panel (Ladder / Any Distance energy)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(odoValue)
                        .font(VS.Typography.heading(60, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                        .minimumScaleFactor(0.48)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: odoValue)
                    Text(odoUnit)
                        .font(VS.Typography.heading(20, weight: .bold))
                        .foregroundStyle(liveKm > 0.05 ? VS.Color.accent : VS.Color.textTertiary)
                }

                HStack(spacing: 8) {
                    Text(odometerCaption(estimate: estimate, liveKm: liveKm))
                        .font(VS.Typography.body(13, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)
                    if recorder.phase == .recording {
                        trackingLivePill(
                            paused: recorder.snapshot?.isPaused == true
                        )
                    }
                }

                Text(TrackyVoice.monthLine(monthLabel))
                    .font(VS.Typography.body(14, weight: .semibold))
                    .foregroundStyle(VS.Color.textSecondary)
            }

            // Single status rail (pending > fuel). Hidden while recording.
            if let rail = trackingStatusPriority {
                trackingStatusRail(rail)
            }

            if let snap = recorder.snapshot, recorder.phase == .recording {
                HStack(spacing: 8) {
                    liveMetric(String(format: "%.1f", snap.distanceKm), "km")
                    liveMetric(formatDuration(snap.durationSec), "time")
                    liveMetric(String(format: "%.0f", snap.currentSpeedKmh), "km/h")
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(recorder.liveRoute.isEmpty ? VS.Color.warning : VS.Color.accent)
                        .frame(width: 7, height: 7)
                        .opacity(recorder.liveRoute.isEmpty ? 1 : pulseOpacity)
                    Text(routeStatusText)
                        .font(VS.Typography.body(12, weight: .semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            if let error = recorder.lastError {
                Text(error)
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.warning)
                    .onTapGesture { recorder.clearError() }
            }

            trackingActionRow
        }
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
                            .font(VS.Typography.heading(14, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(TrackyVoice.pendingSubtitle(
                            distanceLabel: DistanceFormat.formatDistance(km, unit: store.defaultDistanceUnit)
                        ))
                            .font(VS.Typography.body(12, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(TrackyVoice.pendingCTA(count: count))
                        .font(VS.Typography.heading(12, weight: .bold))
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
                    .font(VS.Typography.heading(13, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer(minLength: 4)
                Text(detail)
                    .font(VS.Typography.body(12, weight: .semibold))
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
            pendingIn: estimate?.includesPending == true
        )
    }

    private var pulseOpacity: Double {
        // Soft pulse without a Timer — driven by snapshot updates while recording.
        let tick = Int((recorder.snapshot?.durationSec ?? 0) * 2)
        return tick % 2 == 0 ? 1.0 : 0.45
    }

    private func trackingLivePill(paused: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(paused ? VS.Color.warning : VS.Color.accent)
                .frame(width: 6, height: 6)
                .opacity(paused ? 1 : pulseOpacity)
            Text(paused ? "PAUSED" : "LIVE")
                .font(VS.Typography.mono(10, weight: .bold))
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
                    showTripPermissions = true
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
                    .font(VS.Typography.body(12, weight: .bold))
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

    @ViewBuilder
    private func trackingVehiclePicker(vehicle: Vehicle?) -> some View {
        Menu {
            ForEach(store.vehicles) { option in
                Button {
                    selectedVehicleId = option.id
                } label: {
                    Label {
                        Text(option.nickname)
                    } icon: {
                        VehicleMark(style: VehicleMarkStyle.resolve(option.icon), size: 18)
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let vehicle {
                    VehicleMark(style: VehicleMarkStyle.resolve(vehicle.icon), size: 44)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VS.Color.chip)
                        .frame(width: 44, height: 44)
                        .overlay(
                            VSIcon(icon: .car, size: 18, weight: .fill, tint: VS.Color.textTertiary)
                        )
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(vehicle?.nickname ?? "Select car")
                            .font(VS.Typography.heading(20, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                            .lineLimit(1)
                        if store.vehicles.count > 1 {
                            VSIcon(icon: .caretDown, size: 12, weight: .bold, tint: VS.Color.textTertiary)
                        }
                    }
                    Text(trackingIdentitySubtitle(vehicle))
                        .font(VS.Typography.body(13, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(store.vehicles.isEmpty)
    }

    private func trackingIdentitySubtitle(_ vehicle: Vehicle?) -> String {
        guard let vehicle else { return phaseSubtitle }
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
                            .font(VS.Typography.heading(16, weight: .bold))
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

    private var drivesMode: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                Capsule()
                    .fill(Color.white.opacity(0.26))
                    .frame(width: 42, height: 5)
                    .padding(.top, 8)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My Drives")
                            .font(VS.Typography.heading(28, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text(filteredPendingTrips.isEmpty
                             ? driveRollupLine
                             : TrackyVoice.drivesAwaiting(filteredPendingTrips.count))
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text("\(filteredTrips.count + filteredPendingTrips.count)")
                        .font(VS.Typography.heading(16, weight: .bold))
                        .foregroundStyle(VS.Color.navPill)
                        .frame(minWidth: 36, minHeight: 36)
                        .background(VS.Color.accent, in: Circle())
                }
                .padding(.horizontal, 18)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(driveDrawerGesture(from: .handle))

            filterBar.padding(.horizontal, 18)

            if filteredTrips.isEmpty && filteredPendingTrips.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(driveDrawerGesture(from: .content))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !filteredPendingTrips.isEmpty {
                            HStack(spacing: 8) {
                                Text(TrackyVoice.reviewRequired())
                                    .font(VS.Typography.heading(13, weight: .bold))
                                    .foregroundStyle(VS.Color.warning)
                                Text("\(filteredPendingTrips.count)")
                                    .font(VS.Typography.heading(12, weight: .bold))
                                    .foregroundStyle(VS.Color.navPill)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(VS.Color.warning, in: Capsule())
                                Spacer()
                                Button {
                                    Task { await confirmAllPending() }
                                } label: {
                                    HStack(spacing: 6) {
                                        if isConfirmingAll {
                                            ProgressView()
                                                .controlSize(.mini)
                                                .tint(VS.Color.navPill)
                                        } else {
                                            VSIcon(icon: .checkCircle, size: 13, weight: .bold, tint: VS.Color.navPill)
                                        }
                                        Text(isConfirmingAll ? "Locking in…" : TrackyVoice.confirmAll())
                                            .font(VS.Typography.heading(12, weight: .bold))
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

                            ForEach(filteredPendingTrips) { pending in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    reviewPendingTrip = pending
                                } label: {
                                    PendingDriveRowView(
                                        pending: pending,
                                        unit: store.defaultDistanceUnit
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if !filteredTrips.isEmpty {
                                Text("Confirmed")
                                    .font(VS.Typography.heading(13, weight: .bold))
                                    .foregroundStyle(VS.Color.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 10)
                            }
                        }

                        if sort.isChronological {
                            ForEach(groupedTrips) { group in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.title)
                                        .font(VS.Typography.heading(14, weight: .bold))
                                        .foregroundStyle(VS.Color.textSecondary)
                                    Spacer()
                                    Text(DistanceFormat.formatDistance(group.totalKm, unit: store.defaultDistanceUnit))
                                        .font(VS.Typography.heading(14, weight: .bold))
                                        .foregroundStyle(VS.Color.textPrimary)
                                }
                                .padding(.top, 6)
                                .padding(.horizontal, 2)

                                ForEach(group.trips) { trip in
                                    driveRow(trip, showsDay: false)
                                }
                            }
                        } else {
                            ForEach(filteredTrips) { trip in
                                driveRow(trip, showsDay: true)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDisabled(!driveDrawerExpanded)
                .simultaneousGesture(driveDrawerGesture(from: .content))
            }
        }
        .frame(height: driveDrawerVisibleHeight, alignment: .top)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous))
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: driveDrawerExpanded)
    }

    /// Collapsed sheet — keeps mode picker + bottom nav fully on screen.
    private var driveDrawerCollapsedHeight: CGFloat {
        min(300, UIScreen.main.bounds.height * 0.36)
    }

    /// Expanded sheet — never covers top chrome or the floating bottom nav.
    private var driveDrawerExpandedHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        let reservedTop: CGFloat = 132
        let reservedBottom = VS.Spacing.frameGutter + 78 + 12
        let maxAllowed = max(driveDrawerCollapsedHeight, screen - reservedTop - reservedBottom)
        let target = screen * (filteredTrips.isEmpty && filteredPendingTrips.isEmpty ? 0.48 : 0.56)
        return max(driveDrawerCollapsedHeight, min(maxAllowed, target))
    }

    private var driveDrawerTravel: CGFloat {
        max(0, driveDrawerExpandedHeight - driveDrawerCollapsedHeight)
    }

    /// Live height while dragging — no off-screen offset layout.
    private var driveDrawerVisibleHeight: CGFloat {
        let resting = driveDrawerExpanded ? driveDrawerExpandedHeight : driveDrawerCollapsedHeight
        let proposed = resting - driveDrawerDragOffset
        return min(driveDrawerExpandedHeight, max(driveDrawerCollapsedHeight, proposed))
    }

    private func driveDrawerGesture(from source: DriveDrawerGestureOwner) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if driveDrawerGestureOwner == nil {
                    driveDrawerGestureOwner = drawerGestureOwner(
                        requestedBy: source,
                        initialTranslation: value.translation.height
                    )
                }

                guard driveDrawerGestureOwner != .scrolling else { return }
                driveDrawerDragOffset = value.translation.height
            }
            .onEnded { value in
                defer {
                    driveDrawerGestureOwner = nil
                }

                guard driveDrawerGestureOwner != .scrolling else {
                    driveDrawerDragOffset = 0
                    return
                }
                guard driveDrawerTravel > 0 else {
                    driveDrawerDragOffset = 0
                    return
                }

                let resting = driveDrawerExpanded ? driveDrawerExpandedHeight : driveDrawerCollapsedHeight
                let projected = min(
                    driveDrawerExpandedHeight,
                    max(driveDrawerCollapsedHeight, resting - value.predictedEndTranslation.height)
                )
                let midpoint = (driveDrawerCollapsedHeight + driveDrawerExpandedHeight) / 2
                let shouldExpand = projected > midpoint

                if shouldExpand != driveDrawerExpanded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.08)) {
                    driveDrawerExpanded = shouldExpand
                    driveDrawerDragOffset = 0
                }
            }
    }

    private func drawerGestureOwner(
        requestedBy source: DriveDrawerGestureOwner,
        initialTranslation: CGFloat
    ) -> DriveDrawerGestureOwner {
        if source == .handle { return .handle }
        // Collapsed: content drag expands. Expanded: list scrolls; only handle collapses.
        if !driveDrawerExpanded { return .content }
        return .scrolling
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
            .fill(Color(hex: 0x161916))
            .overlay(
                RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
                    .stroke(VS.Color.hairline, lineWidth: 1)
            )
    }

    private func mapCanvas(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TripsMapCanvas(
                trips: mode == .drives ? filteredTrips : [],
                selected: mode == .drives ? selectedTrip : nil,
                activeRoute: recorder.liveRoute,
                isActivelyRecording: recorder.phase == .recording,
                showsUserCharacter: mode == .tracking,
                courseDegrees: recorder.followCourseDegrees,
                characterCoordinate: mapCharacterCoordinate,
                vehicleStyle: VehicleMarkStyle.resolve(store.currentVehicle?.icon),
                locksMinimumPitch: mode == .tracking || selectedTrip != nil,
                position: $mapPosition
            )
            .frame(height: height)

            HStack(spacing: 7) {
                Circle()
                    .fill(recorder.phase == .recording ? VS.Color.success : VS.Color.textTertiary)
                    .frame(width: 7, height: 7)
                Text(TrackyVoice.mapChip(
                    recording: recorder.phase == .recording,
                    trackingMode: mode == .tracking
                ))
                    .font(VS.Typography.body(10, weight: .bold))
            }
            .foregroundStyle(VS.Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func syncRecorderVehicle() {
        let vehicle = store.vehicles.first(where: { $0.id == selectedVehicleId }) ?? store.currentVehicle
        guard let vehicle else { return }
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
                .font(VS.Typography.heading(22, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(VS.Typography.mono(10, weight: .bold))
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

    private var routeStatusText: String {
        TrackyVoice.routeStatus(accuracy: recorder.lastLocationAccuracy)
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

        if !driveMapCoordinates.isEmpty {
            // Wide historic overview — flat camera, no 9.5 km distance cap, no south shift
            // into empty water between cities (Dammam ↔ Doha).
            let region = drawerAwareRegion(for: driveMapCoordinates, shiftForPitch: false)
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All Cars") { selectedVehicleId = nil }
                    ForEach(store.vehicles) { vehicle in
                        Button {
                            selectedVehicleId = vehicle.id
                        } label: {
                            Label {
                                Text(vehicle.nickname)
                            } icon: {
                                VehicleMark(style: VehicleMarkStyle.resolve(vehicle.icon), size: 18)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VSIcon(icon: .car, size: 14, weight: .fill, tint: VS.Color.textSecondary)
                        Text(vehicleFilterLabel)
                            .font(VS.Typography.heading(14, weight: .bold))
                        VSIcon(icon: .caretDown, size: 11, weight: .bold, tint: VS.Color.textSecondary)
                    }
                    .foregroundStyle(VS.Color.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(VS.Color.chip, in: Capsule())
                    .overlay(Capsule().stroke(VS.Color.hairline, lineWidth: 1))
                }

                Menu {
                    ForEach(DriveSort.allCases) { option in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                sort = option
                            }
                        } label: {
                            if sort == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VSIcon(icon: .chartLine, size: 14, weight: .bold, tint: VS.Color.navPill)
                        Text(sort.label)
                            .font(VS.Typography.heading(14, weight: .bold))
                        VSIcon(icon: .caretDown, size: 11, weight: .bold, tint: VS.Color.navPill)
                    }
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(VS.Color.accent, in: Capsule())
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
            Text(TrackyVoice.emptyDrivesTitle())
                .font(VS.Typography.heading(18))
                .foregroundStyle(VS.Color.textPrimary)
            Text(TrackyVoice.emptyDrivesBody())
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
                        Text(TrackyVoice.Soft.setUpTracking)
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
            : TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 240)
        guard !coords.isEmpty else { return nil }
        return region(for: coords)
    }

    private func drawerAwareRegion(for trip: Trip, shiftForPitch: Bool = true) -> MKCoordinateRegion? {
        let coordinates = trip.route.isEmpty
            ? [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
            : TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 240)
        guard !coordinates.isEmpty else { return nil }
        return drawerAwareRegion(for: coordinates, shiftForPitch: shiftForPitch)
    }

    private func drawerAwareRegion(
        for coordinates: [TripCoordinate],
        shiftForPitch: Bool = true
    ) -> MKCoordinateRegion {
        let base = region(for: coordinates)
        let viewportHeight = max(UIScreen.main.bounds.height, 1)
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

struct TripsMapCanvas: View {
    let trips: [Trip]
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
    /// When false (historic overview), allow flat camera so multi-city history can fit.
    var locksMinimumPitch: Bool = true
    @Binding var position: MapCameraPosition
    @State private var mapHeading: Double = 0

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .pitch, .rotate]) {
            if showsUserCharacter {
                if let characterCoordinate {
                    Annotation("You", coordinate: characterCoordinate, anchor: .center) {
                        VeloseeteMapCharacter(
                            isLive: isActivelyRecording,
                            courseDegrees: courseDegrees,
                            mapHeading: mapHeading,
                            vehicleStyle: vehicleStyle
                        )
                    }
                } else {
                    UserAnnotation {
                        VeloseeteMapCharacter(
                            isLive: isActivelyRecording,
                            courseDegrees: courseDegrees,
                            mapHeading: mapHeading,
                            vehicleStyle: vehicleStyle
                        )
                    }
                }
            }

            ForEach(trips) { trip in
                let displayRoute: [TripCoordinate] = {
                    if trip.route.count >= 2 {
                        return TripTrackingLogic.mapDisplayRoute(
                            id: trip.id,
                            points: trip.route,
                            maximumPoints: 64
                        )
                    }
                    return [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
                }()
                if displayRoute.count >= 2 {
                    let coords = displayRoute.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    let isSelected = selected?.id == trip.id
                    let dim = isSelected ? 0.35 : 1.0

                    MapPolyline(coordinates: coords)
                        .stroke(
                            VS.Color.accent.opacity(0.22 * dim),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: coords)
                        .stroke(
                            Color.white.opacity(0.75 * dim),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                }
            }

            if let selected {
                let selectedRoute = TripTrackingLogic.mapDisplayRoute(
                    id: selected.id,
                    points: selected.route,
                    maximumPoints: 240
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
            mapHeading = context.camera.heading
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
        .animation(.linear(duration: 0.35), value: characterCoordinate?.latitude)
        .animation(.linear(duration: 0.35), value: characterCoordinate?.longitude)
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

private struct VeloseeteMapCharacter: View {
    let isLive: Bool
    var courseDegrees: Double = -1
    var mapHeading: Double = 0
    var vehicleStyle: VehicleMarkStyle = .sedan
    @State private var pulse = false

    private var showsHeading: Bool { courseDegrees >= 0 }

    /// Rotate absolute course into screen space (annotations stay upright).
    private var bodyRotation: Double { courseDegrees - mapHeading }

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(VS.Color.accent.opacity(0.22))
                    .frame(width: 72, height: 72)
                    .scaleEffect(pulse ? 1.18 : 0.9)
                    .opacity(pulse ? 0.12 : 0.7)
            }

            VehicleMark(style: vehicleStyle, size: 64, viewpoint: .map)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                .shadow(color: VS.Color.accent.opacity(0.2), radius: 8)
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
                ? "\(vehicleStyle.label) live location"
                : "\(vehicleStyle.label) location"
        )
    }
}

struct PendingDriveRowView: View {
    let pending: PendingTripSave
    let unit: String

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: pending.startedAt)
    }

    private var durationFormatted: String {
        let total = Int(pending.durationSec)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, 1))m"
    }

    private var distanceValue: String {
        DistanceFormat.formatDistance(pending.distanceKm, unit: unit)
            .replacingOccurrences(of: " km", with: "")
            .replacingOccurrences(of: " mi", with: "")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(distanceValue)
                        .font(VS.Typography.heading(28, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(unit == "mi" ? "mi" : "km")
                        .font(VS.Typography.heading(14, weight: .bold))
                        .foregroundStyle(VS.Color.textTertiary)
                    Text(TrackyVoice.Soft.pendingBadge)
                        .font(VS.Typography.body(9, weight: .bold))
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(VS.Color.warning, in: Capsule())
                }

                Text("\(dayTitle) · \(pending.startedAt.formatted(date: .omitted, time: .shortened)) – \(pending.endedAt.formatted(date: .omitted, time: .shortened))")
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)

                Text(durationFormatted)
                    .font(VS.Typography.heading(13, weight: .bold))
                    .foregroundStyle(VS.Color.textSecondary)
            }

            Spacer(minLength: 6)

            MiniRoutePreview(routeId: pending.id.uuidString, route: pending.route)
                .frame(width: 56, height: 56)

            VSIcon(icon: .caretLeft, size: 16, weight: .bold, tint: VS.Color.warning)
                .rotationEffect(.degrees(180))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VS.Color.warning.opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TrackyVoice.Soft.pendingSection). \(dayTitle), \(DistanceFormat.formatDistance(pending.distanceKm, unit: unit)), \(durationFormatted)")
        .accessibilityHint("Opens this drive for confirmation")
    }
}

struct DriveRowView: View {
    let trip: Trip
    let unit: String
    var showsDay: Bool = true

    private var dayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: trip.startedAt)
    }

    private var distanceValue: String {
        let km = trip.distanceKm
        if unit == "mi" {
            let mi = km * 0.621371
            return String(format: mi >= 100 ? "%.0f" : "%.1f", mi)
        }
        return String(format: km >= 100 ? "%.0f" : "%.1f", km)
    }

    private var timeLine: String {
        let range = "\(trip.startedAt.formatted(date: .omitted, time: .shortened)) – \(trip.endedAt.formatted(date: .omitted, time: .shortened))"
        return showsDay ? "\(dayTitle) · \(range)" : range
    }

    private var speedLine: String {
        let speed = unit == "mi"
            ? String(format: "%.0f mph", trip.maxSpeedKmh * 0.621371)
            : String(format: "%.0f km/h", trip.maxSpeedKmh)
        return "\(trip.durationFormatted) · \(speed) top"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(distanceValue)
                        .font(VS.Typography.heading(28, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(unit == "mi" ? "mi" : "km")
                        .font(VS.Typography.heading(14, weight: .bold))
                        .foregroundStyle(VS.Color.textTertiary)
                }

                Text(timeLine)
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)

                Text(speedLine)
                    .font(VS.Typography.heading(13, weight: .bold))
                    .foregroundStyle(VS.Color.textSecondary)
            }

            Spacer(minLength: 8)

            MiniRoutePreview(routeId: trip.id, route: trip.route)
                .frame(width: 56, height: 56)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VS.Color.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct MiniRoutePreview: View {
    var routeId: String = "preview"
    let route: [TripCoordinate]

    private var displayRoute: [TripCoordinate] {
        TripTrackingLogic.mapDisplayRoute(id: routeId, points: route, maximumPoints: 48)
    }

    var body: some View {
        Canvas { context, size in
            let points = displayRoute
            guard points.count >= 2 else {
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.7))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.8, y: size.height * 0.3),
                    control: CGPoint(x: size.width * 0.5, y: size.height * 0.9)
                )
                context.stroke(path, with: .color(VS.Color.textSecondary.opacity(0.5)), lineWidth: 2)
                return
            }

            let lats = points.map(\.latitude)
            let lngs = points.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLng = lngs.min()!, maxLng = lngs.max()!
            let midLat = (minLat + maxLat) / 2

            // Aspect-fit in meters so the path is centered — not stretched to corners.
            let pad: CGFloat = 7
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

            var path = Path()
            for (i, point) in points.enumerated() {
                let x = originX + CGFloat((point.longitude - minLng) * metersPerDegLng * scale)
                let y = originY + CGFloat((maxLat - point.latitude) * metersPerDegLat * scale)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(
                path,
                with: .color(VS.Color.accent),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(VS.Color.hairline, lineWidth: 1)
                )
        )
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
            : TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 240)
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
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: latDelta,
                longitudeDelta: lngDelta
            )
        )
    }

    private var distanceValue: String {
        let km = trip.distanceKm
        if unit == "mi" {
            let mi = km * 0.621371
            return String(format: mi >= 100 ? "%.0f" : "%.1f", mi)
        }
        return String(format: km >= 100 ? "%.0f" : "%.1f", km)
    }

    private var unitLabel: String { unit == "mi" ? "mi" : "km" }

    private var vehicleName: String {
        store.vehicles.first(where: { $0.id == trip.vehicleId })?.nickname
            ?? store.archivedVehicles.first(where: { $0.id == trip.vehicleId })?.nickname
            ?? "Drive"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    routeMap
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous)
                                .stroke(VS.Color.hairline, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(distanceValue)
                                .font(VS.Typography.heading(56, weight: .bold))
                                .foregroundStyle(VS.Color.textPrimary)
                                .minimumScaleFactor(0.55)
                                .lineLimit(1)
                            Text(unitLabel)
                                .font(VS.Typography.heading(20, weight: .bold))
                                .foregroundStyle(VS.Color.textTertiary)
                            Spacer(minLength: 8)
                            Text(trip.source == "auto" ? "AUTO" : "MANUAL")
                                .font(VS.Typography.body(10, weight: .bold))
                                .foregroundStyle(VS.Color.navPill)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(VS.Color.accent, in: Capsule())
                        }

                        Text(trip.startedAt.formatted(date: .complete, time: .omitted))
                            .font(VS.Typography.heading(16, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)

                        Text("\(trip.startedAt.formatted(date: .omitted, time: .shortened)) – \(trip.endedAt.formatted(date: .omitted, time: .shortened))")
                            .font(VS.Typography.body(14, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    HStack(spacing: 10) {
                        detailHeroStat(trip.durationFormatted, "Drive time")
                        detailHeroStat(speed(trip.avgSpeedKmh), "Average")
                        detailHeroStat(speed(trip.maxSpeedKmh), "Top speed")
                    }

                    HStack(spacing: 12) {
                        VSIcon(icon: .checkCircle, size: 22, weight: .fill, tint: VS.Color.success)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(TrackyVoice.Soft.inEstimateTitle)
                                .font(VS.Typography.heading(15, weight: .bold))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text(TrackyVoice.Soft.inEstimateBody(
                                distance: DistanceFormat.formatDistance(trip.distanceKm, unit: unit)
                            ))
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

                    HStack(spacing: 0) {
                        detailMetric("\(trip.route.count)", "Route points", .mapPin)
                        Rectangle().fill(VS.Color.divider).frame(width: 1, height: 48)
                        detailMetric(trip.route.count >= 10 ? "Good" : "Partial", "GPS quality", .target)
                        Rectangle().fill(VS.Color.divider).frame(width: 1, height: 48)
                        detailMetric(unitLabel, "Distance unit", .roadHorizon)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(VS.Color.hairline, lineWidth: 1)
                    )

                    if let shareError {
                        Text(shareError)
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.warning)
                    }

                    if let deleteError {
                        Text(deleteError)
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.error)
                    }

                    PrimaryCTAButton(
                        title: isPreparingShare ? "Preparing…" : TrackyVoice.Soft.shareDrive,
                        icon: nil,
                        isLoading: isPreparingShare
                    ) {
                        Task { await prepareShare() }
                    }

                    Button {
                        confirmDelete = true
                    } label: {
                        HStack(spacing: 8) {
                            if isDeleting {
                                ProgressView().tint(VS.Color.error)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text("Delete drive")
                                .font(VS.Typography.body(14, weight: .semibold))
                        }
                        .foregroundStyle(VS.Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassCard(radius: VS.Radius.card)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting || isPreparingShare)
                }
                .padding(.horizontal, VS.Spacing.sheetInset)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
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
        Map(initialPosition: .region(routeRegion)) {
            let displayRoute = TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 240)
            if displayRoute.count >= 2 {
                MapPolyline(coordinates: displayRoute.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(VS.Color.accent.opacity(0.22), lineWidth: 12)
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
        .mapStyle(Self.lockedMapStyle)
        .mapControlVisibility(.hidden)
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottomLeading) {
            Text("RECORDED ROUTE")
                .font(VS.Typography.heading(11, weight: .bold))
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(VS.Color.accent, in: Capsule())
                .padding(14)
        }
    }

    private static let lockedMapStyle: MapStyle = .standard(
        elevation: .realistic,
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

    private func detailHeroStat(_ value: String, _ label: String) -> some View {
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

    private func detailMetric(_ value: String, _ label: String, _ icon: VSIconName) -> some View {
        VStack(spacing: 6) {
            VSIcon(icon: icon, size: 18, weight: .duotone, tint: VS.Color.accent)
            Text(value)
                .font(VS.Typography.heading(15, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label)
                .font(VS.Typography.body(11, weight: .medium))
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
