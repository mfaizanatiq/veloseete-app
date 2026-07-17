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

        public init(
            distanceKm: Double,
            durationSec: Double,
            currentSpeedKmh: Double,
            maxSpeedKmh: Double,
            isPaused: Bool,
            statusLabel: String
        ) {
            self.distanceKm = distanceKm
            self.durationSec = durationSec
            self.currentSpeedKmh = currentSpeedKmh
            self.maxSpeedKmh = maxSpeedKmh
            self.isPaused = isPaused
            self.statusLabel = statusLabel
        }
    }

    public var vehicleName: String
    public var startedAt: Date

    public init(vehicleName: String, startedAt: Date) {
        self.vehicleName = vehicleName
        self.startedAt = startedAt
    }
}
