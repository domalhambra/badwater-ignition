import XCTest
@testable import BadwaterCore

final class SensitivityTests: XCTestCase {

    // MARK: - Golden cases (hand-verified against the printed tables)

    /// The IgnitionChain worked example — 95 °F, 12% RH, July, 1400–1559, South,
    /// 0–30%, level — read through the sensitivity lens.
    ///
    /// Unshaded PIG is pinned at 100 and rock-solid: every neighbouring reading
    /// still maxes the table, so it is *firm*. Shaded PIG is 70 (Very High) but a
    /// −3% RH miss (RH 9) drops reference fuel moisture 2→1, FFM 5→4, and shaded
    /// PIG 70→80 — crossing into Extreme. That is exactly the knife-edge the
    /// marker exists to surface.
    func testWorkedExample_unshadedFirm_shadedOnEdge() throws {
        let s = SensitivityAnalysis.analyze(
            dryBulbF: 95, rhSource: .direct, relativeHumidity: 12, wetBulbF: 60,
            band: .band3, month: 7, timeOfDay: .band1400_1559,
            aspect: .south, slope: .gentle, elevationDelta: .level)

        // Unshaded — firm at 100.
        XCTAssertEqual(s.unshaded.baseline, 100)
        XCTAssertEqual(s.unshaded.pigLow, 100)
        XCTAssertEqual(s.unshaded.pigHigh, 100)
        XCTAssertFalse(s.unshaded.crossesBand)
        XCTAssertNil(s.unshaded.notable)

        // Shaded — Very High baseline, plausibly Extreme.
        XCTAssertEqual(s.shaded.baseline, 70)
        XCTAssertEqual(s.shaded.baselineBand, .veryHigh)
        XCTAssertEqual(s.shaded.pigLow, 70)
        XCTAssertEqual(s.shaded.pigHigh, 80)
        XCTAssertTrue(s.shaded.crossesBand)
        XCTAssertEqual(s.shaded.direction, .higher)

        let notable = try XCTUnwrap(s.shaded.notable)
        XCTAssertEqual(notable.pig, 80)
        XCTAssertEqual(notable.band, .extreme)
        // The nearest way into Extreme is a 3-point RH miss; dry bulb unchanged.
        XCTAssertEqual(notable.dryBulbF, 95)
        XCTAssertEqual(notable.relativeHumidity, 9)
        XCTAssertEqual(notable.dryBulbShifted, false)
        XCTAssertEqual(notable.humidityShifted, true)
        XCTAssertEqual(notable.descriptor, "RH 9")
    }

    /// A mid-cell reading well inside its bands: 65 °F, 60% RH. Both dry-bulb and
    /// RH perturbations stay in the same Table A and PIG cells, so PIG never moves
    /// and the reading is firm on both shading conditions.
    func testMidCellReadingIsFirm() {
        let s = SensitivityAnalysis.analyze(
            dryBulbF: 65, rhSource: .direct, relativeHumidity: 60, wetBulbF: 55,
            band: .band3, month: 7, timeOfDay: .band1200_1359,
            aspect: .north, slope: .gentle, elevationDelta: .level)

        for env in [s.unshaded, s.shaded] {
            XCTAssertFalse(env.crossesBand)
            XCTAssertNil(env.notable)
            XCTAssertEqual(env.pigLow, env.baseline)
            XCTAssertEqual(env.pigHigh, env.baseline)
            XCTAssertNil(env.direction)
        }
    }

    // MARK: - Sling mode

    /// In sling mode the baseline PIG is derived through the same psychrometric
    /// path the live screen uses, so the envelope's baseline matches the displayed
    /// value exactly, and the envelope always brackets it.
    func testSlingBaselineMatchesDerivedRHAndBrackets() {
        let dry = 90, wet = 62, band = ElevationBand.band4
        let derivedRH = Psychrometrics.compute(dryBulbF: dry, wetBulbF: wet, band: band).relativeHumidity
        let expected = IgnitionCalculator.estimate(IgnitionInput(
            dryBulbF: dry, relativeHumidity: derivedRH, month: 8, timeOfDay: .band1200_1359,
            aspect: .west, slope: .steep, elevationDelta: .above))

        let s = SensitivityAnalysis.analyze(
            dryBulbF: dry, rhSource: .wetBulb, relativeHumidity: 20, wetBulbF: wet,
            band: band, month: 8, timeOfDay: .band1200_1359,
            aspect: .west, slope: .steep, elevationDelta: .above)

        XCTAssertEqual(s.unshaded.baseline, expected.unshaded.probabilityOfIgnition)
        XCTAssertEqual(s.shaded.baseline, expected.shaded.probabilityOfIgnition)
        for env in [s.unshaded, s.shaded] {
            XCTAssertLessThanOrEqual(env.pigLow, env.baseline)
            XCTAssertGreaterThanOrEqual(env.pigHigh, env.baseline)
        }
    }

    // MARK: - Night rule

    /// The nighttime "+5" path is a step function too; sensitivity flows through
    /// it unchanged (no correction table, FFM = reference + 5).
    func testNighttimeStillAnalyses() {
        let s = SensitivityAnalysis.analyze(
            dryBulbF: 88, rhSource: .direct, relativeHumidity: 14, wetBulbF: 60,
            band: .band3, month: 7, timeOfDay: .night,
            aspect: .south, slope: .gentle, elevationDelta: .level)
        for env in [s.unshaded, s.shaded] {
            XCTAssertLessThanOrEqual(env.pigLow, env.baseline)
            XCTAssertGreaterThanOrEqual(env.pigHigh, env.baseline)
        }
    }

    // MARK: - Properties (scanned across the operating envelope)

    /// Invariants that must hold for every reading in the fire-weather range.
    func testEnvelopeInvariants() {
        var sawHigher = false
        var sawLower = false
        var sawFirm = false

        for dry in stride(from: 40, through: 115, by: 5) {
            for rh in stride(from: 2, through: 95, by: 3) {
                let s = SensitivityAnalysis.analyze(
                    dryBulbF: dry, rhSource: .direct, relativeHumidity: rh, wetBulbF: 60,
                    band: .band3, month: 7, timeOfDay: .band1400_1559,
                    aspect: .south, slope: .gentle, elevationDelta: .level)

                for env in [s.unshaded, s.shaded] {
                    // 1. The envelope always brackets the displayed value.
                    XCTAssertLessThanOrEqual(env.pigLow, env.baseline, "dry \(dry) rh \(rh)")
                    XCTAssertGreaterThanOrEqual(env.pigHigh, env.baseline, "dry \(dry) rh \(rh)")

                    // 2. crossesBand ⇔ notable present.
                    XCTAssertEqual(env.crossesBand, env.notable != nil)

                    if let n = env.notable {
                        // 3. A notable reading is genuinely in a different band…
                        XCTAssertNotEqual(n.band, env.baselineBand)
                        // …and differs from the displayed reading on some axis.
                        XCTAssertTrue(n.dryBulbShifted || n.humidityShifted)

                        // 4. Direction agrees with the PIG and with the endpoints.
                        if n.pig > env.baseline {
                            XCTAssertEqual(env.direction, .higher)
                            XCTAssertEqual(n.pig, env.pigHigh)
                            XCTAssertGreaterThan(n.band.rawValue, env.baselineBand.rawValue)
                            sawHigher = true
                        } else {
                            XCTAssertEqual(env.direction, .lower)
                            XCTAssertEqual(n.pig, env.pigLow)
                            XCTAssertLessThan(n.band.rawValue, env.baselineBand.rawValue)
                            sawLower = true
                        }
                    } else {
                        sawFirm = true
                    }
                }
            }
        }

        // The scan must exercise firm readings, hazardous crossings, and softer
        // crossings — otherwise the branches above aren't really covered.
        XCTAssertTrue(sawFirm, "expected some firm readings")
        XCTAssertTrue(sawHigher, "expected some hazardous-side crossings")
        XCTAssertTrue(sawLower, "expected some softer-side crossings")
    }

    /// Tightening the tolerance to zero collapses the envelope to the baseline —
    /// no perturbation, nothing ever flagged.
    func testZeroToleranceIsAlwaysFirm() {
        let zero = ReadingTolerance(dryBulbF: 0, relativeHumidity: 0, wetBulbF: 0)
        for rh in stride(from: 2, through: 95, by: 7) {
            let s = SensitivityAnalysis.analyze(
                dryBulbF: 95, rhSource: .direct, relativeHumidity: rh, wetBulbF: 60,
                band: .band3, month: 7, timeOfDay: .band1400_1559,
                aspect: .south, slope: .gentle, elevationDelta: .level,
                tolerance: zero)
            XCTAssertFalse(s.unshaded.crossesBand)
            XCTAssertFalse(s.shaded.crossesBand)
            XCTAssertEqual(s.unshaded.pigLow, s.unshaded.pigHigh)
        }
    }
}
