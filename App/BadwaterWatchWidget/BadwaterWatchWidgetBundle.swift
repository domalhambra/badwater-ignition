import WidgetKit
import SwiftUI
import BadwaterCore

/// The watch complication — the highest-value surface in 3.5, and the one a
/// crew actually reads: it is on the face, so it costs nothing to look at.
///
/// It reads the snapshot the watch app persisted (see ``WatchSnapshotStore``)
/// and applies the **same** staleness rule as the phone widget, against this
/// device's clock. Past the due moment it shows no number at all — it
/// annunciates the cadence instead. See the display policy in `CLAUDE.md`.
@main
struct BadwaterWatchWidgetBundle: WidgetBundle {
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
        .description("The last logged observation's PIG, with its time.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let glance: ObsGlance

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line, system-rendered. Room for the number and its time, which
            // is the minimum this surface is allowed to show.
            switch glance {
            case .none: Text("No obs")
            case .reading(let r):
                Text("PIG \(r.pigUnshaded)% · \(GlancePhrasing.clockLabel(for: r.observedAt))")
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

/// Circular is the tightest of the three. It gets the number and the obs time
/// and nothing else — and on the overdue path, the interval instead of the
/// number. There is no room for an age *and* a time, so it shows the time: an
/// age with no anchor is the one thing worse than neither.
private struct CircularGlance: View {
    let glance: ObsGlance

    var body: some View {
        VStack(spacing: 0) {
            switch glance {
            case .none:
                Text("--").font(.title3)
                Text("no obs").font(.system(size: 10))
            case .reading(let r):
                Text("\(r.pigUnshaded)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(GlancePhrasing.clockLabel(for: r.observedAt))
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
            Text("\(r.pigUnshaded)%")
                .widgetLabel("PIG · \(GlancePhrasing.clockLabel(for: r.observedAt))")
        case .overdue(let o):
            Image(systemName: "exclamationmark.triangle.fill")
                .widgetLabel(GlancePhrasing.overdue(seconds: o.overdueBySeconds))
        }
    }
}
