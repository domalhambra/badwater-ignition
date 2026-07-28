#if os(iOS)
import Foundation
@preconcurrency import ActivityKit
import PlateworksCore

/// Starts, updates and ends the obs-cadence Live Activity.
///
/// ### One entry point, not five
/// The plan's lifecycle table lists five events — first obs, later obs, edit,
/// last obs deleted, new shift. They are all the same question: *what is the
/// shift's latest observation now?* So there is one method, ``sync(latest:siteLabel:)``,
/// called from the same funnel that reloads the widget. A caller cannot forget
/// which of the five it is in, and cannot get the first-obs case wrong by
/// calling `update` before anything was requested.
///
/// ### Adopting on relaunch
/// This is the row that bites. A Live Activity outlives the app process, so a
/// relaunch that blindly requests a new one leaves the old one orphaned and the
/// crew looking at two countdowns that disagree. ``init()`` adopts whatever is
/// already running, and ends any extras beyond the first — one shift has one
/// next observation, so more than one countdown is always wrong.
@MainActor
final class ObsActivityController {

    private var activity: Activity<ObsActivityAttributes>?

    init() {
        let running = Activity<ObsActivityAttributes>.activities
        activity = running.first
        // Belt and braces: if a previous crash or a race ever left two, end the
        // extras rather than leaving contradicting countdowns on the screen.
        for stale in running.dropFirst() {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Bring the Live Activity in line with the shift's latest observation.
    ///
    /// - Parameters:
    ///   - latest: the chronologically latest logged observation, or `nil` when
    ///     the shift is empty — which covers both "last obs deleted" and "new
    ///     shift started". Either way there is no next observation to count down
    ///     to, so the activity ends.
    ///   - siteLabel: division / location, used only when starting.
    func sync(latest: WeatherObs?,
              siteLabel: String?,
              cadence: TimeInterval = ObsGlance.standardCadence) {
        guard let latest else {
            end()
            return
        }
        let state = ObsActivityAttributes.ContentState(
            observedAt: latest.timestamp,
            dueAt: latest.timestamp.addingTimeInterval(cadence))

        if let activity {
            // Update rather than stack. A new observation moves the countdown;
            // it does not deserve a second activity.
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            start(state: state, siteLabel: siteLabel)
        }
    }

    /// End the activity now.
    ///
    /// `.immediate` rather than a lingering dismissal: the shift is over or its
    /// last observation is gone, so there is nothing left to count down to and a
    /// countdown left on the lock screen would be counting toward a reading that
    /// no longer exists.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func start(state: ObsActivityAttributes.ContentState, siteLabel: String?) {
        // Not an error worth surfacing: the operator may simply have Live
        // Activities switched off, and every other surface still works.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: ObsActivityAttributes(siteLabel: siteLabel ?? "Weather watch"),
            content: ActivityContent(state: state, staleDate: nil))
    }
}
#endif
