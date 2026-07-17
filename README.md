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

Uses the same project as the web PWA. Config is in `Services/Firestore/FirebaseBootstrap.swift`.

When you have an Apple Developer account:

1. Register an iOS app in Firebase Console (bundle id `com.veloseete.app`)
2. Download `GoogleService-Info.plist` into `Veloseete/`
3. Prefer that over the programmatic web fallback

## Requirements

- Xcode 16+
- iOS 17+
- No paid Apple Developer team required for Simulator builds
