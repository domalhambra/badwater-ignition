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

    func testBackfilledObsFreezesAgainstChronologicalPredecessor() {
        let ign = ignition(dry: 60, rh: 25)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.prev"))
        w.addressee = "Diamond Mountain"
        let t0 = Date(timeIntervalSince1970: 0)

        _ = w.logObs(at: t0)                                     // 0000 · 60 / 25
        ign.dryBulbF = 70; ign.relativeHumidity = 15
        _ = w.logObs(at: t0.addingTimeInterval(7200))            // 0200 · 70 / 15
        // BACK-FILL the forgotten 0100: its frozen script must compare against
        // the 0000 (its predecessor in time), not the 0200 (latest at log time).
        ign.dryBulbF = 65; ign.relativeHumidity = 20
        let backfilled = w.logObs(at: t0.addingTimeInterval(3600))
        let script = w.broadcastScript(for: backfilled)
        XCTAssertTrue(script.contains("Dry Bulb 65 degrees, up 5"), script)
        XCTAssertTrue(script.contains("RH 20%, down 5"), script)
    }

    func testFrozenBroadcastSurvivesEditsDeletesAndAddresseeChange() {
        let ign = ignition(dry: 60, rh: 25)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.frozen"))
        w.addressee = "Diamond Mountain"
        let t0 = Date(timeIntervalSince1970: 0)

        let first = w.logObs(at: t0)
        ign.dryBulbF = 65; ign.relativeHumidity = 20
        let second = w.logObs(at: t0.addingTimeInterval(3600))
        let asSpoken = w.broadcastScript(for: second)
        XCTAssertTrue(asSpoken.contains("up 5"), asSpoken)

        // Neither renaming the net nor deleting the neighbor can retro-alter
        // the record of what went out over the air.
        w.addressee = "Silver Creek"
        w.removeObs(id: first.id)
        XCTAssertEqual(w.broadcastScript(for: second), asSpoken)
        XCTAssertTrue(asSpoken.hasPrefix("Diamond Mountain,"))
    }

    func testSuppressLocationAtLogTime() {
        let w = WeatherWatchModel(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.suppress"))
        w.setShiftHeader(division: nil, locationName: "near the 659 road")
        // Even the first obs of a shift stays silent when the operator asserts
        // "location unchanged" explicitly.
        let obs = w.logObs(suppressLocation: true)
        XCTAssertFalse(w.broadcastScript(for: obs).contains("Taken"))
    }

    func testLocationTextEditReannounces() {
        let ign = ignition(dry: 80, rh: 15)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.locmove"))
        w.setShiftHeader(division: nil, locationName: "near the 659 road")
        let t0 = Date(timeIntervalSince1970: 0)
        _ = w.logObs(at: t0)
        // Crew relocates along the ridge — same elevation band, same aspect —
        // and retypes only the location. The next broadcast must announce it.
        w.setShiftHeader(division: nil, locationName: "at the saddle above Split Rock")
        let moved = w.logObs(at: t0.addingTimeInterval(3600))
        XCTAssertTrue(w.broadcastScript(for: moved).contains("Taken at the saddle above Split Rock"))
        // And an unchanged location stays suppressed.
        let third = w.logObs(at: t0.addingTimeInterval(7200))
        XCTAssertFalse(w.broadcastScript(for: third).contains("Taken"))
    }

    func testSiteCoordinateFoldsIntoLogAndPersists() {
        let store = fresh("watch.coord")
        let ign = ignition(dry: 80, rh: 15)
        let w = WeatherWatchModel(ignition: ign, store: store)
        w.siteCoordinate = GeoPoint(latitude: 38.21437, longitude: -112.3978)
        // The sticky decimal lat/long lands on the logged obs (spreadsheet column J).
        XCTAssertEqual(w.logObs().location?.rendered, "38.21437, -112.3978")
        // An explicit per-obs coordinate wins over the sticky one.
        let explicit = GeoPoint(latitude: 38.5, longitude: -112.5)
        XCTAssertEqual(w.logObs(location: explicit).location, explicit)
        // Persists across instances; clearing removes the key.
        XCTAssertEqual(WeatherWatchModel(ignition: ign, store: store).siteCoordinate?.rendered,
                       "38.21437, -112.3978")
        w.siteCoordinate = nil
        XCTAssertNil(WeatherWatchModel(ignition: ign, store: store).siteCoordinate)
    }

    func testNoteTrimsAndFolds() {
        let w = WeatherWatchModel(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.note"))
        XCTAssertEqual(w.logObs(note: "  sun on thermometer  ").note, "sun on thermometer")
        XCTAssertNil(w.logObs(note: "   ").note)
        XCTAssertNil(w.logObs().note)
    }

    func testSiteConfirmationLifecycle() {
        let store = fresh("watch.confirm")
        let ign = ignition(dry: 80, rh: 15)
        let w = WeatherWatchModel(ignition: ign, store: store)
        XCTAssertTrue(w.needsSiteConfirmation)          // fresh shift: gate is up
        w.confirmSite()
        XCTAssertFalse(w.needsSiteConfirmation)
        // Confirmation persists across instances…
        XCTAssertFalse(WeatherWatchModel(ignition: ign, store: store).needsSiteConfirmation)
        // …and a new shift demands a fresh review.
        w.startNewShift()
        XCTAssertTrue(w.needsSiteConfirmation)
        XCTAssertTrue(WeatherWatchModel(ignition: ign, store: store).needsSiteConfirmation)
    }

    func testUndoRestoresDeletedObs() {
        let w = WeatherWatchModel(ignition: ignition(dry: 90, rh: 8), store: fresh("watch.undo"))
        let t0 = Date(timeIntervalSince1970: 0)
        let a = w.logObs(at: t0)
        _ = w.logObs(at: t0.addingTimeInterval(3600))
        w.removeObs(id: a.id)
        XCTAssertEqual(w.shift.obs.count, 1)
        // Undo restores the obs; timestamp-ordered reads put it back in place.
        XCTAssertEqual(w.undoRemoveObs()?.id, a.id)
        XCTAssertEqual(w.shift.obs.count, 2)
        XCTAssertEqual(w.series(of: .temperature).first?.date, t0)
        // A second undo is a no-op.
        XCTAssertNil(w.undoRemoveObs())
    }

    func testWeatherStalenessWarning() {
        let ign = ignition(dry: 80, rh: 15)   // helper edits inputs -> stamps weatherEditedAt
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.stale"))
        XCTAssertFalse(w.isPendingWeatherStale())       // just edited
        let inFiveHours = Date().addingTimeInterval(5 * 3600)
        XCTAssertTrue(w.isPendingWeatherStale(at: inFiveHours))
        XCTAssertNotNil(w.pendingWeatherAge(at: inFiveHours))
        // "Mark current" clears the warning without a fabricated edit.
        w.confirmPendingWeatherCurrent(at: inFiveHours)
        XCTAssertFalse(w.isPendingWeatherStale(at: inFiveHours))
    }

    func testPreFeatureObsRendersLiveScript() {
        // An obs persisted before broadcastText existed (simulated by appending
        // a pendingObs directly) falls back to live rendering.
        let ign = ignition(dry: 60, rh: 25)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.prefeature"))
        w.addressee = "Diamond Mountain"
        let legacy = w.pendingObs(at: Date(timeIntervalSince1970: 0))
        w.shift.obs.append(legacy)                       // bypasses logObs freezing
        XCTAssertNil(legacy.broadcastText)
        let script = w.broadcastScript(for: legacy)
        XCTAssertTrue(script.hasPrefix("Diamond Mountain, stand by for your"))
    }

    func testPreFeatureReplayNeverBorrowsTheCurrentLocation() {
        // A legacy obs has no frozen spokenLocation. Replaying it after the crew
        // renamed the site must NOT put the crew's CURRENT location into the
        // historical script — an unknown location degrades to aspect only.
        let ign = ignition(dry: 60, rh: 25)
        let w = WeatherWatchModel(ignition: ign, store: fresh("watch.prefeature2"))
        w.setShiftHeader(division: nil, locationName: "near the 659 road")
        let legacy = w.pendingObs(at: Date(timeIntervalSince1970: 0))
        w.shift.obs.append(legacy)                       // logged pre-feature
        w.setShiftHeader(division: nil, locationName: "at the saddle above Split Rock")
        let replay = w.broadcastScript(for: legacy)
        XCTAssertFalse(replay.contains("at the saddle above Split Rock"), replay)
        // The pending PREVIEW, by contrast, is the current position — live applies.
        let preview = w.broadcastScript(for: w.pendingObs(at: Date(timeIntervalSince1970: 7200)))
        XCTAssertTrue(preview.contains("at the saddle above Split Rock"), preview)
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
