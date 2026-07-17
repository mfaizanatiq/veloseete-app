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

        // Hex-style iOS googleAppID (SDK validates format). Same project + API key as web app.
        let options = FirebaseOptions(
            googleAppID: "1:1090690719538:ios:7b95426ad4f19cc1bec12b",
            gcmSenderID: "1090690719538"
        )
        options.apiKey = "AIzaSyBqcpdfO0mBWlP2L2Epo-Ik2iKU15I6s-E"
        options.projectID = "velocity-5e576"
        options.storageBucket = "velocity-5e576.firebasestorage.app"
        options.bundleID = Bundle.main.bundleIdentifier ?? "com.veloseete.app"

        FirebaseApp.configure(options: options)
        print("[Firebase] Configured programmatic fallback — project \(options.projectID ?? "?")")
    }
}
