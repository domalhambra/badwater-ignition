import XCTest
@testable import BadwaterCore

/// Golden tests for the Weather Watch domain: metric extraction wired to the real
/// IRPG engine, inclusive/latched trigger evaluation, the radio line, and Codable
/// round-tripping of a logged shift.
final class WeatherWatchTests: XCTestCase {

    private let rhTrigger = BriefedTrigger(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
        metric: .relativeHumidity, direction: .fallsToAtOrBelow, value: 20)
    private let pigTrigger = BriefedTrigger(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
        metric: .probabilityOfIgnitionUnshaded, direction: .risesToAtOrAbove, value: 80)

    /// Build one observation via the real engine. `hour` drives the IRPG time
    /// band; a slung obs carries a HumidityResult so dew point is available.
    private func obs(
        at hour: Int, dryF: Int, rh: Int, slung: Bool, dewF: Int = 30,
        triggers: [BriefedTrigger] = []
    ) -> WeatherObs {
        let input = IgnitionInput(
            dryBulbF: dryF, relativeHumidity: rh, month: 8,
            timeOfDay: TimeOfDay.from(hour: hour), aspect: .south,
            slope: .gentle, elevationDelta: .level)
        let estimate = IgnitionCalculator.estimate(input)
        let humidity = slung
            ? HumidityResult(relativeHumidity: rh, dewPointF: dewF, wetBulbDepressionF: 26, elevationBand: .band3)
            : nil
        var o = WeatherObs(
            timestamp: Date(timeIntervalSince1970: TimeInterval(hour) * 3600),
            estimate: estimate, humidity: humidity, rhSource: slung ? .wetBulb : .direct)
        o = WeatherObs(
            id: o.id, timestamp: o.timestamp, estimate: o.estimate, humidity: o.humidity,
            rhSource: o.rhSource,
            crossedTriggerIDs: TriggerEvaluator.metTriggerIDs(triggers, by: o))
        return o
    }

    /// The verified table-accurate August shift (S / 0–30% / level, slung):
    /// temp climbs, RH falls, PIG ramps into Extreme.
    private func shiftObs() -> [WeatherObs] {
        let triggers = [rhTrigger, pigTrigger]
        return [
            obs(at: 9,  dryF: 64, rh: 23, slung: true, triggers: triggers),
            obs(at: 10, dryF: 69, rh: 20, slung: true, triggers: triggers),
            obs(at: 11, dryF: 74, rh: 17, slung: true, triggers: triggers),
            obs(at: 12, dryF: 80, rh: 14, slung: true, dewF: 28, triggers: triggers),
            obs(at: 13, dryF: 85, rh: 11, slung: true, triggers: triggers),
            obs(at: 14, dryF: 90, rh: 8,  slung: true, triggers: triggers),
        ]
    }

    // MARK: - Metric extraction wired to the engine

    func testMetricExtractionMatchesEngine() {
        let o = shiftObs()
        // 1430 latest
        XCTAssertEqual(o[5].value(of: .temperature), 90)
        XCTAssertEqual(o[5].value(of: .relativeHumidity), 8)
        XCTAssertEqual(o[5].value(of: .probabilityOfIgnitionUnshaded), 100)
        XCTAssertEqual(o[5].value(of: .probabilityOfIgnitionShaded), 70)
        XCTAssertEqual(o[5].value(of: .fineFuelMoistureUnshaded), 2)
        // 1230 (first PIG≥80) and 1030 (first RH≤20)
        XCTAssertEqual(o[3].value(of: .probabilityOfIgnitionUnshaded), 90)
        XCTAssertEqual(o[1].value(of: .relativeHumidity), 20)
        XCTAssertEqual(o[1].value(of: .probabilityOfIgnitionUnshaded), 50)
    }

    func testDewPointIsNilWhenNotSlung() {
        let kestrel = obs(at: 12, dryF: 80, rh: 14, slung: false)
        XCTAssertNil(kestrel.value(of: .dewPoint))
        let dewTrigger = BriefedTrigger(metric: .dewPoint, direction: .fallsToAtOrBelow, value: 30)
        XCTAssertNil(TriggerEvaluator.isMet(dewTrigger, by: kestrel))   // n/a, not a false "clear"
    }

    // MARK: - Inclusive evaluation

    func testEvaluationIsInclusiveAtThreshold() {
        XCTAssertTrue(TriggerDirection.fallsToAtOrBelow.isSatisfied(value: 20, threshold: 20))
        XCTAssertFalse(TriggerDirection.fallsToAtOrBelow.isSatisfied(value: 21, threshold: 20))
        XCTAssertTrue(TriggerDirection.risesToAtOrAbove.isSatisfied(value: 80, threshold: 80))
        XCTAssertFalse(TriggerDirection.risesToAtOrAbove.isSatisfied(value: 79, threshold: 80))
    }

    func testUnarmedTriggerNeverMet() {
        let blank = BriefedTrigger(metric: .relativeHumidity, direction: .fallsToAtOrBelow, value: nil)
        let disabled = BriefedTrigger(metric: .relativeHumidity, direction: .fallsToAtOrBelow, value: 20, enabled: false)
        let o = obs(at: 14, dryF: 90, rh: 8, slung: true)
        XCTAssertNil(TriggerEvaluator.isMet(blank, by: o))
        XCTAssertNil(TriggerEvaluator.isMet(disabled, by: o))
    }

    // MARK: - Latched crossings across the shift

    func testCrossingsLatchWithFirstCrossTime() {
        let o = shiftObs()
        let rh = TriggerEvaluator.crossing(of: rhTrigger, across: o)
        XCTAssertEqual(rh.firstCrossedAt, o[1].timestamp)   // first RH ≤ 20 at 1030
        XCTAssertEqual(rh.pastCount, 5)                     // 1030…1430
        XCTAssertEqual(rh.nowValue, 8)
        XCTAssertTrue(rh.isCrossed)

        let pig = TriggerEvaluator.crossing(of: pigTrigger, across: o)
        XCTAssertEqual(pig.firstCrossedAt, o[3].timestamp)  // first PIG ≥ 80 at 1230
        XCTAssertEqual(pig.pastCount, 3)                    // 1230, 1330, 1430
        XCTAssertEqual(pig.nowValue, 100)
    }

    func testFrozenCrossingsPerObs() {
        let o = shiftObs()
        XCTAssertEqual(o[0].crossedTriggerIDs, [])                          // 0930 crosses nothing
        XCTAssertEqual(o[1].crossedTriggerIDs, [rhTrigger.id])              // 1030 RH only
        XCTAssertEqual(Set(o[3].crossedTriggerIDs), [rhTrigger.id, pigTrigger.id]) // 1230 both
    }

    func testCrossingsOrderPutsCrossedFirst() {
        let clear = BriefedTrigger(metric: .temperature, direction: .risesToAtOrAbove, value: 200)
        let list = TriggerEvaluator.crossings(of: [clear, rhTrigger], across: shiftObs())
        XCTAssertEqual(list.first?.trigger.id, rhTrigger.id)   // crossed sorts above clear
        XCTAssertFalse(list.last!.isCrossed)
    }

    // MARK: - Radio line & printed rules

    func testRadioLine() {
        let latest = shiftObs()[5]
        XCTAssertEqual(latest.radioLine(timeLabel: "1430"),
                       "Wx obs 1430, temp 90, RH 8, PIG 100 unshaded, 70 shaded")
    }

    func testRuleTextInclusiveAndBlankUntilBriefed() {
        XCTAssertEqual(rhTrigger.ruleText, "RH ≤ 20%")
        XCTAssertEqual(pigTrigger.ruleText, "PIG (unshaded) ≥ 80%")
        XCTAssertEqual(rhTrigger.spokenRule, "RH 20 or less")
        let blank = BriefedTrigger(metric: .temperature, direction: .risesToAtOrAbove, value: nil)
        XCTAssertEqual(blank.ruleText, "Temp ≥ — —°F")
    }

    // MARK: - Codable round-trip

    func testShiftCodableRoundTrip() throws {
        let shift = Shift(started: Date(timeIntervalSince1970: 0), obs: shiftObs())
        let data = try JSONEncoder().encode(shift)
        let decoded = try JSONDecoder().decode(Shift.self, from: data)
        XCTAssertEqual(decoded, shift)

        let triggers = [rhTrigger, pigTrigger]
        let tData = try JSONEncoder().encode(triggers)
        XCTAssertEqual(try JSONDecoder().decode([BriefedTrigger].self, from: tData), triggers)
    }
}
