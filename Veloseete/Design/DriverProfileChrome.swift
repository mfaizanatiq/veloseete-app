import SwiftUI

/// Shared wavy spectrum bar (Driver style, Garage fuel thirst, Live Activity colors).
struct DriverThirstSpectrumBar: View {
    let thirst: Double

    private var snapped: Double {
        let clamped = min(max(thirst, 0), 1)
        return (clamped * 20).rounded() / 20
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let tip = tipPoint(progress: snapped, in: size)

            ZStack {
                Capsule()
                    .fill(VS.Color.chip)
                    .frame(height: 5)
                    .position(x: size.width / 2, y: size.height / 2)

                Circle()
                    .fill(VS.Color.routeEnd.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .position(x: size.width - 3, y: size.height / 2)

                DriverThirstWavyLine(amplitude: 4, wavelength: 20)
                    .trim(from: 0, to: max(0.02, snapped))
                    .stroke(
                        DriverThirstSpectrumBar.spectrumGradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )

                Circle()
                    .fill(markerColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .position(tip)
            }
        }
        .frame(height: 16)
    }

    private var markerColor: Color {
        if snapped < 0.35 { return VS.Color.accent }
        if snapped < 0.65 { return VS.Color.warning }
        return VS.Color.routeEnd
    }

    private func tipPoint(progress: Double, in size: CGSize) -> CGPoint {
        let x = size.width * progress
        let midY = size.height / 2
        let y = midY + sin((x / 20) * 2 * .pi) * 4
        return CGPoint(x: min(max(x, 4), size.width - 4), y: y)
    }

    static let spectrumGradient = LinearGradient(
        colors: [VS.Color.accent, VS.Color.warning, VS.Color.routeEnd],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// Calm → spirited driving style (person), not car fuel thirst.
typealias DriverStyleSpectrumBar = DriverThirstSpectrumBar

private struct DriverThirstWavyLine: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width
        guard width > 1 else { return path }

        path.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        while x <= width {
            let y = midY + sin((x / wavelength) * 2 * .pi) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 1.5
        }
        return path
    }
}

/// Compact stat chip for Driver profile — icon, value, label, optional trend.
struct DriverStatChip: View {
    let icon: VSIconName
    let value: String
    let label: String
    var detail: String? = nil
    var trend: String? = nil
    var trendUp: Bool = false
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                VSIcon(
                    icon: icon,
                    size: 14,
                    weight: .fill,
                    tint: emphasized ? VS.Color.accent : VS.Color.textTertiary
                )
                Text(label.uppercased())
                    .font(VS.Typography.body(10, weight: .bold))
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(1)
            }

            Text(value)
                .font(VS.Typography.heading(22, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            if let trend {
                Text(trend)
                    .font(VS.Typography.body(11, weight: .semibold))
                    .foregroundStyle(trendUp ? VS.Color.warning : VS.Color.accent)
                    .lineLimit(1)
            } else if let detail {
                Text(detail)
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                .fill(emphasized ? VS.Color.accent.opacity(0.12) : VS.Color.chip.opacity(0.45))
        }
        .overlay {
            RoundedRectangle(cornerRadius: VS.Radius.metric, style: .continuous)
                .strokeBorder(
                    emphasized ? VS.Color.accent.opacity(0.45) : VS.Color.hairline,
                    lineWidth: emphasized ? 1.5 : 1
                )
        }
    }
}
