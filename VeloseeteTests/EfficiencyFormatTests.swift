import XCTest
@testable import Veloseete

final class EfficiencyFormatTests: XCTestCase {
    func testKmPerLiterIsInverseOfLitersPer100() {
        let l100 = 8.0
        let kmL = EfficiencyFormat.toDisplay(l100, unit: .kmPerLiter)
        XCTAssertEqual(kmL ?? -1, 12.5, accuracy: 0.0001)

        let back = EfficiencyFormat.toLitersPer100km(12.5, unit: .kmPerLiter)
        XCTAssertEqual(back ?? -1, 8.0, accuracy: 0.0001)
    }

    func testLitersPer100Passthrough() {
        XCTAssertEqual(
            EfficiencyFormat.toDisplay(7.4, unit: .litersPer100km) ?? -1,
            7.4,
            accuracy: 0.0001
        )
    }

    func testZeroAndNegativeAreNil() {
        XCTAssertNil(EfficiencyFormat.toDisplay(0, unit: .kmPerLiter))
        XCTAssertNil(EfficiencyFormat.toDisplay(-3, unit: .kmPerLiter))
        XCTAssertNil(EfficiencyFormat.toLitersPer100km(0, unit: .kmPerLiter))
    }

    func testFormatLabels() {
        XCTAssertEqual(
            EfficiencyFormat.format(10, unit: .litersPer100km),
            "10.0 L/100km"
        )
        XCTAssertEqual(
            EfficiencyFormat.format(10, unit: .kmPerLiter, style: .short),
            "10.0 km/L"
        )
        // 10 L/100 → 10 km/L
        XCTAssertEqual(
            EfficiencyFormat.format(10, unit: .kmPerLiter),
            "10.0 km/L"
        )
    }

    func testBetterThanSpecAlwaysUsesL100() {
        // 7 L/100 beats 8 L/100 brochure (uses less fuel)
        XCTAssertTrue(EfficiencyFormat.isBetterThanSpec(currentL100: 7, standardL100: 8))
        XCTAssertFalse(EfficiencyFormat.isBetterThanSpec(currentL100: 9, standardL100: 8))

        // Same truth after display conversion mentally: 14.3 km/L > 12.5 km/L
        let you = EfficiencyFormat.toDisplay(7, unit: .kmPerLiter)!
        let brochure = EfficiencyFormat.toDisplay(8, unit: .kmPerLiter)!
        XCTAssertGreaterThan(you, brochure)
        XCTAssertTrue(EfficiencyUnit.kmPerLiter.higherIsBetter)
        XCTAssertFalse(EfficiencyUnit.litersPer100km.higherIsBetter)
    }

    func testDeviationPercent() {
        let pct = EfficiencyFormat.deviationPercent(currentL100: 9, standardL100: 8)
        XCTAssertEqual(pct, 12.5, accuracy: 0.01)
        let better = EfficiencyFormat.deviationPercent(currentL100: 7.2, standardL100: 8)
        XCTAssertLessThan(better, 0)
    }
}
