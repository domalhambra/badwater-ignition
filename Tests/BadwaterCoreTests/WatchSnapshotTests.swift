import XCTest
@testable import BadwaterCore

/// The payload the phone sends the watch, and — more importantly — the rule that
/// a snapshot is re-judged against the *watch's* clock rather than trusted as
/// sent. `WCSession.updateApplicationContext` delivers opportunistically, so a
/// snapshot can arrive long after it was made.
final class WatchSnapshotTests: XCTestCase {

    private let cadence: TimeInterval = 3600
    private let observedAt = Date(timeIntervalSince1970: 1_780_000_000)

    private func obs(at date: Date) -> WeatherObs {
        let input = IgnitionInput(dryBulbF: 90, relativeHumidity: 8, month: 7,
                                  timeOfDay: .band1400_1559, aspect: .south,
                                  slope: .gentle, elevationDelta: .level)
        return WeatherObs(timestamp: date,
                          estimate: IgnitionCalculator.estimate(input),
                          rhSource: .direct)
    }

    // MARK: - Projection

    func testNothingToMirrorWhenTheShiftIsEmpty() {
        XCTAssertNil(WatchSnapshot.from(latest: nil, cadence: cadence, siteLabel: "Division W"))
    }

    func testProjectsTheFrozenObservation() {
        let o = obs(at: observedAt)
        guard let s = WatchSnapshot.from(latest: o, cadence: cadence, siteLabel: "Division W") else {
            return XCTFail("expected a snapshot")
        }
        XCTAssertEqual(s.pigUnshaded, o.estimate.unshaded.probabilityOfIgnition)
        XCTAssertEqual(s.pigShaded, o.estimate.shaded.probabilityOfIgnition)
        XCTAssertEqual(s.behavior, o.estimate.unshaded.interpretation)
        XCTAssertEqual(s.observedAt, observedAt)
        XCTAssertEqual(s.siteLabel, "Division W")
    }

    /// The watch needs the due moment to render a countdown without knowing the
    /// cadence the phone used.
    func testDueAtIsOneCadenceAfterTheObservation() {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: cadence, siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        XCTAssertEqual(s.dueAt, observedAt.addingTimeInterval(cadence))
    }

    func testSiteLabelIsOptional() {
        let s = WatchSnapshot.from(latest: obs(at: observedAt), cadence: cadence, siteLabel: nil)
        XCTAssertNil(s?.siteLabel)
    }

    // MARK: - Wire format

    func testCodableRoundTrip() throws {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: cadence, siteLabel: "Division W") else {
            return XCTFail("expected a snapshot")
        }
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WatchSnapshot.self, from: data), s)
    }

    /// `FireBehavior` travels as its raw value so an older watch build decoding a
    /// newer band degrades to a legible value instead of failing the whole
    /// decode and leaving the face blank.
    func testUnknownBehaviorRawValueDegradesRatherThanFailing() throws {
        let json = """
        {"pigUnshaded":100,"pigShaded":70,"behaviorRawValue":99,
         "observedAt":0,"dueAt":3600}
        """
        let s = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.behavior, .veryLow)
        XCTAssertEqual(s.pigUnshaded, 100)
    }

    // MARK: - The application-context wire

    /// The sender is in the iOS app target and the receiver in the watch target;
    /// neither can see the other. This round trip is the only thing standing
    /// between them and a silent disagreement about the wire format.
    func testApplicationContextRoundTrip() throws {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: cadence, siteLabel: "Division W") else {
            return XCTFail("expected a snapshot")
        }
        let context = try s.applicationContext()
        XCTAssertEqual(WatchSnapshot.from(applicationContext: context), s)
    }

    /// An empty context is how the phone says "the shift ended, or its last
    /// observation was deleted". The watch must clear, not keep showing a
    /// reading the phone no longer has.
    func testEmptyApplicationContextDecodesToNothing() {
        XCTAssertNil(WatchSnapshot.from(applicationContext: [:]))
    }

    func testMalformedApplicationContextDecodesToNothing() {
        XCTAssertNil(WatchSnapshot.from(
            applicationContext: [WatchSnapshot.applicationContextKey: Data("not json".utf8)]))
        XCTAssertNil(WatchSnapshot.from(
            applicationContext: [WatchSnapshot.applicationContextKey: "not even data"]))
    }

    // MARK: - The watch re-judges by its own clock

    func testFreshSnapshotRendersAsAReading() {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: cadence, siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        guard case .reading(let r) = s.glance(at: observedAt.addingTimeInterval(600)) else {
            return XCTFail("expected .reading")
        }
        XCTAssertEqual(r.ageSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(r.pigUnshaded, s.pigUnshaded)
        XCTAssertEqual(r.behavior, s.behavior)
    }

    /// The important one. Application context is delivered opportunistically, so
    /// the watch may receive this snapshot an hour after the phone made it. It
    /// must never present a late delivery as fresh.
    func testLateDeliveredSnapshotRendersAsOverdueNotFresh() {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: cadence, siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        guard case .overdue(let o) = s.glance(at: observedAt.addingTimeInterval(cadence + 2400)) else {
            return XCTFail("a snapshot delivered late presented as fresh")
        }
        XCTAssertEqual(o.observedAt, observedAt)
        XCTAssertEqual(o.overdueBySeconds, 2400, accuracy: 0.001)
    }

    /// The watch applies the *same* boundary as the widget, so the two surfaces
    /// can never disagree about whether a number is still showable.
    func testFlipsAtExactlyTheDueMoment() {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: cadence, siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        guard case .reading = s.glance(at: s.dueAt.addingTimeInterval(-1)) else {
            return XCTFail("expected .reading one second before due")
        }
        guard case .overdue = s.glance(at: s.dueAt) else {
            return XCTFail("expected .overdue at the due moment")
        }
    }

    /// A snapshot re-judged on the watch agrees with `ObsGlance` applied to the
    /// observation it came from — the projection loses nothing the rule needs.
    func testGlanceMatchesObsGlanceOnTheSourceObservation() {
        let o = obs(at: observedAt)
        guard let s = WatchSnapshot.from(latest: o, cadence: cadence, siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        for offset in [0.0, 600, cadence - 1, cadence, cadence + 2400] {
            let now = observedAt.addingTimeInterval(offset)
            XCTAssertEqual(s.glance(at: now),
                           ObsGlance.at(now, latest: o, cadence: cadence),
                           "disagreed \(offset)s after the observation")
        }
    }

    /// The snapshot is self-describing: the boundary comes from the `dueAt` the
    /// phone stamped, not from a cadence constant compiled into the watch. A
    /// watch build whose idea of the cadence had drifted would otherwise show a
    /// superseded number — the exact disagreement `RecordLocation` and
    /// `ObsGlance.standardCadence` exist to make impossible.
    func testBoundaryFollowsTheSendersDueMomentNotTheReceiversCadence() {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt),
                                         cadence: 1800, siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        // Half an hour on: past the phone's 30-minute cadence, but well inside
        // the hour a watch holding `standardCadence` would have assumed.
        guard case .overdue = s.glance(at: observedAt.addingTimeInterval(1800)) else {
            return XCTFail("the watch ignored the phone's due moment")
        }
    }

    /// A malformed snapshot — `dueAt` before `observedAt` — reads as immediately
    /// overdue rather than showing a number. The safe direction.
    func testDueBeforeObservedReadsAsOverdue() {
        let s = WatchSnapshot(pigUnshaded: 100, pigShaded: 70,
                              behaviorRawValue: FireBehavior.extreme.rawValue,
                              observedAt: observedAt,
                              dueAt: observedAt.addingTimeInterval(-60),
                              siteLabel: nil)
        guard case .overdue = s.glance(at: observedAt) else {
            return XCTFail("expected .overdue")
        }
    }

    func testDefaultCadenceIsTheStandardOne() {
        guard let s = WatchSnapshot.from(latest: obs(at: observedAt), siteLabel: nil) else {
            return XCTFail("expected a snapshot")
        }
        XCTAssertEqual(s.dueAt, observedAt.addingTimeInterval(ObsGlance.standardCadence))
    }
}
