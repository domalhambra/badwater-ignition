import XCTest
@testable import BadwaterCore

/// The GPS site-elevation normalization rule. This feeds ``ElevationBand``,
/// which feeds the station pressure, which feeds the sling RH derivation — so a
/// wrong elevation here is a wrong Probability of Ignition downstream.
final class SiteElevationTests: XCTestCase {

    // MARK: - Rounding to the nearest 100 ft

    func testRoundsToNearestHundredFeet() {
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 5657), 5700)
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 5649), 5600)
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 4150), 4200)
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 100), 100)
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 0), 0)
    }

    func testTiesRoundAwayFromZero() {
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 5650), 5700)
        XCTAssertEqual(SiteElevation.rounded(feetMSL: 50), 100)
        XCTAssertEqual(SiteElevation.rounded(feetMSL: -250), -300)
    }

    /// Badwater Basin is −282 ft. The app is named after it; a below-sea-level
    /// site has to survive the rounding path intact.
    func testBelowSeaLevelElevationsRoundAndBand() {
        XCTAssertEqual(SiteElevation.rounded(feetMSL: -282), -300)
        // ...and still clamp into band 1, per ElevationBand's documented behavior.
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: -300), .band1)
    }

    /// Rounding is **not** band-neutral: every band top (500, 1,900, 3,900,
    /// 6,100, 8,500) is a multiple of 100, so a raw elevation 1–49 ft above one
    /// rounds down onto it and lands a band low. This pins that it happens, and
    /// only there.
    func testRoundingCanShiftTheBandOnlyOntoABandTop() {
        let bandTops: Set<Int> = [500, 1900, 3900, 6100, 8500]
        var shifted = 0
        for raw in -1400...11_500 {
            guard let snapped = SiteElevation.rounded(feetMSL: Double(raw)) else {
                return XCTFail("plausible elevation \(raw) was rejected")
            }
            guard ElevationBand.forElevation(feetMSL: snapped)
                    != ElevationBand.forElevation(feetMSL: raw) else { continue }
            shifted += 1
            XCTAssertTrue(bandTops.contains(snapped),
                "rounding \(raw) → \(snapped) changed the band away from a band top")
        }
        // 49 raw values above each of the five band tops.
        XCTAssertEqual(shifted, 245)
    }

    /// The containment guarantee the app relies on: every elevation whose band
    /// the rounding could have shifted is reported as straddling a boundary, so
    /// the crew is told to confirm it by map rather than trusting the fix.
    func testEveryBandShiftingRoundingIsFlaggedAsStraddling() {
        for raw in -1400...11_500 {
            guard let snapped = SiteElevation.rounded(feetMSL: Double(raw)) else {
                return XCTFail("plausible elevation \(raw) was rejected")
            }
            guard ElevationBand.forElevation(feetMSL: snapped)
                    != ElevationBand.forElevation(feetMSL: raw) else { continue }
            XCTAssertTrue(
                SiteElevation.straddlesBandBoundary(
                    feetMSL: snapped,
                    uncertaintyFeet: SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: nil)),
                "rounding \(raw) → \(snapped) shifted the band without flagging a straddle")
        }
    }

    // MARK: - Effective uncertainty

    func testEffectiveUncertaintyFloorsAtTheRoundingSlop() {
        // An unstated or nonsense accuracy still carries the rounding's own ±50.
        XCTAssertEqual(SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: nil), 50)
        XCTAssertEqual(SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: -1), 50)
        XCTAssertEqual(SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: .nan), 50)
        XCTAssertEqual(SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: 10), 50)
        // A worse-than-rounding fix reports its own accuracy, rounded up.
        XCTAssertEqual(SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: 164), 164)
        XCTAssertEqual(SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: 80.2), 81)
    }

    // MARK: - Rejecting readings that aren't sites

    func testRejectsNonFiniteAndImplausibleReadings() {
        XCTAssertNil(SiteElevation.rounded(feetMSL: .nan))
        XCTAssertNil(SiteElevation.rounded(feetMSL: .infinity))
        XCTAssertNil(SiteElevation.rounded(feetMSL: -.infinity))
        XCTAssertNil(SiteElevation.rounded(feetMSL: -50_000))
        XCTAssertNil(SiteElevation.rounded(feetMSL: 1_000_000))
        // A Double far past Int's range must be rejected, not trap.
        XCTAssertNil(SiteElevation.rounded(feetMSL: 1e30))
    }

    // MARK: - Meters → feet

    func testConvertsSensorMetersToFeet() {
        // CoreLocation reports altitude in meters; 1724 m ≈ 5656.2 ft → 5700.
        XCTAssertEqual(SiteElevation.roundedFeet(fromMeters: 1724), 5700)
        XCTAssertEqual(SiteElevation.roundedFeet(fromMeters: 0), 0)
        // Badwater Basin, −86 m ≈ −282 ft.
        XCTAssertEqual(SiteElevation.roundedFeet(fromMeters: -86), -300)
    }

    func testRejectsNonFiniteSensorAltitude() {
        XCTAssertNil(SiteElevation.feet(fromMeters: .nan))
        XCTAssertNil(SiteElevation.roundedFeet(fromMeters: .nan))
        XCTAssertNil(SiteElevation.roundedFeet(fromMeters: .infinity))
    }

    // MARK: - Band-boundary straddling

    func testStraddleDetectionMatchesTheRealBanding() {
        // 1,900/1,901 ft is the band2/band3 edge: a ±100 ft fix spans it.
        XCTAssertTrue(SiteElevation.straddlesBandBoundary(feetMSL: 1900, uncertaintyFeet: 100))
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 1800), .band2)
        XCTAssertEqual(ElevationBand.forElevation(feetMSL: 2000), .band3)
    }

    func testMidBandFixDoesNotStraddle() {
        // 3,000 ft sits mid-band3 (1,901–3,900); even a coarse fix stays inside.
        XCTAssertFalse(SiteElevation.straddlesBandBoundary(feetMSL: 3000, uncertaintyFeet: 300))
    }

    func testZeroOrNegativeUncertaintyNeverStraddles() {
        XCTAssertFalse(SiteElevation.straddlesBandBoundary(feetMSL: 1900, uncertaintyFeet: 0))
        XCTAssertFalse(SiteElevation.straddlesBandBoundary(feetMSL: 1900, uncertaintyFeet: -50))
    }

    func testStraddleHonorsAlaskaThresholds() {
        // Alaska's band2/band3 edge is 1,700/1,701 — not CONUS's 1,900/1,901.
        XCTAssertTrue(SiteElevation.straddlesBandBoundary(
            feetMSL: 1700, uncertaintyFeet: 100, alaska: true))
        XCTAssertFalse(SiteElevation.straddlesBandBoundary(
            feetMSL: 1700, uncertaintyFeet: 100, alaska: false))
    }
}

/// Coordinate validation — a transposed or half-typed coordinate must never be
/// frozen onto an observation and read out on the radio net.
final class GeoPointValidationTests: XCTestCase {

    func testAcceptsRealCoordinates() {
        XCTAssertNotNil(GeoPoint(validating: 38.21437, longitude: -112.3978))
        XCTAssertNotNil(GeoPoint(validating: 0, longitude: 0))
        XCTAssertNotNil(GeoPoint(validating: 90, longitude: 180))
        XCTAssertNotNil(GeoPoint(validating: -90, longitude: -180))
    }

    func testRejectsOutOfRangeCoordinates() {
        XCTAssertNil(GeoPoint(validating: 91, longitude: 0))
        XCTAssertNil(GeoPoint(validating: -91, longitude: 0))
        XCTAssertNil(GeoPoint(validating: 0, longitude: 181))
        XCTAssertNil(GeoPoint(validating: 0, longitude: -181))
        // A latitude/longitude transposition that only the range check catches.
        XCTAssertNil(GeoPoint(validating: -112.3978, longitude: 38.21437))
    }

    func testRejectsNonFiniteCoordinates() {
        XCTAssertNil(GeoPoint(validating: .nan, longitude: 0))
        XCTAssertNil(GeoPoint(validating: 0, longitude: .nan))
        XCTAssertNil(GeoPoint(validating: .infinity, longitude: 0))
    }

    func testValidationDoesNotChangeRendering() {
        let p = GeoPoint(validating: 38.21437, longitude: -112.3978)
        XCTAssertEqual(p?.rendered, "38.21437, -112.3978")
    }
}
