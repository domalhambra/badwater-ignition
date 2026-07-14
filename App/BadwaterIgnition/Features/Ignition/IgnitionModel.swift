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
    var dryBulbF: Int { didSet { clampWet(); touchWeather(); persist() } }
    /// RH typed directly (Kestrel). Used when ``rhSource`` is ``RHSource/direct``.
    var relativeHumidity: Int { didSet { touchWeather(); persist() } }
    /// Wet-bulb temperature (°F) for the sling-psychrometer RH derivation.
    /// Clamped on edit too (not only when the dry bulb drops), so a wet bulb typed
    /// above the dry bulb can't yield a physically impossible >100% RH.
    var wetBulbF: Int { didSet { clampWet(); touchWeather(); persist() } }
    /// Elevation band supplying the station pressure for the RH derivation.
    var elevationBand: ElevationBand { didSet { persist() } }
    /// Whether RH is typed directly or derived from the wet bulb.
    var rhSource: RHSource { didSet { touchWeather(); persist() } }
    var month: Int { didSet { markClockOverridden(); persist() } }
    var timeOfDay: TimeOfDay { didSet { markClockOverridden(); persist() } }
    var aspect: Aspect { didSet { persist() } }
    var slope: Slope { didSet { persist() } }
    var elevationDelta: ElevationDelta { didSet { persist() } }

    /// When the weather inputs (dry bulb / RH / wet bulb / source) were last
    /// hand-edited. Persisted, so "these numbers are five hours old" survives a
    /// relaunch. Watch uses it to warn before logging against stale weather.
    private(set) var weatherEditedAt: Date?
    /// When the operator last asserted the weather is still current *without*
    /// re-typing it — the "Mark current" tap. Freshness (``weatherAge(at:)``) is
    /// the later of this and ``weatherEditedAt``, so re-confirming an unchanged
    /// reading clears a staleness warning without faking an edit.
    private(set) var weatherConfirmedAt: Date?
    /// True once the operator manually picks a month or time of day — the
    /// clock auto-refresh then stands down until ``resumeAutoClock(now:calendar:)``.
    /// Session-scoped on purpose: a fresh launch re-derives from the clock.
    private(set) var clockOverridden = false
    /// Set while ``refreshClock(now:calendar:)`` writes month/timeOfDay, so its
    /// own writes don't read as a manual override.
    private var refreshingClock = false

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
        let storedWeatherEdit = store.object(forKey: Keys.weatherEdited) as? Double
        weatherEditedAt = storedWeatherEdit.map { Date(timeIntervalSince1970: $0) }
        weatherConfirmedAt = (store.object(forKey: Keys.weatherConfirmed) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        clampWet()
        // clampWet() runs after self is fully initialized, so a clamp on torn
        // persisted data (wet > dry after an interrupted persist) goes through
        // wetBulbF's didSet and stamps touchWeather() with "now". Re-assert the
        // persisted stamp: restoring state is not a user edit, and "edited five
        // hours ago" must survive a relaunch for the staleness warning to work.
        weatherEditedAt = storedWeatherEdit.map { Date(timeIntervalSince1970: $0) }
        if let s = storedWeatherEdit { store.set(s, forKey: Keys.weatherEdited) }
        else { store.removeObject(forKey: Keys.weatherEdited) }
    }

    /// Re-derive month + time-of-day from the wall clock unless the operator has
    /// manually overridden them. The view calls this on a timer and on foreground,
    /// so an app launched at 0755 doesn't still apply the night rule at 1400
    /// (red-team #4 — the staleness `pendingObs` already works around, fixed at
    /// the source).
    func refreshClock(now: Date = Date(), calendar: Calendar = .current) {
        guard !clockOverridden else { return }
        refreshingClock = true
        defer { refreshingClock = false }
        let comps = calendar.dateComponents([.month, .hour, .minute], from: now)
        if let m = comps.month, m != month { month = m }
        let t = TimeOfDay.from(hour: comps.hour ?? 12, minute: comps.minute ?? 0)
        if t != timeOfDay { timeOfDay = t }
    }

    /// Clear a manual month/time override and snap back to the wall clock.
    func resumeAutoClock(now: Date = Date(), calendar: Calendar = .current) {
        clockOverridden = false
        refreshClock(now: now, calendar: calendar)
    }

    /// Age of the freshest weather assertion — the later of the last edit and the
    /// last explicit "still current" confirmation; nil when neither has happened
    /// (first launch, defaults still showing).
    func weatherAge(at now: Date = Date()) -> TimeInterval? {
        guard let freshest = [weatherEditedAt, weatherConfirmedAt].compactMap({ $0 }).max() else { return nil }
        return now.timeIntervalSince(freshest)
    }

    /// Assert the current weather reading is still good without re-typing it —
    /// the "Mark current" affordance that clears a staleness warning. Does not
    /// move ``weatherEditedAt`` (nothing was actually re-measured).
    func confirmWeatherCurrent(now: Date = Date()) {
        weatherConfirmedAt = now
        store.set(now.timeIntervalSince1970, forKey: Keys.weatherConfirmed)
    }

    private func markClockOverridden() {
        if !refreshingClock { clockOverridden = true }
    }

    private func touchWeather(now: Date = Date()) {
        weatherEditedAt = now
        store.set(now.timeIntervalSince1970, forKey: Keys.weatherEdited)
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
        static let weatherEdited = "ignition.weatherEditedAt"
        static let weatherConfirmed = "ignition.weatherConfirmedAt"
    }
}

extension Month {
    /// Short month names for the month picker.
    static let shortNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

/// Namespace for month helpers used by the picker.
enum Month {}
