import XCTest
@testable import BadwaterCore

/// Golden tests for the Weather Watch domain: metric extraction wired to the real
/// IRPG engine, the trend series, the radio line, and Codable round-tripping of a
/// logged shift.
final class WeatherWatchTests: XCTestCase {

    /// Build one observation via the real engine. `hour` drives the IRPG time
    /// band; a slung obs carries a HumidityResult so dew point is available.
    private func obs(
        at hour: Int, dryF: Int, rh: Int, slung: Bool, dewF: Int = 30
    ) -> WeatherObs {
        let input = IgnitionInput(
            dryBulbF: dryF, relativeHumidity: rh, month: 8,
            timeOfDay: TimeOfDay.from(hour: hour), aspect: .south,
            slope: .gentle, elevationDelta: .level)
        let estimate = IgnitionCalculator.estimate(input)
        let humidity = slung
            ? HumidityResult(relativeHumidity: rh, dewPointF: dewF, wetBulbDepressionF: 26, elevationBand: .band3)
            : nil
        return WeatherObs(
            timestamp: Date(timeIntervalSince1970: TimeInterval(hour) * 3600),
            estimate: estimate, humidity: humidity, rhSource: slung ? .wetBulb : .direct)
    }

    /// The verified table-accurate August shift (S / 0–30% / level, slung):
    /// temp climbs, RH falls, PIG ramps into Extreme.
    private func shiftObs() -> [WeatherObs] {
        return [
            obs(at: 9,  dryF: 64, rh: 23, slung: true),
            obs(at: 10, dryF: 69, rh: 20, slung: true),
            obs(at: 11, dryF: 74, rh: 17, slung: true),
            obs(at: 12, dryF: 80, rh: 14, slung: true, dewF: 28),
            obs(at: 13, dryF: 85, rh: 11, slung: true),
            obs(at: 14, dryF: 90, rh: 8,  slung: true),
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
        // 1230 and 1030 spot checks
        XCTAssertEqual(o[3].value(of: .probabilityOfIgnitionUnshaded), 90)
        XCTAssertEqual(o[1].value(of: .relativeHumidity), 20)
        XCTAssertEqual(o[1].value(of: .probabilityOfIgnitionUnshaded), 50)
    }

    func testDewPointIsNilWhenNotSlung() {
        let kestrel = obs(at: 12, dryF: 80, rh: 14, slung: false)
        XCTAssertNil(kestrel.value(of: .dewPoint))   // n/a, not a false zero
        let slung = obs(at: 12, dryF: 80, rh: 14, slung: true, dewF: 28)
        XCTAssertEqual(slung.value(of: .dewPoint), 28)
    }

    // MARK: - Radio line

    func testRadioLine() {
        let latest = shiftObs()[5]
        XCTAssertEqual(latest.radioLine(timeLabel: "1430"),
                       "Wx obs 1430, temp 90, RH 8, PIG 100 unshaded, 70 shaded")
    }

    // MARK: - Live reads follow timestamp, not append order

    func testLatestAndSeriesFollowTimestampNotAppendOrder() {
        // A back-filled 0900, appended to the shift AFTER the 1000 and 1100 obs.
        let o9  = obs(at: 9,  dryF: 64, rh: 23, slung: true)
        let o10 = obs(at: 10, dryF: 69, rh: 20, slung: true)
        let o11 = obs(at: 11, dryF: 74, rh: 17, slung: true)
        let shift = Shift(started: o9.timestamp, obs: [o11, o10, o9])   // reversed append order

        // "Latest" is the chronological max (1100), never merely the last appended.
        XCTAssertEqual(shift.latest?.timestamp, o11.timestamp)
        XCTAssertEqual(shift.latest?.value(of: .temperature), 74)

        // The trend series is sorted ascending by time regardless of append order.
        let temps = shift.series(of: .temperature)
        XCTAssertEqual(temps.map(\.date), [o9.timestamp, o10.timestamp, o11.timestamp])
        XCTAssertEqual(temps.map(\.value), [64, 69, 74])
    }

    // MARK: - Codable round-trip

    func testShiftCodableRoundTrip() throws {
        let shift = Shift(started: Date(timeIntervalSince1970: 0), obs: shiftObs())
        let data = try JSONEncoder().encode(shift)
        let decoded = try JSONDecoder().decode(Shift.self, from: data)
        XCTAssertEqual(decoded, shift)
    }
}
