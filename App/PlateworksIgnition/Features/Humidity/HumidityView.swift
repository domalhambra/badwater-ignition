import SwiftUI
import PlateworksCore

/// The Humidity screen: dry/wet-bulb inputs, elevation band, and the resulting
/// relative humidity and dew point — with a one-tap hand-off into the Ignition
/// calculator.
@MainActor
struct HumidityView: View {
    @Bindable var model: HumidityModel
    /// Called when the user taps "Use in ignition calc" with the computed RH.
    var onUseInIgnition: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.cardSpacing) {
                header

                bigResult

                HStack(spacing: 10) {
                    StepperCard(label: "Dry bulb", unit: "°F",
                                value: $model.dryBulbF, range: 10...130)
                    StepperCard(label: "Wet bulb", unit: "°F",
                                value: $model.wetBulbF, range: 10...130)
                }

                HStack(spacing: 10) {
                    StatCard(label: "Dew point",
                             value: "\(model.result.dewPointF)",
                             unit: "°F")
                    StatCard(label: "WB depression",
                             value: "\(model.result.wetBulbDepressionF)",
                             unit: "°F")
                }

                elevationPicker
                alaskaToggle
                useButton
                disclaimer
            }
            .padding(Metric.screenPadding)
        }
        .background(PlateworksColor.background)
        .navigationTitle("Humidity")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Humidity").font(PlateworksFont.title).foregroundStyle(PlateworksColor.ink)
            Spacer()
            Text("NWCG PMS 437").fieldLabel()
        }
    }

    private var bigResult: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(model.result.relativeHumidity)").readout(72)
                    .foregroundStyle(PlateworksColor.accent)
                Text("%").readout(30).foregroundStyle(PlateworksColor.accent)
            }
            Text("Relative humidity").fieldLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("rh-readout")
        .accessibilityLabel("Relative humidity")
        .accessibilityValue("\(model.result.relativeHumidity) percent")
    }

    private var elevationPicker: some View {
        ChipPicker(title: "Elevation band  ·  \(Int(model.band.stationPressureInHg)) inHg",
                   options: ElevationBand.allCases, selection: $model.band,
                   label: model.label(for:))
    }

    private var alaskaToggle: some View {
        Toggle(isOn: $model.alaska) {
            Text("Alaska elevation thresholds").font(PlateworksFont.body).foregroundStyle(PlateworksColor.ink)
        }
        .tint(PlateworksColor.accent)
        .padding(.horizontal, 14)
        .frame(minHeight: Metric.tapTarget)
        .background(PlateworksColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(PlateworksColor.hairline))
    }

    private var useButton: some View {
        Button {
            onUseInIgnition(model.result.relativeHumidity)
        } label: {
            Text("Use in ignition calc")
                .font(PlateworksFont.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                .background(PlateworksColor.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("use-in-ignition")
    }

    private var disclaimer: some View {
        Text("Psychrometric estimate — verify against your belt weather kit tables.")
            .font(PlateworksFont.labelSmall).foregroundStyle(PlateworksColor.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}
