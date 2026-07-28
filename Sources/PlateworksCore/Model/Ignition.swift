import Foundation

/// A complete set of inputs for a Fine Fuel Moisture / Probability of Ignition
/// estimate.
///
/// Temperature and humidity change hourly; the site factors (aspect, slope,
/// elevation delta) tend to persist while a crew works the same piece of line,
/// and month / time-of-day pre-fill from the clock in the app.
public struct IgnitionInput: Sendable, Equatable, Codable {
    /// Dry-bulb temperature in °F.
    public var dryBulbF: Int
    /// Relative humidity, 0–100%.
    public var relativeHumidity: Int
    /// Calendar month, 1 (January) … 12 (December).
    public var month: Int
    /// Time-of-day band, or ``TimeOfDay/night``.
    public var timeOfDay: TimeOfDay
    /// Slope aspect.
    public var aspect: Aspect
    /// Slope steepness class.
    public var slope: Slope
    /// Elevation of the fire relative to the weather site.
    public var elevationDelta: ElevationDelta

    public init(
        dryBulbF: Int,
        relativeHumidity: Int,
        month: Int,
        timeOfDay: TimeOfDay,
        aspect: Aspect,
        slope: Slope,
        elevationDelta: ElevationDelta
    ) {
        self.dryBulbF = dryBulbF
        self.relativeHumidity = relativeHumidity
        self.month = month
        self.timeOfDay = timeOfDay
        self.aspect = aspect
        self.slope = slope
        self.elevationDelta = elevationDelta
    }

    /// The correction table selected by ``month``.
    public var monthGroup: MonthGroup { MonthGroup.from(month: month) }
}

/// The estimate for one shading condition (unshaded or shaded).
public struct ShadingEstimate: Sendable, Equatable, Codable, Identifiable {
    public let shading: Shading
    /// The 1-hr fuel-moisture correction added to the reference value, or `nil`
    /// at night (where the "+5" rule replaces the correction table).
    public let correction: Int?
    /// Fine Fuel Moisture: reference fuel moisture + correction (or + 5 at night).
    public let fineFuelMoisture: Int
    /// Probability of Ignition (%).
    public let probabilityOfIgnition: Int

    public var id: String { shading.rawValue }

    /// Plain-language fire-behavior interpretation of the PIG value.
    public var interpretation: FireBehavior {
        FireBehaviorInterpretation.interpretation(forPIG: probabilityOfIgnition)
    }
}

/// The full result of an ignition estimate: the shared reference fuel moisture
/// plus both the unshaded and shaded outcomes.
public struct IgnitionEstimate: Sendable, Equatable, Codable {
    public let input: IgnitionInput
    /// Reference fuel moisture from Table A (before correction).
    public let referenceFuelMoisture: Int
    /// `true` when the nighttime "+5" rule was applied.
    public let isNight: Bool
    public let unshaded: ShadingEstimate
    public let shaded: ShadingEstimate

    /// The estimate for a specific shading condition.
    public func estimate(for shading: Shading) -> ShadingEstimate {
        shading == .shaded ? shaded : unshaded
    }
}
