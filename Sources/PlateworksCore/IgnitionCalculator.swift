import Foundation

/// Walks the IRPG Fine Fuel Moisture / Probability of Ignition procedure
/// (PMS 461, p. 44) end to end, computing both the unshaded and shaded outcomes
/// so a crew can compare exposure in the open versus under canopy.
///
/// The procedure:
/// 1. **Reference fuel moisture** from Table A (dry-bulb temp × RH).
/// 2. **Correction** from Table B/C/D (season, shading, aspect, slope, time band,
///    elevation delta).
/// 3. **Fine Fuel Moisture** = reference + correction.
/// 4. **Probability of Ignition** from the PIG table (dry-bulb temp × FFM,
///    unshaded or shaded).
///
/// ### Nighttime
/// For nighttime estimates the IRPG (p. 45) replaces steps 2–3 with a simple
/// rule: Fine Fuel Moisture = Table A value **+ 5**. Plateworks Ignition applies
/// that rule when ``TimeOfDay/night`` is selected.
///
/// > Note: Table D (Nov–Dec–Jan) annotates its 0800–0959 column "(+ night)",
/// > implying the winter early-morning correction may also serve nighttime. The
/// > explicit p. 45 "+5" rule is used here as the documented method; the winter
/// > nuance is flagged for subject-matter review rather than silently assumed.
public enum IgnitionCalculator {

    /// The value added to Table A's reference fuel moisture for nighttime
    /// estimates (IRPG p. 45).
    public static let nighttimeFuelMoistureAddition = 5

    /// Produce a full ignition estimate (reference fuel moisture plus both
    /// shaded and unshaded outcomes) for the given inputs.
    public static func estimate(_ input: IgnitionInput) -> IgnitionEstimate {
        let referenceFuelMoisture = ReferenceFuelMoistureTable.referenceFuelMoisture(
            dryBulbF: input.dryBulbF,
            relativeHumidity: input.relativeHumidity
        )
        let isNight = input.timeOfDay.isNight

        func shadingEstimate(for shading: Shading) -> ShadingEstimate {
            let correction: Int?
            let fineFuelMoisture: Int

            if isNight {
                correction = nil
                fineFuelMoisture = referenceFuelMoisture + nighttimeFuelMoistureAddition
            } else {
                let c = FuelMoistureCorrectionTable.correction(
                    monthGroup: input.monthGroup,
                    shading: shading,
                    aspect: input.aspect,
                    slope: input.slope,
                    timeOfDay: input.timeOfDay,
                    elevationDelta: input.elevationDelta
                ) ?? 0
                correction = c
                fineFuelMoisture = referenceFuelMoisture + c
            }

            let pig = ProbabilityOfIgnitionTable.probabilityOfIgnition(
                dryBulbF: input.dryBulbF,
                fineFuelMoisture: fineFuelMoisture,
                shading: shading
            )
            return ShadingEstimate(
                shading: shading,
                correction: correction,
                fineFuelMoisture: fineFuelMoisture,
                probabilityOfIgnition: pig
            )
        }

        return IgnitionEstimate(
            input: input,
            referenceFuelMoisture: referenceFuelMoisture,
            isNight: isNight,
            unshaded: shadingEstimate(for: .unshaded),
            shaded: shadingEstimate(for: .shaded)
        )
    }
}
