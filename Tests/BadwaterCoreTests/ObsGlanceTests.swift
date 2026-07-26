import XCTest
@testable import BadwaterCore

/// The rule persistent glanceable surfaces enforce: when to stop showing a
/// number. Tested here, on Linux CI, rather than inside a widget extension
/// nothing exercises.
final class ObsGlanceTests: XCTestCase {

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

    // MARK: - What to show

    func testNoObservationYet() {
        XCTAssertEqual(ObsGlance.at(observedAt, latest: nil, cadence: cadence), .none)
    }

    func testFreshObservationIsReadable() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(600),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .reading(let r) = g else { return XCTFail("expected .reading, got \(g)") }
        XCTAssertEqual(r.observedAt, observedAt)
        XCTAssertEqual(r.ageSeconds, 600, accuracy: 0.001)
        XCTAssertGreaterThan(r.pigUnshaded, 0)
        XCTAssertGreaterThan(r.pigShaded, 0)
    }

    /// The reading carries the values the surface renders, taken from the frozen
    /// observation rather than recomputed.
    func testReadingMirrorsTheFrozenObservation() {
        let o = obs(at: observedAt)
        let g = ObsGlance.at(observedAt, latest: o, cadence: cadence)
        guard case .reading(let r) = g else { return XCTFail("expected .reading") }
        XCTAssertEqual(r.pigUnshaded, o.estimate.unshaded.probabilityOfIgnition)
        XCTAssertEqual(r.pigShaded, o.estimate.shaded.probabilityOfIgnition)
        XCTAssertEqual(r.behavior, o.estimate.unshaded.interpretation)
    }

    /// The moment the next obs is due, the displayed one is superseded and the
    /// glance stops showing a number.
    func testAtExactlyOneCadenceItBecomesOverdue() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(cadence),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .overdue(let o) = g else { return XCTFail("expected .overdue, got \(g)") }
        XCTAssertEqual(o.observedAt, observedAt)
        XCTAssertEqual(o.overdueBySeconds, 0, accuracy: 0.001)
    }

    /// One second before the cadence it is still readable — the boundary is
    /// closed on the overdue side, matching "the next obs is now due".
    func testJustBeforeTheCadenceItIsStillReadable() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(cadence - 1),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .reading = g else { return XCTFail("expected .reading, got \(g)") }
    }

    func testWellPastCadenceReportsHowOverdue() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(cadence + 2400),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .overdue(let o) = g else { return XCTFail("expected .overdue") }
        XCTAssertEqual(o.overdueBySeconds, 2400, accuracy: 0.001)
    }

    /// A back-filled or clock-skewed observation timestamped ahead of `now` must
    /// not read as "aged negative seconds".
    func testFutureObservationClampsAgeToZero() {
        let g = ObsGlance.at(observedAt,
                             latest: obs(at: observedAt.addingTimeInterval(300)),
                             cadence: cadence)
        guard case .reading(let r) = g else { return XCTFail("expected .reading") }
        XCTAssertEqual(r.ageSeconds, 0, accuracy: 0.001)
    }

    // MARK: - When the surface next changes

    /// The widget timeline's second entry: exactly when the glance flips.
    func testNextTransitionIsTheDueMoment() {
        let t = ObsGlance.nextTransition(after: observedAt,
                                         latest: obs(at: observedAt), cadence: cadence)
        XCTAssertEqual(t, observedAt.addingTimeInterval(cadence))
    }

    func testNoTransitionOnceAlreadyOverdue() {
        XCTAssertNil(ObsGlance.nextTransition(after: observedAt.addingTimeInterval(cadence + 60),
                                              latest: obs(at: observedAt), cadence: cadence))
    }

    func testNoTransitionWithoutAnObservation() {
        XCTAssertNil(ObsGlance.nextTransition(after: observedAt, latest: nil, cadence: cadence))
    }

    /// The transition is the moment the glance actually changes — scheduling an
    /// entry there must land on `.overdue`, not one second short of it.
    func testTheTransitionMomentItselfRendersAsOverdue() {
        let o = obs(at: observedAt)
        guard let t = ObsGlance.nextTransition(after: observedAt, latest: o, cadence: cadence) else {
            return XCTFail("expected a transition")
        }
        guard case .overdue = ObsGlance.at(t, latest: o, cadence: cadence) else {
            return XCTFail("timeline entry at the transition did not render as overdue")
        }
    }

    // MARK: - Cadence

    /// The threshold is the observation cadence itself, not a separately tuned
    /// constant — a superseded observation is exactly one the next was due to
    /// replace. A caller passing a different cadence gets a correspondingly
    /// different boundary.
    func testThresholdFollowsWhateverCadenceIsPassed() {
        let half: TimeInterval = 1800
        let o = obs(at: observedAt)
        guard case .overdue = ObsGlance.at(observedAt.addingTimeInterval(half),
                                           latest: o, cadence: half) else {
            return XCTFail("expected .overdue at the shorter cadence")
        }
        guard case .reading = ObsGlance.at(observedAt.addingTimeInterval(half),
                                           latest: o, cadence: cadence) else {
            return XCTFail("expected .reading at the standard cadence")
        }
    }

    func testStandardCadenceIsOneHour() {
        XCTAssertEqual(ObsGlance.standardCadence, 3600)
    }
}
