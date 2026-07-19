import CoreLocation
import Foundation

enum TripTrackingLogic {
    static func accepts(horizontalAccuracy: Double) -> Bool {
        horizontalAccuracy >= 0 && horizontalAccuracy <= 45
    }

    static func acceptedSegmentDistance(from previous: CLLocation, to current: CLLocation) -> Double {
        let distance = current.distance(from: previous)
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard distance > 2, distance < 200, elapsed > 0, elapsed < 30 else { return 0 }
        return distance
    }

    static func appending(_ point: TripCoordinate, to route: [TripCoordinate]) -> [TripCoordinate] {
        guard route.last != point else { return route }
        var updated = route
        updated.append(point)
        return updated
    }

    static func downsample(_ points: [TripCoordinate], maximum: Int = 200) -> [TripCoordinate] {
        guard points.count > maximum else { return points }
        let step = max(1, points.count / (maximum - 20))
        var reduced = points.enumerated().compactMap { index, point in
            index % step == 0 ? point : nil
        }
        if let last = points.last, reduced.last != last { reduced.append(last) }
        return reduced
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
            let intoSpike = distance(from: previous, to: current)
            let outOfSpike = distance(from: current, to: next)
            let bypass = distance(from: previous, to: next)

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

    private static func distance(from lhs: TripCoordinate, to rhs: TripCoordinate) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
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
