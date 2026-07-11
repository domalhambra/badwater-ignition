import Foundation

/// IRPG **Table A — Reference Fuel Moisture** (PMS 461, p. 45).
///
/// Maps a dry-bulb temperature band and a relative-humidity band to a reference
/// (1-hr) fuel-moisture percentage. Every value below is a faithful, cell-exact
/// transcription of the printed table — not a formula approximation — so results
/// match the pocket guide line for line.
///
/// > Note: The printed row labels are `10-29, 30-49, 50-69, 70-89, 90-109, 109+`.
/// > The final two labels overlap at 109; this is read as `90-109` and `110+`
/// > (a long-standing print quirk). Temperatures ≥ 110 °F use the last row.
public enum ReferenceFuelMoistureTable {

    /// Row bands (dry-bulb °F), inclusive lower bounds in table order.
    /// Index 0 = `10-29` … index 5 = `110+`.
    public static let temperatureBands: [String] = [
        "10-29", "30-49", "50-69", "70-89", "90-109", "110+"
    ]

    /// Column bands (relative humidity %). Index 0 = `0-4` … index 20 = `100`.
    public static let humidityBands: [String] = [
        "0-4", "5-9", "10-14", "15-19", "20-24", "25-29", "30-34", "35-39",
        "40-44", "45-49", "50-54", "55-59", "60-64", "65-69", "70-74", "75-79",
        "80-84", "85-89", "90-94", "95-99", "100"
    ]

    /// The reference fuel-moisture grid: `grid[tempRow][humidityColumn]` → %.
    /// 6 rows × 21 columns.
    static let grid: [[Int]] = [
        [1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 8, 8, 9, 9, 10, 11, 12, 12, 13, 13, 14],
        [1, 2, 2, 3, 4, 5, 5, 6, 7, 7, 7, 8, 9, 9, 10, 10, 11, 12, 13, 13, 13],
        [1, 2, 2, 3, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 11, 12, 12, 12, 13],
        [1, 1, 2, 2, 3, 4, 5, 5, 6, 7, 7, 8, 8, 8, 9, 10, 10, 11, 12, 12, 13],
        [1, 1, 2, 2, 3, 4, 4, 5, 6, 7, 7, 8, 8, 8, 9, 10, 10, 11, 12, 12, 13],
        [1, 1, 2, 2, 3, 4, 4, 5, 6, 7, 7, 8, 8, 8, 9, 10, 10, 11, 12, 12, 12]
    ]

    /// Row index into Table A for a dry-bulb temperature.
    /// Temperatures below the table clamp to the first row.
    static func temperatureRow(forDryBulbF temp: Int) -> Int {
        switch temp {
        case ..<30: return 0        // 10-29 (and below, clamped)
        case 30...49: return 1
        case 50...69: return 2
        case 70...89: return 3
        case 90...109: return 4
        default: return 5           // 110+
        }
    }

    /// Column index into Table A for a relative humidity (0–100%).
    static func humidityColumn(forRH rh: Int) -> Int {
        let clamped = min(max(rh, 0), 100)
        if clamped >= 100 { return 20 }
        return clamped / 5   // 0-4→0, 5-9→1, … 95-99→19
    }

    /// Look up the reference fuel moisture (%) for a temperature and humidity.
    ///
    /// - Parameters:
    ///   - dryBulbF: dry-bulb temperature in °F.
    ///   - relativeHumidity: relative humidity, 0–100%.
    /// - Returns: reference fuel moisture as a whole-number percentage.
    public static func referenceFuelMoisture(dryBulbF: Int, relativeHumidity: Int) -> Int {
        grid[temperatureRow(forDryBulbF: dryBulbF)][humidityColumn(forRH: relativeHumidity)]
    }
}
