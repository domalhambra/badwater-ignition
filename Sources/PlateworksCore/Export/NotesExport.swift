import Foundation

/// Renders a shift's observations as a **tab-separated** plain-text table for the
/// iOS Notes app (share sheet → "Copy to Notes", then AirDrop).
///
/// Why tabs instead of the space-padded block used by ``SpotObservationsRenderer``:
/// Notes composes in a *proportional* font, so a monospace, space-counted grid
/// collapses the instant it lands there. A single tab between cells is honoured by
/// Notes as a real tab stop, so columns line up regardless of how wide each digit
/// glyph is. The one variable-width field — Wind — is placed **last**, exactly as
/// the spot renderer keeps it last, so a long `"5-10 Southwest, Gust 18"` can never
/// shove a numeric column out of its stop. Plain text pasted or AirDropped into
/// Notes does not auto-convert to a native Notes table, but this lands as a clean,
/// aligned, shareable grid — and degrades gracefully (a wide cell nudges to the
/// next stop; rows stay grouped and readable).
///
/// Deterministic and dependency-free: all formatting is manual (no NumberFormatter,
/// no Locale), ASCII throughout (the separator is a literal tab, U+0009), and the
/// structure / access levels mirror ``SpotObservationsRenderer``.
public enum NotesExport {

    /// The shareable table for a whole shift. Time and date come from the obs
    /// timestamps via `calendar`, so the output never depends on the device clock.
    public static func plainText(from shift: Shift, calendar: Calendar = .current) -> String {
        let sorted = shift.obs.sorted { $0.timestamp < $1.timestamp }

        var lines: [String] = []
        lines.append(titleLine(shift: shift, sorted: sorted, calendar: calendar))
        lines.append("Temp/Wet F, RH %, PIG unshaded/shaded %, wind mph (from). Times local 24h.")

        if sorted.isEmpty {
            lines.append("")
            lines.append("No observations logged this shift.")
            return finish(lines)
        }

        lines.append("")
        // The Note column exists only when some obs actually carries a note, so
        // a note-free shift keeps the exact historical layout.
        let withNotes = sorted.contains { sanitizedNote($0.note) != nil }
        lines.append(withNotes ? headerRow + "\tNote" : headerRow)

        var currentMD = monthDay(of: sorted[0].timestamp, calendar: calendar)
        for (i, obs) in sorted.enumerated() {
            let md = monthDay(of: obs.timestamp, calendar: calendar)
            if i > 0 && md != currentMD {
                lines.append("-- \(md) --")   // divider when the shift crosses local midnight
                currentMD = md
            }
            lines.append(dataRow(for: obs, calendar: calendar, withNotes: withNotes))
        }

        lines.append("")
        lines.append("PIG = IRPG Probability of Ignition, app-computed (not observed, not a forecast).")
        lines.append("Wet bulb shown only when slung from a wet bulb; RH otherwise from a meter.")
        lines.append("Logged with Plateworks Ignition - decision-support only, not affiliated with NWS/NWCG.")
        return finish(lines)
    }

    // MARK: - Columns

    /// Column order — Wind last so its variable width can't break the grid's tab stops.
    static let columns = ["Time", "Temp", "Wet", "RH", "PIG u/s", "Wind"]

    /// The tab-separated column-header row.
    static let headerRow = columns.joined(separator: "\t")

    /// One observation → one tab-separated row. Wet bulb is reconstructed as
    /// dry − wet-bulb-depression when the obs was slung, else `"--"` (same rule as
    /// ``IMETExport/row(from:calendar:)``). Wind uses ``Wind/imetCell`` (speed-first,
    /// full-word direction), matching the spreadsheet column.
    private static func dataRow(for obs: WeatherObs, calendar: Calendar, withNotes: Bool) -> String {
        let dry = obs.estimate.input.dryBulbF
        let wet = obs.humidity.map { "\(dry - $0.wetBulbDepressionF)" } ?? "--"
        let pig = "\(obs.estimate.unshaded.probabilityOfIgnition)/\(obs.estimate.shaded.probabilityOfIgnition)"
        let wind = obs.wind?.imetCell ?? "--"
        var cells = [
            hhmm(of: obs.timestamp, calendar: calendar),
            "\(dry)",
            wet,
            "\(obs.estimate.input.relativeHumidity)",
            pig,
            wind,
        ]
        if withNotes { cells.append(sanitizedNote(obs.note) ?? "--") }
        return cells.joined(separator: "\t")
    }

    /// A note flattened for the tab grid: tabs/newlines become spaces (either
    /// would tear the row apart), whitespace-only collapses to nil.
    ///
    /// `\r` counts as a newline here: a pasted CRLF note used to keep its CR —
    /// which renders as a line break in Notes and tears the row — because only
    /// `\t` and `\n` were flattened and `.whitespaces` doesn't trim `\r` either.
    static func sanitizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let flat = note
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? nil : flat
    }

    // MARK: - Header

    /// `"8/12/26 Weather observations - Division W, 659 Road"`. Date comes from the
    /// first obs (or the shift start when empty); site/division are the shift's own.
    private static func titleLine(shift: Shift, sorted: [WeatherObs], calendar: Calendar) -> String {
        let day = sorted.first?.timestamp ?? shift.started
        var s = dateLabel(of: day, calendar: calendar) + " Weather observations"
        var tail: [String] = []
        if let d = shift.division, !d.isEmpty { tail.append(d) }
        if let l = shift.locationName, !l.isEmpty { tail.append(l) }
        if !tail.isEmpty { s += " - " + tail.joined(separator: ", ") }
        return s
    }

    // MARK: - Manual formatters (no NumberFormatter / no Locale)

    /// `"HHmm"` local 24-hour, e.g. `"0900"`, `"1405"`.
    private static func hhmm(of date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return pad2(c.hour ?? 0) + pad2(c.minute ?? 0)
    }

    /// `"M/D"`, e.g. `"8/12"` — used to trigger the local-midnight divider.
    private static func monthDay(of date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// `"M/D/YY"`, e.g. `"8/12/26"`.
    private static func dateLabel(of date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .year], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)/\((c.year ?? 0) % 100)"
    }

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    // MARK: - Assembly

    private static func finish(_ lines: [String]) -> String {
        lines.map(rstrip).joined(separator: "\n") + "\n"
    }
    private static func rstrip(_ s: String) -> String {
        var t = s
        while t.hasSuffix(" ") { t.removeLast() }
        return t
    }
}
