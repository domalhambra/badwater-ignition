import Foundation

/// A GPS coordinate attached to an observation, rendered the way the IMET sheet's
/// Location column expects: `"38.21437, -112.3978"` (five decimal places ≈ 1 m,
/// trailing zeros trimmed).
public struct GeoPoint: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// `"lat, long"`, e.g. `"38.21437, -112.3978"`.
    public var rendered: String { "\(Self.trim(latitude)), \(Self.trim(longitude))" }

    /// Format to 5 dp and trim trailing zeros. `String(format:)` with no `Locale`
    /// uses the C locale, so a comma-decimal device can never emit `"38,21437"`.
    static func trim(_ value: Double) -> String {
        var s = String(format: "%.5f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }
}
