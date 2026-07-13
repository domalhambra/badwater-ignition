import Foundation
import Observation
import BadwaterCore

/// View model for the **Watch** screen (Weather Watch — the shift observation log).
///
/// It does not own a second input form: it holds a reference to the shared
/// ``IgnitionModel`` so the *pending* observation is always the live estimate.
/// A log freezes that estimate (plus the ``HumidityResult`` when slung) with a
/// timestamp, deriving month + time-of-day from the wall clock so the record and
/// the trend can't be biased by a stale band left on the Ignition tab. Triggers
/// and the current shift persist across launches; all compute is local & offline.
@Observable
final class WeatherWatchModel {
    /// The current shift's logged observations.
    var shift: Shift { didSet { persistShift() } }
    /// The crew's briefed trigger points. Empty until the crew adds their own —
    /// the app never authors a threshold.
    var triggers: [BriefedTrigger] { didSet { persistTriggers() } }
    /// Radio addressee for the broadcast script (e.g. "Diamond Mountain").
    /// Deliberately stored app-wide, not per-shift: the radio net usually
    /// outlives a shift, so it survives `startNewShift()`.
    var addressee: String { didSet { persistAddressee() } }
    /// Absolute site elevation (feet MSL) for the current position, sticky across
    /// obs. When set, a pending/logged obs derives its sling RH from the
    /// ``ElevationBand`` for THIS elevation — not the (possibly stale) band left on
    /// the Ignition tab — and pre-fills the obs's absolute elevation. Nil restores
    /// the earlier behavior of falling back to the Ignition tab's band.
    var siteElevationFeet: Int? { didSet { persistSiteElevation() } }
    /// Sticky decimal lat/long for the current position (typed or GPS-filled).
    /// Folded into each logged obs so the coordinate lands in the spreadsheet
    /// export (IMET column J) without re-entry every hour.
    var siteCoordinate: GeoPoint? { didSet { persistSiteCoordinate() } }
    /// When the operator last explicitly reviewed the site factors this shift
    /// (aspect, slope, elevation, location). Nil until confirmed — the Watch
    /// screen gates the first log of a shift on this, so the persisted aspect
    /// default can never silently feed a broadcast (red-team #9).
    private(set) var siteConfirmedAt: Date? { didSet { persistSiteConfirmed() } }
    /// The most recently deleted obs, held (in memory only) for an undo toast —
    /// a glove mis-tap must not silently erase part of the record (red-team #7).
    private(set) var lastRemovedObs: WeatherObs?

    private let ignition: IgnitionModel
    private let store: UserDefaults

    init(ignition: IgnitionModel, store: UserDefaults = .standard, now: Date = Date()) {
        self.ignition = ignition
        self.store = store
        self.shift = Self.decode(Shift.self, from: store.data(forKey: Keys.shift)) ?? Shift(started: now)
        self.triggers = Self.decode([BriefedTrigger].self, from: store.data(forKey: Keys.triggers)) ?? []
        self.addressee = store.string(forKey: Keys.addressee) ?? ""
        self.siteElevationFeet = store.object(forKey: Keys.siteElevation) as? Int
        self.siteCoordinate = Self.decode(GeoPoint.self, from: store.data(forKey: Keys.siteCoordinate))
        self.siteConfirmedAt = (store.object(forKey: Keys.siteConfirmed) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
    }

    /// True until ``confirmSite(at:)`` — the once-per-shift explicit review of
    /// the site factors before the first log.
    var needsSiteConfirmation: Bool { siteConfirmedAt == nil }

    func confirmSite(at now: Date = Date()) { siteConfirmedAt = now }

    /// The observation a LOG tap would freeze right now: the live estimate, with
    /// month + time-of-day taken from the wall clock (not a possibly-stale band),
    /// and the triggers it currently meets already computed.
    func pendingObs(at now: Date = Date(), calendar: Calendar = .current) -> WeatherObs {
        let comps = calendar.dateComponents([.month, .hour, .minute], from: now)
        // A slung obs uses the station-pressure band for the observation site's own
        // elevation when the crew has entered one; otherwise it falls back to the
        // band on the Ignition tab. The SAME HumidityResult is frozen into the obs
        // AND feeds the estimate, so the logged record and the PIG it produces can
        // never disagree about which band (elevation) was used.
        let humidity: HumidityResult?
        if ignition.rhSource == .wetBulb {
            let band = siteElevationFeet.map { ElevationBand.forElevation(feetMSL: $0) } ?? ignition.elevationBand
            humidity = Psychrometrics.compute(
                dryBulbF: ignition.dryBulbF, wetBulbF: ignition.wetBulbF, band: band)
        } else {
            humidity = nil
        }
        let relativeHumidity = humidity?.relativeHumidity ?? ignition.effectiveRelativeHumidity
        let input = IgnitionInput(
            dryBulbF: ignition.dryBulbF,
            relativeHumidity: relativeHumidity,
            month: comps.month ?? ignition.month,
            timeOfDay: TimeOfDay.from(hour: comps.hour ?? 12, minute: comps.minute ?? 0),
            aspect: ignition.aspect, slope: ignition.slope, elevationDelta: ignition.elevationDelta)
        let estimate = IgnitionCalculator.estimate(input)
        let base = WeatherObs(timestamp: now, estimate: estimate, humidity: humidity, rhSource: ignition.rhSource)
        return WeatherObs(
            id: base.id, timestamp: now, estimate: estimate, humidity: humidity,
            rhSource: ignition.rhSource,
            crossedTriggerIDs: TriggerEvaluator.metTriggerIDs(triggers, by: base))
    }

    /// Freeze the current reading and append it to the shift. Observed metadata
    /// for the IMET export (wind, absolute elevation, GPS) is captured by the app
    /// and folded into the frozen obs here — along with the spoken-location text
    /// and the fully rendered broadcast script, so the record of what went out
    /// over the air can never be retro-altered by a later edit or delete.
    @discardableResult
    func logObs(at now: Date = Date(), calendar: Calendar = .current,
                wind: Wind? = nil, elevationFeet: Int? = nil, location: GeoPoint? = nil,
                note: String? = nil,
                forceLocation: Bool = false, suppressLocation: Bool = false) -> WeatherObs {
        var obs = pendingObs(at: now, calendar: calendar)
        obs.wind = wind
        // An explicit per-obs elevation wins; otherwise fall back to the sticky
        // site elevation so the logged record matches the band used for its RH.
        obs.elevationFeet = elevationFeet ?? siteElevationFeet
        obs.location = location ?? siteCoordinate
        obs.note = note.flatMap { n in
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        obs.spokenLocation = shift.locationName
        obs.broadcastText = RadioScript.render(
            addressee: addressee, timeLabel: obs.timeLabel(calendar),
            spokenLocation: obs.spokenLocation,
            current: obs, previous: chronologicalPrevious(before: obs.timestamp),
            forceLocation: forceLocation, suppressLocation: suppressLocation)
        shift.obs.append(obs)
        return obs
    }

    /// The obs immediately preceding `t` in time (not append order), optionally
    /// excluding one id — the "previous" for deltas and location suppression.
    private func chronologicalPrevious(before t: Date, excluding id: UUID? = nil) -> WeatherObs? {
        shift.obs
            .filter { $0.timestamp < t && $0.id != id }
            .max { $0.timestamp < $1.timestamp }
    }

    var latest: WeatherObs? { shift.latest }

    /// `(timestamp, value)` points for a metric across the shift, chronological.
    func series(of metric: TriggerMetric) -> [(date: Date, value: Int?)] { shift.series(of: metric) }

    /// Latched trigger status, crossed ones first.
    var crossings: [TriggerCrossing] { TriggerEvaluator.crossings(of: triggers, across: shift.obs) }

    /// How many briefed triggers have been crossed this shift.
    var crossedCount: Int { crossings.filter(\.isCrossed).count }

    func startNewShift(at now: Date = Date()) {
        shift = Shift(started: now)
        // A new shift means a fresh site review before the first broadcast.
        siteConfirmedAt = nil
    }

    /// Delete a mis-entered observation. Trigger crossings re-derive from the
    /// remaining obs on the next read, so removing a bad log can't leave a
    /// latched flag behind; the shift re-persists via `didSet`. The removed obs
    /// is retained for ``undoRemoveObs()`` so the view can offer an undo toast.
    func removeObs(id: UUID) {
        if let removed = shift.obs.first(where: { $0.id == id }) { lastRemovedObs = removed }
        shift.obs.removeAll { $0.id == id }
    }

    /// Restore the most recently deleted obs. Position doesn't matter — every
    /// live read is timestamp-ordered, so a plain append lands it correctly.
    @discardableResult
    func undoRemoveObs() -> WeatherObs? {
        guard let removed = lastRemovedObs else { return nil }
        lastRemovedObs = nil
        shift.obs.append(removed)
        return removed
    }

    /// Seconds since the Ignition-tab weather inputs (dry bulb / RH / wet bulb /
    /// source) were last hand-edited; nil when never edited. The Watch screen
    /// warns before logging when this exceeds `threshold` — a fresh timestamp
    /// must not silently freeze hours-old weather (red-team #3).
    func pendingWeatherAge(at now: Date = Date()) -> TimeInterval? {
        ignition.weatherAge(at: now)
    }

    func isPendingWeatherStale(at now: Date = Date(), threshold: TimeInterval = 30 * 60) -> Bool {
        guard let age = pendingWeatherAge(at: now) else { return false }
        return age > threshold
    }

    /// Set the IMET export header (division / location name), sticky per shift.
    func setShiftHeader(division: String?, locationName: String?) {
        shift.division = division
        shift.locationName = locationName
    }

    /// The IMET `.xlsx` workbook bytes for the current shift (one sheet per local
    /// day) — hand this to the OS share sheet.
    func imetWorkbookData(calendar: Calendar = .current) -> Data {
        IMETWorkbook.build(from: shift, calendar: calendar)
    }

    /// A tab-separated, Notes-app-ready table of the shift's observations —
    /// hand this to the OS share sheet ("Copy to Notes") for AirDrop.
    func notesText(calendar: Calendar = .current) -> String {
        NotesExport.plainText(from: shift, calendar: calendar)
    }

    /// A plain-text NWS spot-request "recent observations" block for the shift.
    func spotObservationsText(includePoI: Bool = true, calendar: Calendar = .current) -> String {
        let header = SpotObsHeader(
            site: [shift.division, shift.locationName].compactMap { $0 }.joined(separator: " "),
            latLong: latest?.location?.rendered,
            elevationFeet: latest?.elevationFeet,
            aspect: latest?.estimate.input.aspect.displayName,
            dateLabel: dateLabel(shift.started, calendar))
        let rows = shift.obs.sorted { $0.timestamp < $1.timestamp }.map { o -> SpotObsLine in
            let dry = o.estimate.input.dryBulbF
            let md = calendar.dateComponents([.month, .day], from: o.timestamp)
            return SpotObsLine(
                timeHHmm: o.timeLabel(calendar), dryBulbF: dry,
                wetBulbF: o.humidity.map { dry - $0.wetBulbDepressionF },
                relativeHumidity: o.estimate.input.relativeHumidity,
                dewPointF: o.humidity?.dewPointF, windText: o.wind?.spotString,
                poiUnshaded: o.estimate.unshaded.probabilityOfIgnition,
                poiShaded: o.estimate.shaded.probabilityOfIgnition,
                monthDay: "\(md.month ?? 0)/\(md.day ?? 0)")
        }
        return SpotObservationsRenderer.plainText(header: header, rows: rows, includePoI: includePoI)
    }

    private func dateLabel(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .year], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)/\((c.year ?? 0) % 100)"
    }

    /// The spoken radio broadcast for an observation. A **logged** obs replays
    /// its frozen ``WeatherObs/broadcastText`` — the record of what actually went
    /// out over the air, immune to later edits/deletes of neighboring obs and to
    /// addressee changes (red-team #11). A pending preview renders live against
    /// the chronologically latest logged obs.
    func broadcastScript(for obs: WeatherObs, calendar: Calendar = .current,
                         forceLocation: Bool = false, suppressLocation: Bool = false) -> String {
        if let frozen = obs.broadcastText { return frozen }
        let previous: WeatherObs?
        let spokenLocation: String?
        if shift.obs.contains(where: { $0.id == obs.id }) {
            // A logged pre-feature obs (no frozen script): render against its
            // chronological predecessor, speaking ONLY what was frozen on it.
            // The live shift.locationName may describe wherever the crew is NOW —
            // substituting it would misattribute a historical reading's location,
            // so an unknown location degrades to elevation + aspect (both frozen).
            previous = chronologicalPrevious(before: obs.timestamp, excluding: obs.id)
            spokenLocation = obs.spokenLocation
        } else {
            // A pending preview IS the current position — the live location applies.
            previous = shift.latest
            spokenLocation = shift.locationName
        }
        return RadioScript.render(
            addressee: addressee, timeLabel: obs.timeLabel(calendar),
            spokenLocation: spokenLocation,
            current: obs, previous: previous,
            forceLocation: forceLocation, suppressLocation: suppressLocation)
    }

    func addTrigger(_ trigger: BriefedTrigger) { triggers.append(trigger) }
    func removeTrigger(id: UUID) { triggers.removeAll { $0.id == id } }
    func updateTrigger(_ trigger: BriefedTrigger) {
        if let i = triggers.firstIndex(where: { $0.id == trigger.id }) { triggers[i] = trigger }
    }

    // MARK: - Persistence (JSON blobs; arrays grow across a shift/season)

    private func persistShift() { store.set(try? JSONEncoder().encode(shift), forKey: Keys.shift) }
    private func persistTriggers() { store.set(try? JSONEncoder().encode(triggers), forKey: Keys.triggers) }
    private func persistAddressee() { store.set(addressee, forKey: Keys.addressee) }
    private func persistSiteElevation() {
        // Store nil as an absent key (not NSNull) so a fresh model reads it back as nil.
        if let ft = siteElevationFeet { store.set(ft, forKey: Keys.siteElevation) }
        else { store.removeObject(forKey: Keys.siteElevation) }
    }
    private func persistSiteCoordinate() {
        if let c = siteCoordinate { store.set(try? JSONEncoder().encode(c), forKey: Keys.siteCoordinate) }
        else { store.removeObject(forKey: Keys.siteCoordinate) }
    }
    private func persistSiteConfirmed() {
        if let at = siteConfirmedAt { store.set(at.timeIntervalSince1970, forKey: Keys.siteConfirmed) }
        else { store.removeObject(forKey: Keys.siteConfirmed) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private enum Keys {
        static let shift = "watch.shift"
        static let triggers = "watch.triggers"
        static let addressee = "watch.addressee"
        static let siteElevation = "watch.siteElevationFeet"
        static let siteCoordinate = "watch.siteCoordinate"
        static let siteConfirmed = "watch.siteConfirmedAt"
    }
}

extension WeatherObs {
    /// `"HHmm"` label for this obs's timestamp (used for the radio line and rows).
    func timeLabel(_ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: timestamp)
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
