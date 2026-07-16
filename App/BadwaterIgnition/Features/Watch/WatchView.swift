import SwiftUI
import BadwaterCore

/// The **Watch** screen (Weather Watch — the shift observation log).
///
/// M0 scaffold + M1 capture card: the latest-reading hero over the pending-obs
/// editor (freshness, obs time, humidity source, dry/wet/RH, elevation band,
/// note, and a live PIG preview), all above a fixed Log bar that freezes the
/// current estimate into the shift. Site/wind controls, the broadcast panel, the
/// trend, and the shift log arrive in M2–M6.
///
/// Per the build scope's Decision A, the site/weather inputs live on the shared
/// ``IgnitionModel`` — the same weather the Ignition tab shows — so this screen
/// binds to it directly rather than duplicating state. Structure and tokens
/// mirror ``IgnitionView`` so the two screens read as one system.
struct WatchView: View {
    @Bindable var model: WeatherWatchModel
    @Bindable var ignition: IgnitionModel
    @Environment(\.colorScheme) private var scheme

    /// The timestamp a Log tap will record. Seeded to "now"; editable via the obs
    /// time steppers (off-hour or back-filled readings), reset to now after a log.
    @State private var pendingTime = Date()
    /// The optional caveat for this one reading; cleared after it's logged.
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.cardSpacing) {
                header
                if let latest = model.latest {
                    hero(latest)
                } else {
                    emptyState
                }
                captureCard
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
            Text("Set the reading below, then Log Observation").fieldLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 14)
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

    // MARK: - Pending capture card (M1)

    /// The pending observation the Log button will freeze — computed from the live
    /// inputs and the chosen obs time, so the PIG preview and the freeze agree.
    private var captureCard: some View {
        let pending = model.pendingObs(at: pendingTime)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pending obs").fieldLabel()
                Spacer()
                Text("→ PIG \(pending.estimate.unshaded.probabilityOfIgnition) / \(pending.estimate.shaded.probabilityOfIgnition)")
                    .font(BadwaterFont.label).kerning(0.4)
                    .foregroundStyle(BadwaterColor.accent)
                    .accessibilityIdentifier("pending-pig")
            }
            freshnessStrip
            HStack(spacing: 10) {
                StepperCard(label: "Obs hour", unit: "", value: hourBinding, range: 0...23)
                StepperCard(label: "Obs min", unit: "", value: minuteBinding, range: 0...55, step: 5)
            }
            WeatherInputGroup(model: ignition, sharedWith: "Ignition", showsDerivedHumidity: false)
            noteField
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
    }

    /// How fresh the dry-bulb / RH reading is — a status annunciator that turns to
    /// caution amber and offers "Mark current" once the reading is older than the
    /// staleness window, so a fresh timestamp can't silently freeze hours-old
    /// weather. Always present at a fixed height, so it never shifts the card.
    private var freshnessStrip: some View {
        let stale = model.isPendingWeatherStale()
        let ageMinutes = model.pendingWeatherAge().map { Int($0 / 60) }
        return StatusStrip(
            icon: stale ? "exclamationmark.triangle.fill" : "clock",
            message: freshnessText(stale: stale, ageMinutes: ageMinutes),
            caution: stale,
            actionTitle: stale ? "Mark current" : nil,
            action: stale ? { model.confirmPendingWeatherCurrent() } : nil,
            identifier: "weather-freshness",
            actionIdentifier: "mark-weather-current")
    }

    private func freshnessText(stale: Bool, ageMinutes: Int?) -> String {
        guard let ageMinutes else { return "Weather not read yet" }
        if stale { return "Weather read \(ageMinutes) min ago — confirm current" }
        return ageMinutes == 0 ? "Weather just read" : "Weather read \(ageMinutes) min ago"
    }

    private var noteField: some View {
        TextField("Note (optional) — e.g. sun on thermometer", text: $note, axis: .vertical)
            .font(BadwaterFont.body)
            .lineLimit(1...3)
            .padding(11)
            .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BadwaterColor.hairline))
            .accessibilityIdentifier("obs-note")
    }

    // MARK: - Obs-time bindings (hour / minute of `pendingTime`)

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: pendingTime) },
            set: { pendingTime = setTime(hour: $0, minute: Calendar.current.component(.minute, from: pendingTime)) })
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: pendingTime) },
            set: { pendingTime = setTime(hour: Calendar.current.component(.hour, from: pendingTime), minute: $0) })
    }

    private func setTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: pendingTime) ?? pendingTime
    }

    // MARK: - Log bar

    /// Fixed bottom action: freezes the current estimate — plus the note and the
    /// chosen obs time — into the shift, then resets for the next reading. The
    /// site-confirmation gate that holds the first log of a shift arrives in M2.
    private var logBar: some View {
        Button {
            model.logObs(at: pendingTime, note: note.isEmpty ? nil : note)
            note = ""
            pendingTime = Date()
        } label: {
            HStack(spacing: 10) {
                Text("Log Observation")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("· \(clock(pendingTime))")
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
        .padding(.horizontal, Metric.screenPadding)
        .padding(.top, 10).padding(.bottom, 8)
        .background(BadwaterColor.surface)
        .overlay(alignment: .top) { BadwaterColor.hairline.frame(height: 1) }
    }

    /// Local `"HH:MM"` for the obs-time label on the Log button.
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
    return NavigationStack { WatchView(model: model, ignition: ignition) }
}
