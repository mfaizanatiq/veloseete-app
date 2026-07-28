import CoreLocation
import XCTest
@testable import Veloseete

final class TripTrackingLogicTests: XCTestCase {
    func testAccuracyBoundary() {
        XCTAssertTrue(TripTrackingLogic.accepts(horizontalAccuracy: 0))
        XCTAssertTrue(TripTrackingLogic.accepts(horizontalAccuracy: 45))
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: -1))
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: 45.1))
    }

    func testValidSegmentAccumulatesDistance() {
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        let end = location(latitude: 25.2859, longitude: 51.5310, seconds: 8)
        XCTAssertGreaterThan(TripTrackingLogic.acceptedSegmentDistance(from: start, to: end), 40)
    }

    func testJumpAndStaleSegmentsAreRejected() {
        let start = location(latitude: 25.2854, longitude: 51.5310, seconds: 0)
        let jump = location(latitude: 25.30, longitude: 51.5310, seconds: 4)
        let stale = location(latitude: 25.2859, longitude: 51.5310, seconds: 35)
        XCTAssertEqual(TripTrackingLogic.acceptedSegmentDistance(from: start, to: jump), 0)
        XCTAssertEqual(TripTrackingLogic.acceptedSegmentDistance(from: start, to: stale), 0)
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

    func testOdometerEstimateAndVariance() {
        XCTAssertEqual(OdometerReconciliation.estimated(verifiedKm: 52_000, trackedKm: 184), 52_184)
        XCTAssertEqual(OdometerReconciliation.variance(enteredKm: 52_191, verifiedKm: 52_000, trackedKm: 184), 7)
    }

    func testDashboardEfficiencyUsesClosingFuelOnly() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "2", odometer: 10_500, liters: 35, full: true, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertEqual(metrics.current ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(metrics.avgEfficiency ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(metrics.totalDistance, 500, accuracy: 0.001)
        XCTAssertEqual(metrics.efficiencySampleCount, 1)
    }

    func testDashboardDoesNotCalculateFromSingleOrUnclosedPartialFill() {
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "2", odometer: 10_200, liters: 15, full: false, daysAgo: 2)
        ]
        let metrics = MetricsCalculator.compute(vehicle: testVehicle, logs: logs)
        XCTAssertNil(metrics.current)
        XCTAssertNil(metrics.avgEfficiency)
        XCTAssertEqual(metrics.totalDistance, 0)
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
        XCTAssertEqual(DashboardCopy.spendTrend(nil), "No prior month to compare")
        XCTAssertEqual(DashboardCopy.spendTrend(0), "Flat vs last month")
    }

    func testSpecComparisonRequiresTwoValidIntervals() {
        let status = DashboardCopy.status(efficiency: 18.6, standard: 8, sampleCount: 1)
        XCTAssertEqual(status.text, "Based on 1 interval — add another full tank")
        XCTAssertEqual(status.tone, .learning)
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
        let logs = [
            fuelLog(id: "1", odometer: 10_000, liters: 40, full: true, daysAgo: 20),
            fuelLog(id: "2", odometer: 10_400, liters: 40, full: true, daysAgo: 10),
            fuelLog(id: "3", odometer: 10_800, liters: 40, full: true, daysAgo: 0)
        ]
        let prediction = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_800,
            now: Date()
        )
        XCTAssertNotNil(prediction)
        // ~10 day cadence just filled → about 9–10 days remaining (with early lean).
        XCTAssertGreaterThanOrEqual(prediction?.daysRemaining ?? -1, 7)
        XCTAssertLessThanOrEqual(prediction?.daysRemaining ?? 99, 11)
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

    private var testVehicle: Vehicle {
        Vehicle(id: "car", nickname: "Test", make: "Test", model: "Car", fuelType: "petrol", currentOdometer: 10_500, fuelTankCapacity: 50, currency: "QAR", fuelVolumeUnit: "L", icon: nil, createdAt: Date(), isArchived: false, archivedAt: nil)
    }

    private func fuelLog(id: String, vehicleId: String = "car", odometer: Double, liters: Double, full: Bool, daysAgo: Int) -> FuelLog {
        FuelLog(id: id, vehicleId: vehicleId, timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!, odometerReading: odometer, fuelVolume: liters, pricePerUnit: 2, totalCost: liters * 2, currency: "QAR", isFullTank: full)
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
