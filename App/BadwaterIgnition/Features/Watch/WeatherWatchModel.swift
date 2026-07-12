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

    private let ignition: IgnitionModel
    private let store: UserDefaults

    init(ignition: IgnitionModel, store: UserDefaults = .standard, now: Date = Date()) {
        self.ignition = ignition
        self.store = store
        self.shift = Self.decode(Shift.self, from: store.data(forKey: Keys.shift)) ?? Shift(started: now)
        self.triggers = Self.decode([BriefedTrigger].self, from: store.data(forKey: Keys.triggers)) ?? []
        self.addressee = store.string(forKey: Keys.addressee) ?? ""
    }

    /// The observation a LOG tap would freeze right now: the live estimate, with
    /// month + time-of-day taken from the wall clock (not a possibly-stale band),
    /// and the triggers it currently meets already computed.
    func pendingObs(at now: Date = Date(), calendar: Calendar = .current) -> WeatherObs {
        let comps = calendar.dateComponents([.month, .hour, .minute], from: now)
        let input = IgnitionInput(
            dryBulbF: ignition.dryBulbF,
            relativeHumidity: ignition.effectiveRelativeHumidity,
            month: comps.month ?? ignition.month,
            timeOfDay: TimeOfDay.from(hour: comps.hour ?? 12, minute: comps.minute ?? 0),
            aspect: ignition.aspect, slope: ignition.slope, elevationDelta: ignition.elevationDelta)
        let estimate = IgnitionCalculator.estimate(input)
        let humidity = ignition.rhSource == .wetBulb
            ? Psychrometrics.compute(dryBulbF: ignition.dryBulbF, wetBulbF: ignition.wetBulbF, band: ignition.elevationBand)
            : nil
        let base = WeatherObs(timestamp: now, estimate: estimate, humidity: humidity, rhSource: ignition.rhSource)
        return WeatherObs(
            id: base.id, timestamp: now, estimate: estimate, humidity: humidity,
            rhSource: ignition.rhSource,
            crossedTriggerIDs: TriggerEvaluator.metTriggerIDs(triggers, by: base))
    }

    /// Freeze the current reading and append it to the shift. Observed metadata
    /// for the IMET export (wind, absolute elevation, GPS) is captured by the app
    /// and folded into the frozen obs here.
    @discardableResult
    func logObs(at now: Date = Date(), calendar: Calendar = .current,
                wind: Wind? = nil, elevationFeet: Int? = nil, location: GeoPoint? = nil) -> WeatherObs {
        var obs = pendingObs(at: now, calendar: calendar)
        obs.wind = wind
        obs.elevationFeet = elevationFeet
        obs.location = location
        shift.obs.append(obs)
        return obs
    }

    var latest: WeatherObs? { shift.obs.last }

    /// `(timestamp, value)` points for a metric across the shift, in log order.
    func series(of metric: TriggerMetric) -> [(date: Date, value: Int?)] { shift.series(of: metric) }

    /// Latched trigger status, crossed ones first.
    var crossings: [TriggerCrossing] { TriggerEvaluator.crossings(of: triggers, across: shift.obs) }

    /// How many briefed triggers have been crossed this shift.
    var crossedCount: Int { crossings.filter(\.isCrossed).count }

    func startNewShift(at now: Date = Date()) { shift = Shift(started: now) }

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

    /// The spoken radio broadcast for an observation. `previous` is the obs
    /// logged immediately before it in the shift (drives the "up 5 / down 3"
    /// deltas and the location-suppression rule); an obs not yet in the shift
    /// (a pending preview) compares against the latest logged one.
    func broadcastScript(for obs: WeatherObs, calendar: Calendar = .current,
                         forceLocation: Bool = false) -> String {
        let previous: WeatherObs?
        if let i = shift.obs.firstIndex(where: { $0.id == obs.id }) {
            previous = i > 0 ? shift.obs[i - 1] : nil
        } else {
            previous = shift.obs.last
        }
        return RadioScript.render(
            addressee: addressee, timeLabel: obs.timeLabel(calendar),
            spokenLocation: shift.locationName, current: obs, previous: previous,
            forceLocation: forceLocation)
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

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private enum Keys {
        static let shift = "watch.shift"
        static let triggers = "watch.triggers"
        static let addressee = "watch.addressee"
    }
}

extension WeatherObs {
    /// `"HHmm"` label for this obs's timestamp (used for the radio line and rows).
    func timeLabel(_ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: timestamp)
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
