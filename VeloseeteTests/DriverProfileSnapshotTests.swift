import XCTest
@testable import Veloseete

final class DriverProfileSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    /// Wednesday, 1 Oct 2025, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_759_320_000)

    private func trip(
        daysAgo: Double,
        hour: Int = 8,
        km: Double = 10,
        topKmh: Double = 80,
        minutes: Double = 20,
        role: TripRole = .driver
    ) -> Trip {
        let day = calendar.startOfDay(for: now.addingTimeInterval(-daysAgo * 86_400))
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return Trip(
            id: UUID().uuidString,
            vehicleId: "car",
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            distanceKm: km,
            durationSec: minutes * 60,
            avgSpeedKmh: 40,
            maxSpeedKmh: topKmh,
            startCoordinate: nil,
            endCoordinate: nil,
            route: [],
            source: "auto",
            role: role.rawValue
        )
    }

    private func build(_ trips: [Trip]) -> DriverProfileSnapshot {
        DriverProfileSnapshot.build(trips: trips, lifetimeKm: 0, unit: "km", now: now, calendar: calendar)
    }

    func testCurrentStreakSurvivesQuietCurrentWeek() {
        // Last week and the two before it, nothing yet this week.
        let snapshot = build([trip(daysAgo: 7), trip(daysAgo: 14), trip(daysAgo: 21)])
        XCTAssertEqual(snapshot.currentWeekStreak, 3)
        XCTAssertEqual(snapshot.bestWeekStreak, 3)
    }

    func testStreakBreaksOnAMissedWeek() {
        let snapshot = build([trip(daysAgo: 0), trip(daysAgo: 21), trip(daysAgo: 28), trip(daysAgo: 35)])
        XCTAssertEqual(snapshot.currentWeekStreak, 1)
        XCTAssertEqual(snapshot.bestWeekStreak, 3)
    }

    func testNightDrivesMakeANightOwl() {
        let snapshot = build((1...4).map { trip(daysAgo: Double($0), hour: 23, km: 12) })
        XCTAssertEqual(snapshot.archetype?.title, "Night-owl Commuter")
    }

    func testArchetypeNeedsAFewDrives() {
        XCTAssertNil(build([trip(daysAgo: 1), trip(daysAgo: 2)]).archetype)
    }

    func testPassengerLegsAreNotYourStats() {
        let snapshot = build([trip(daysAgo: 1, km: 10), trip(daysAgo: 2, km: 500, role: .passenger)])
        XCTAssertEqual(snapshot.lifetimeDrives, 1)
        XCTAssertEqual(snapshot.records.first { $0.kind == .longest }?.value, "10.0")
    }

    func testRentalDrivesCountAsYourDrivingButNotYourCar() {
        let rental = trip(daysAgo: 2, km: 120, role: .otherCar)
        XCTAssertTrue(rental.countsAsDriven)
        XCTAssertFalse(rental.countsOnVehicle)
        let snapshot = build([trip(daysAgo: 1, km: 10), rental])
        XCTAssertEqual(snapshot.lifetimeDrives, 2)
        XCTAssertEqual(snapshot.records.first { $0.kind == .longest }?.value, "120")
    }

    func testRollingWindowIgnoresCalendarMonth() {
        // 25 days ago is last month, but still inside the rolling 30 days.
        let snapshot = build([trip(daysAgo: 25, km: 40), trip(daysAgo: 45, km: 20)])
        XCTAssertEqual(snapshot.last30Km, 40)
        XCTAssertEqual(snapshot.prev30Km, 20)
        XCTAssertEqual(snapshot.last30Drives, 1)
    }

    func testHeatmapCoversEighteenFullWeeksUpToToday() {
        let snapshot = build([trip(daysAgo: 0, km: 30), trip(daysAgo: 3, km: 5)])
        XCTAssertEqual(snapshot.heatWeeks.count, DriverProfileSnapshot.heatmapWeeks)
        XCTAssertTrue(snapshot.heatWeeks.allSatisfy { $0.count == 7 })
        let days = snapshot.heatWeeks.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(days.filter(\.isToday).first?.level, 4)
        XCTAssertEqual(snapshot.activeDaysInWindow, 2)
        // Days after today stay empty rather than rendering as "no drive".
        XCTAssertNil(snapshot.heatWeeks.last?.last ?? nil)
    }

    func testTypicalDriveIsTheMedianNotTheMean() {
        // Two long road trips must not turn a 10 km commuter into a cruiser.
        let trips = [10, 10, 10, 200, 300].enumerated().map { trip(daysAgo: Double($0.offset + 1), hour: 8, km: Double($0.element)) }
        let archetype = build(trips).archetype
        XCTAssertEqual(archetype?.title, "Early-bird Commuter")
        XCTAssertTrue(archetype?.reason.hasSuffix("typical drive 10.0 km") == true)
    }

    func testLifetimeDistanceNeverSubtractsOneCarsOdometerFromAnother() {
        func log(_ car: String, _ odo: Double, daysAgo: Double) -> FuelLog {
            FuelLog(
                id: UUID().uuidString, vehicleId: car, timestamp: now.addingTimeInterval(-daysAgo * 86_400),
                odometerReading: odo, fuelVolume: 40, pricePerUnit: 3, totalCost: 120,
                currency: "AED", isFullTank: true
            )
        }
        // Car A drove 1,000 km between fills, car B 500 km. Their odometers are far apart.
        let logs = [log("a", 38_000, daysAgo: 100), log("b", 60_000, daysAgo: 90),
                    log("a", 39_000, daysAgo: 10), log("b", 60_500, daysAgo: 5)]
        let total = InsightGenerator.totalKilometersDriven(trips: [], logs: logs, vehicleId: nil)
        XCTAssertEqual(total, 1_500)
    }
}
