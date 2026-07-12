import Foundation

/// A metric a crew can set a briefed trigger point on. Each maps to a value the
/// app already computes for an observation.
public enum TriggerMetric: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case temperature
    case relativeHumidity
    case fineFuelMoistureUnshaded
    case fineFuelMoistureShaded
    case probabilityOfIgnitionUnshaded
    case probabilityOfIgnitionShaded
    case dewPoint

    public var id: String { rawValue }

    /// Short label for compact rows and chips.
    public var shortLabel: String {
        switch self {
        case .temperature: return "Temp"
        case .relativeHumidity: return "RH"
        case .fineFuelMoistureUnshaded: return "FFM (unshaded)"
        case .fineFuelMoistureShaded: return "FFM (shaded)"
        case .probabilityOfIgnitionUnshaded: return "PIG (unshaded)"
        case .probabilityOfIgnitionShaded: return "PIG (shaded)"
        case .dewPoint: return "Dew point"
        }
    }

    /// Unit suffix used in printed rules.
    public var unit: String {
        switch self {
        case .temperature, .dewPoint: return "°F"
        default: return "%"
        }
    }

    /// The direction most briefings use for this metric — a sensible pre-highlight
    /// the crew still confirms. The app never originates the threshold value.
    public var defaultDirection: TriggerDirection {
        switch self {
        case .temperature, .probabilityOfIgnitionUnshaded, .probabilityOfIgnitionShaded:
            return .risesToAtOrAbove
        case .relativeHumidity, .fineFuelMoistureUnshaded, .fineFuelMoistureShaded, .dewPoint:
            return .fallsToAtOrBelow
        }
    }
}

/// Which way a metric has to move to meet a trigger. Both comparisons are
/// **inclusive** at the threshold — a safety tool must not miss the boundary
/// reading.
public enum TriggerDirection: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    /// Met when the value is at or below the threshold.
    case fallsToAtOrBelow
    /// Met when the value is at or above the threshold.
    case risesToAtOrAbove

    public var id: String { rawValue }

    /// The comparator glyph for printed rules (`≤` / `≥`).
    public var comparatorLabel: String {
        self == .fallsToAtOrBelow ? "≤" : "≥"
    }

    /// Inclusive, spoken-cadence phrasing so the read-aloud rule matches the
    /// briefed rule at the boundary (never "under/over").
    public func phrase(_ value: Int) -> String {
        switch self {
        case .fallsToAtOrBelow: return "\(value) or less"
        case .risesToAtOrAbove: return "\(value) or more"
        }
    }

    /// Whether a reading meets this direction at the given threshold (inclusive).
    public func isSatisfied(value: Int, threshold: Int) -> Bool {
        switch self {
        case .fallsToAtOrBelow: return value <= threshold
        case .risesToAtOrAbove: return value >= threshold
        }
    }
}

/// A trigger point the crew wrote down at briefing. Weather Watch flags when a
/// logged observation crosses one; it never suggests a value, warns, or makes
/// the call.
public struct BriefedTrigger: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var metric: TriggerMetric
    public var direction: TriggerDirection
    /// The briefed threshold, or `nil` until the crew enters the number they were
    /// briefed. The app never originates this value.
    public var value: Int?
    /// An optional short note the crew attaches, shown verbatim.
    public var label: String?
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        metric: TriggerMetric,
        direction: TriggerDirection,
        value: Int? = nil,
        label: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.metric = metric
        self.direction = direction
        self.value = value
        self.label = label
        self.enabled = enabled
    }

    /// `true` once the crew has entered a threshold and the trigger is enabled.
    public var isArmed: Bool { enabled && value != nil }

    /// Printed rule, e.g. `"RH ≤ 20%"` or `"PIG (unshaded) ≥ 80%"`. Shows a blank
    /// placeholder until the crew enters the briefed number.
    public var ruleText: String {
        let v = value.map(String.init) ?? "— —"
        return "\(metric.shortLabel) \(direction.comparatorLabel) \(v)\(metric.unit)"
    }

    /// Inclusive spoken rule, e.g. `"RH 20 or less"`, for the radio/export line.
    public var spokenRule: String {
        guard let value else { return "\(metric.shortLabel) not set" }
        return "\(metric.shortLabel) \(direction.phrase(value))"
    }
}
