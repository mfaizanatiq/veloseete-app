import XCTest
@testable import Veloseete

final class LiveDriveIntelligenceLogicTests: XCTestCase {
    private let vehicleId = "v1"
    private lazy var fills: [FuelLog] = {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            FuelLog(
                id: "f1",
                vehicleId: vehicleId,
                timestamp: start,
                odometerReading: 10_000,
                fuelVolume: 45,
                pricePerUnit: 2.1,
                totalCost: 94.5,
                currency: "QAR",
                isFullTank: true
            ),
            FuelLog(
                id: "f2",
                vehicleId: vehicleId,
                timestamp: start.addingTimeInterval(86_400 * 5),
                odometerReading: 10_420,
                fuelVolume: 42,
                pricePerUnit: 2.1,
                totalCost: 88.2,
                currency: "QAR",
                isFullTank: true
            )
        ]
    }()

    func testEfficientBurnSitsRightOnWave() {
        let snap = LiveDriveIntelligenceLogic.compute(
            logs: fills,
            estimatedOdometer: 10_200,
            tankCapacityLiters: 50,
            brochureL100km: 8.5,
            personalBaselineL100: 8.0,
            liveEstL100: 6.8,
            thirst: 0.15,
            sessionAvgSpeedKmh: 62,
            distanceUnit: "km"
        )
        XCTAssertLessThan(snap.burnPosition, 0.35)
    }

    func testThirstyLiveBurnShiftsLeftAndAdjustsRange() {
        let lean = LiveDriveIntelligenceLogic.compute(
            logs: fills,
            estimatedOdometer: 10_200,
            tankCapacityLiters: 50,
            brochureL100km: 8.5,
            personalBaselineL100: 8.0,
            liveEstL100: 7.0,
            thirst: 0.2,
            sessionAvgSpeedKmh: 60,
            distanceUnit: "km"
        )
        let thirsty = LiveDriveIntelligenceLogic.compute(
            logs: fills,
            estimatedOdometer: 10_200,
            tankCapacityLiters: 50,
            brochureL100km: 8.5,
            personalBaselineL100: 8.0,
            liveEstL100: 10.5,
            thirst: 0.72,
            sessionAvgSpeedKmh: 60,
            distanceUnit: "km"
        )
        XCTAssertGreaterThan(thirsty.burnPosition, lean.burnPosition)
        if let leanKm = lean.kmRemaining, let thirstyKm = thirsty.kmRemaining {
            XCTAssertLessThan(thirstyKm, leanKm)
        }
    }

    func testWithoutFullTankHistoryAvoidsPreciseRange() {
        let snap = LiveDriveIntelligenceLogic.compute(
            logs: [],
            estimatedOdometer: 10_000,
            tankCapacityLiters: 50,
            brochureL100km: 8.5,
            personalBaselineL100: 8.0,
            liveEstL100: 8.2,
            thirst: 0.3,
            sessionAvgSpeedKmh: 0,
            distanceUnit: "km"
        )
        XCTAssertFalse(snap.showsRangeEstimate)
        XCTAssertNil(snap.kmRemaining)
        XCTAssertFalse(snap.headline.contains("312"))
    }

    func testConfidentRangeUsesBandLanguage() {
        let snap = LiveDriveIntelligenceLogic.compute(
            logs: fills,
            estimatedOdometer: 10_200,
            tankCapacityLiters: 50,
            brochureL100km: 8.5,
            personalBaselineL100: 8.0,
            liveEstL100: 7.2,
            thirst: 0.25,
            sessionAvgSpeedKmh: 55,
            distanceUnit: "km"
        )
        if snap.showsRangeEstimate {
            XCTAssertTrue(snap.headline.contains("About"))
            XCTAssertTrue(snap.headline.contains("–") || snap.headline.contains("-"))
        }
    }
}
