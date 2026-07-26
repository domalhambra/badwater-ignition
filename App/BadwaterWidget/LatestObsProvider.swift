import WidgetKit
import BadwaterCore

struct LatestObsEntry: TimelineEntry {
    let date: Date
    let glance: ObsGlance
}

/// Two entries and done.
///
/// The glance changes at exactly one predictable moment — when the next
/// observation becomes due — so the timeline is "now" plus "then", and the app
/// calls `WidgetCenter.shared.reloadAllTimelines()` whenever it logs, edits,
/// deletes, undoes, or starts a new shift. No periodic refresh, so this costs no
/// background wakeups: relevant on a 16-hour shift with no way to charge.
///
/// The cadence comes from ``ObsGlance/standardCadence`` in the core rather than
/// from the app's `ObsCadenceScheduler`, so the extension depends on no
/// app-target type and the countdown, the due reminder and this widget cannot
/// drift apart.
struct LatestObsProvider: TimelineProvider {

    func placeholder(in context: Context) -> LatestObsEntry {
        LatestObsEntry(date: Date(), glance: .none)
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestObsEntry) -> Void) {
        let now = Date()
        completion(LatestObsEntry(
            date: now,
            glance: ObsGlance.at(now, latest: RecordReader.latestObservation())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestObsEntry>) -> Void) {
        let now = Date()
        let latest = RecordReader.latestObservation()

        var entries = [LatestObsEntry(date: now, glance: ObsGlance.at(now, latest: latest))]
        // The one scheduled change: the moment the displayed reading is
        // superseded and the widget changes job. `ObsGlanceTests` pins that an
        // entry scheduled here renders as `.overdue`, not one second short of it.
        if let flip = ObsGlance.nextTransition(after: now, latest: latest) {
            entries.append(LatestObsEntry(date: flip, glance: ObsGlance.at(flip, latest: latest)))
        }
        // .never: nothing else changes on its own, and the app reloads us on any
        // record mutation.
        completion(Timeline(entries: entries, policy: .never))
    }
}
