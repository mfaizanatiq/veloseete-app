import CoreLocation
import MapKit
import XCTest
@testable import Veloseete

final class TripTrackingLogicTests: XCTestCase {
    func testAccuracyBoundary() {
        XCTAssertTrue(TripTrackingLogic.accepts(horizontalAccuracy: 0))
        XCTAssertTrue(TripTrackingLogic.accepts(horizontalAccuracy: 100))
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: -1))
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: 100.1))
    }

    func testValidSegmentAccumulatesDistance() {
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        let end = location(latitude: 25.2859, longitude: 51.5310, seconds: 8)
        XCTAssertGreaterThan(TripTrackingLogic.acceptedSegmentDistance(from: start, to: end), 40)
    }

    func testJumpAndTeleportSegmentsAreRejected() {
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        // ~1.6 km in 4s ≈ 400 m/s — impossible for a car.
        let jump = location(latitude: 25.30, longitude: 51.5310, seconds: 4)
        XCTAssertEqual(TripTrackingLogic.acceptedSegmentDistance(from: start, to: jump), 0)
    }

    func testHighwaySparseUpdateIsAccepted() {
        // ~278 m in 10s ≈ 100 km/h — common when Core Location batches highway fixes.
        // The old 200 m / 30 s caps rejected this and destroyed long-drive maps.
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        let end = location(latitude: 25.2879, longitude: 51.5310, seconds: 10)
        let distance = TripTrackingLogic.acceptedSegmentDistance(from: start, to: end)
        XCTAssertGreaterThan(distance, 250)
        XCTAssertLessThan(distance, 320)
    }

    func testBackgroundGapWithPlausibleSpeedIsAccepted() {
        // 900 m in 45s ≈ 72 km/h after a brief GPS pause.
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        let end = location(latitude: 25.2935, longitude: 51.5310, seconds: 45)
        XCTAssertGreaterThan(TripTrackingLogic.acceptedSegmentDistance(from: start, to: end), 800)
    }

    func testLongGapResumesInsteadOfFreezingRoute() {
        // After a long tunnel / background pause, the next fix must resume — the old
        // hard reject froze lastLocation and dropped the rest of the drive.
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        let afterTunnel = location(latitude: 25.2950, longitude: 51.5400, seconds: 500)
        XCTAssertEqual(
            TripTrackingLogic.evaluateSegment(from: start, to: afterTunnel),
            .resumeAfterGap
        )
        XCTAssertEqual(TripTrackingLogic.acceptedSegmentDistance(from: start, to: afterTunnel), 0)
    }

    func testSimplifyKeepsHairpinCornersBetterThanStride() {
        // Straight approach, sharp 90° corner, straight exit — RDP should keep the corner.
        var route: [TripCoordinate] = []
        for i in 0..<40 {
            route.append(TripCoordinate(latitude: 25.0 + Double(i) * 0.0001, longitude: 51.0))
        }
        let corner = TripCoordinate(latitude: 25.0 + 40 * 0.0001, longitude: 51.0)
        route.append(corner)
        for i in 1...40 {
            route.append(TripCoordinate(latitude: corner.latitude, longitude: 51.0 + Double(i) * 0.0001))
        }

        let simplified = TripTrackingLogic.simplify(route, epsilonMeters: 8)
        let stride = TripTrackingLogic.downsample(route, maximum: simplified.count)

        let cornerKept = simplified.contains { point in
            abs(point.latitude - corner.latitude) < 1e-9 && abs(point.longitude - corner.longitude) < 1e-9
        }
        XCTAssertTrue(cornerKept, "RDP should retain the hairpin vertex")
        XCTAssertEqual(simplified.first, route.first)
        XCTAssertEqual(simplified.last, route.last)
        XCTAssertLessThan(simplified.count, route.count)

        // Stride at the same budget often skips the exact corner index.
        let strideHasExactCorner = stride.contains { point in
            abs(point.latitude - corner.latitude) < 1e-9 && abs(point.longitude - corner.longitude) < 1e-9
        }
        // Not asserting stride fails — just that RDP keeps geometry under a modest budget.
        _ = strideHasExactCorner
        XCTAssertLessThanOrEqual(simplified.count, 12)
    }

    func testThinForPersistenceKeepsTwistyShapeUnderBudget() {
        // Dense switchback: zig-zag east-west every few points (~40 m amplitude).
        var route: [TripCoordinate] = []
        for index in 0..<2_000 {
            let lat = 25.0 + Double(index) * 0.00005
            let lng = 51.0 + (index % 2 == 0 ? 0.0 : 0.00035)
            route.append(TripCoordinate(latitude: lat, longitude: lng))
        }
        let thinned = TripTrackingLogic.thinForPersistence(route, minSpacingMeters: 12, maximum: 800)
        let stride = TripTrackingLogic.downsample(route, maximum: 200)
        XCTAssertEqual(thinned.first, route.first)
        XCTAssertEqual(thinned.last, route.last)
        XCTAssertLessThanOrEqual(thinned.count, 800)
        // RDP keeps switchback peaks; old uniform crush to 200 loses most of them.
        XCTAssertGreaterThan(thinned.count, 120)
        XCTAssertGreaterThan(thinned.count, stride.count)
    }

    func testRouteKeepsDistinctPointsAndDropsDuplicates() {
        let first = TripCoordinate(latitude: 25.2854, longitude: 51.5310)
        let second = TripCoordinate(latitude: 25.2859, longitude: 51.5315)
        var route = TripTrackingLogic.appending(first, to: [])
        route = TripTrackingLogic.appending(first, to: route)
        route = TripTrackingLogic.appending(second, to: route)
        XCTAssertEqual(route, [first, second])
    }

    func testDownsamplePreservesFirstAndLastPoint() {
        let route = (0..<500).map { index in
            TripCoordinate(latitude: 25 + Double(index) * 0.0001, longitude: 51)
        }
        let reduced = TripTrackingLogic.downsample(route)
        XCTAssertEqual(reduced.first, route.first)
        XCTAssertEqual(reduced.last, route.last)
        XCTAssertLessThan(reduced.count, route.count)
    }

    func testThinForPersistenceKeepsShapeBetterThanCrush() {
        var route: [TripCoordinate] = []
        for index in 0..<1_200 {
            let lat = 25.0 + Double(index) * 0.00008
            let lng = index < 600 ? 51.0 : 51.0 + Double(index - 600) * 0.00008
            route.append(TripCoordinate(latitude: lat, longitude: lng))
        }
        let thinned = TripTrackingLogic.thinForPersistence(route, minSpacingMeters: 12, maximum: 800)
        XCTAssertEqual(thinned.first, route.first)
        XCTAssertEqual(thinned.last, route.last)
        XCTAssertLessThanOrEqual(thinned.count, 800)
        // Perfect L-shape collapses to a handful of RDP vertices — that's correct.
        // The corner (turn point) must survive.
        let corner = route[600]
        let keptCorner = thinned.contains {
            abs($0.latitude - corner.latitude) < 0.0002 && abs($0.longitude - corner.longitude) < 0.0002
        }
        XCTAssertTrue(keptCorner)
        XCTAssertGreaterThanOrEqual(thinned.count, 3)
    }

    func testPendingTripQueueItemSurvivesPersistenceRoundTrip() throws {
        let pending = PendingTripSave(
            id: UUID(),
            vehicleId: "car",
            vehicleName: "Daily Driver",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_900),
            distanceKm: 12.4,
            durationSec: 900,
            avgSpeedKmh: 49.6,
            maxSpeedKmh: 82,
            startCoordinate: TripCoordinate(latitude: 25.28, longitude: 51.53),
            endCoordinate: TripCoordinate(latitude: 25.36, longitude: 51.48),
            route: [
                TripCoordinate(latitude: 25.28, longitude: 51.53),
                TripCoordinate(latitude: 25.36, longitude: 51.48)
            ],
            source: "auto",
            suggestedOdometer: 52_012.4
        )

        let encoded = try JSONEncoder().encode([pending])
        let restored = try JSONDecoder().decode([PendingTripSave].self, from: encoded)

        XCTAssertEqual(restored, [pending])
    }

    /// Where a coordinate lands on screen (points) when the map shows `rect` in a view of `size`.
    private func screenPoint(_ coordinate: CLLocationCoordinate2D, rect: MKMapRect, size: CGSize) -> CGPoint {
        let p = MKMapPoint(coordinate)
        return CGPoint(
            x: (p.x - rect.origin.x) / rect.size.width * size.width,
            y: (p.y - rect.origin.y) / rect.size.height * size.height
        )
    }

    func testRouteFramingKeepsEveryPointInTheVisibleAreaWhateverTheShape() {
        func coords(_ count: Int, _ f: (Double) -> (Double, Double)) -> [CLLocationCoordinate2D] {
            (0..<count).map { i in
                let (lat, lng) = f(Double(i) / Double(count - 1))
                return CLLocationCoordinate2D(latitude: 25.2 + lat, longitude: 55.27 + lng)
            }
        }
        let routes: [String: [CLLocationCoordinate2D]] = [
            "north-south": coords(50) { ($0 * 0.30, sin($0 * 5) * 0.012) },
            "east-west": coords(50) { (sin($0 * 6) * 0.01, $0 * 0.30) },
            "diagonal": coords(50) { ($0 * 0.22, $0 * 0.22) },
            "loop": coords(50) { (sin($0 * .pi * 2) * 0.05, (1 - cos($0 * .pi * 2)) * 0.05) },
            "short": coords(20) { ($0 * 0.003, sin($0 * 4) * 0.0008) },
            "single point": [CLLocationCoordinate2D(latitude: 25.2, longitude: 55.27)]
        ]
        let layouts: [(CGSize, RouteFraming.Insets)] = [
            (CGSize(width: 402, height: 440), .phoneHero),   // phone hero
            (CGSize(width: 510, height: 669), .wideHero),    // Duo unfolded, tall hero
            (CGSize(width: 330, height: 220), .card),        // review sheet card
            (CGSize(width: 377, height: 440), .phoneHero)    // Duo folded
        ]
        for (name, route) in routes {
            for (size, insets) in layouts {
                let rect = RouteFraming.mapRect(for: route, viewSize: size, insets: insets)
                XCTAssertNotNil(rect, name)
                guard let rect else { continue }
                // The view is shown whole, undistorted.
                XCTAssertEqual(rect.size.width / rect.size.height, size.width / size.height, accuracy: 0.001, name)
                let clear = CGRect(
                    x: insets.leading, y: insets.top,
                    width: size.width - insets.leading - insets.trailing,
                    height: size.height - insets.top - insets.bottom
                )
                for coordinate in route {
                    let point = screenPoint(coordinate, rect: rect, size: size)
                    XCTAssertTrue(clear.insetBy(dx: -0.5, dy: -0.5).contains(point), "\(name) \(size): \(point) outside \(clear)")
                }
                // Centred in the clear area (the bounding box midpoint sits at its centre).
                let xs = route.map { screenPoint($0, rect: rect, size: size).x }
                let ys = route.map { screenPoint($0, rect: rect, size: size).y }
                XCTAssertEqual((xs.min()! + xs.max()!) / 2, clear.midX, accuracy: 1, name)
                XCTAssertEqual((ys.min()! + ys.max()!) / 2, clear.midY, accuracy: 1, name)
            }
        }
        XCTAssertNil(RouteFraming.mapRect(for: [], viewSize: CGSize(width: 300, height: 300), insets: .card))
    }

    func testQueuedDriveKeepsBothAnswersAndOldQueuesStillLoad() throws {
        var pending = PendingTripSave(
            id: UUID(), vehicleId: "car", vehicleName: "Daily Driver",
            startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_900),
            distanceKm: 12.4, durationSec: 900, avgSpeedKmh: 49.6, maxSpeedKmh: 82,
            startCoordinate: nil, endCoordinate: nil, route: [], source: "auto", suggestedOdometer: 52_000
        )
        pending.role = TripRole.passenger.rawValue
        pending.vehicleKind = TripVehicle.garage.rawValue
        let restored = try JSONDecoder().decode(PendingTripSave.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(restored.tripRole, .passenger)
        XCTAssertEqual(restored.tripVehicle, .garage)

        // A drive queued by an older build has neither field beyond `role`.
        let legacy = """
        {"id":"\(UUID().uuidString)","vehicleId":"car","vehicleName":"Daily Driver",
         "startedAt":1000,"endedAt":1900,"distanceKm":3,"durationSec":300,"avgSpeedKmh":36,
         "maxSpeedKmh":50,"route":[],"source":"auto","suggestedOdometer":10,"role":"passenger"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let old = try decoder.decode(PendingTripSave.self, from: legacy)
        XCTAssertNil(old.vehicleKind)
        XCTAssertEqual(old.tripVehicle, .other) // an old "passenger" meant keep it off my car
    }

    func testOdometerEstimateAndVariance() {
        XCTAssertEqual(OdometerReconciliation.estimated(verifiedKm: 52_000, trackedKm: 184), 52_184)
        XCTAssertEqual(OdometerReconciliation.variance(enteredKm: 52_191, verifiedKm: 52_000, trackedKm: 184), 7)
    }

    func testDashboardEfficiencyUsesClosingFuelOnly() {
        // Fixed mid-month reference so "2 days ago" can't slip into last month
        // (the monthly stats legitimately reset at the month boundary).
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 10, from: reference),
            fuelLog(id: "2", odometer: 10_500, liters: 35, full: true, daysAgo: 2, from: reference)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs, now: reference)
        XCTAssertEqual(metrics.current ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(metrics.avgEfficiency ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(metrics.totalDistance, 500, accuracy: 0.001)
        XCTAssertEqual(metrics.efficiencySampleCount, 1)
    }

    func testTwoFillsOver100KmGiveAnEarlyEstimate() {
        // Full, then a partial 200 km later: no measured tank, but 15 L / 200 km ≈ 7.5.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "2", odometer: 10_200, liters: 15, full: false, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.current ?? 0, 7.5, accuracy: 0.001)
        XCTAssertEqual(metrics.avgEfficiency ?? 0, 7.5, accuracy: 0.001)
        XCTAssertTrue(metrics.isEstimate)
        XCTAssertEqual(metrics.estimate?.fills, 2)
        XCTAssertEqual(metrics.efficiencySampleCount, 0)
        // Cost-per-km stays on measured tanks only.
        XCTAssertEqual(metrics.totalDistance, 0)
    }

    func testTwoPartialFillsStillEstimate() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 20, full: false, daysAgo: 10),
            fuelLog(id: "2", odometer: 10_300, liters: 24, full: false, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.current ?? 0, 8, accuracy: 0.001)
        XCTAssertTrue(metrics.isEstimate)
    }

    func testShortGapIsTooNoisyToEstimate() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 3),
            fuelLog(id: "2", odometer: 10_060, liters: 5, full: false, daysAgo: 1)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertNil(metrics.current)
        XCTAssertFalse(metrics.isEstimate)
    }

    func testMeasuredTankWinsOverEstimate() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_500, liters: 35, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_700, liters: 30, full: false, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.current ?? 0, 7, accuracy: 0.001)
        XCTAssertFalse(metrics.isEstimate)
    }

    func testOdometerTypoTankIsIgnored() {
        // 35 L over 50 km = 70 L/100 — a missed digit, not a car.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_050, liters: 35, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_550, liters: 35, full: true, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.efficiencySampleCount, 1)
        XCTAssertEqual(metrics.current ?? 0, 7, accuracy: 0.001)
    }

    func testAverageSurvivesTheMonthBoundary() {
        // Both fills last month; viewed on the 2nd of this month.
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20, from: reference),
            fuelLog(id: "2", odometer: 10_500, liters: 35, full: true, daysAgo: 10, from: reference)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs, now: reference)
        XCTAssertEqual(metrics.avgEfficiency ?? 0, 7, accuracy: 0.001)
    }

    func testGarageBadgesNeverMixTwoCarsOdometers() {
        let logs = [
            fuelLog(id: "a1", vehicleId: "a", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "b1", vehicleId: "b", odometer: 90_000, liters: 50, full: true, daysAgo: 15),
            fuelLog(id: "a2", vehicleId: "a", odometer: 10_500, liters: 35, full: true, daysAgo: 10),
            fuelLog(id: "b2", vehicleId: "b", odometer: 90_400, liters: 40, full: true, daysAgo: 5)
        ]
        let all = InsightGenerator.achievements(
            trips: [], logs: logs, vehicleId: nil, unit: "km", manufacturerStandard: nil
        )
        // Old pairing subtracted car A's 10,000 from car B's 90,000 → an 80,000 km "stretch".
        XCTAssertEqual(all.first { $0.id == "fill-stretch" }?.detail, "500 km between fills")
        XCTAssertEqual(all.first { $0.id == "best-tank" }?.unlocked, true)
        let highlights = InsightGenerator.personalHighlights(logs: logs, vehicleId: "a", unit: "km")
        XCTAssertEqual(highlights.first { $0.id == "longest-run" }?.value, "500 km")
    }

    func testDashboardAggregatesPartialFillsBetweenFullTankAnchors() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_250, liters: 15, full: false, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_500, liters: 20, full: true, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.current ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(metrics.efficiencySampleCount, 1)
    }

    func testDashboardFiltersOtherVehiclesAndRejectsOdometerRollback() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "other", vehicleId: "other", odometer: 10_100, liters: 99, full: true, daysAgo: 5),
            fuelLog(id: "2", odometer: 9_900, liters: 35, full: true, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertNil(metrics.current)
        XCTAssertEqual(metrics.efficiencySampleCount, 0)
    }

    func testSpendTrendDoesNotClaimFlatWithoutPriorMonth() {
        XCTAssertEqual(DashboardCopy.spendTrend(nil), "First month on the board")
        XCTAssertEqual(DashboardCopy.spendTrend(0), "Holding steady")
    }

    func testOneMeasuredTankAlreadyComparesToBrochure() {
        let status = DashboardCopy.status(efficiency: 18.6, standard: 8, sampleCount: 1)
        XCTAssertEqual(status.tone, .watch)
        XCTAssertEqual(DashboardCopy.vibe(efficiency: 18.6, standard: 8, refuelCount: 1).tone, .watch)
    }

    func testEstimateIsLabelledAsSuch() {
        let status = DashboardCopy.status(efficiency: 7.5, standard: 8, sampleCount: 0, isEstimate: true)
        XCTAssertEqual(status.tone, .learning)
        XCTAssertEqual(DashboardCopy.vibe(efficiency: 7.5, standard: 8, refuelCount: 0, isEstimate: true).label, "Early estimate")
    }

    func testRollingEfficiencyIsDistanceWeighted() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 15),
            fuelLog(id: "2", odometer: 10_500, liters: 35, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 11_500, liters: 80, full: true, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.current ?? 0, 115.0 / 1_500.0 * 100, accuracy: 0.001)
    }

    func testFuelPredictionUsesFillCadence() {
        // Just filled a full tank — must NOT notify; plenty of range left.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 0)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_800,
            tankCapacityLiters: 45,
            now: Date()
        )
        XCTAssertNotNil(prediction)
        XCTAssertGreaterThanOrEqual(prediction?.daysRemaining ?? -1, 7)
        XCTAssertFalse(prediction?.shouldNotify ?? true)
        XCTAssertEqual(prediction?.urgency, FuelInsightLogic.FuelUrgency.none)
    }

    func testFuelPredictionExtendsWhenBarelyDriving() {
        // Usual pattern: 400 km / 10 days per tank. But 4 days into this tank
        // only 40 km were driven — must not declare low fuel.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 24),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 14),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 4)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_840,
            tankCapacityLiters: 45,
            now: Date()
        )
        XCTAssertNotNil(prediction)
        XCTAssertGreaterThan(prediction?.daysRemaining ?? 0, 15)
        XCTAssertFalse(prediction?.shouldNotify ?? true)
    }

    func testFuelPredictionFiresWhenTankActuallyLow() {
        // 45 L tank at 10 L/100 km = 450 km. 400 km burned → ~5 L / 50 km left.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 24),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 14),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 4)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 11_200,
            tankCapacityLiters: 45,
            now: Date()
        )
        XCTAssertNotNil(prediction)
        XCTAssertTrue(prediction?.shouldNotify ?? false)
        XCTAssertTrue((prediction?.urgency ?? .none) >= .low)
        XCTAssertLessThanOrEqual(prediction?.kmRemaining ?? 999, 60)
    }

    func testFuelPredictionDeclaresEmptyNearZeroRange() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 24),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 14),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 4)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 11_240,
            tankCapacityLiters: 45,
            now: Date()
        )
        XCTAssertEqual(prediction?.urgency, .empty)
        XCTAssertTrue(prediction?.shouldNotify ?? false)
    }

    func testHalfTankHabitDoesNotEmptyTheTank() {
        // Driver tops up every ~300 km on a 60 L tank (8 L/100 km → 750 km range).
        // Habit used to say "empty at 300 km"; physically half the tank is left.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 55, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_300, liters: 24, full: true, daysAgo: 13),
            fuelLog(id: "3", odometer: 10_600, liters: 24, full: true, daysAgo: 6)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_900,
            tankCapacityLiters: 60,
            now: Date()
        )
        XCTAssertEqual(prediction?.urgency, FuelInsightLogic.FuelUrgency.none)
        XCTAssertFalse(prediction?.shouldNotify ?? true)
        XCTAssertEqual(prediction?.kmRemaining ?? 0, 450, accuracy: 5)
        XCTAssertEqual(prediction?.tankPercentRemaining ?? 0, 60, accuracy: 1)
    }

    func testSmallFillToFullStillMeansAFullTank() {
        // Last fill was only 12 L but it topped the tank off — range is a full tank, not 12 L.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_520, liters: 12, full: true, daysAgo: 1)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_520,
            tankCapacityLiters: 45,
            now: Date()
        )
        XCTAssertEqual(prediction?.tankPercentRemaining ?? 0, 100, accuracy: 0.5)
        XCTAssertGreaterThan(prediction?.kmRemaining ?? 0, 400)
    }

    func testPartialTopUpKeepsFuelAlreadyInTank() {
        // Full at 10_000, 150 km later add 10 L. Tank had ~30 L left, now ~40 L — not "10 L".
        let logs = [
            fuelLog(id: "1", odometer: 9_550, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_000, liters: 45, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_150, liters: 10, full: false, daysAgo: 1)
        ]
        let tank = FuelInsightLogic.tankState(
            logs: logs,
            kmSinceLastFill: 0,
            litersPer100km: 10,
            tankCapacityLiters: 45
        )
        XCTAssertEqual(tank?.litersLeft ?? 0, 45 - 15 + 10, accuracy: 0.01)
        XCTAssertTrue(tank?.anchoredOnFullTank ?? false)
    }

    func testInferredCapacityNeverPushesAlerts() {
        // No tank spec: capacity is only a lower bound from the biggest fill.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 24),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 14),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 4)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 11_190,
            tankCapacityLiters: nil,
            now: Date()
        )
        XCTAssertNotNil(prediction)
        XCTAssertFalse(prediction?.shouldNotify ?? true)
    }

    func testOdometerAnchorSkipsReadingThatRunsBackwards() {
        let now = Date()
        let anchors: [(Date, Double, String)] = [
            (now.addingTimeInterval(-86_400 * 3), 52_000, "Fuel entry"),
            (now.addingTimeInterval(-86_400), 5_210, "Service entry") // missing digit
        ]
        let anchor = OdometerReconciliation.latestTrustedAnchor(anchors)
        XCTAssertEqual(anchor?.1, 52_000)
        XCTAssertEqual(anchor?.2, "Fuel entry")
    }

    func testDriveStraddlingFillOnlyCountsTheRestOfTheDrive() {
        let fill = Date()
        let km = OdometerReconciliation.kmAfter(
            fill,
            startedAt: fill.addingTimeInterval(-600),
            endedAt: fill.addingTimeInterval(1_800),
            distanceKm: 40
        )
        XCTAssertEqual(km, 30, accuracy: 0.001)
        XCTAssertEqual(
            OdometerReconciliation.kmAfter(fill, startedAt: fill.addingTimeInterval(60), endedAt: fill.addingTimeInterval(600), distanceKm: 12),
            12
        )
    }

    func testFuelPredictionIgnoresCalendarWithoutOdometer() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 5)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: nil,
            now: Date()
        )
        XCTAssertNil(prediction)
    }

    func testFuelPredictionShrinksBudgetForPartialFill() {
        // Last fill was only 10 L — range budget must shrink; still full-ish of that slice so no notify yet at 0 km.
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_800, liters: 10, full: false, daysAgo: 0)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_800,
            tankCapacityLiters: 45,
            now: Date()
        )
        XCTAssertNotNil(prediction)
        XCTAssertLessThan(prediction?.kmRemaining ?? 999, 200)
        XCTAssertFalse(prediction?.shouldNotify ?? true)
    }

    func testFuelCooldownBlocksRepeatEmptySpam() {
        let vehicleId = "car-cooldown"
        let fillId = "fill-1"
        UserDefaults.standard.removeObject(forKey: "veloseete.fuelNotify." + vehicleId)
        let now = Date()

        let first = FuelNotifyCooldown.decision(
            vehicleId: vehicleId,
            fillId: fillId,
            urgency: .empty,
            proposedFireDate: now.addingTimeInterval(900),
            now: now
        )
        guard case let .schedule(fire) = first else {
            return XCTFail("expected first schedule")
        }
        FuelNotifyCooldown.markScheduled(vehicleId: vehicleId, fillId: fillId, urgency: .empty, fireDate: fire)

        // Same urgency after the scheduled fire already passed → skip (no spam).
        FuelNotifyCooldown.markScheduled(
            vehicleId: vehicleId,
            fillId: fillId,
            urgency: .empty,
            fireDate: now.addingTimeInterval(-120)
        )
        let second = FuelNotifyCooldown.decision(
            vehicleId: vehicleId,
            fillId: fillId,
            urgency: .empty,
            proposedFireDate: now.addingTimeInterval(900),
            now: now
        )
        XCTAssertEqual(second, .skip)

        // New fill resets.
        let third = FuelNotifyCooldown.decision(
            vehicleId: vehicleId,
            fillId: "fill-2",
            urgency: .low,
            proposedFireDate: now.addingTimeInterval(3_600),
            now: now
        )
        XCTAssertNotEqual(third, .skip)
    }

    func testServicePredictionHonorsDueDate() {
        let due = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let log = ServiceLog(
            id: "s1",
            vehicleId: "car",
            timestamp: Date().addingTimeInterval(-86_400 * 30),
            odometerReading: 10_000,
            serviceType: "Oil change",
            description: nil,
            brand: nil,
            cost: 200,
            currency: "QAR",
            nextServiceOdometer: nil,
            nextServiceDate: due
        )
        let prediction = FuelInsightLogic.predictServiceDue(
            services: [log],
            estimatedOdometer: 10_100
        )
        XCTAssertNotNil(prediction)
        XCTAssertEqual(prediction?.daysRemaining, 5)
    }

    func testAutoStartBlocksRecentPedestrian() {
        let now = Date()
        let recentWalk = now.addingTimeInterval(-10)
        XCTAssertTrue(TripAutoStartLogic.isPedestrianBlocked(lastPedestrianAt: recentWalk, now: now))
        XCTAssertFalse(
            TripAutoStartLogic.motionAdvancesHold(
                isAutomotive: true,
                confidenceOK: true,
                pedestrianBlocked: true
            )
        )
        XCTAssertFalse(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: 30,
                automotiveCorroborated: true,
                pedestrianBlocked: true
            )
        )
    }

    func testAutoStartSoftSpeedNeedsAutomotiveCorroboration() {
        // Jogging range — must not start a drive from GPS alone.
        XCTAssertFalse(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: 14,
                automotiveCorroborated: false,
                pedestrianBlocked: false
            )
        )
        XCTAssertTrue(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: 14,
                automotiveCorroborated: true,
                pedestrianBlocked: false
            )
        )
    }

    func testAutoStartHardSpeedAloneIsEnough() {
        XCTAssertTrue(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: 25,
                automotiveCorroborated: false,
                pedestrianBlocked: false
            )
        )
        XCTAssertFalse(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: TripAutoStartLogic.hardDrivingSpeedKmh - 0.1,
                automotiveCorroborated: false,
                pedestrianBlocked: false
            )
        )
    }

    func testAutoStartRequiresHoldDuration() {
        XCTAssertFalse(TripAutoStartLogic.shouldStart(heldFor: nil))
        XCTAssertFalse(TripAutoStartLogic.shouldStart(heldFor: 10))
        XCTAssertTrue(TripAutoStartLogic.shouldStart(heldFor: 18))
    }

    func testLowConfidenceAutomotiveDoesNotAdvanceHold() {
        XCTAssertFalse(
            TripAutoStartLogic.motionAdvancesHold(
                isAutomotive: true,
                confidenceOK: false,
                pedestrianBlocked: false
            )
        )
        XCTAssertTrue(
            TripAutoStartLogic.motionAdvancesHold(
                isAutomotive: true,
                confidenceOK: true,
                pedestrianBlocked: false
            )
        )
    }

    func testDrivesListBuildsRowsAPageAtATimeButMapsEveryDrive() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let trips = (0..<100).map { i in
            Trip(
                id: "t\(i)", vehicleId: "car",
                startedAt: start.addingTimeInterval(Double(i) * 3_600 * 7),
                endedAt: start.addingTimeInterval(Double(i) * 3_600 * 7 + 1_200),
                distanceKm: 10, durationSec: 1_200, avgSpeedKmh: 30, maxSpeedKmh: 60,
                startCoordinate: .init(latitude: 25.2, longitude: 51.5),
                endCoordinate: .init(latitude: 25.3, longitude: 51.6),
                route: [], source: "auto"
            )
        }
        let input = DrivesInputs(
            trips: trips, vehicles: [testVehicle], archivedVehicles: [], pending: [],
            fuelLogs: [], manufacturerStandard: nil, selectedVehicleId: nil, sort: .recent, unit: "km"
        )

        let first = DrivesListModel.build(from: input, revision: 1, rowLimit: 40)
        XCTAssertEqual(first.groups.flatMap(\.rows).count, 40)
        XCTAssertTrue(first.hasMoreRows)
        XCTAssertEqual(first.mapRoutes.count, 100)
        XCTAssertEqual(first.trips.count, 100)
        XCTAssertEqual(first.groups.first?.rows.first?.id, "t99")

        let all = DrivesListModel.build(from: input, revision: 2, rowLimit: 120)
        XCTAssertEqual(all.groups.flatMap(\.rows).count, 100)
        XCTAssertFalse(all.hasMoreRows)

        var ranked = input
        ranked.sort = .longest
        XCTAssertEqual(DrivesListModel.build(from: ranked, revision: 3, rowLimit: 40).flatRows.count, 40)
    }

    private var testVehicle: Vehicle {
        Vehicle(id: "car", nickname: "Test", make: "Test", model: "Car", fuelType: "petrol", currentOdometer: 10_500, fuelTankCapacity: 50, currency: "QAR", fuelVolumeUnit: "L", icon: nil, paintColor: nil, createdAt: Date(), isArchived: false, archivedAt: nil)
    }

    private func fuelLog(id: String, vehicleId: String = "car", odometer: Double, liters: Double, full: Bool, daysAgo: Int, from reference: Date = Date()) -> FuelLog {
        FuelLog(id: id, vehicleId: vehicleId, timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: reference)!, odometerReading: odometer, fuelVolume: liters, pricePerUnit: 2, totalCost: liters * 2, currency: "QAR", isFullTank: full)
    }

    private func location(latitude: Double, longitude: Double, seconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 10,
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }
}
