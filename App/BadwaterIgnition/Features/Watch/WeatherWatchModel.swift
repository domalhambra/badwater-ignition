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

    private let ignition: IgnitionModel
    private let store: UserDefaults

    init(ignition: IgnitionModel, store: UserDefaults = .standard, now: Date = Date()) {
        self.ignition = ignition
        self.store = store
        self.shift = Self.decode(Shift.self, from: store.data(forKey: Keys.shift)) ?? Shift(started: now)
        self.triggers = Self.decode([BriefedTrigger].self, from: store.data(forKey: Keys.triggers)) ?? []
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

    /// Freeze the current reading and append it to the shift.
    @discardableResult
    func logObs(at now: Date = Date(), calendar: Calendar = .current) -> WeatherObs {
        let obs = pendingObs(at: now, calendar: calendar)
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
    func addTrigger(_ trigger: BriefedTrigger) { triggers.append(trigger) }
    func removeTrigger(id: UUID) { triggers.removeAll { $0.id == id } }
    func updateTrigger(_ trigger: BriefedTrigger) {
        if let i = triggers.firstIndex(where: { $0.id == trigger.id }) { triggers[i] = trigger }
    }

    // MARK: - Persistence (JSON blobs; arrays grow across a shift/season)

    private func persistShift() { store.set(try? JSONEncoder().encode(shift), forKey: Keys.shift) }
    private func persistTriggers() { store.set(try? JSONEncoder().encode(triggers), forKey: Keys.triggers) }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private enum Keys {
        static let shift = "watch.shift"
        static let triggers = "watch.triggers"
    }
}

extension WeatherObs {
    /// `"HHmm"` label for this obs's timestamp (used for the radio line and rows).
    func timeLabel(_ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: timestamp)
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
