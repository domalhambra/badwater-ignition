import XCTest
@testable import PlateworksCore

final class TimeAndMonthTests: XCTestCase {

    func testTimeOfDayFromClock() {
        XCTAssertEqual(TimeOfDay.from(hour: 8, minute: 0), .band0800_0959)
        XCTAssertEqual(TimeOfDay.from(hour: 9, minute: 59), .band0800_0959)
        XCTAssertEqual(TimeOfDay.from(hour: 12, minute: 30), .band1200_1359)
        XCTAssertEqual(TimeOfDay.from(hour: 19, minute: 59), .band1800_1959)
        XCTAssertEqual(TimeOfDay.from(hour: 20, minute: 0), .night)
        XCTAssertEqual(TimeOfDay.from(hour: 3, minute: 0), .night)
        XCTAssertEqual(TimeOfDay.from(hour: 7, minute: 59), .night)
    }

    func testDaytimeBandColumnOrder() {
        XCTAssertEqual(TimeOfDay.daytimeBands.count, 6)
        for (i, band) in TimeOfDay.daytimeBands.enumerated() {
            XCTAssertEqual(band.correctionColumnIndex, i)
        }
        XCTAssertNil(TimeOfDay.night.correctionColumnIndex)
    }

    func testMonthGroups() {
        XCTAssertEqual(MonthGroup.from(month: 5), .tableB)
        XCTAssertEqual(MonthGroup.from(month: 7), .tableB)
        XCTAssertEqual(MonthGroup.from(month: 3), .tableC)
        XCTAssertEqual(MonthGroup.from(month: 9), .tableC)
        XCTAssertEqual(MonthGroup.from(month: 12), .tableD)
        XCTAssertEqual(MonthGroup.from(month: 1), .tableD)
        XCTAssertTrue(MonthGroup.tableD.isWinter)
        XCTAssertFalse(MonthGroup.tableB.isWinter)
    }
}
