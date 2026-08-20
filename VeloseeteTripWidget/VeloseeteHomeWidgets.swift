import SwiftUI
import WidgetKit

// MARK: - Shared chrome

enum VeloseeteWidgetStyle {
    static let accent = Color(red: 0.84, green: 0.98, blue: 0.31)
    static let background = Color(red: 0.035, green: 0.045, blue: 0.038)
    static let panel = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.58)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.24)
    static let live = Color(red: 0.35, green: 0.92, blue: 0.62)
}

enum VeloseeteWidgetFormat {
    static func currencySymbol(_ code: String) -> String {
        switch code {
        case "QAR": return "QR "
        case "AED": return "د.إ "
        case "SAR": return "﷼ "
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return "\(code) "
        }
    }

    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%d:%02d", h, m) }
        return String(format: "%d min", max(m, 1))
    }

    static func previewSnapshot(
        tracking: CarPlayWidgetTrackingState = .idle,
        pendingTrips: Int = 0
    ) -> CarPlayWidgetSnapshot {
        CarPlayWidgetSnapshot(
            vehicleID: "preview",
            vehicleName: "Q8 Cruiser",
            odometerKm: 42_180,
            estimatedOdometerKm: 42_214,
            trackingState: tracking,
            autoTrackingEnabled: true,
            tripStartedAt: tracking == .recording ? Date().addingTimeInterval(-1_840) : nil,
            distanceKm: tracking == .recording ? 18.4 : 0,
            durationSec: tracking == .recording ? 1_840 : 0,
            currentSpeedKmh: tracking == .recording ? 74 : 0,
            lastFuelVolume: 46.2,
            lastFuelTotalCost: 96,
            lastFuelCurrency: "QAR",
            lastFuelDate: Date().addingTimeInterval(-86_400 * 4),
            lastStationName: "WOQOD Al Waab",
            totalDistanceKm: 12_480,
            efficiencyLPer100Km: 7.6,
            monthlySpend: 420,
            currency: "QAR",
            fuelVolumeUnit: "L",
            recentRoute: [
                CarPlayWidgetRoutePoint(latitude: 25.285, longitude: 51.531),
                CarPlayWidgetRoutePoint(latitude: 25.294, longitude: 51.522),
                CarPlayWidgetRoutePoint(latitude: 25.303, longitude: 51.516),
            ],
            pendingRefuelAt: nil,
            pendingTripCount: pendingTrips,
            updatedAt: Date()
        )
    }
}

struct VeloseeteSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarPlayStatusEntry {
        CarPlayStatusEntry(date: Date(), snapshot: VeloseeteWidgetFormat.previewSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (CarPlayStatusEntry) -> Void) {
        let snapshot = context.isPreview
            ? VeloseeteWidgetFormat.previewSnapshot()
            : CarPlayWidgetStateStore.loadSnapshot()
        completion(CarPlayStatusEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarPlayStatusEntry>) -> Void) {
        let snapshot = CarPlayWidgetStateStore.loadSnapshot()
        let entry = CarPlayStatusEntry(date: Date(), snapshot: snapshot)
        let refresh: TimeInterval = snapshot.trackingState == .recording ? 60 : 15 * 60
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(refresh))))
    }
}

// MARK: - Fuel Pulse

struct FuelPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CarPlayWidgetStateStore.fuelWidgetKind,
            provider: VeloseeteSnapshotProvider()
        ) { entry in
            FuelPulseWidgetView(entry: entry)
                .containerBackground(for: .widget) { VeloseeteWidgetStyle.background }
        }
        .configurationDisplayName("Fuel Pulse")
        .description("Last fill, days since pump, efficiency, and this month's spend.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable()
    }
}

private struct FuelPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CarPlayStatusEntry

    private var s: CarPlayWidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if s.vehicleID == nil {
                emptyState
            } else if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
        .foregroundStyle(.white)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Fuel Pulse", systemImage: "fuelpump.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VeloseeteWidgetStyle.accent)
            Spacer(minLength: 0)
            Text("Waiting for sync")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("Open Veloseete once")
                .font(.caption)
                .foregroundStyle(VeloseeteWidgetStyle.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "fuelpump.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloseeteWidgetStyle.accent)
                Text("FUEL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            if let days = s.daysSinceLastFuel {
                Text("\(days)")
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(days >= 10 ? VeloseeteWidgetStyle.warning : .white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(days == 0 ? "filled today" : days == 1 ? "day since fill" : "days since fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else {
                Text("—")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("no fills yet")
                    .font(.caption)
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(s.efficiencyLPer100Km.map { String(format: "%.1f L/100", $0) } ?? "Eff —")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(VeloseeteWidgetStyle.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumBody: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(s.vehicleName, systemImage: "fuelpump.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloseeteWidgetStyle.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if let days = s.daysSinceLastFuel {
                    Text("\(days)d")
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(days == 0 ? "Filled today" : "Since last pump")
                        .font(.caption)
                        .foregroundStyle(VeloseeteWidgetStyle.secondary)
                        .lineLimit(1)
                } else {
                    Text("Fresh")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("Log a fill to start")
                        .font(.caption)
                        .foregroundStyle(VeloseeteWidgetStyle.secondary)
                        .lineLimit(1)
                }

                if let station = s.lastStationName, !station.isEmpty {
                    Text(station)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(VeloseeteWidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                metricTile(title: "Last fill", value: lastFillText)
                metricTile(
                    title: "Efficiency",
                    value: s.efficiencyLPer100Km.map { String(format: "%.1f L/100", $0) } ?? "—"
                )
                metricTile(
                    title: "This month",
                    value: "\(VeloseeteWidgetFormat.currencySymbol(s.currency))\(Int(s.monthlySpend.rounded()))"
                )
            }
            .frame(maxWidth: 148)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var lastFillText: String {
        guard let volume = s.lastFuelVolume else { return "—" }
        let unit = s.fuelVolumeUnit
        let display: Double
        let suffix: String
        if unit == "gal" {
            display = volume / 3.785411784
            suffix = "gal"
        } else {
            display = volume
            suffix = "L"
        }
        if let cost = s.lastFuelTotalCost {
            let code = s.lastFuelCurrency ?? s.currency
            return String(format: "%.1f %@ · %@%.0f", display, suffix, VeloseeteWidgetFormat.currencySymbol(code), cost)
        }
        return String(format: "%.1f %@", display, suffix)
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(VeloseeteWidgetStyle.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(VeloseeteWidgetStyle.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Live Drive

struct LiveDriveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CarPlayWidgetStateStore.driveWidgetKind,
            provider: VeloseeteSnapshotProvider()
        ) { entry in
            LiveDriveWidgetView(entry: entry)
                .containerBackground(for: .widget) { VeloseeteWidgetStyle.background }
        }
        .configurationDisplayName("Live Drive")
        .description("Live trip distance, speed, and duration while Veloseete is tracking.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable()
    }
}

private struct LiveDriveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CarPlayStatusEntry

    private var s: CarPlayWidgetSnapshot { entry.snapshot }
    private var isLive: Bool {
        s.trackingState == .recording || s.trackingState == .paused
    }

    var body: some View {
        Group {
            if s.vehicleID == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Live Drive", systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VeloseeteWidgetStyle.accent)
                    Spacer(minLength: 0)
                    Text("Select a car to arm tracking")
                        .font(.headline)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if isLive {
                liveBody
            } else {
                idleBody
            }
        }
        .foregroundStyle(.white)
    }

    private var liveBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(s.trackingState == .paused ? VeloseeteWidgetStyle.warning : VeloseeteWidgetStyle.live)
                    .frame(width: 7, height: 7)
                Text(s.trackingState == .paused ? "PAUSED" : "LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(s.trackingState == .paused ? VeloseeteWidgetStyle.warning : VeloseeteWidgetStyle.live)
                Spacer(minLength: 4)
                Text(s.vehicleName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(s.distanceKm, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: family == .systemMedium ? 40 : 34, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("km")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
            }

            if family == .systemMedium {
                HStack(spacing: 6) {
                    driveChip(String(format: "%.0f", s.currentSpeedKmh), "km/h")
                    driveChip(VeloseeteWidgetFormat.duration(s.durationSec), "time")
                    driveChip(String(format: "%.0f", s.estimatedOdometerKm ?? s.odometerKm), "odo")
                }
            } else {
                Text("\(Int(s.currentSpeedKmh.rounded())) km/h · \(VeloseeteWidgetFormat.duration(s.durationSec))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "car.side.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VeloseeteWidgetStyle.accent)
                Text(s.autoTrackingEnabled ? "ARMED" : "IDLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                Spacer(minLength: 0)
            }

            Text(s.vehicleName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(s.autoTrackingEnabled
                 ? "Auto-detect ON — watching"
                 : "Auto-detect OFF — enable in Drives")
                .font(.caption)
                .foregroundStyle(VeloseeteWidgetStyle.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f km odo", s.estimatedOdometerKm ?? s.odometerKm))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(VeloseeteWidgetStyle.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if s.pendingTripCount > 0 {
                    Text("\(s.pendingTripCount) to review")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(VeloseeteWidgetStyle.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func driveChip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(VeloseeteWidgetStyle.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(VeloseeteWidgetStyle.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Review Queue

struct ReviewQueueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CarPlayWidgetStateStore.reviewWidgetKind,
            provider: VeloseeteSnapshotProvider()
        ) { entry in
            ReviewQueueWidgetView(entry: entry)
                .containerBackground(for: .widget) { VeloseeteWidgetStyle.background }
        }
        .configurationDisplayName("Drive Review")
        .description("How many trips are waiting for your confirmation in My Drives.")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable()
    }
}

private struct ReviewQueueWidgetView: View {
    let entry: CarPlayStatusEntry
    private var s: CarPlayWidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(s.pendingTripCount > 0 ? VeloseeteWidgetStyle.warning : VeloseeteWidgetStyle.accent)
                Text("REVIEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(VeloseeteWidgetStyle.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Text("\(s.pendingTripCount)")
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(s.pendingTripCount > 0 ? VeloseeteWidgetStyle.warning : .white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(s.pendingTripCount == 0
                 ? "All caught up"
                 : s.pendingTripCount == 1 ? "drive waiting" : "drives waiting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VeloseeteWidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            Text(s.pendingTripCount > 0 ? "Open My Drives" : s.vehicleName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(VeloseeteWidgetStyle.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }
}
