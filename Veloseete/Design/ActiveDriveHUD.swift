import SwiftUI
import UIKit

// MARK: - Model

struct ActiveDriveHUDModel: Equatable {
    var vehicleName: String
    var speedKmh: Double
    var distanceKm: Double
    var durationSec: Double
    var estL100: Double
    var avgSpeedKmh: Double
    var isPaused: Bool
    var driveScore: Int
    var statusLabel: String
    var lastEvent: String
    var thirst: Double
    /// Session cushion — full at drive start, drains when you throttle hard.
    var efficiencyReserve: Double
    var speedSamplesKmh: [Double]
    var intelligence: LiveDriveIntelligenceLogic.Snapshot
    var avatarImage: UIImage? = nil
    /// When false, parent already shows the vehicle (Trips header).
    var showsVehicleName: Bool = true
}

// MARK: - Panel

struct ActiveDriveHUDContent: View {
    let model: ActiveDriveHUDModel
    var pulseOpacity: Double = 1

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            DriveEfficiencyArcMeter(
                fillLevel: model.efficiencyReserve,
                vehicleName: model.showsVehicleName ? model.vehicleName : nil,
                speedKmh: model.speedKmh,
                isPaused: model.isPaused,
                pulseOpacity: pulseOpacity
            )

            // Trip facts — centered under the arc
            HStack(alignment: .center, spacing: 0) {
                hudStat(String(format: "%.1f", model.distanceKm), "km")
                hudDivider
                hudStat(formatDuration(model.durationSec), "time")
                hudDivider
                hudStat(String(format: "%.1f", model.estL100), "L/100")
            }

            // Range copy left · dynamic tank bar right
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.intelligence.rangeCardTitle)
                        .font(VS.Typography.heading(16, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(model.intelligence.filledAgo)
                        .font(VS.Typography.body(12, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DriveFuelTankBattery(
                    fillLevel: model.intelligence.tankFillLevel,
                    isPaused: model.isPaused,
                    isLearning: !model.intelligence.showsRangeEstimate
                        && model.intelligence.tankFillLevel == nil
                )
                .frame(width: 118, height: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hudStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(VS.Typography.heading(18, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label.uppercased())
                .font(VS.Typography.mono(9, weight: .bold))
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = max(0, Int(sec.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Arc efficiency meter (same drain concept, gauge form)

/// Full at drive start (leaf / right). Throttle drains the wavy arc toward the pump (left / red).
private struct DriveEfficiencyArcMeter: View {
    let fillLevel: Double
    var vehicleName: String?
    let speedKmh: Double
    var isPaused: Bool = false
    var pulseOpacity: Double = 1

    /// Match the smooth line-bar feel — longer waves, gentler amplitude.
    private let wavelength: CGFloat = 48
    private let amplitude: CGFloat = 4.0

    private var level: Double { min(max(fillLevel, 0), 1) }
    private var snapped: Double { (level * 20).rounded() / 20 }

    private var markerColor: Color {
        if snapped > 0.55 { return VS.Color.accent }
        if snapped > 0.28 { return VS.Color.warning }
        return VS.Color.routeEnd
    }

    /// Gap from arc feet down to icon centers.
    private let iconDrop: CGFloat = 20
    /// Keep the stroke off the card edges (pump / leaf need this room too).
    private let sideInset: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let innerWidth = max(120, geo.size.width - sideInset * 2)
            // Padded semicircle — cap so leftover panel height doesn't inflate it.
            let arcHeight = min(max(innerWidth * 0.46, 148), 188)
            let drawRect = CGRect(x: sideInset, y: 0, width: innerWidth, height: arcHeight)
            let arc = DriveWavyArc(amplitude: amplitude, wavelength: wavelength)
            let tip = arc.point(at: snapped, in: drawRect)
            let start = arc.point(at: 0, in: drawRect)
            let end = arc.point(at: 1, in: drawRect)
            let speedSize: CGFloat = 48

            ZStack(alignment: .top) {
                ZStack {
                    arc
                        .stroke(
                            Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                        )

                    arc
                        .trim(from: 0, to: max(0.02, snapped))
                        .stroke(
                            LinearGradient(
                                colors: [VS.Color.routeEnd, VS.Color.warning, VS.Color.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: markerColor.opacity(isPaused ? 0.12 : 0.35), radius: 6, y: 1)
                        .opacity(isPaused ? 0.45 : 1)
                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: snapped)

                    Circle()
                        .fill(markerColor)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                        .shadow(color: markerColor.opacity(0.5), radius: 6)
                        .position(tip)
                        .opacity(isPaused ? 0.5 : 1)
                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: snapped)
                }
                .frame(width: geo.size.width, height: arcHeight)

                VSIcon(
                    icon: .gasPump,
                    size: 18,
                    weight: .fill,
                    tint: snapped < 0.35 ? VS.Color.routeEnd : VS.Color.routeEnd.opacity(0.75)
                )
                .accessibilityHidden(true)
                .position(x: start.x, y: start.y + iconDrop)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VS.Color.accent.opacity(snapped > 0.4 ? 0.95 : 0.45))
                    .accessibilityHidden(true)
                    .position(x: end.x, y: end.y + iconDrop)

                VStack(spacing: 6) {
                    if let vehicleName, !vehicleName.isEmpty {
                        Text(vehicleName)
                            .font(VS.Typography.heading(13, weight: .bold))
                            .foregroundStyle(VS.Color.textSecondary)
                            .lineLimit(1)
                    }

                    // Hidden matching unit keeps the number optically centered.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("km/h")
                            .font(VS.Typography.heading(14, weight: .bold))
                            .hidden()
                        Text(String(format: "%.0f", speedKmh))
                            .font(VS.Typography.heading(speedSize, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: Int(speedKmh))
                        Text("km/h")
                            .font(VS.Typography.heading(14, weight: .bold))
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    livePill
                }
                .frame(maxWidth: .infinity)
                .offset(y: arcHeight * 0.30)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(max((UIScreen.main.bounds.width - 88) * 0.46, 148), 188) + iconDrop + 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Efficiency reserve \(Int(snapped * 100)) percent, \(Int(speedKmh)) kilometers per hour")
    }

    private var livePill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isPaused ? VS.Color.warning : VS.Color.accent)
                .frame(width: 5, height: 5)
                .opacity(isPaused ? 1 : pulseOpacity)
            Text(isPaused ? "PAUSED" : "LIVE")
                .font(VS.Typography.mono(9, weight: .bold))
                .foregroundStyle(isPaused ? VS.Color.warning : VS.Color.navPill)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (isPaused ? VS.Color.warning : VS.Color.accent).opacity(isPaused ? 0.18 : 1),
            in: Capsule()
        )
    }
}

/// Semicircle gauge with a soft sine along the stroke — same smoothness as the line bar.
private struct DriveWavyArc: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = samplePoints(in: rect)
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        // Fine polyline reads as a smooth curve when amplitude is gentle.
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    func point(at progress: Double, in rect: CGRect) -> CGPoint {
        let points = samplePoints(in: rect)
        guard points.count > 1 else { return CGPoint(x: rect.midX, y: rect.midY) }
        let t = min(max(progress, 0), 1) * Double(points.count - 1)
        let i = Int(t)
        let f = CGFloat(t - Double(i))
        if i >= points.count - 1 { return points[points.count - 1] }
        let a = points[i]
        let b = points[i + 1]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    private func samplePoints(in rect: CGRect) -> [CGPoint] {
        // Leave room at the sides so the stroke doesn’t clip under the end icons.
        let inset = rect.insetBy(dx: 10, dy: 10)
        let center = CGPoint(x: inset.midX, y: inset.maxY - 2)
        let radius = min(inset.width / 2, inset.height * 0.98)
        let start = CGFloat.pi
        let end: CGFloat = 0
        let steps = 180
        var points: [CGPoint] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = start + (end - start) * t
            let arcLen = t * radius * .pi
            let wave = sin((arcLen / max(wavelength, 1)) * 2 * .pi) * amplitude
            let x = center.x + cos(angle) * (radius + wave)
            let y = center.y - sin(angle) * (radius + wave)
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }
}

// MARK: - Dynamic fuel tank battery

/// Horizontal tank — liquid fills from the left.
/// Pump stays centered: white over empty, dark only where liquid actually overlaps it.
private struct DriveFuelTankBattery: View {
    let fillLevel: Double?
    var isPaused: Bool = false
    var isLearning: Bool = false

    private let inset: CGFloat = 3
    private let pumpSize: CGFloat = 18

    private var displayFill: Double {
        if let fillLevel { return min(1, max(0.06, fillLevel)) }
        return 0.28
    }

    private var statusTint: Color {
        if isLearning { return VS.Color.textTertiary }
        if displayFill < 0.18 { return VS.Color.routeEnd }
        if displayFill < 0.35 { return VS.Color.warning }
        return VS.Color.accent
    }

    private var liquidColors: [Color] {
        if isLearning {
            return [VS.Color.textTertiary.opacity(0.4), VS.Color.textTertiary.opacity(0.2)]
        }
        if displayFill < 0.18 {
            return [VS.Color.routeEnd, VS.Color.warning.opacity(0.8)]
        }
        if displayFill < 0.35 {
            return [VS.Color.warning.opacity(0.9), VS.Color.accentSecondary]
        }
        return [VS.Color.accentSecondary, VS.Color.accent]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VS.Color.bgPrimary.opacity(0.65))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            statusTint.opacity(isLearning ? 0.35 : (displayFill < 0.35 ? 0.55 : 0.28)),
                            style: isLearning
                                ? StrokeStyle(lineWidth: 1.25, dash: [3, 2])
                                : StrokeStyle(lineWidth: 1.25)
                        )
                }

            // Battery nub
            HStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(statusTint.opacity(0.55))
                    .frame(width: 5, height: 16)
                    .offset(x: 4)
            }

            GeometryReader { geo in
                let innerW = geo.size.width - inset * 2
                let innerH = geo.size.height - inset * 2
                let liquidW = max(10, innerW * displayFill)
                // Absolute X where liquid ends — mask must use tank coords, not icon size.
                let liquidEndX = inset + liquidW

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: liquidColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: liquidW, height: innerH)
                    .position(x: inset + liquidW / 2, y: geo.size.height / 2)
                    .opacity(isPaused ? 0.55 : 1)

                // Full-tank frames so the mask aligns to the liquid edge, not the 18pt icon.
                ZStack {
                    VSIcon(icon: .gasPump, size: pumpSize, weight: .fill, tint: .white.opacity(0.95))
                        .frame(width: geo.size.width, height: geo.size.height)

                    VSIcon(icon: .gasPump, size: pumpSize, weight: .fill, tint: VS.Color.navPill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: liquidEndX, height: geo.size.height)
                        }
                }
                .opacity(isPaused ? 0.5 : 1)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: displayFill)
        }
        .accessibilityLabel(tankLabel)
    }

    private var tankLabel: String {
        if isLearning { return "Learning your tank level" }
        if let fillLevel {
            return "Tank about \(Int((fillLevel * 100).rounded())) percent full"
        }
        return "Fuel tank"
    }
}

/// Live coaching copy that evolves with how long you’ve been on the road.
enum DriveHealthCoach {
    struct Tip: Equatable {
        var title: String
        var detail: String
        /// 0…1 how settled into this drive (by duration).
        var durationProgress: Double
    }

    static func tip(
        durationSec: Double,
        score: Int,
        thirst: Double,
        lastEvent: String,
        isPaused: Bool
    ) -> Tip {
        let progress = min(1, max(0, durationSec / (45 * 60)))

        if isPaused {
            return Tip(
                title: "Paused",
                detail: "Resume when you’re ready.",
                durationProgress: progress
            )
        }

        if !lastEvent.isEmpty,
           lastEvent.hasPrefix("Hard") || lastEvent.hasPrefix("Heavy") || lastEvent.hasPrefix("Harsh") {
            return Tip(
                title: "Ease up",
                detail: lastEvent,
                durationProgress: progress
            )
        }

        switch durationSec {
        case ..<90.0:
            return Tip(
                title: "Just rolling",
                detail: "Find an easy pace.",
                durationProgress: progress
            )
        case ..<(8 * 60.0):
            if thirst > 0.55 {
                return Tip(
                    title: "Thirsty start",
                    detail: "Lighten the foot.",
                    durationProgress: progress
                )
            }
            return Tip(
                title: score >= 75 ? "Nice start" : "Settling in",
                detail: score >= 75 ? "Keep it silky." : "Smooth beats speed.",
                durationProgress: progress
            )
        case ..<(25 * 60.0):
            if thirst > 0.6 {
                return Tip(
                    title: "You’re pushing",
                    detail: "Try a calmer lane.",
                    durationProgress: progress
                )
            }
            return Tip(
                title: score >= 72 ? "In the zone" : "Mid-drive",
                detail: score >= 72 ? "Rhythm locked in." : "Reset with gentle inputs.",
                durationProgress: progress
            )
        case ..<(50 * 60.0):
            return Tip(
                title: score >= 70 ? "Solid stretch" : "Driver needs rest",
                detail: score >= 70 ? "Stay loose in the shoulders." : "Ease throttle, check posture.",
                durationProgress: progress
            )
        default:
            return Tip(
                title: "Driver needs rest",
                detail: "Stretch soon, sip water.",
                durationProgress: progress
            )
        }
    }
}

#if DEBUG
extension ActiveDriveHUDModel {
    static let preview = ActiveDriveHUDModel(
        vehicleName: "Coolray",
        speedKmh: 57,
        distanceKm: 12.4,
        durationSec: 1458,
        estL100: 7.4,
        avgSpeedKmh: 58,
        isPaused: false,
        driveScore: 86,
        statusLabel: "Smooth",
        lastEvent: "",
        thirst: 0.22,
        efficiencyReserve: 0.82,
        speedSamplesKmh: [],
        intelligence: LiveDriveIntelligenceLogic.Snapshot(
            burnPosition: 0.28,
            tankFillLevel: 0.64,
            kmRemaining: 312,
            timeRemainingSec: 4.2 * 3600,
            confidence: 0.72,
            showsRangeEstimate: true,
            headline: "About 280–330 km left · ~4h driving",
            detail: "On your usual rhythm · filled Aug 18",
            rangeCardTitle: "280–330 km left",
            filledAgo: "Filled 6 days ago"
        ),
        avatarImage: nil,
        showsVehicleName: true
    )
}
#endif
