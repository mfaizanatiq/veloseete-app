import SwiftUI

/// Tracky — Veloseete’s co-pilot mark.
/// Same round body + two-dot eyes; emotion is only mouth, eye pose, and tint
/// (mood-check-in scale energy, not cartoon faces).
enum TrackyMood: String, CaseIterable, Identifiable {
    case locked
    case proud
    case chill
    case fueled
    case focused
    case night
    case dawn
    case grit
    case legend
    case cozy

    var id: String { rawValue }

    /// Expressions the driver can pick for Tracky (avatar / mascot — not badges).
    static var selectable: [TrackyMood] {
        allCases.filter { $0 != .locked }
    }

    var label: String {
        switch self {
        case .locked: return "Locked"
        case .proud: return "Proud"
        case .chill: return "Chill"
        case .fueled: return "Fueled"
        case .focused: return "Focused"
        case .night: return "Night"
        case .dawn: return "Dawn"
        case .grit: return "Grit"
        case .legend: return "Legend"
        case .cozy: return "Cozy"
        }
    }
}

/// Driver-tab Tracky picker — outside Collection / achievements.
struct TrackyPickerCard: View {
    @AppStorage("veloseete.tracky.mood") private var trackyMoodRaw: String = TrackyMood.chill.rawValue

    private var trackyMood: TrackyMood {
        TrackyMood(rawValue: trackyMoodRaw) ?? .chill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tracky")
                        .font(VS.Typography.heading(17))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("Your co-pilot face")
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                Spacer()
                Text(trackyMood.label)
                    .font(VS.Typography.body(12, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
            }

            HStack(spacing: 16) {
                TrackyFace(mood: trackyMood, size: 72)
                    .accessibilityLabel("Tracky, \(trackyMood.label)")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(TrackyMood.selectable) { mood in
                            Button {
                                trackyMoodRaw = mood.rawValue
                            } label: {
                                VStack(spacing: 6) {
                                    TrackyFace(mood: mood, size: 44)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(
                                                    trackyMood == mood ? VS.Color.accent : .clear,
                                                    lineWidth: 2
                                                )
                                                .padding(-3)
                                        }
                                    Text(mood.label)
                                        .font(VS.Typography.body(10, weight: trackyMood == mood ? .semibold : .medium))
                                        .foregroundStyle(
                                            trackyMood == mood ? VS.Color.textPrimary : VS.Color.textTertiary
                                        )
                                        .lineLimit(1)
                                }
                                .frame(width: 56)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Tracky \(mood.label)")
                            .accessibilityAddTraits(trackyMood == mood ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(VS.Spacing.card)
        .glassCard()
    }
}

/// Pure SwiftUI Tracky — brand mascot / avatar expression. Not used on badges.
struct TrackyFace: View {
    var mood: TrackyMood = .chill
    var size: CGFloat = 56
    /// When false, omit the outer disc (e.g. already clipped into a hex).
    var showsDisc: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            if showsDisc {
                let disc = Path(ellipseIn: CGRect(
                    x: center.x - s * 0.48,
                    y: center.y - s * 0.48,
                    width: s * 0.96,
                    height: s * 0.96
                ))
                context.fill(disc, with: .color(discFill))
                context.stroke(disc, with: .color(discStroke), lineWidth: max(1, s * 0.025))
            }

            // Two-dot eyes — the whole identity.
            let eyeY = center.y - s * eyeYOffset
            let eyeR = s * eyeRadius
            let spacing = s * eyeSpacing
            let left = CGPoint(x: center.x - spacing, y: eyeY + eyeYJitter)
            let right = CGPoint(x: center.x + spacing, y: eyeY - eyeYJitter)

            context.fill(Path(ellipseIn: eyeRect(left, eyeR)), with: .color(eyeColor))
            context.fill(Path(ellipseIn: eyeRect(right, eyeR)), with: .color(eyeColor))

            // Mouth: one stroke. Never a full emoji face.
            if let mouth = mouthPath(center: center, s: s) {
                context.stroke(
                    mouth,
                    with: .color(mouthColor),
                    style: StrokeStyle(lineWidth: max(1.2, s * 0.045), lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Tracky, \(mood.label)")
    }

    private func eyeRect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    // MARK: Mood geometry

    private var eyeSpacing: CGFloat {
        switch mood {
        case .focused: return 0.11
        case .grit: return 0.13
        case .legend: return 0.125
        default: return 0.12
        }
    }

    private var eyeRadius: CGFloat {
        switch mood {
        case .night: return 0.045
        case .locked: return 0.05
        case .legend, .proud: return 0.058
        default: return 0.055
        }
    }

    private var eyeYOffset: CGFloat {
        switch mood {
        case .dawn: return 0.06
        case .night: return 0.02
        default: return 0.04
        }
    }

    /// Tiny asymmetry for grit / night — still two dots.
    private var eyeYJitter: CGFloat {
        switch mood {
        case .grit: return size * 0.008
        case .night: return size * 0.004
        default: return 0
        }
    }

    private var discFill: Color {
        switch mood {
        case .locked: return Color.white.opacity(0.04)
        case .proud: return VS.Color.accent.opacity(0.16)
        case .chill: return VS.Color.accentSecondary.opacity(0.14)
        case .fueled: return VS.Color.accent.opacity(0.12)
        case .focused: return Color.white.opacity(0.06)
        case .night: return Color(hex: 0x12160E)
        case .dawn: return VS.Color.accent.opacity(0.10)
        case .grit: return Color.white.opacity(0.05)
        case .legend: return VS.Color.accent.opacity(0.22)
        case .cozy: return VS.Color.accentSecondary.opacity(0.10)
        }
    }

    private var discStroke: Color {
        switch mood {
        case .locked: return VS.Color.hairline
        case .legend, .proud, .fueled: return VS.Color.accent.opacity(0.85)
        case .chill, .cozy: return VS.Color.accentSecondary.opacity(0.7)
        case .night: return Color.white.opacity(0.14)
        default: return VS.Color.hairlineStrong
        }
    }

    private var eyeColor: Color {
        mood == .locked ? VS.Color.textTertiary.opacity(0.55) : Color(hex: 0x050505)
    }

    private var mouthColor: Color {
        mood == .locked ? VS.Color.textTertiary.opacity(0.45) : Color(hex: 0x050505).opacity(0.85)
    }

    private func mouthPath(center: CGPoint, s: CGFloat) -> Path? {
        let y = center.y + s * 0.14
        switch mood {
        case .locked:
            return nil
        case .focused:
            // Flat — concentrating.
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.07, y: y))
            p.addLine(to: CGPoint(x: center.x + s * 0.07, y: y))
            return p
        case .fueled:
            // Tiny open “o” — tank open / sip.
            return Path(ellipseIn: CGRect(
                x: center.x - s * 0.035,
                y: y - s * 0.02,
                width: s * 0.07,
                height: s * 0.055
            ))
        case .night:
            // Soft small smile, sleepy.
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.06, y: y))
            p.addQuadCurve(
                to: CGPoint(x: center.x + s * 0.06, y: y),
                control: CGPoint(x: center.x, y: y + s * 0.04)
            )
            return p
        case .dawn:
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.08, y: y - s * 0.01))
            p.addQuadCurve(
                to: CGPoint(x: center.x + s * 0.08, y: y - s * 0.01),
                control: CGPoint(x: center.x, y: y + s * 0.07)
            )
            return p
        case .grit:
            // Slight grit — short firm line, tilted.
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.06, y: y + s * 0.01))
            p.addLine(to: CGPoint(x: center.x + s * 0.06, y: y - s * 0.01))
            return p
        case .legend:
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.1, y: y - s * 0.02))
            p.addQuadCurve(
                to: CGPoint(x: center.x + s * 0.1, y: y - s * 0.02),
                control: CGPoint(x: center.x, y: y + s * 0.1)
            )
            return p
        case .proud, .chill, .cozy:
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.08, y: y))
            p.addQuadCurve(
                to: CGPoint(x: center.x + s * 0.08, y: y),
                control: CGPoint(x: center.x, y: y + s * 0.06)
            )
            return p
        }
    }
}
