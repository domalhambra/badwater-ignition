import Foundation

/// Elevation band for the NWCG psychrometric (relative humidity / dew point)
/// tables. Each band corresponds to a nominal station pressure; the printed
/// belt-weather-kit tables (PMS 437) are published one booklet per band.
///
/// Alaska uses shifted elevation thresholds (lower pressures at a given
/// elevation), selected by the `alaska` flag on ``forElevation(feetMSL:alaska:)``.
public enum ElevationBand: Int, CaseIterable, Sendable, Codable, Identifiable {
    case band1 = 1   // 0–500 ft   (AK 0–300)        — 30 inHg
    case band2 = 2   // 501–1,900  (AK 301–1,700)    — 29 inHg
    case band3 = 3   // 1,901–3,900 (AK 1,701–3,600) — 27 inHg
    case band4 = 4   // 3,901–6,100 (AK 3,601–5,700) — 25 inHg
    case band5 = 5   // 6,101–8,500 (AK 5,701–7,900) — 23 inHg
    case band6 = 6   // 8,501–11,000 (AK >7,900)     — 21 inHg

    public var id: Int { rawValue }

    /// Nominal station pressure for the band, in inches of mercury.
    public var stationPressureInHg: Double {
        switch self {
        case .band1: return 30
        case .band2: return 29
        case .band3: return 27
        case .band4: return 25
        case .band5: return 23
        case .band6: return 21
        }
    }

    /// Elevation range label for the contiguous U.S. (feet MSL).
    public var conusLabel: String {
        switch self {
        case .band1: return "0–500 ft"
        case .band2: return "501–1,900 ft"
        case .band3: return "1,901–3,900 ft"
        case .band4: return "3,901–6,100 ft"
        case .band5: return "6,101–8,500 ft"
        case .band6: return "8,501–11,000 ft"
        }
    }

    /// Elevation range label for Alaska (feet MSL).
    public var alaskaLabel: String {
        switch self {
        case .band1: return "0–300 ft"
        case .band2: return "301–1,700 ft"
        case .band3: return "1,701–3,600 ft"
        case .band4: return "3,601–5,700 ft"
        case .band5: return "5,701–7,900 ft"
        case .band6: return "above 7,900 ft"
        }
    }

    /// Resolve the elevation band for a site elevation.
    ///
    /// Elevations below sea level (e.g. Badwater Basin, −282 ft) clamp to
    /// band 1; elevations above the top band clamp to band 6.
    ///
    /// - Parameters:
    ///   - feetMSL: site elevation in feet above mean sea level.
    ///   - alaska: use Alaska thresholds when `true`.
    public static func forElevation(feetMSL: Int, alaska: Bool = false) -> ElevationBand {
        if alaska {
            switch feetMSL {
            case ..<301: return .band1
            case 301...1700: return .band2
            case 1701...3600: return .band3
            case 3601...5700: return .band4
            case 5701...7900: return .band5
            default: return .band6
            }
        } else {
            switch feetMSL {
            case ..<501: return .band1
            case 501...1900: return .band2
            case 1901...3900: return .band3
            case 3901...6100: return .band4
            case 6101...8500: return .band5
            default: return .band6
            }
        }
    }
}
