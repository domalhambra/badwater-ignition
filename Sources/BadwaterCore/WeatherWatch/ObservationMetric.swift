import Foundation

/// A per-observation metric the app already computes — the axis a shift **trend**
/// can be plotted on, and the value ``WeatherObs/value(of:)`` extracts.
///
/// Each case maps to a value derived from a logged observation's estimate (or its
/// ``HumidityResult`` for dew point, which is only present when the obs was slung).
public enum ObservationMetric: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case temperature
    case relativeHumidity
    case fineFuelMoistureUnshaded
    case fineFuelMoistureShaded
    case probabilityOfIgnitionUnshaded
    case probabilityOfIgnitionShaded
    case dewPoint

    public var id: String { rawValue }

    /// Short label for compact rows, chips, and trend axes.
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

    /// Unit suffix used when the value is shown.
    public var unit: String {
        switch self {
        case .temperature, .dewPoint: return "°F"
        default: return "%"
        }
    }
}
