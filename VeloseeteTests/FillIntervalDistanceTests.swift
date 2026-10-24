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

/// Lives here because new test files need an XcodeGen run to join the target.
final class ServiceScheduleTests: XCTestCase {
    private let now = Date()

    private func service(
        _ type: String,
        odo: Double,
        daysAgo: Double,
        nextOdo: Double? = nil,
        nextInDays: Double? = nil
    ) -> ServiceLog {
        ServiceLog(
            id: UUID().uuidString,
            vehicleId: "car",
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            odometerReading: odo,
            serviceType: type,
            description: nil,
            brand: nil,
            cost: nil,
            currency: "QAR",
            nextServiceOdometer: nextOdo,
            nextServiceDate: nextInDays.map { now.addingTimeInterval($0 * 86_400) }
        )
    }

    func testPicksTheMostUrgentReminder() {
        let logs = [
            service("Oil Change", odo: 40_000, daysAgo: 60, nextOdo: 50_000),       // 8,000 km ≈ 200 days
            service("AC Service", odo: 39_000, daysAgo: 300, nextInDays: 20)        // 20 days
        ]
        let next = ServiceSchedule.nextUp(logs: logs, currentKm: 42_000, now: now)
        XCTAssertEqual(next?.log.serviceType, "AC Service")
        XCTAssertEqual(next?.status, .onTrack)
    }

    func testOnlyTheLatestEntryOfATypeCounts() {
        let logs = [
            service("Oil Change", odo: 30_000, daysAgo: 400, nextOdo: 40_000),      // superseded, would be overdue
            service("Oil Change", odo: 40_000, daysAgo: 60, nextOdo: 50_000)
        ]
        let next = ServiceSchedule.nextUp(logs: logs, currentKm: 42_000, now: now)
        XCTAssertEqual(next?.kmLeft ?? 0, 8_000, accuracy: 0.5)
        XCTAssertEqual(next?.progress ?? 0, 0.2, accuracy: 0.001)
    }

    func testOverdueAndDueSoon() {
        let overdue = ServiceSchedule.nextUp(
            logs: [service("Oil Change", odo: 40_000, daysAgo: 60, nextOdo: 42_000)],
            currentKm: 42_300,
            now: now
        )
        XCTAssertEqual(overdue?.status, .overdue)
        XCTAssertEqual(overdue?.progress, 1)

        let soon = ServiceSchedule.nextUp(
            logs: [service("Tire Rotation", odo: 40_000, daysAgo: 60, nextOdo: 42_400)],
            currentKm: 42_000,
            now: now
        )
        XCTAssertEqual(soon?.status, .dueSoon)
    }

    func testNoReminderMeansNoNextUp() {
        XCTAssertNil(ServiceSchedule.nextUp(logs: [service("Wiper Blades", odo: 40_000, daysAgo: 10)], currentKm: 41_000, now: now))
    }

    func testEveryCommonTypeHasAnInterval() {
        for type in ServiceLog.knownTypes where type != "Other" {
            XCTAssertNotNil(ServiceSchedule.suggestedInterval(for: type), type)
        }
        XCTAssertNil(ServiceSchedule.suggestedInterval(for: "Other"))
    }
}
