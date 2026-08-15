import SwiftUI

private enum OnboardingPage: Int, CaseIterable {
    case drives
    case insights
    case permissions
}

struct TripPermissionsOnboardingView: View {
    @EnvironmentObject private var permissions: TripPermissionsManager
    @EnvironmentObject private var permissionsStore: TripPermissionsStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onComplete: (() -> Void)?

    @State private var page: OnboardingPage
    @State private var routeProgress: CGFloat = 0
    @State private var routeArrival = false
    @State private var insightProgress: Double = 0
    @State private var insightArrival = false

    init(startAtPermissions: Bool = false, onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
        _page = State(initialValue: startAtPermissions ? .permissions : .drives)
    }

    var body: some View {
        ZStack {
            VeloseeteBackground()
            ambientGlow

            VStack(spacing: 0) {
                topBar

                Group {
                    switch page {
                    case .drives:
                        valuePage(
                            eyebrow: "YOUR CAR, REMEMBERED",
                            title: "Every drive tells\na story.",
                            subtitle: "Veloseete turns everyday trips into a living history of your car — without the admin.",
                            visual: AnyView(routeVisual)
                        )
                    case .insights:
                        valuePage(
                            eyebrow: "LESS GUESSING. MORE GOING.",
                            title: "Know your car.\nEnjoy the drive.",
                            subtitle: "See distance, fuel rhythm and recent routes together, so the useful stuff is ready when you need it.",
                            visual: AnyView(insightVisual)
                        )
                    case .permissions:
                        permissionsPage
                    }
                }
                .id(page)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                bottomBar
            }
        }
        .onAppear {
            permissions.refreshStatuses()
            animateCurrentPage()
        }
        .onChange(of: page) { _, _ in animateCurrentPage() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refreshStatuses() }
        }
    }

    private var ambientGlow: some View {
        Circle()
            .fill(VS.Color.accent.opacity(0.10))
            .frame(width: 330, height: 330)
            .blur(radius: 90)
            .offset(x: 170, y: page == .permissions ? 250 : -170)
            .animation(.easeInOut(duration: 0.7), value: page)
            .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Image("VeloseeteMark")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            Spacer()

            HStack(spacing: 6) {
                ForEach(OnboardingPage.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == page ? VS.Color.accent : Color.white.opacity(0.16))
                        .frame(width: item == page ? 24 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: page)

            if page != .permissions {
                Button("Skip") { goToPermissions() }
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.textSecondary)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func valuePage(
        eyebrow: String,
        title: String,
        subtitle: String,
        visual: AnyView
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            visual
                .frame(maxWidth: .infinity)
                .frame(height: 315)

            Spacer(minLength: 16)

            Text(eyebrow)
                .font(VS.Typography.body(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(VS.Color.accent)

            Text(title)
                .font(VS.Typography.heading(39, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(VS.Color.textPrimary)
                .padding(.top, 10)

            Text(subtitle)
                .font(VS.Typography.body(15))
                .foregroundStyle(VS.Color.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var routeVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(VS.Color.divider, lineWidth: 1)
                }
                .rotationEffect(.degrees(-3))

            Path { path in
                path.move(to: CGPoint(x: 52, y: 252))
                path.addCurve(
                    to: CGPoint(x: 280, y: 62),
                    control1: CGPoint(x: 94, y: 135),
                    control2: CGPoint(x: 222, y: 206)
                )
            }
            .trim(from: 0, to: routeProgress * 0.98)
            .stroke(
                VS.Color.accent,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 13])
            )
            .shadow(color: VS.Color.accent.opacity(0.45), radius: 10)

            visualPin(icon: .car, label: "YOU", alignment: .bottomLeading)
                .scaleEffect(routeArrival ? 1 : 0.82)
                .opacity(routeArrival ? 1 : 0)
            visualPin(icon: .target, label: "48.2 KM", alignment: .topTrailing)
                .scaleEffect(routeArrival ? 1 : 0.82)
                .opacity(routeArrival ? 1 : 0)

            Text("DRIVE LOGGED")
                .font(VS.Typography.body(10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(VS.Color.navPill)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(VS.Color.accent, in: Capsule())
                .rotationEffect(.degrees(5))
                .offset(x: 62, y: 22)
                .scaleEffect(routeArrival ? 1 : 0.7)
                .opacity(routeArrival ? 1 : 0)
        }
    }

    private func visualPin(icon: VSIconName, label: String, alignment: Alignment) -> some View {
        VStack(spacing: 7) {
            VSIcon(icon: icon, size: 25, weight: .fill, tint: VS.Color.navPill)
                .frame(width: 54, height: 54)
                .background(VS.Color.accent, in: Circle())
                .shadow(color: VS.Color.accent.opacity(0.30), radius: 14)
            Text(label)
                .font(VS.Typography.body(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(VS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(26)
    }

    private var insightVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(VS.Color.divider, lineWidth: 1)
                }
                .rotationEffect(.degrees(2))

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    insightTile(icon: .gauge, value: "\(Int(612 * insightProgress))", label: "KM THIS MONTH", tint: VS.Color.accent)
                    insightTile(icon: .gasPump, value: String(format: "%.1f", 7.4 * insightProgress), label: "L / 100 KM", tint: VS.Color.accentSecondary)
                }
                HStack(spacing: 10) {
                    VSIcon(icon: .wrench, size: 21, weight: .regular, tint: VS.Color.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next service in 1,840 km")
                            .font(VS.Typography.heading(14))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("You’re comfortably on track")
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    Spacer()
                    Text("NICE")
                        .font(VS.Typography.body(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(VS.Color.accent, in: Capsule())
                }
                .padding(16)
                .glassCard()
                .offset(y: insightArrival ? 0 : 16)
                .opacity(insightArrival ? 1 : 0)
            }
            .padding(24)
        }
    }

    private func insightTile(icon: VSIconName, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VSIcon(icon: icon, size: 22, weight: .regular, tint: tint)
            Spacer()
            Text(value)
                .font(VS.Typography.heading(28, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(label)
                .font(VS.Typography.body(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(16)
        .glassCard(elevated: true)
    }

    private func animateCurrentPage() {
        if reduceMotion {
            routeProgress = 1
            routeArrival = true
            insightProgress = 1
            insightArrival = true
            return
        }

        switch page {
        case .drives:
            routeProgress = 0
            routeArrival = false
            withAnimation(.easeInOut(duration: 1.05)) { routeProgress = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68).delay(0.72)) {
                routeArrival = true
            }
        case .insights:
            insightProgress = 0
            insightArrival = false
            withAnimation(.easeOut(duration: 0.9)) { insightProgress = 1 }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.35)) {
                insightArrival = true
            }
        case .permissions:
            break
        }
    }

    private var permissionsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ONE LAST PIT STOP")
                        .font(VS.Typography.body(11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(VS.Color.accent)
                    Text("Make the magic\nwork.")
                        .font(VS.Typography.heading(38, weight: .bold))
                        .tracking(-1.1)
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("Switch on what you’re comfortable with. Each one has a clear job — and you stay in control.")
                        .font(VS.Typography.body(15))
                        .foregroundStyle(VS.Color.textSecondary)
                        .lineSpacing(4)
                }

                VStack(spacing: 0) {
                    permissionRow(
                        icon: .mapPin,
                        title: "Location",
                        detail: locationDetail,
                        state: locationControlState,
                        action: handleLocationAction
                    )
                    divider
                    permissionRow(
                        icon: .personSimpleRun,
                        title: "Motion",
                        detail: "Knows a drive from a walk",
                        state: motionControlState,
                        action: handleMotionAction
                    )
                    divider
                    permissionRow(
                        icon: .bell,
                        title: "Notifications",
                        detail: "Confirms trips at the right moment",
                        state: notificationControlState,
                        action: handleNotificationAction
                    )
                }
                .glassCard(elevated: true)

                HStack(spacing: 8) {
                    VSIcon(icon: .eye, size: 16, weight: .regular, tint: VS.Color.textTertiary)
                    Text("No ads. No selling your movement. Change access anytime in Settings.")
                        .font(VS.Typography.body(11))
                        .foregroundStyle(VS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(VS.Color.divider)
            .frame(height: 1)
            .padding(.leading, 72)
    }

    private enum PermissionControlState {
        case off
        case partial
        case on
        case settings
    }

    private func permissionRow(
        icon: VSIconName,
        title: String,
        detail: String,
        state: PermissionControlState,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VSIcon(icon: icon, size: 22, weight: .regular, tint: state == .on ? VS.Color.navPill : VS.Color.accent)
                    .frame(width: 46, height: 46)
                    .background(state == .on ? VS.Color.accent : VS.Color.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(VS.Typography.heading(15))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text(detail)
                        .font(VS.Typography.body(11))
                        .foregroundStyle(state == .settings ? VS.Color.warning : VS.Color.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                permissionSwitch(state)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(accessibilityValue(for: state))
    }

    private func permissionSwitch(_ state: PermissionControlState) -> some View {
        ZStack(alignment: state == .off || state == .settings ? .leading : .trailing) {
            Capsule()
                .fill(state == .on ? VS.Color.accent : state == .partial ? VS.Color.warning : Color.white.opacity(0.13))
                .frame(width: 50, height: 30)
            Circle()
                .fill(VS.Color.navPill)
                .frame(width: 24, height: 24)
                .padding(3)
        }
        .overlay {
            if state == .partial {
                Text("1×")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .offset(x: -9)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: String(describing: state))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            PrimaryCTAButton(
                title: page == .permissions ? "Start exploring" : "Keep going",
                icon: page == .permissions ? .checkCircle : nil
            ) {
                if page == .permissions { complete() } else { advance() }
            }

            if page == .permissions {
                Button("I’ll do this later") { complete() }
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.textSecondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [.clear, VS.Color.bgPrimary.opacity(0.96), VS.Color.bgPrimary],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private var locationDetail: String {
        switch permissions.locationStatus {
        case .whenInUse: return "Tap again for automatic background trips"
        case .always: return "Logs route and distance automatically"
        case .denied, .restricted: return "Open Settings to allow access"
        case .notDetermined: return "Logs route and distance automatically"
        }
    }

    private var locationControlState: PermissionControlState {
        switch permissions.locationStatus {
        case .notDetermined: return .off
        case .whenInUse: return .partial
        case .always: return .on
        case .denied, .restricted: return .settings
        }
    }

    private var motionControlState: PermissionControlState {
        switch permissions.motionStatus {
        case .authorized, .unavailable: return .on
        case .notDetermined: return .off
        case .denied, .restricted: return .settings
        }
    }

    private var notificationControlState: PermissionControlState {
        switch permissions.notificationStatus {
        case .authorized, .provisional, .ephemeral: return .on
        case .notDetermined: return .off
        case .denied: return .settings
        }
    }

    private func accessibilityValue(for state: PermissionControlState) -> String {
        switch state {
        case .off: return "Off"
        case .partial: return "While using enabled; background access available"
        case .on: return "On"
        case .settings: return "Needs Settings"
        }
    }

    private func handleLocationAction() {
        switch permissions.locationStatus {
        case .notDetermined: permissions.requestWhenInUseLocation()
        case .whenInUse: permissions.requestAlwaysLocation()
        case .always: break
        case .denied, .restricted: permissions.openSettings()
        }
    }

    private func handleMotionAction() {
        switch permissions.motionStatus {
        case .notDetermined: permissions.requestMotion()
        case .denied, .restricted: permissions.openSettings()
        case .authorized, .unavailable: break
        }
    }

    private func handleNotificationAction() {
        switch permissions.notificationStatus {
        case .notDetermined: permissions.requestNotifications()
        case .denied: permissions.openSettings()
        case .authorized, .provisional, .ephemeral: break
        }
    }

    private func advance() {
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { page = next }
    }

    private func goToPermissions() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { page = .permissions }
    }

    private func complete() {
        permissionsStore.complete()
        onComplete?()
    }
}
