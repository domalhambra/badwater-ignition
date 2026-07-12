import XCTest
import BadwaterCore
@testable import BadwaterIgnition

/// View-model tests for Weather Watch. These run in the simulator (Observation +
/// UserDefaults); the pure trigger/obs logic is covered by WeatherWatchTests in
/// BadwaterCore on Linux CI.
final class WeatherWatchModelTests: XCTestCase {

    private func fresh(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "test.\(name)")!
        d.removePersistentDomain(forName: "test.\(name)")
        return d
    }

    private func ignition(dry: Int, rh: Int) -> IgnitionModel {
        let m = IgnitionModel(store: fresh("watch.ign.\(dry).\(rh)"))
        m.rhSource = .direct
        m.dryBulbF = dry
        m.relativeHumidity = rh
        m.aspect = .south; m.slope = .gentle; m.elevationDelta = .level
        return m
    }

    func testLogFreezesLiveInputsAndTriggers() {
        let w = WeatherWatchModel(ignition: ignition(dry: 90, rh: 8), store: fresh("watch.log"))
        w.addTrigger(BriefedTrigger(metric: .relativeHumidity, direction: .fallsToAtOrBelow, value: 20))

        w.logObs()
        XCTAssertEqual(w.shift.obs.count, 1)
        let obs = try! XCTUnwrap(w.latest)
        XCTAssertEqual(obs.value(of: .temperature), 90)          // frozen dry bulb
        XCTAssertEqual(obs.value(of: .relativeHumidity), 8)      // direct RH used
        XCTAssertEqual(obs.crossedTriggerIDs, [w.triggers[0].id]) // RH 8 ≤ 20 frozen at log time
        XCTAssertEqual(w.crossedCount, 1)
    }

    func testShiftPersistsAcrossInstances() {
        let store = fresh("watch.persist")
        let ign = ignition(dry: 85, rh: 12)
        let a = WeatherWatchModel(ignition: ign, store: store)
        a.logObs()
        a.logObs()
        // A new model on the same store restores the shift.
        let b = WeatherWatchModel(ignition: ign, store: store)
        XCTAssertEqual(b.shift.obs.count, 2)
    }

    func testStartNewShiftClearsObs() {
        let w = WeatherWatchModel(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.new"))
        w.logObs()
        w.startNewShift()
        XCTAssertTrue(w.shift.obs.isEmpty)
    }
}
