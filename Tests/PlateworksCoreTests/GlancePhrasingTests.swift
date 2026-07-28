import XCTest
@testable import PlateworksCore

/// The words a widget and a watch complication put on screen. Tested here
/// because a SwiftUI view's text is never tested anywhere else, and because the
/// two surfaces must say the same thing about the same record.
final class GlancePhrasingTests: XCTestCase {

    // MARK: - Clock label

    /// A fixed UTC calendar so the assertions are about the formatting, not
    /// about wherever the test happens to run.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(hour: Int, minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 7, day: 21,
                                      hour: hour, minute: minute))!
    }

    func testClockLabelIsZeroPaddedTwentyFourHour() {
        XCTAssertEqual(GlancePhrasing.clockLabel(for: at(hour: 14, minute: 30), calendar: utc), "1430")
        XCTAssertEqual(GlancePhrasing.clockLabel(for: at(hour: 9, minute: 5), calendar: utc), "0905")
        XCTAssertEqual(GlancePhrasing.clockLabel(for: at(hour: 0, minute: 0), calendar: utc), "0000")
        XCTAssertEqual(GlancePhrasing.clockLabel(for: at(hour: 23, minute: 59), calendar: utc), "2359")
    }

    /// It is the same four digits that go out over the radio, so what a crew
    /// reads on a wrist is what they say on the net.
    func testClockLabelMatchesTheSpokenRadioLine() {
        let input = IgnitionInput(dryBulbF: 90, relativeHumidity: 8, month: 7,
                                  timeOfDay: .band1400_1559, aspect: .south,
                                  slope: .gentle, elevationDelta: .level)
        let obs = WeatherObs(timestamp: at(hour: 14, minute: 30),
                             estimate: IgnitionCalculator.estimate(input),
                             rhSource: .direct)
        let label = GlancePhrasing.clockLabel(for: obs.timestamp, calendar: utc)
        XCTAssertTrue(obs.radioLine(timeLabel: label).hasPrefix("Wx obs 1430,"),
                      "the glance label and the radio line disagreed")
    }

    /// No locale can turn it into "2:30 PM" — it is built from calendar
    /// components, not a `DateFormatter`.
    func testClockLabelIgnoresLocale() {
        var french = utc
        french.locale = Locale(identifier: "fr_FR")
        XCTAssertEqual(GlancePhrasing.clockLabel(for: at(hour: 14, minute: 30), calendar: french),
                       "1430")
    }

    // MARK: - Durations

    func testMinutesUnderAnHour() {
        XCTAssertEqual(GlancePhrasing.duration(seconds: 0), "0 min")
        XCTAssertEqual(GlancePhrasing.duration(seconds: 60), "1 min")
        XCTAssertEqual(GlancePhrasing.duration(seconds: 40 * 60), "40 min")
        XCTAssertEqual(GlancePhrasing.duration(seconds: 59 * 60), "59 min")
    }

    func testWholeHoursDropTheMinutes() {
        XCTAssertEqual(GlancePhrasing.duration(seconds: 3600), "1 hr")
        XCTAssertEqual(GlancePhrasing.duration(seconds: 2 * 3600), "2 hr")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(GlancePhrasing.duration(seconds: 3600 + 5 * 60), "1 hr 5 min")
        XCTAssertEqual(GlancePhrasing.duration(seconds: 2 * 3600 + 15 * 60), "2 hr 15 min")
    }

    /// Truncated, never rounded up. A reading 119 seconds old is "1 min": erring
    /// young would understate staleness, which is the wrong direction for a
    /// value that exists to say how stale something is.
    func testTruncatesRatherThanRounds() {
        XCTAssertEqual(GlancePhrasing.duration(seconds: 119), "1 min")
        XCTAssertEqual(GlancePhrasing.duration(seconds: 3599), "59 min")
    }

    /// `ObsGlance` already floors age at zero, but the phrasing must not produce
    /// "-1 min" if it is ever handed a negative directly.
    func testNegativeDurationsClampToZero() {
        XCTAssertEqual(GlancePhrasing.duration(seconds: -300), "0 min")
    }

    // MARK: - Age

    func testUnderAMinuteReadsAsJustNow() {
        XCTAssertEqual(GlancePhrasing.age(seconds: 0), "just now")
        XCTAssertEqual(GlancePhrasing.age(seconds: 59), "just now")
    }

    func testAgeIsSpelledOutInWords() {
        XCTAssertEqual(GlancePhrasing.age(seconds: 12 * 60), "12 min ago")
        XCTAssertEqual(GlancePhrasing.age(seconds: 3600 + 5 * 60), "1 hr 5 min ago")
    }

    // MARK: - Overdue

    func testAtTheDueMomentItAnnouncesRatherThanCountingZero() {
        XCTAssertEqual(GlancePhrasing.overdue(seconds: 0), "obs due now")
        XCTAssertEqual(GlancePhrasing.overdue(seconds: 59), "obs due now")
    }

    func testOverdueReportsTheInterval() {
        XCTAssertEqual(GlancePhrasing.overdue(seconds: 40 * 60), "obs overdue 40 min")
        XCTAssertEqual(GlancePhrasing.overdue(seconds: 3600 + 20 * 60), "obs overdue 1 hr 20 min")
    }

    // MARK: - The display policy

    /// The overdue annunciation replaces the number; it must never carry one.
    /// A surface past the cadence changes job — a crew glancing at a wrist wants
    /// "obs overdue 40 min", not a value they then have to date-check.
    ///
    /// Sweeps the whole plausible range so a future edit that interpolates a PIG
    /// (or any value that isn't the interval itself) into this string fails
    /// here rather than on someone's wrist.
    func testOverdueNeverQuotesAComputedValue() {
        for minutes in 0...(48 * 60) {
            let text = GlancePhrasing.overdue(seconds: TimeInterval(minutes * 60))
            XCTAssertFalse(text.contains("%"), "overdue text carried a percentage: \(text)")
            XCTAssertFalse(text.lowercased().contains("pig"),
                           "overdue text quoted a PIG: \(text)")
            XCTAssertFalse(text.lowercased().contains("ffm"),
                           "overdue text quoted a fuel moisture: \(text)")
            // The only digits allowed are the interval's own.
            let digits = text.filter(\.isNumber)
            let expected = (GlancePhrasing.duration(seconds: TimeInterval(minutes * 60)))
                .filter(\.isNumber)
            XCTAssertTrue(minutes < 1 ? digits.isEmpty : digits == expected,
                          "overdue text carried unexpected digits: \(text)")
        }
    }

    // MARK: - Observed conditions

    func testConditionsLeadsWithTheObservation() {
        XCTAssertEqual(
            GlancePhrasing.conditions(dryBulbF: 75, relativeHumidity: 20, wind: "Calm"),
            "75°F · RH 20% · Calm")
        XCTAssertEqual(
            GlancePhrasing.conditions(dryBulbF: 96, relativeHumidity: 8, wind: "SW 4-6"),
            "96°F · RH 8% · SW 4-6")
    }

    func testConditionsCompactDropsUnitsButNotOrder() {
        XCTAssertEqual(
            GlancePhrasing.conditionsCompact(dryBulbF: 75, relativeHumidity: 20, wind: "Calm"),
            "75° · 20% · Calm")
    }

    /// An unrecorded value must render as a visible gap. Dropping the segment
    /// would leave "Calm" looking like a recorded wind, and a missing RH looking
    /// like the number beside it.
    func testMissingValuesRenderAsDashesRatherThanVanishing() {
        XCTAssertEqual(
            GlancePhrasing.conditions(dryBulbF: 75, relativeHumidity: 20, wind: nil),
            "75°F · RH 20% · wind —")
        XCTAssertEqual(
            GlancePhrasing.conditions(dryBulbF: nil, relativeHumidity: nil, wind: "Calm"),
            "— · RH — · Calm")
        XCTAssertEqual(
            GlancePhrasing.conditionsCompact(dryBulbF: nil, relativeHumidity: nil, wind: nil),
            "— · — · —")
    }

    /// RH and PIG are both percentages on the same small screen. The conditions
    /// line must name its humidity so the two can never be read for each other.
    func testConditionsLabelsItsHumidity() {
        for rh in 0...100 {
            let text = GlancePhrasing.conditions(dryBulbF: 70, relativeHumidity: rh, wind: "Calm")
            XCTAssertTrue(text.contains("RH \(rh)%"),
                          "humidity was not labelled: \(text)")
        }
    }

    /// The regression this wording exists for: the previous PIG line rendered as
    /// `"PIG 40% · 40% s…"` on `accessoryRectangular`, losing the one word that
    /// distinguished the two numbers.
    func testPigSummaryStaysShortEnoughForTheLockScreen() {
        for unshaded in 0...100 {
            for shaded in stride(from: 0, through: 100, by: 10) {
                let text = GlancePhrasing.pigSummary(unshaded: unshaded, shaded: shaded)
                XCTAssertLessThanOrEqual(text.count, 18,
                                         "PIG summary too long to render: \(text)")
                XCTAssertTrue(text.hasPrefix("PIG "))
                XCTAssertTrue(text.hasSuffix("shd"),
                              "shaded value lost its label: \(text)")
            }
        }
        XCTAssertEqual(GlancePhrasing.pigSummary(unshaded: 40, shaded: 40), "PIG 40/40% shd")
    }
}
