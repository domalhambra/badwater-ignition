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

    func testDewPointNeverExceedsDryBulb() {
        for dry in stride(from: 40, through: 110, by: 10) {
            for depression in 0...30 {
                let r = Psychrometrics.compute(dryBulbF: dry, wetBulbF: dry - depression, band: .band3)
                XCTAssertLessThanOrEqual(r.dewPointF, dry + 1)
            }
        }
    }

    /// Sanity band for a common observation. 90 °F dry / 70 °F wet near sea
    /// level lands around 40% RH in the NWCG tables; assert a tolerant range
    /// pending cell-exact validation against the printed PMS 437 booklets.
    func testReferenceObservationInRange() {
        let r = Psychrometrics.compute(dryBulbF: 90, wetBulbF: 70, band: .band1)
        XCTAssert((36...46).contains(r.relativeHumidity),
                  "RH \(r.relativeHumidity)% outside expected ~40% band")
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
