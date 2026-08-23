import CoreLocation
import Foundation

enum TripTrackingLogic {
    /// Highway / background GPS often reports 30–60 m; 45 m was dropping real fixes.
    static func accepts(horizontalAccuracy: Double) -> Bool {
        horizontalAccuracy.isFinite && horizontalAccuracy >= 0 && horizontalAccuracy <= 65
    }

    /// Accepts real driving segments, including sparse highway updates.
    /// Rejects teleports (impossible speed) and absurd gaps.
    static func acceptedSegmentDistance(from previous: CLLocation, to current: CLLocation) -> Double {
        let distance = current.distance(from: previous)
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard distance > 2, elapsed > 0 else { return 0 }

        // ~200 km/h — anything faster is a GPS jump, not a car.
        let maxPlausibleSpeedMps = 55.0
        if distance / elapsed > maxPlausibleSpeedMps { return 0 }

        // Background delivery can pause briefly (tunnels, suspension). Keep a
        // generous gap so a 3–4 hour drive does not shed whole highway stretches.
        let maxGapMeters = 2_500.0
        let maxGapSeconds = 180.0
        guard distance <= maxGapMeters, elapsed <= maxGapSeconds else { return 0 }

        return distance
    }

    static func appending(_ point: TripCoordinate, to route: [TripCoordinate]) -> [TripCoordinate] {
        guard route.last != point else { return route }
        var updated = route
        updated.append(point)
        return updated
    }

    /// Uniform stride downsample — fine for UI after spacing-based thinning.
    static func downsample(_ points: [TripCoordinate], maximum: Int = 200) -> [TripCoordinate] {
        guard points.count > maximum, maximum >= 2 else { return points }
        let step = max(1, (points.count - 1) / (maximum - 1))
        var reduced: [TripCoordinate] = []
        reduced.reserveCapacity(maximum)
        var index = 0
        while index < points.count {
            reduced.append(points[index])
            index += step
        }
        if let last = points.last, reduced.last != last {
            reduced.append(last)
        }
        return reduced
    }

    /// Prefer keeping geometry: drop points closer than `minSpacingMeters`, then
    /// fall back to uniform downsample only if still over `maximum`.
    static func thinForPersistence(
        _ points: [TripCoordinate],
        minSpacingMeters: Double = 25,
        maximum: Int = 2_000
    ) -> [TripCoordinate] {
        guard points.count > 2 else { return points }
        var thinned: [TripCoordinate] = [points[0]]
        thinned.reserveCapacity(min(points.count, maximum))
        var lastKept = points[0]
        for point in points.dropFirst() {
            if approximateDistanceMeters(from: lastKept, to: point) >= minSpacingMeters {
                thinned.append(point)
                lastKept = point
            }
        }
        if let last = points.last, thinned.last != last {
            thinned.append(last)
        }
        return downsample(thinned, maximum: maximum)
    }

    /// Live recording buffer: keep shape under memory pressure without the old
    /// every-Nth crush to ~1.2k points that erased multi-hour highways.
    static func compactLiveRoute(
        _ points: [TripCoordinate],
        softCap: Int = 8_000,
        compactedMaximum: Int = 4_000
    ) -> [TripCoordinate] {
        guard points.count > softCap else { return points }
        return thinForPersistence(points, minSpacingMeters: 35, maximum: compactedMaximum)
    }

    /// Removes isolated GPS spikes from legacy routes for map presentation only.
    /// The stored route remains untouched.
    static func cleanedForDisplay(_ points: [TripCoordinate]) -> [TripCoordinate] {
        let valid = points.filter {
            (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
        }
        guard valid.count >= 3 else { return valid }

        var cleaned: [TripCoordinate] = [valid[0]]
        for index in 1..<(valid.count - 1) {
            let previous = cleaned.last!
            let current = valid[index]
            let next = valid[index + 1]
            let intoSpike = approximateDistanceMeters(from: previous, to: current)
            let outOfSpike = approximateDistanceMeters(from: current, to: next)
            let bypass = approximateDistanceMeters(from: previous, to: next)

            // A point far from both neighbours that returns close to the route is a GPS jump.
            let isIsolatedSpike = intoSpike > 600
                && outOfSpike > 600
                && bypass < min(1_200, (intoSpike + outOfSpike) * 0.35)
            if !isIsolatedSpike, current != previous {
                cleaned.append(current)
            }
        }
        if let last = valid.last, cleaned.last != last { cleaned.append(last) }
        return cleaned
    }

    /// Map-ready route: clean spikes, then downsample. Cached per trip id + point count
    /// so SwiftUI/MapKit body refreshes (drawer drag) don't re-walk thousands of points.
    static func mapDisplayRoute(
        id: String,
        points: [TripCoordinate],
        maximumPoints: Int = 220
    ) -> [TripCoordinate] {
        let key = "\(id)|\(points.count)|\(maximumPoints)"
        if let cached = displayCache.object(forKey: key as NSString) {
            return cached.points
        }
        let prepared = downsample(cleanedForDisplay(points), maximum: maximumPoints)
        displayCache.setObject(CachedRoute(points: prepared), forKey: key as NSString)
        return prepared
    }

    /// Equirectangular approximation — fast enough for spike detection / UI, no CLLocation alloc.
    static func approximateDistanceMeters(from lhs: TripCoordinate, to rhs: TripCoordinate) -> Double {
        let meanLat = (lhs.latitude + rhs.latitude) * 0.5 * .pi / 180
        let dLat = (rhs.latitude - lhs.latitude) * 111_320
        let dLng = (rhs.longitude - lhs.longitude) * 111_320 * cos(meanLat)
        return (dLat * dLat + dLng * dLng).squareRoot()
    }

    private static let displayCache = NSCache<NSString, CachedRoute>()

    private final class CachedRoute: NSObject {
        let points: [TripCoordinate]
        init(points: [TripCoordinate]) { self.points = points }
    }
}

enum OdometerReconciliation {
    static func estimated(verifiedKm: Double, trackedKm: Double) -> Double {
        verifiedKm + max(0, trackedKm)
    }

    static func variance(enteredKm: Double, verifiedKm: Double, trackedKm: Double) -> Double {
        enteredKm - estimated(verifiedKm: verifiedKm, trackedKm: trackedKm)
    }
}

/// Pure finish/save math — keeps TripRecordingService from crashing on bad times/distances.
enum TripFinishLogic {
    static let minSaveDistanceKm = 0.25

    static func durationSec(
        startedAt: Date,
        endedAt: Date,
        pausedAccumulated: TimeInterval,
        pauseStartedAt: Date?,
        isPaused: Bool
    ) -> TimeInterval {
        var duration = endedAt.timeIntervalSince(startedAt) - pausedAccumulated
        if let pauseStartedAt, isPaused {
            duration -= endedAt.timeIntervalSince(pauseStartedAt)
        }
        // Guard inverted clocks / clock skew — never negative or NaN.
        guard duration.isFinite else { return 0 }
        return max(duration, 0)
    }

    static func averageSpeedKmh(distanceKm: Double, durationSec: TimeInterval) -> Double {
        guard distanceKm.isFinite, durationSec.isFinite, durationSec > 0, distanceKm >= 0 else {
            return 0
        }
        return distanceKm / (durationSec / 3600)
    }

    static func shouldPersist(distanceKm: Double, minimumKm: Double = minSaveDistanceKm) -> Bool {
        guard distanceKm.isFinite else { return false }
        return distanceKm >= minimumKm
    }
}

/// Pure rules for auto-start — walking must not look like a drive.
enum TripAutoStartLogic {
    /// Automotive / hard-speed must hold this long before recording begins.
    static let holdSeconds: TimeInterval = 18
    /// Soft GPS gate (jogging range) — needs motion automotive corroboration.
    static let softDrivingSpeedKmh = 12.0
    /// Hard GPS gate — clearly a vehicle even without motion (above typical jogging).
    static let hardDrivingSpeedKmh = 22.0
    /// After walking/running, ignore automotive / soft-speed starts for this long.
    static let pedestrianBlockSeconds: TimeInterval = 60

    static func isPedestrianBlocked(lastPedestrianAt: Date?, now: Date = Date()) -> Bool {
        guard let lastPedestrianAt else { return false }
        return now.timeIntervalSince(lastPedestrianAt) < pedestrianBlockSeconds
    }

    /// Motion may advance the hold clock only with usable confidence and no recent walk/run.
    static func motionAdvancesHold(
        isAutomotive: Bool,
        confidenceOK: Bool,
        pedestrianBlocked: Bool
    ) -> Bool {
        isAutomotive && confidenceOK && !pedestrianBlocked
    }

    /// GPS may advance the hold clock: hard speed alone, or soft speed + automotive motion.
    static func gpsAdvancesHold(
        speedKmh: Double,
        automotiveCorroborated: Bool,
        pedestrianBlocked: Bool
    ) -> Bool {
        guard speedKmh.isFinite, !pedestrianBlocked else { return false }
        if speedKmh >= hardDrivingSpeedKmh { return true }
        if speedKmh >= softDrivingSpeedKmh, automotiveCorroborated { return true }
        return false
    }

    static func shouldStart(heldFor: TimeInterval?) -> Bool {
        guard let heldFor, heldFor.isFinite else { return false }
        return heldFor >= holdSeconds
    }

    /// Simulates the watching hold clock for tests / invariants.
    struct HoldClock: Equatable {
        var automotiveSince: Date?
        var automotiveCorroborated = false
        var lastPedestrianAt: Date?

        mutating func onPedestrian(at now: Date, confidenceOK: Bool) {
            if confidenceOK { lastPedestrianAt = now }
            automotiveSince = nil
            automotiveCorroborated = false
        }

        mutating func onAutomotive(at now: Date, confidenceOK: Bool) -> Bool {
            let blocked = TripAutoStartLogic.isPedestrianBlocked(lastPedestrianAt: lastPedestrianAt, now: now)
            guard TripAutoStartLogic.motionAdvancesHold(
                isAutomotive: true,
                confidenceOK: confidenceOK,
                pedestrianBlocked: blocked
            ) else {
                if blocked {
                    automotiveSince = nil
                    automotiveCorroborated = false
                }
                return false
            }
            if automotiveSince == nil { automotiveSince = now }
            automotiveCorroborated = true
            let held = automotiveSince.map { now.timeIntervalSince($0) }
            return TripAutoStartLogic.shouldStart(heldFor: held)
        }

        mutating func onGPS(speedKmh: Double, at now: Date) -> Bool {
            let blocked = TripAutoStartLogic.isPedestrianBlocked(lastPedestrianAt: lastPedestrianAt, now: now)
            if TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: speedKmh,
                automotiveCorroborated: automotiveCorroborated,
                pedestrianBlocked: blocked
            ) {
                if automotiveSince == nil { automotiveSince = now }
                let held = automotiveSince.map { now.timeIntervalSince($0) }
                return TripAutoStartLogic.shouldStart(heldFor: held)
            }
            if speedKmh < 3 || !automotiveCorroborated || blocked {
                automotiveSince = nil
            }
            return false
        }
    }
}
