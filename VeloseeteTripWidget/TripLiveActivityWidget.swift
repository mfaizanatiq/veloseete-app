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

    static let spectrumGradient = LinearGradient(
        colors: [lime, amber, coral],
        startPoint: .leading,
        endPoint: .trailing
    )
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

                        EfficiencySpectrumBar(
                            thirst: context.state.thirst,
                            mood: context.state.mood
                        )

                        Text(footerLine(for: context.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(footerColor(for: context.state))
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

            EfficiencySpectrumBar(thirst: context.state.thirst, mood: mood)

            Text(footerLine(for: context.state))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(footerColor(for: context.state))
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

/// Thrifty → Thirsty bar as a fun sine wave — same lime/amber/coral spectrum.
private struct EfficiencySpectrumBar: View {
    let thirst: Double
    let mood: DriveMood

    private var snapped: Double {
        let clamped = min(max(thirst, 0), 1)
        return (clamped * 20).rounded() / 20
    }

    private var markerColor: Color {
        TripActivityStyle.mood(mood)
    }

    private let amplitude: CGFloat = 4.5
    private let wavelength: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                let size = geo.size
                let tip = tipPoint(progress: snapped, in: size)

                ZStack {
                    // Quiet remaining track
                    Capsule()
                        .fill(TripActivityStyle.track)
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                        .position(x: size.width / 2, y: size.height / 2)

                    // End stop at “Thirsty”
                    Circle()
                        .fill(TripActivityStyle.coral.opacity(0.9))
                        .frame(width: 7, height: 7)
                        .position(x: size.width - 3.5, y: size.height / 2)

                    // Wavy progress — spectrum along the wave
                    WavyLine(amplitude: amplitude, wavelength: wavelength)
                        .trim(from: 0, to: max(0.02, snapped))
                        .stroke(
                            TripActivityStyle.spectrumGradient,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: markerColor.opacity(0.3), radius: 3, y: 1)

                    // Tip follows the wave crest
                    Circle()
                        .fill(markerColor)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .position(tip)
                }
            }
            .frame(height: 18)

            HStack {
                Label("Thrifty", systemImage: "leaf.fill")
                    .foregroundStyle(TripActivityStyle.lime.opacity(0.85))
                Spacer(minLength: 0)
                Label("Thirsty", systemImage: "flame.fill")
                    .foregroundStyle(TripActivityStyle.coral.opacity(0.9))
            }
            .font(.system(size: 8, weight: .bold))
        }
    }

    private func tipPoint(progress: Double, in size: CGSize) -> CGPoint {
        let x = size.width * progress
        let midY = size.height / 2
        let y = midY + sin((x / wavelength) * 2 * .pi) * amplitude
        return CGPoint(x: min(max(x, 4.5), size.width - 4.5), y: y)
    }
}

/// Full-width sine used with `.trim` so progress grows along the wave.
private struct WavyLine: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width
        guard width > 1 else { return path }

        path.move(to: CGPoint(x: 0, y: midY))
        let step: CGFloat = 1.5
        var x: CGFloat = 0
        while x <= width {
            let y = midY + sin((x / wavelength) * 2 * .pi) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        let endY = midY + sin((width / wavelength) * 2 * .pi) * amplitude
        path.addLine(to: CGPoint(x: width, y: endY))
        return path
    }
}

private func footerColor(for state: TripActivityAttributes.ContentState) -> Color {
    let event = state.lastEvent
    if event.contains("throttle") || event.contains("accel") || event.contains("thirsty") {
        return TripActivityStyle.coral.opacity(0.95)
    }
    if event.contains("brake") {
        return TripActivityStyle.amber.opacity(0.95)
    }
    if event.isEmpty {
        return TripActivityStyle.secondary
    }
    return TripActivityStyle.mood(state.mood).opacity(0.9)
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
