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

    /// Valid ranges for a decimal-degree coordinate.
    public static let latitudeRange: ClosedRange<Double> = -90...90
    public static let longitudeRange: ClosedRange<Double> = -180...180

    /// Whether a decimal-degree pair is a real coordinate. Rejects non-finite
    /// values as well as out-of-range ones, so a `nan` from a parser or a sensor
    /// can't become a location.
    public static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && latitudeRange.contains(latitude)
            && longitudeRange.contains(longitude)
    }

    /// Build a coordinate only if the pair is real — the entry point for typed
    /// or parsed input, so a transposed or half-typed field (`lat 380.2`) is
    /// rejected instead of being frozen onto an observation and read out on the
    /// radio.
    public init?(validating latitude: Double, longitude: Double) {
        guard Self.isValid(latitude: latitude, longitude: longitude) else { return nil }
        self.init(latitude: latitude, longitude: longitude)
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
