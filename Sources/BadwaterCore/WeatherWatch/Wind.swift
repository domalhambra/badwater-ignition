import Foundation

/// An observed wind reading. Wind is not computed by the app — the crew reads it
/// off the terrain / a meter — so this is a pure record type that renders exactly
/// the way the IMET spreadsheet and the NWS spot request each expect.
public struct Wind: Hashable, Codable, Sendable {

    /// A speed value or range, in MPH.
    public struct SpeedRange: Hashable, Codable, Sendable {
        public var low: Int
        public var high: Int
        public init(low: Int, high: Int) { self.low = low; self.high = high }
        public init(_ single: Int) { self.low = single; self.high = single }
        /// `"3-5"` for a range, `"8"` for a single value.
        public var rendered: String { low == high ? "\(low)" : "\(low)-\(high)" }
    }

    /// Eight-point compass direction the wind blows **from**. Nested so it doesn't
    /// collide with the four-point terrain ``Aspect``.
    public enum Direction: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
        case north = "N", northeast = "NE", east = "E", southeast = "SE"
        case south = "S", southwest = "SW", west = "W", northwest = "NW"

        public var id: String { rawValue }
        public var abbreviation: String { rawValue }
        public var displayName: String {
            switch self {
            case .north: return "North"
            case .northeast: return "Northeast"
            case .east: return "East"
            case .southeast: return "Southeast"
            case .south: return "South"
            case .southwest: return "Southwest"
            case .west: return "West"
            case .northwest: return "Northwest"
            }
        }
    }

    /// `nil` speed means light/variable — calm with no defined direction.
    public var speed: SpeedRange?
    public var direction: Direction?
    /// Peak gust in MPH — the crew reports a single ceiling ("gusts up to N"),
    /// not a range. `nil` when not gusting.
    public var gust: Int?

    public init(speed: SpeedRange?, direction: Direction?, gust: Int? = nil) {
        self.speed = speed
        self.direction = direction
        self.gust = gust
    }

    public static func lightVariable(gust: Int? = nil) -> Wind {
        Wind(speed: nil, direction: nil, gust: gust)
    }
    public static func measured(_ speed: SpeedRange, _ direction: Direction, gust: Int? = nil) -> Wind {
        Wind(speed: speed, direction: direction, gust: gust)
    }

    /// XLSX column E — speed-first, full direction word.
    /// e.g. `"3-5 North, Gust 12"`, `"Light/Variable"`, `"1-5 South"`.
    public var imetCell: String {
        let gustSuffix = gust.map { ", Gust \($0)" } ?? ""
        guard let speed else { return "Light/Variable" + gustSuffix }
        let dir = direction.map { " \($0.displayName)" } ?? ""
        return speed.rendered + dir + gustSuffix
    }

    /// NWS spot-request line — direction-first, abbreviated.
    /// e.g. `"N 3-5 Gust 12"`, `"SW 4-6"`, `"Calm"`.
    public var spotString: String {
        guard let speed else { return "Calm" }
        let dir = direction.map { "\($0.abbreviation) " } ?? ""
        let gustSuffix = gust.map { " Gust \($0)" } ?? ""
        return dir + speed.rendered + gustSuffix
    }

    /// Spoken radio phrasing — `"1-3 miles per hour from the West"`, `"8 miles
    /// per hour from the Southwest"`, `"1 mile per hour from the North"`,
    /// `"light and variable"`; gusts append `", gusts up to 12"`. Mirrors the
    /// other renderings' precedence: `speed == nil` means light/variable and
    /// ignores any direction.
    public var spokenPhrase: String {
        let gustSuffix = gust.map { ", gusts up to \($0)" } ?? ""
        guard let speed else { return "light and variable" + gustSuffix }
        let unit = (speed.low == speed.high && speed.low == 1) ? "mile per hour" : "miles per hour"
        let dir = direction.map { " from the \($0.displayName)" } ?? ""
        return "\(speed.rendered) \(unit)\(dir)" + gustSuffix
    }
}
