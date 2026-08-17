# Veloseete iOS

Native SwiftUI app for **Veloseete** — same Firebase backend as the web app (`velocity-5e576`).

## Phase v1 (current)

- Splash → Auth (sign in / sign up / reset password)
- Load `users`, `vehicles`, `fuelLogs`, `serviceLogs` from Firestore
- Pixel-close Dashboard (hero, metrics, recent refuels)
- Bottom nav: Overview · Analytics · Details · Service · **Trips** (placeholder)
- Profile sheet with sign out
- Pull-to-refresh
- **Garage 3-step onboarding** (writes vehicles to Firestore)
- **Add Refuel sheet** (writes fuel logs + updates odometer)
- Add vehicle from Profile

## Upcoming

- **v1.5+** — Service writes, edit/delete entries, offline queue, analytics charts
- **v2** — Smart trip detection, Live Activities, MapKit, odometer confirm

## Open in Xcode

```bash
cd Veloseete-iOS
xed .
# or
open Veloseete.xcodeproj
```

## Firebase

Same project as the web PWA: `velocity-5e576`.

Auth providers: **Email/password**, **Google**, and **Sign in with Apple** (linkable on one account).

1. iOS app is registered in Firebase (`com.veloseete.ios`)
2. Keep `Veloseete/GoogleService-Info.plist` on the machine (gitignored) — regenerate with:
   `firebase apps:sdkconfig IOS --project velocity-5e576 -o Veloseete/GoogleService-Info.plist`
3. **Paid Apple Developer Program** is required for Sign in with Apple on device / App Store
   - Release builds use `Veloseete.entitlements` (SIWA on)
   - Debug builds use `VeloseeteDebug.entitlements` (SIWA off) so personal teams can still install Google + email
4. Apple Developer → Identifiers → `com.veloseete.ios` → enable **Sign in with Apple**
5. Firebase Console → Authentication → Sign-in method: Email, Google, Apple (Email + Google enabled; Apple IdP created for `com.veloseete.ios`)
6. For production Apple (web/OAuth secret), add Team ID + Key (.p8) under Firebase → Apple provider

## Requirements

- Xcode 16+
- iOS 17+
- No paid Apple Developer team required for Simulator builds

## CarPlay

Veloseete includes a CarPlay driving-task scene for live trip status, start/pause/resume/end controls, pending-trip save/discard, recent drives, and refuel handoff. At a station, **Log refuel** captures the vehicle, time, and estimated odometer; opening the iPhone presents the existing refuel sheet prefilled so the driver can safely enter exact liters, receipt cost, and dashboard odometer while parked. The CarPlay UI uses Apple system templates and refreshes live metrics every 10 seconds.

On iOS 26, the **Veloseete Footprint** `systemSmall` widget can be added to CarPlay. It shows the current car, total driving footprint, average efficiency, this month's fuel spend, and the most recent route map on the trailing side. The existing Live Activity remains responsible for active-trip information. The Driving Task CarPlay screen also shows route-map thumbnails for active and recent drives; a full interactive `CPMapTemplate` requires Apple's separate navigation/maps entitlement.

Before device or CarPlay Simulator testing:

1. Request the **Driving Task** CarPlay entitlement from [Apple](https://developer.apple.com/carplay/).
2. Enable the approved CarPlay capability for the `com.veloseete.ios` App ID.
3. Regenerate and install development and distribution provisioning profiles containing `com.apple.developer.carplay-driving-task`.
4. Enable the `group.com.veloseete.shared` App Group for both `com.veloseete.ios` and `com.veloseete.ios.TripWidget`, then regenerate their profiles.
5. In Simulator, run Veloseete and choose **I/O → External Displays → CarPlay**.

The entitlement must be approved by Apple and included in the signing profile; adding the entitlement file entry alone is not sufficient for a signed device build.
