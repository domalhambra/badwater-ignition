import WidgetKit
import SwiftUI
import BadwaterCore

/// The latest **logged** observation, on the home screen and the lock screen.
///
/// Two families only. `systemSmall` for the home screen, and
/// `accessoryRectangular` for the lock screen — which is where this is actually
/// read, without unlocking a phone, in gloves.
///
/// Everything below follows from the display policy in `CLAUDE.md`: this surface
/// shows a **frozen** observation, always with its time and age, and once that
/// observation is superseded it stops showing a number and annunciates the
/// cadence instead. The live estimate never reaches here.
struct LatestObsWidget: Widget {
    let kind = "LatestObsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestObsProvider()) { entry in
            LatestObsWidgetView(glance: entry.glance)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Latest Obs")
        .description("The last logged weather observation, with its time and age.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct LatestObsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let glance: ObsGlance

    var body: some View {
        switch family {
        case .accessoryRectangular: RectangularGlance(glance: glance)
        default: SmallGlance(glance: glance)
        }
    }
}

// MARK: - Home screen

/// The three states are three separate branches on purpose. `.overdue` has no
/// access to a Probability of Ignition here — not a dimmed one, not a caveated
/// one — because the value simply isn't in scope on that path.
private struct SmallGlance: View {
    let glance: ObsGlance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch glance {
            case .none:
                Text("No obs logged")
                    .font(.headline)
                    .foregroundStyle(BadwaterColor.muted)

            case .reading(let r):
                // The time is as prominent as the number. A PIG without its time
                // is precisely the failure this whole design avoids, so they are
                // set at the same weight and never separated.
                Text(GlancePhrasing.clockLabel(for: r.observedAt))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(BadwaterColor.ink)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(r.pigUnshaded)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(r.behavior.color)
                    Text("%")
                        .font(.headline)
                        .foregroundStyle(r.behavior.color)
                }
                Text("PIG unshaded · \(r.pigShaded)% shaded")
                    .font(.caption2)
                    .foregroundStyle(BadwaterColor.muted)
                Text(GlancePhrasing.age(seconds: r.ageSeconds))
                    .font(.caption)
                    .foregroundStyle(BadwaterColor.muted)

            case .overdue(let o):
                // Changed job. No number at all — the crew is being told to take
                // a reading, not handed one to date-check.
                Text(GlancePhrasing.overdue(seconds: o.overdueBySeconds))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(BadwaterColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Last obs \(GlancePhrasing.clockLabel(for: o.observedAt))")
                    .font(.caption)
                    .foregroundStyle(BadwaterColor.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen

/// The accessory families render monochrome — the system tints them and ignores
/// `foregroundStyle`. The severity ramp therefore carries no meaning here, so
/// the reading leads with its time and states the band in words instead of
/// relying on a colour that will not survive.
private struct RectangularGlance: View {
    let glance: ObsGlance

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch glance {
            case .none:
                Text("No obs logged").font(.headline)

            case .reading(let r):
                Text("Obs \(GlancePhrasing.clockLabel(for: r.observedAt))")
                    .font(.headline)
                Text("PIG \(r.pigUnshaded)% · \(r.pigShaded)% shaded")
                    .font(.body)
                Text("\(r.behavior.title) · \(GlancePhrasing.age(seconds: r.ageSeconds))")
                    .font(.caption)

            case .overdue(let o):
                Text(GlancePhrasing.overdue(seconds: o.overdueBySeconds))
                    .font(.headline)
                Text("Last obs \(GlancePhrasing.clockLabel(for: o.observedAt))")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
