import SwiftUI
import BadwaterCore

/// The Humidity screen: dry/wet-bulb inputs, elevation band, and the resulting
/// relative humidity and dew point — with a one-tap hand-off into the Ignition
/// calculator.
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
                    StepperCard(label: "Dry bulb", unit: "°F", value: $model.dryBulbF, range: 10...130)
                    StepperCard(label: "Wet bulb", unit: "°F", value: $model.wetBulbF, range: 10...130)
                }

                HStack(spacing: 10) {
                    StatCard(label: "Dew point", value: "\(model.result.dewPointF)", unit: "°F")
                    StatCard(label: "WB depression", value: "\(model.result.wetBulbDepressionF)", unit: "°F")
                }

                elevationPicker
                alaskaToggle
                useButton
                disclaimer
            }
            .padding(Metric.screenPadding)
        }
        .background(BadwaterColor.background)
        .navigationTitle("Humidity")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Humidity").font(BadwaterFont.title).foregroundStyle(BadwaterColor.ink)
            Spacer()
            Text("NWCG PMS 437").fieldLabel()
        }
    }

    private var bigResult: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(model.result.relativeHumidity)").font(BadwaterFont.readout(72))
                    .foregroundStyle(BadwaterColor.accent)
                Text("%").font(BadwaterFont.readout(30)).foregroundStyle(BadwaterColor.accent)
            }
            Text("Relative humidity").fieldLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var elevationPicker: some View {
        ChipPicker(title: "Elevation band  ·  \(Int(model.band.stationPressureInHg)) inHg",
                   options: ElevationBand.allCases, selection: $model.band,
                   label: { alaskaAwareLabel($0) })
    }

    private func alaskaAwareLabel(_ band: ElevationBand) -> String {
        model.alaska ? band.alaskaLabel : band.conusLabel
    }

    private var alaskaToggle: some View {
        Toggle(isOn: $model.alaska) {
            Text("Alaska elevation thresholds").font(BadwaterFont.body).foregroundStyle(BadwaterColor.ink)
        }
        .tint(BadwaterColor.accent)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
    }

    private var useButton: some View {
        Button {
            onUseInIgnition(model.result.relativeHumidity)
        } label: {
            Text("Use in ignition calc")
                .font(BadwaterFont.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                .background(BadwaterColor.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text("Psychrometric estimate — verify against your belt weather kit tables.")
            .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}
