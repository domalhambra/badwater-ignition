import XCTest
import BadwaterCore
@testable import BadwaterIgnition

/// Unit tests for the view-model layer. These run in the simulator (the models
/// use the Observation framework), and exercise the real persistence and
/// hand-off logic rather than the UI.
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
