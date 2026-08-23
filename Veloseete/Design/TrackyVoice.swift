import CoreLocation
import Foundation

/// Veloseete voice system.
///
/// Three volumes — same co-pilot personality, different heat:
/// - **Loud** — Drives live panel, confirm sheet, drive push (first person, roast OK).
/// - **Soft** — empty states, Fuels/Driver/Garage warmth (you-facing, light wit).
/// - **Calm** — Auth, forms, delete/archive, CarPlay, a11y (plain, no slang).
///
/// Glossary: **Drive** (trip), **Fill** (fuel log noun), **Refuel** (verb only),
/// **Confirm** (chrome for pending), Tracky CTA flavor on buttons only.
enum TrackyVoice {

    // MARK: - Loud (Drives)

    static func phaseTitle(phase: TripRecordingPhase, isPaused: Bool) -> String {
        switch phase {
        case .idle: return "I'm ready when you are"
        case .watching: return "Eyes on the road (yours)"
        case .recording: return isPaused ? "Paused. Dramatic." : "We're live"
        case .confirming: return "This one real?"
        }
    }

    static func phaseSubtitle(phase: TripRecordingPhase, autoOn: Bool, source: String?) -> String {
        switch phase {
        case .idle:
            return autoOn
                ? "Auto ON — I'll jump in when you roll"
                : "Auto OFF — poke the capsule if you want me hunting"
        case .watching:
            return "Just vibing till the wheels move"
        case .recording:
            let src = (source ?? "manual") == "auto" ? "auto catch" : "manual start"
            return "Counting km · \(src) · don't ghost me"
        case .confirming:
            return "Peek the route, tap yes, we move"
        }
    }

    static func odometerCaption(live: Bool, pendingIn: Bool) -> String {
        if live { return "Tracky count · live" }
        if pendingIn { return "Tracky count · pending in" }
        return "Tracky count · estimated"
    }

    static func monthLine(_ distanceLabel: String) -> String {
        "\(distanceLabel) this month — cute streak"
    }

    static func autoCapsule(isOn: Bool) -> String {
        isOn ? "Auto ON" : "Auto OFF"
    }

    static func autoAccessibility(isOn: Bool) -> String {
        isOn ? "Tracky auto-detect on" : "Tracky auto-detect off"
    }

    static func pendingTitle(count: Int) -> String {
        count == 1 ? "One drive still open" : "\(count) drives waiting on you"
    }

    static func pendingSubtitle(distanceLabel: String) -> String {
        "+\(distanceLabel) already in the estimate"
    }

    static func pendingCTA(count: Int) -> String {
        count == 1 ? "Say yes" : "Clear queue"
    }

    static func fuelTitle(_ base: String) -> String {
        Soft.fuelBanner(base)
    }

    static func startCTA() -> String { "Let's roll" }
    static func endCTA() -> String { "End it" }
    static func pauseCTA() -> String { "Pause" }
    static func resumeCTA() -> String { "Back on" }

    static func mapChip(recording: Bool, trackingMode: Bool) -> String {
        if recording { return "LIVE ROUTE" }
        return trackingMode ? "TRACKY'S WATCHING" : "PICK A DRIVE"
    }

    static func routeStatus(accuracy: CLLocationAccuracy?) -> String {
        guard let accuracy else { return "Hunting GPS… hold up" }
        if accuracy <= 15 { return "GPS locked in · ±\(Int(accuracy)) m" }
        if accuracy <= 30 { return "GPS decent · ±\(Int(accuracy)) m" }
        return "GPS mid · ±\(Int(accuracy)) m — still counting"
    }

    static func confirmHeadline() -> String { "This one real?" }

    static func confirmEstimateTitle(km: Double) -> String {
        "~\(String(format: "%.0f", km)) km on my count"
    }

    static func confirmEstimateBody() -> String {
        "Already in the estimate. Confirm saves history. Dash number waits for the pump."
    }

    static func confirmFallbackTitle() -> String { "Adds to my estimate" }

    static func confirmFallbackBody() -> String {
        "Verified odometer only changes when you type the car's number — usually at a fill."
    }

    static func confirmCTA(hasNext: Bool) -> String {
        hasNext ? "Lock it · next" : "Lock it in"
    }

    static func discardCTA() -> String { "Nah, trash it" }

    static func drivesAwaiting(_ count: Int) -> String {
        count == 1
            ? "1 drive waiting on you"
            : "\(count) drives waiting on you"
    }

    static func reviewRequired() -> String { Soft.pendingSection }

    static func emptyDrivesTitle() -> String { Soft.emptyDrivesTitle }
    static func emptyDrivesBody() -> String { Soft.emptyDrivesBody }

    static func confirmAll() -> String { Calm.confirmAll }

    // MARK: - Soft (warm product empties / Fuels / Driver / Garage)

    enum Soft {
        static let pendingSection = "Waiting on you"
        static let pendingBadge = "OPEN"
        static let confirmedBadge = "SAVED"

        static let addFillCTA = "+ Add fill"
        static let recentFills = "Recent fills"
        static let seeAllFills = "See all"
        static let fillHistory = "Fill history"
        static let fillsLabel = "Fills"

        static let emptyFuelsTitle = "First fill’s the charm"
        static let emptyFuelsBody = "Log a fill — spend and efficiency show up."
        static let fuelsHeroHint = "A few fills and this car’s personality shows up."
        static let emptyHistory = "No fills logged yet."

        static func syncChip(cars: Int, fills: Int) -> String {
            "\(cars) cars · \(fills) fills"
        }

        static let garageSubtitle = "Your cars"
        static let emptyGarageTitle = "Garage’s quiet"
        static let emptyGarageBody = "Add a car and I’ll connect drives, fills, and service."
        static let emptyGarageCTA = "Add your first car"

        static let serviceSubtitle = "Keep it healthy"
        static let emptyServiceTitle = "Log your first service"
        static let emptyServiceBody = "Oil, brakes, whatever’s due — leave a trail."
        static let logServiceCTA = "Log service"
        static let logServiceNav = "Log service"
        static let editServiceNav = "Edit service"
        static let saveService = "Save service"

        static let emptyInsightsTitle = "Nothing yet — that’s fine"
        static let emptyInsightsBody = "A few fills and drives unlock notes here."
        static let emptyTrendsTitle = "No trend yet"
        static let emptyTrendsBody = "A couple of fills unlock spend and efficiency charts."

        static let emptyBadgesTitle = "No medals yet"
        static let emptyBadgesBody = "Drive and fill — earned marks land here."

        static let emptyDrivesTitle = "No drives yet — let’s fix that"
        static let emptyDrivesBody =
            "Hit Let’s roll or flip Auto ON. I’ll catch the route, km, and that spicy top speed."

        static let odometerStepTitle = "Current odometer"
        static let odometerStepBody = "Dashboard reading right now — you can refine later"

        static let trackysMoodTitle = "Tracky’s mood"
        static let trackyCardHint = "Home screen icon follows along · tap to change"
        static let trackyInlineHint = "App icon"
        static let trackyDrawerSubtitle = "Face on Driver · icon on your Home Screen"

        static let inEstimateTitle = "In your Tracky count"
        static func inEstimateBody(distance: String) -> String {
            "Adds \(distance) until your next verified dash reading at a fill."
        }

        static let shareDrive = "Share drive"
        static let setUpTracking = "Set up trip tracking"

        static let welcomeBack = "Welcome back"
        static let createAccount = "Create your account"
        static let orEmail = "or email"

        static let authTagline = "Your car’s co-pilot — fills, drives, service."

        static let firstVehicleEyebrow = "START HERE"
        static let firstVehicleTitle = "Add the car you’ll track"
        static let firstVehicleBody =
            "Nickname it, pick a mark — Veloseete remembers every drive, fill, and service from here."

        static let permissionsKeepGoing = "Keep going"
        static let permissionsStartExploring = "Start exploring"
        static let permissionsLater = "I’ll do this later"

        static func fuelBanner(_ base: String) -> String {
            switch base {
            case "Running on fumes": return "Tank’s almost empty"
            case "Low fuel": return "Fuel’s getting low"
            case "Fuel watch": return "Fuel watch — just saying"
            default: return base
            }
        }
    }

    // MARK: - Calm (forms, destructive, system)

    enum Calm {
        static let confirmAll = "Confirm all"
        static let addFillNav = "Add fill"
        static let editFillNav = "Edit fill"
        static let saveFill = "Save fill"
        static let saveFillChanges = "Save changes"
        static let editThisFill = "Edit this fill"
        static let deleteFill = "Delete fill"
        static let deleteFillMessage =
            "This removes the fill from your history and updates efficiency."

        static let deleteDrive = "Delete drive"
        static let deleteDriveTitle = "Delete this drive?"
        static let deleteDriveMessage =
            "Removes this route and stats. Your dashboard odometer stays as entered."

        static let linkOrphanDrivesTitle = "Link earlier drives?"
        static func linkOrphanDrivesMessage(count: Int, distance: String, vehicleName: String) -> String {
            let driveWord = count == 1 ? "drive" : "drives"
            return "You tracked \(count) \(driveWord) (\(distance)) before adding a car. Attach them to \(vehicleName)?"
        }
        static func linkOrphanDrivesConfirm(vehicleName: String) -> String {
            "Link to \(vehicleName)"
        }
        static let linkOrphanDrivesSkip = "Not this car"

        static let archiveVehicle = "Archive vehicle"
        static let archiveVehicleMessage =
            "Hides this car from the garage. Drives, fills, and service stay saved."

        static let deleteServiceTitle = "Delete service entry?"
        static let deleteServiceMessage =
            "This removes the service record from your history."

        static let estimateIncludesPending =
            "Estimate includes drives waiting to confirm"

        static let currentOdometer = "Current odometer"

        static let managePermissions = "Trip permissions"
        static let managePermissionsDetail = "Location, motion, and notifications"
        static let replayOnboarding = "Replay intro"
        static let replayOnboardingDetail = "See the Veloseete welcome again"
        static let leaveFeedback = "Send feedback"
        static let leaveFeedbackDetail = "Bugs, praise, or missing bits — we read it"
        static let roadmap = "Roadmap"
        static let roadmapDetail = "Vote on what’s next, or request a feature"
        static let deleteAccount = "Delete account"
        static let deleteAccountTitle = "Delete account?"
        static let signOut = "Sign out"

        static let logFillCarPlay = "Log fill"
        static let logFillCarPlayBody =
            "Fill ready on iPhone. Enter amount, liters, and dashboard odometer while parked."

        static let hardAccel = "Hard accel"
        static let hardBrake = "Hard brake"
        static let heavyThrottle = "Heavy throttle"
        static let fastCruise = "Fast cruise · thirsty"
        static let readyWhenYouRoll = "Ready when you roll"
    }
}
