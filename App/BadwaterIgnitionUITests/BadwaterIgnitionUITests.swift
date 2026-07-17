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

    func testWatchTabLogsAnObservation() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Obs"].tap()
        // Fresh shift shows the empty state until the first log.
        XCTAssertTrue(app.otherElements["watch-empty"].waitForExistence(timeout: 5))

        // The first log of a shift is gated on an explicit site review.
        app.buttons["confirm-site"].tap()

        // Logging freezes the current reading into the shift: the hero (both PIG
        // results + the radio line) appears and the empty state goes away.
        app.buttons["log-observation"].tap()
        XCTAssertTrue(app.staticTexts["result-Unshaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["result-Shaded"].exists)
        XCTAssertTrue(app.staticTexts["radio-line"].exists)
        XCTAssertFalse(app.otherElements["watch-empty"].exists)
    }

    func testWatchCaptureCardIsPresent() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Obs"].tap()
        // The pending capture card is always available — note field, dry-bulb
        // stepper, and the live PIG preview — so a reading can be built and logged.
        XCTAssertTrue(app.textFields["obs-note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["Dry bulb"].exists)
        XCTAssertTrue(app.staticTexts["pending-pig"].exists)
    }
}
