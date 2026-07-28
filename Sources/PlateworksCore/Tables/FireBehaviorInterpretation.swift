import Foundation

/// Plain-language fire-behavior interpretation of a Probability of Ignition
/// value, from the IRPG **Fine Fuel Moisture and Fire Behavior** table
/// (PMS 461, p. 49).
///
/// The printed table always carries the caution: *"Use these thresholds with
/// caution; consult local experts."* — surfaced as ``FireBehaviorInterpretation/caution``.
public enum FireBehavior: Int, CaseIterable, Sendable, Codable, Identifiable {
    case veryLow = 0
    case low = 1
    case medium = 2
    case high = 3
    case veryHigh = 4
    case extreme = 5

    public var id: Int { rawValue }

    /// Short label for compact display.
    public var title: String {
        switch self {
        case .veryLow: return "Very Low"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .veryHigh: return "Very High"
        case .extreme: return "Extreme"
        }
    }

    /// The full interpretation text as printed in the IRPG.
    public var detail: String {
        switch self {
        case .veryLow:
            return "Very low ignition, some spotting may occur with wind"
        case .low:
            return "Low ignition, campfires can be hazardous"
        case .medium:
            return "Medium ignition, matches hazardous, easy burning"
        case .high:
            return "High ignition, matches dangerous, spotting possible with wind, medium burning conditions"
        case .veryHigh:
            return "Very high ignition, rapid buildup, extensive spotting and crowning, and loss of control"
        case .extreme:
            return "Extreme ignition and initial spread, frequent spots, critical fire conditions"
        }
    }

    /// The PIG range label as printed in the IRPG.
    public var pigRangeLabel: String {
        switch self {
        case .veryLow: return "<10%"
        case .low: return "10 to 20%"
        case .medium: return "20 to 30%"
        case .high: return "30 to 50%"
        case .veryHigh: return "50 to 70%"
        case .extreme: return "80 to 100%"
        }
    }

    /// The reference relative-humidity range from the same table row.
    public var humidityRangeLabel: String {
        switch self {
        case .veryLow: return ">60%"
        case .low: return "45 to 60%"
        case .medium: return "30 to 45%"
        case .high: return "26 to 40%"
        case .veryHigh: return "15 to 30%"
        case .extreme: return "<15%"
        }
    }

    /// Severity ordinal 0–5, for the design-system color ramp.
    public var severity: Int { rawValue }
}

public enum FireBehaviorInterpretation {

    /// Caution note printed beneath the interpretation table in the IRPG.
    public static let caution = "Use these thresholds with caution; consult local experts."

    /// Interpret a Probability of Ignition percentage.
    ///
    /// Computed PIG values are always multiples of 10, so band boundaries are
    /// unambiguous. The printed table shows a gap between the "50 to 70%" and
    /// "80 to 100%" rows; here "Very high" is extended to cover < 80% so that a
    /// PIG of exactly 70 maps to "Very high" and 80 maps to "Extreme".
    public static func interpretation(forPIG pig: Int) -> FireBehavior {
        switch pig {
        case ..<10: return .veryLow
        case 10..<20: return .low
        case 20..<30: return .medium
        case 30..<50: return .high
        case 50..<80: return .veryHigh
        default: return .extreme
        }
    }
}
