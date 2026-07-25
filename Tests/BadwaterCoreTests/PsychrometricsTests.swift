import XCTest
@testable import BadwaterCore

final class PsychrometricsTests: XCTestCase {

    func testSaturatedAirIsHundredPercent() {
        // Wet bulb equal to dry bulb → saturated → 100% RH, dew point ≈ dry bulb.
        let r = Psychrometrics.compute(dryBulbF: 75, wetBulbF: 75, band: .band1)
        XCTAssertEqual(r.relativeHumidity, 100)
        XCTAssertEqual(r.dewPointF, 75, accuracy: 1)
    }

    func testHumidityFallsWithWetBulbDepression() {
        var previous = 101
        for wet in stride(from: 90, through: 55, by: -5) {
            let r = Psychrometrics.compute(dryBulbF: 90, wetBulbF: wet, band: .band1)
            XCTAssertLessThan(r.relativeHumidity, previous,
                "RH did not fall as wet-bulb depression grew (wet \(wet))")
            previous = r.relativeHumidity
        }
    }

    /// The dew point can never exceed the dry bulb — asserted **exactly**, with
    /// no tolerance, across the app's whole input range and every band.
    ///
    /// This used to allow `dry + 1`, which quietly masked whether the invariant
    /// actually held. It does hold, and provably: `wetBulbF` is clamped to
    /// ≤ `dryBulbF`, saturation vapor pressure is monotonic in temperature (so
    /// `esWet ≤ esDry`), and the psychrometer term subtracted from it is
    /// non-negative — therefore `vaporPressure ≤ esDry` and `dewPointC ≤ tDryC`.
    ///
    /// Tightening this is what lets `Psychrometrics` carry *no* defensive
    /// `min(dewPoint, dryBulb)` clamp: an unreachable clamp would mask a future
    /// break in the wet-bulb clamp, whereas this test fails loudly on one.
    /// Wet bulbs above the dry bulb are included so the saturation edge — where
    /// the Bolton inversion returns the dry bulb exactly — is covered too.
    func testDewPointNeverExceedsDryBulb() {
        for band in ElevationBand.allCases {
            for dry in stride(from: 10, through: 130, by: 5) {
                for wet in stride(from: 10, through: 135, by: 5) {
                    let r = Psychrometrics.compute(dryBulbF: dry, wetBulbF: wet, band: band)
                    XCTAssertLessThanOrEqual(
                        r.dewPointF, dry,
                        "dew point \(r.dewPointF) exceeded dry bulb \(dry) (wet \(wet), \(band))")
                }
            }
        }
    }

    /// Golden cells transcribed directly from the printed NWCG PMS 437
    /// Temperature / RH / Dew Point tables. Each case is
    /// `(dryBulbF, wetBulbF, band, expectedRH, expectedDewPointF)`.
    ///
    /// These were read cell-by-cell from the published tables (0–500 ft and
    /// 1,901–3,900 ft pages) and matched this implementation exactly at
    /// authoring time across RH 3–94% and dew points from −21 to 66 °F; the
    /// ±1 tolerance guards only against half-unit rounding at the boundaries.
    func testGoldenCellsFromPMS437() {
        let cases: [(Int, Int, ElevationBand, Int, Int)] = [
            // Sea level (0–500 ft, 30 inHg)
            (40, 35, .band1, 60, 27),
            (61, 40, .band1, 3, -21),
            (61, 45, .band1, 23, 23),
            (61, 60, .band1, 94, 59),
            (80, 65, .band1, 44, 56),
            (80, 70, .band1, 61, 65),
            // 1,901–3,900 ft (27 inHg) — validates the station-pressure term
            (80, 70, .band3, 62, 66)
        ]
        for (db, wb, band, expRH, expDP) in cases {
            let r = Psychrometrics.compute(dryBulbF: db, wetBulbF: wb, band: band)
            XCTAssertEqual(r.relativeHumidity, expRH, accuracy: 1,
                "RH mismatch at DB \(db)/WB \(wb) (\(band)): got \(r.relativeHumidity), expected \(expRH)")
            XCTAssertEqual(r.dewPointF, expDP, accuracy: 1,
                "Dew point mismatch at DB \(db)/WB \(wb) (\(band)): got \(r.dewPointF), expected \(expDP)")
        }
    }

    func testElevationBandResolution() {
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 0), .band1)
        // Badwater Basin (−282 ft) clamps to band 1 — the app's namesake.
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: -282), .band1)
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 500), .band1)
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 501), .band2)
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 3900), .band3)
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 12000), .band6)
        // Alaska thresholds are lower.
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 400, alaska: true), .band2)
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 8000, alaska: true), .band6)
    }

    func testStationPressures() {
        XCTAssertEqual(ElevationBand.band1.stationPressureInHg, 30)
        XCTAssertEqual(ElevationBand.band6.stationPressureInHg, 21)
    }
}
