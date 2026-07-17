import SwiftUI

private enum TripPermissionStep: Int, CaseIterable {
    case intro
    case location
    case motion
    case notifications

    var title: String {
        switch self {
        case .intro:
            return "Set up trip tracking"
        case .location:
            return "Enable location"
        case .motion:
            return "Enable motion"
        case .notifications:
            return "Enable alerts"
        }
    }

    var icon: VSIconName {
        switch self {
        case .intro:
            return .roadHorizon
        case .location:
            return .mapPin
        case .motion:
            return .personSimpleRun
        case .notifications:
            return .bellRinging
        }
    }
}

struct TripPermissionsOnboardingView: View {
    @EnvironmentObject private var permissions: TripPermissionsManager
    @EnvironmentObject private var permissionsStore: TripPermissionsStore
    @Environment(\.scenePhase) private var scenePhase

    var onComplete: (() -> Void)? = nil

    @State private var step: TripPermissionStep = .intro

    var body: some View {
        ZStack {
            VeloseeteBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        stepBody
                        statusList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 140)
                }
            }

            VStack {
                Spacer()
                actionBar
            }
        }
        .onAppear {
            permissions.refreshStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refreshStatuses()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Veloseete")
                .font(VS.Typography.heading(20, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Spacer()
            Text("\(step.rawValue + 1) of \(TripPermissionStep.allCases.count)")
                .font(VS.Typography.body(12, weight: .semibold))
                .foregroundStyle(VS.Color.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    Circle()
                        .fill(VS.Color.accent.opacity(0.14))
                        .frame(width: 64, height: 64)
                    VSIcon(icon: step.icon, size: 34, weight: .duotone, tint: VS.Color.accent)
                }
                Spacer()
                progressDots
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(VS.Typography.heading(30, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(stepSubtitle)
                    .font(VS.Typography.body(15))
                    .foregroundStyle(VS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .glassCard(elevated: true)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(TripPermissionStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? VS.Color.accent : Color.white.opacity(0.14))
                    .frame(width: item == step ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: step)
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .intro:
            VStack(alignment: .leading, spacing: 12) {
                permissionCard(
                    icon: .target,
                    title: "Accurate kilometers",
                    body: "Veloseete will use trips to keep distance, routes, and efficiency honest."
                )
                permissionCard(
                    icon: .heartStraight,
                    title: "Built for control",
                    body: "You can skip now, enable later, or change permissions from iPhone Settings anytime."
                )
            }
        case .location:
            VStack(alignment: .leading, spacing: 12) {
                permissionCard(
                    icon: .navigationArrow,
                    title: "When In Use first",
                    body: "We ask while the app is open before upgrading to background detection."
                )
                permissionCard(
                    icon: .mapPin,
                    title: "Always for background drives",
                    body: "Always location lets future smart tracking keep counting kilometers after you leave the app."
                )
            }
        case .motion:
            permissionCard(
                icon: .personSimpleRun,
                title: "Fewer false starts",
                body: "Motion helps Veloseete tell driving apart from walking or idle time."
            )
        case .notifications:
            permissionCard(
                icon: .bell,
                title: "Trip prompts",
                body: "Alerts prepare Veloseete to ask when a drive starts or needs odometer confirmation."
            )
        }
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                icon: .mapPin,
                title: "Location",
                status: locationStatusText,
                ready: permissions.locationStatus == .always
            )
            statusRow(
                icon: .personSimpleRun,
                title: "Motion",
                status: motionStatusText,
                ready: permissions.motionStatus.isReady
            )
            statusRow(
                icon: .bell,
                title: "Notifications",
                status: notificationStatusText,
                ready: permissions.notificationStatus.isReady
            )
        }
        .padding(14)
        .glassCard()
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button(primaryButtonTitle) {
                handlePrimaryAction()
            }
            .font(VS.Typography.heading(17))
            .foregroundStyle(VS.Color.navPill)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VS.Color.accent, in: RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
            .buttonStyle(ScaleButtonStyle())

            Button(secondaryButtonTitle) {
                handleSecondaryAction()
            }
            .font(VS.Typography.body(14, weight: .semibold))
            .foregroundStyle(VS.Color.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [.clear, VS.Color.bgPrimary.opacity(0.95), VS.Color.bgPrimary],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func permissionCard(icon: VSIconName, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VSIcon(icon: icon, size: 22, weight: .regular, tint: VS.Color.accent)
                .frame(width: 34, height: 34)
                .background(VS.Color.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(VS.Typography.heading(15))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(body)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .glassCard()
    }

    private func statusRow(icon: VSIconName, title: String, status: String, ready: Bool) -> some View {
        HStack(spacing: 12) {
            VSIcon(icon: icon, size: 18, weight: .regular, tint: ready ? VS.Color.accent : VS.Color.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VS.Typography.body(13, weight: .semibold))
                    .foregroundStyle(VS.Color.textPrimary)
                Text(status)
                    .font(VS.Typography.body(12))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            Spacer()
            VSIcon(
                icon: ready ? .checkCircle : .warningCircle,
                size: 20,
                weight: ready ? .fill : .regular,
                tint: ready ? VS.Color.accent : VS.Color.warning
            )
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .intro:
            return "A few permissions make future automatic trip tracking accurate without extra typing."
        case .location:
            return "Location powers route distance and background drive detection when trip tracking is enabled."
        case .motion:
            return "Motion keeps trip starts smarter, so a walk or quick stop does not become a drive."
        case .notifications:
            return "Notifications prepare the app to confirm detected drives and keep Live Activity prompts visible."
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .intro:
            return "Continue"
        case .location:
            switch permissions.locationStatus {
            case .notDetermined:
                return "Enable location"
            case .whenInUse:
                return "Enable background tracking"
            case .always:
                return "Continue"
            case .denied, .restricted:
                return "Open Settings"
            }
        case .motion:
            switch permissions.motionStatus {
            case .notDetermined:
                return "Enable motion"
            case .denied, .restricted:
                return "Open Settings"
            case .authorized, .unavailable:
                return "Continue"
            }
        case .notifications:
            switch permissions.notificationStatus {
            case .notDetermined:
                return "Enable notifications"
            case .denied:
                return "Open Settings"
            case .authorized, .provisional, .ephemeral:
                return "Finish setup"
            }
        }
    }

    private var secondaryButtonTitle: String {
        step == .notifications ? "Not now" : "Skip for now"
    }

    private var locationStatusText: String {
        switch permissions.locationStatus {
        case .notDetermined:
            return "Not requested"
        case .whenInUse:
            return "Allowed while using"
        case .always:
            return "Ready for background trips"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    private var motionStatusText: String {
        switch permissions.motionStatus {
        case .notDetermined:
            return "Not requested"
        case .authorized:
            return "Ready"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .unavailable:
            return "Unavailable on this device"
        }
    }

    private var notificationStatusText: String {
        switch permissions.notificationStatus {
        case .notDetermined:
            return "Not requested"
        case .authorized:
            return "Ready"
        case .denied:
            return "Denied"
        case .provisional:
            return "Quiet alerts enabled"
        case .ephemeral:
            return "Temporary alerts enabled"
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .intro:
            advance()
        case .location:
            handleLocationAction()
        case .motion:
            handleMotionAction()
        case .notifications:
            handleNotificationAction()
        }
    }

    private func handleLocationAction() {
        switch permissions.locationStatus {
        case .notDetermined:
            permissions.requestWhenInUseLocation()
        case .whenInUse:
            permissions.requestAlwaysLocation()
        case .always:
            advance()
        case .denied, .restricted:
            permissions.openSettings()
        }
    }

    private func handleMotionAction() {
        switch permissions.motionStatus {
        case .notDetermined:
            permissions.requestMotion()
        case .authorized, .unavailable:
            advance()
        case .denied, .restricted:
            permissions.openSettings()
        }
    }

    private func handleNotificationAction() {
        switch permissions.notificationStatus {
        case .notDetermined:
            permissions.requestNotifications()
        case .authorized, .provisional, .ephemeral:
            complete()
        case .denied:
            permissions.openSettings()
        }
    }

    private func handleSecondaryAction() {
        if step == .notifications {
            complete()
        } else {
            advance()
        }
    }

    private func advance() {
        guard let next = TripPermissionStep(rawValue: step.rawValue + 1) else {
            complete()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = next
        }
    }

    private func complete() {
        permissionsStore.complete()
        onComplete?()
    }
}
