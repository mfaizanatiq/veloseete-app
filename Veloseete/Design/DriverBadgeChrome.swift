import SwiftUI
import UIKit

// MARK: - Achievement visual language

extension DriverAchievement {
    /// Phosphor mark for this badge — never emoji.
    var markIcon: VSIconName {
        switch id {
        case "first-drive", "ten-trips", "twenty-five-trips", "multi-car":
            return .car
        case "hundred-club", "five-hundred-roads", "thousand-roads", "five-thousand-roads",
             "weekend-warrior", "fill-stretch":
            return .roadHorizon
        case "long-haul", "marathon-drive":
            return .navigationArrow
        case "seat-time", "pace-noted", "full-tank-discipline", "best-tank", "lean-machine":
            return .gauge
        case "early-bird", "night-owl":
            return .eye
        case "meal-runs":
            return .mapPin
        case "first-fill", "five-fills", "ten-fills", "twenty-five-fills", "fifty-fills",
             "currency-hopper", "gulf-hopper":
            return .gasPump
        case "spec-beater", "efficient-king":
            return .target
        case "service-kept", "service-pro", "consistent", "half-year":
            return .wrench
        default:
            switch category {
            case .road: return .roadHorizon
            case .fuel: return .gasPump
            case .efficiency: return .gauge
            case .habit: return .checkCircle
            }
        }
    }

    /// Short hex caption for milestone medals (NRC-style type inside the mark).
    var hexCaption: String? {
        switch id {
        case "hundred-club": return "100"
        case "five-hundred-roads": return "500"
        case "thousand-roads": return "1K"
        case "five-thousand-roads": return "5K"
        case "ten-trips": return "10"
        case "twenty-five-trips": return "25"
        case "five-fills": return "5"
        case "ten-fills": return "10"
        case "twenty-five-fills": return "25"
        case "fifty-fills": return "50"
        case "long-haul": return "80"
        case "marathon-drive": return "200"
        default: return nil
        }
    }
}

// MARK: - Shapes

struct HexagonShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = r.width
        let h = r.height
        let insetX = w * 0.08
        var path = Path()
        path.move(to: CGPoint(x: r.minX + w * 0.5, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - insetX, y: r.minY + h * 0.25))
        path.addLine(to: CGPoint(x: r.maxX - insetX, y: r.minY + h * 0.75))
        path.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + insetX, y: r.minY + h * 0.75))
        path.addLine(to: CGPoint(x: r.minX + insetX, y: r.minY + h * 0.25))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> HexagonShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Soft track-lane arcs inside a hex — the Veloseete signature texture.
private struct HexTrackLanes: View {
    var color: Color
    var lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            for i in 0..<4 {
                var path = Path()
                let y = size.height * (0.55 + CGFloat(i) * 0.08)
                path.move(to: CGPoint(x: size.width * 0.18, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.82, y: y - size.height * 0.06),
                    control: CGPoint(x: size.width * 0.5, y: y - size.height * 0.18)
                )
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
            }
        }
    }
}

// MARK: - Marks

/// Direction C — shelf disc. Same mark content as Collection hex (caption or icon).
struct BadgeDiscMark: View {
    let badge: DriverAchievement
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(badge.unlocked ? VS.Color.accent.opacity(0.12) : Color.white.opacity(0.03))
            Circle()
                .strokeBorder(
                    badge.unlocked ? VS.Color.accent.opacity(0.85) : VS.Color.hairline,
                    lineWidth: badge.unlocked ? 1.5 : 1
                )

            if let caption = badge.hexCaption {
                Text(caption)
                    .font(VS.Typography.heading(size * 0.34, weight: .bold))
                    .foregroundStyle(badge.unlocked ? VS.Color.accent : VS.Color.textTertiary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } else {
                VSIcon(
                    icon: badge.markIcon,
                    size: size * 0.36,
                    weight: badge.unlocked ? .bold : .regular,
                    tint: badge.unlocked ? VS.Color.accent : VS.Color.textTertiary
                )
            }
        }
        .frame(width: size, height: size)
        .opacity(badge.unlocked ? 1 : 0.55)
        .accessibilityHidden(true)
    }
}

/// Direction A — hex track medal for the full board (icons / captions — not Tracky).
struct BadgeHexMark: View {
    let badge: DriverAchievement
    var size: CGFloat = 92

    var body: some View {
        ZStack {
            HexagonShape()
                .fill(badge.unlocked ? VS.Color.bgSecondary : Color.white.opacity(0.03))
            HexagonShape()
                .strokeBorder(
                    badge.unlocked ? VS.Color.accent.opacity(0.9) : VS.Color.hairline,
                    lineWidth: badge.unlocked ? 1.75 : 1
                )
            HexTrackLanes(
                color: badge.unlocked ? VS.Color.accent.opacity(0.55) : Color.white.opacity(0.08)
            )
                .clipShape(HexagonShape())
                .opacity(badge.unlocked ? 1 : 0.45)

            if let caption = badge.hexCaption {
                Text(caption)
                    .font(VS.Typography.heading(size * 0.28, weight: .bold))
                    .foregroundStyle(badge.unlocked ? VS.Color.accent : VS.Color.textTertiary)
                    .minimumScaleFactor(0.7)
            } else {
                VSIcon(
                    icon: badge.markIcon,
                    size: size * 0.32,
                    weight: .bold,
                    tint: badge.unlocked ? VS.Color.accent : VS.Color.textTertiary
                )
            }
        }
        .frame(width: size, height: size)
        .opacity(badge.unlocked ? 1 : 0.55)
        .accessibilityHidden(true)
    }
}

// MARK: - Driver tab section (C)

struct DriverBadgesShelfSection: View {
    let achievements: [DriverAchievement]
    let onOpenBoard: () -> Void
    var onSelectBadge: (DriverAchievement) -> Void

    private var unlocked: [DriverAchievement] {
        achievements
            .filter(\.unlocked)
            .sorted { $0.title < $1.title }
    }

    private var nextQuests: [DriverAchievement] {
        achievements
            .filter { !$0.unlocked }
            .sorted { lhs, rhs in
                if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
                return lhs.title < rhs.title
            }
    }

    private var previewNext: [DriverAchievement] {
        Array(nextQuests.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges")
                    .font(VS.Typography.heading(20, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Spacer()
                Text("\(unlocked.count)/\(achievements.count)")
                    .font(VS.Typography.mono(13, weight: .semibold))
                    .foregroundStyle(VS.Color.textSecondary)
            }

            if unlocked.isEmpty {
                emptyShelf
            } else {
                shelfStrip
            }

            if !previewNext.isEmpty {
                VStack(alignment: .leading, spacing: VS.Spacing.stack) {
                    Text("Up next")
                        .font(VS.Typography.body(12, weight: .medium))
                        .foregroundStyle(VS.Color.textTertiary)

                    VStack(spacing: 0) {
                        ForEach(Array(previewNext.enumerated()), id: \.element.id) { index, badge in
                            nextQuestRow(badge)
                            if index < previewNext.count - 1 {
                                Divider().overlay(VS.Color.divider)
                            }
                        }

                        boardLink
                    }
                    .glassCard(elevated: true)
                }
            } else {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Board cleared")
                            .font(VS.Typography.body(15, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Every badge is unlocked — open the collection anytime.")
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VS.Spacing.card)

                    boardLink
                }
                .glassCard(elevated: true)
            }
        }
    }

    private var emptyShelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TrackyVoice.Soft.emptyBadgesTitle)
                .font(VS.Typography.body(15, weight: .semibold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(TrackyVoice.Soft.emptyBadgesBody)
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private var shelfStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(unlocked.prefix(10)) { badge in
                    Button {
                        onSelectBadge(badge)
                    } label: {
                        VStack(spacing: 8) {
                            BadgeDiscMark(badge: badge, size: 58)
                            Text(badge.title)
                                .font(VS.Typography.body(11, weight: .medium))
                                .foregroundStyle(VS.Color.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 72)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(badge.title), unlocked")
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func nextQuestRow(_ badge: DriverAchievement) -> some View {
        Button {
            onSelectBadge(badge)
        } label: {
            HStack(spacing: 12) {
                BadgeDiscMark(badge: badge, size: 40)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(badge.title)
                            .font(VS.Typography.body(14, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Spacer(minLength: 8)
                        Text(badge.progressLabel)
                            .font(VS.Typography.mono(11, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                            .lineLimit(1)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(VS.Color.chip)
                            Rectangle()
                                .fill(VS.Color.accent.opacity(0.8))
                                .frame(width: max(2, geo.size.width * badge.progress))
                        }
                    }
                    .frame(height: 2)
                }
            }
            .padding(.horizontal, VS.Spacing.md)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(badge.title), \(badge.progressLabel)")
    }

    private var boardLink: some View {
        Button(action: onOpenBoard) {
            HStack {
                Text("Open collection")
                    .font(VS.Typography.body(14, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(.horizontal, VS.Spacing.md)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Divider().overlay(VS.Color.divider)
        }
    }
}

// MARK: - Detail drawer + share

/// Hex medal inverted for lime share cards — black lines on accent.
struct BadgeShareMark: View {
    let badge: DriverAchievement
    var size: CGFloat = 180

    var body: some View {
        ZStack {
            HexagonShape()
                .strokeBorder(VS.Color.navPill, lineWidth: max(3, size * 0.028))
            HexTrackLanes(color: VS.Color.navPill.opacity(0.55), lineWidth: max(1.5, size * 0.012))
                .clipShape(HexagonShape())

            if let caption = badge.hexCaption {
                Text(caption)
                    .font(VS.Typography.heading(size * 0.28, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .minimumScaleFactor(0.7)
            } else {
                VSIcon(
                    icon: badge.markIcon,
                    size: size * 0.32,
                    weight: .bold,
                    tint: VS.Color.navPill
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BadgeShareCard: View {
    let badge: DriverAchievement
    var cardSize = CGSize(width: 360, height: 480)

    var body: some View {
        VStack(spacing: 0) {
            Text("VELOSEETE")
                .font(VS.Typography.body(11, weight: .bold))
                .tracking(4)
                .foregroundStyle(VS.Color.navPill.opacity(0.55))

            Spacer(minLength: 0)

            BadgeShareMark(badge: badge, size: 188)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text(badge.title)
                    .font(VS.Typography.heading(32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Text(badge.detail)
                    .font(VS.Typography.heading(18, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(3)
                if let achievedOnLabel = badge.achievedOnLabel {
                    Text(achievedOnLabel)
                        .font(VS.Typography.heading(14, weight: .bold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(VS.Color.navPill)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
        .frame(width: cardSize.width, height: cardSize.height)
        .background(VS.Color.accent)
    }

    @MainActor
    static func render(_ badge: DriverAchievement) -> UIImage? {
        let card = BadgeShareCard(badge: badge)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: 480)
        return renderer.uiImage
    }
}

struct BadgeDetailDrawer: View {
    let badge: DriverAchievement

    var body: some View {
        VStack(spacing: VS.Spacing.module) {
            BadgeHexMark(badge: badge, size: 168)

            VStack(spacing: 10) {
                Text(badge.title)
                    .font(VS.Typography.heading(28, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text(badge.detail)
                    .font(VS.Typography.body(16, weight: .medium))
                    .foregroundStyle(VS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if badge.unlocked, let achievedOnLabel = badge.achievedOnLabel {
                    Text("Unlocked \(achievedOnLabel)")
                        .font(VS.Typography.heading(15, weight: .bold))
                        .foregroundStyle(VS.Color.accent)
                } else if !badge.unlocked {
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(VS.Color.chip)
                                Rectangle()
                                    .fill(VS.Color.accent.opacity(0.85))
                                    .frame(width: max(2, geo.size.width * badge.progress))
                            }
                        }
                        .frame(height: 3)
                        Text(badge.progressLabel)
                            .font(VS.Typography.mono(13, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            if badge.unlocked {
                PrimaryCTAButton(title: "Share badge", icon: nil) {
                    var items: [Any] = [badge.shareCaption]
                    if let image = BadgeShareCard.render(badge) {
                        items.insert(image, at: 0)
                    }
                    SharePresenter.present(items)
                }
            }
        }
        .padding(.horizontal, VS.Spacing.sheetInset)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .veloseetePage()
    }
}

enum SharePresenter {
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene.windows.first?.rootViewController
        guard var top = root else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(
                x: top.view.bounds.midX,
                y: top.view.bounds.maxY - 24,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
