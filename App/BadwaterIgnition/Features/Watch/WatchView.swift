import SwiftUI
import BadwaterCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The **Watch** screen (Weather Watch — the shift observation log).
///
/// The full loop: the latest-reading hero and its frozen radio broadcast, a
/// shift trend, the shift log (with delete + undo), the site & radio block
/// (``SiteEditor``, which also owns the GPS position autofill), the pending-obs
/// capture card (weather is the shared ``IgnitionModel``,
/// so it mirrors the Ignition tab), and the shift exports (IMET `.xlsx`, NWS
/// spot, Notes). The first log of a shift is gated on an explicit site review, so
/// a persisted default can never silently feed a broadcast.
@MainActor
struct WatchView: View {
    @Bindable var model: WeatherWatchModel
    @Bindable var ignition: IgnitionModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    /// The timestamp a Log tap will record. Seeded to "now" and **re-seeded** as
    /// the clock moves (on the tick, on appear, on foreground) unless the
    /// operator has taken it over by typing or nudging — see ``obsTimeIsManual``.
    @State private var pendingTime = Date()
    /// The value this view last auto-seeded ``pendingTime`` to. Comparing the two
    /// is how a manual edit is detected without threading a callback through
    /// `ObsTimeField`: any type or nudge moves `pendingTime` away from this.
    @State private var autoSeededObsTime = Date()
    /// The optional caveat for this one reading; cleared after it's logged.
    @State private var note = ""
    /// The workbook bytes for a presented export sheet, built once when the
    /// export is requested rather than on every body pass.
    @State private var workbookDocument: IMETWorkbookDocument?
    /// Whether an undo affordance for the last delete is showing.
    @State private var showUndo = false
    /// The logged observation being corrected in the edit sheet (nil = closed).
    @State private var editingObs: WeatherObs?
    /// Drives the IMET `.xlsx` export sheet.
    @State private var exportingWorkbook = false
    /// Guards the new-shift action (which archives the current shift) behind a confirm.
    @State private var confirmNewShift = false
    /// Guards the destructive clear-all-history action behind a confirm.
    @State private var confirmClearHistory = false
    /// The archived day pending deletion (nil = no confirm showing).
    @State private var shiftToDelete: Shift?
    /// Wall-clock reference for the "next obs due" countdown and the pending obs
    /// time. Advanced by a `.task` loop (see ``body``) rather than a
    /// `Timer.publish` — an autoconnected publisher keeps a run-loop source alive
    /// for as long as the view exists, including while the Obs tab is off screen,
    /// and every tick re-evaluated this whole body. Battery is a safety input on
    /// a 16-hour shift.
    @State private var now = Date()

    /// Standard hourly weather-watch cadence for the next observation.
    private let obsCadence: TimeInterval = 60 * 60
    /// Which metric the shift trend plots.
    @State private var trendMetric: ObservationMetric = .probabilityOfIgnitionUnshaded
    /// Haptic triggers. A gloved tap on a phone held at arm's length gives no
    /// tactile confirmation of its own, and the operator is usually looking at
    /// the weather rather than the screen — so a log and a delete each announce
    /// themselves. `.success` for a log, `.warning` for a deletion, matching what
    /// those feedbacks mean everywhere else on the platform.
    @State private var logHaptic = 0
    @State private var deleteHaptic = 0
    /// Schedules the "next obs due" reminder so the cadence survives the app
    /// being backgrounded — the on-screen countdown only works while it isn't.
    #if canImport(UserNotifications)
    @State private var cadence = ObsCadenceScheduler(center: SystemNotificationCenter())
    #endif

    /// Owns the lock-screen / Dynamic Island countdown. Created once with the
    /// view, and adopts any activity already running from a previous launch —
    /// without that, a relaunch orphans the old countdown and starts a second
    /// one, and the crew sees two that disagree.
    #if os(iOS)
    @State private var obsActivity = ObsActivityController()
    #endif

    private var hasObs: Bool { !model.shift.obs.isEmpty }
    /// The trend overlays every retained day, so it's available once ≥2 obs exist
    /// across the history and the current shift (not just the current one).
    private var canTrend: Bool { model.allShifts.reduce(0) { $0 + $1.obs.count } >= 2 }
    /// There's something to export/manage when the current shift has obs or any day
    /// is retained in history (so the export + record controls survive a fresh shift).
    private var hasExportableData: Bool { hasObs || !model.history.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                header
                if model.persistenceFailed { persistenceWarning }
                obsDueStrip
                if let latest = model.latest {
                    hero(latest)
                    broadcastSection(latest)
                } else {
                    emptyState
                }
                if canTrend { trendSection }
                if hasObs { shiftLogSection }
                SiteEditor(model: model)
                captureCard
                if hasExportableData { exportSection }
                if !model.history.isEmpty { historySection }
                if hasObs { newShiftRow }
                disclaimer
            }
            .padding(Metric.screenPadding)
        }
        .safeAreaInset(edge: .bottom) { logBar }
        .sheet(item: $editingObs) { obs in
            ObsEditSheet(original: obs) { time, dry, rh, wet, wind, editedNote in
                model.updateObs(id: obs.id, timestamp: time, dryBulbF: dry,
                                relativeHumidity: rh, wetBulbF: wet, wind: wind, note: editedNote)
                rescheduleCadence()
            }
        }
        .background(BadwaterColor.background)
        .navigationTitle("Obs")
        // Suspends with the view: leaving the tab cancels the loop, and a
        // suspended app doesn't run it at all.
        .task {
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { tick() } }
        .onAppear { tick() }
        .sensoryFeedback(.success, trigger: logHaptic)
        .sensoryFeedback(.warning, trigger: deleteHaptic)
    }

    /// Re-point the due reminder at the shift's current latest observation, and
    /// refresh the surfaces that mirror the record. A delete, an undo, or a
    /// corrected timestamp can all move the next-obs moment, and a stale
    /// reminder would fire for a reading that no longer exists.
    private func rescheduleCadence() {
        #if canImport(UserNotifications)
        cadence.reschedule(latestObs: model.latest?.timestamp)
        #endif
        reloadGlanceSurfaces()
    }

    /// Tell every glanceable surface the record moved — the widget, and the
    /// Live Activity counting down to the next observation.
    ///
    /// The widget's timeline policy is `.never` — two entries and done — so it
    /// refreshes only when asked. That is what makes it free to run for a
    /// 16-hour shift, and it is also why every mutation has to call this: miss
    /// one and the home screen keeps showing a superseded reading with no clock
    /// to correct it.
    ///
    /// Called from all five: log, edit, delete, undo, new shift. Note that the
    /// log and new-shift paths do **not** route through ``rescheduleCadence()``
    /// — they talk to the scheduler directly, one to ask permission first and
    /// one to cancel rather than re-point — so they call this themselves.
    private func reloadGlanceSurfaces() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        #if os(iOS)
        // One call for all five events: the controller works out start vs
        // update vs end from what the shift's latest observation now is. An
        // empty shift — last obs deleted, or a new shift — ends the countdown.
        obsActivity.sync(latest: model.latest, siteLabel: liveActivitySiteLabel)
        #endif
    }

    /// The division or location the countdown is captioned with. Fixed for the
    /// activity's life, so it is only read when one starts.
    private var liveActivitySiteLabel: String? {
        for candidate in [model.shift.division, model.shift.locationName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Advance the wall-clock reference and re-seed the pending obs time with it.
    private func tick() {
        now = Date()
        reseedObsTime(now)
    }

    // MARK: - Pending obs time

    /// True once the operator has typed or nudged the obs time — detected by the
    /// value having moved away from what this view last auto-seeded. Auto-seeding
    /// then stands down until the next log.
    ///
    /// Compared at **minute** granularity, not by equality: `ObsTimeField` echoes
    /// the value back through its `"HH:MM"` text field, and that round trip zeroes
    /// the seconds. An exact comparison would read the echo as a manual edit and
    /// stop the clock tracking within one tick of the view appearing — the very
    /// bug this mechanism exists to fix. Every real edit (typing a different time,
    /// a ±5 m nudge) moves the value by at least a minute.
    private var obsTimeIsManual: Bool {
        !Calendar.current.isDate(pendingTime, equalTo: autoSeededObsTime, toGranularity: .minute)
    }

    /// Track the wall clock unless the operator has taken the time over.
    ///
    /// Without this the obs timestamp was seeded exactly once, when the view was
    /// first constructed, and never moved except by a log. An app opened at 0900
    /// and returned to at 1400 stamped **0900** — and `pendingObs` derives the
    /// month and the IRPG time-of-day band from that timestamp, so the reading
    /// was filed under the wrong correction column and produced the wrong PIG.
    private func reseedObsTime(_ date: Date) {
        guard !obsTimeIsManual else { return }
        pendingTime = date
        autoSeededObsTime = date
    }

    /// Hand the obs time back to the clock — after a log, or after a new shift.
    private func resetObsTimeToNow() {
        let t = Date()
        pendingTime = t
        autoSeededObsTime = t
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
                    .readout(24)
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

    /// One line per retained local day, points projected onto a shared clock, most
    /// recent day flagged so the chart can draw it solid.
    private func dayLines(_ metric: ObservationMetric) -> [DayLine] {
        let series = model.daySeries(of: metric)
        let latest = series.last?.day
        return series.map { entry in
            DayLine(id: entry.day,
                    label: Self.trendDayFormatter.string(from: entry.day),
                    isLatest: entry.day == latest,
                    points: entry.points.map {
                        TrendPoint(id: $0.date, clock: Self.clockProjection($0.date), value: $0.value)
                    })
        }
    }

    private var trendSection: some View {
        let lines = dayLines(trendMetric)
        let allVals = lines.flatMap { $0.points.map(\.value) }
        // Percent metrics pin to 0–100; °F metrics (temp / dew point) auto-fit.
        let domain: ClosedRange<Int> = trendMetric.unit == "%"
            ? 0...100
            : ((allVals.min() ?? 0) - 5)...((allVals.max() ?? 100) + 5)
        let annotation = lines.count > 1 ? "\(trendMetric.shortLabel) · \(lines.count) days" : trendMetric.shortLabel
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Trend", annotation: annotation)
            ChipPicker(title: "Metric", options: ObservationMetric.allCases,
                       selection: $trendMetric, label: \.shortLabel)
            if allVals.count >= 2 {
                ShiftTrendChart(days: lines, domain: domain, unit: trendMetric.unit)
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

    /// Project a timestamp onto a fixed reference day, keeping only its wall-clock
    /// hour+minute, so every day's line shares one time-of-day x-axis.
    private static func clockProjection(_ date: Date) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: date)
        return cal.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                             hour: c.hour ?? 0, minute: c.minute ?? 0)) ?? date
    }

    private static let trendDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    // MARK: - Shift log + delete/undo (M3)

    private var shiftLogSection: some View {
        let ordered = model.shift.obs.sorted { $0.timestamp > $1.timestamp }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Shift log", annotation: "\(model.shift.obs.count) obs")
            if showUndo, model.undoableRemovalCount > 0 {
                // The count is shown so a second delete can't hide the first: the
                // strip used to read "Observation removed" while silently holding
                // only the most recent one.
                StatusStrip(
                    icon: "arrow.uturn.backward",
                    message: model.undoableRemovalCount == 1
                        ? "Observation removed"
                        : "\(model.undoableRemovalCount) observations removed",
                    caution: true, actionTitle: "Undo",
                    action: {
                        model.undoRemoveObs()
                        if model.undoableRemovalCount == 0 { showUndo = false }
                        rescheduleCadence()
                    },
                    identifier: "undo-strip", actionIdentifier: "undo-remove")
            }
            ForEach(ordered) { obs in logRow(obs) }
        }
    }

    private func logRow(_ obs: WeatherObs) -> some View {
        let e = obs.estimate
        return HStack(spacing: 12) {
            Text(obs.timeLabel())
                .readout(17)
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
            Button { editingObs = obs } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BadwaterColor.accent)
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit-obs")
            .accessibilityLabel("Edit \(obs.timeLabel()) observation")
            Button(role: .destructive) {
                model.removeObs(id: obs.id)
                deleteHaptic += 1
                showUndo = true
                rescheduleCadence()
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
            futureTimeStrip
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

    /// A hand-set obs time in the future would file the reading under a
    /// time-of-day band that hasn't happened, and make it the "latest" obs the
    /// hero and the due countdown read from. Back-filling a *past* time is
    /// legitimate and stays silent.
    @ViewBuilder private var futureTimeStrip: some View {
        if pendingTime.timeIntervalSince(now) > 60 {
            StatusStrip(
                icon: "clock.badge.exclamationmark",
                message: "Obs time is ahead of the clock — this reading would be filed in the future.",
                caution: true, actionTitle: "Use now",
                action: { resetObsTimeToNow() },
                identifier: "obs-time-future", actionIdentifier: "obs-time-use-now")
        }
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
            SectionHeader(title: "Export", annotation: exportAnnotation)
            HStack(spacing: 10) {
                // Build the workbook once, on the tap. The document argument is
                // re-evaluated on every body pass, so constructing it inline
                // re-zipped the whole multi-day .xlsx on each 30-second tick for
                // as long as the sheet was open.
                Button {
                    workbookDocument = IMETWorkbookDocument(data: model.imetWorkbookData())
                    exportingWorkbook = true
                } label: { actionLabel("IMET .xlsx", "tablecells") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("export-imet")
                ShareLink(item: model.notesText()) { actionLabel("Notes table", "note.text") }
                    .accessibilityIdentifier("export-notes")
            }
        }
        .fileExporter(
            isPresented: $exportingWorkbook,
            document: workbookDocument,
            contentType: IMETWorkbookDocument.xlsx,
            defaultFilename: "BadwaterIgnition-observations"
        ) { _ in workbookDocument = nil }
    }

    /// The record couldn't be written to disk. The in-memory log is intact and
    /// still exportable, so the actionable instruction is "export now" rather
    /// than a bare error.
    private var persistenceWarning: some View {
        StatusStrip(
            icon: "externaldrive.badge.exclamationmark",
            message: "Couldn't save the log to this device — export the spreadsheet before you quit the app.",
            caution: true, identifier: "persistence-warning")
    }

    /// Export header annotation — surfaces the multi-day span once more than one
    /// day of observations is retained.
    private var exportAnnotation: String {
        let days = model.retainedObsDayCount()
        return days > 1 ? "\(days) days" : "Spreadsheet + notes"
    }

    // MARK: - History (retained days) + clearing

    /// The retained-days record: a reminder to export-then-clear once the log spans
    /// several days, the list of archived days (each individually removable), and a
    /// clear-all action. Present whenever any day is retained.
    private var historySection: some View {
        let obsDays = model.retainedObsDayCount()
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "History", annotation: "\(model.history.count) day\(model.history.count == 1 ? "" : "s")")
            if obsDays > 3 {
                StatusStrip(
                    icon: "tray.full",
                    message: "\(obsDays) days of observations retained — export the spreadsheet, then clear the days you don't need.",
                    caution: true, identifier: "history-reminder")
            }
            ForEach(model.history) { archived in archivedRow(archived) }
            Button(role: .destructive) { confirmClearHistory = true } label: {
                actionLabel("Clear all history", "trash")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clear-history")
            .confirmationDialog(
                "Clear all \(model.history.count) retained day\(model.history.count == 1 ? "" : "s")? Export the spreadsheet first if you still need them.",
                isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Clear all history", role: .destructive) { model.clearHistory() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .confirmationDialog(
            "Delete this day's observations? Export the spreadsheet first if you still need them.",
            isPresented: Binding(get: { shiftToDelete != nil }, set: { if !$0 { shiftToDelete = nil } }),
            titleVisibility: .visible, presenting: shiftToDelete) { day in
            Button("Delete day", role: .destructive) { model.removeArchivedShift(id: day.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func archivedRow(_ shift: Shift) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLabel(shift))
                    .readout(16).foregroundStyle(BadwaterColor.ink)
                Text(archivedSubtitle(shift))
                    .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) { shiftToDelete = shift } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BadwaterColor.caution)
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("delete-day")
            .accessibilityLabel("Delete \(dayLabel(shift))")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.hairline))
    }

    /// A retained day's date, e.g. "Mon, Jul 6" — taken from its earliest obs so a
    /// night shift crossing midnight still labels by the day it began.
    private func dayLabel(_ shift: Shift) -> String {
        let date = shift.obs.map(\.timestamp).min() ?? shift.started
        return Self.dayFormatter.string(from: date)
    }

    private func archivedSubtitle(_ shift: Shift) -> String {
        var parts = ["\(shift.obs.count) obs"]
        if let d = shift.division, !d.isEmpty { parts.append(d) }
        else if let l = shift.locationName, !l.isEmpty { parts.append(l) }
        return parts.joined(separator: " · ")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f
    }()

    // MARK: - New shift (M3)

    private var newShiftRow: some View {
        Button { confirmNewShift = true } label: { actionLabel("Start new shift", "plus.circle") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("new-shift")
            .confirmationDialog("Start a new shift? This shift is saved to History; the new shift starts empty.",
                                isPresented: $confirmNewShift, titleVisibility: .visible) {
                Button("Start new shift") {
                    model.startNewShift()
                    resetObsTimeToNow()
                    note = ""
                    showUndo = false
                    // The shift is over; its pending reminder is meaningless.
                    #if canImport(UserNotifications)
                    cadence.cancel()
                    #endif
                    // And so is the reading on the home screen — the new shift
                    // is empty, so the widget must fall back to "No obs logged"
                    // rather than keep showing the old shift's last obs.
                    reloadGlanceSurfaces()
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
            logHaptic += 1
            note = ""
            // Permission is asked here, at the point of value — the first log —
            // rather than on a cold launch before the operator knows what the
            // app does.
            #if canImport(UserNotifications)
            Task {
                await cadence.requestAuthorizationIfNeeded()
                cadence.reschedule(latestObs: model.latest?.timestamp)
            }
            #endif
            // Outside the #if: the widget follows the record, not the
            // notification permission, and this is the mutation it exists for.
            reloadGlanceSurfaces()
            // Hand the time back to the clock. This used to pre-fill the *next*
            // hourly slot (`pendingTime + 1 h`), which forward-dates the reading:
            // a second tap — a glove double-tap, a correction, a back-fill —
            // stamped an observation in the future, and `obsDueStrip` then
            // counted down from a `latest.timestamp` that hadn't happened yet.
            // Announcing when the next obs is due is the due strip's job, not
            // the timestamp's.
            resetObsTimeToNow()
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

/// The observation-time control: tap the value to **type** a time directly
/// ("1435" or "14:35"), or nudge it ±5 minutes. Two-way bound to the pending-obs
/// timestamp, so typing, nudging, and the reset-to-now after a log all agree.
@MainActor
private struct ObsTimeField: View {
    @Binding var time: Date
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Obs time").fieldLabel()
            HStack(spacing: 8) {
                TextField("HH:MM", text: $text)
                    .readout(32, weight: .bold)
                    // .numbersAndPunctuation, not .numberPad: the field accepts
                    // "14:35" as well as "1435", and the number pad has no colon.
                    .fieldKeyboard(.signedNumber)
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

/// The edit sheet for a logged observation — correct a mis-entered reading, time,
/// wind, or note without deleting and re-logging (the crew's "one wrong digit"
/// fix path). Its inputs are isolated `@State` seeded from the obs, so editing
/// never touches the live Ignition tab or the pending obs. `rhSource` is fixed to
/// how the reading was taken: a slung obs edits its wet bulb (RH / dew point
/// re-derive against the obs's own band); a direct obs edits RH.
@MainActor
private struct ObsEditSheet: View {
    let original: WeatherObs
    /// Commits the corrected fields; the parent calls `model.updateObs`, which
    /// recomputes the estimate, re-renders this obs's broadcast, and persists.
    let onSave: (_ timestamp: Date, _ dryBulbF: Int, _ relativeHumidity: Int,
                 _ wetBulbF: Int, _ wind: Wind?, _ note: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var time: Date
    @State private var dryBulb: Int
    @State private var rh: Int
    @State private var wetBulb: Int
    @State private var windLow: Int
    @State private var windHigh: Int
    @State private var gust: Int
    @State private var direction: Wind.Direction
    @State private var note: String

    init(original: WeatherObs,
         onSave: @escaping (Date, Int, Int, Int, Wind?, String) -> Void) {
        self.original = original
        self.onSave = onSave
        let input = original.estimate.input
        _time = State(initialValue: original.timestamp)
        _dryBulb = State(initialValue: input.dryBulbF)
        _rh = State(initialValue: input.relativeHumidity)
        // Reconstruct the wet bulb from the frozen depression (slung obs only; a
        // direct obs has no depression, so this seeds to the dry bulb).
        _wetBulb = State(initialValue: input.dryBulbF - (original.humidity?.wetBulbDepressionF ?? 0))
        let w = original.wind
        _windLow = State(initialValue: w?.speed?.low ?? 0)
        _windHigh = State(initialValue: w?.speed?.high ?? 0)
        _gust = State(initialValue: w?.gust ?? 0)
        _direction = State(initialValue: w?.direction ?? .north)
        _note = State(initialValue: original.note ?? "")
    }

    private var isSlung: Bool { original.rhSource == .wetBulb }

    /// A corrected timestamp in the future would re-file the reading under an
    /// IRPG time-of-day band that hasn't happened, and make it the "latest" obs
    /// the hero and the due countdown read from — the same hazard the capture
    /// card guards, which this sheet previously did not. Correcting a reading
    /// *backwards* is the normal case and stays silent.
    @ViewBuilder private var editFutureTimeStrip: some View {
        if time.timeIntervalSinceNow > 60 {
            StatusStrip(
                icon: "clock.badge.exclamationmark",
                message: "That time is ahead of the clock — this reading would be filed in the future.",
                caution: true, actionTitle: "Use now",
                action: { time = Date() },
                identifier: "edit-time-future", actionIdentifier: "edit-time-use-now")
        }
    }

    /// Rebuild the edited wind, mirroring `IgnitionModel.wind` (no high speed ⇒
    /// light/variable, still carrying any gust) — but preserve "not recorded"
    /// (`nil`) for an obs that never had wind and still has none entered, so a
    /// dry-bulb-only correction can't fabricate a light-and-variable broadcast.
    private var editedWind: Wind? {
        let g = gust > 0 ? gust : nil
        guard windHigh > 0 else {
            return (original.wind == nil && g == nil) ? nil : .lightVariable(gust: g)
        }
        return .measured(Wind.SpeedRange(low: min(windLow, windHigh), high: windHigh),
                         direction, gust: g)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metric.cardSpacing) {
                    Text("Correcting the \(formatHourMinute(original.timestamp)) reading — recomputes PIG. Neighboring broadcasts are unchanged.")
                        .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    ObsTimeField(time: $time)
                    editFutureTimeStrip

                    HStack(spacing: 10) {
                        StepperCard(label: "Dry bulb", unit: "°F", value: $dryBulb, range: 10...130)
                        if isSlung {
                            StepperCard(label: "Wet bulb", unit: "°F", value: $wetBulb, range: 10...130)
                        } else {
                            StepperCard(label: "Rel. humidity", unit: "%", value: $rh, range: 0...100)
                        }
                    }

                    HStack(spacing: 10) {
                        StepperCard(label: "Wind low", unit: "mph", value: $windLow, range: 0...60)
                        StepperCard(label: "Wind high", unit: "mph", value: $windHigh, range: 0...60)
                    }
                    if windHigh > 0 {
                        StepperCard(label: "Gust", unit: "mph", value: $gust, range: 0...80)
                        ChipPicker(title: "Wind from", options: Wind.Direction.allCases,
                                   selection: $direction, label: \.abbreviation)
                    }

                    Text("Note").fieldLabel()
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .font(BadwaterFont.body)
                        .lineLimit(1...3)
                        .padding(11)
                        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BadwaterColor.hairline))
                        .accessibilityIdentifier("edit-obs-note")
                }
                .padding(Metric.screenPadding)
            }
            .background(BadwaterColor.background)
            .navigationTitle("Edit observation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("edit-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(time, dryBulb, rh, wetBulb, editedWind, note)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .accessibilityIdentifier("edit-save")
                }
            }
        }
    }
}

/// Copy text to the system pasteboard — the inset "Copy" pill on the broadcast
/// panel. Platform-guarded so the view compiles for iOS and macOS.
@MainActor
private func copyToPasteboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    _ = NSPasteboard.general.setString(text, forType: .string)
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
