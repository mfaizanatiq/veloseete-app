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
    @State private var role: TripRole = .driver
    /// Car this drive is saved to. Starts as the car that was current when it was
    /// recorded; switch it for a rental or a friend's car.
    @State private var vehicleId: String = ""
    /// Drove a car that isn't in the garage — no need to add a rental just to log it.
    @State private var usesOtherCar = false

    private var effectiveRole: TripRole {
        if role == .passenger { return .passenger }
        return usesOtherCar ? .otherCar : .driver
    }

    private var selectedVehicle: Vehicle? {
        store.vehicles.first { $0.id == vehicleId }
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
        !usesOtherCar && !vehicleId.isEmpty && vehicleId != pending.vehicleId
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
                        vehicleName: usesOtherCar ? Self.otherCarLabel : (selectedVehicle?.nickname ?? pending.vehicleName),
                        unit: store.defaultDistanceUnit,
                        speedBuckets: pending.speedBuckets,
                        role: effectiveRole,
                        roleSelection: $role
                    )

                    if role != .passenger {
                        vehiclePicker
                    }

                    if role == .passenger {
                        Text("Logged as a passenger. Uber, a lift, a friend driving: it stays in your log and off your odometer.")
                            .font(VS.TextStyle.footnote(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if usesOtherCar {
                        Text("Counts toward your driving. Stays off \(pending.vehicleName)’s odometer and fuel.")
                            .font(VS.TextStyle.footnote(.medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let estimateKm {
                        HStack(spacing: 12) {
                            VSIcon(icon: .gauge, size: 22, weight: .duotone, tint: VS.Color.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TrackyVoice.confirmEstimateTitle(km: estimateKm))
                                    .font(VS.TextStyle.headline())
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text(movesToOtherCar
                                     ? "Moves to \(selectedVehicle?.nickname ?? "this car") and stays off \(pending.vehicleName)."
                                     : TrackyVoice.confirmEstimateBody())
                                    .font(VS.TextStyle.footnote(.medium))
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
                    } else {
                        HStack(spacing: 12) {
                            VSIcon(icon: .gauge, size: 22, weight: .duotone, tint: VS.Color.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TrackyVoice.confirmFallbackTitle())
                                    .font(VS.TextStyle.headline())
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text(TrackyVoice.confirmFallbackBody())
                                    .font(VS.TextStyle.footnote(.medium))
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
                    }

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
            .onAppear {
                guard vehicleId.isEmpty else { return }
                vehicleId = store.vehicles.contains { $0.id == pending.vehicleId }
                    ? pending.vehicleId
                    : (store.currentVehicle?.id ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        .veloseeteSheet()
    }

    @ViewBuilder
    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHICH CAR?")
                .font(VS.TextStyle.label())
                .foregroundStyle(VS.Color.textTertiary)
            ScrollView(.horizontal) {
                // Recording car, then Rental / other — both on screen without scrolling.
                HStack(spacing: 8) {
                    if let first = pickerVehicles.first {
                        vehicleChip(first)
                    }
                    chip(isSelected: usesOtherCar, title: Self.otherCarLabel) {
                        usesOtherCar = true
                    } icon: {
                        VSIcon(icon: .car, size: 16, weight: .fill, tint: usesOtherCar ? VS.Color.navPill : VS.Color.textSecondary)
                    }
                    ForEach(pickerVehicles.dropFirst()) { vehicle in
                        vehicleChip(vehicle)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("Rental or a friend’s car? Pick \(Self.otherCarLabel) — no need to add it to your garage.")
                .font(VS.TextStyle.footnote(.medium))
                .foregroundStyle(VS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let otherCarLabel = "Rental / other"

    private var pickerVehicles: [Vehicle] {
        let recording = store.vehicles.filter { $0.id == pending.vehicleId }
        return recording + store.vehicles.filter { $0.id != pending.vehicleId }
    }

    private func vehicleChip(_ vehicle: Vehicle) -> some View {
        chip(isSelected: !usesOtherCar && vehicle.id == vehicleId, title: vehicle.nickname) {
            vehicleId = vehicle.id
            usesOtherCar = false
        } icon: {
            VehicleMark(
                style: VehicleMarkStyle.resolve(vehicle.icon),
                size: 20,
                paint: VehiclePaintColor.resolve(vehicle.paintColor)
            )
        }
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
            saving.role = effectiveRole.rawValue
            // Other-car drives stay filed under the recording car, flagged off its odometer.
            if !usesOtherCar, let selectedVehicle {
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
    var vehicleName: String
    var unit: String
    var speedBuckets: [Int]
    var role: TripRole
    var roleSelection: Binding<TripRole>? = nil

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

            HStack(spacing: 10) {
                reviewFact(icon: .car, title: "Vehicle", value: vehicleName)
                reviewFact(
                    icon: role == .passenger ? .user : (role == .otherCar ? .car : .gauge),
                    title: "Role",
                    value: role.label
                )
            }

            if let roleSelection {
                HStack(spacing: 8) {
                    ForEach([TripRole.driver, .passenger], id: \.self) { item in
                        // An other-car drive is still you driving.
                        let isOn = item == .passenger ? role == .passenger : role != .passenger
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            roleSelection.wrappedValue = item
                        } label: {
                            Text(item == .driver ? "I'm driving" : "I'm a passenger")
                                .font(VS.TextStyle.subheadline(.semibold))
                                .foregroundStyle(isOn ? VS.Color.navPill : VS.Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isOn ? VS.Color.accent : VS.Color.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
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

    private func reviewFact(icon: VSIconName, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            VSIcon(icon: icon, size: 16, weight: .fill, tint: VS.Color.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(VS.TextStyle.label())
                    .foregroundStyle(VS.Color.textTertiary)
                Text(value)
                    .font(VS.TextStyle.subheadline())
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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

    private static let trip: Trip = {
        let end = Date().addingTimeInterval(-3 * 3600)
        let route = TripReviewPreview.sampleRoute
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
