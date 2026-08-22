import ActivityKit
import Foundation

@MainActor
final class TripLiveActivityController {
    static let shared = TripLiveActivityController()

    private var activity: Activity<TripActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        vehicleName: String,
        startedAt: Date,
        baselineL100: Double = 8.0
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] skipped — enable Live Activities in Settings → Veloseete")
            return
        }

        // A new recording owns a fresh activity. Remove anything stale first.
        for existing in Activity<TripActivityAttributes>.activities {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }

        let attributes = TripActivityAttributes(vehicleName: vehicleName, startedAt: startedAt)
        let state = TripActivityAttributes.ContentState(
            distanceKm: 0,
            durationSec: 0,
            currentSpeedKmh: 0,
            maxSpeedKmh: 0,
            isPaused: false,
            statusLabel: "Smooth",
            driveScore: 78,
            estL100: baselineL100,
            moodRaw: "smooth",
            lastEvent: TrackyVoice.Calm.readyWhenYouRoll,
            thirst: 0.22
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 8)),
                pushType: nil
            )
            print("[LiveActivity] started for \(vehicleName)")
        } catch {
            print("[LiveActivity] start failed: \(error)")
        }
    }

    func update(
        distanceKm: Double,
        durationSec: Double,
        currentSpeedKmh: Double,
        maxSpeedKmh: Double,
        isPaused: Bool,
        mood: DriveMoodLogic.Snapshot
    ) {
        guard let activity = activity ?? Activity<TripActivityAttributes>.activities.first else { return }
        self.activity = activity
        let state = TripActivityAttributes.ContentState(
            distanceKm: distanceKm,
            durationSec: durationSec,
            currentSpeedKmh: currentSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            isPaused: isPaused,
            statusLabel: mood.statusLabel,
            driveScore: mood.driveScore,
            estL100: mood.estL100,
            moodRaw: mood.moodRaw,
            lastEvent: mood.lastEvent,
            thirst: mood.thirst
        )
        Task {
            await activity.update(
                .init(state: state, staleDate: Date().addingTimeInterval(60 * 8))
            )
        }
    }

    func end(
        finalDistanceKm: Double,
        durationSec: Double,
        maxSpeedKmh: Double,
        mood: DriveMoodLogic.Snapshot
    ) {
        guard let activity = activity ?? Activity<TripActivityAttributes>.activities.first else { return }
        self.activity = activity
        let state = TripActivityAttributes.ContentState(
            distanceKm: finalDistanceKm,
            durationSec: durationSec,
            currentSpeedKmh: 0,
            maxSpeedKmh: maxSpeedKmh,
            isPaused: false,
            statusLabel: mood.statusLabel,
            driveScore: mood.driveScore,
            estL100: mood.estL100,
            moodRaw: mood.moodRaw,
            lastEvent: mood.lastEvent,
            thirst: mood.thirst
        )
        Task {
            // Hold the trip summary briefly — Apple Fitness style, not a flash.
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(50))
            )
        }
        self.activity = nil
    }

    func cancel() {
        let activities = Activity<TripActivityAttributes>.activities
        for activity in activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        self.activity = nil
    }
}
