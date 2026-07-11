import Foundation

/// IRPG **Tables B / C / D — 1-hr Fuel Moisture Corrections** (PMS 461, pp. 46–48).
///
/// A correction (in fuel-moisture percentage points) is added to the reference
/// fuel moisture from Table A to obtain Fine Fuel Moisture. The correction
/// depends on season (which table), shading, aspect, slope, time-of-day band,
/// and the elevation relationship between the fire and the weather site.
///
/// Layout of each grid:
/// - **18 value columns** = six time bands `[0800-0959, 1000-1159, 1200-1359,
///   1400-1559, 1600-1759, 1800-1959]`, each split into `B, L, A`
///   (below / level / above the weather site).
/// - **Unshaded rows (8)** = aspect × slope, in order
///   `N/0-30, N/31%, E/0-30, E/31%, S/0-30, S/31%, W/0-30, W/31%`.
/// - **Shaded rows (4)** = aspect only (slope not a factor), `N, E, S, W`.
///
/// > Note: In every table the Shaded section's `0800-0959 / L` cell is printed
/// > with an asterisk (`5*`). No footnote for the asterisk appears on the table
/// > pages of the IRPG; the numeric value (5) is used and the asterisk is
/// > recorded in ``asteriskCells`` for faithful display.
public enum FuelMoistureCorrectionTable {

    public static let timeBands: [String] = [
        "0800-0959", "1000-1159", "1200-1359", "1400-1559", "1600-1759", "1800-1959"
    ]

    // MARK: - Table B (May–Jun–Jul)

    static let tableB_unshaded: [[Int]] = [
        [2, 3, 4, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 2, 3, 4],
        [3, 4, 4, 1, 2, 2, 1, 1, 2, 1, 1, 2, 1, 2, 2, 3, 4, 4],
        [2, 2, 3, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 2, 3, 4, 4],
        [1, 2, 2, 0, 0, 1, 0, 0, 1, 1, 1, 2, 2, 3, 4, 4, 5, 6],
        [2, 3, 3, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 2, 3, 3],
        [2, 3, 3, 1, 1, 2, 0, 1, 1, 0, 1, 1, 1, 1, 2, 2, 3, 3],
        [2, 3, 4, 1, 1, 2, 0, 0, 1, 0, 0, 1, 0, 1, 1, 2, 3, 3],
        [4, 5, 6, 2, 3, 4, 1, 1, 2, 0, 0, 1, 0, 0, 1, 1, 2, 2]
    ]
    static let tableB_shaded: [[Int]] = [
        [4, 5, 5, 3, 4, 5, 3, 3, 4, 3, 3, 4, 3, 4, 5, 4, 5, 5],
        [4, 4, 5, 3, 4, 5, 3, 3, 4, 3, 4, 4, 3, 4, 5, 4, 5, 6],
        [4, 4, 5, 3, 4, 5, 3, 3, 4, 3, 3, 4, 3, 4, 5, 4, 5, 5],
        [4, 5, 6, 3, 4, 5, 3, 3, 4, 3, 3, 4, 3, 4, 5, 4, 4, 5]
    ]

    // MARK: - Table C (Feb–Mar–Apr & Aug–Sep–Oct)

    static let tableC_unshaded: [[Int]] = [
        [3, 4, 5, 1, 2, 3, 1, 1, 2, 1, 1, 2, 1, 2, 3, 3, 4, 5],
        [3, 4, 5, 3, 3, 4, 2, 3, 4, 2, 3, 4, 3, 3, 4, 3, 4, 5],
        [3, 4, 5, 1, 2, 3, 1, 1, 1, 1, 1, 2, 1, 2, 4, 3, 4, 5],
        [3, 3, 4, 1, 1, 1, 1, 1, 1, 1, 2, 3, 3, 4, 5, 4, 5, 6],
        [3, 4, 5, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2, 3, 3, 4, 5],
        [3, 4, 5, 1, 2, 2, 0, 1, 1, 0, 1, 1, 1, 2, 2, 3, 4, 5],
        [3, 4, 5, 1, 2, 3, 1, 1, 1, 1, 1, 1, 1, 2, 3, 3, 4, 5],
        [4, 5, 6, 3, 4, 5, 1, 2, 3, 1, 1, 1, 1, 1, 1, 3, 3, 4]
    ]
    static let tableC_shaded: [[Int]] = [
        [4, 5, 6, 4, 5, 5, 3, 4, 5, 3, 4, 5, 4, 5, 5, 4, 5, 6],
        [4, 5, 6, 3, 4, 5, 3, 4, 5, 3, 4, 5, 4, 5, 6, 4, 5, 6],
        [4, 5, 6, 3, 4, 5, 3, 4, 5, 3, 4, 5, 3, 4, 5, 4, 5, 6],
        [4, 5, 6, 4, 5, 6, 3, 4, 5, 3, 4, 5, 3, 4, 5, 4, 5, 6]
    ]

    // MARK: - Table D (Nov–Dec–Jan). 0800-0959 column is "(+ night)".

    static let tableD_unshaded: [[Int]] = [
        [4, 5, 6, 3, 4, 5, 2, 3, 4, 2, 3, 4, 3, 4, 5, 4, 5, 6],
        [4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6],
        [4, 5, 6, 3, 4, 4, 2, 3, 3, 2, 3, 3, 3, 4, 5, 4, 5, 6],
        [4, 5, 6, 2, 3, 4, 2, 2, 3, 3, 4, 4, 4, 5, 6, 4, 5, 6],
        [4, 5, 6, 3, 4, 5, 2, 3, 3, 2, 2, 3, 3, 4, 4, 4, 5, 6],
        [4, 5, 6, 2, 3, 3, 1, 1, 2, 1, 1, 2, 2, 3, 3, 4, 5, 6],
        [4, 5, 6, 3, 4, 5, 2, 3, 3, 2, 3, 3, 3, 4, 4, 4, 5, 6],
        [4, 5, 6, 4, 5, 6, 3, 4, 4, 2, 2, 3, 2, 3, 4, 4, 5, 6]
    ]
    static let tableD_shaded: [[Int]] = [
        [4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6],
        [4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6],
        [4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6],
        [4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6, 4, 5, 6]
    ]

    /// Cells printed with an asterisk in the IRPG (Shaded, 0800-0959, L),
    /// as `(shadingIsShaded, row, column)` triples. Same in Tables B/C/D.
    static let asteriskColumn = 1   // 0800-0959 / L
    static func hasAsterisk(shading: Shading, row: Int, column: Int) -> Bool {
        shading == .shaded && column == asteriskColumn
    }

    // MARK: - Lookup

    static func unshadedGrid(for group: MonthGroup) -> [[Int]] {
        switch group {
        case .tableB: return tableB_unshaded
        case .tableC: return tableC_unshaded
        case .tableD: return tableD_unshaded
        }
    }

    static func shadedGrid(for group: MonthGroup) -> [[Int]] {
        switch group {
        case .tableB: return tableB_shaded
        case .tableC: return tableC_shaded
        case .tableD: return tableD_shaded
        }
    }

    /// Row index for the unshaded section: aspect × slope.
    static func unshadedRow(aspect: Aspect, slope: Slope) -> Int {
        let aspectIndex = Aspect.allCases.firstIndex(of: aspect) ?? 0
        return aspectIndex * 2 + (slope == .steep ? 1 : 0)
    }

    /// Row index for the shaded section: aspect only.
    static func shadedRow(aspect: Aspect) -> Int {
        Aspect.allCases.firstIndex(of: aspect) ?? 0
    }

    /// Column index: time band × elevation delta.
    static func column(timeBandIndex: Int, elevationDelta: ElevationDelta) -> Int {
        let deltaIndex = ElevationDelta.allCases.firstIndex(of: elevationDelta) ?? 1
        return timeBandIndex * 3 + deltaIndex
    }

    /// Look up the 1-hr fuel-moisture correction for daytime conditions.
    ///
    /// - Returns: the correction in fuel-moisture percentage points, or `nil`
    ///   if the time of day is ``TimeOfDay/night`` (night uses a separate rule).
    public static func correction(
        monthGroup: MonthGroup,
        shading: Shading,
        aspect: Aspect,
        slope: Slope,
        timeOfDay: TimeOfDay,
        elevationDelta: ElevationDelta
    ) -> Int? {
        guard let bandIndex = timeOfDay.correctionColumnIndex else { return nil }
        let col = column(timeBandIndex: bandIndex, elevationDelta: elevationDelta)
        switch shading {
        case .unshaded:
            return unshadedGrid(for: monthGroup)[unshadedRow(aspect: aspect, slope: slope)][col]
        case .shaded:
            return shadedGrid(for: monthGroup)[shadedRow(aspect: aspect)][col]
        }
    }
}
