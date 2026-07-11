import XCTest
@testable import BadwaterCore

final class CorrectionTableTests: XCTestCase {

    func testGridDimensions() {
        for group in MonthGroup.allCases {
            let unshaded = FuelMoistureCorrectionTable.unshadedGrid(for: group)
            let shaded = FuelMoistureCorrectionTable.shadedGrid(for: group)
            XCTAssertEqual(unshaded.count, 8, "\(group) unshaded rows")
            XCTAssertEqual(shaded.count, 4, "\(group) shaded rows")
            for row in unshaded { XCTAssertEqual(row.count, 18, "\(group) unshaded cols") }
            for row in shaded { XCTAssertEqual(row.count, 18, "\(group) shaded cols") }
        }
    }

    func testRowAndColumnIndexing() {
        XCTAssertEqual(FuelMoistureCorrectionTable.unshadedRow(aspect: .north, slope: .gentle), 0)
        XCTAssertEqual(FuelMoistureCorrectionTable.unshadedRow(aspect: .north, slope: .steep), 1)
        XCTAssertEqual(FuelMoistureCorrectionTable.unshadedRow(aspect: .south, slope: .gentle), 4)
        XCTAssertEqual(FuelMoistureCorrectionTable.unshadedRow(aspect: .west, slope: .steep), 7)
        XCTAssertEqual(FuelMoistureCorrectionTable.shadedRow(aspect: .east), 1)
        XCTAssertEqual(FuelMoistureCorrectionTable.column(timeBandIndex: 0, elevationDelta: .below), 0)
        XCTAssertEqual(FuelMoistureCorrectionTable.column(timeBandIndex: 3, elevationDelta: .level), 10)
        XCTAssertEqual(FuelMoistureCorrectionTable.column(timeBandIndex: 5, elevationDelta: .above), 17)
    }

    func testNightReturnsNil() {
        let c = FuelMoistureCorrectionTable.correction(
            monthGroup: .tableB, shading: .unshaded, aspect: .north,
            slope: .gentle, timeOfDay: .night, elevationDelta: .level)
        XCTAssertNil(c)
    }

    /// Golden corner cells (IRPG Tables B and D, pp. 46 & 48).
    func testGoldenCells() {
        // Table B, unshaded, N/0-30, 0800-0959 / B → 2.
        XCTAssertEqual(FuelMoistureCorrectionTable.correction(
            monthGroup: .tableB, shading: .unshaded, aspect: .north,
            slope: .gentle, timeOfDay: .band0800_0959, elevationDelta: .below), 2)
        // Table D, shaded, N, 1200-1359 / A → 6 (winter shaded is uniform 4/5/6).
        XCTAssertEqual(FuelMoistureCorrectionTable.correction(
            monthGroup: .tableD, shading: .shaded, aspect: .north,
            slope: .gentle, timeOfDay: .band1200_1359, elevationDelta: .above), 6)
    }

    func testAsteriskMetadata() {
        // The asterisk is on Shaded / 0800-0959 / L in every table.
        XCTAssertTrue(FuelMoistureCorrectionTable.hasAsterisk(shading: .shaded, row: 0, column: 1))
        XCTAssertFalse(FuelMoistureCorrectionTable.hasAsterisk(shading: .unshaded, row: 0, column: 1))
        XCTAssertFalse(FuelMoistureCorrectionTable.hasAsterisk(shading: .shaded, row: 0, column: 0))
    }
}
