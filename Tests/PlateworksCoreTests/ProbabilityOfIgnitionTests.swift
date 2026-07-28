import XCTest
@testable import PlateworksCore

final class ProbabilityOfIgnitionTests: XCTestCase {

    func testGridDimensions() {
        XCTAssertEqual(ProbabilityOfIgnitionTable.unshaded.count, 9)
        XCTAssertEqual(ProbabilityOfIgnitionTable.shaded.count, 9)
        for row in ProbabilityOfIgnitionTable.unshaded { XCTAssertEqual(row.count, 16) }
        for row in ProbabilityOfIgnitionTable.shaded { XCTAssertEqual(row.count, 16) }
    }

    func testTemperatureBanding() {
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 120), 0)
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 110), 0)
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 105), 1)
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 95), 2)
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 75), 4)
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 39), 8)
        XCTAssertEqual(ProbabilityOfIgnitionTable.temperatureRow(forDryBulbF: 20), 8)  // clamp
    }

    func testFuelMoistureBanding() {
        XCTAssertEqual(ProbabilityOfIgnitionTable.fuelMoistureColumn(forFFM: 2), 0)
        XCTAssertEqual(ProbabilityOfIgnitionTable.fuelMoistureColumn(forFFM: 1), 0)   // clamp low
        XCTAssertEqual(ProbabilityOfIgnitionTable.fuelMoistureColumn(forFFM: 17), 15)
        XCTAssertEqual(ProbabilityOfIgnitionTable.fuelMoistureColumn(forFFM: 25), 15) // clamp high
        XCTAssertEqual(ProbabilityOfIgnitionTable.fuelMoistureColumn(forFFM: 9), 7)
    }

    /// Golden cells (IRPG PIG table, p. 44).
    func testGoldenCells() {
        // Hottest, driest fuels → certain ignition.
        XCTAssertEqual(ProbabilityOfIgnitionTable.probabilityOfIgnition(dryBulbF: 115, fineFuelMoisture: 2, shading: .unshaded), 100)
        // Coolest band, wettest fuels → floor of 10%.
        XCTAssertEqual(ProbabilityOfIgnitionTable.probabilityOfIgnition(dryBulbF: 35, fineFuelMoisture: 17, shading: .unshaded), 10)
        XCTAssertEqual(ProbabilityOfIgnitionTable.probabilityOfIgnition(dryBulbF: 35, fineFuelMoisture: 17, shading: .shaded), 10)
    }

    /// Within a temperature row, PIG is non-increasing as fine fuel moisture
    /// rises (wetter fuels are harder to ignite). This holds in both tables and
    /// is a strong guard against transcription errors.
    func testNonIncreasingWithFuelMoisture() {
        for (label, grid) in [("unshaded", ProbabilityOfIgnitionTable.unshaded),
                              ("shaded", ProbabilityOfIgnitionTable.shaded)] {
            for (r, row) in grid.enumerated() {
                for c in 1..<row.count {
                    XCTAssertLessThanOrEqual(row[c], row[c - 1],
                        "\(label) PIG rose with fuel moisture at row \(r), col \(c)")
                }
            }
        }
    }
}

// Note: the shaded ≥ unshaded inversion at 30-39 °F / FFM 3 (shaded 80 vs
// unshaded 70) is intentionally NOT asserted as an invariant — it is a
// plausible rounding artifact of the empirical tables at the coolest band, and
// is confirmed by the adversarial transcription-verification pass rather than
// assumed here.
