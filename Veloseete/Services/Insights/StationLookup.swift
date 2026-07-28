import CoreLocation
import Foundation
import MapKit

/// One-shot location + MapKit search for nearby petrol / gas stations.
enum StationLookup {
    struct Station: Equatable, Identifiable, Hashable {
        var id: String { "\(name.lowercased())|\(latitude)|\(longitude)" }
        var name: String
        var latitude: Double
        var longitude: Double
        var distanceMeters: Double = 0
    }

    /// Auto-tag only when you're basically at the pump.
    static let autoSelectMaxMeters: CLLocationDistance = 280
    /// Still offer these in the picker.
    static let searchMaxMeters: CLLocationDistance = 2_500

    /// Nearest credible station within auto-select range, if any.
    static func nearestPetrolStation() async -> Station? {
        let all = await nearbyPetrolStations(limit: 8)
        return all.first { $0.distanceMeters <= autoSelectMaxMeters }
    }

    static func currentUserCoordinate() async -> CLLocationCoordinate2D? {
        await currentCoordinate()
    }

    static func nearbyPetrolStations(limit: Int = 8) async -> [Station] {
        await MainActor.run { } // ensure auth prompt can present from main
        guard let coordinate = await currentCoordinate() else { return [] }
        return await petrolStations(near: coordinate, limit: limit)
    }

    /// Free-text / brand search around a map center (or the user).
    static func searchPetrolStations(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        limit: Int = 20
    ) async -> [Station] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return await petrolStations(near: coordinate, limit: limit)
        }

        var seen = Set<String>()
        var ranked: [Station] = []
        let queries = [trimmed, "\(trimmed) petrol", "\(trimmed) fuel"]
        for q in queries {
            let found = await searchStations(query: q, near: coordinate, maxMeters: 12_000)
            for station in found {
                guard !seen.contains(station.id) else { continue }
                guard !isGenericStationName(station.name) else { continue }
                seen.insert(station.id)
                ranked.append(station)
            }
        }
        return ranked
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(limit)
            .map { $0 }
    }

    private static func petrolStations(
        near coordinate: CLLocationCoordinate2D,
        limit: Int
    ) async -> [Station] {
        var seen = Set<String>()
        var ranked: [Station] = []

        for query in ["petrol station", "gas station", "fuel", "WOQOD", "Shell", "Total"] {
            let found = await searchStations(query: query, near: coordinate)
            for station in found {
                let key = station.id
                guard !seen.contains(key) else { continue }
                guard !isGenericStationName(station.name) else { continue }
                seen.insert(key)
                ranked.append(station)
            }
        }

        return ranked
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(limit)
            .map { $0 }
    }

    private static func isGenericStationName(_ name: String) -> Bool {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let generics: Set<String> = [
            "petrol",
            "petrol station",
            "gas station",
            "fuel",
            "fuel station",
            "gas",
            "filling station",
            "service station",
        ]
        return generics.contains(normalized)
    }

    private static func currentCoordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let manager = CLLocationManager()
                switch manager.authorizationStatus {
                case .notDetermined:
                    manager.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    continuation.resume(returning: nil)
                    return
                default:
                    break
                }

                if let location = manager.location,
                   location.horizontalAccuracy >= 0,
                   location.horizontalAccuracy <= 250 {
                    continuation.resume(returning: location.coordinate)
                    return
                }

                let delegate = OneShotLocationDelegate { location in
                    continuation.resume(returning: location?.coordinate)
                }
                OneShotLocationDelegate.retain(delegate)
                delegate.manager.delegate = delegate
                delegate.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                delegate.manager.requestLocation()
            }
        }
    }

    private static func searchStations(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        maxMeters: CLLocationDistance = searchMaxMeters
    ) async -> [Station] {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: maxMeters * 1.2,
            longitudinalMeters: maxMeters * 1.2
        )

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item -> Station? in
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return nil }
                let loc = item.placemark.coordinate
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: loc.latitude, longitude: loc.longitude))
                guard distance <= maxMeters else { return nil }
                return Station(
                    name: name,
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    distanceMeters: distance
                )
            }
        } catch {
            print("[StationLookup] search failed for \(query): \(error.localizedDescription)")
            return []
        }
    }
}

private final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    private static var retained: [ObjectIdentifier: OneShotLocationDelegate] = [:]

    let manager = CLLocationManager()
    private let completion: (CLLocation?) -> Void
    private var finished = false

    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        super.init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finish(nil)
        }
    }

    static func retain(_ delegate: OneShotLocationDelegate) {
        retained[ObjectIdentifier(delegate)] = delegate
    }

    private func finish(_ location: CLLocation?) {
        guard !finished else { return }
        finished = true
        completion(location)
        Self.retained.removeValue(forKey: ObjectIdentifier(self))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[StationLookup] location failed: \(error.localizedDescription)")
        finish(nil)
    }
}
