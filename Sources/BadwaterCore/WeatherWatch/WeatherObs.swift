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

    // Observed metadata for the IMET export (not computed by the app). All
    // optional — pre-feature persisted observations decode unchanged.
    /// Observed wind (IMET column E). `nil` = not recorded.
    public var wind: Wind?
    /// Absolute site elevation in feet (IMET column H). This is NOT the
    /// `elevationDelta` used for RH — it's the observation site's real elevation.
    public var elevationFeet: Int?
    /// GPS location of the observation (IMET column J).
    public var location: GeoPoint?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        estimate: IgnitionEstimate,
        humidity: HumidityResult? = nil,
        rhSource: RHSource,
        crossedTriggerIDs: [UUID] = [],
        note: String? = nil,
        wind: Wind? = nil,
        elevationFeet: Int? = nil,
        location: GeoPoint? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.estimate = estimate
        self.humidity = humidity
        self.rhSource = rhSource
        self.crossedTriggerIDs = crossedTriggerIDs
        self.note = note
        self.wind = wind
        self.elevationFeet = elevationFeet
        self.location = location
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
    /// Division / branch label for the IMET export title & tab (e.g. `"Division W"`).
    public var division: String?
    /// Location / road name for the IMET export title (e.g. `"659 Road"`).
    public var locationName: String?

    public init(
        id: UUID = UUID(),
        started: Date,
        obs: [WeatherObs] = [],
        division: String? = nil,
        locationName: String? = nil
    ) {
        self.id = id
        self.started = started
        self.obs = obs
        self.division = division
        self.locationName = locationName
    }

    /// The most recent observation *by timestamp* — not merely the last appended.
    /// A back-filled obs (e.g. a forgotten 0900 logged after the 1000) must never
    /// masquerade as "current" on the dashboard, so this is the chronological max.
    public var latest: WeatherObs? { obs.max { $0.timestamp < $1.timestamp } }

    /// `(timestamp, value)` points for a metric across the shift, in **chronological
    /// order** (a back-filled obs can't kink the trend line). A `nil` value marks
    /// an obs where the metric wasn't computed.
    public func series(of metric: TriggerMetric) -> [(date: Date, value: Int?)] {
        obs.sorted { $0.timestamp < $1.timestamp }
            .map { (date: $0.timestamp, value: $0.value(of: metric)) }
    }
}
