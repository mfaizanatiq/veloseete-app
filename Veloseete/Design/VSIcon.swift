import SwiftUI

enum VSIconName: String {
    case arrowLeft = "arrow-left"
    case bell
    case bellRinging = "bell-ringing"
    case car
    case caretDown = "caret-down"
    case caretLeft = "caret-left"
    case chartLine = "chart-line"
    case checkCircle = "check-circle"
    case cloud
    case eye
    case eyeSlash = "eye-slash"
    case fileText = "file-text"
    case gasPump = "gas-pump"
    case gauge
    case heartStraight = "heart-straight"
    case mapPin = "map-pin"
    case mapTrifold = "map-trifold"
    case navigationArrow = "navigation-arrow"
    case pause
    case personSimpleRun = "person-simple-run"
    case play
    case plusCircle = "plus-circle"
    case roadHorizon = "road-horizon"
    case stop
    case target
    case user
    case warningCircle = "warning-circle"
    case wrench
    case x
}

enum VSIconWeight: String {
    case regular
    case bold
    case fill
    case duotone
}

/// Sized local Phosphor icon asset — matches web `phosphor-react` usage (`size` + `weight`).
struct VSIcon: View {
    let icon: VSIconName
    var size: CGFloat = 20
    var weight: VSIconWeight = .regular
    var tint: Color = VS.Color.textSecondary

    var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(tint)
    }

    private var assetName: String {
        "ph-\(icon.rawValue)-\(weight.rawValue)"
    }
}
