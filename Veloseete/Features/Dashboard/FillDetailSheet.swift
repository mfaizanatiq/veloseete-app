import SwiftUI
import MapKit

/// Detail view for a single fuel log — everything captured at the pump,
/// plus the efficiency of the tank interval it closes. Edit and delete live here.
struct FillDetailSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

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

    /// L/100km for the interval this fill closes — only meaningful full-tank to full-tank.
    private var intervalEfficiency: Double? {
        guard let previousLog, let distance = distanceSincePrevious else { return nil }
        guard currentLog.isFullTank, previousLog.isFullTank, currentLog.fuelVolume > 0 else { return nil }
        return (currentLog.fuelVolume / distance) * 100
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
                    }

                    if currentLog.stationName != nil {
                        stationSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(13))
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
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)

            Text(CurrencyFormat.format(currentLog.totalCost, currency: currentLog.currency))
                .font(VS.Typography.heading(34, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)

            HStack(spacing: 8) {
                tankPill
                Text(String(
                    format: "%@ %.3f / %@",
                    CurrencyFormat.symbols[currentLog.currency] ?? currentLog.currency,
                    currentLog.pricePerUnit,
                    VolumeFormat.suffix(volumeUnit)
                ))
                .font(VS.Typography.body(12, weight: .medium))
                .foregroundStyle(VS.Color.textSecondary)
            }
        }
        .padding(VS.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(elevated: true)
    }

    private var tankPill: some View {
        Text(currentLog.isFullTank ? "Full tank" : "Partial fill")
            .font(VS.Typography.body(11, weight: .semibold))
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
                    .font(VS.Typography.body(11, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
            }
            Text(value)
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricInset()
    }

    private func efficiencyCard(_ efficiency: Double) -> some View {
        HStack(spacing: 12) {
            VSIcon(icon: .chartLine, size: 20, weight: .bold, tint: VS.Color.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS TANK")
                    .font(VS.Typography.body(11, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
                Text(String(format: "%.1f L/100km", efficiency))
                    .font(VS.Typography.heading(20, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
            }
            Spacer()
            if let standard = store.manufacturerStandard, standard > 0 {
                let deviation = Int((((efficiency - standard) / standard) * 100).rounded())
                Text(deviation <= 0 ? "\(abs(deviation))% under spec" : "\(deviation)% over spec")
                    .font(VS.Typography.body(12, weight: .medium))
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
                    .font(VS.Typography.heading(15))
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
                        .font(VS.Typography.body(14, weight: .semibold))
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
