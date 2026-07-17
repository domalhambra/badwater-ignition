import SwiftUI
import BadwaterCore

/// The shared **weather** inputs — humidity source, dry bulb, and either a direct
/// RH or a wet bulb (with its elevation band and derived RH). Both the Ignition
/// screen and the Watch capture card render *these exact controls bound to the
/// same* ``IgnitionModel``, so extracting them here keeps the two screens from
/// drifting and lets the "shared with the other tab" cue stay honest.
///
/// The wet-bulb-only extras (elevation band + derived RH) sit at the end of the
/// group and animate in place, so switching humidity source resizes this one
/// bounded block instead of inserting rows that shove the rest of the screen.
struct WeatherInputGroup: View {
    @Bindable var model: IgnitionModel
    /// The other tab these inputs are shared with, shown as a passive cue in the
    /// section header (e.g. "Watch" on Ignition, "Ignition" on Watch). Pass `nil`
    /// to omit the header entirely.
    var sharedWith: String? = nil
    /// Whether to show the read-only derived-RH card in wet-bulb mode. Ignition
    /// shows it (the value flowing into the PIG chain); the Watch capture card
    /// keeps its footprint tighter and omits it.
    var showsDerivedHumidity: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.cardSpacing) {
            if let sharedWith {
                SectionHeader(title: "Weather", annotation: "IRPG Table A", sharedWith: sharedWith)
            }
            ChipPicker(title: "Humidity source", options: RHSource.allCases,
                       selection: $model.rhSource, label: \.displayName)
            HStack(spacing: 10) {
                StepperCard(label: "Dry bulb", unit: "°F",
                            value: $model.dryBulbF, range: 10...130)
                if model.rhSource == .direct {
                    StepperCard(label: "Rel. humidity", unit: "%",
                                value: $model.relativeHumidity, range: 0...100)
                } else {
                    StepperCard(label: "Wet bulb", unit: "°F",
                                value: $model.wetBulbF, range: 10...130)
                }
            }
            if model.rhSource == .wetBulb {
                ChipPicker(title: "Elevation band  ·  \(Int(model.elevationBand.stationPressureInHg)) inHg",
                           options: ElevationBand.allCases, selection: $model.elevationBand,
                           label: \.conusLabel)
                if showsDerivedHumidity { derivedHumidity }
            }
            windControls
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.rhSource)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.windSpeedMPH > 0)
    }

    /// Observed wind. Speed 0 mph reads as light/variable and hides the direction
    /// and gust; above 0 the compass and gust appear (contained, so the rest of
    /// the group doesn't jump). Wind is recorded on the reading, not used by PIG.
    @ViewBuilder private var windControls: some View {
        HStack(spacing: 10) {
            StepperCard(label: "Wind", unit: "mph", value: $model.windSpeedMPH, range: 0...60)
            if model.windSpeedMPH > 0 {
                StepperCard(label: "Gust", unit: "mph", value: $model.windGustMPH, range: 0...80)
            }
        }
        if model.windSpeedMPH > 0 {
            ChipPicker(title: "Wind from", options: Wind.Direction.allCases,
                       selection: $model.windDirection, label: \.abbreviation)
        }
    }

    /// The RH derived from the wet bulb, shown (read-only, in the brand teal) so
    /// the value flowing into the PIG chain is visible in wet-bulb mode.
    private var derivedHumidity: some View {
        let rh = model.effectiveRelativeHumidity
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rel. humidity").fieldLabel()
                Text("computed from wet bulb")
                    .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(rh)").font(BadwaterFont.readout(32)).foregroundStyle(BadwaterColor.accent)
                Text("%").font(BadwaterFont.readout(18)).foregroundStyle(BadwaterColor.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("derived-rh")
        .accessibilityLabel("Relative humidity from wet bulb")
        .accessibilityValue("\(rh) percent")
    }
}
