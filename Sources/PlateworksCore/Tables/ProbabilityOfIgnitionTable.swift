import Foundation

/// IRPG **Probability of Ignition Table** (PMS 461, p. 44).
///
/// Maps a dry-bulb temperature band and a Fine Dead Fuel Moisture percentage to
/// a Probability of Ignition (PIG) percentage — the chance that a firebrand
/// landing in fine fuels starts a fire that requires suppression. Two variants
/// are printed, for Unshaded (< 50%) and Shaded (≥ 50%) fuels.
///
/// > Important: The PIG table uses a **different** dry-bulb banding than Table A
/// > (10-wide bands `30-39 … 110+`, versus Table A's 20-wide bands). Both
/// > bandings are implemented separately.
public enum ProbabilityOfIgnitionTable {

    /// Column headers — Fine Dead Fuel Moisture percent, 2…17.
    public static let fineFuelMoistureColumns: [Int] = Array(2...17)

    /// Row bands (dry-bulb °F) in table order. Index 0 = `110+` … index 8 = `30-39`.
    public static let temperatureBands: [String] = [
        "110+", "100-109", "90-99", "80-89", "70-79", "60-69", "50-59", "40-49", "30-39"
    ]

    /// PIG for Unshaded fuels (< 50% shading). `grid[tempRow][ffmColumn]` → %.
    static let unshaded: [[Int]] = [
        [100, 100, 80, 70, 60, 60, 50, 40, 40, 30, 30, 20, 20, 20, 20, 10],
        [100, 90, 80, 70, 60, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10],
        [100, 90, 80, 70, 60, 50, 40, 40, 30, 30, 30, 20, 20, 20, 10, 10],
        [100, 90, 80, 70, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10],
        [100, 80, 70, 60, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10],
        [90, 80, 70, 60, 50, 50, 40, 30, 30, 20, 20, 20, 20, 10, 10, 10],
        [90, 80, 70, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10, 10],
        [90, 80, 70, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10, 10],
        [80, 70, 60, 50, 50, 40, 30, 30, 20, 20, 20, 10, 10, 10, 10, 10]
    ]

    /// PIG for Shaded fuels (≥ 50% shading). `grid[tempRow][ffmColumn]` → %.
    static let shaded: [[Int]] = [
        [100, 90, 80, 70, 60, 50, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10],
        [100, 90, 80, 70, 60, 50, 50, 40, 30, 30, 30, 20, 20, 20, 10, 10],
        [100, 90, 80, 70, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10],
        [100, 80, 70, 60, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10],
        [90, 80, 70, 60, 50, 50, 40, 30, 30, 30, 20, 20, 20, 10, 10, 10],
        [90, 80, 70, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10, 10],
        [90, 80, 70, 60, 50, 40, 40, 30, 30, 20, 20, 20, 10, 10, 10, 10],
        [90, 80, 60, 50, 50, 40, 30, 30, 30, 20, 20, 20, 10, 10, 10, 10],
        [80, 80, 60, 50, 50, 40, 30, 30, 20, 20, 20, 10, 10, 10, 10, 10]
    ]

    /// Row index into the PIG table for a dry-bulb temperature.
    static func temperatureRow(forDryBulbF temp: Int) -> Int {
        switch temp {
        case 110...: return 0
        case 100...109: return 1
        case 90...99: return 2
        case 80...89: return 3
        case 70...79: return 4
        case 60...69: return 5
        case 50...59: return 6
        case 40...49: return 7
        default: return 8   // 30-39 and below (clamped)
        }
    }

    /// Column index into the PIG table for a fine-fuel-moisture percentage.
    /// Values below 2 clamp to the first column; values above 17 to the last.
    static func fuelMoistureColumn(forFFM ffm: Int) -> Int {
        min(max(ffm - 2, 0), fineFuelMoistureColumns.count - 1)
    }

    /// Look up Probability of Ignition (%) for a temperature, fine fuel moisture,
    /// and shading condition.
    public static func probabilityOfIgnition(dryBulbF: Int, fineFuelMoisture: Int, shading: Shading) -> Int {
        let grid = shading == .shaded ? shaded : unshaded
        return grid[temperatureRow(forDryBulbF: dryBulbF)][fuelMoistureColumn(forFFM: fineFuelMoisture)]
    }
}
