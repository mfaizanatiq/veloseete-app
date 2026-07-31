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
            snapshot: VeloseeteWidgetFormat.previewSnapshot()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CarPlayStatusEntry) -> Void) {
        let snapshot = context.isPreview
            ? VeloseeteWidgetFormat.previewSnapshot()
            : CarPlayWidgetStateStore.loadSnapshot()
        completion(CarPlayStatusEntry(date: Date(), snapshot: snapshot))
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
        .configurationDisplayName("Driving Footprint")
        .description("Your current car, driving footprint, efficiency, and monthly spend.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable()
    }
}

private struct CarPlayStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CarPlayStatusEntry

    private var snapshot: CarPlayWidgetSnapshot { entry.snapshot }
    private let accent = Color(red: 0.84, green: 0.98, blue: 0.31)

    var body: some View {
        Group {
            if snapshot.vehicleID == nil {
                emptyState
            } else if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
        .foregroundStyle(.white)
        .widgetAccentable()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text("Veloseete")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text("Waiting for sync")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("Open Veloseete once")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(snapshot.vehicleName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Text("DRIVING FOOTPRINT")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(snapshot.totalDistanceKm, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("km")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                hotPoint(
                    value: snapshot.efficiencyLPer100Km.map { String(format: "%.1f", $0) } ?? "—",
                    label: "L/100",
                    icon: "leaf.fill",
                    compact: true
                )
                hotPoint(
                    value: "\(currencySymbol(snapshot.currency))\(Int(snapshot.monthlySpend.rounded()))",
                    label: "Month",
                    icon: "fuelpump.fill",
                    compact: true
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(snapshot.vehicleName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DRIVING FOOTPRINT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(snapshot.totalDistanceKm, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text("km")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }

                Spacer(minLength: 4)

                RouteMapPreview(points: snapshot.recentRoute, accent: accent)
                    .frame(width: 72, height: 56)
            }

            HStack(spacing: 8) {
                hotPoint(
                    value: snapshot.efficiencyLPer100Km.map { String(format: "%.1f", $0) } ?? "—",
                    label: "L/100 km",
                    icon: "leaf.fill",
                    compact: false
                )
                hotPoint(
                    value: "\(currencySymbol(snapshot.currency))\(Int(snapshot.monthlySpend.rounded()))",
                    label: "This month",
                    icon: "fuelpump.fill",
                    compact: false
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    private func hotPoint(value: String, label: String, icon: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .foregroundStyle(accent)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 5 : 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
