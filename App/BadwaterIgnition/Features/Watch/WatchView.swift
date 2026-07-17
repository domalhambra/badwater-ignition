import SwiftUI
import Combine
import BadwaterCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The **Watch** screen (Weather Watch — the shift observation log).
///
/// The full loop: the latest-reading hero and its frozen radio broadcast, a
/// shift trend, the shift log (with delete + undo), the sticky site / radio
/// header, the pending-obs capture card (weather is the shared ``IgnitionModel``,
/// so it mirrors the Ignition tab), and the shift exports (IMET `.xlsx`, NWS
/// spot, Notes). The first log of a shift is gated on an explicit site review, so
/// a persisted default can never silently feed a broadcast.
struct WatchView: View {
    @Bindable var model: WeatherWatchModel
    @Bindable var ignition: IgnitionModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    /// The timestamp a Log tap will record. Seeded to "now"; editable via the obs
    /// time steppers (off-hour or back-filled readings), reset to now after a log.
    @State private var pendingTime = Date()
    /// The optional caveat for this one reading; cleared after it's logged.
    @State private var note = ""
    /// Typed site coordinate (committed to the model only when both parse).
    @State private var latText = ""
    @State private var lonText = ""
    /// Whether an undo affordance for the last delete is showing.
    @State private var showUndo = false
    /// Drives the IMET `.xlsx` export sheet.
    @State private var exportingWorkbook = false
    /// Guards the destructive new-shift action behind a confirm.
    @State private var confirmNewShift = false
    /// Wall-clock reference for the "next obs due" countdown; ticks every 30 s and
    /// refreshes on foreground so the strip counts down without a manual nudge.
    @State private var now = Date()
    private let dueTick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Standard hourly weather-watch cadence for the next observation.
    private let obsCadence: TimeInterval = 60 * 60
    /// Which metric the shift trend plots.
    @State private var trendMetric: ObservationMetric = .probabilityOfIgnitionUnshaded

    private var hasObs: Bool { !model.shift.obs.isEmpty }
    private var canTrend: Bool { model.shift.obs.count >= 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                header
                obsDueStrip
                if let latest = model.latest {
                    hero(latest)
                    broadcastSection(latest)
                } else {
                    emptyState
                }
                if canTrend { trendSection }
                if hasObs { shiftLogSection }
                siteSection
                captureCard
                if hasObs { exportSection }
                if hasObs { newShiftRow }
                disclaimer
            }
            .padding(Metric.screenPadding)
        }
        .safeAreaInset(edge: .bottom) { logBar }
        .background(BadwaterColor.background)
        .navigationTitle("Obs")
        .onReceive(dueTick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
        .onAppear {
            now = Date()
            if let c = model.siteCoordinate {
                latText = String(c.latitude)
                lonText = String(c.longitude)
            }
        }
    }

    // MARK: - Next-obs-due annunciator

    /// Always-present cadence strip: how long until the next hourly observation is
    /// due (from the last logged obs), turning to caution amber within 5 minutes
    /// of — and after — the due time, so a weather watch stays a *prospective*
    /// discipline rather than a log noticed an hour late. No obs yet ⇒ take one now.
    private var obsDueStrip: some View {
        let icon: String, message: String, caution: Bool
        if let last = model.latest?.timestamp {
            let due = last.addingTimeInterval(obsCadence)
            let mins = Int(due.timeIntervalSince(now) / 60)   // truncates toward zero
            if mins <= 5 {
                caution = true
                icon = "clock.badge.exclamationmark"
                message = mins >= 0
                    ? "Obs due now · \(clock(due))"
                    : "Obs overdue \(-mins) min · was due \(clock(due))"
            } else {
                caution = false
                icon = "clock"
                message = "Next obs \(clock(due)) · in \(mins) min"
            }
        } else {
            caution = false
            icon = "clock"
            message = "First obs of the shift — take one now"
        }
        return StatusStrip(icon: icon, message: message, caution: caution, identifier: "obs-due")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Obs").font(BadwaterFont.title).foregroundStyle(BadwaterColor.ink)
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

    // MARK: - Broadcast panel (M4)

    /// The full spoken broadcast for the latest obs — the frozen script that went
    /// out over the air — with a Share action for the radio operator.
    private func broadcastSection(_ obs: WeatherObs) -> some View {
        let script = model.broadcastScript(for: obs)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Broadcast", annotation: "Radio")
            Text(script)
                .font(BadwaterFont.body)
                .foregroundStyle(BadwaterColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .padding(.top, 10)   // leave room for the inset Copy pill
                .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.hairline))
                .overlay(alignment: .topTrailing) {
                    Button { copyToPasteboard(script) } label: {
                        Text("Copy")
                            .font(BadwaterFont.labelSmall).fontWeight(.bold)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(BadwaterColor.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(BadwaterColor.accent, lineWidth: 1))
                            .foregroundStyle(BadwaterColor.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .accessibilityIdentifier("copy-broadcast")
                }
                .accessibilityIdentifier("broadcast-script")
        }
    }

    // MARK: - Trend (M5)

    private func trendPoints(_ metric: ObservationMetric) -> [TrendPoint] {
        model.series(of: metric).compactMap { pt in
            pt.value.map { TrendPoint(date: pt.date, value: $0) }
        }
    }

    private var trendSection: some View {
        let points = trendPoints(trendMetric)
        // Percent metrics pin to 0–100; °F metrics (temp / dew point) auto-fit.
        let vals = points.map(\.value)
        let domain: ClosedRange<Int> = trendMetric.unit == "%"
            ? 0...100
            : ((vals.min() ?? 0) - 5)...((vals.max() ?? 100) + 5)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Trend", annotation: trendMetric.shortLabel)
            ChipPicker(title: "Metric", options: ObservationMetric.allCases,
                       selection: $trendMetric, label: \.shortLabel)
            if points.count >= 2 {
                ShiftTrendChart(points: points, domain: domain, unit: trendMetric.unit)
                    .padding(12)
                    .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.hairline))
            } else {
                Text("Not enough observations record \(trendMetric.shortLabel.lowercased()) yet.")
                    .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Shift log + delete/undo (M3)

    private var shiftLogSection: some View {
        let ordered = model.shift.obs.sorted { $0.timestamp > $1.timestamp }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Shift log", annotation: "\(model.shift.obs.count) obs")
            if showUndo, model.lastRemovedObs != nil {
                StatusStrip(icon: "arrow.uturn.backward", message: "Observation removed",
                            caution: true, actionTitle: "Undo",
                            action: { model.undoRemoveObs(); showUndo = false },
                            identifier: "undo-strip", actionIdentifier: "undo-remove")
            }
            ForEach(ordered) { obs in logRow(obs) }
        }
    }

    private func logRow(_ obs: WeatherObs) -> some View {
        let e = obs.estimate
        return HStack(spacing: 12) {
            Text(obs.timeLabel())
                .font(BadwaterFont.readout(17)).monospacedDigit()
                .foregroundStyle(BadwaterColor.ink)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("PIG \(e.unshaded.probabilityOfIgnition)/\(e.shaded.probabilityOfIgnition)")
                        .font(BadwaterFont.label).foregroundStyle(BadwaterColor.ink)
                    if let wind = obs.wind {
                        Text(wind.spotString).font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
                    }
                }
                if let note = obs.note, !note.isEmpty {
                    Text(note).font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                model.removeObs(id: obs.id)
                showUndo = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BadwaterColor.caution)
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("delete-obs")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.hairline))
    }

    // MARK: - Site & radio header + confirmation gate (M2)

    private var siteSection: some View {
        VStack(alignment: .leading, spacing: Metric.cardSpacing) {
            SectionHeader(title: "Site & radio", annotation: "IMET header")
            siteGate
            VStack(alignment: .leading, spacing: 10) {
                labeledField("Radio addressee", "e.g. Division W", $model.addressee)
                labeledField("Location name", "e.g. 659 Road", locationNameBinding)
                labeledField("Division", "e.g. Division W", divisionBinding)
                labeledField("Site elevation", "feet MSL", siteElevationBinding, numeric: true)
                HStack(spacing: 10) {
                    labeledField("Latitude", "38.214", $latText, numeric: true, decimal: true)
                    labeledField("Longitude", "-112.398", $lonText, numeric: true, decimal: true)
                }
            }
            .onChange(of: latText) { _, _ in commitCoordinate() }
            .onChange(of: lonText) { _, _ in commitCoordinate() }
        }
    }

    /// The once-per-shift site review that gates the first log (red-team #9).
    @ViewBuilder private var siteGate: some View {
        if model.needsSiteConfirmation {
            StatusStrip(icon: "checkmark.shield", message: "Review the site factors, then confirm",
                        caution: true, actionTitle: "Confirm site",
                        action: { model.confirmSite() },
                        identifier: "site-gate", actionIdentifier: "confirm-site")
        } else {
            StatusStrip(icon: "checkmark.shield.fill", message: "Site confirmed for this shift",
                        identifier: "site-confirmed")
        }
    }

    private func commitCoordinate() {
        if let la = Double(latText), let lo = Double(lonText) {
            model.siteCoordinate = GeoPoint(latitude: la, longitude: lo)
        } else {
            model.siteCoordinate = nil
        }
    }

    private var locationNameBinding: Binding<String> {
        Binding(get: { model.shift.locationName ?? "" },
                set: { model.shift.locationName = $0.isEmpty ? nil : $0 })
    }
    private var divisionBinding: Binding<String> {
        Binding(get: { model.shift.division ?? "" },
                set: { model.shift.division = $0.isEmpty ? nil : $0 })
    }
    private var siteElevationBinding: Binding<String> {
        Binding(get: { model.siteElevationFeet.map(String.init) ?? "" },
                set: { model.siteElevationFeet = Int($0) })
    }

    private func labeledField(_ label: String, _ placeholder: String, _ text: Binding<String>,
                              numeric: Bool = false, decimal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).fieldLabel()
            TextField(placeholder, text: text)
                .font(BadwaterFont.body)
                .keyboard(numeric: numeric, decimal: decimal)
                .padding(11)
                .frame(minHeight: Metric.tapTarget, alignment: .leading)
                .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BadwaterColor.hairline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ObsTimeField(time: $pendingTime)
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

    // MARK: - Exports (M4)

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Export shift", annotation: "Share")
            HStack(spacing: 10) {
                Button { exportingWorkbook = true } label: { actionLabel("IMET .xlsx", "tablecells") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("export-imet")
                ShareLink(item: model.spotObservationsText()) { actionLabel("Spot obs", "doc.plaintext") }
                    .accessibilityIdentifier("export-spot")
            }
            ShareLink(item: model.notesText()) { actionLabel("Notes table", "note.text") }
                .accessibilityIdentifier("export-notes")
        }
        .fileExporter(
            isPresented: $exportingWorkbook,
            document: exportingWorkbook ? IMETWorkbookDocument(data: model.imetWorkbookData())
                                        : IMETWorkbookDocument(data: Data()),
            contentType: IMETWorkbookDocument.xlsx,
            defaultFilename: "BadwaterIgnition-shift"
        ) { _ in }
    }

    // MARK: - New shift (M3)

    private var newShiftRow: some View {
        Button { confirmNewShift = true } label: { actionLabel("Start new shift", "plus.circle") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("new-shift")
            .confirmationDialog("Start a new shift? The current shift's log is cleared.",
                                isPresented: $confirmNewShift, titleVisibility: .visible) {
                Button("Start new shift", role: .destructive) {
                    model.startNewShift()
                    pendingTime = Date()
                    note = ""
                    showUndo = false
                }
                Button("Cancel", role: .cancel) { }
            }
    }

    /// A bordered secondary action label (teal outline) shared by the export,
    /// broadcast, and new-shift buttons.
    private func actionLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(BadwaterFont.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.accent, lineWidth: 1.5))
        .foregroundStyle(BadwaterColor.accent)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text("No observations yet")
                .font(BadwaterFont.title).foregroundStyle(BadwaterColor.ink)
            Text("Confirm the site, set the reading, then Log Observation").fieldLabel()
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

    // MARK: - Log bar

    /// Fixed bottom action: freezes the current estimate — plus the wind, note, and
    /// chosen obs time — into the shift, then resets for the next reading. Disabled
    /// until the site has been confirmed for the shift (the first-log gate).
    private var logBar: some View {
        let gated = model.needsSiteConfirmation
        return Button {
            model.logObs(at: pendingTime, wind: ignition.wind, note: note.isEmpty ? nil : note)
            note = ""
            // Pre-fill the next hourly slot so the operator isn't re-entering the
            // time every observation (an off-hour read can still be tap-typed).
            pendingTime = pendingTime.addingTimeInterval(obsCadence)
        } label: {
            HStack(spacing: 10) {
                Text(gated ? "Confirm site to log" : "Log Observation")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                if !gated {
                    Text("· \(clock(pendingTime))")
                        .font(BadwaterFont.label).monospacedDigit().opacity(0.85)
                }
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
        .disabled(gated)
        .opacity(gated ? 0.5 : 1)
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

private extension View {
    /// Numeric keyboards are iOS-only; on macOS this is a no-op so the shared view
    /// compiles for both destinations.
    @ViewBuilder func keyboard(numeric: Bool, decimal: Bool) -> some View {
        #if os(iOS)
        self.keyboardType(numeric ? (decimal ? .numbersAndPunctuation : .numberPad) : .default)
        #else
        self
        #endif
    }
}

/// The observation-time control: tap the value to **type** a time directly
/// ("1435" or "14:35"), or nudge it ±5 minutes. Two-way bound to the pending-obs
/// timestamp, so typing, nudging, and the reset-to-now after a log all agree.
private struct ObsTimeField: View {
    @Binding var time: Date
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Obs time").fieldLabel()
            HStack(spacing: 8) {
                TextField("HH:MM", text: $text)
                    .font(BadwaterFont.inputValue).monospacedDigit()
                    .keyboard(numeric: true, decimal: false)
                    .frame(maxWidth: 92)
                    .accessibilityIdentifier("obs-time-field")
                    .onChange(of: text) { _, v in
                        if let hm = parseHourMinute(v) { time = settingHourMinute(time, hm.0, hm.1) }
                    }
                Spacer(minLength: 6)
                nudge("−5m", -5)
                nudge("+5m", 5)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
        .onAppear { text = formatHourMinute(time) }
        .onChange(of: time) { _, t in
            // Resync the field when the time changed from a nudge or a post-log
            // reset — but not from the user's own typing (parse already matches).
            let c = Calendar.current.dateComponents([.hour, .minute], from: t)
            let parsed = parseHourMinute(text)
            if parsed?.0 != c.hour || parsed?.1 != c.minute { text = formatHourMinute(t) }
        }
        .accessibilityIdentifier("obs-time")
    }

    private func nudge(_ label: String, _ minutes: Int) -> some View {
        Button { time = shiftingMinutes(time, minutes) } label: {
            Text(label)
                .font(BadwaterFont.labelSmall).fontWeight(.bold)
                .foregroundStyle(BadwaterColor.ink)
                .frame(minWidth: 46, minHeight: Metric.tapTarget)
                .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Parse `"HH:MM"` / `"HHMM"` / `"H"` into clamped (hour, minute), or nil if the
/// text doesn't yield a valid clock time (so a half-typed field leaves the time
/// alone).
private func parseHourMinute(_ s: String) -> (Int, Int)? {
    let cleaned = s.filter { $0.isNumber || $0 == ":" }
    var h = 0, m = 0
    if cleaned.contains(":") {
        let parts = cleaned.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        h = Int(parts[0]) ?? 0
        m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
    } else {
        let digits = cleaned.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        if digits.count <= 2 {
            h = Int(digits) ?? 0
        } else {
            h = Int(digits.prefix(digits.count - 2)) ?? 0
            m = Int(digits.suffix(2)) ?? 0
        }
    }
    guard (0...23).contains(h), (0...59).contains(m) else { return nil }
    return (h, m)
}

private func formatHourMinute(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

private func settingHourMinute(_ base: Date, _ h: Int, _ m: Int) -> Date {
    Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base
}

private func shiftingMinutes(_ base: Date, _ minutes: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minutes, to: base) ?? base
}

/// Copy text to the system pasteboard — the inset "Copy" pill on the broadcast
/// panel. Platform-guarded so the view compiles for iOS and macOS.
private func copyToPasteboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}

#Preview {
    let ignition = IgnitionModel()
    ignition.dryBulbF = 90
    ignition.relativeHumidity = 8
    let model = WeatherWatchModel(ignition: ignition)
    model.confirmSite()
    model.logObs()
    return NavigationStack { WatchView(model: model, ignition: ignition) }
}
