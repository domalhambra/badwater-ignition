import Foundation

/// How a glanceable surface words an observation's age and its overdue
/// interval.
///
/// In the core, next to ``ObsGlance``, for two reasons. The widget and the watch
/// complication must say the *same* thing about the same record — two surfaces
/// on the same wrist disagreeing about how old a reading is would be worse than
/// either being absent. And phrasing put here is golden-tested on Linux CI,
/// where a SwiftUI view's text never is; ``RadioScript`` and
/// ``WeatherObs/radioLine(timeLabel:)`` already establish that operational
/// wording belongs in the core rather than in a view.
///
/// Deliberately spelled out in words rather than left to a relative date
/// formatter: "12 min ago" is read at arm's length in sunlight, in gloves, by
/// someone who must not have to work out what "12m" means or which of two
/// numbers on the screen is the clock.
public enum GlancePhrasing {

    /// An observation's time as it is spoken on the net: `"1430"`.
    ///
    /// 24-hour, zero-padded, no separator — the same four digits that go out in
    /// `"Wx obs 1430"`, so what a crew reads on a wrist is what they say on the
    /// radio. Built from `Calendar` components rather than a `DateFormatter`:
    /// no locale can turn it into "2:30 PM", and there is no shared mutable
    /// formatter for a widget and a watch to contend over.
    public static func clockLabel(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// A whole-minute duration: `"40 min"`, `"1 hr"`, `"2 hr 15 min"`.
    ///
    /// Truncated to minutes, never rounded up — an observation 119 seconds old
    /// is "1 min", not "2 min". Erring young would be the wrong direction for a
    /// value whose whole purpose is to say how stale something is.
    public static func duration(seconds: TimeInterval) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    /// How old a reading is: `"just now"`, `"12 min ago"`, `"1 hr 5 min ago"`.
    ///
    /// Under a minute reads as "just now" rather than "0 min ago", which looks
    /// like a missing value.
    public static func age(seconds: TimeInterval) -> String {
        max(0, seconds) < 60 ? "just now" : "\(duration(seconds: seconds)) ago"
    }

    /// The cadence annunciation: `"obs due now"`, `"obs overdue 40 min"`.
    ///
    /// This replaces the number entirely once a reading is superseded — see the
    /// display policy in `CLAUDE.md`. It never contains a Probability of
    /// Ignition — `GlancePhrasingTests` sweeps the range and asserts the only
    /// digits it can carry are the interval's own.
    public static func overdue(seconds: TimeInterval) -> String {
        max(0, seconds) < 60 ? "obs due now" : "obs overdue \(duration(seconds: seconds))"
    }

    // MARK: - Observed conditions

    /// The observed conditions line: `"75°F · RH 20% · Calm"`.
    ///
    /// These are the values a crew actually reads off a glanceable surface. PIG
    /// is a *derived* number and one input among several to a decision; dry bulb,
    /// relative humidity and wind are the observation itself. So this line leads
    /// on every glanceable surface and the Probability of Ignition follows it.
    ///
    /// ### Every segment is labelled or unambiguous
    /// `75°F` carries its unit and `RH 20%` its name, because two bare
    /// percentages on one small screen — humidity and ignition probability — is
    /// exactly the confusion this app cannot afford. The wind segment is
    /// ``Wind/spotString``, reused rather than re-worded so the wrist and the
    /// spot request cannot disagree.
    ///
    /// ### Missing is "—", never absent
    /// A dropped segment would read as though the value were zero, or leave
    /// "Calm" looking like a recorded wind when none was taken. An unrecorded
    /// value renders as an em dash so the gap is visible as a gap.
    public static func conditions(dryBulbF: Int?,
                                  relativeHumidity: Int?,
                                  wind: String?) -> String {
        let temp = dryBulbF.map { "\($0)°F" } ?? "—"
        let rh = relativeHumidity.map { "RH \($0)%" } ?? "RH —"
        return "\(temp) · \(rh) · \(wind ?? "wind —")"
    }

    /// The same line for surfaces that cannot hold it: `"75° · 20% · Calm"`.
    ///
    /// For the inline complication and other single-line families. Units are
    /// dropped because the order is fixed and the degree sign and percent sign
    /// still separate the two numbers; anything longer truncates, and a
    /// truncated conditions line is worse than a terse one.
    public static func conditionsCompact(dryBulbF: Int?,
                                         relativeHumidity: Int?,
                                         wind: String?) -> String {
        let temp = dryBulbF.map { "\($0)°" } ?? "—"
        let rh = relativeHumidity.map { "\($0)%" } ?? "—"
        return "\(temp) · \(rh) · \(wind ?? "—")"
    }

    /// The Probability of Ignition, worded as the secondary line it now is:
    /// `"PIG 40/40 shd"`.
    ///
    /// Short enough for `accessoryRectangular`, which truncated the previous
    /// wording (`"PIG 40% · 40% shaded"` rendered as `"PIG 40% · 40% s…"`,
    /// losing the very word that distinguished the two numbers). One percent
    /// sign governs the pair and `shd` labels the second.
    public static func pigSummary(unshaded: Int, shaded: Int) -> String {
        "PIG \(unshaded)/\(shaded)% shd"
    }
}
