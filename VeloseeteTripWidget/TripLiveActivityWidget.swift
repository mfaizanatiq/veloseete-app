import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VeloseeteTripWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripLiveActivityWidget()
    }
}

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.04, green: 0.05, blue: 0.04))
                .activitySystemActionForegroundColor(Color(red: 0.85, green: 0.99, blue: 0.33))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.vehicleName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(context.state.statusLabel)
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.85, green: 0.99, blue: 0.33))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f km", context.state.distanceKm))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        Text(formatDuration(context.state.durationSec))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(String(format: "%.0f km/h", context.state.currentSpeedKmh), systemImage: "speedometer")
                        Spacer()
                        Label(String(format: "max %.0f", context.state.maxSpeedKmh), systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                }
            } compactLeading: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color(red: 0.85, green: 0.99, blue: 0.33))
            } compactTrailing: {
                Text(String(format: "%.1f", context.state.distanceKm))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color(red: 0.85, green: 0.99, blue: 0.33))
            }
        }
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%d:%02d", m, s)
    }
}

private struct TripLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Veloseete")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.85, green: 0.99, blue: 0.33))
                Spacer()
                Text(context.state.statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(context.attributes.vehicleName)
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                metric(String(format: "%.1f", context.state.distanceKm), "km")
                metric(formatDuration(context.state.durationSec), "time")
                metric(String(format: "%.0f", context.state.currentSpeedKmh), "km/h")
            }
        }
        .padding(16)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
