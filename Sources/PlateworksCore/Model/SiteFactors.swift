import Foundation

/// Terrain aspect — the compass direction a slope faces. Used to index the
/// 1-hr fuel-moisture correction tables (IRPG Tables B/C/D).
public enum Aspect: String, CaseIterable, Sendable, Codable, Identifiable {
    case north = "N"
    case east = "E"
    case south = "S"
    case west = "W"

    public var id: String { rawValue }

    /// Full compass name for display.
    public var displayName: String {
        switch self {
        case .north: return "North"
        case .east: return "East"
        case .south: return "South"
        case .west: return "West"
        }
    }
}

/// Slope steepness class. The IRPG correction tables split unshaded fuels into
/// two slope classes; shaded fuels use a single "All" class where slope is
/// not a factor.
public enum Slope: String, CaseIterable, Sendable, Codable, Identifiable {
    /// 0–30% slope.
    case gentle = "0-30%"
    /// 31% or steeper.
    case steep = "31%+"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gentle: return "0–30%"
        case .steep: return "31%+"
        }
    }
}

/// Surface-fuel shading. Determines which half of the correction table and
/// which Probability-of-Ignition table is used. Plateworks Ignition always
/// computes BOTH so the crew can compare exposure in the open vs. under canopy.
public enum Shading: String, CaseIterable, Sendable, Codable, Identifiable {
    /// Less than 50% shading of surface fuels.
    case unshaded
    /// 50% or more shading of surface fuels (canopy and/or cloud cover).
    case shaded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unshaded: return "Unshaded"
        case .shaded: return "Shaded"
        }
    }

    /// The shading threshold as printed in the IRPG.
    public var detail: String {
        switch self {
        case .unshaded: return "Less than 50% shading"
        case .shaded: return "50% or more shading"
        }
    }
}

/// Elevation relationship between the *area of concern* (the fire) and the
/// *weather site* where the observation was taken. Indexes the B/L/A
/// sub-columns of the correction tables (IRPG Tables B/C/D).
public enum ElevationDelta: String, CaseIterable, Sendable, Codable, Identifiable {
    /// Area of concern is 1,000′ to 2,000′ **below** the weather site.
    case below = "B"
    /// Area of concern is **within** 1,000′ of the weather site.
    case level = "L"
    /// Area of concern is 1,000′ to 2,000′ **above** the weather site.
    case above = "A"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .below: return "Below"
        case .level: return "Level"
        case .above: return "Above"
        }
    }

    /// The full description as printed in the IRPG legend.
    public var detail: String {
        switch self {
        case .below: return "1,000′–2,000′ below the weather site"
        case .level: return "Within 1,000′ of the weather site"
        case .above: return "1,000′–2,000′ above the weather site"
        }
    }
}
