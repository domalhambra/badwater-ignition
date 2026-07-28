import XCTest
@testable import PlateworksCore

/// Golden tests for the iOS-Notes tab-separated export. They lock the *layout*
/// (title, units line, tab-separated header, wind-last, "--" for missing cells,
/// midnight divider, footnotes), determinism, and the ASCII/no-trailing-space
/// claims. PIG values in the exact-row check are read back from the obs under
/// test rather than hard-coded, so the assertion pins the format precisely while
/// staying correct-by-construction against the same engine that produced them.
final class NotesExportTests: XCTestCase {

    private func denver() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }

    // MARK: - Header + structure

    func testHeaderAndUnitsLine() {
        let cal = denver()
        let ts = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14))!
        let o = obs(cal: cal, ts: ts, dry: 92, depression: 32, rh: 12,
                    wind: .measured(.init(low: 5, high: 10), .southwest, gust: 18),
                    elev: 10500, loc: nil, aspect: .south)
        let out = NotesExport.plainText(
            from: Shift(started: ts, obs: [o], division: "Division W", locationName: "659 Road"),
            calendar: cal)
        XCTAssertTrue(out.hasPrefix("8/12/26 Weather observations - Division W, 659 Road\n"))
        XCTAssertTrue(out.contains("Temp/Wet F, RH %, PIG unshaded/shaded %, wind mph (from). Times local 24h.\n"))
        // Tab-separated header row, wind last.
        XCTAssertEqual(NotesExport.headerRow, "Time\tTemp\tWet\tRH\tPIG u/s\tWind")
        XCTAssertTrue(out.contains("\nTime\tTemp\tWet\tRH\tPIG u/s\tWind\n"))
        XCTAssertTrue(out.contains("app-computed (not observed, not a forecast)"))
        XCTAssertTrue(out.hasSuffix("not affiliated with NWS/NWCG.\n"))
    }

    // MARK: - One data row, exact

    func testSingleRowExact() {
        let cal = denver()
        let ts = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14, minute: 0))!
        let o = obs(cal: cal, ts: ts, dry: 92, depression: 32, rh: 12,
                    wind: .measured(.init(low: 5, high: 10), .southwest, gust: 18),
                    elev: 10500, loc: GeoPoint(latitude: 38.216, longitude: -112.398), aspect: .south)
        let out = NotesExport.plainText(
            from: Shift(started: ts, obs: [o], division: "Division W", locationName: "659 Road"),
            calendar: cal)
        let u = o.estimate.unshaded.probabilityOfIgnition
        let s = o.estimate.shaded.probabilityOfIgnition
        // Time 1400, temp 92, wet = dry 92 − depression 32 = 60, RH 12, PIG u/s, wind (imetCell) last.
        XCTAssertTrue(out.contains("1400\t92\t60\t12\t\(u)/\(s)\t5-10 Southwest, Gust 18"),
                      "expected row not found in:\n\(out)")
    }

    // MARK: - Missing cells render "--"

    func testKestrelObsShowsDashes() {
        let cal = denver()
        let ts = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10))!
        let k = obs(cal: cal, ts: ts, dry: 70, depression: nil, rh: 25,
                    wind: nil, elev: nil, loc: nil, aspect: .south)
        let out = NotesExport.plainText(from: Shift(started: ts, obs: [k]), calendar: cal)
        let u = k.estimate.unshaded.probabilityOfIgnition
        let s = k.estimate.shaded.probabilityOfIgnition
        XCTAssertTrue(out.contains("1000\t70\t--\t25\t\(u)/\(s)\t--"),
                      "expected Kestrel row not found in:\n\(out)")
    }

    // MARK: - Note column (only when a note exists)

    func testNoteColumnAppearsOnlyWhenNoted() {
        let cal = denver()
        let ts = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10))!
        let ts2 = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 11))!
        var flagged = obs(cal: cal, ts: ts, dry: 70, depression: nil, rh: 25,
                          wind: nil, elev: nil, loc: nil, aspect: .south)
        flagged.note = " sun on\tthermometer\nsuspect "   // tab/newline must not tear the grid
        let plain = obs(cal: cal, ts: ts2, dry: 72, depression: nil, rh: 24,
                        wind: nil, elev: nil, loc: nil, aspect: .south)

        let out = NotesExport.plainText(from: Shift(started: ts, obs: [flagged, plain]), calendar: cal)
        XCTAssertTrue(out.contains("\nTime\tTemp\tWet\tRH\tPIG u/s\tWind\tNote\n"))
        XCTAssertTrue(out.contains("\tsun on thermometer suspect"))   // flattened, trimmed
        XCTAssertTrue(out.contains("1100\t72\t--\t24"))
        // The note-free obs pads its Note cell with "--" so the column stays aligned.
        let plainRow = out.split(separator: "\n").first { $0.hasPrefix("1100\t") }
        XCTAssertTrue(plainRow?.hasSuffix("\t--") == true, "row was: \(plainRow ?? "")")

        // No notes anywhere -> the historical 6-column layout, byte-identical.
        let bare = NotesExport.plainText(from: Shift(started: ts, obs: [plain]), calendar: cal)
        XCTAssertTrue(bare.contains("\nTime\tTemp\tWet\tRH\tPIG u/s\tWind\n"))
        XCTAssertFalse(bare.contains("\tNote"))
    }

    // MARK: - Midnight divider

    func testMidnightDivider() {
        let cal = denver()
        let d1 = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 23, minute: 30))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 0, minute: 30))!
        let out = NotesExport.plainText(from: Shift(started: d1, obs: [
            obs(cal: cal, ts: d1, dry: 60, depression: nil, rh: 30, wind: nil, elev: nil, loc: nil, aspect: .south),
            obs(cal: cal, ts: d2, dry: 58, depression: nil, rh: 35, wind: nil, elev: nil, loc: nil, aspect: .south),
        ]), calendar: cal)
        XCTAssertTrue(out.contains("\n-- 8/13 --\n"))
    }

    // MARK: - Empty shift

    func testEmptyShift() {
        let cal = denver()
        let ts = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9))!
        let out = NotesExport.plainText(from: Shift(started: ts, obs: [], division: "Division W"), calendar: cal)
        XCTAssertTrue(out.hasPrefix("8/12/26 Weather observations - Division W\n"))
        XCTAssertTrue(out.contains("No observations logged this shift."))
        XCTAssertFalse(out.contains("\t"))   // no grid when there are no rows
    }

    // MARK: - Determinism + ASCII + no trailing spaces

    func testDeterministicAsciiAndNoTrailingSpace() {
        let cal = denver()
        let ts = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14))!
        let shift = Shift(started: ts, obs: [
            obs(cal: cal, ts: ts, dry: 92, depression: 32, rh: 12,
                wind: .measured(.init(low: 5, high: 10), .southwest, gust: 18),
                elev: 10500, loc: GeoPoint(latitude: 38.216, longitude: -112.398), aspect: .south),
            obs(cal: cal, ts: cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 15))!,
                dry: 90, depression: nil, rh: 8, wind: .lightVariable(), elev: nil, loc: nil, aspect: .south),
        ], division: "Division W", locationName: "659 Road")

        let a = NotesExport.plainText(from: shift, calendar: cal)
        let b = NotesExport.plainText(from: shift, calendar: cal)
        XCTAssertEqual(a, b, "output must be deterministic")

        // Tab (U+0009) is ASCII; the whole document must be ASCII as claimed.
        XCTAssertTrue(a.unicodeScalars.allSatisfy { $0.isASCII })
        for line in a.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertFalse(line.hasSuffix(" "), "trailing space in: \(line)")
        }
    }

    // MARK: - helper (mirrors ExportTests.obs)

    private func obs(cal: Calendar, ts: Date, dry: Int, depression: Int?, rh: Int,
                     wind: Wind?, elev: Int?, loc: GeoPoint?, aspect: Aspect = .south) -> WeatherObs {
        let input = IgnitionInput(
            dryBulbF: dry, relativeHumidity: rh, month: cal.component(.month, from: ts),
            timeOfDay: TimeOfDay.from(hour: cal.component(.hour, from: ts)),
            aspect: aspect, slope: .gentle, elevationDelta: .level)
        let humidity = depression.map {
            HumidityResult(relativeHumidity: rh, dewPointF: 36, wetBulbDepressionF: $0, elevationBand: .band3)
        }
        return WeatherObs(
            timestamp: ts, estimate: IgnitionCalculator.estimate(input),
            humidity: humidity, rhSource: depression != nil ? .wetBulb : .direct,
            wind: wind, elevationFeet: elev, location: loc)
    }
}
