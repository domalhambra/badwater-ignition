import Foundation

/// Display/input temperature unit.
///
/// Badwater Ignition keeps **°F canonical** internally because the IRPG and
/// PMS 437 tables are all Fahrenheit-banded; Celsius is offered as an
/// input/display convenience and converted to whole °F for every table lookup.
public enum TemperatureUnit: String, CaseIterable, Sendable, Codable, Identifiable {
    case fahrenheit = "°F"
    case celsius = "°C"

    public var id: String { rawValue }
    public var symbol: String { rawValue }

    public var displayName: String {
        self == .fahrenheit ? "Fahrenheit" : "Celsius"
    }

    /// Convert an absolute temperature expressed in this unit to whole °F.
    public func toFahrenheit(_ value: Int) -> Int {
        switch self {
        case .fahrenheit: return value
        case .celsius: return Int((Double(value) * 9.0 / 5.0 + 32.0).rounded())
        }
    }

    /// Convert an absolute °F temperature to whole degrees in this unit.
    public func fromFahrenheit(_ fahrenheit: Int) -> Int {
        switch self {
        case .fahrenheit: return fahrenheit
        case .celsius: return Int(((Double(fahrenheit) - 32.0) * 5.0 / 9.0).rounded())
        }
    }

    /// Convert a temperature *difference* (e.g. wet-bulb depression) from °F to
    /// this unit. Differences scale by 5/9 with no 32° offset.
    public func differenceFromFahrenheit(_ deltaF: Int) -> Int {
        switch self {
        case .fahrenheit: return deltaF
        case .celsius: return Int((Double(deltaF) * 5.0 / 9.0).rounded())
        }
    }
}
