import SwiftUI
import Combine
import BadwaterCore

/// The Ignition screen: inputs at top, the IRPG calculation chain in the
/// middle, and both shaded/unshaded Probability of Ignition results with a
/// plain-language interpretation. Everything updates live.
struct IgnitionView: View {
    @Bindable var model: IgnitionModel
    @Environment(\.scenePhase) private var scenePhase
    /// Keeps month/time tracking the wall clock across a long shift; the model
    /// ignores ticks once the operator overrides either picker.
    private let clockTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.cardSpacing) {
                header

                // Fast inputs
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
                    derivedHumidity
                }

                // Site factors
                monthPicker
                ChipPicker(title: "Time of day", options: TimeOfDay.allCases,
                           selection: $model.timeOfDay, label: \.label)
                if model.clockOverridden { clockOverrideNotice }
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
        .onReceive(clockTick) { _ in model.refreshClock() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshClock() }
        }
    }

    /// Shown only while a manual month/time override is standing in for the
    /// clock — the "visible flag" so a stale night/day rule is never silent.
    private var clockOverrideNotice: some View {
        Button {
            model.resumeAutoClock()
        } label: {
            Label("Month/time set manually — tap to resume tracking the clock",
                  systemImage: "clock.arrow.circlepath")
                .font(BadwaterFont.labelSmall)
                .foregroundStyle(BadwaterColor.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clock-override-notice")
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
