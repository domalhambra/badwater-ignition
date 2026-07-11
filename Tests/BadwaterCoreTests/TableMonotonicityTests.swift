import XCTest
@testable import BadwaterCore

/// Property tests that hold for the printed IRPG tables and act as an
/// independent guard against transcription errors.
final class TableMonotonicityTests: XCTestCase {

    /// Table A: within each temperature row, reference fuel moisture is
    /// non-decreasing as relative humidity rises (moister air → moister fuel).
    func testReferenceFuelMoistureNonDecreasingWithHumidity() {
        for (r, row) in ReferenceFuelMoistureTable.grid.enumerated() {
            for c in 1..<row.count {
                XCTAssertGreaterThanOrEqual(row[c], row[c - 1],
                    "Table A fell as humidity rose at row \(r), col \(c)")
            }
        }
    }

    /// Reference fuel moisture stays within the physical 1–14% envelope of the
    /// printed table.
    func testReferenceFuelMoistureBounds() {
        for row in ReferenceFuelMoistureTable.grid {
            for v in row { XCTAssert((1...14).contains(v), "RFM \(v) out of range") }
        }
    }

    /// Correction values stay within the printed 0–6 envelope.
    func testCorrectionBounds() {
        for group in MonthGroup.allCases {
            for grid in [FuelMoistureCorrectionTable.unshadedGrid(for: group),
                         FuelMoistureCorrectionTable.shadedGrid(for: group)] {
                for row in grid {
                    for v in row { XCTAssert((0...6).contains(v), "correction \(v) out of range") }
                }
            }
        }
    }

    /// PIG values are always whole decades in 10…100.
    func testProbabilityValuesAreDecades() {
        for grid in [ProbabilityOfIgnitionTable.unshaded, ProbabilityOfIgnitionTable.shaded] {
            for row in grid {
                for v in row {
                    XCTAssert((10...100).contains(v) && v % 10 == 0, "PIG \(v) is not a decade in 10…100")
                }
            }
        }
    }
}
