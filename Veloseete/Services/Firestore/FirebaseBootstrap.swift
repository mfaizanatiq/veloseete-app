import Foundation
import FirebaseCore

enum FirebaseBootstrap {
    /// Prefer `GoogleService-Info.plist` when present (register iOS app in Firebase Console).
    /// Falls back to programmatic options for the shared `velocity-5e576` project.
    static func configure() {
        guard FirebaseApp.app() == nil else { return }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            print("[Firebase] Configured from GoogleService-Info.plist — project \(options.projectID ?? "?")")
            return
        }

        // Registered iOS app in Firebase Console (prefer GoogleService-Info.plist in the bundle).
        let options = FirebaseOptions(
            googleAppID: "1:1090690719538:ios:9f5299b05e4b451bbec12b",
            gcmSenderID: "1090690719538"
        )
        options.apiKey = "AIzaSyDFxFjV2ED9aX-adXe5_jjx9JxEywnFMQ0"
        options.projectID = "velocity-5e576"
        options.storageBucket = "velocity-5e576.firebasestorage.app"
        options.bundleID = Bundle.main.bundleIdentifier ?? "com.veloseete.app"
        options.clientID = "1090690719538-7betv9lmo15m6qftsmuc9pdfqo87mf1c.apps.googleusercontent.com"

        FirebaseApp.configure(options: options)
        print("[Firebase] Configured programmatic fallback — project \(options.projectID ?? "?")")
    }
}
