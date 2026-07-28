import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VeloseeteTripWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarPlayStatusWidget()
        FuelPulseWidget()
        LiveDriveWidget()
        ReviewQueueWidget()
        TripLiveActivityWidget()
    }
}

private enum TripActivityStyle {
    static let accent = Color(red: 0.84, green: 0.98, blue: 0.31)
    static let paused = Color(red: 1.00, green: 0.72, blue: 0.24)
    static let background = Color(red: 0.035, green: 0.045, blue: 0.038)
    static let secondary = Color.white.opacity(0.58)
}

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityContent(context: context)
                .activityBackgroundTint(TripActivityStyle.background)
                .activitySystemActionForegroundColor(TripActivityStyle.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        Image(systemName: context.state.isPaused ? "pause.fill" : "car.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
                        StatusLabel(state: context.state)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatDuration(context.state.durationSec))
                            .font(.headline.monospacedDigit().weight(.semibold))
                        Text("ELAPSED")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TripActivityStyle.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.attributes.vehicleName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)

                        HStack(alignment: .lastTextBaseline, spacing: 14) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(String(format: "%.1f", context.state.distanceKm))
                                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                Text("DISTANCE · KM")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(TripActivityStyle.secondary)
                            }

                            Spacer(minLength: 6)

                            SmallMetric(
                                value: String(format: "%.0f", context.state.currentSpeedKmh),
                                label: "KM/H",
                                icon: "speedometer"
                            )
                            SmallMetric(
                                value: String(format: "%.0f", context.state.maxSpeedKmh),
                                label: "MAX",
                                icon: "gauge.with.dots.needle.67percent"
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
                        .frame(width: 6, height: 6)
                    Image(systemName: context.state.isPaused ? "pause.fill" : "car.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
                }
            } compactTrailing: {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", context.state.distanceKm))
                        .font(.caption.monospacedDigit().weight(.bold))
                    Text("km")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "car.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
            }
            .keylineTint(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
        }
    }
}

private struct TripActivityContent: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        if #available(iOS 18.0, *) {
            AdaptiveTripActivityView(context: context)
        } else {
            TripLockScreenView(context: context)
        }
    }
}

@available(iOS 18.0, *)
private struct AdaptiveTripActivityView: View {
    @Environment(\.activityFamily) private var activityFamily
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        if activityFamily == .small {
            CarPlayTripActivityView(context: context)
        } else {
            TripLockScreenView(context: context)
        }
    }
}

@available(iOS 18.0, *)
private struct CarPlayTripActivityView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: context.state.isPaused ? "pause.fill" : "car.fill")
                    .foregroundStyle(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
                Text(context.attributes.vehicleName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(context.state.isPaused ? "PAUSED" : "LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(context.state.distanceKm, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Text("km")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TripActivityStyle.secondary)
                Spacer(minLength: 0)
            }

            HStack {
                Label(formatDuration(context.state.durationSec), systemImage: "clock.fill")
                Spacer()
                Text("\(Int(context.state.currentSpeedKmh.rounded())) km/h")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TripActivityStyle.secondary)
        }
        .padding(14)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(context.state.statusLabel), \(context.state.distanceKm, format: .number.precision(.fractionLength(1))) kilometers"
        )
    }
}

private struct TripLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                    Image(systemName: context.state.isPaused ? "pause.fill" : "location.north.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.isPaused ? "Trip paused" : "Trip in progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(context.attributes.vehicleName)
                        .font(.caption)
                        .foregroundStyle(TripActivityStyle.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(context.state.isPaused ? "PAUSED" : "LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", context.state.distanceKm))
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("km")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TripActivityStyle.secondary)
                Spacer()
            }

            HStack(spacing: 0) {
                metric(formatDuration(context.state.durationSec), "Elapsed")
                divider
                metric(String(format: "%.0f km/h", context.state.currentSpeedKmh), "Current speed")
                divider
                metric(String(format: "%.0f km/h", context.state.maxSpeedKmh), "Top speed")
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var statusColor: Color {
        context.state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 12)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(TripActivityStyle.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilitySummary: String {
        "\(context.state.statusLabel) trip in \(context.attributes.vehicleName), "
            + String(format: "%.1f kilometers, %@ elapsed, %.0f kilometers per hour", context.state.distanceKm, formatDuration(context.state.durationSec), context.state.currentSpeedKmh)
    }
}

private struct StatusLabel: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.isPaused ? "PAUSED" : "RECORDING")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        state.isPaused ? TripActivityStyle.paused : TripActivityStyle.accent
    }
}

private struct SmallMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(TripActivityStyle.accent)
                Text(value)
                    .font(.headline.monospacedDigit().weight(.semibold))
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(TripActivityStyle.secondary)
        }
    }
}

private func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}
