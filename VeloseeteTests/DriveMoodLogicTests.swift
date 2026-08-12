import XCTest
@testable import Veloseete

final class DriveMoodLogicTests: XCTestCase {
    func testSmoothDrivingKeepsHighScore() {
        var state = DriveMoodLogic.State()
        let start = Date()
        var last = DriveMoodLogic.ingest(
            state: &state,
            speedKmh: 60,
            at: start,
            isPaused: false,
            baselineL100: 8
        )

        for step in 1...12 {
            last = DriveMoodLogic.ingest(
                state: &state,
                speedKmh: 62 + Double(step % 3),
                at: start.addingTimeInterval(Double(step) * 2),
                isPaused: false,
                baselineL100: 8
            )
        }

        XCTAssertGreaterThanOrEqual(last.driveScore, 70)
        XCTAssertEqual(last.moodRaw, "smooth")
        XCTAssertLessThan(last.estL100, 9.5)
    }

    func testHarshAccelerationDropsScoreAndSetsEvent() {
        var state = DriveMoodLogic.State()
        let start = Date()
        _ = DriveMoodLogic.ingest(
            state: &state,
            speedKmh: 30,
            at: start,
            isPaused: false,
            baselineL100: 8
        )
        let after = DriveMoodLogic.ingest(
            state: &state,
            speedKmh: 70,
            at: start.addingTimeInterval(2),
            isPaused: false,
            baselineL100: 8
        )

        XCTAssertLessThan(after.driveScore, 78)
        XCTAssertEqual(after.lastEvent, "Harsh accel")
        XCTAssertTrue(["watch", "heavy"].contains(after.moodRaw))
    }

    func testPausedKeepsMoodPaused() {
        var state = DriveMoodLogic.State(score: 55)
        let snap = DriveMoodLogic.ingest(
            state: &state,
            speedKmh: 0,
            at: Date(),
            isPaused: true,
            baselineL100: 8
        )
        XCTAssertEqual(snap.moodRaw, "paused")
        XCTAssertEqual(snap.statusLabel, "Paused")
    }

    func testFinalSnapshotMarksSaved() {
        let snap = DriveMoodLogic.finalSnapshot(
            state: DriveMoodLogic.State(score: 82),
            baselineL100: 7.2,
            saved: true
        )
        XCTAssertEqual(snap.moodRaw, "saved")
        XCTAssertEqual(snap.statusLabel, "Saved")
    }
}
