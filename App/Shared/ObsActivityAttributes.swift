#if os(iOS)
import Foundation
import ActivityKit

/// The obs-cadence countdown shown on the lock screen and in the Dynamic Island.
///
/// Carries **no computed value** — not a Probability of Ignition, not a fine
/// fuel moisture. This is the most persistent surface in the app, and a Live
/// Activity outlives the reading that produced it *by definition*: it exists
/// precisely to count down to that reading's replacement. Putting a number on it
/// would mean displaying one at exactly the moment it stops being true.
///
/// So it shows two instants and nothing else: when the last observation was
/// taken, and when the next is due. Both are rendered with
/// `Text(timerInterval:)`, which the system updates without waking the app.
///
/// iOS only — Live Activities have no macOS presentation, and the app target
/// builds for macOS too.
struct ObsActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// When the observation this countdown follows was taken.
        var observedAt: Date
        /// When the next observation is due. Drives the countdown, and the
        /// moment the presentation switches from "next obs in" to "obs overdue"
        /// — the same boundary ``ObsGlance`` applies everywhere else.
        var dueAt: Date
    }

    /// Division or location label, fixed for the activity's life. A shift that
    /// is relabelled mid-run keeps the label it started with; changing it would
    /// mean tearing down and restarting the activity, and a countdown that
    /// restarts is worse than one with a stale caption.
    var siteLabel: String
}
#endif
