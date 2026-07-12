import Foundation
import Observation
import BadwaterCore

// `RHSource` (direct / wetBulb) now lives in BadwaterCore so logged observations
// can record how their humidity was measured.

/// View model for the Ignition (PIG / FFM) screen.
///
/// Temperature and humidity are the fast-changing inputs; the site factors
/// (aspect, slope, elevation delta) persist between launches because they don't
/// change while a crew works the same piece of line. Month and time-of-day
/// pre-fill from the device clock and can be overridden for forecasts.
///
/// Relative humidity is either typed directly or derived from a wet-bulb
/// temperature via the NWCG psychrometric method (see ``rhSource`` and
/// ``effectiveRelativeHumidity``). Every property change recomputes ``estimate``
/// synchronously — the screen has no "Calculate" button. All computation is
/// local and offline.
@Observable
final class IgnitionModel {
    var dryBulbF: Int { didSet { clampWet(); persist() } }
    /// RH typed directly (Kestrel). Used when ``rhSource`` is ``RHSource/direct``.
    var relativeHumidity: Int { didSet { persist() } }
    /// Wet-bulb temperature (°F) for the sling-psychrometer RH derivation.
    var wetBulbF: Int { didSet { persist() } }
    /// Elevation band supplying the station pressure for the RH derivation.
    var elevationBand: ElevationBand { didSet { persist() } }
    /// Whether RH is typed directly or derived from the wet bulb.
    var rhSource: RHSource { didSet { persist() } }
    var month: Int { didSet { persist() } }
    var timeOfDay: TimeOfDay { didSet { persist() } }
    var aspect: Aspect { didSet { persist() } }
    var slope: Slope { didSet { persist() } }
    var elevationDelta: ElevationDelta { didSet { persist() } }

    private let store: UserDefaults

    init(store: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) {
        self.store = store
        let comps = calendar.dateComponents([.month, .hour, .minute], from: now)
        // Fast inputs start at sensible mid-range defaults.
        dryBulbF = store.object(forKey: Keys.dryBulb) as? Int ?? 75
        relativeHumidity = store.object(forKey: Keys.rh) as? Int ?? 20
        // Humidity source and its wet-bulb inputs persist between launches.
        wetBulbF = store.object(forKey: Keys.wetBulb) as? Int ?? 60
        elevationBand = ElevationBand(rawValue: store.object(forKey: Keys.band) as? Int ?? 3) ?? .band3
        rhSource = RHSource(rawValue: store.string(forKey: Keys.rhSource) ?? "") ?? .direct
        // Month / time pre-fill from the clock unless previously overridden this session.
        month = comps.month ?? 7
        timeOfDay = TimeOfDay.from(hour: comps.hour ?? 12, minute: comps.minute ?? 0)
        // Persisted site factors.
        aspect = Aspect(rawValue: store.string(forKey: Keys.aspect) ?? "") ?? .south
        slope = Slope(rawValue: store.string(forKey: Keys.slope) ?? "") ?? .gentle
        elevationDelta = ElevationDelta(rawValue: store.string(forKey: Keys.elevation) ?? "") ?? .level
        clampWet()
    }

    /// The relative humidity actually used by the calculation: typed directly
    /// (``RHSource/direct``), or derived from the wet bulb via the NWCG
    /// psychrometric method (``RHSource/wetBulb``).
    var effectiveRelativeHumidity: Int {
        switch rhSource {
        case .direct:
            return relativeHumidity
        case .wetBulb:
            return Psychrometrics.compute(dryBulbF: dryBulbF, wetBulbF: wetBulbF, band: elevationBand)
                .relativeHumidity
        }
    }

    /// The live estimate for the current inputs (both shaded and unshaded).
    var estimate: IgnitionEstimate {
        IgnitionCalculator.estimate(
            IgnitionInput(
                dryBulbF: dryBulbF, relativeHumidity: effectiveRelativeHumidity, month: month,
                timeOfDay: timeOfDay, aspect: aspect, slope: slope, elevationDelta: elevationDelta))
    }

    /// Seed RH coming from the Humidity screen ("Use in ignition calc"). The
    /// pushed value is a concrete percentage, so it lands as a direct entry.
    func applyHumidity(_ rh: Int) {
        rhSource = .direct
        relativeHumidity = min(max(rh, 0), 100)
    }

    /// The wet bulb cannot read hotter than the dry bulb.
    private func clampWet() { if wetBulbF > dryBulbF { wetBulbF = dryBulbF } }

    private func persist() {
        // didSet does not fire during init, so this only runs on user edits.
        store.set(dryBulbF, forKey: Keys.dryBulb)
        store.set(relativeHumidity, forKey: Keys.rh)
        store.set(wetBulbF, forKey: Keys.wetBulb)
        store.set(elevationBand.rawValue, forKey: Keys.band)
        store.set(rhSource.rawValue, forKey: Keys.rhSource)
        store.set(aspect.rawValue, forKey: Keys.aspect)
        store.set(slope.rawValue, forKey: Keys.slope)
        store.set(elevationDelta.rawValue, forKey: Keys.elevation)
    }

    private enum Keys {
        static let dryBulb = "ignition.dryBulbF"
        static let rh = "ignition.rh"
        static let wetBulb = "ignition.wetBulbF"
        static let band = "ignition.elevationBand"
        static let rhSource = "ignition.rhSource"
        static let aspect = "ignition.aspect"
        static let slope = "ignition.slope"
        static let elevation = "ignition.elevationDelta"
    }
}

extension Month {
    /// Short month names for the month picker.
    static let shortNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

/// Namespace for month helpers used by the picker.
enum Month {}
