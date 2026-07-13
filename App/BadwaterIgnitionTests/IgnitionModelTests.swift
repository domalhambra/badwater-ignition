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

    // MARK: - Weather-edit tracking (staleness, red-team #3)

    func testWeatherEditsStampTimestampAndPersist() {
        let store = freshStore()
        let a = IgnitionModel(store: store)
        XCTAssertNil(a.weatherEditedAt)                 // untouched install
        XCTAssertNil(a.weatherAge())
        a.dryBulbF = 90
        let stamped = try! XCTUnwrap(a.weatherEditedAt)
        XCTAssertLessThan(abs(stamped.timeIntervalSinceNow), 5)
        XCTAssertNotNil(a.weatherAge())
        // Site-factor edits are NOT weather edits — the stamp must not move.
        a.aspect = .west
        a.slope = .steep
        XCTAssertEqual(a.weatherEditedAt, stamped)
        // The stamp survives a relaunch, so "five hours old" is knowable later.
        XCTAssertEqual(IgnitionModel(store: store).weatherEditedAt!.timeIntervalSince1970,
                       stamped.timeIntervalSince1970, accuracy: 0.001)
    }

    func testTornStoreClampDoesNotFakeAFreshWeatherEdit() {
        // Simulate an interrupted persist: wet > dry on disk with an hours-old
        // edit stamp. Init clamps the wet bulb (fires its didSet), but the stamp
        // must survive as-restored — a restore is not a user edit.
        let store = freshStore()
        store.set(70, forKey: "ignition.dryBulbF")
        store.set(90, forKey: "ignition.wetBulbF")        // torn: wet > dry
        let fiveHoursAgo = Date().addingTimeInterval(-5 * 3600).timeIntervalSince1970
        store.set(fiveHoursAgo, forKey: "ignition.weatherEditedAt")

        let m = IgnitionModel(store: store)
        XCTAssertLessThanOrEqual(m.wetBulbF, m.dryBulbF)  // clamp still applied
        XCTAssertEqual(m.weatherEditedAt!.timeIntervalSince1970, fiveHoursAgo, accuracy: 0.001)
        // And the store still carries the old stamp for the NEXT launch too.
        XCTAssertEqual(store.object(forKey: "ignition.weatherEditedAt") as? Double ?? 0,
                       fiveHoursAgo, accuracy: 0.001)
    }

    // MARK: - Clock auto-refresh (red-team #4)

    private func mountain() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }

    func testRefreshClockTracksWallClockUntilOverridden() {
        let cal = mountain()
        let dawn = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 7, minute: 55))!
        let m = IgnitionModel(store: freshStore(), now: dawn, calendar: cal)
        XCTAssertEqual(m.timeOfDay, .night)             // pre-0800 launch
        XCTAssertFalse(m.clockOverridden)

        // Six hours later the tick re-derives the band — no more silent night +5.
        let afternoon = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14, minute: 30))!
        m.refreshClock(now: afternoon, calendar: cal)
        XCTAssertEqual(m.timeOfDay, .band1400_1559)
        XCTAssertEqual(m.month, 8)
        XCTAssertFalse(m.clockOverridden)               // auto writes don't count as overrides

        // A manual pick (forecasting tomorrow morning) stands: ticks stop moving it.
        m.timeOfDay = .band0800_0959
        XCTAssertTrue(m.clockOverridden)
        m.refreshClock(now: afternoon, calendar: cal)
        XCTAssertEqual(m.timeOfDay, .band0800_0959)

        // Resuming auto snaps back to the clock.
        m.resumeAutoClock(now: afternoon, calendar: cal)
        XCTAssertFalse(m.clockOverridden)
        XCTAssertEqual(m.timeOfDay, .band1400_1559)
    }

    func testManualMonthAlsoOverrides() {
        let cal = mountain()
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10))!
        let m = IgnitionModel(store: freshStore(), now: now, calendar: cal)
        m.month = 11                                     // forecasting a late-season burn
        XCTAssertTrue(m.clockOverridden)
        m.refreshClock(now: now, calendar: cal)
        XCTAssertEqual(m.month, 11)                      // override respected
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
