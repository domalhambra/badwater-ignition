import SwiftUI
import BadwaterCore

/// The single watch screen.
///
/// Renders from `snapshot.glance(at:)` — **not** from the raw snapshot. That is
/// the whole point: application context is delivered opportunistically, so the
/// reading on the wrist may have been sent an hour ago and may have been read
/// back off disk after that. Whether it is still showable is decided here,
/// against this device's clock, by the same rule the widget applies.
///
/// The screen re-decides on a timer as well as on delivery, so a wrist left
/// raised across the due moment flips to the overdue annunciation rather than
/// holding a superseded number until something else happens.
struct WatchGlanceView: View {

    let receiver: WatchSessionReceiver
    @State private var now = Date()

    private var glance: ObsGlance {
        receiver.snapshot?.glance(at: now) ?? .none
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                switch glance {
                case .none:
                    Text("No obs logged")
                        .font(.headline)
                    Text("Log one on the phone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                case .reading(let r):
                    // Time first and at full weight. A number without its time
                    // is the failure this design exists to avoid.
                    Text("Obs \(GlancePhrasing.clockLabel(for: r.observedAt))")
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(r.pigUnshaded)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(r.behavior.color)
                        Text("%")
                            .font(.headline)
                            .foregroundStyle(r.behavior.color)
                    }
                    Text("PIG unshaded · \(r.pigShaded)% shaded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(r.behavior.title)
                        .font(.caption)
                    Text(GlancePhrasing.age(seconds: r.ageSeconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                case .overdue(let o):
                    // No number on this path — it isn't in scope.
                    Text(GlancePhrasing.overdue(seconds: o.overdueBySeconds))
                        .font(.headline)
                        .foregroundStyle(BadwaterColor.caution)
                    Text("Last obs \(GlancePhrasing.clockLabel(for: o.observedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let site = receiver.snapshot?.siteLabel, !site.isEmpty {
                    Text(site)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Obs")
        // Suspends with the view, so a backgrounded watch app isn't ticking.
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
