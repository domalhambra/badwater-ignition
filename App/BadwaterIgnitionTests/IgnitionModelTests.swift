import XCTest
import BadwaterCore
@testable import BadwaterIgnition

/// Unit tests for the view-model layer. These run in the simulator (the models
/// use the Observation framework), and exercise the real persistence, wet-bulb
/// RH derivation, and hand-off logic rather than the UI.
final class IgnitionModelTests: XCTestCase {

    private func freshStore(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "test.\(name)")!
        d.removePersistentDomain(forName: "test.\(name)")
        return d
    }

    func testEstimateReflectsInputs() {
        let m = IgnitionModel(store: freshStore())
        m.dryBulbF = 95
        m.relativeHumidity = 12
        m.month = 7
        m.timeOfDay = .band1400_1559
        m.aspect = .south
        m.slope = .gentle
        m.elevationDelta = .level
        // Matches the BadwaterCore worked example (unshaded PIG 100, shaded 70).
        XCTAssertEqual(m.estimate.referenceFuelMoisture, 2)
        XCTAssertEqual(m.estimate.unshaded.probabilityOfIgnition, 100)
        XCTAssertEqual(m.estimate.shaded.probabilityOfIgnition, 70)
    }

    func testSiteFactorsPersistAcrossInstances() {
        let store = freshStore()
        let a = IgnitionModel(store: store)
        a.aspect = .west
        a.slope = .steep
        a.elevationDelta = .above
        // A new model reading the same store restores the site factors.
        let b = IgnitionModel(store: store)
        XCTAssertEqual(b.aspect, .west)
        XCTAssertEqual(b.slope, .steep)
        XCTAssertEqual(b.elevationDelta, .above)
    }

    func testApplyHumidityClampsAndSets() {
        let m = IgnitionModel(store: freshStore())
        m.applyHumidity(150)
        XCTAssertEqual(m.relativeHumidity, 100)
        m.applyHumidity(-5)
        XCTAssertEqual(m.relativeHumidity, 0)
        m.applyHumidity(37)
        XCTAssertEqual(m.relativeHumidity, 37)
    }

    func testNightModeUsesPlusFive() {
        let m = IgnitionModel(store: freshStore())
        m.dryBulbF = 95
        m.relativeHumidity = 12
        m.timeOfDay = .night
        XCTAssertTrue(m.estimate.isNight)
        XCTAssertNil(m.estimate.unshaded.correction)
        XCTAssertEqual(m.estimate.unshaded.fineFuelMoisture, m.estimate.referenceFuelMoisture + 5)
    }

    func testDirectSourceUsesTypedHumidity() {
        let m = IgnitionModel(store: freshStore())
        m.rhSource = .direct
        m.relativeHumidity = 22
        m.wetBulbF = 40   // must be ignored in direct mode
        XCTAssertEqual(m.effectiveRelativeHumidity, 22)
    }

    func testWetBulbSourceDerivesHumidity() {
        let m = IgnitionModel(store: freshStore())
        m.rhSource = .wetBulb
        m.dryBulbF = 80
        m.wetBulbF = 65
        m.elevationBand = .band1
        m.relativeHumidity = 5   // stale direct value must be ignored
        let expected = Psychrometrics.compute(dryBulbF: 80, wetBulbF: 65, band: .band1).relativeHumidity
        XCTAssertEqual(m.effectiveRelativeHumidity, expected)
        XCTAssertEqual(expected, 44, accuracy: 1)   // PMS 437 sea-level golden cell
        // The PIG estimate consumes the derived RH, not the typed one.
        XCTAssertEqual(m.estimate.input.relativeHumidity, expected)
    }

    func testWetBulbClampedToDryBulb() {
        let m = IgnitionModel(store: freshStore())
        m.rhSource = .wetBulb
        m.dryBulbF = 70
        m.wetBulbF = 65
        m.dryBulbF = 60   // lowering dry bulb pulls the wet bulb down with it
        XCTAssertLessThanOrEqual(m.wetBulbF, 60)
    }

    func testRaisingWetBulbAboveDryClamps() {
        let m = IgnitionModel(store: freshStore())
        m.rhSource = .wetBulb
        m.dryBulbF = 70
        m.wetBulbF = 90                       // typed above the dry bulb
        XCTAssertEqual(m.wetBulbF, 70)        // clamped down on edit, not only when dry drops
        XCTAssertLessThanOrEqual(m.effectiveRelativeHumidity, 100)   // no impossible >100% RH
    }

    func testApplyHumiditySwitchesToDirect() {
        let m = IgnitionModel(store: freshStore())
        m.rhSource = .wetBulb
        m.applyHumidity(37)
        XCTAssertEqual(m.rhSource, .direct)
        XCTAssertEqual(m.relativeHumidity, 37)
        XCTAssertEqual(m.effectiveRelativeHumidity, 37)
    }

    func testHumiditySourceAndWetBulbPersist() {
        let store = freshStore()
        let a = IgnitionModel(store: store)
        a.rhSource = .wetBulb
        a.wetBulbF = 58
        a.elevationBand = .band4
        let b = IgnitionModel(store: store)
        XCTAssertEqual(b.rhSource, .wetBulb)
        XCTAssertEqual(b.wetBulbF, 58)
        XCTAssertEqual(b.elevationBand, .band4)
    }
}

final class HumidityModelTests: XCTestCase {

    func testResultUpdatesAndClampsWetBulb() {
        let store = UserDefaults(suiteName: "test.humidity")!
        store.removePersistentDomain(forName: "test.humidity")
        let m = HumidityModel(store: store)
        m.band = .band1
        m.dryBulbF = 61
        m.wetBulbF = 45
        XCTAssertEqual(m.result.relativeHumidity, 23, accuracy: 1)   // PMS 437 sea-level cell

        // Lowering dry bulb below wet bulb clamps the wet bulb.
        m.dryBulbF = 40
        XCTAssertLessThanOrEqual(m.wetBulbF, 40)

        // Raising the wet bulb above the dry bulb clamps it too.
        m.dryBulbF = 61
        m.wetBulbF = 80
        XCTAssertEqual(m.wetBulbF, 61)
        XCTAssertLessThanOrEqual(m.result.relativeHumidity, 100)
    }

    func testBandLabelRespectsAlaska() {
        let store = UserDefaults(suiteName: "test.humidity2")!
        store.removePersistentDomain(forName: "test.humidity2")
        let m = HumidityModel(store: store)
        m.band = .band2
        m.alaska = false
        XCTAssertEqual(m.label(for: .band2), ElevationBand.band2.conusLabel)
        m.alaska = true
        XCTAssertEqual(m.label(for: .band2), ElevationBand.band2.alaskaLabel)
    }
}
