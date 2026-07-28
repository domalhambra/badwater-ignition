import WidgetKit
import SwiftUI
import PlateworksCore

/// The watch complication — the highest-value surface in 3.5, and the one a
/// crew actually reads: it is on the face, so it costs nothing to look at.
///
/// It reads the snapshot the watch app persisted (see ``WatchSnapshotStore``)
/// and applies the **same** staleness rule as the phone widget, against this
/// device's clock. Past the due moment it shows no number at all — it
/// annunciates the cadence instead. See the display policy in `CLAUDE.md`.
@main
struct PlateworksWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestObsComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let glance: ObsGlance
}

/// Two entries and done, exactly like the phone widget: "now", and the moment
/// the reading is superseded. The watch app reloads these timelines whenever a
/// snapshot arrives, so there is no polling and no scheduled refresh — which
/// matters more here than anywhere else, on the smallest battery in the kit.
struct ComplicationProvider: TimelineProvider {

    private func glance(at date: Date) -> ObsGlance {
        WatchSnapshotStore.load()?.glance(at: date) ?? .none
    }

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), glance: .none)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let now = Date()
        completion(ComplicationEntry(date: now, glance: glance(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        var entries = [ComplicationEntry(date: now, glance: glance(at: now))]
        if let due = WatchSnapshotStore.load()?.dueAt, due > now {
            entries.append(ComplicationEntry(date: due, glance: glance(at: due)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct LatestObsComplication: Widget {
    let kind = "LatestObsComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(glance: entry.glance)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Latest Obs")
        .description("The last logged observation's conditions, with its time.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let glance: ObsGlance

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line, system-rendered, and the system truncates it without
            // asking. So the order is chosen for how it *degrades*: the obs time
            // leads, then dry bulb, then RH, then wind. Anything the system cuts
            // is taken off the least critical end, and the time anchor — the one
            // thing a displayed value may never appear without — is the last
            // thing that could ever be lost.
            switch glance {
            case .none: Text("No obs")
            case .reading(let r):
                Text("\(GlancePhrasing.clockLabel(for: r.observedAt)) · \(r.conditionsCompact)")
            case .overdue(let o):
                Text(GlancePhrasing.overdue(seconds: o.overdueBySeconds))
            }

        case .accessoryCorner:
            CornerGlance(glance: glance)

        default:
            CircularGlance(glance: glance)
        }
    }
}

/// Circular is the tightest of the three. It gets **one** value, and that value
/// is relative humidity — the single most decision-relevant number in a fire
/// weather observation, and the reason this family stopped showing PIG.
///
/// The second line carries both the label and the obs time, because neither can
/// be dropped: unlabelled, the number is indistinguishable from the PIG this
/// surface used to show; undated, it is a value with no anchor, which the
/// display policy forbids outright.
private struct CircularGlance: View {
    let glance: ObsGlance

    var body: some View {
        VStack(spacing: 0) {
            switch glance {
            case .none:
                Text("--").font(.title3)
                Text("no obs").font(.system(size: 10))
            case .reading(let r):
                Text(r.relativeHumidity.map { "\($0)" } ?? "--")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("RH \(GlancePhrasing.clockLabel(for: r.observedAt))")
                    .font(.system(size: 10))
            case .overdue(let o):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text(GlancePhrasing.duration(seconds: o.overdueBySeconds))
                    .font(.system(size: 10))
            }
        }
        .widgetAccentable()
    }
}

private struct CornerGlance: View {
    let glance: ObsGlance

    var body: some View {
        switch glance {
        case .none:
            Text("--").widgetLabel("no obs")
        case .reading(let r):
            // Same choice as circular: RH, labelled and dated. The curved label
            // has room for the wind too, which circular does not.
            Text(r.relativeHumidity.map { "\($0)%" } ?? "--")
                .widgetLabel("RH · \(r.windSummary ?? "wind —") · \(GlancePhrasing.clockLabel(for: r.observedAt))")
        case .overdue(let o):
            Image(systemName: "exclamationmark.triangle.fill")
                .widgetLabel(GlancePhrasing.overdue(seconds: o.overdueBySeconds))
        }
    }
}
