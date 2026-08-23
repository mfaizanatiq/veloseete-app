import CoreLocation
import XCTest
@testable import Veloseete

/// Crash-prevention + invariant suite for the tracking core.
final class TripTrackingStressTests: XCTestCase {

    // MARK: - Auto-start / walking

    func testWalkingThenFalseAutomotiveNeverStarts() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        clock.onPedestrian(at: t0, confidenceOK: true)
        // 20s of fake automotive while still in the pedestrian block window.
        for second in 1...25 {
            let started = clock.onAutomotive(
                at: t0.addingTimeInterval(Double(second)),
                confidenceOK: true
            )
            XCTAssertFalse(started, "Must not auto-start \(second)s after walking")
        }
    }

    func testJoggingSpeedAloneNeverStarts() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        for second in 0...30 {
            let started = clock.onGPS(speedKmh: 14, at: t0.addingTimeInterval(Double(second)))
            XCTAssertFalse(started, "14 km/h alone must not start at t+\(second)")
        }
    }

    func testRealDriveAutomotiveHoldStartsAt18s() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        XCTAssertFalse(clock.onAutomotive(at: t0, confidenceOK: true))
        XCTAssertFalse(clock.onAutomotive(at: t0.addingTimeInterval(17), confidenceOK: true))
        XCTAssertTrue(clock.onAutomotive(at: t0.addingTimeInterval(18), confidenceOK: true))
    }

    func testHardGPSHoldStartsWithoutMotion() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        XCTAssertFalse(clock.onGPS(speedKmh: 40, at: t0))
        XCTAssertTrue(clock.onGPS(speedKmh: 45, at: t0.addingTimeInterval(18)))
    }

    func testSoftGPSWithCorroborationStarts() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        _ = clock.onAutomotive(at: t0, confidenceOK: true)
        XCTAssertFalse(clock.onGPS(speedKmh: 15, at: t0.addingTimeInterval(5)))
        XCTAssertTrue(clock.onGPS(speedKmh: 16, at: t0.addingTimeInterval(18)))
    }

    func testLowConfidenceAutomotiveDoesNotArmClock() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 6_000_000)
        for second in 0...30 {
            XCTAssertFalse(
                clock.onAutomotive(at: t0.addingTimeInterval(Double(second)), confidenceOK: false)
            )
        }
        XCTAssertNil(clock.automotiveSince)
    }

    func testPedestrianBlockExpiresAfter60s() {
        var clock = TripAutoStartLogic.HoldClock()
        let t0 = Date(timeIntervalSince1970: 7_000_000)
        clock.onPedestrian(at: t0, confidenceOK: true)
        XCTAssertFalse(clock.onAutomotive(at: t0.addingTimeInterval(30), confidenceOK: true))
        // After block window, a fresh 18s automotive hold can start.
        let after = t0.addingTimeInterval(61)
        XCTAssertFalse(clock.onAutomotive(at: after, confidenceOK: true))
        XCTAssertTrue(clock.onAutomotive(at: after.addingTimeInterval(18), confidenceOK: true))
    }

    func testNonFiniteGPSSpeedIsIgnored() {
        XCTAssertFalse(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: .nan,
                automotiveCorroborated: true,
                pedestrianBlocked: false
            )
        )
        XCTAssertFalse(
            TripAutoStartLogic.gpsAdvancesHold(
                speedKmh: .infinity,
                automotiveCorroborated: false,
                pedestrianBlocked: false
            )
        )
    }

    // MARK: - Finish / save safety

    func testShortWalkDistanceIsDiscarded() {
        XCTAssertFalse(TripFinishLogic.shouldPersist(distanceKm: 0.05))
        XCTAssertFalse(TripFinishLogic.shouldPersist(distanceKm: 0.249))
        XCTAssertTrue(TripFinishLogic.shouldPersist(distanceKm: 0.25))
        XCTAssertFalse(TripFinishLogic.shouldPersist(distanceKm: .nan))
        XCTAssertFalse(TripFinishLogic.shouldPersist(distanceKm: -.infinity))
    }

    func testDurationNeverNegativeWithClockSkew() {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 50) // inverted
        let duration = TripFinishLogic.durationSec(
            startedAt: start,
            endedAt: end,
            pausedAccumulated: 0,
            pauseStartedAt: nil,
            isPaused: false
        )
        XCTAssertEqual(duration, 0)
    }

    func testDurationSubtractsActivePause() {
        let start = Date(timeIntervalSince1970: 0)
        let pauseAt = Date(timeIntervalSince1970: 60)
        let end = Date(timeIntervalSince1970: 100)
        let duration = TripFinishLogic.durationSec(
            startedAt: start,
            endedAt: end,
            pausedAccumulated: 10,
            pauseStartedAt: pauseAt,
            isPaused: true
        )
        // 100 - 0 - 10 - (100-60) = 50
        XCTAssertEqual(duration, 50, accuracy: 0.001)
    }

    func testAverageSpeedSafeWhenDurationZero() {
        XCTAssertEqual(TripFinishLogic.averageSpeedKmh(distanceKm: 12, durationSec: 0), 0)
        XCTAssertEqual(TripFinishLogic.averageSpeedKmh(distanceKm: 12, durationSec: .nan), 0)
        let speed = TripFinishLogic.averageSpeedKmh(distanceKm: 60, durationSec: 3600)
        XCTAssertEqual(speed, 60, accuracy: 0.001)
    }

    // MARK: - Route / GPS rejection

    func testEmptyAndTinyRoutesSurviveCompaction() {
        XCTAssertEqual(TripTrackingLogic.compactLiveRoute([]), [])
        let one = [TripCoordinate(latitude: 25, longitude: 51)]
        XCTAssertEqual(TripTrackingLogic.compactLiveRoute(one), one)
        XCTAssertEqual(TripTrackingLogic.downsample([], maximum: 200), [])
        XCTAssertEqual(TripTrackingLogic.downsample(one, maximum: 2), one)
        XCTAssertEqual(TripTrackingLogic.cleanedForDisplay([]), [])
        XCTAssertEqual(TripTrackingLogic.thinForPersistence([]), [])
    }

    func testCorruptAccuracyNeverAccepted() {
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: .nan))
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: .infinity))
        XCTAssertFalse(TripTrackingLogic.accepts(horizontalAccuracy: -0.1))
    }

    func testZeroElapsedSegmentRejected() {
        let a = location(latitude: 25.2854, longitude: 51.5310, seconds: 10, speed: 20)
        let b = location(latitude: 25.2855, longitude: 51.5310, seconds: 10, speed: 20)
        XCTAssertEqual(TripTrackingLogic.acceptedSegmentDistance(from: a, to: b), 0)
    }

    func testLongDriveCompactionKeepsEndpoints() {
        var route: [TripCoordinate] = []
        route.reserveCapacity(9_500)
        for index in 0..<9_500 {
            route.append(
                TripCoordinate(
                    latitude: 25.0 + Double(index) * 0.00005,
                    longitude: 51.0 + Double(index % 40) * 0.00001
                )
            )
        }
        let compacted = TripTrackingLogic.compactLiveRoute(
            route,
            softCap: 8_000,
            compactedMaximum: 4_000
        )
        XCTAssertEqual(compacted.first, route.first)
        XCTAssertEqual(compacted.last, route.last)
        XCTAssertLessThanOrEqual(compacted.count, 4_000)
        XCTAssertGreaterThan(compacted.count, 100)
    }

    func testCorruptPendingJSONDoesNotCrashDecodePath() {
        // Mirrors TripRecordingService.restorePendingSaves catch path.
        let junk = Data("not-json".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([PendingTripSave].self, from: junk))
    }

    func testPendingQueueWithEmptyVehicleIdRoundTrips() throws {
        let pending = PendingTripSave(
            id: UUID(),
            vehicleId: "",
            vehicleName: "Orphan",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 100),
            distanceKm: 1.2,
            durationSec: 90,
            avgSpeedKmh: 48,
            maxSpeedKmh: 60,
            startCoordinate: nil,
            endCoordinate: nil,
            route: [],
            source: "manual",
            suggestedOdometer: 1001.2
        )
        let data = try JSONEncoder().encode([pending])
        let restored = try JSONDecoder().decode([PendingTripSave].self, from: data)
        XCTAssertEqual(restored.first?.vehicleId, "")
        XCTAssertEqual(restored.first?.route, [])
    }

    // MARK: - Drive mood resilience

    func testMoodHandlesZeroBaselineAndNaNSpeed() {
        var state = DriveMoodLogic.State()
        let snap = DriveMoodLogic.ingest(
            state: &state,
            speedKmh: .nan,
            at: Date(),
            isPaused: false,
            baselineL100: 0
        )
        XCTAssertGreaterThanOrEqual(snap.driveScore, 0)
        XCTAssertLessThanOrEqual(snap.driveScore, 100)
        XCTAssertTrue(snap.estL100.isFinite)
        XCTAssertTrue(snap.thirst.isFinite)
    }

    func testMoodBurstDoesNotCrashOrExplodeScore() {
        var state = DriveMoodLogic.State()
        let start = Date()
        for step in 0..<200 {
            let speed = Double((step * 37) % 140)
            let snap = DriveMoodLogic.ingest(
                state: &state,
                speedKmh: speed,
                at: start.addingTimeInterval(Double(step) * 1.5),
                isPaused: false,
                baselineL100: 8
            )
            XCTAssertGreaterThanOrEqual(snap.driveScore, 0)
            XCTAssertLessThanOrEqual(snap.driveScore, 100)
            XCTAssertTrue(snap.thirst.isFinite)
            XCTAssertTrue(snap.estL100.isFinite)
        }
        XCTAssertLessThanOrEqual(state.samples.count, 40)
    }

    private func location(
        latitude: Double,
        longitude: Double,
        seconds: TimeInterval,
        speed: Double = 10
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: speed,
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }
}
