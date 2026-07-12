import Foundation

/// The latched status of one briefed trigger across a shift.
///
/// A crossing **latches**: once an observation meets a briefed re-evaluation
/// point it stays flagged with its first-cross time even if a later reading
/// recovers — a briefed trigger doesn't un-ring. The live ``nowValue`` still
/// updates so recovery remains visible.
public struct TriggerCrossing: Identifiable, Equatable, Sendable {
    public let trigger: BriefedTrigger
    /// Timestamp of the first observation that met the trigger, or `nil` if none has.
    public let firstCrossedAt: Date?
    /// The latest observation's value for this metric (the live "NOW" read), or
    /// `nil` when the metric isn't computed for the latest obs.
    public let nowValue: Int?
    /// How many logged observations have met the trigger.
    public let pastCount: Int
    /// `false` when the metric can't be computed for the latest obs (e.g. dew
    /// point in Kestrel mode) — the board shows "n/a this obs", never a false clear.
    public let applicableNow: Bool

    public var id: UUID { trigger.id }

    /// `true` once any logged obs has met the trigger this shift.
    public var isCrossed: Bool { firstCrossedAt != nil }
}

/// Pure, offline evaluation of briefed trigger points against logged
/// observations. No math beyond an inclusive comparison; no forecasting.
public enum TriggerEvaluator {

    /// Whether an observation meets a briefed trigger. Returns `nil` when the
    /// trigger is unarmed (disabled or no briefed value) or the metric isn't
    /// computed for this obs — never a silent "not met".
    public static func isMet(_ trigger: BriefedTrigger, by obs: WeatherObs) -> Bool? {
        guard trigger.enabled, let threshold = trigger.value else { return nil }
        guard let value = obs.value(of: trigger.metric) else { return nil }
        return trigger.direction.isSatisfied(value: value, threshold: threshold)
    }

    /// The IDs of every armed trigger an observation meets — frozen onto the obs
    /// at log time via ``WeatherObs/crossedTriggerIDs``.
    public static func metTriggerIDs(_ triggers: [BriefedTrigger], by obs: WeatherObs) -> [UUID] {
        triggers.filter { isMet($0, by: obs) == true }.map(\.id)
    }

    /// The latched status of one trigger across a shift's observations, which
    /// must be in log order (oldest first).
    public static func crossing(of trigger: BriefedTrigger, across obs: [WeatherObs]) -> TriggerCrossing {
        let met = obs.filter { isMet(trigger, by: $0) == true }
        let latest = obs.last
        return TriggerCrossing(
            trigger: trigger,
            firstCrossedAt: met.first?.timestamp,
            nowValue: latest?.value(of: trigger.metric),
            pastCount: met.count,
            applicableNow: latest.map { $0.value(of: trigger.metric) != nil } ?? false
        )
    }

    /// The latched status of every trigger across a shift, crossed ones first
    /// (each group keeps the triggers' given order).
    public static func crossings(of triggers: [BriefedTrigger], across obs: [WeatherObs]) -> [TriggerCrossing] {
        let all = triggers.map { crossing(of: $0, across: obs) }
        return all.filter(\.isCrossed) + all.filter { !$0.isCrossed }
    }
}
