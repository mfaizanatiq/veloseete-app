import MapKit
import SwiftUI

struct TripConfirmSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var recorder: TripRecordingService
    @Environment(\.dismiss) private var dismiss

    let pending: PendingTripSave
    /// Called after a successful confirm with the next pending drive for this car, if any.
    var onConfirmed: ((PendingTripSave?) -> Void)? = nil

    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Two independent answers: who was driving, and which vehicle moved.
    @State private var role: TripRole = .driver
    /// Garage car this drive belongs to. Starts as the car it was recorded on.
    @State private var vehicleId: String = ""
    /// A rental, a friend's car, a taxi — anything not in the garage.
    @State private var usesOtherVehicle = false
    /// Set when the answers were pre-filled from a recent drive (e.g. the rental from this morning).
    @State private var suggestion: TripContext.Suggestion?
    @State private var didPrefill = false

    private var vehicleKind: TripVehicle { usesOtherVehicle ? .other : .garage }

    private var selectedVehicle: Vehicle? {
        store.vehicles.first { $0.id == vehicleId }
    }

    /// The car named in explanations: the one picked, or the one this was recorded on.
    private var carName: String {
        selectedVehicle?.nickname ?? pending.vehicleName
    }

    private var queuePeers: [PendingTripSave] {
        recorder.pendingSaves
            .filter { $0.vehicleId == pending.vehicleId }
            .sorted { $0.endedAt < $1.endedAt }
    }

    private var queueIndex: Int? {
        queuePeers.firstIndex(where: { $0.id == pending.id }).map { $0 + 1 }
    }

    private var estimate: OdometerEstimate? {
        store.odometerEstimate(vehicleId: vehicleId)
    }

    /// The pending km is already in the recording car's estimate; for another car add it on top.
    private var movesToOtherCar: Bool {
        !usesOtherVehicle && !vehicleId.isEmpty && vehicleId != pending.vehicleId
    }

    /// Estimate after this confirm — same total (pending → confirmed), for clarity.
    private var estimateKm: Double? {
        guard let estimate else { return nil }
        guard movesToOtherCar else { return estimate.estimatedKm }
        return VehicleLearningModel.estimatedKm(
            verifiedKm: estimate.estimatedKm,
            trackedKm: pending.distanceKm,
            gpsScale: estimate.gpsScale
        )
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

                    if let queueIndex, queuePeers.count > 1 {
                        Text("\(queueIndex) of \(queuePeers.count)")
                            .font(VS.TextStyle.footnote(.semibold))
                            .foregroundStyle(VS.Color.warning)
                    }

                    TripReviewSummary(
                        startedAt: pending.startedAt,
                        distanceKm: pending.distanceKm,
                        durationSec: pending.durationSec,
                        maxSpeedKmh: pending.maxSpeedKmh,
                        avgSpeedKmh: pending.avgSpeedKmh,
                        unit: store.defaultDistanceUnit,
                        speedBuckets: pending.speedBuckets
                    )

                    whoDrovePicker
                    vehiclePicker
                    outcomeCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.TextStyle.footnote(.medium))
                            .foregroundStyle(VS.Color.error)
                    }

                    PrimaryCTAButton(
                        title: TrackyVoice.confirmCTA(hasNext: queuePeers.count > 1),
                        icon: .checkCircle,
                        isLoading: isSaving
                    ) {
                        Task { await save() }
                    }

                    Button(TrackyVoice.discardCTA()) {
                        recorder.discardPending(id: pending.id)
                        dismiss()
                    }
                    .font(VS.TextStyle.headline())
                    .foregroundStyle(VS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(.horizontal, VS.Spacing.sheetInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .onAppear(perform: prefill)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        .veloseeteSheet()
    }

    /// Start from the car it was recorded on and the answers a recent drive implies.
    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        vehicleId = store.vehicles.contains { $0.id == pending.vehicleId }
            ? pending.vehicleId
            : (store.currentVehicle?.id ?? "")
        // An answer already on the drive wins over a guess.
        if let kind = pending.vehicleKind, let known = TripVehicle(rawValue: kind) {
            role = pending.tripRole == .passenger ? .passenger : .driver
            usesOtherVehicle = known == .other
            return
        }
        let guess = TripContext.suggest(startedAt: pending.startedAt, recentTrips: store.trips)
        role = guess.role
        usesOtherVehicle = guess.vehicle == .other
        suggestion = guess.followsDriveEndedAt == nil ? nil : guess
    }

    // MARK: Who drove

    private var whoDrovePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WHO WAS DRIVING?")
            HStack(spacing: 8) {
                choicePill("I was driving", icon: .gauge, isSelected: role != .passenger) { role = .driver }
                choicePill("Someone else", icon: .user, isSelected: role == .passenger) { role = .passenger }
            }
        }
    }

    // MARK: Which vehicle

    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WHICH VEHICLE?")
            ScrollView(.horizontal) {
                // Recording car first, then Another vehicle — both visible without scrolling.
                HStack(spacing: 8) {
                    if let first = pickerVehicles.first {
                        vehicleChip(first)
                    }
                    chip(isSelected: usesOtherVehicle, title: Self.otherVehicleLabel) {
                        usesOtherVehicle = true
                    } icon: {
                        VSIcon(icon: .car, size: 16, weight: .fill, tint: usesOtherVehicle ? VS.Color.navPill : VS.Color.textSecondary)
                    }
                    ForEach(pickerVehicles.dropFirst()) { vehicle in
                        vehicleChip(vehicle)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let followed = suggestion?.followsDriveEndedAt, usesOtherVehicle, role != .passenger {
                Text("Set from your drive at \(followed.formatted(date: .omitted, time: .shortened)) in another vehicle. Change it if this one was different.")
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A rental, a friend’s car, a taxi? Pick Another vehicle — it doesn’t need to be in your garage.")
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let otherVehicleLabel = "Another vehicle"

    private var pickerVehicles: [Vehicle] {
        let recording = store.vehicles.filter { $0.id == pending.vehicleId }
        return recording + store.vehicles.filter { $0.id != pending.vehicleId }
    }

    private func vehicleChip(_ vehicle: Vehicle) -> some View {
        chip(isSelected: !usesOtherVehicle && vehicle.id == vehicleId, title: vehicle.nickname) {
            vehicleId = vehicle.id
            usesOtherVehicle = false
        } icon: {
            VehicleMark(
                style: VehicleMarkStyle.resolve(vehicle.icon),
                size: 20,
                paint: VehiclePaintColor.resolve(vehicle.paintColor)
            )
        }
    }

    // MARK: What it means

    /// What this combination does to the odometer, fuel and your driving stats — in words.
    private var outcomeCard: some View {
        let copy = outcomeCopy
        return HStack(alignment: .top, spacing: 12) {
            VSIcon(icon: copy.icon, size: 22, weight: .duotone, tint: VS.Color.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title)
                    .font(VS.TextStyle.headline())
                    .foregroundStyle(VS.Color.textPrimary)
                Text(copy.body)
                    .font(VS.TextStyle.footnote(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VS.Color.hairline, lineWidth: 1)
        )
        .animation(.snappy(duration: 0.2), value: role)
        .animation(.snappy(duration: 0.2), value: usesOtherVehicle)
    }

    private var outcomeCopy: (icon: VSIconName, title: String, body: String) {
        let youDrove = role != .passenger
        switch (youDrove, vehicleKind) {
        case (true, .garage):
            if let estimateKm {
                return (
                    .gauge,
                    TrackyVoice.confirmEstimateTitle(km: estimateKm),
                    movesToOtherCar
                        ? "Moves to \(carName) and stays off \(pending.vehicleName)."
                        : TrackyVoice.confirmEstimateBody()
                )
            }
            return (.gauge, TrackyVoice.confirmFallbackTitle(), TrackyVoice.confirmFallbackBody())
        case (false, .garage):
            return (
                .car,
                "\(carName) still did these km",
                "Its odometer and fuel count them — the car moved. They stay out of your driving stats and badges."
            )
        case (true, .other):
            return (
                .gauge,
                "Your driving, not your car’s",
                "Counts toward your driving stats. \(carName)’s odometer and fuel stay untouched."
            )
        case (false, .other):
            return (
                .user,
                "Just for your history",
                "A ride in another vehicle: it stays in My Drives, off every car and off your driving stats."
            )
        }
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.TextStyle.label())
            .foregroundStyle(VS.Color.textTertiary)
    }

    private func choicePill(
        _ title: String,
        icon: VSIconName,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            select()
        } label: {
            HStack(spacing: 8) {
                VSIcon(icon: icon, size: 15, weight: .fill, tint: isSelected ? VS.Color.navPill : VS.Color.textSecondary)
                Text(title)
                    .font(VS.TextStyle.subheadline(.semibold))
                    .foregroundStyle(isSelected ? VS.Color.navPill : VS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? VS.Color.accent : VS.Color.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chip<Icon: View>(
        isSelected: Bool,
        title: String,
        select: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            select()
        } label: {
            HStack(spacing: 7) {
                icon()
                Text(title)
                    .font(VS.TextStyle.subheadline(.semibold))
                    .foregroundStyle(isSelected ? VS.Color.navPill : VS.Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 9)
            .background(isSelected ? VS.Color.accent : VS.Color.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            var saving = pending
            saving.role = (role == .passenger ? TripRole.passenger : .driver).rawValue
            saving.vehicleKind = vehicleKind.rawValue
            // Another-vehicle drives stay filed under the car they were recorded on,
            // flagged so that car's odometer and fuel ignore them.
            if !usesOtherVehicle, let selectedVehicle {
                saving.vehicleId = selectedVehicle.id
                saving.vehicleName = selectedVehicle.nickname
            }
            _ = try await store.saveTrip(saving, odometer: pending.suggestedOdometer, applyOdometer: false)
            recorder.markPendingSaved(id: pending.id)
            let next = recorder.pendingSaves
                .filter { $0.vehicleId == pending.vehicleId }
                .sorted { $0.endedAt < $1.endedAt }
                .first
            dismiss()
            onConfirmed?(next)
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

    @State private var position: MapCameraPosition = .automatic

    private var framed: [CLLocationCoordinate2D] {
        coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func reframe(_ size: CGSize) {
        guard let rect = RouteFraming.mapRect(for: framed, viewSize: size, insets: .card) else { return }
        position = .rect(rect)
    }

    var body: some View {
        GeometryReader { proxy in
            map
                .onAppear { reframe(proxy.size) }
                .onChange(of: proxy.size) { _, size in reframe(size) }
        }
    }

    private var map: some View {
        Map(position: $position, interactionModes: []) {
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
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .preferredColorScheme(.dark)
        .accessibilityLabel("Recorded trip route")
    }
}

/// Shared facts for a drive review and a saved drive: role, headline stats, speed bands.
struct TripReviewSummary: View {
    var startedAt: Date
    var distanceKm: Double
    var durationSec: Double
    var maxSpeedKmh: Double
    var avgSpeedKmh: Double
    var unit: String
    var speedBuckets: [Int]

    private var distanceLabel: String {
        DistanceFormat.formatDistance(distanceKm, unit: unit)
    }

    private var durationLabel: String {
        let total = Int(durationSec)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    private var topSpeedLabel: String {
        let value = unit == "mi" ? maxSpeedKmh * 0.621371 : maxSpeedKmh
        let suffix = unit == "mi" ? "mph" : "km/h"
        return String(format: "%.0f %@", value, suffix)
    }

    private var headline: String {
        let time = startedAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(startedAt) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(startedAt) { return "Yesterday, \(time)" }
        let day = startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day), \(time)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(VS.TextStyle.title2())
                    .foregroundStyle(VS.Color.textPrimary)
                Text("\(distanceLabel)  ·  \(durationLabel)")
                    .font(VS.TextStyle.callout(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }

            HStack(spacing: 8) {
                reviewStat(distanceLabel, "Distance")
                reviewStat(durationLabel, "Duration")
                reviewStat(topSpeedLabel, "Top")
            }

            speedDistribution
        }
    }

    private var speedDistribution: some View {
        SpeedMixView(speedBuckets: speedBuckets, avgSpeedKmh: avgSpeedKmh, maxSpeedKmh: maxSpeedKmh, unit: unit)
            .padding(14)
            .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VS.Color.hairline, lineWidth: 1)
            )
    }

    private func reviewStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(VS.TextStyle.label())
                .foregroundStyle(VS.Color.textTertiary)
            Text(value)
                .font(VS.TextStyle.headline())
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VS.Color.hairline, lineWidth: 1)
        )
    }
}

/// Share of the drive spent in each speed band — bar plus labelled legend.
struct SpeedMixView: View {
    var speedBuckets: [Int]
    var avgSpeedKmh: Double
    var maxSpeedKmh: Double
    var unit: String
    var showsHeader = true

    private var fractions: [Double] {
        SpeedBands.fractions(counts: speedBuckets, avgKmh: avgSpeedKmh, maxKmh: maxSpeedKmh)
    }

    /// Same km/h buckets, labeled in the user's unit.
    private var bandLabels: [String] {
        unit == "mi" ? ["<31", "31–50", "50–68", "68–99", "99+"] : SpeedBands.labels
    }

    private var bandColors: [Color] {
        [
            VS.Color.accentSecondary,
            VS.Color.accent,
            VS.Color.warning,
            Color(hex: 0xF97316),
            VS.Color.routeEnd
        ]
    }

    var body: some View {
        let shares = fractions
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack {
                    Text("Speed")
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.textTertiary)
                    Spacer()
                    Text(unit == "mi" ? "MPH" : "KM/H")
                        .font(VS.TextStyle.label())
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(shares.indices, id: \.self) { index in
                        Rectangle()
                            .fill(bandColors[index])
                            .frame(width: geo.size.width * shares[index])
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack(alignment: .top, spacing: 4) {
                ForEach(bandLabels.indices, id: \.self) { index in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(bandColors[index])
                            .frame(width: 6, height: 6)
                        Text(bandLabels[index])
                            .font(VS.TextStyle.label(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(Int((shares[index] * 100).rounded()))%")
                            .font(VS.TextStyle.tag())
                            .foregroundStyle(VS.Color.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Speed mix: " + bandLabels.indices
                .map { "\(bandLabels[$0]) \(unit == "mi" ? "mph" : "km/h") \(Int((shares[$0] * 100).rounded())) percent" }
                .joined(separator: ", ")
        )
    }
}

#if DEBUG
/// Simulator-only — review sheet over the demo garage, so the car picker has cars.
/// Launch with: `-TripReviewPreview`
struct TripReviewPreview: View {
    @StateObject private var store = DataStore.shared

    static let sampleRoute: [TripCoordinate] = (0..<40).map { i in
        TripCoordinate(latitude: 25.20 + Double(i) * 0.0016, longitude: 55.27 + sin(Double(i) / 6) * 0.004)
    }

    private static let pending: PendingTripSave = {
        let end = Date().addingTimeInterval(-20 * 60)
        let route = sampleRoute
        return PendingTripSave(
            id: UUID(),
            vehicleId: "demo-coolray",
            vehicleName: "Coolray",
            startedAt: end.addingTimeInterval(-24 * 60),
            endedAt: end,
            distanceKm: 18.6,
            durationSec: 24 * 60,
            avgSpeedKmh: 46,
            maxSpeedKmh: 92,
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: route,
            source: "auto",
            suggestedOdometer: 0,
            speedBuckets: [30, 22, 12, 2, 0]
        )
    }()

    init() {
        DataStore.shared.seedProductShots()
    }

    var body: some View {
        TripConfirmSheet(pending: Self.pending)
            .environmentObject(store)
            .environmentObject(TripRecordingService.shared)
            .preferredColorScheme(.dark)
            .tint(VS.Color.accent)
    }
}

/// Simulator-only — a saved drive's detail sheet over the demo garage.
/// Launch with: `-TripDetailPreview`
struct TripDetailPreview: View {
    @StateObject private var store = DataStore.shared

    /// `-TripRoute ns|ew|short|loop|diag` — route shapes that stress the map framing.
    private static var route: [TripCoordinate] {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-TripRoute"), args.indices.contains(flag + 1) else {
            return TripReviewPreview.sampleRoute
        }
        let n = 60
        func line(_ f: (Double) -> (Double, Double)) -> [TripCoordinate] {
            (0..<n).map { i in
                let (lat, lng) = f(Double(i) / Double(n - 1))
                return TripCoordinate(latitude: 25.20 + lat, longitude: 55.27 + lng)
            }
        }
        switch args[flag + 1] {
        case "ew": return line { t in (sin(t * 6) * 0.01, t * 0.30) }          // ~30 km east-west
        case "short": return line { t in (t * 0.003, sin(t * 4) * 0.0008) }   // ~300 m
        case "loop": return line { t in (sin(t * .pi * 2) * 0.05, (1 - cos(t * .pi * 2)) * 0.05) }
        case "diag": return line { t in (t * 0.22, t * 0.22) }
        default: return line { t in (t * 0.30, sin(t * 5) * 0.012) }           // ~33 km north-south
        }
    }

    private static let trip: Trip = {
        let end = Date().addingTimeInterval(-3 * 3600)
        let route = Self.route
        return Trip(
            id: "preview-detail",
            vehicleId: "demo-coolray",
            startedAt: end.addingTimeInterval(-24 * 60),
            endedAt: end,
            distanceKm: 18.6,
            durationSec: 24 * 60,
            avgSpeedKmh: 46,
            maxSpeedKmh: 92,
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: route,
            source: "auto",
            speedBuckets: [30, 22, 12, 2, 0]
        )
    }()

    init() {
        DataStore.shared.seedProductShots()
    }

    var body: some View {
        TripDetailView(trip: Self.trip, unit: "km")
            // In the app it's a sheet with veloseeteSheet(allowsWide: true) — it lays itself out.
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(VS.Color.accent)
    }
}
#endif
