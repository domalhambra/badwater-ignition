import Foundation

/// The whole of what the phone tells the watch.
///
/// Small on purpose. The watch mirrors the *latest* reading and when the next
/// one is due; it has no use for history, and `WCSession.updateApplicationContext`
/// is far more reliable with a small dictionary. Being a value type in the core
/// means its encoding is golden-tested on Linux CI like everything else here,
/// rather than inside a watch target nothing exercises.
///
/// ### It carries no live estimate
/// A watch face is the most persistent glanceable surface there is, so the
/// display policy applies at full strength: only a **frozen, logged**
/// observation, always with its time and age, and the number stops being shown
/// once it is superseded. See ``ObsGlance`` and `docs/PLAN_WIDGET_AND_WATCH.md`.
///
/// ### It carries its own due moment
/// ``dueAt`` is stamped by the phone rather than recomputed on the watch. The
/// watch therefore cannot disagree with the phone about when a reading expires
/// — the same reason ``ObsGlance/standardCadence`` and `RecordLocation` exist.
/// A snapshot is self-describing; ``glance(at:)`` needs no cadence argument and
/// so has no way to be handed the wrong one.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public let pigUnshaded: Int
    public let pigShaded: Int
    /// ``FireBehavior`` travels as its raw value so a watch build that predates a
    /// new band degrades to a legible reading instead of failing the whole decode
    /// and leaving the face blank.
    public let behaviorRawValue: Int
    public let observedAt: Date
    /// When the next observation is due — the moment this reading is superseded.
    public let dueAt: Date
    /// Division / location, for context on the watch screen. `nil` when the
    /// shift has no label yet.
    public let siteLabel: String?

    public init(pigUnshaded: Int, pigShaded: Int, behaviorRawValue: Int,
                observedAt: Date, dueAt: Date, siteLabel: String?) {
        self.pigUnshaded = pigUnshaded
        self.pigShaded = pigShaded
        self.behaviorRawValue = behaviorRawValue
        self.observedAt = observedAt
        self.dueAt = dueAt
        self.siteLabel = siteLabel
    }

    /// The fire-behavior band of the unshaded value — the more hazardous one,
    /// matching how the app's own results lead.
    ///
    /// An unrecognized raw value falls back to ``FireBehavior/veryLow`` rather
    /// than trapping: the band only tints the reading, and losing the tint is a
    /// far better failure on a wrist than losing the screen.
    public var behavior: FireBehavior { FireBehavior(rawValue: behaviorRawValue) ?? .veryLow }

    /// Project the latest observation into a snapshot, or `nil` when there is
    /// nothing to mirror.
    public static func from(latest: WeatherObs?,
                            cadence: TimeInterval = ObsGlance.standardCadence,
                            siteLabel: String?) -> WatchSnapshot? {
        guard let latest else { return nil }
        return WatchSnapshot(
            pigUnshaded: latest.estimate.unshaded.probabilityOfIgnition,
            pigShaded: latest.estimate.shaded.probabilityOfIgnition,
            behaviorRawValue: latest.estimate.unshaded.interpretation.rawValue,
            observedAt: latest.timestamp,
            dueAt: latest.timestamp.addingTimeInterval(cadence),
            siteLabel: siteLabel)
    }

    /// Re-derive the glance **on the watch, against the watch's own clock**.
    ///
    /// This is the point of the type. `updateApplicationContext` delivers
    /// opportunistically, so a snapshot can arrive long after the phone made it
    /// — and the watch may then keep rendering it for hours while out of range.
    /// Nothing about "is this still showable" may be trusted from the sender;
    /// it is decided here, every time the face draws, by the same rule the
    /// widget applies.
    ///
    /// A malformed snapshot whose ``dueAt`` precedes its ``observedAt`` reads as
    /// immediately overdue — the safe direction.
    public func glance(at now: Date) -> ObsGlance {
        if now >= dueAt {
            return .overdue(ObsGlance.Overdue(observedAt: observedAt,
                                              overdueBySeconds: now.timeIntervalSince(dueAt)))
        }
        return .reading(ObsGlance.Reading(
            pigUnshaded: pigUnshaded,
            pigShaded: pigShaded,
            behavior: behavior,
            observedAt: observedAt,
            // Same floor as ObsGlance: a back-filled observation, or one taken
            // across a clock adjustment, can be stamped ahead of `now`.
            ageSeconds: max(0, now.timeIntervalSince(observedAt))))
    }
}
