import XCTest
@testable import PlateworksCore

final class IgnitionChainTests: XCTestCase {

    /// End-to-end worked example (daytime).
    ///
    /// 95 °F, 12% RH, July, 1400–1559, South aspect, 0–30% slope, level with
    /// the weather site:
    /// - Reference fuel moisture (Table A, 90-109 × 10-14) = 2
    /// - Unshaded correction (Table B, S/0-30, 1400-1559/L) = 0 → FFM 2
    ///   → PIG (90-99 × 2, unshaded) = 100
    /// - Shaded correction (Table B, S, 1400-1559/L) = 3 → FFM 5
    ///   → PIG (90-99 × 5, shaded) = 70
    func testDaytimeWorkedExample() {
        let input = IgnitionInput(
            dryBulbF: 95, relativeHumidity: 12, month: 7,
            timeOfDay: .band1400_1559, aspect: .south, slope: .gentle,
            elevationDelta: .level)
        let e = IgnitionCalculator.estimate(input)

        XCTAssertEqual(e.referenceFuelMoisture, 2)
        XCTAssertFalse(e.isNight)

        XCTAssertEqual(e.unshaded.correction, 0)
        XCTAssertEqual(e.unshaded.fineFuelMoisture, 2)
        XCTAssertEqual(e.unshaded.probabilityOfIgnition, 100)

        XCTAssertEqual(e.shaded.correction, 3)
        XCTAssertEqual(e.shaded.fineFuelMoisture, 5)
        XCTAssertEqual(e.shaded.probabilityOfIgnition, 70)
    }

    /// The internal chain is always self-consistent for daytime inputs.
    func testChainConsistencyDaytime() {
        let input = IgnitionInput(
            dryBulbF: 78, relativeHumidity: 33, month: 3,
            timeOfDay: .band1000_1159, aspect: .east, slope: .steep,
            elevationDelta: .above)
        let e = IgnitionCalculator.estimate(input)
        for shading in Shading.allCases {
            let s = e.estimate(for: shading)
            XCTAssertNotNil(s.correction)
            XCTAssertEqual(s.fineFuelMoisture, e.referenceFuelMoisture + (s.correction ?? -999))
            XCTAssertEqual(
                s.probabilityOfIgnition,
                ProbabilityOfIgnitionTable.probabilityOfIgnition(
                    dryBulbF: input.dryBulbF, fineFuelMoisture: s.fineFuelMoisture, shading: shading))
        }
    }

    /// Nighttime uses the "+5" rule and skips the correction table.
    func testNighttimeRule() {
        let input = IgnitionInput(
            dryBulbF: 95, relativeHumidity: 12, month: 7,
            timeOfDay: .night, aspect: .south, slope: .gentle,
            elevationDelta: .level)
        let e = IgnitionCalculator.estimate(input)

        XCTAssertTrue(e.isNight)
        XCTAssertNil(e.unshaded.correction)
        XCTAssertNil(e.shaded.correction)
        // Reference fuel moisture 2 → nighttime FFM 7 for both shading cases.
        XCTAssertEqual(e.referenceFuelMoisture, 2)
        XCTAssertEqual(e.unshaded.fineFuelMoisture, 7)
        XCTAssertEqual(e.shaded.fineFuelMoisture, 7)
    }

    /// The interpretation mapping covers the full 0–100 range with no gap.
    func testInterpretationCoverage() {
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 0), .veryLow)
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 10), .low)
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 20), .medium)
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 40), .high)
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 70), .veryHigh)  // gap resolved
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 80), .extreme)
        XCTAssertEqual(FireBehaviorInterpretation.interpretation(forPIG: 100), .extreme)
    }
}
