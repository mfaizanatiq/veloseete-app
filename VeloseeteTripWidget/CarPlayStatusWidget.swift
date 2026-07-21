import SwiftUI
import WidgetKit

struct CarPlayStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: CarPlayWidgetSnapshot
}

struct CarPlayStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarPlayStatusEntry {
        CarPlayStatusEntry(
            date: Date(),
            snapshot: CarPlayWidgetSnapshot(
                vehicleID: "preview",
                vehicleName: "My Car",
                odometerKm: 42_180,
                trackingState: .idle,
                autoTrackingEnabled: true,
                tripStartedAt: nil,
                distanceKm: 0,
                durationSec: 0,
                currentSpeedKmh: 0,
                lastFuelVolume: 46.2,
                lastFuelTotalCost: 96,
                lastFuelCurrency: "QAR",
                lastFuelDate: Date().addingTimeInterval(-86_400),
                totalDistanceKm: 12_480,
                efficiencyLPer100Km: 7.6,
                monthlySpend: 420,
                currency: "QAR",
                recentRoute: [
                    CarPlayWidgetRoutePoint(latitude: 25.285, longitude: 51.531),
                    CarPlayWidgetRoutePoint(latitude: 25.294, longitude: 51.522),
                    CarPlayWidgetRoutePoint(latitude: 25.303, longitude: 51.516),
                    CarPlayWidgetRoutePoint(latitude: 25.314, longitude: 51.527),
                    CarPlayWidgetRoutePoint(latitude: 25.326, longitude: 51.521),
                ],
                pendingRefuelAt: nil,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CarPlayStatusEntry) -> Void) {
        completion(CarPlayStatusEntry(date: Date(), snapshot: CarPlayWidgetStateStore.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarPlayStatusEntry>) -> Void) {
        let entry = CarPlayStatusEntry(date: Date(), snapshot: CarPlayWidgetStateStore.loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct CarPlayStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CarPlayWidgetStateStore.widgetKind,
            provider: CarPlayStatusProvider()
        ) { entry in
            CarPlayStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.035, green: 0.045, blue: 0.038)
                }
        }
        .configurationDisplayName("Veloseete Footprint")
        .description("Your current car, driving footprint, efficiency, and monthly spend.")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable()
    }
}

private struct CarPlayStatusWidgetView: View {
    let entry: CarPlayStatusEntry

    private var snapshot: CarPlayWidgetSnapshot { entry.snapshot }
    private let accent = Color(red: 0.84, green: 0.98, blue: 0.31)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "car.side.fill")
                    .foregroundStyle(accent)
                Text(snapshot.vehicleName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if snapshot.vehicleID == nil {
                Spacer()
                Text("Select a car in Veloseete")
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
            } else {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DRIVING FOOTPRINT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(snapshot.totalDistanceKm, format: .number.precision(.fractionLength(0)))
                                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                            Text("km")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    Spacer(minLength: 0)

                    RouteMapPreview(points: snapshot.recentRoute, accent: accent)
                        .frame(width: 62, height: 58)
                }

                HStack(spacing: 8) {
                    hotPoint(
                        value: snapshot.efficiencyLPer100Km.map { String(format: "%.1f", $0) } ?? "—",
                        label: "L/100 km",
                        icon: "leaf.fill"
                    )
                    hotPoint(
                        value: "\(currencySymbol(snapshot.currency))\(Int(snapshot.monthlySpend.rounded()))",
                        label: "This month",
                        icon: "fuelpump.fill"
                    )
                }
            }
        }
        .padding(14)
        .foregroundStyle(.white)
        .widgetAccentable()
    }

    private struct RouteMapPreview: View {
        let points: [CarPlayWidgetRoutePoint]
        let accent: Color

        var body: some View {
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: bounds, cornerRadius: 10), with: .color(.white.opacity(0.07)))

                var roads = Path()
                roads.move(to: CGPoint(x: 0, y: size.height * 0.30))
                roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.12))
                roads.move(to: CGPoint(x: size.width * 0.16, y: size.height))
                roads.addLine(to: CGPoint(x: size.width * 0.72, y: 0))
                roads.move(to: CGPoint(x: 0, y: size.height * 0.76))
                roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.58))
                context.stroke(roads, with: .color(.white.opacity(0.10)), lineWidth: 1)

                guard points.count >= 2 else {
                    let pin = Path(ellipseIn: CGRect(x: size.width / 2 - 3, y: size.height / 2 - 3, width: 6, height: 6))
                    context.fill(pin, with: .color(accent))
                    return
                }

                let latitudes = points.map(\.latitude)
                let longitudes = points.map(\.longitude)
                let minLat = latitudes.min() ?? 0
                let maxLat = latitudes.max() ?? 0
                let minLon = longitudes.min() ?? 0
                let maxLon = longitudes.max() ?? 0
                let latSpan = max(maxLat - minLat, 0.000_001)
                let lonSpan = max(maxLon - minLon, 0.000_001)
                let inset: CGFloat = 8

                func position(_ point: CarPlayWidgetRoutePoint) -> CGPoint {
                    let x = inset + CGFloat((point.longitude - minLon) / lonSpan) * (size.width - inset * 2)
                    let y = inset + CGFloat((maxLat - point.latitude) / latSpan) * (size.height - inset * 2)
                    return CGPoint(x: x, y: y)
                }

                var route = Path()
                route.move(to: position(points[0]))
                for point in points.dropFirst() {
                    route.addLine(to: position(point))
                }
                context.stroke(route, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                context.stroke(route, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                let start = position(points[0])
                let end = position(points[points.count - 1])
                context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(accent))
                context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(.orange))
            }
            .accessibilityLabel(points.count >= 2 ? "Most recent route map" : "No recent route")
        }
    }

    private func hotPoint(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private func currencySymbol(_ code: String) -> String {
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
}
