import Foundation

/// Time of day for a fuel-moisture estimate.
///
/// The IRPG correction tables (B/C/D) are organized into six two-hour daytime
/// bands spanning 0800–1959. Outside that window the IRPG uses a separate
/// nighttime rule (see ``IgnitionCalculator``), represented here by ``night``.
public enum TimeOfDay: Sendable, Codable, Equatable, Hashable, CaseIterable, Identifiable {
    case band0800_0959
    case band1000_1159
    case band1200_1359
    case band1400_1559
    case band1600_1759
    case band1800_1959
    /// 2000–0759. Handled by the nighttime reference-fuel-moisture rule
    /// rather than a correction-table column.
    case night

    public var id: String { label }

    /// The six daytime bands, in table-column order.
    public static let daytimeBands: [TimeOfDay] = [
        .band0800_0959, .band1000_1159, .band1200_1359,
        .band1400_1559, .band1600_1759, .band1800_1959
    ]

    /// Column index (0–5) into the correction tables, or `nil` for ``night``.
    public var correctionColumnIndex: Int? {
        switch self {
        case .band0800_0959: return 0
        case .band1000_1159: return 1
        case .band1200_1359: return 2
        case .band1400_1559: return 3
        case .band1600_1759: return 4
        case .band1800_1959: return 5
        case .night: return nil
        }
    }

    /// `true` for the nighttime case.
    public var isNight: Bool { self == .night }

    /// The band label as printed in the IRPG (e.g. `"1200-1359"`).
    public var label: String {
        switch self {
        case .band0800_0959: return "0800-0959"
        case .band1000_1159: return "1000-1159"
        case .band1200_1359: return "1200-1359"
        case .band1400_1559: return "1400-1559"
        case .band1600_1759: return "1600-1759"
        case .band1800_1959: return "1800-1959"
        case .night: return "Night"
        }
    }

    /// Resolve a time of day from a 24-hour clock value.
    ///
    /// - Parameters:
    ///   - hour: 0–23
    ///   - minute: 0–59 (defaults to 0)
    /// - Returns: the daytime band containing the time, or ``night`` when the
    ///   time falls outside 0800–1959.
    public static func from(hour: Int, minute: Int = 0) -> TimeOfDay {
        let minutes = hour * 60 + minute
        switch minutes {
        case (8 * 60)..<(10 * 60): return .band0800_0959
        case (10 * 60)..<(12 * 60): return .band1000_1159
        case (12 * 60)..<(14 * 60): return .band1200_1359
        case (14 * 60)..<(16 * 60): return .band1400_1559
        case (16 * 60)..<(18 * 60): return .band1600_1759
        case (18 * 60)..<(20 * 60): return .band1800_1959
        default: return .night
        }
    }
}
