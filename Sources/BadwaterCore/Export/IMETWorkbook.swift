import Foundation

/// One row of the IMET sheet (columns A–J), already reduced to display values.
/// `nil` optionals render as a blank cell.
public struct IMETRow: Equatable, Sendable {
    public let timeSerial: Double      // A — never blank
    public let dryBulbF: Int           // B
    public let wetBulbF: Int?          // C — blank unless slung
    public let relativeHumidity: Int   // D
    public let wind: String?           // E — Wind.imetCell, blank if not recorded
    public let pigUnshaded: Int        // F
    public let pigShaded: Int          // G
    public let elevationFeet: Int?     // H
    public let aspect: String          // I
    public let location: String?       // J — GeoPoint.rendered
}

/// One worksheet = one operational day.
public struct IMETSheet: Equatable, Sendable {
    public let name: String    // tab, e.g. "Div W - 7626"
    public let title: String   // A1
    public let rows: [IMETRow]
}

/// Pure mapping from a logged ``Shift`` to per-day IMET sheets. Groups by the
/// **local** calendar day and uses local wall-clock time serials so an obs never
/// lands on the wrong sheet or hour.
public enum IMETExport {

    /// IMET column headers (F/G corrected from the template's duplicate "Shaded").
    public static let headers = [
        "Time", "Dry Bulb", "Wet Bulb", "RH (%)", "Wind (MPH)",
        "Probability of Ignition (Unshaded) (%)", "Probability of Ignition (Shaded) (%)",
        "Elevation", "Aspect", "Location",
    ]

    /// Provenance footnote written two rows below the data on every sheet, so a
    /// forwarded workbook can't be mistaken for observed or NWS-issued data. Wording
    /// matches the Notes and NWS-spot exports.
    public static let disclaimer =
        "Probability of Ignition = IRPG value, app-computed (not observed, not a forecast). "
        + "Logged with Badwater Ignition - decision-support only, not affiliated with NWS/NWCG."

    /// Excel time-of-day serial: fraction of a day from local midnight, in `[0, 1)`.
    /// 09:00 → 0.375, 13:00 → 0.5416666666666666.
    public static func timeSerial(of date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let secs = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        return Double(secs) / 86400.0
    }

    /// Map one observation to a row. Wet bulb is reconstructed as
    /// dry − wet-bulb-depression when the obs was slung, else blank.
    public static func row(from obs: WeatherObs, calendar: Calendar) -> IMETRow {
        let dry = obs.estimate.input.dryBulbF
        return IMETRow(
            timeSerial: timeSerial(of: obs.timestamp, calendar: calendar),
            dryBulbF: dry,
            wetBulbF: obs.humidity.map { dry - $0.wetBulbDepressionF },
            relativeHumidity: obs.estimate.input.relativeHumidity,
            wind: obs.wind?.imetCell,
            pigUnshaded: obs.estimate.unshaded.probabilityOfIgnition,
            pigShaded: obs.estimate.shaded.probabilityOfIgnition,
            elevationFeet: obs.elevationFeet,
            aspect: obs.estimate.input.aspect.displayName,
            location: obs.location?.rendered)
    }

    /// Group a shift's obs into one sheet per local day (ascending; rows
    /// time-ascending). An empty shift yields one header-only sheet for its start day.
    public static func sheets(from shift: Shift, calendar: Calendar) -> [IMETSheet] {
        let sorted = shift.obs.sorted { $0.timestamp < $1.timestamp }
        let days: [Date]
        var byDay: [Date: [WeatherObs]] = [:]
        if sorted.isEmpty {
            days = [calendar.startOfDay(for: shift.started)]
        } else {
            byDay = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.timestamp) }
            days = byDay.keys.sorted()
        }
        return days.map { day in
            let c = calendar.dateComponents([.month, .day, .year], from: day)
            let rows = (byDay[day] ?? []).map { row(from: $0, calendar: calendar) }
            return IMETSheet(
                name: sheetName(division: shift.division, c),
                title: titleLine(division: shift.division, location: shift.locationName, c),
                rows: rows)
        }
    }

    /// Tab name, e.g. `"Div W - 7626"` (Division W, 7/6/26).
    public static func sheetName(division: String?, _ c: DateComponents) -> String {
        let date = "\(c.month ?? 0)\(c.day ?? 0)\((c.year ?? 0) % 100)"
        let div = divisionAbbrev(division)
        return sanitizeSheetName(div.isEmpty ? "Obs - \(date)" : "\(div) - \(date)")
    }

    /// Title row, e.g. `"7/6/26 Weather Observations - Division W, 659 Road"`.
    public static func titleLine(division: String?, location: String?, _ c: DateComponents) -> String {
        var s = "\(c.month ?? 0)/\(c.day ?? 0)/\((c.year ?? 0) % 100) Weather Observations"
        var tail: [String] = []
        if let division, !division.isEmpty { tail.append(division) }
        if let location, !location.isEmpty { tail.append(location) }
        if !tail.isEmpty { s += " - " + tail.joined(separator: ", ") }
        return s
    }

    /// `"Division W"` → `"Div W"`; otherwise the label as given.
    static func divisionAbbrev(_ division: String?) -> String {
        guard let d = division?.trimmingCharacters(in: .whitespaces), !d.isEmpty else { return "" }
        if d.lowercased().hasPrefix("division ") { return "Div " + d.dropFirst("division ".count) }
        return d
    }

    /// Enforce Excel's tab rules: ≤ 31 chars, none of `: \ / ? * [ ]`, non-empty.
    static func sanitizeSheetName(_ raw: String) -> String {
        let illegal: Set<Character> = [":", "\\", "/", "?", "*", "[", "]"]
        var s = ""
        for ch in raw { s.append(illegal.contains(ch) ? " " : ch) }
        if s.count > 31 { s = String(s.prefix(31)) }
        return s.isEmpty ? "Sheet" : s
    }
}

/// Builds the OOXML `.xlsx` bytes for the IMET export. Minimal, valid, and
/// dependency-free: inline strings (no shared-strings table), the built-in time
/// number format (id 20), and a STORE-only zip. Verified to open in a real reader.
public enum IMETWorkbook {

    /// The complete `.xlsx` bytes for a shift — hand this to the OS share sheet.
    public static func build(from shift: Shift, calendar: Calendar = .current) -> Data {
        ZipArchive.zip(parts(for: IMETExport.sheets(from: shift, calendar: calendar)))
    }

    static func parts(for sheets: [IMETSheet]) -> [(path: String, data: Data)] {
        var out: [(path: String, data: Data)] = [
            ("[Content_Types].xml", data(contentTypes(sheetCount: sheets.count))),
            ("_rels/.rels", data(rootRels)),
            ("xl/workbook.xml", data(workbook(sheets))),
            ("xl/_rels/workbook.xml.rels", data(workbookRels(sheetCount: sheets.count))),
            ("xl/styles.xml", data(styles)),
        ]
        for (i, sheet) in sheets.enumerated() {
            out.append(("xl/worksheets/sheet\(i + 1).xml", data(worksheet(sheet))))
        }
        return out
    }

    // MARK: - XML parts

    private static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    static func xmlEscape(_ raw: String) -> String {
        var s = ""
        for u in raw.unicodeScalars {
            switch u {
            case "&": s += "&amp;"
            case "<": s += "&lt;"
            case ">": s += "&gt;"
            case "\"": s += "&quot;"
            case "'": s += "&apos;"
            default:
                if u.value < 0x20 && u != "\t" && u != "\n" { continue }  // drop control chars
                s.unicodeScalars.append(u)
            }
        }
        return s
    }

    private static func contentTypes(sheetCount: Int) -> String {
        var s = header
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
            + "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for i in 1...max(sheetCount, 1) {
            s += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return s + "</Types>"
    }

    private static let rootRels = header
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
        + "</Relationships>"

    private static func workbook(_ sheets: [IMETSheet]) -> String {
        var s = header
            + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
        for (i, sheet) in sheets.enumerated() {
            s += "<sheet name=\"\(xmlEscape(sheet.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        return s + "</sheets></workbook>"
    }

    private static func workbookRels(sheetCount: Int) -> String {
        var s = header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in 1...max(sheetCount, 1) {
            s += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        s += "<Relationship Id=\"rId\(max(sheetCount, 1) + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        return s + "</Relationships>"
    }

    // Style index 1 = built-in number format 20 ("h:mm") for the time column.
    private static let styles = header
        + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
        + "<fills count=\"1\"><fill><patternFill patternType=\"none\"/></fill></fills>"
        + "<borders count=\"1\"><border/></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"2\">"
        + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        + "<xf numFmtId=\"20\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        + "</cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"

    private static func worksheet(_ sheet: IMETSheet) -> String {
        func col(_ i: Int) -> String { String(UnicodeScalar(UInt8(65 + i))) }
        func num(_ ref: String, _ v: Int) -> String { "<c r=\"\(ref)\"><v>\(v)</v></c>" }
        func str(_ ref: String, _ v: String) -> String {
            "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(v))</t></is></c>"
        }

        var rows = ""
        // Title (row 1)
        rows += "<row r=\"1\">\(str("A1", sheet.title))</row>"
        // Headers (row 2)
        var head = "<row r=\"2\">"
        for (i, h) in IMETExport.headers.enumerated() { head += str("\(col(i))2", h) }
        rows += head + "</row>"
        // Data rows (3+)
        for (ri, r) in sheet.rows.enumerated() {
            let R = ri + 3
            var cells = "<c r=\"A\(R)\" s=\"1\"><v>\(r.timeSerial)</v></c>"   // A time serial
            cells += num("B\(R)", r.dryBulbF)
            if let wet = r.wetBulbF { cells += num("C\(R)", wet) }
            cells += num("D\(R)", r.relativeHumidity)
            if let wind = r.wind { cells += str("E\(R)", wind) }
            cells += num("F\(R)", r.pigUnshaded)
            cells += num("G\(R)", r.pigShaded)
            if let elev = r.elevationFeet { cells += num("H\(R)", elev) }
            cells += str("I\(R)", r.aspect)
            if let loc = r.location { cells += str("J\(R)", loc) }
            rows += "<row r=\"\(R)\">\(cells)</row>"
        }
        // Provenance footer, one blank row below the data (row count + 4:
        // 1 title + 1 header + N data + 1 gap).
        let footRow = sheet.rows.count + 4
        rows += "<row r=\"\(footRow)\">\(str("A\(footRow)", IMETExport.disclaimer))</row>"

        let dim = "A1:J\(footRow)"
        return header
            + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
            + "<dimension ref=\"\(dim)\"/><sheetData>\(rows)</sheetData></worksheet>"
    }

    private static func data(_ s: String) -> Data { Data(s.utf8) }
}
