import Foundation

/// Seasonal grouping that selects which 1-hr fuel-moisture correction table to
/// use. The IRPG provides three tables keyed by month:
///
/// - ``tableB`` — May, June, July
/// - ``tableC`` — February, March, April and August, September, October
/// - ``tableD`` — November, December, January
public enum MonthGroup: String, CaseIterable, Sendable, Codable, Identifiable {
    case tableB
    case tableC
    case tableD

    public var id: String { rawValue }

    /// Resolve the correction table for a calendar month (1 = January … 12 = December).
    public static func from(month: Int) -> MonthGroup {
        switch month {
        case 5, 6, 7: return .tableB
        case 2, 3, 4, 8, 9, 10: return .tableC
        case 11, 12, 1: return .tableD
        default:
            // Out-of-range months clamp to the nearest sensible table; callers
            // should pass 1–12. Default to the shoulder-season table.
            return .tableC
        }
    }

    /// Table letter as printed in the IRPG.
    public var letter: String {
        switch self {
        case .tableB: return "B"
        case .tableC: return "C"
        case .tableD: return "D"
        }
    }

    /// The months covered, for display.
    public var monthsDescription: String {
        switch self {
        case .tableB: return "May–Jun–Jul"
        case .tableC: return "Feb–Mar–Apr & Aug–Sep–Oct"
        case .tableD: return "Nov–Dec–Jan"
        }
    }

    /// `true` for the winter table (Nov–Dec–Jan), whose 0800–0959 column is
    /// annotated "(+ night)" in the IRPG.
    public var isWinter: Bool { self == .tableD }
}
