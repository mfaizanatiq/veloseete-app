import XCTest
@testable import Veloseete

final class FillIntervalDistanceTests: XCTestCase {
    func testDrivenKmIsOdometerDeltaBetweenFills() {
        let logs = [
            fuel(id: "a", odo: 10_000, daysAgo: 20),
            fuel(id: "b", odo: 10_420, daysAgo: 10),
            fuel(id: "c", odo: 10_900, daysAgo: 1)
        ]

        let map = FillIntervalDistance.drivenKmByFillId(logs: logs)

        XCTAssertNil(map["a"], "First fill has no prior interval")
        XCTAssertEqual(map["b"] ?? -1, 420, accuracy: 0.01)
        XCTAssertEqual(map["c"] ?? -1, 480, accuracy: 0.01)
    }

    func testIgnoresNonPositiveDeltas() {
        let logs = [
            fuel(id: "a", odo: 10_000, daysAgo: 5),
            fuel(id: "b", odo: 9_900, daysAgo: 2), // corrected/backwards reading
            fuel(id: "c", odo: 10_100, daysAgo: 0)
        ]

        let map = FillIntervalDistance.drivenKmByFillId(logs: logs)

        XCTAssertNil(map["b"])
        XCTAssertEqual(map["c"] ?? -1, 200, accuracy: 0.01)
    }

    func testEmptyAndSingleFill() {
        XCTAssertTrue(FillIntervalDistance.drivenKmByFillId(logs: []).isEmpty)
        XCTAssertTrue(
            FillIntervalDistance.drivenKmByFillId(logs: [fuel(id: "only", odo: 1_000, daysAgo: 0)]).isEmpty
        )
    }

    private func fuel(id: String, odo: Double, daysAgo: Int) -> FuelLog {
        FuelLog(
            id: id,
            vehicleId: "car",
            timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            odometerReading: odo,
            fuelVolume: 40,
            pricePerUnit: 2,
            totalCost: 80,
            currency: "QAR",
            isFullTank: true
        )
    }
}
