import XCTest

/// Black-box UI smoke tests. These require a simulator/device (run from Xcode);
/// they exercise the navigation and the RH → Ignition hand-off using the
/// accessibility identifiers set on the controls.
final class BadwaterIgnitionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsBothPigResults() {
        let app = XCUIApplication()
        app.launch()
        // The Ignition tab shows both shaded and unshaded results on launch.
        XCTAssertTrue(app.staticTexts["result-Unshaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["result-Shaded"].exists)
        XCTAssertTrue(app.otherElements["calc-chain"].exists)
    }

    func testHumidityTabAndHandoff() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Humidity"].tap()
        XCTAssertTrue(app.otherElements["rh-readout"].waitForExistence(timeout: 5))

        // "Use in ignition calc" pushes RH into the Ignition tab and switches to it.
        app.buttons["use-in-ignition"].tap()
        XCTAssertTrue(app.staticTexts["result-Unshaded"].waitForExistence(timeout: 5))
    }

    func testDryBulbIsAdjustable() {
        let app = XCUIApplication()
        app.launch()
        let dryBulb = app.otherElements["Dry bulb"]
        XCTAssertTrue(dryBulb.waitForExistence(timeout: 5))
        // Adjustable element: a swipe up should increment without crashing.
        dryBulb.swipeUp()
        XCTAssertTrue(app.staticTexts["result-Unshaded"].exists)
    }

    func testWetBulbSourceRevealsWetBulbInput() {
        let app = XCUIApplication()
        app.launch()
        // Switching the humidity source to "From wet bulb" reveals the wet-bulb
        // stepper; the PIG results keep rendering with the derived RH.
        app.buttons["From wet bulb"].tap()
        XCTAssertTrue(app.otherElements["Wet bulb"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["derived-rh"].exists)
        XCTAssertTrue(app.staticTexts["result-Unshaded"].exists)
    }
}
