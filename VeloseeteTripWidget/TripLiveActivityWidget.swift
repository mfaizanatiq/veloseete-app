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
    static let lime = Color(red: 0.85, green: 0.99, blue: 0.33)
    static let amber = Color(red: 1.00, green: 0.72, blue: 0.24)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.38)
    static let background = Color(red: 0.04, green: 0.05, blue: 0.045)
    static let secondary = Color.white.opacity(0.55)
    static let track = Color.white.opacity(0.14)

    static func mood(_ mood: DriveMood) -> Color {
        switch mood {
        case .smooth, .saved: return lime
        case .watch: return amber
        case .heavy: return coral
        case .paused: return amber
        }
    }
}

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityContent(context: context)
                .activityBackgroundTint(TripActivityStyle.background)
                .activitySystemActionForegroundColor(TripActivityStyle.mood(context.state.mood))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.mood.title)
                            .font(.caption.weight(.bold))
                    } icon: {
                        Image(systemName: context.state.mood.symbolName)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TripActivityStyle.mood(context.state.mood))
                    .labelStyle(.titleAndIcon)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatDuration(context.state.durationSec))
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            MetricCell(
                                value: "\(context.state.driveScore)",
                                label: "SCORE",
                                tint: TripActivityStyle.mood(context.state.mood),
                                emphasis: true
                            )
                            MetricCell(
                                value: String(format: "%.1f", context.state.estL100),
                                label: "L/100",
                                tint: .white,
                                emphasis: true
                            )
                            MetricCell(
                                value: String(format: "%.1f", context.state.distanceKm),
                                label: "KM",
                                tint: .white,
                                emphasis: true
                            )
                        }

                        StableTrack(
                            thirst: context.state.thirst,
                            tint: TripActivityStyle.mood(context.state.mood)
                        )

                        Text(footerLine(for: context.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TripActivityStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.mood.symbolName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(TripActivityStyle.mood(context.state.mood))
            } compactTrailing: {
                Text("\(context.state.driveScore)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(TripActivityStyle.mood(context.state.mood))
                    .contentTransition(.numericText())
                    .frame(minWidth: 22, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.mood.symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TripActivityStyle.mood(context.state.mood))
            }
            .keylineTint(TripActivityStyle.mood(context.state.mood))
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
        let tint = TripActivityStyle.mood(context.state.mood)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: context.state.mood.symbolName)
                    .foregroundStyle(tint)
                Text(context.state.mood.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text("\(context.state.driveScore)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Text(String(format: "%.1f L/100", context.state.estL100))
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text(String(format: "%.1f km · %@", context.state.distanceKm, formatDuration(context.state.durationSec)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TripActivityStyle.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
    }
}

private struct TripLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        let mood = context.state.mood
        let tint = TripActivityStyle.mood(mood)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: mood.symbolName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(mood.lockHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(context.attributes.vehicleName)
                        .font(.caption)
                        .foregroundStyle(TripActivityStyle.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(mood.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
            }

            // Equal columns — same type size so digits don't reflow.
            HStack(spacing: 0) {
                MetricCell(
                    value: "\(context.state.driveScore)",
                    label: "SCORE",
                    tint: tint,
                    emphasis: true
                )
                MetricCell(
                    value: String(format: "%.1f", context.state.estL100),
                    label: "L/100",
                    tint: .white,
                    emphasis: true
                )
                MetricCell(
                    value: String(format: "%.1f", context.state.distanceKm),
                    label: "KM",
                    tint: .white,
                    emphasis: true
                )
            }

            StableTrack(thirst: context.state.thirst, tint: tint)

            // Always the same structure — no if/else swap that jumps layout.
            Text(footerLine(for: context.state))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TripActivityStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(mood.lockHeadline), score \(context.state.driveScore), "
                + String(format: "%.1f L/100, %.1f km", context.state.estL100, context.state.distanceKm)
        )
    }
}

// MARK: - Stable primitives (no GeometryReader / offsets)

private struct MetricCell: View {
    let value: String
    let label: String
    let tint: Color
    var emphasis: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: emphasis ? 26 : 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TripActivityStyle.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Simple ProgressView-based bar — avoids GeometryReader offset glitches.
private struct StableTrack: View {
    let thirst: Double
    let tint: Color

    /// Snap to steps so the bar doesn't jitter every GPS tick.
    private var snapped: Double {
        let clamped = min(max(thirst, 0), 1)
        return (clamped * 20).rounded() / 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: snapped)
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(height: 6)
                .scaleEffect(x: 1, y: 1.15, anchor: .center)

            HStack {
                Text("Thrifty")
                Spacer(minLength: 0)
                Text("Thirsty")
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(TripActivityStyle.secondary)
        }
    }
}

private func footerLine(for state: TripActivityAttributes.ContentState) -> String {
    let time = formatDuration(state.durationSec)
    let speed = String(format: "%.0f km/h", state.currentSpeedKmh)
    if state.lastEvent.isEmpty {
        return "\(time)  ·  \(speed)"
    }
    return "\(state.lastEvent)  ·  \(time)  ·  \(speed)"
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
