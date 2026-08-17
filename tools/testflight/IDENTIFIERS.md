# Veloseete — Apple identifiers (TestFlight)

Team: `X978QRK3WP` (paid Developer Team) · Bundle prefix: `com.veloseete`

## Identifiers (registered via automatic signing)

| Kind | Identifier |
|------|------------|
| iOS App | `com.veloseete.ios` |
| Widget extension | `com.veloseete.ios.TripWidget` |
| App Group | `group.com.veloseete.shared` |

> Note: `com.veloseete.app` / `group.com.veloseete.app` are locked to the old personal team (`B97UDSSKPC`) and cannot be reused on this paid team.

### App capabilities
- Sign in with Apple
- App Groups → `group.com.veloseete.shared`
- Background Modes → Location (Info.plist)

### Widget capabilities
- App Groups → `group.com.veloseete.shared`

## Firebase
- Project: `velocity-5e576`
- New iOS app: `com.veloseete.ios` (`1:1090690719538:ios:10c3a8e8271fa659bec12b`)
- Config: `Veloseete/GoogleService-Info.plist`

## Build artifacts
- Archive: `build/Veloseete.xcarchive`
- IPA: `build/TestFlightExport/Veloseete.ipa`

## App Store Connect
1. Create app with bundle ID `com.veloseete.ios` (SKU: `veloseete-ios`)
2. Privacy Policy URL: `https://mfaizanatiq.github.io/Veloseete-iOS/privacy/` (enable GitHub Pages from `/docs` first — see `docs/README.md`)
3. Terms / EULA (if asked): `https://mfaizanatiq.github.io/Veloseete-iOS/terms/`
4. Support contact: `m.faizan.atiq@icloud.com`
5. Upload IPA via Transporter / Xcode Organizer
6. TestFlight → wait for processing → add testers
