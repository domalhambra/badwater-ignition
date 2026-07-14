import SwiftUI
import BadwaterCore

/// The **Watch** screen (Weather Watch — the shift observation log).
///
/// M0 scaffold: the latest-reading hero (both PIG results + the radio line) over
/// a fixed Log bar that freezes the current estimate into the shift. The pending
/// capture card, site/wind controls, trend, and shift log arrive in later
/// milestones; this slice proves the shell, the shared-`IgnitionModel` wiring,
/// and the log loop end to end.
///
/// Structure and tokens mirror ``IgnitionView`` — the same `ScrollView` + card
/// grammar, the same `ResultCard`, so the two screens read as one system.
struct WatchView: View {
    @Bindable var model: WeatherWatchModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.cardSpacing) {
                header
                if let latest = model.latest {
                    hero(latest)
                } else {
                    emptyState
                }
                disclaimer
            }
            .padding(Metric.screenPadding)
        }
        .safeAreaInset(edge: .bottom) { logBar }
        .background(BadwaterColor.background)
        .navigationTitle("Watch")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Watch").font(BadwaterFont.title).foregroundStyle(BadwaterColor.ink)
            Spacer()
            Text(shiftSummary).fieldLabel()
        }
    }

    private var shiftSummary: String {
        let n = model.shift.obs.count
        return n == 0 ? "IRPG PMS 461" : "\(n) obs this shift"
    }

    // MARK: - Latest-reading hero

    private func hero(_ obs: WeatherObs) -> some View {
        let e = obs.estimate
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(obs.timeLabel())
                    .font(BadwaterFont.readout(24))
                    .foregroundStyle(BadwaterColor.ink)
                Text("Latest").fieldLabel()
                Spacer()
            }
            HStack(spacing: 10) {
                ResultCard(title: "Unshaded", pig: e.unshaded.probabilityOfIgnition,
                           severity: e.unshaded.interpretation.color,
                           subtitle: "FFM \(e.unshaded.fineFuelMoisture)% · <50% shade")
                ResultCard(title: "Shaded", pig: e.shaded.probabilityOfIgnition,
                           severity: e.shaded.interpretation.color,
                           subtitle: "FFM \(e.shaded.fineFuelMoisture)% · ≥50% shade")
            }
            radioLine(obs)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Metric.resultRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.resultRadius).strokeBorder(BadwaterColor.hairline))
    }

    /// The radio-ready broadcast line, e.g. "Wx obs 1430, temp 90, RH 8, …".
    private func radioLine(_ obs: WeatherObs) -> some View {
        Text(obs.radioLine(timeLabel: obs.timeLabel()))
            .font(BadwaterFont.labelSmall)
            .foregroundStyle(BadwaterColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BadwaterColor.hairline))
            .accessibilityIdentifier("radio-line")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text("No observations yet")
                .font(BadwaterFont.title).foregroundStyle(BadwaterColor.ink)
            Text("Set the reading, then Log Observation").fieldLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30).padding(.horizontal, 14)
        .background(BadwaterColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.cardRadius)
                .strokeBorder(BadwaterColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .accessibilityIdentifier("watch-empty")
    }

    private var disclaimer: some View {
        Text("PIG is app-computed — not observed, not a forecast. Verify against your IRPG.")
            .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: - Log bar

    /// Fixed bottom action: freezes the current estimate into the shift. The
    /// live clock shows the timestamp the tap will record. The site-confirmation
    /// gate (which holds the first log of a shift) arrives in M2.
    private var logBar: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Button {
                model.logObs()
            } label: {
                HStack(spacing: 10) {
                    Text("Log Observation")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("· \(clock(context.date))")
                        .font(BadwaterFont.label).monospacedDigit().opacity(0.85)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(scheme == .dark ? Color.clear : BadwaterColor.accent,
                            in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    if scheme == .dark {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(BadwaterColor.accent, lineWidth: 1.5)
                    }
                }
                .foregroundStyle(scheme == .dark ? BadwaterColor.accent : Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("log-observation")
        }
        .padding(.horizontal, Metric.screenPadding)
        .padding(.top, 10).padding(.bottom, 8)
        .background(BadwaterColor.surface)
        .overlay(alignment: .top) { BadwaterColor.hairline.frame(height: 1) }
    }

    /// Local `"HH:MM"` for the log-bar clock.
    private func clock(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

#Preview {
    let ignition = IgnitionModel()
    ignition.dryBulbF = 90
    ignition.relativeHumidity = 8
    let model = WeatherWatchModel(ignition: ignition)
    model.logObs()
    return NavigationStack { WatchView(model: model) }
}
