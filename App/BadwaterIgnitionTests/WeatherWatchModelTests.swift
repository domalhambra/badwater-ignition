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

    func testRemoveObsDeletesAndPersists() {
        let store = fresh("watch.remove")
        let w = WeatherWatchModel(ignition: ignition(dry: 90, rh: 8), store: store)
        let a = w.logObs()
        let b = w.logObs()
        XCTAssertEqual(w.shift.obs.count, 2)

        w.removeObs(id: a.id)                       // drop the mis-entry
        XCTAssertEqual(w.shift.obs.map(\.id), [b.id])

        // Delete persisted: a fresh model on the same store sees only the survivor.
        let reloaded = WeatherWatchModel(ignition: ignition(dry: 90, rh: 8), store: store)
        XCTAssertEqual(reloaded.shift.obs.count, 1)
        XCTAssertEqual(reloaded.shift.obs.first?.id, b.id)
    }

    func testAddresseePersistsAcrossInstances() {
        let store = fresh("watch.addressee")
        let ign = ignition(dry: 80, rh: 15)
        let a = WeatherWatchModel(ignition: ign, store: store)
        a.addressee = "Diamond Mountain"
        let b = WeatherWatchModel(ignition: ign, store: store)
        XCTAssertEqual(b.addressee, "Diamond Mountain")
    }

    func testSiteElevationDrivesSlungBandAndStampsElevation() {
        let ign = IgnitionModel(store: fresh("watch.siteelev.ign"))
        ign.rhSource = .wetBulb
        ign.dryBulbF = 80
        ign.wetBulbF = 65
        ign.elevationBand = .band1                 // stale band left on the Ignition tab
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.siteelev"))

        // No site elevation yet → falls back to the Ignition tab's band.
        XCTAssertEqual(w.pendingObs().humidity?.elevationBand, .band1)

        // Entering a high site elevation re-bands the sling RH to THAT elevation.
        w.siteElevationFeet = 9000
        let expectedBand = ElevationBand.forElevation(feetMSL: 9000)   // band6
        let obs = w.pendingObs()
        XCTAssertEqual(obs.humidity?.elevationBand, expectedBand)
        // The frozen RH and the PIG estimate agree (both use the elevation band).
        let expectedRH = Psychrometrics.compute(dryBulbF: 80, wetBulbF: 65, band: expectedBand).relativeHumidity
        XCTAssertEqual(obs.humidity?.relativeHumidity, expectedRH)
        XCTAssertEqual(obs.value(of: .relativeHumidity), expectedRH)

        // Logging with no explicit elevation stamps the sticky site elevation.
        XCTAssertEqual(w.logObs().elevationFeet, 9000)
    }

    func testSiteElevationPersistsAndClears() {
        let store = fresh("watch.siteelev.persist")
        let ign = ignition(dry: 80, rh: 15)
        let a = WeatherWatchModel(ignition: ign, store: store)
        a.siteElevationFeet = 7200
        XCTAssertEqual(WeatherWatchModel(ignition: ign, store: store).siteElevationFeet, 7200)
        // Clearing removes the key (a fresh model reads it back as nil, not 0).
        a.siteElevationFeet = nil
        XCTAssertNil(WeatherWatchModel(ignition: ign, store: store).siteElevationFeet)
    }

    func testLatestFollowsTimestampNotAppendOrder() {
        let w = WeatherWatchModel(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.latest"))
        let t0 = Date(timeIntervalSince1970: 0)
        let later = w.logObs(at: t0.addingTimeInterval(3600))   // 0100
        _ = w.logObs(at: t0)                                    // 0000, back-filled AFTER
        XCTAssertEqual(w.latest?.id, later.id)                  // chronological max, not the tail
    }

    func testBroadcastPreviousIsChronological() {
        let ign = ignition(dry: 60, rh: 25)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.prev"))
        w.addressee = "Diamond Mountain"
        let t0 = Date(timeIntervalSince1970: 0)

        // Log the 0100 first, then BACK-FILL the 0000 after it.
        ign.dryBulbF = 65; ign.relativeHumidity = 20
        let later = w.logObs(at: t0.addingTimeInterval(3600))   // 65 / 20
        ign.dryBulbF = 60; ign.relativeHumidity = 25
        let earlier = w.logObs(at: t0)                          // 60 / 25 (precedes in time)

        // The 0100's predecessor is the chronologically-earlier 0000, though it was
        // appended later: deltas 65−60 = up 5, 20−25 = down 5.
        let script = w.broadcastScript(for: later)
        XCTAssertTrue(script.contains("Dry Bulb 65 degrees, up 5"), script)
        XCTAssertTrue(script.contains("RH 20%, down 5"), script)
        // The earliest obs has no predecessor → no deltas.
        let firstScript = w.broadcastScript(for: earlier)
        XCTAssertFalse(firstScript.contains(", up"))
        XCTAssertFalse(firstScript.contains(", down"))
    }

    func testBroadcastScriptResolvesPreviousObs() {
        let ign = ignition(dry: 80, rh: 15)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.script"))
        w.addressee = "Diamond Mountain"

        let first = w.logObs()
        let firstScript = w.broadcastScript(for: first)
        XCTAssertTrue(firstScript.hasPrefix("Diamond Mountain, stand by for your"))
        XCTAssertFalse(firstScript.contains(", up"))       // no deltas on the first obs

        ign.dryBulbF = 85
        ign.relativeHumidity = 12
        let second = w.logObs()
        let script = w.broadcastScript(for: second)
        XCTAssertTrue(script.contains("Dry Bulb 85 degrees, up 5"))
        XCTAssertTrue(script.contains("RH 12%, down 3"))
    }
}
