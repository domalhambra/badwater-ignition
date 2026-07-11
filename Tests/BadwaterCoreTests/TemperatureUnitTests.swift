import XCTest
@testable import BadwaterCore

final class TemperatureUnitTests: XCTestCase {

    func testFahrenheitIsIdentity() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.toFahrenheit(95), 95)
        XCTAssertEqual(TemperatureUnit.fahrenheit.fromFahrenheit(95), 95)
        XCTAssertEqual(TemperatureUnit.fahrenheit.differenceFromFahrenheit(18), 18)
    }

    func testCelsiusConversions() {
        XCTAssertEqual(TemperatureUnit.celsius.fromFahrenheit(32), 0)
        XCTAssertEqual(TemperatureUnit.celsius.fromFahrenheit(212), 100)
        XCTAssertEqual(TemperatureUnit.celsius.fromFahrenheit(95), 35)   // 35.0
        XCTAssertEqual(TemperatureUnit.celsius.toFahrenheit(0), 32)
        XCTAssertEqual(TemperatureUnit.celsius.toFahrenheit(100), 212)
        XCTAssertEqual(TemperatureUnit.celsius.toFahrenheit(35), 95)
    }

    func testCelsiusDifference() {
        // A 20 °F wet-bulb depression is ~11 °C.
        XCTAssertEqual(TemperatureUnit.celsius.differenceFromFahrenheit(20), 11)
        XCTAssertEqual(TemperatureUnit.celsius.differenceFromFahrenheit(18), 10)
    }

    /// Round-tripping °F → °C → °F stays within 1 °F (the display resolution).
    func testRoundTripStability() {
        for f in stride(from: -20, through: 130, by: 1) {
            let c = TemperatureUnit.celsius.fromFahrenheit(f)
            let back = TemperatureUnit.celsius.toFahrenheit(c)
            XCTAssertLessThanOrEqual(abs(back - f), 1, "round trip drifted at \(f) °F")
        }
    }
}
