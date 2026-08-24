import CoreLocation
import Foundation

enum TripTrackingLogic {
    /// How a consecutive GPS pair should be applied to the live route buffer.
    enum SegmentDecision: Equatable {
        /// Too close / duplicate — ignore.
        case noise
        /// Impossible jump — ignore and keep the prior anchor.
        case teleport
        /// Continuous drive — accumulate `meters`.
        case accept(meters: Double)
        /// Tunnel / background gap — resume geometry without inflating distance.
        case resumeAfterGap
    }

    /// Mountain / canopy GPS often reports 70–100 m; 65 m was dropping real stretches.
    static func accepts(horizontalAccuracy: Double) -> Bool {
        horizontalAccuracy.isFinite && horizontalAccuracy >= 0 && horizontalAccuracy <= 100
    }

    /// Accepts real driving segments, including sparse highway updates.
    /// Rejects teleports (impossible speed). Large time/distance gaps resume
    /// rather than permanently freezing the route anchor.
    static func acceptedSegmentDistance(from previous: CLLocation, to current: CLLocation) -> Double {
        switch evaluateSegment(from: previous, to: current) {
        case .accept(let meters): return meters
        case .noise, .teleport, .resumeAfterGap: return 0
        }
    }

    static func evaluateSegment(from previous: CLLocation, to current: CLLocation) -> SegmentDecision {
        let distance = current.distance(from: previous)
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard distance > 2, elapsed > 0 else { return .noise }

        // ~200 km/h — anything faster is a GPS jump, not a car.
        let maxPlausibleSpeedMps = 55.0
        if distance / elapsed > maxPlausibleSpeedMps { return .teleport }

        // Background delivery can pause (tunnels, suspension). Beyond this we
        // still keep the new fix so the route continues — we just don't credit
        // the chord as driven distance.
        let maxGapMeters = 3_500.0
        let maxGapSeconds = 420.0
        if distance > maxGapMeters || elapsed > maxGapSeconds {
            return .resumeAfterGap
        }

        return .accept(meters: distance)
    }

    static func appending(_ point: TripCoordinate, to route: [TripCoordinate]) -> [TripCoordinate] {
        guard route.last != point else { return route }
        var updated = route
        updated.append(point)
        return updated
    }

    /// Uniform stride downsample — last-resort budget crush only.
    /// Prefer `simplify` / `simplifyToBudget` so twisty geometry survives.
    static func downsample(_ points: [TripCoordinate], maximum: Int = 200) -> [TripCoordinate] {
        guard points.count > maximum, maximum >= 2 else { return points }
        var reduced: [TripCoordinate] = []
        reduced.reserveCapacity(maximum)
        let lastIndex = points.count - 1
        for slot in 0..<maximum {
            let index = slot == maximum - 1
                ? lastIndex
                : Int((Double(slot) * Double(lastIndex) / Double(maximum - 1)).rounded())
            let point = points[index]
            if reduced.last != point {
                reduced.append(point)
            }
        }
        if let last = points.last, reduced.last != last {
            reduced.append(last)
        }
        if reduced.count > maximum, let last = points.last {
            reduced = Array(reduced.prefix(maximum - 1)) + [last]
        }
        return reduced
    }

    /// Ramer–Douglas–Peucker — keeps corners / hairpins, drops collinear highway points.
    static func simplify(_ points: [TripCoordinate], epsilonMeters: Double) -> [TripCoordinate] {
        guard points.count > 2, epsilonMeters > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        rdpMark(points, start: 0, end: points.count - 1, epsilonMeters: epsilonMeters, keep: &keep)
        var out: [TripCoordinate] = []
        out.reserveCapacity(keep.filter { $0 }.count)
        for index in points.indices where keep[index] {
            out.append(points[index])
        }
        return out
    }

    /// Simplify at a fixed epsilon, then stride only if still over `maximum`.
    /// Do not grow epsilon — that flattens switchbacks before the budget is hit.
    static func simplifyToBudget(
        _ points: [TripCoordinate],
        maximum: Int,
        startingEpsilonMeters: Double = 8
    ) -> [TripCoordinate] {
        guard points.count > maximum, maximum >= 2 else { return points }
        let simplified = simplify(points, epsilonMeters: max(1, startingEpsilonMeters))
        if simplified.count > maximum {
            return downsample(simplified, maximum: maximum)
        }
        return simplified
    }

    /// Prefer geometry: light spacing thin, then RDP (not uniform stride).
    static func thinForPersistence(
        _ points: [TripCoordinate],
        minSpacingMeters: Double = 12,
        maximum: Int = 5_000,
        epsilonMeters: Double = 8
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
        return simplifyToBudget(thinned, maximum: maximum, startingEpsilonMeters: epsilonMeters)
    }

    /// Live recording buffer: keep twisty shape under memory pressure.
    static func compactLiveRoute(
        _ points: [TripCoordinate],
        softCap: Int = 12_000,
        compactedMaximum: Int = 6_000
    ) -> [TripCoordinate] {
        guard points.count > softCap else { return points }
        return thinForPersistence(
            points,
            minSpacingMeters: 16,
            maximum: compactedMaximum,
            epsilonMeters: 10
        )
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

    /// Map-ready route: clean spikes, then RDP to budget (keeps hairpins).
    /// Cached per trip id + point count so MapKit body refreshes stay cheap.
    static func mapDisplayRoute(
        id: String,
        points: [TripCoordinate],
        maximumPoints: Int = 600
    ) -> [TripCoordinate] {
        let key = "\(id)|\(points.count)|\(maximumPoints)"
        if let cached = displayCache.object(forKey: key as NSString) {
            return cached.points
        }
        let prepared = simplifyToBudget(
            cleanedForDisplay(points),
            maximum: maximumPoints,
            startingEpsilonMeters: maximumPoints <= 80 ? 28 : 12
        )
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

    /// Perpendicular distance from `point` to the segment `start`→`end` (meters).
    static func perpendicularDistanceMeters(
        point: TripCoordinate,
        start: TripCoordinate,
        end: TripCoordinate
    ) -> Double {
        let meanLat = (start.latitude + end.latitude) * 0.5 * .pi / 180
        let cosLat = cos(meanLat)
        let ax = start.longitude * 111_320 * cosLat
        let ay = start.latitude * 111_320
        let bx = end.longitude * 111_320 * cosLat
        let by = end.latitude * 111_320
        let px = point.longitude * 111_320 * cosLat
        let py = point.latitude * 111_320
        let dx = bx - ax
        let dy = by - ay
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 1e-6 else {
            return approximateDistanceMeters(from: start, to: point)
        }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSq))
        let projX = ax + t * dx
        let projY = ay + t * dy
        let ex = px - projX
        let ey = py - projY
        return (ex * ex + ey * ey).squareRoot()
    }

    private static func rdpMark(
        _ points: [TripCoordinate],
        start: Int,
        end: Int,
        epsilonMeters: Double,
        keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }
        var maxDistance = 0.0
        var maxIndex = start
        let lineStart = points[start]
        let lineEnd = points[end]
        for index in (start + 1)..<end {
            let distance = perpendicularDistanceMeters(
                point: points[index],
                start: lineStart,
                end: lineEnd
            )
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = index
            }
        }
        guard maxDistance > epsilonMeters else { return }
        keep[maxIndex] = true
        rdpMark(points, start: start, end: maxIndex, epsilonMeters: epsilonMeters, keep: &keep)
        rdpMark(points, start: maxIndex, end: end, epsilonMeters: epsilonMeters, keep: &keep)
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
