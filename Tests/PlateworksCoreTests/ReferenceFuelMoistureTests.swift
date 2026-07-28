import XCTest
@testable import PlateworksCore

final class ReferenceFuelMoistureTests: XCTestCase {

    func testGridDimensions() {
        XCTAssertEqual(ReferenceFuelMoistureTable.grid.count, 6)
        for row in ReferenceFuelMoistureTable.grid {
            XCTAssertEqual(row.count, 21)
        }
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureBands.count, 6)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityBands.count, 21)
    }

    func testTemperatureBanding() {
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 15), 0)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 29), 0)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 30), 1)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 69), 2)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 89), 3)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 90), 4)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 109), 4)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 110), 5)
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 130), 5)
        // Below-table clamps to first row.
        XCTAssertEqual(ReferenceFuelMoistureTable.temperatureRow(forDryBulbF: 5), 0)
    }

    func testHumidityBanding() {
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 0), 0)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 4), 0)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 5), 1)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 24), 4)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 25), 5)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 99), 19)
        XCTAssertEqual(ReferenceFuelMoistureTable.humidityColumn(forRH: 100), 20)
    }

    /// Golden corner and interior cells (IRPG Table A, p. 45).
    func testGoldenCells() {
        // Coolest band, driest → 1; wettest → 14.
        XCTAssertEqual(ReferenceFuelMoistureTable.referenceFuelMoisture(dryBulbF: 20, relativeHumidity: 2), 1)
        XCTAssertEqual(ReferenceFuelMoistureTable.referenceFuelMoisture(dryBulbF: 20, relativeHumidity: 100), 14)
        // Hottest band at 100% RH → 12.
        XCTAssertEqual(ReferenceFuelMoistureTable.referenceFuelMoisture(dryBulbF: 115, relativeHumidity: 100), 12)
        // A common field value: 95 °F, 12% RH → 2.
        XCTAssertEqual(ReferenceFuelMoistureTable.referenceFuelMoisture(dryBulbF: 95, relativeHumidity: 12), 2)
    }
}
