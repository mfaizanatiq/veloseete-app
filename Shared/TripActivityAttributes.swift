import ActivityKit
import Foundation

/// Shared between the main app and the Live Activity widget extension.
public struct TripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var distanceKm: Double
        public var durationSec: Double
        public var currentSpeedKmh: Double
        public var maxSpeedKmh: Double
        public var isPaused: Bool
        public var statusLabel: String

        /// 0…100 drive quality score (higher = smoother / thriftier).
        public var driveScore: Int
        /// Live estimate of trip fuel use (L/100km).
        public var estL100: Double
        /// `smooth` | `watch` | `heavy` | `paused` | `saved`
        public var moodRaw: String
        /// Short glanceable cue, e.g. "Harsh accel".
        public var lastEvent: String
        /// 0…1 thirst / intensity for the efficiency track (0 = thrifty).
        public var thirst: Double

        public init(
            distanceKm: Double,
            durationSec: Double,
            currentSpeedKmh: Double,
            maxSpeedKmh: Double,
            isPaused: Bool,
            statusLabel: String,
            driveScore: Int = 78,
            estL100: Double = 8.0,
            moodRaw: String = "smooth",
            lastEvent: String = "",
            thirst: Double = 0.28
        ) {
            self.distanceKm = distanceKm
            self.durationSec = durationSec
            self.currentSpeedKmh = currentSpeedKmh
            self.maxSpeedKmh = maxSpeedKmh
            self.isPaused = isPaused
            self.statusLabel = statusLabel
            self.driveScore = driveScore
            self.estL100 = estL100
            self.moodRaw = moodRaw
            self.lastEvent = lastEvent
            self.thirst = thirst
        }

        public var mood: DriveMood {
            DriveMood(rawValue: moodRaw) ?? (isPaused ? .paused : .watch)
        }
    }

    public var vehicleName: String
    public var startedAt: Date

    public init(vehicleName: String, startedAt: Date) {
        self.vehicleName = vehicleName
        self.startedAt = startedAt
    }
}

public enum DriveMood: String, Codable, Hashable {
    case smooth
    case watch
    case heavy
    case paused
    case saved

    public var title: String {
        switch self {
        case .smooth: return "SMOOTH"
        case .watch: return "OK"
        case .heavy: return "HEAVY"
        case .paused: return "PAUSED"
        case .saved: return "SAVED"
        }
    }

    public var lockHeadline: String {
        switch self {
        case .smooth: return "Driving smooth"
        case .watch: return "Steady drive"
        case .heavy: return "Heavy foot"
        case .paused: return "Trip paused"
        case .saved: return "Trip saved"
        }
    }

    public var symbolName: String {
        switch self {
        case .smooth: return "leaf.fill"
        case .watch: return "car.fill"
        case .heavy: return "flame.fill"
        case .paused: return "pause.fill"
        case .saved: return "checkmark.circle.fill"
        }
    }
}
