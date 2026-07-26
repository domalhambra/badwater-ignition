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
}
