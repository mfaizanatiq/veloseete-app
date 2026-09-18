import XCTest
@testable import Veloseete

final class VehicleLearningModelTests: XCTestCase {

    // MARK: - Scale learning

    func testPerfectGpsKeepsScaleNearOne() {
        var state = VehicleLearningState.default
        for _ in 0..<3 {
            let result = VehicleLearningModel.observeScale(
                .init(previousDashKm: 10_000, newDashKm: 10_450, gpsTrackedKm: 450),
                state: state
            )
            guard case .applied(_, let next) = result else {
                return XCTFail("expected applied")
            }
            state = next
        }
        XCTAssertEqual(state.gpsScale, 1.0, accuracy: 0.01)
        XCTAssertEqual(state.scaleSampleCount, 3)
        XCTAssertTrue(state.isCalibrated)
    }

    func testGpsEightPercentLowConvergesTowardTrueScale() {
        // Dash advances 450; GPS only saw 450/1.087 ≈ 414.
        let trueScale = 1.087
        let dashDelta = 450.0
        let gps = dashDelta / trueScale
        var state = VehicleLearningState.default

        for i in 0..<5 {
            let base = 10_000.0 + Double(i) * dashDelta
            let result = VehicleLearningModel.observeScale(
                .init(previousDashKm: base, newDashKm: base + dashDelta, gpsTrackedKm: gps),
                state: state
            )
            guard case .applied(let observed, let next) = result else {
                return XCTFail("expected applied at cycle \(i)")
            }
            XCTAssertEqual(observed, trueScale, accuracy: 0.001)
            state = next
        }

        XCTAssertEqual(state.gpsScale, trueScale, accuracy: 0.02)
        XCTAssertGreaterThanOrEqual(state.scaleSampleCount, 3)

        // Next live estimate: verified + gps*scale ≈ dash
        let est = VehicleLearningModel.estimatedKm(
            verifiedKm: 12_250,
            trackedKm: gps,
            gpsScale: state.gpsScale
        )
        let expectedDash = 12_250 + dashDelta
        let errorPct = abs(est - expectedDash) / dashDelta
        XCTAssertLessThan(errorPct, 0.02, "calibrated EST should be within ~2% of dash advance")
    }

    func testGpsFivePercentHighConvergesDown() {
        let trueScale = 0.95
        let dashDelta = 400.0
        let gps = dashDelta / trueScale
        var state = VehicleLearningState.default
        for i in 0..<4 {
            let base = 20_000.0 + Double(i) * dashDelta
            let result = VehicleLearningModel.observeScale(
                .init(previousDashKm: base, newDashKm: base + dashDelta, gpsTrackedKm: gps),
                state: state
            )
            guard case .applied(_, let next) = result else {
                return XCTFail("expected applied")
            }
            state = next
        }
        XCTAssertEqual(state.gpsScale, trueScale, accuracy: 0.025)
    }

    func testMissedTripsOutlierRejected() {
        var state = VehicleLearningState.default
        // First good cycle
        if case .applied(_, let next) = VehicleLearningModel.observeScale(
            .init(previousDashKm: 10_000, newDashKm: 10_450, gpsTrackedKm: 450),
            state: state
        ) {
            state = next
        }
        let before = state.gpsScale

        // Huge dash jump vs tiny GPS → out of clamp
        let rejected = VehicleLearningModel.observeScale(
            .init(previousDashKm: 10_450, newDashKm: 11_200, gpsTrackedKm: 50),
            state: state
        )
        guard case .rejected(let reason, let same) = rejected else {
            return XCTFail("expected rejection")
        }
        XCTAssertEqual(reason, .outOfClamp)
        XCTAssertEqual(same.gpsScale, before, accuracy: 0.0001)
        XCTAssertEqual(same.scaleSampleCount, state.scaleSampleCount)
    }

    func testInsufficientGpsRejected() {
        let result = VehicleLearningModel.observeScale(
            .init(previousDashKm: 10_000, newDashKm: 10_030, gpsTrackedKm: 25),
            state: .default
        )
        guard case .rejected(let reason, _) = result else {
            return XCTFail("expected rejection")
        }
        XCTAssertEqual(reason, .insufficientGps)
    }

    // MARK: - Range learning

    func testPartialFillDoesNotUpdateFullTankRange() {
        let state = VehicleLearningModel.observeRange(
            .init(actualRangeKm: 200, fuelLiters: 20, isFullTankCycle: false, predictedBudgetKm: 220),
            state: .default
        )
        XCTAssertNil(state.fullTankRangeKm)
        XCTAssertEqual(state.rangeSampleCount, 0)
    }

    func testFullTankRangeEWMA() {
        var state = VehicleLearningState.default
        let cycles = [450.0, 440.0, 460.0, 450.0]
        for range in cycles {
            state = VehicleLearningModel.observeRange(
                .init(actualRangeKm: range, fuelLiters: 40, isFullTankCycle: true, predictedBudgetKm: 450),
                state: state
            )
        }
        XCTAssertEqual(state.rangeSampleCount, 4)
        XCTAssertEqual(state.fullTankRangeKm ?? 0, 450, accuracy: 8)
    }

    func testRangeBudgetPrefersLearnedRange() {
        var state = VehicleLearningState.default
        state = VehicleLearningModel.observeRange(
            .init(actualRangeKm: 450, fuelLiters: 40, isFullTankCycle: true, predictedBudgetKm: nil),
            state: state
        )
        state = VehicleLearningModel.observeRange(
            .init(actualRangeKm: 450, fuelLiters: 40, isFullTankCycle: true, predictedBudgetKm: 450),
            state: state
        )
        state = VehicleLearningModel.observeRange(
            .init(actualRangeKm: 450, fuelLiters: 40, isFullTankCycle: true, predictedBudgetKm: 450),
            state: state
        )

        let budget = VehicleLearningModel.rangeBudgetKm(
            state: state,
            lastFillLiters: 40,
            isFullTank: true,
            litersPer100km: 8.0, // volume-only would say 500 km
            patternTypicalRangeKm: 500,
            tankCapacityLiters: 50
        )
        // Learned ~450 should pull the blend well below pure volume/pattern 500.
        XCTAssertLessThan(budget.km, 490)
        XCTAssertGreaterThan(budget.km, 420)
        XCTAssertGreaterThan(budget.confidence, 0.55)
    }

    func testColdStartLowConfidence() {
        let budget = VehicleLearningModel.rangeBudgetKm(
            state: .default,
            lastFillLiters: 40,
            isFullTank: true,
            litersPer100km: 8.0,
            patternTypicalRangeKm: nil,
            tankCapacityLiters: 50
        )
        XCTAssertLessThanOrEqual(budget.confidence, 0.5)
    }

    // MARK: - Efficiency identity (interval)

    func testKmPerLiterMatchesInverseOfL100FromSameTotals() {
        let km = 500.0
        let liters = 35.0
        let l100 = EfficiencyFormat.litersPer100km(distanceKm: km, fuelLiters: liters)!
        let kml = EfficiencyFormat.kmPerLiter(distanceKm: km, fuelLiters: liters)!
        XCTAssertEqual(l100, 7.0, accuracy: 0.0001)
        XCTAssertEqual(kml, km / liters, accuracy: 0.0001)
        XCTAssertEqual(
            EfficiencyFormat.toDisplay(l100, unit: .kmPerLiter)!,
            kml,
            accuracy: 0.0001
        )
    }

    func testWeightedAverageNotMeanOfRates() {
        // Interval A: 500 km / 35 L = 7.0 L/100
        // Interval B: 1000 km / 80 L = 8.0 L/100
        // Weighted: 115 L / 1500 km * 100 = 7.666...
        let l100 = EfficiencyFormat.litersPer100km(totalDistanceKm: 1500, totalFuelLiters: 115)!
        XCTAssertEqual(l100, 115.0 / 1500.0 * 100, accuracy: 0.0001)
        let naiveMean = (7.0 + 8.0) / 2.0
        XCTAssertNotEqual(l100, naiveMean, accuracy: 0.01)

        let kml = EfficiencyFormat.toDisplay(l100, unit: .kmPerLiter)!
        XCTAssertEqual(kml, 1500.0 / 115.0, accuracy: 0.0001)
    }

    func testOdometerReconciliationUsesScale() {
        let raw = OdometerReconciliation.estimated(verifiedKm: 52_000, trackedKm: 184, gpsScale: 1.0)
        XCTAssertEqual(raw, 52_184, accuracy: 0.001)
        let scaled = OdometerReconciliation.estimated(verifiedKm: 52_000, trackedKm: 184, gpsScale: 1.087)
        XCTAssertEqual(scaled, 52_000 + 184 * 1.087, accuracy: 0.01)
        let variance = OdometerReconciliation.variance(
            enteredKm: scaled + 3,
            verifiedKm: 52_000,
            trackedKm: 184,
            gpsScale: 1.087
        )
        XCTAssertEqual(variance, 3, accuracy: 0.01)
    }

    func testPredictNextFillUsesCalibratedOdometerKmSince() {
        let logs = [
            fuel(id: "1", odo: 10_000, liters: 40, full: true, daysAgo: 20),
            fuel(id: "2", odo: 10_450, liters: 38, full: true, daysAgo: 5)
        ]
        // Without learning, kmSince from estimated odo 10_450 + 100 tracked raw
        // With scale 1.1 → estimated = 10450 + 110
        var learning = VehicleLearningState.default
        learning.gpsScale = 1.1
        learning.scaleSampleCount = 4
        learning.fullTankRangeKm = 450
        learning.rangeSampleCount = 4

        let pred = FuelInsightLogic.predictNextFill(
            logs: logs,
            estimatedOdometer: 10_450 + 100 * 1.1,
            tankCapacityLiters: 50,
            brochureL100km: 8.0,
            learning: learning
        )
        XCTAssertNotNil(pred)
        // Budget ~450, kmSince = 110 → kmLeft ~340
        XCTAssertEqual(pred!.kmRemaining ?? -1, 450 - 110, accuracy: 40)
    }

    // MARK: Helpers

    private func fuel(id: String, odo: Double, liters: Double, full: Bool, daysAgo: Int) -> FuelLog {
        FuelLog(
            id: id,
            vehicleId: "car",
            timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            odometerReading: odo,
            fuelVolume: liters,
            pricePerUnit: 2,
            totalCost: liters * 2,
            currency: "QAR",
            isFullTank: full
        )
    }
}
