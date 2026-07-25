import XCTest
import BadwaterCore
@testable import BadwaterIgnition

/// View-model tests for Weather Watch. These run in the simulator (Observation +
/// UserDefaults); the pure observation logic is covered by WeatherWatchTests in
/// BadwaterCore on Linux CI.
@MainActor
final class WeatherWatchModelTests: XCTestCase {

    private func fresh(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "test.\(name)")!
        d.removePersistentDomain(forName: "test.\(name)")
        return d
    }

    /// Per-test-method record directory.
    ///
    /// The observation record moved from a per-test `UserDefaults` suite into a
    /// file (ObservationRecordStore). Without an App Group entitlement — which CI
    /// has not, building with CODE_SIGNING_ALLOWED=NO — that file lands in one
    /// shared Application Support directory, so every model in every test read
    /// and wrote the *same* shift. Keyed on `#function`, so constructions within
    /// one test share a directory (reload-from-the-same-store tests still work)
    /// while different tests are isolated.
    private var recordDirectories: [String: URL] = [:]

    private func recordDirectory(_ key: String) -> URL {
        if let existing = recordDirectories[key] { return existing }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bw-watch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        recordDirectories[key] = url
        return url
    }

    /// Build a model whose record is isolated to this test.
    private func model(ignition ign: IgnitionModel, store: UserDefaults,
                       dir key: String = #function) -> WeatherWatchModel {
        WeatherWatchModel(
            ignition: ign, store: store,
            record: ObservationRecordStore(defaults: store, directory: recordDirectory(key)))
    }

    private func ignition(dry: Int, rh: Int) -> IgnitionModel {
        let m = IgnitionModel(store: fresh("watch.ign.\(dry).\(rh)"))
        m.rhSource = .direct
        m.dryBulbF = dry
        m.relativeHumidity = rh
        m.aspect = .south; m.slope = .gentle; m.elevationDelta = .level
        return m
    }

    func testLogFreezesLiveInputs() {
        let w = model(ignition: ignition(dry: 90, rh: 8), store: fresh("watch.log"))

        w.logObs()
        XCTAssertEqual(w.shift.obs.count, 1)
        let obs = try! XCTUnwrap(w.latest)
        XCTAssertEqual(obs.value(of: .temperature), 90)          // frozen dry bulb
        XCTAssertEqual(obs.value(of: .relativeHumidity), 8)      // direct RH used
    }

    func testShiftPersistsAcrossInstances() {
        let store = fresh("watch.persist")
        let ign = ignition(dry: 85, rh: 12)
        let a = model(ignition: ign, store: store)
        a.logObs()
        a.logObs()
        // A new model on the same store restores the shift.
        let b = model(ignition: ign, store: store)
        XCTAssertEqual(b.shift.obs.count, 2)
    }

    func testStartNewShiftClearsObs() {
        let w = model(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.new"))
        w.logObs()
        w.startNewShift()
        XCTAssertTrue(w.shift.obs.isEmpty)
    }

    func testRemoveObsDeletesAndPersists() {
        let store = fresh("watch.remove")
        let w = model(ignition: ignition(dry: 90, rh: 8), store: store)
        let a = w.logObs()
        let b = w.logObs()
        XCTAssertEqual(w.shift.obs.count, 2)

        w.removeObs(id: a.id)                       // drop the mis-entry
        XCTAssertEqual(w.shift.obs.map(\.id), [b.id])

        // Delete persisted: a fresh model on the same store sees only the survivor.
        let reloaded = model(ignition: ignition(dry: 90, rh: 8), store: store)
        XCTAssertEqual(reloaded.shift.obs.count, 1)
        XCTAssertEqual(reloaded.shift.obs.first?.id, b.id)
    }

    func testAddresseePersistsAcrossInstances() {
        let store = fresh("watch.addressee")
        let ign = ignition(dry: 80, rh: 15)
        let a = model(ignition: ign, store: store)
        a.addressee = "Diamond Mountain"
        let b = model(ignition: ign, store: store)
        XCTAssertEqual(b.addressee, "Diamond Mountain")
    }

    func testSiteElevationDrivesSlungBandAndStampsElevation() {
        let ign = IgnitionModel(store: fresh("watch.siteelev.ign"))
        ign.rhSource = .wetBulb
        ign.dryBulbF = 80
        ign.wetBulbF = 65
        ign.elevationBand = .band1                 // stale band left on the Ignition tab
        let w = model(ignition: ign, store: fresh("watch.siteelev"))

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
        let a = model(ignition: ign, store: store)
        a.siteElevationFeet = 7200
        XCTAssertEqual(model(ignition: ign, store: store).siteElevationFeet, 7200)
        // Clearing removes the key (a fresh model reads it back as nil, not 0).
        a.siteElevationFeet = nil
        XCTAssertNil(model(ignition: ign, store: store).siteElevationFeet)
    }

    func testLatestFollowsTimestampNotAppendOrder() {
        let w = model(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.latest"))
        let t0 = Date(timeIntervalSince1970: 0)
        let later = w.logObs(at: t0.addingTimeInterval(3600))   // 0100
        _ = w.logObs(at: t0)                                    // 0000, back-filled AFTER
        XCTAssertEqual(w.latest?.id, later.id)                  // chronological max, not the tail
    }

    func testBackfilledObsFreezesAgainstChronologicalPredecessor() {
        let ign = ignition(dry: 60, rh: 25)
        let w = model(ignition: ign, store: fresh("watch.prev"))
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
        let w = model(ignition: ign, store: fresh("watch.frozen"))
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
        let w = model(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.suppress"))
        w.setShiftHeader(division: nil, locationName: "near the 659 road")
        // Even the first obs of a shift stays silent when the operator asserts
        // "location unchanged" explicitly.
        let obs = w.logObs(suppressLocation: true)
        XCTAssertFalse(w.broadcastScript(for: obs).contains("Taken"))
    }

    func testLocationTextEditReannounces() {
        let ign = ignition(dry: 80, rh: 15)
        let w = model(ignition: ign, store: fresh("watch.locmove"))
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
        let w = model(ignition: ign, store: store)
        w.siteCoordinate = GeoPoint(latitude: 38.21437, longitude: -112.3978)
        // The sticky decimal lat/long lands on the logged obs (spreadsheet column J).
        XCTAssertEqual(w.logObs().location?.rendered, "38.21437, -112.3978")
        // An explicit per-obs coordinate wins over the sticky one.
        let explicit = GeoPoint(latitude: 38.5, longitude: -112.5)
        XCTAssertEqual(w.logObs(location: explicit).location, explicit)
        // Persists across instances; clearing removes the key.
        XCTAssertEqual(model(ignition: ign, store: store).siteCoordinate?.rendered,
                       "38.21437, -112.3978")
        w.siteCoordinate = nil
        XCTAssertNil(model(ignition: ign, store: store).siteCoordinate)
    }

    func testNoteTrimsAndFolds() {
        let w = model(ignition: ignition(dry: 80, rh: 15), store: fresh("watch.note"))
        XCTAssertEqual(w.logObs(note: "  sun on thermometer  ").note, "sun on thermometer")
        XCTAssertNil(w.logObs(note: "   ").note)
        XCTAssertNil(w.logObs().note)
    }

    func testSiteConfirmationLifecycle() {
        let store = fresh("watch.confirm")
        let ign = ignition(dry: 80, rh: 15)
        let w = model(ignition: ign, store: store)
        XCTAssertTrue(w.needsSiteConfirmation)          // fresh shift: gate is up
        w.confirmSite()
        XCTAssertFalse(w.needsSiteConfirmation)
        // Confirmation persists across instances…
        XCTAssertFalse(model(ignition: ign, store: store).needsSiteConfirmation)
        // …and a new shift demands a fresh review.
        w.startNewShift()
        XCTAssertTrue(w.needsSiteConfirmation)
        XCTAssertTrue(model(ignition: ign, store: store).needsSiteConfirmation)
    }

    func testUndoRestoresDeletedObs() {
        let w = model(ignition: ignition(dry: 90, rh: 8), store: fresh("watch.undo"))
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

    /// Two deletes used to leave the first unrecoverable while the undo strip
    /// still read "Observation removed". The stack keeps both, newest first.
    func testUndoWalksBackThroughMultipleDeletions() {
        let store = fresh("undostack")
        let ign = IgnitionModel(store: store)
        let w = model(ignition: ign, store: store)
        let a = w.logObs(at: Date(timeIntervalSince1970: 1_000))
        let b = w.logObs(at: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(w.shift.obs.count, 2)

        w.removeObs(id: a.id)
        w.removeObs(id: b.id)
        XCTAssertEqual(w.undoableRemovalCount, 2)
        XCTAssertTrue(w.shift.obs.isEmpty)

        // Newest deletion comes back first, then the older one.
        XCTAssertEqual(w.undoRemoveObs()?.id, b.id)
        XCTAssertEqual(w.undoableRemovalCount, 1)
        XCTAssertEqual(w.undoRemoveObs()?.id, a.id)
        XCTAssertEqual(w.undoableRemovalCount, 0)
        XCTAssertNil(w.undoRemoveObs())
        XCTAssertEqual(Set(w.shift.obs.map(\.id)), Set([a.id, b.id]))
    }

    func testUndoStackIsBounded() {
        let store = fresh("undobound")
        let ign = IgnitionModel(store: store)
        let w = model(ignition: ign, store: store)
        let logged = (0..<(WeatherWatchModel.undoDepth + 3)).map {
            w.logObs(at: Date(timeIntervalSince1970: Double(1_000 + $0)))
        }
        for obs in logged { w.removeObs(id: obs.id) }
        XCTAssertEqual(w.undoableRemovalCount, WeatherWatchModel.undoDepth)
    }

    /// Undo must not reach across a shift boundary — restoring there would append
    /// a previous shift's observation into the new one.
    func testStartingANewShiftClearsTheUndoStack() {
        let store = fresh("undoshift")
        let ign = IgnitionModel(store: store)
        let w = model(ignition: ign, store: store)
        let a = w.logObs(at: Date(timeIntervalSince1970: 1_000))
        w.removeObs(id: a.id)
        XCTAssertEqual(w.undoableRemovalCount, 1)
        w.startNewShift()
        XCTAssertEqual(w.undoableRemovalCount, 0)
        XCTAssertNil(w.undoRemoveObs())
        XCTAssertTrue(w.shift.obs.isEmpty)
    }

    func testWeatherStalenessWarning() {
        let ign = ignition(dry: 80, rh: 15)   // helper edits inputs -> stamps weatherEditedAt
        let w = model(ignition: ign, store: fresh("watch.stale"))
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
        let w = model(ignition: ign, store: fresh("watch.prefeature"))
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
        let w = model(ignition: ign, store: fresh("watch.prefeature2"))
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
        let w = model(ignition: ign, store: fresh("watch.script"))
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

/// The GPS fix-normalization rules, tested without a device, a simulator, or a
/// real `CLLocation` — `SiteLocationProvider.normalize` is pure and takes a
/// Sendable value sample, which is what makes this possible.
@MainActor
final class SiteLocationProviderTests: XCTestCase {

    private func sample(lat: Double = 38.21437, lon: Double = -112.3978,
                        altitudeMeters: Double = 1724,
                        verticalAccuracyMeters: Double = 10,
                        horizontalAccuracyMeters: Double = 5)
        -> SiteLocationProvider.LocationSample {
        SiteLocationProvider.LocationSample(
            latitude: lat, longitude: lon,
            altitudeMeters: altitudeMeters,
            verticalAccuracyMeters: verticalAccuracyMeters,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000))
    }

    func testElevationRoundsToNearestHundredFeet() {
        // 1724 m ≈ 5656.2 ft → 5700.
        let fix = SiteLocationProvider.normalize(sample())
        XCTAssertEqual(fix?.elevationFeet, 5700)
    }

    func testNoVerticalFixLeavesElevationNil() {
        // A non-positive verticalAccuracy means no altitude — the coordinate is
        // still usable, and the elevation stays for the operator to type.
        let fix = SiteLocationProvider.normalize(sample(verticalAccuracyMeters: -1))
        XCTAssertNotNil(fix)
        XCTAssertNil(fix?.elevationFeet)
        XCTAssertNil(fix?.elevationUncertaintyFeet)
        XCTAssertFalse(fix?.straddlesBandBoundary ?? true)
    }

    func testInvalidCoordinateIsRejected() {
        XCTAssertNil(SiteLocationProvider.normalize(sample(lat: 500)))
        XCTAssertNil(SiteLocationProvider.normalize(sample(lon: .nan)))
    }

    /// A fix landing on an elevation-band top must be flagged: the band picks the
    /// station pressure that derives wet-bulb RH, so the crew is told to confirm
    /// it against a map rather than trust the sensor.
    func testFixOnABandTopIsFlaggedAsStraddling() {
        // 579.12 m = 1900 ft exactly — the band2/band3 top.
        let fix = SiteLocationProvider.normalize(sample(altitudeMeters: 579.12))
        XCTAssertEqual(fix?.elevationFeet, 1900)
        XCTAssertTrue(fix?.straddlesBandBoundary ?? false)
    }

    func testMidBandFixIsNotFlagged() {
        // 914.4 m = 3000 ft, mid band3 (1,901–3,900).
        let fix = SiteLocationProvider.normalize(sample(altitudeMeters: 914.4))
        XCTAssertEqual(fix?.elevationFeet, 3000)
        XCTAssertFalse(fix?.straddlesBandBoundary ?? true)
    }

    /// The uncertainty a rounded elevation is judged by never drops below the
    /// ±50 ft the rounding itself introduces, however good the sensor claims to be.
    func testUncertaintyFloorsAtTheRoundingSlop() {
        let fix = SiteLocationProvider.normalize(sample(verticalAccuracyMeters: 1))
        XCTAssertEqual(fix?.elevationUncertaintyFeet, SiteElevation.roundingUncertaintyFeet)
    }

    func testCoordinateIsPreservedExactly() {
        let fix = SiteLocationProvider.normalize(sample())
        XCTAssertEqual(fix?.coordinate.rendered, "38.21437, -112.3978")
    }
}

/// Migration of the observation record out of `UserDefaults` and into files.
///
/// This is the highest-risk change in the storage work, so it is tested against
/// the thing that actually matters: **does every observation survive, byte for
/// byte, including the frozen broadcast text?** A migration that re-renders a
/// broadcast would rewrite the record of what was spoken on the net.
@MainActor
final class ObservationRecordStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("badwater-record-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func fresh(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "test.record.\(name)")!
        d.removePersistentDomain(forName: "test.record.\(name)")
        return d
    }

    /// Build a shift whose observations exercise the fields a careless migration
    /// would drop: a frozen broadcast, a note, wind, elevation, coordinate, and a
    /// "pre-feature" obs with those optionals nil.
    private func sampleShift(started: Date, obsCount: Int, broadcast: String?) -> Shift {
        let input = IgnitionInput(dryBulbF: 90, relativeHumidity: 8, month: 7,
                                  timeOfDay: .band1400_1559, aspect: .south,
                                  slope: .gentle, elevationDelta: .level)
        var obs: [WeatherObs] = []
        for i in 0..<obsCount {
            var o = WeatherObs(timestamp: started.addingTimeInterval(Double(i) * 3600),
                               estimate: IgnitionCalculator.estimate(input),
                               rhSource: .direct)
            if i == 0 {
                o.note = "sun on thermometer"
                o.wind = .measured(Wind.SpeedRange(low: 3, high: 6), .southwest, gust: 12)
                o.elevationFeet = 5700
                o.location = GeoPoint(latitude: 38.21437, longitude: -112.3978)
                o.spokenLocation = "near the 659 road"
                o.broadcastText = broadcast
            }
            obs.append(o)
        }
        return Shift(started: started, obs: obs, division: "Division W", locationName: "659 Road")
    }

    func testMigratesShiftAndHistoryFromUserDefaultsIntact() throws {
        let defaults = fresh("intact")
        let current = sampleShift(started: Date(timeIntervalSince1970: 1_780_000_000),
                                  obsCount: 3, broadcast: "Wx obs 1400, temp 90, RH 8")
        let history = [sampleShift(started: Date(timeIntervalSince1970: 1_779_900_000),
                                   obsCount: 2, broadcast: "Wx obs 0900, temp 70, RH 20"),
                       sampleShift(started: Date(timeIntervalSince1970: 1_779_800_000),
                                   obsCount: 1, broadcast: nil)]
        defaults.set(try JSONEncoder().encode(current),
                     forKey: ObservationRecordStore.LegacyKeys.shift)
        defaults.set(try JSONEncoder().encode(history),
                     forKey: ObservationRecordStore.LegacyKeys.history)

        let store = ObservationRecordStore(defaults: defaults, directory: tempDir)
        XCTAssertEqual(store.loadShift(), current, "current shift did not survive migration")
        XCTAssertEqual(store.loadHistory(), history, "history did not survive migration")

        // The evidentiary field specifically.
        XCTAssertEqual(store.loadShift()?.obs.first?.broadcastText,
                       "Wx obs 1400, temp 90, RH 8",
                       "migration altered the frozen broadcast text")
    }

    func testMigrationIsIdempotentAndDoesNotDuplicate() throws {
        let defaults = fresh("idempotent")
        let history = [sampleShift(started: Date(timeIntervalSince1970: 1_779_900_000),
                                   obsCount: 2, broadcast: "spoken")]
        defaults.set(try JSONEncoder().encode(history),
                     forKey: ObservationRecordStore.LegacyKeys.history)

        _ = ObservationRecordStore(defaults: defaults, directory: tempDir)
        let second = ObservationRecordStore(defaults: defaults, directory: tempDir)
        XCTAssertEqual(second.loadHistory(), history)
        XCTAssertEqual(second.loadHistory().count, 1, "migration duplicated the record")
    }

    /// A migration must never clobber a newer file with the stale legacy blob.
    func testMigrationDoesNotOverwriteAnExistingFile() throws {
        let defaults = fresh("nooverwrite")
        let legacy = [sampleShift(started: Date(timeIntervalSince1970: 1), obsCount: 1, broadcast: "old")]
        defaults.set(try JSONEncoder().encode(legacy),
                     forKey: ObservationRecordStore.LegacyKeys.history)

        let store = ObservationRecordStore(defaults: defaults, directory: tempDir)
        let newer = [sampleShift(started: Date(timeIntervalSince1970: 2), obsCount: 4, broadcast: "new")]
        XCTAssertTrue(store.saveHistory(newer))

        // A fresh store over the same directory must read the file, not re-migrate.
        let reopened = ObservationRecordStore(defaults: defaults, directory: tempDir)
        XCTAssertEqual(reopened.loadHistory(), newer)
    }

    /// The legacy keys stay put, so a rolled-back build still finds the record.
    func testLegacyKeysAreLeftInPlace() throws {
        let defaults = fresh("legacy")
        let current = sampleShift(started: Date(timeIntervalSince1970: 1_780_000_000),
                                  obsCount: 1, broadcast: "spoken")
        defaults.set(try JSONEncoder().encode(current),
                     forKey: ObservationRecordStore.LegacyKeys.shift)
        _ = ObservationRecordStore(defaults: defaults, directory: tempDir)
        XCTAssertNotNil(defaults.data(forKey: ObservationRecordStore.LegacyKeys.shift),
                        "legacy key was deleted; a rollback would lose the record")
    }

    func testSaveAndLoadRoundTrips() {
        let store = ObservationRecordStore(defaults: fresh("roundtrip"), directory: tempDir)
        let shift = sampleShift(started: Date(timeIntervalSince1970: 1_780_000_000),
                                obsCount: 5, broadcast: "spoken")
        XCTAssertTrue(store.saveShift(shift))
        XCTAssertEqual(store.loadShift(), shift)
    }

    /// A corrupt file must not take the app down or silently look like an empty
    /// shift on a fresh launch — it reads as "no record", and the legacy blob is
    /// still there to fall back on.
    func testCorruptFileReadsAsNoRecordRatherThanCrashing() throws {
        let defaults = fresh("corrupt")
        let store = ObservationRecordStore(defaults: defaults, directory: tempDir)
        try Data("not json".utf8).write(to: tempDir.appendingPathComponent("shift.json"))
        XCTAssertNil(store.loadShift())
    }

    /// The model reads through the store, so a migrated record shows up as the
    /// live shift on construction.
    func testModelPicksUpAMigratedRecord() throws {
        let defaults = fresh("model")
        let current = sampleShift(started: Date(timeIntervalSince1970: 1_780_000_000),
                                  obsCount: 2, broadcast: "spoken")
        defaults.set(try JSONEncoder().encode(current),
                     forKey: ObservationRecordStore.LegacyKeys.shift)

        let record = ObservationRecordStore(defaults: defaults, directory: tempDir)
        let ign = IgnitionModel(store: defaults)
        let model = WeatherWatchModel(ignition: ign, store: defaults, record: record)
        XCTAssertEqual(model.shift.obs.count, 2)
        XCTAssertEqual(model.shift.obs.first?.broadcastText, "spoken")
    }

    /// Logging writes through to the file, and a new model over the same
    /// directory sees it — the persistence path end to end.
    func testLoggedObsSurvivesANewModelInstance() {
        let defaults = fresh("persist")
        let ign = IgnitionModel(store: defaults)
        let first = WeatherWatchModel(
            ignition: ign, store: defaults,
            record: ObservationRecordStore(defaults: defaults, directory: tempDir))
        first.confirmSite()
        let logged = first.logObs(at: Date(timeIntervalSince1970: 1_780_000_000))

        let second = WeatherWatchModel(
            ignition: ign, store: defaults,
            record: ObservationRecordStore(defaults: defaults, directory: tempDir))
        XCTAssertEqual(second.shift.obs.map(\.id), [logged.id])
    }
}

/// The obs-cadence reminder. Scheduling *decisions* are tested through the
/// injected `Center` — no device, no entitlement, no real notification centre.
@MainActor
final class ObsCadenceSchedulerTests: XCTestCase {

    /// Records what the scheduler asked for.
    @MainActor
    final class SpyCenter: ObsCadenceScheduler.Center {
        var granted = true
        var authorizationRequests = 0
        var removed: [[String]] = []
        var scheduled: [(id: String, title: String, body: String, delay: TimeInterval)] = []

        func requestAuthorization() async -> Bool {
            authorizationRequests += 1
            return granted
        }
        func removePending(identifiers: [String]) { removed.append(identifiers) }
        func schedule(identifier: String, title: String, body: String, after seconds: TimeInterval) {
            scheduled.append((identifier, title, body, seconds))
        }
    }

    private let noon = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - The timing rule

    func testDelayIsAFullCadenceAfterTheLastObs() {
        let delay = ObsCadenceScheduler.delayUntilNextObs(after: noon, now: noon)
        XCTAssertEqual(delay ?? 0, ObsCadenceScheduler.cadence, accuracy: 0.001)
    }

    func testDelayShrinksAsTheHourElapses() {
        let delay = ObsCadenceScheduler.delayUntilNextObs(
            after: noon, now: noon.addingTimeInterval(20 * 60))
        XCTAssertEqual(delay ?? 0, 40 * 60, accuracy: 0.001)
    }

    /// An already-due or overdue observation must not schedule a notification in
    /// the past — the screen's amber "obs overdue" strip is the right surface.
    func testOverdueObsSchedulesNothing() {
        XCTAssertNil(ObsCadenceScheduler.delayUntilNextObs(
            after: noon, now: noon.addingTimeInterval(ObsCadenceScheduler.cadence)))
        XCTAssertNil(ObsCadenceScheduler.delayUntilNextObs(
            after: noon, now: noon.addingTimeInterval(2 * ObsCadenceScheduler.cadence)))
    }

    // MARK: - Scheduling behaviour

    func testReschedulingAlwaysClearsThePendingRequestFirst() async {
        let spy = SpyCenter()
        let s = ObsCadenceScheduler(center: spy)
        await s.requestAuthorizationIfNeeded()
        s.reschedule(latestObs: noon, now: noon)
        XCTAssertEqual(spy.removed.first, [ObsCadenceScheduler.requestIdentifier])
        XCTAssertEqual(spy.scheduled.count, 1)
        XCTAssertEqual(spy.scheduled.first?.id, ObsCadenceScheduler.requestIdentifier)
    }

    /// A deleted last observation must clear the reminder rather than leave it
    /// pointing at a reading that no longer exists.
    func testEmptyShiftClearsWithoutScheduling() async {
        let spy = SpyCenter()
        let s = ObsCadenceScheduler(center: spy)
        await s.requestAuthorizationIfNeeded()
        s.reschedule(latestObs: nil, now: noon)
        XCTAssertEqual(spy.removed.count, 1)
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    func testNothingIsScheduledWithoutAuthorization() {
        let spy = SpyCenter()
        let s = ObsCadenceScheduler(center: spy)
        s.reschedule(latestObs: noon, now: noon)   // never authorized
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    func testAuthorizationIsAskedOnlyOnce() async {
        let spy = SpyCenter()
        let s = ObsCadenceScheduler(center: spy)
        await s.requestAuthorizationIfNeeded()
        await s.requestAuthorizationIfNeeded()
        await s.requestAuthorizationIfNeeded()
        XCTAssertEqual(spy.authorizationRequests, 1)
    }

    func testDeniedAuthorizationSchedulesNothing() async {
        let spy = SpyCenter()
        spy.granted = false
        let s = ObsCadenceScheduler(center: spy)
        await s.requestAuthorizationIfNeeded()
        s.reschedule(latestObs: noon, now: noon)
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    /// The reminder is advisory: it must never carry a computed value. A PIG on a
    /// lock screen is a number stripped of the disclaimer, the freshness strip,
    /// and the band-edge marker that keep it honest on the screen.
    func testReminderTextQuotesNoComputedValue() async {
        let spy = SpyCenter()
        let s = ObsCadenceScheduler(center: spy)
        await s.requestAuthorizationIfNeeded()
        s.reschedule(latestObs: noon, now: noon)
        let text = (spy.scheduled.first?.title ?? "") + " " + (spy.scheduled.first?.body ?? "")
        for forbidden in ["PIG", "FFM", "%", "probability", "ignition"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden),
                           "reminder text leaked a computed value: '\(forbidden)' in \(text)")
        }
    }

    func testCancelRemovesThePendingRequest() {
        let spy = SpyCenter()
        ObsCadenceScheduler(center: spy).cancel()
        XCTAssertEqual(spy.removed, [[ObsCadenceScheduler.requestIdentifier]])
    }
}
