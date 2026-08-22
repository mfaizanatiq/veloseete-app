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

/// Compact Tracky card — selected face centered; mood grid lives in a drawer.
struct TrackyPickerCard: View {
    @AppStorage("veloseete.tracky.mood") private var trackyMoodRaw: String = TrackyMood.chill.rawValue
    @State private var showMoodDrawer = false

    private var trackyMood: TrackyMood {
        TrackyMood(rawValue: trackyMoodRaw) ?? .chill
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMoodDrawer = true
        } label: {
            VStack(spacing: 14) {
                Text(TrackyVoice.Soft.trackysMoodTitle)
                    .font(VS.Typography.heading(15, weight: .bold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TrackyFace(mood: trackyMood, size: 96)
                    .overlay {
                        Circle()
                            .strokeBorder(VS.Color.accent.opacity(0.55), lineWidth: 2.5)
                            .frame(width: 108, height: 108)
                    }
                    .frame(width: 108, height: 108)
                    .shadow(color: VS.Color.accent.opacity(0.22), radius: 16)

                VStack(spacing: 6) {
                    Text(trackyMood.label)
                        .font(VS.Typography.heading(22, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                        .contentTransition(.opacity)

                    Text(TrackyVoice.Soft.trackyCardHint)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, VS.Spacing.card)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(elevated: true)
        .accessibilityLabel("\(TrackyVoice.Soft.trackysMoodTitle), \(trackyMood.label)")
        .accessibilityHint("Opens Tracky’s mood picker")
        .onChange(of: trackyMoodRaw) { _, newValue in
            TrackyAppIcon.apply(mood: TrackyMood(rawValue: newValue) ?? .chill)
        }
        .sheet(isPresented: $showMoodDrawer) {
            TrackyMoodDrawer(
                selectedRaw: $trackyMoodRaw,
                onDismiss: { showMoodDrawer = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .veloseeteSheet()
        }
    }
}

/// Cutout drawer — pick a mood; selection updates the centered face on the Driver card.
private struct TrackyMoodDrawer: View {
    @Binding var selectedRaw: String
    var onDismiss: () -> Void

    private var selected: TrackyMood {
        TrackyMood(rawValue: selectedRaw) ?? .chill
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            HStack(alignment: .center, spacing: 14) {
                TrackyFace(mood: selected, size: 56)
                    .overlay {
                        Circle()
                            .strokeBorder(VS.Color.accent, lineWidth: 2)
                            .frame(width: 64, height: 64)
                    }
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(TrackyVoice.Soft.trackysMoodTitle)
                        .font(VS.Typography.heading(20, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(TrackyVoice.Soft.trackyDrawerSubtitle)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VS.Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(VS.Color.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text("SELECTED")
                .font(VS.Typography.body(11, weight: .bold))
                .foregroundStyle(VS.Color.textTertiary)
                .padding(.top, 4)

            HStack(spacing: 12) {
                TrackyFace(mood: selected, size: 44)
                Text(selected.label)
                    .font(VS.Typography.heading(18, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer()
                Text("Active")
                    .font(VS.Typography.body(11, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(VS.Color.accent, in: Capsule())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                    .fill(VS.Color.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                    .strokeBorder(VS.Color.accent.opacity(0.55), lineWidth: 1.5)
            )

            Text("OTHERS")
                .font(VS.Typography.body(11, weight: .bold))
                .foregroundStyle(VS.Color.textTertiary)
                .padding(.top, 6)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(TrackyMood.selectable) { mood in
                    moodCell(mood)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(VS.Spacing.card)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VS.Color.bgPrimary)
    }

    private func moodCell(_ mood: TrackyMood) -> some View {
        let isSelected = selected == mood

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.22)) {
                selectedRaw = mood.rawValue
            }
            TrackyAppIcon.apply(mood: mood)
        } label: {
            VStack(spacing: 8) {
                TrackyFace(mood: mood, size: 44)
                    .opacity(isSelected ? 1 : 0.4)
                    .saturation(isSelected ? 1 : 0.4)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected ? VS.Color.accent : VS.Color.hairline,
                                lineWidth: isSelected ? 3 : 1
                            )
                            .frame(width: 54, height: 54)
                    }
                    .frame(width: 54, height: 54)

                Text(mood.label)
                    .font(VS.Typography.body(11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? VS.Color.accent : VS.Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous)
                    .fill(isSelected ? VS.Color.accent.opacity(0.14) : VS.Color.chip)
            )
            .overlay {
                RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected ? VS.Color.accent.opacity(0.85) : Color.clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tracky \(mood.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Tracky face — prefers Higgsfield assets; Canvas fallback for locked / missing.
struct TrackyFace: View {
    var mood: TrackyMood = .chill
    var size: CGFloat = 56
    /// When false, omit the outer disc (Canvas fallback only).
    var showsDisc: Bool = true

    private var assetName: String? {
        guard mood != .locked else { return nil }
        return "tracky-\(mood.rawValue)"
    }

    var body: some View {
        Group {
            if let assetName, UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                canvasFace
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Tracky, \(mood.label)")
    }

    private var canvasFace: some View {
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

            let eyeY = center.y - s * eyeYOffset
            let eyeR = s * eyeRadius
            let spacing = s * eyeSpacing
            let left = CGPoint(x: center.x - spacing, y: eyeY + eyeYJitter)
            let right = CGPoint(x: center.x + spacing, y: eyeY - eyeYJitter)

            context.fill(Path(ellipseIn: eyeRect(left, eyeR)), with: .color(eyeColor))
            context.fill(Path(ellipseIn: eyeRect(right, eyeR)), with: .color(eyeColor))

            if let mouth = mouthPath(center: center, s: s) {
                context.stroke(
                    mouth,
                    with: .color(mouthColor),
                    style: StrokeStyle(lineWidth: max(1.2, s * 0.045), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func eyeRect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

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
            var p = Path()
            p.move(to: CGPoint(x: center.x - s * 0.07, y: y))
            p.addLine(to: CGPoint(x: center.x + s * 0.07, y: y))
            return p
        case .fueled:
            return Path(ellipseIn: CGRect(
                x: center.x - s * 0.035,
                y: y - s * 0.02,
                width: s * 0.07,
                height: s * 0.055
            ))
        case .night:
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
