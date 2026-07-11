import SwiftUI
import BadwaterCore

/// The Ignition screen: inputs at top, the IRPG calculation chain in the
/// middle, and both shaded/unshaded Probability of Ignition results with a
/// plain-language interpretation. Everything updates live.
struct IgnitionView: View {
    @Bindable var model: IgnitionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.cardSpacing) {
                header

                // Fast inputs
                HStack(spacing: 10) {
                    TemperatureStepperCard(label: "Dry bulb", valueF: $model.dryBulbF,
                                           rangeF: 10...130, unit: model.temperatureUnit)
                    StepperCard(label: "Rel. humidity", unit: "%",
                                value: $model.relativeHumidity, range: 0...100)
                }
                ChipPicker(title: "Units", options: TemperatureUnit.allCases,
                           selection: $model.temperatureUnit, label: \.symbol)

                // Site factors
                monthPicker
                ChipPicker(title: "Time of day", options: TimeOfDay.allCases,
                           selection: $model.timeOfDay, label: \.label)
                HStack(alignment: .top, spacing: 10) {
                    ChipPicker(title: "Aspect", options: Aspect.allCases,
                               selection: $model.aspect, label: \.rawValue)
                    ChipPicker(title: "Slope", options: Slope.allCases,
                               selection: $model.slope, label: \.displayName)
                }
                ChipPicker(title: "Elevation vs. weather site", options: ElevationDelta.allCases,
                           selection: $model.elevationDelta, label: \.displayName)

                chainStrip
                results
                interpretation
                disclaimer
            }
            .padding(Metric.screenPadding)
        }
        .background(BadwaterColor.background)
        .navigationTitle("Ignition")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ignition").font(BadwaterFont.title).foregroundStyle(BadwaterColor.ink)
            Spacer()
            Text("IRPG p.44–49").fieldLabel()
        }
    }

    private var monthPicker: some View {
        ChipPicker(title: "Month  ·  \(model.estimate.input.monthGroup.letter) (\(model.estimate.input.monthGroup.monthsDescription))",
                   options: Array(1...12), selection: $model.month,
                   label: { Month.shortNames[$0 - 1] })
    }

    private var chainStrip: some View {
        let e = model.estimate
        return HStack(spacing: 0) {
            chainNode("REF FM", "\(e.referenceFuelMoisture)")
            chainArrow
            chainNode("CORR", e.isNight ? "night +5"
                      : "\(e.unshaded.correction ?? 0)/\(e.shaded.correction ?? 0)")
            chainArrow
            chainNode("FFM", "\(e.unshaded.fineFuelMoisture)/\(e.shaded.fineFuelMoisture)%")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calc-chain")
    }

    private func chainNode(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            Text(value).font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(BadwaterColor.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var chainArrow: some View {
        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(BadwaterColor.muted.opacity(0.6))
    }

    private var results: some View {
        let e = model.estimate
        return HStack(spacing: 10) {
            ResultCard(title: "Unshaded", pig: e.unshaded.probabilityOfIgnition,
                       severity: e.unshaded.interpretation.color,
                       subtitle: "FFM \(e.unshaded.fineFuelMoisture)% · <50% shade")
            ResultCard(title: "Shaded", pig: e.shaded.probabilityOfIgnition,
                       severity: e.shaded.interpretation.color,
                       subtitle: "FFM \(e.shaded.fineFuelMoisture)% · ≥50% shade")
        }
    }

    private var interpretation: some View {
        // Lead with the more hazardous (unshaded) interpretation.
        let behavior = model.estimate.unshaded.interpretation
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(behavior.color).frame(width: 9, height: 9)
                Text(behavior.title).font(BadwaterFont.body.weight(.semibold)).foregroundStyle(BadwaterColor.ink)
                Text(behavior.pigRangeLabel).font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            }
            Text(behavior.detail).font(.footnote).foregroundStyle(BadwaterColor.ink.opacity(0.85))
            Text(FireBehaviorInterpretation.caution + "  IRPG p.49")
                .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted).italic()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BadwaterColor.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("interpretation")
    }

    private var disclaimer: some View {
        Text("Decision support only — not affiliated with or endorsed by NWCG. Verify against your IRPG.")
            .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}
