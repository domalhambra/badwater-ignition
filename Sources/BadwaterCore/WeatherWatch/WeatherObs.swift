import Foundation

/// A single weather observation, frozen at log time.
///
/// It keeps the **full computed** ``IgnitionEstimate`` (and the ``HumidityResult``
/// when the obs was slung) rather than just the inputs, so the record is
/// re-derivable line-for-line against the printed IRPG — and so a later change to
/// the live Ignition screen can never retro-alter a logged reading. `estimate`
/// already embeds its ``IgnitionInput``, so no inputs are stored twice.
public struct WeatherObs: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let estimate: IgnitionEstimate
    /// Present only when the obs was slung from a wet bulb (dew point etc.).
    public let humidity: HumidityResult?
    /// How the humidity was measured (Kestrel vs. sling).
    public let rhSource: RHSource
    /// The briefed triggers this observation met, frozen at log time so the
    /// record stays re-evaluation-proof if triggers change later.
    public let crossedTriggerIDs: [UUID]
    public var note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        estimate: IgnitionEstimate,
        humidity: HumidityResult? = nil,
        rhSource: RHSource,
        crossedTriggerIDs: [UUID] = [],
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.estimate = estimate
        self.humidity = humidity
        self.rhSource = rhSource
        self.crossedTriggerIDs = crossedTriggerIDs
        self.note = note
    }

    /// The value of a metric for this observation, or `nil` when it isn't
    /// computed here (e.g. dew point on a Kestrel obs that wasn't slung).
    public func value(of metric: TriggerMetric) -> Int? {
        switch metric {
        case .temperature: return estimate.input.dryBulbF
        case .relativeHumidity: return estimate.input.relativeHumidity
        case .fineFuelMoistureUnshaded: return estimate.unshaded.fineFuelMoisture
        case .fineFuelMoistureShaded: return estimate.shaded.fineFuelMoisture
        case .probabilityOfIgnitionUnshaded: return estimate.unshaded.probabilityOfIgnition
        case .probabilityOfIgnitionShaded: return estimate.shaded.probabilityOfIgnition
        case .dewPoint: return humidity?.dewPointF
        }
    }

    /// The radio-ready broadcast line, e.g.
    /// `"Wx obs 1430, temp 90, RH 8, PIG 100 unshaded, 70 shaded"`.
    ///
    /// The time is supplied by the caller so the core stays clock- and
    /// timezone-agnostic; the app formats ``timestamp`` as `"HHmm"`.
    public func radioLine(timeLabel: String) -> String {
        "Wx obs \(timeLabel), temp \(estimate.input.dryBulbF), "
            + "RH \(estimate.input.relativeHumidity), "
            + "PIG \(estimate.unshaded.probabilityOfIgnition) unshaded, "
            + "\(estimate.shaded.probabilityOfIgnition) shaded"
    }
}

/// One shift's worth of observations. A shift is just an ordered list of obs
/// with a start time; the app decides when a new one begins (never a hard
/// midnight split, which would cut a night crew in half).
public struct Shift: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var started: Date
    public var obs: [WeatherObs]

    public init(id: UUID = UUID(), started: Date, obs: [WeatherObs] = []) {
        self.id = id
        self.started = started
        self.obs = obs
    }

    /// The most recent observation.
    public var latest: WeatherObs? { obs.last }

    /// `(timestamp, value)` points for a metric across the shift, in log order.
    /// A `nil` value marks an obs where the metric wasn't computed.
    public func series(of metric: TriggerMetric) -> [(date: Date, value: Int?)] {
        obs.map { (date: $0.timestamp, value: $0.value(of: metric)) }
    }
}
