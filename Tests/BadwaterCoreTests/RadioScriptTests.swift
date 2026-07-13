import XCTest
@testable import BadwaterCore

/// Golden tests for the radio broadcast script. The primary golden is the
/// user's dictated field script, reproduced byte-exact from real engine inputs
/// (July, 0800–0959, West aspect, 0–30% slope, area below the weather site,
/// dry 60 °F / RH 25% → REF 5, corr +2/+4, FFM 7/9, PIG 50/30 — verified
/// against the IRPG tables by two independent traces).
final class RadioScriptTests: XCTestCase {

    /// Obs builder with full input control. The dictated golden REQUIRES
    /// elevationDelta .below (with .level the correction is +3 → PIG 40, not
    /// 50), so this test file keeps its own helper rather than reusing the
    /// hardcoded ones in WeatherWatchTests/ExportTests.
    private func obs(
        month: Int = 7,
        timeOfDay: TimeOfDay = .band0800_0959,
        aspect: Aspect = .west,
        slope: Slope = .gentle,
        elevationDelta: ElevationDelta = .below,
        dry: Int, rh: Int,
        wind: Wind? = nil, elevationFeet: Int? = nil
    ) -> WeatherObs {
        let input = IgnitionInput(
            dryBulbF: dry, relativeHumidity: rh, month: month, timeOfDay: timeOfDay,
            aspect: aspect, slope: slope, elevationDelta: elevationDelta)
        return WeatherObs(
            timestamp: Date(timeIntervalSince1970: 0),
            estimate: IgnitionCalculator.estimate(input),
            humidity: nil, rhSource: .direct,
            wind: wind, elevationFeet: elevationFeet)
    }

    // MARK: - (a) The dictated golden

    func testMatchesDictatedSampleScript() {
        // Elevation changed 10700 → 10300, so the location sentence fires
        // naturally (no forceLocation needed); deltas are up 5 / down 3.
        let previous = obs(dry: 55, rh: 28, elevationFeet: 10700)
        let current = obs(dry: 60, rh: 25,
                          wind: .measured(.init(low: 1, high: 3), .west),
                          elevationFeet: 10300)
        // Cross-assert the engine values the dictation encodes, so IRPG table
        // drift fails loudly here instead of as an opaque string diff.
        XCTAssertEqual(current.estimate.referenceFuelMoisture, 5)
        XCTAssertEqual(current.estimate.unshaded.probabilityOfIgnition, 50)
        XCTAssertEqual(current.estimate.shaded.probabilityOfIgnition, 30)

        let script = RadioScript.render(
            addressee: "Diamond Mountain", timeLabel: "0900",
            spokenLocation: "near the 659 road", current: current, previous: previous)
        XCTAssertEqual(script,
            "Diamond Mountain, stand by for your 0900 Weather observations. "
            + "Taken near the 659 road at an elevation of 10,300 feet, on a Western aspect. "
            + "Dry Bulb 60 degrees, up 5, RH 25%, down 3. "
            + "Winds are 1-3 miles per hour from the West, Probability of Ignition Unshaded is 50%, Shaded is 30%. "
            + "I repeat, Dry Bulb 60 degrees, up 5, RH 25%, down 3. How copy?")
    }

    // MARK: - (b) First obs

    func testFirstObsSpeaksLocationWithoutDeltas() {
        let current = obs(dry: 60, rh: 25, elevationFeet: 10300)
        let script = RadioScript.render(
            addressee: "Diamond Mountain", timeLabel: "0800",
            spokenLocation: "near the 659 road", current: current, previous: nil)
        XCTAssertTrue(script.contains("Taken near the 659 road"))
        XCTAssertTrue(script.contains("Dry Bulb 60 degrees, RH 25%."))
        XCTAssertFalse(script.contains(", up"))
        XCTAssertFalse(script.contains(", down"))
        XCTAssertFalse(script.contains("steady"))
    }

    // MARK: - (c) Suppression

    func testLocationSuppressedWhenSiteUnchanged() {
        let previous = obs(dry: 55, rh: 28, elevationFeet: 10300)
        let current = obs(dry: 60, rh: 25, elevationFeet: 10300)
        let script = RadioScript.render(
            addressee: "Diamond Mountain", timeLabel: "1000",
            spokenLocation: "near the 659 road", current: current, previous: previous)
        XCTAssertFalse(script.contains("Taken"))
        XCTAssertTrue(script.contains("Weather observations. Dry Bulb 60 degrees"))
    }

    // MARK: - (d) Re-trigger cases

    func testLocationRespokenOnSiteChange() {
        let base = obs(dry: 55, rh: 28, elevationFeet: 10300)

        // Elevation changed.
        let elev = obs(dry: 60, rh: 25, elevationFeet: 10100)
        XCTAssertTrue(RadioScript.render(addressee: "", timeLabel: "1000", spokenLocation: nil,
                                         current: elev, previous: base).contains("Taken"))

        // Aspect changed.
        let aspect = obs(aspect: .north, dry: 60, rh: 25, elevationFeet: 10300)
        let aspectScript = RadioScript.render(addressee: "", timeLabel: "1000", spokenLocation: nil,
                                              current: aspect, previous: base)
        XCTAssertTrue(aspectScript.contains("on a Northern aspect."))

        // Elevation → nil counts as changed; sentence degrades to loc + aspect.
        let lost = obs(dry: 60, rh: 25, elevationFeet: nil)
        let lostScript = RadioScript.render(addressee: "", timeLabel: "1000", spokenLocation: "near the 659 road",
                                            current: lost, previous: base)
        XCTAssertTrue(lostScript.contains("Taken near the 659 road, on a Western aspect."))
        XCTAssertFalse(lostScript.contains("elevation"))

        // forceLocation re-announces an unchanged site.
        let same = obs(dry: 60, rh: 25, elevationFeet: 10300)
        XCTAssertTrue(RadioScript.render(addressee: "", timeLabel: "1000", spokenLocation: nil,
                                         current: same, previous: base, forceLocation: true).contains("Taken"))
    }

    // MARK: - (e) Deltas

    func testSteadyAndMixedDeltas() {
        let previous = obs(dry: 60, rh: 25, elevationFeet: 10300)
        let steady = obs(dry: 60, rh: 25, elevationFeet: 10300)
        XCTAssertTrue(RadioScript.render(addressee: "", timeLabel: "1100", spokenLocation: nil,
                                         current: steady, previous: previous)
            .contains("Dry Bulb 60 degrees, steady, RH 25%, steady."))

        let mixed = obs(dry: 62, rh: 25, elevationFeet: 10300)
        XCTAssertTrue(RadioScript.render(addressee: "", timeLabel: "1100", spokenLocation: nil,
                                         current: mixed, previous: previous)
            .contains("Dry Bulb 62 degrees, up 2, RH 25%, steady."))
    }

    // MARK: - (f) Wind variants

    func testWindSpokenPhrases() {
        XCTAssertEqual(Wind.measured(.init(low: 1, high: 3), .west).spokenPhrase, "1-3 miles per hour from the West")
        XCTAssertEqual(Wind.measured(.init(8), .southwest).spokenPhrase, "8 miles per hour from the Southwest")
        XCTAssertEqual(Wind.measured(.init(1), .north).spokenPhrase, "1 mile per hour from the North")
        XCTAssertEqual(Wind(speed: .init(low: 4, high: 6), direction: nil).spokenPhrase, "4-6 miles per hour")
        XCTAssertEqual(Wind.lightVariable().spokenPhrase, "light and variable")
        XCTAssertEqual(Wind.measured(.init(low: 3, high: 5), .west, gust: 12).spokenPhrase,
                       "3-5 miles per hour from the West, gusts up to 12")
        XCTAssertEqual(Wind.lightVariable(gust: 12).spokenPhrase,
                       "light and variable, gusts up to 12")
    }

    func testNilWindOmitsWindsSentence() {
        let current = obs(dry: 60, rh: 25)
        let script = RadioScript.render(addressee: "", timeLabel: "0900", spokenLocation: nil,
                                        current: current, previous: nil)
        XCTAssertFalse(script.contains("Winds are"))
        XCTAssertTrue(script.contains(". Probability of Ignition Unshaded is 50%, Shaded is 30%."))
    }

    // MARK: - (g) Addressee

    func testEmptyAndWhitespaceAddressee() {
        let current = obs(dry: 60, rh: 25)
        for name in ["", "   "] {
            let script = RadioScript.render(addressee: name, timeLabel: "0900", spokenLocation: nil,
                                            current: current, previous: nil)
            XCTAssertTrue(script.hasPrefix("Stand by for your 0900 Weather observations."))
        }
    }

    // MARK: - (h) Location nil matrix

    func testLocationSentenceNilMatrix() {
        let both = obs(dry: 60, rh: 25, elevationFeet: 10300)
        XCTAssertEqual(RadioScript.locationSentence(spokenLocation: "near the 659 road", obs: both),
                       "Taken near the 659 road at an elevation of 10,300 feet, on a Western aspect.")
        XCTAssertEqual(RadioScript.locationSentence(spokenLocation: "near the 659 road", obs: obs(dry: 60, rh: 25)),
                       "Taken near the 659 road, on a Western aspect.")
        // Verbatim: a different preposition is inserted exactly as typed (no "near").
        XCTAssertEqual(RadioScript.locationSentence(spokenLocation: "at the 659 junction", obs: both),
                       "Taken at the 659 junction at an elevation of 10,300 feet, on a Western aspect.")
        XCTAssertEqual(RadioScript.locationSentence(spokenLocation: nil, obs: both),
                       "Taken at an elevation of 10,300 feet, on a Western aspect.")
        XCTAssertEqual(RadioScript.locationSentence(spokenLocation: nil, obs: obs(dry: 60, rh: 25)),
                       "Taken on a Western aspect.")
        XCTAssertEqual(RadioScript.locationSentence(spokenLocation: nil, obs: obs(aspect: .east, dry: 60, rh: 25)),
                       "Taken on an Eastern aspect.")
    }

    // MARK: - (i) Thousands grouping

    func testThousandsGrouping() {
        XCTAssertEqual(RadioScript.grouped(0), "0")
        XCTAssertEqual(RadioScript.grouped(659), "659")
        XCTAssertEqual(RadioScript.grouped(10300), "10,300")
        XCTAssertEqual(RadioScript.grouped(1234567), "1,234,567")
        XCTAssertEqual(RadioScript.grouped(-282), "-282")
        XCTAssertEqual(RadioScript.grouped(-10300), "-10,300")
    }
}
