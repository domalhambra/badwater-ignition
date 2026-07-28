import Foundation

/// How a relative-humidity reading was obtained.
///
/// A Kestrel (or other electronic meter) reads RH directly; a sling
/// psychrometer / belt weather kit reads a wet-bulb temperature from which RH is
/// derived (dry bulb + wet bulb + elevation band). Both feed the same PIG chain.
/// This is a record-level fact — a logged observation keeps it so an export can
/// state how the humidity was measured — so it lives in the pure core.
public enum RHSource: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    /// RH is typed in directly (e.g. read off a Kestrel).
    case direct
    /// RH is derived from a wet-bulb temperature (slinging weather).
    case wetBulb

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .direct: return "Direct"
        case .wetBulb: return "From wet bulb"
        }
    }
}
