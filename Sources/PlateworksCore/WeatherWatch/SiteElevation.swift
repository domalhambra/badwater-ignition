import Foundation

/// Normalization for a **site elevation** taken from a device sensor (GPS)
/// rather than typed by the operator.
///
/// This matters more than a display detail: the site elevation selects the
/// ``ElevationBand``, which supplies the station pressure for the sling-RH
/// derivation, which feeds relative humidity into the whole IRPG chain. A
/// GPS-derived elevation that lands in the wrong band produces a wrong RH and
/// therefore a wrong Probability of Ignition.
///
/// Two properties follow from that:
///
/// 1. **Round to 100 ft.** GPS vertical accuracy is far coarser than its
///    horizontal accuracy — routinely ±10–50 m — so a raw `5657 ft` reads as
///    false precision. Rounding to the nearest 100 (`5657 → 5700`) states the
///    value at roughly the honesty of the sensor.
/// 2. **Say when the fix straddles a band edge.** Rounding is *not* band-safe on
///    its own: every band top (500, 1,900, 3,900, 6,100, 8,500 ft) is itself a
///    multiple of 100, so a raw elevation 1–49 ft above one — 1,949 ft, say —
///    rounds *down* onto it and lands one band low.
///
///    That is contained rather than special-cased, because of an invariant worth
///    stating: **whenever rounding changes the band, the rounded value is exactly
///    a band top**, so ``straddlesBandBoundary(feetMSL:uncertaintyFeet:alaska:)``
///    flags it for any positive uncertainty. (Proof: rounding moves a value by at
///    most half an increment, and the only multiple of 100 within that reach of
///    the result is the result itself.) The rule for callers follows: always
///    evaluate the straddle check on the *rounded* value, with an uncertainty of
///    at least ``roundingUncertaintyFeet`` — which is what
///    ``effectiveUncertaintyFeet(sensorAccuracyFeet:)`` returns — and have the
///    crew confirm the elevation by map when it reports `true`.
///
///    `SiteElevationTests` pins both halves: the 245 raw elevations in field
///    range where rounding shifts the band, and the fact that every one of them
///    is flagged.
///
/// Pure and dependency-free: no CoreLocation here, so the rule is golden-tested
/// on Linux CI alongside the tables it protects.
public enum SiteElevation {

    /// GPS elevations are reported to the nearest 100 ft (see the type note).
    public static let roundingIncrementFeet = 100

    /// Exact conversion factor (the international foot).
    public static let feetPerMeter = 3.280839895013123

    /// The range a real site elevation can fall in, in feet MSL — from below the
    /// Dead Sea shore to above Everest. A reading outside this is a bad fix (or a
    /// sensor returning a sentinel), not a site, and is rejected rather than
    /// rounded into something plausible-looking.
    public static let plausibleRangeFeet: ClosedRange<Int> = -1500...30000

    /// Convert a sensor altitude in meters to feet. Returns `nil` for a
    /// non-finite value (CoreLocation reports `nan`/`infinity` when it has no
    /// vertical fix).
    public static func feet(fromMeters meters: Double) -> Double? {
        guard meters.isFinite else { return nil }
        return meters * feetPerMeter
    }

    /// Round a sensor-derived elevation to the nearest ``roundingIncrementFeet``.
    ///
    /// Ties round away from zero (`5650 → 5700`, `-250 → -300`). Returns `nil`
    /// when the value is non-finite or outside ``plausibleRangeFeet`` — the
    /// caller should then fall back to manual entry rather than display a
    /// fabricated elevation.
    ///
    /// - Parameter feetMSL: raw elevation in feet above mean sea level.
    public static func rounded(feetMSL: Double) -> Int? {
        guard feetMSL.isFinite else { return nil }
        let increment = Double(roundingIncrementFeet)
        let snapped = (feetMSL / increment).rounded() * increment
        // Guard the Int conversion before the range check: a huge Double would
        // trap on Int(_:) rather than fail the bounds test.
        guard snapped >= Double(plausibleRangeFeet.lowerBound),
              snapped <= Double(plausibleRangeFeet.upperBound) else { return nil }
        return Int(snapped)
    }

    /// Round a sensor altitude given in **meters** straight to the nearest
    /// hundred feet — the one-call path from a `CLLocation.altitude`.
    public static func roundedFeet(fromMeters meters: Double) -> Int? {
        guard let ft = feet(fromMeters: meters) else { return nil }
        return rounded(feetMSL: ft)
    }

    /// The uncertainty the rounding itself introduces: ±half an increment. Any
    /// band decision made on a rounded elevation carries at least this much
    /// slop, so it is the floor for ``effectiveUncertaintyFeet(sensorAccuracyFeet:)``.
    public static let roundingUncertaintyFeet = roundingIncrementFeet / 2

    /// The ± uncertainty to judge a *rounded* elevation by: the sensor's own
    /// stated vertical accuracy, never less than ``roundingUncertaintyFeet``.
    ///
    /// Pass the result to ``straddlesBandBoundary(feetMSL:uncertaintyFeet:alaska:)``.
    /// Taking the floor is what makes the rounding safe — see the type note.
    ///
    /// - Parameter sensorAccuracyFeet: the fix's vertical accuracy in feet, or
    ///   `nil` when the sensor didn't state one (CoreLocation reports a negative
    ///   `verticalAccuracy` in that case, which is also treated as unstated).
    public static func effectiveUncertaintyFeet(sensorAccuracyFeet: Double?) -> Int {
        guard let accuracy = sensorAccuracyFeet, accuracy.isFinite, accuracy > 0 else {
            return roundingUncertaintyFeet
        }
        // Cap before converting — same trap `rounded(feetMSL:)` guards: a sensor
        // claiming an absurd accuracy must degrade, not crash. 100,000 ft already
        // straddles every band from every plausible elevation, so nothing above
        // it carries more meaning (and, unlike `Int.max`, it can't overflow the
        // ± arithmetic in `straddlesBandBoundary`).
        let cappedFeet = min(accuracy.rounded(.up), 100_000)
        return max(roundingUncertaintyFeet, Int(cappedFeet))
    }

    /// Whether an elevation's uncertainty interval spans two ``ElevationBand``s —
    /// i.e. the fix is not precise enough to pick the station pressure with
    /// confidence, and the crew should confirm the elevation against a map.
    ///
    /// Delegates to ``ElevationBand/forElevation(feetMSL:alaska:)`` rather than
    /// restating the thresholds, so this can never drift from the real banding.
    ///
    /// - Parameters:
    ///   - feetMSL: the elevation in question.
    ///   - uncertaintyFeet: ± vertical uncertainty of the fix, in feet. Zero or
    ///     negative means "no stated uncertainty" and reports `false`.
    ///   - alaska: use the Alaska band thresholds.
    public static func straddlesBandBoundary(
        feetMSL: Int, uncertaintyFeet: Int, alaska: Bool = false
    ) -> Bool {
        guard uncertaintyFeet > 0 else { return false }
        let low = ElevationBand.forElevation(feetMSL: feetMSL - uncertaintyFeet, alaska: alaska)
        let high = ElevationBand.forElevation(feetMSL: feetMSL + uncertaintyFeet, alaska: alaska)
        return low != high
    }
}
