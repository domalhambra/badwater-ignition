import ActivityKit
import WidgetKit
import SwiftUI
import PlateworksCore

/// Lock-screen and Dynamic Island presentations of the obs-cadence countdown.
///
/// There is no Probability of Ignition anywhere in this file, and there is no
/// path by which one could reach it — ``ObsActivityAttributes/ContentState``
/// carries two dates and nothing else. See the display policy in `CLAUDE.md`:
/// a Live Activity exists to count down to the current reading's replacement,
/// so it is the one surface guaranteed to outlive the value it would be showing.
///
/// Every countdown is `Text(timerInterval:)`, which the system re-renders on its
/// own. The app is never woken to tick a clock — the same reason the widget's
/// timeline policy is `.never`.
struct ObsCountdownLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ObsActivityAttributes.self) { context in
            // Lock screen / banner.
            LockScreenCountdown(context: context)
                .padding()
                .activityBackgroundTint(PlateworksColor.surface)
                .activitySystemActionForegroundColor(PlateworksColor.ink)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Obs \(GlancePhrasing.clockLabel(for: context.state.observedAt))",
                          systemImage: "thermometer.medium")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.siteLabel)
                        .font(.caption)
                        .foregroundStyle(PlateworksColor.muted)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CountdownLine(dueAt: context.state.dueAt)
                        .font(.title3.weight(.semibold))
                }
            } compactLeading: {
                Image(systemName: "thermometer.medium")
            } compactTrailing: {
                // Compact has room for one thing: how long until the next obs.
                Text(timerInterval: countdownRange(to: context.state.dueAt),
                     countsDown: true)
                    .frame(maxWidth: 44)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "thermometer.medium")
            }
        }
    }
}

/// `Text(timerInterval:)` needs a range it is inside. Once the due moment has
/// passed the presentation switches to counting *up*, so the range starts there.
private func countdownRange(to dueAt: Date) -> ClosedRange<Date> {
    let now = Date()
    return now < dueAt ? now...dueAt : dueAt...now.addingTimeInterval(1)
}

private struct LockScreenCountdown: View {
    let context: ActivityViewContext<ObsActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last obs \(GlancePhrasing.clockLabel(for: context.state.observedAt))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlateworksColor.ink)
                Spacer()
                Text(context.attributes.siteLabel)
                    .font(.caption)
                    .foregroundStyle(PlateworksColor.muted)
                    .lineLimit(1)
            }
            CountdownLine(dueAt: context.state.dueAt)
                .font(.title2.weight(.bold))
        }
    }
}

/// "Next obs in 12:34" before the due moment; "Obs overdue 4:05" after it.
///
/// The switch happens at `dueAt` — the same boundary ``ObsGlance`` uses to stop
/// showing a number, so this surface and the widget change job at the same
/// instant rather than a minute apart.
private struct CountdownLine: View {
    let dueAt: Date

    var body: some View {
        let overdue = Date() >= dueAt
        HStack(spacing: 6) {
            Text(overdue ? "Obs overdue" : "Next obs in")
                .font(.caption)
                .foregroundStyle(overdue ? PlateworksColor.caution : PlateworksColor.muted)
            Text(timerInterval: countdownRange(to: dueAt), countsDown: !overdue)
                .monospacedDigit()
                .foregroundStyle(overdue ? PlateworksColor.caution : PlateworksColor.ink)
        }
    }
}
