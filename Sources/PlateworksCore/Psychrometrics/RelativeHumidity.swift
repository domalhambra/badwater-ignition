import Foundation

/// The result of a psychrometric relative-humidity computation.
public struct HumidityResult: Sendable, Equatable, Codable {
    /// Relative humidity, rounded to a whole percent (0–100).
    public let relativeHumidity: Int
    /// Dew-point temperature, rounded to a whole °F.
    public let dewPointF: Int
    /// Wet-bulb depression (dry-bulb − wet-bulb), °F.
    public let wetBulbDepressionF: Int
    /// The elevation band used for the station pressure.
    public let elevationBand: ElevationBand
}

/// Computes relative humidity and dew point from dry-bulb and wet-bulb
/// temperatures and site elevation — the NWCG belt-weather-kit / sling
/// psychrometer method (PMS 437).
///
/// This is a physically-based implementation of the sling-psychrometer
/// relationship (Ferrel coefficient — the standard form for the whirled/sling
/// psychrometer used in belt weather kits) parameterized by the band's station
/// pressure, chosen over transcribing the multi-thousand-cell printed booklets.
/// It has been validated cell-by-cell against the printed PMS 437 tables and
/// matched exactly at every point checked (RH 3–94%, dry bulb 40–80 °F, dew
/// points −21 to 66 °F, at both 30 inHg and 27 inHg) — see the golden cases in
/// `PsychrometricsTests`. Accuracy is best in the fire-weather-relevant warm/dry
/// range; operational users should still cross-check against their belt kit.
public enum Psychrometrics {

    /// Inches of mercury → hectopascals.
    static let inHgToHectopascals = 33.86389

    /// Saturation vapor pressure over water (hPa) for a temperature in °C,
    /// via Bolton (1980).
    static func saturationVaporPressure(celsius t: Double) -> Double {
        6.112 * exp((17.67 * t) / (t + 243.5))
    }

    static func fahrenheitToCelsius(_ f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
    static func celsiusToFahrenheit(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }

    /// Compute relative humidity and dew point.
    ///
    /// - Parameters:
    ///   - dryBulbF: dry-bulb temperature, °F.
    ///   - wetBulbF: wet-bulb temperature, °F (clamped to ≤ dry-bulb).
    ///   - band: elevation band supplying the station pressure.
    public static func compute(dryBulbF: Double, wetBulbF: Double, band: ElevationBand) -> HumidityResult {
        // A non-finite temperature is not a reading. Without this it would trap
        // anyway — but incidentally, at the Int conversions below, after NaN had
        // already slipped through the min/max clamps (which don't propagate NaN)
        // into a plausible-looking RH of 100. Fail loudly and by name instead.
        // Neither shipping surface can reach this: the app calls the Int
        // overloads and the web twin's inputs are integer steppers.
        precondition(dryBulbF.isFinite && wetBulbF.isFinite,
                     "Psychrometrics.compute requires finite temperatures")
        let wet = min(wetBulbF, dryBulbF)   // wet bulb cannot exceed dry bulb
        let tDryC = fahrenheitToCelsius(dryBulbF)
        let tWetC = fahrenheitToCelsius(wet)
        let pressureHPa = band.stationPressureInHg * inHgToHectopascals

        let esDry = saturationVaporPressure(celsius: tDryC)
        let esWet = saturationVaporPressure(celsius: tWetC)

        // Sling-psychrometer equation with the Ferrel psychrometer constant
        // (6.60e-4 /°C) and the standard wet-bulb temperature correction term.
        let psychrometerConstant = 0.000660 * (1.0 + 0.00115 * tWetC)
        var vaporPressure = esWet - psychrometerConstant * pressureHPa * (tDryC - tWetC)
        if vaporPressure < 0.01 { vaporPressure = 0.01 }   // keep dew point finite

        let rh = max(0.0, min(100.0, 100.0 * vaporPressure / esDry))

        // Invert Bolton to recover dew point from the vapor pressure.
        //
        // No clamp to the dry bulb is needed here, and deliberately none is
        // applied. The dew point provably cannot exceed the dry bulb: `wet` is
        // clamped to <= dryBulbF above, saturation vapor pressure is monotonic in
        // temperature (so esWet <= esDry), and the psychrometer term subtracted
        // from it is non-negative (tDryC >= tWetC) — therefore
        // vaporPressure <= esWet <= esDry, and dewPointC <= tDryC. At saturation
        // the Bolton inversion returns the dry bulb exactly, algebraically.
        //
        // `PsychrometricsTests.testDewPointNeverExceedsDryBulb` pins this across
        // the full 10-130 F input range and every band. A defensive `min(...)`
        // here would be unreachable code that *masked* a future break in the
        // wet-bulb clamp instead of letting that test fail loudly.
        let ratio = log(vaporPressure / 6.112)
        let dewPointC = (243.5 * ratio) / (17.67 - ratio)
        let dewPointF = celsiusToFahrenheit(dewPointC)

        return HumidityResult(
            relativeHumidity: Int(rh.rounded()),
            dewPointF: Int(dewPointF.rounded()),
            wetBulbDepressionF: Int((dryBulbF - wet).rounded()),
            elevationBand: band
        )
    }

    /// Convenience overload taking whole-degree inputs and an explicit band.
    public static func compute(dryBulbF: Int, wetBulbF: Int, band: ElevationBand) -> HumidityResult {
        compute(dryBulbF: Double(dryBulbF), wetBulbF: Double(wetBulbF), band: band)
    }

    /// Convenience overload taking whole-degree inputs and a site elevation.
    public static func compute(dryBulbF: Int, wetBulbF: Int, elevationFeet: Int, alaska: Bool = false) -> HumidityResult {
        compute(
            dryBulbF: Double(dryBulbF),
            wetBulbF: Double(wetBulbF),
            band: ElevationBand.forElevation(feetMSL: elevationFeet, alaska: alaska)
        )
    }
}
