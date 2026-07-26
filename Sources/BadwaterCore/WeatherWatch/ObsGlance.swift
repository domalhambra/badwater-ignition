import Foundation

/// What a **persistent, glanceable surface** should display for the shift's
/// latest observation — a home-screen or lock-screen widget, a watch
/// complication, a Live Activity.
///
/// This is the single safety-relevant decision those surfaces make, so it lives
/// here in the pure core and is golden-tested on Linux CI rather than inside a
/// widget extension where nothing would exercise it.
///
/// ### The rule
/// A persistent surface may show a **frozen, logged** observation's Probability
/// of Ignition, always with its time and age. Once the *next* observation is
/// due, the displayed one is superseded — and at that point the surface does not
/// dim or caveat the number, it **changes job** and annunciates the cadence
/// instead. A crew glancing at a wrist wants "obs overdue 40 min", not a number
/// they then have to date-check.
///
/// The **live** estimate never reaches these surfaces at all. That distinction —
/// frozen versus volatile, persistent versus transient — is the display policy
/// recorded in `CLAUDE.md`; the full reasoning is in
/// `docs/PLAN_WIDGET_AND_WATCH.md`.
///
/// ### Why the threshold is the cadence
/// There is no separately tuned staleness constant, deliberately. A superseded
/// observation is *exactly* one that the next observation was due to replace, so
/// the boundary is the weather-watch cadence itself. Nothing to tune, and nothing
/// that can drift from the countdown the Obs screen already shows.
public enum ObsGlance: Equatable, Sendable {

    /// The standard hourly weather-watch cadence.
    ///
    /// Shared domain knowledge rather than app plumbing: the Obs screen's
    /// countdown, the due-reminder scheduler, and every glanceable surface all
    /// mean the same interval by it.
    public static let standardCadence: TimeInterval = 60 * 60

    /// A frozen observation, fresh enough to show.
    public struct Reading: Equatable, Sendable {
        public let pigUnshaded: Int
        public let pigShaded: Int
        /// Fire-behavior band of the unshaded value — the more hazardous one,
        /// matching how the app's own results lead.
        public let behavior: FireBehavior
        public let observedAt: Date
        /// Seconds since the observation. Never negative.
        public let ageSeconds: TimeInterval

        public init(pigUnshaded: Int, pigShaded: Int, behavior: FireBehavior,
                    observedAt: Date, ageSeconds: TimeInterval) {
            self.pigUnshaded = pigUnshaded
            self.pigShaded = pigShaded
            self.behavior = behavior
            self.observedAt = observedAt
            self.ageSeconds = ageSeconds
        }
    }

    /// The displayed observation is superseded; annunciate the cadence instead of
    /// showing a number.
    public struct Overdue: Equatable, Sendable {
        /// When the now-superseded observation was taken.
        public let observedAt: Date
        /// Seconds past the moment the next observation became due. Zero exactly
        /// at the due moment.
        public let overdueBySeconds: TimeInterval

        public init(observedAt: Date, overdueBySeconds: TimeInterval) {
            self.observedAt = observedAt
            self.overdueBySeconds = overdueBySeconds
        }
    }

    /// No observation logged yet — the surface has nothing to mirror.
    case none
    case reading(Reading)
    case overdue(Overdue)

    /// Decide what to show at `now`.
    ///
    /// - Parameters:
    ///   - now: the display moment. Callers on a *receiving* device (a watch
    ///     rendering a snapshot that may have been delivered late) must pass
    ///     their own clock, so a stale delivery can never present as fresh.
    ///   - latest: the shift's chronologically latest observation.
    ///   - cadence: the weather-watch interval. See the type note on why this is
    ///     the threshold.
    public static func at(_ now: Date, latest: WeatherObs?,
                          cadence: TimeInterval = standardCadence) -> ObsGlance {
        guard let latest else { return .none }
        let elapsed = now.timeIntervalSince(latest.timestamp)
        if elapsed >= cadence {
            return .overdue(Overdue(observedAt: latest.timestamp,
                                    overdueBySeconds: elapsed - cadence))
        }
        return .reading(Reading(
            pigUnshaded: latest.estimate.unshaded.probabilityOfIgnition,
            pigShaded: latest.estimate.shaded.probabilityOfIgnition,
            behavior: latest.estimate.unshaded.interpretation,
            observedAt: latest.timestamp,
            // A back-filled observation, or one taken across a clock adjustment,
            // can be stamped ahead of `now`. "Aged −5 minutes" is not something
            // to render, so the floor is zero.
            ageSeconds: max(0, elapsed)))
    }

    /// The next moment the glance changes on its own — the second entry a widget
    /// timeline needs, and nothing more.
    ///
    /// `nil` when nothing further will change without new input: there is no
    /// observation, or the displayed one is already overdue and simply gets
    /// staler. A surface that reloads on record changes needs no other schedule,
    /// which is why the widget costs no periodic background wakeups.
    public static func nextTransition(after now: Date, latest: WeatherObs?,
                                      cadence: TimeInterval = standardCadence) -> Date? {
        guard let latest else { return nil }
        let due = latest.timestamp.addingTimeInterval(cadence)
        return due > now ? due : nil
    }
}
