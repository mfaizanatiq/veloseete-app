import SwiftUI
import MapKit

/// Detail view for a single fuel log — everything captured at the pump,
/// plus the efficiency of the tank interval it closes. Edit and delete live here.
struct FillDetailSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var efficiencyUnit = EfficiencyUnitStore.shared

    let log: FuelLog

    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    /// Live copy — reflects edits saved while this sheet is open.
    private var currentLog: FuelLog {
        store.fuelLogs.first { $0.id == log.id } ?? log
    }

    private var vehicle: Vehicle? {
        store.vehicles.first { $0.id == currentLog.vehicleId }
    }

    private var volumeUnit: String {
        vehicle?.fuelVolumeUnit ?? VolumeFormat.liters
    }

    private var distanceUnit: String {
        store.defaultDistanceUnit
    }

    /// The fill logged immediately before this one for the same vehicle.
    private var previousLog: FuelLog? {
        store.fuelLogs
            .filter { $0.vehicleId == currentLog.vehicleId && $0.timestamp < currentLog.timestamp }
            .max { $0.timestamp < $1.timestamp }
    }

    private var distanceSincePrevious: Double? {
        guard let previousLog else { return nil }
        let distance = currentLog.odometerReading - previousLog.odometerReading
        return distance > 0 ? distance : nil
    }

    /// L/100km for the interval this fill closes — includes partials since prior full tank.
    private var intervalEfficiency: Double? {
        MetricsCalculator.intervalEfficiency(
            closingFillId: currentLog.id,
            vehicleId: currentLog.vehicleId,
            logs: store.fuelLogs
        )?.litersPer100km
    }

    /// No measured tank closes here — a rough read from this fill's litres over the
    /// km since the previous fill, once that's long enough to mean something.
    private var fillToFillEstimate: Double? {
        guard intervalEfficiency == nil,
              let distance = distanceSincePrevious,
              distance >= MetricsCalculator.minEstimateKm,
              let l100 = EfficiencyFormat.litersPer100km(distanceKm: distance, fuelLiters: currentLog.fuelVolume),
              MetricsCalculator.plausibleLitersPer100km.contains(l100) else { return nil }
        return l100
    }

    private var stationCoordinate: CLLocationCoordinate2D? {
        guard let lat = currentLog.stationLatitude,
              let lng = currentLog.stationLongitude,
              lat != 0 || lng != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VS.Spacing.lg) {
                    heroCard
                    metricGrid

                    if let efficiency = intervalEfficiency {
                        efficiencyCard(efficiency)
                    } else if let estimate = fillToFillEstimate {
                        efficiencyCard(estimate, isEstimate: true)
                    }

                    if currentLog.stationName != nil {
                        stationSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.TextStyle.footnote())
                            .foregroundStyle(VS.Color.error)
                    }

                    actions
                }
                .padding(.horizontal, VS.Spacing.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .veloseetePage()
            .navigationTitle("Fill details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                RefuelSheetView(vehicleId: currentLog.vehicleId, editing: currentLog)
            }
            .confirmationDialog(
                "Delete this fill?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(TrackyVoice.Calm.deleteFill, role: .destructive) {
                    Task { await deleteLog() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(TrackyVoice.Calm.deleteFillMessage)
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentLog.timestamp.formatted(date: .complete, time: .omitted))
                .font(VS.TextStyle.caption(.medium))
                .foregroundStyle(VS.Color.textTertiary)

            Text(CurrencyFormat.format(currentLog.totalCost, currency: currentLog.currency))
                .font(VS.TextStyle.largeTitle())
                .foregroundStyle(VS.Color.textPrimary)

            HStack(spacing: 8) {
                tankPill
                Text(String(
                    format: "%@ %.3f / %@",
                    CurrencyFormat.symbols[currentLog.currency] ?? currentLog.currency,
                    currentLog.pricePerUnit,
                    VolumeFormat.suffix(volumeUnit)
                ))
                .font(VS.TextStyle.caption(.medium))
                .foregroundStyle(VS.Color.textSecondary)
            }
        }
        .padding(VS.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(elevated: true)
    }

    private var tankPill: some View {
        Text(currentLog.isFullTank ? "Full tank" : "Partial fill")
            .font(VS.TextStyle.caption2(.semibold))
            .foregroundStyle(currentLog.isFullTank ? VS.Color.accentSecondary : VS.Color.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    currentLog.isFullTank
                        ? VS.Color.accentSecondary.opacity(0.14)
                        : Color.white.opacity(0.06)
                )
            )
    }

    private var metricGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricTile(
                    icon: .gasPump,
                    label: "Volume",
                    value: VolumeFormat.format(currentLog.fuelVolume, unit: volumeUnit)
                )
                metricTile(
                    icon: .gauge,
                    label: "Odometer",
                    value: DistanceFormat.formatOdometer(currentLog.odometerReading, unit: distanceUnit)
                )
            }
            if let distance = distanceSincePrevious {
                metricTile(
                    icon: .roadHorizon,
                    label: "Since previous fill",
                    value: DistanceFormat.formatDistance(distance, unit: distanceUnit)
                )
            }
        }
    }

    private func metricTile(icon: VSIconName, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                VSIcon(icon: icon, size: 12, weight: .regular, tint: VS.Color.textTertiary)
                Text(label.uppercased())
                    .font(VS.TextStyle.caption2(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
            }
            Text(value)
                .font(VS.TextStyle.title2())
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricInset()
    }

    private func efficiencyCard(_ efficiency: Double, isEstimate: Bool = false) -> some View {
        HStack(spacing: 12) {
            VSIcon(icon: .chartLine, size: 20, weight: .bold, tint: VS.Color.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(isEstimate ? "SINCE LAST FILL · ROUGH" : "THIS TANK")
                    .font(VS.TextStyle.caption2(.medium))
                    .foregroundStyle(VS.Color.textTertiary)
                Text((isEstimate ? "~" : "") + EfficiencyFormat.format(efficiency, unit: efficiencyUnit.unit))
                    .font(VS.TextStyle.title2())
                    .foregroundStyle(VS.Color.textPrimary)
                if isEstimate {
                    Text("Tick Full tank on both fills for an exact number.")
                        .font(VS.TextStyle.caption())
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }
            Spacer()
            if let standard = store.manufacturerStandard, standard > 0 {
                let deviation = Int(EfficiencyFormat.deviationPercent(
                    currentL100: efficiency,
                    standardL100: standard
                ).rounded())
                Text(deviation <= 0 ? "\(abs(deviation))% better than spec" : "\(deviation)% thirstier than spec")
                    .font(VS.TextStyle.caption(.medium))
                    .foregroundStyle(deviation <= 0 ? VS.Color.accentSecondary : VS.Color.warning)
            }
        }
        .padding(VS.Spacing.md)
        .glassCard()
    }

    private var stationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VSIcon(icon: .mapPin, size: 14, weight: .fill, tint: VS.Color.accent)
                Text(currentLog.stationName ?? "")
                    .font(VS.TextStyle.headline(.semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if let coordinate = stationCoordinate {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            latitudinalMeters: 900,
                            longitudinalMeters: 900
                        )
                    ),
                    interactionModes: []
                ) {
                    Annotation(currentLog.stationName ?? "Station", coordinate: coordinate, anchor: .bottom) {
                        VSIcon(icon: .gasPump, size: 14, weight: .fill, tint: VS.Color.navPill)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(VS.Color.accent))
                            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2))
                            .shadow(color: VS.Color.accent.opacity(0.4), radius: 8)
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous))
                .allowsHitTesting(false)
                .preferredColorScheme(.dark)
            }
        }
        .padding(VS.Spacing.md)
        .glassCard()
    }

    private var actions: some View {
        VStack(spacing: 14) {
            PrimaryCTAButton(title: TrackyVoice.Calm.editThisFill, icon: .gasPump) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showEdit = true
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
                    Text("Delete fill")
                        .font(VS.TextStyle.callout(.semibold))
                }
                .foregroundStyle(VS.Color.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassCard(radius: VS.Radius.card)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
    }

    private func deleteLog() async {
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await store.deleteFuelLog(currentLog)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
