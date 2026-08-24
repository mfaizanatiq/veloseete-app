#if DEBUG
import SwiftUI

/// Simulator-only mock — arc meter + driver health.
/// Launch with: `-DriveHUDPreview`
struct ActiveDriveHUDPreview: View {
    @State private var tick = 0

    private var model: ActiveDriveHUDModel {
        var base = ActiveDriveHUDModel.preview
        let wave = sin(Double(tick) * 0.35) * 11
        base.speedKmh = 57 + wave
        let drainWave = (sin(Double(tick) * 0.22) + 1) / 2
        base.efficiencyReserve = max(0.12, 1 - drainWave * 0.55)
        base.durationSec = 1458 + Double(tick) * 12
        base.thirst = 0.18 + drainWave * 0.4
        var intel = base.intelligence
        intel.tankFillLevel = max(0.18, 0.78 - drainWave * 0.45)
        base.intelligence = intel
        return base
    }

    var body: some View {
        ZStack {
            VS.Color.bgPrimary.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: 0x1A1F18),
                    Color(hex: 0x0B0E0B),
                    Color(hex: 0x12160E)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .overlay {
                Text("MAP FROZEN")
                    .font(VS.Typography.mono(11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.18))
                    .tracking(2)
            }

            VStack {
                Spacer(minLength: 0)
                panel
                    .padding(.horizontal, VS.Spacing.frameGutter)
                    .padding(.bottom, VS.Spacing.frameGutter + 12)
            }
        }
        .onReceive(Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()) { _ in
            tick += 1
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            ActiveDriveHUDContent(
                model: model,
                pulseOpacity: tick % 2 == 0 ? 1 : 0.45
            )

            HStack(spacing: 10) {
                Text("Pause")
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VS.Color.divider, in: Capsule())

                Text("End drive")
                    .font(VS.Typography.heading(16, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VS.Color.accent, in: Capsule())
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
                .fill(Color(hex: 0x161916))
                .overlay(
                    RoundedRectangle(cornerRadius: VS.Radius.panel, style: .continuous)
                        .stroke(VS.Color.hairline, lineWidth: 1)
                )
        )
    }
}

#Preview("Drive HUD · Arc") {
    ActiveDriveHUDPreview()
}
#endif
