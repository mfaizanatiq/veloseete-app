import ActivityKit
import Foundation

@MainActor
final class TripLiveActivityController {
    static let shared = TripLiveActivityController()

    private var activity: Activity<TripActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(vehicleName: String, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = TripActivityAttributes(vehicleName: vehicleName, startedAt: startedAt)
        let state = TripActivityAttributes.ContentState(
            distanceKm: 0,
            durationSec: 0,
            currentSpeedKmh: 0,
            maxSpeedKmh: 0,
            isPaused: false,
            statusLabel: "Recording"
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] start failed: \(error)")
        }
    }

    func update(
        distanceKm: Double,
        durationSec: Double,
        currentSpeedKmh: Double,
        maxSpeedKmh: Double,
        isPaused: Bool
    ) {
        guard let activity else { return }
        let state = TripActivityAttributes.ContentState(
            distanceKm: distanceKm,
            durationSec: durationSec,
            currentSpeedKmh: currentSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            isPaused: isPaused,
            statusLabel: isPaused ? "Paused" : "Recording"
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func end(finalDistanceKm: Double, durationSec: Double, maxSpeedKmh: Double) {
        guard let activity else { return }
        let state = TripActivityAttributes.ContentState(
            distanceKm: finalDistanceKm,
            durationSec: durationSec,
            currentSpeedKmh: 0,
            maxSpeedKmh: maxSpeedKmh,
            isPaused: false,
            statusLabel: "Saved"
        )
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 8))
        }
        self.activity = nil
    }

    func cancel() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
