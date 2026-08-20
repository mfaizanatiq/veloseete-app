import Foundation
import FirebaseCore
import FirebaseFirestore

enum FirebaseBootstrap {
    /// Prefer `GoogleService-Info.plist` when present (register iOS app in Firebase Console).
    static func configure() {
        guard FirebaseApp.app() == nil else { return }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            print("[Firebase] Configured from GoogleService-Info.plist — project \(options.projectID ?? "?")")
            enablePersistentCache()
            return
        }

        #if DEBUG
        // Local/dev fallback only — Release builds must ship GoogleService-Info.plist.
        // Must match the paid-team app `com.veloseete.ios` (not legacy `com.veloseete.app`).
        let options = FirebaseOptions(
            googleAppID: "1:1090690719538:ios:10c3a8e8271fa659bec12b",
            gcmSenderID: "1090690719538"
        )
        options.apiKey = "AIzaSyDFxFjV2ED9aX-adXe5_jjx9JxEywnFMQ0"
        options.projectID = "velocity-5e576"
        options.storageBucket = "velocity-5e576.firebasestorage.app"
        options.bundleID = Bundle.main.bundleIdentifier ?? "com.veloseete.ios"
        options.clientID = "1090690719538-92risgqg4vsdan80orit4k3l16br8lou.apps.googleusercontent.com"

        FirebaseApp.configure(options: options)
        print("[Firebase] Configured programmatic DEBUG fallback — project \(options.projectID ?? "?")")
        enablePersistentCache()
        #else
        // Never ship a Release binary that can limp along without Firebase —
        // Auth.auth() would crash on first use with a confusing system assert.
        fatalError("[Firebase] GoogleService-Info.plist is required for Release builds")
        #endif
    }

    /// Keep a local Firestore disk cache so the app can open from last-known
    /// data even when Google endpoints are slow (VPNs, flaky networks).
    /// Must run before any other Firestore call.
    private static func enablePersistentCache() {
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        print("[Firebase] Persistent Firestore cache enabled")
    }
}
