import SwiftUI
import BadwaterCore

/// A temperature stepper that binds to a canonical °F value but displays and
/// steps in the selected ``TemperatureUnit``. The underlying value stays in °F
/// (the IRPG's native unit) so table lookups are never lossy.
struct TemperatureStepperCard: View {
    let label: String
    /// Canonical value in °F.
    @Binding var valueF: Int
    /// Allowed range in °F.
    var rangeF: ClosedRange<Int>
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).fieldLabel()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(unit.fromFahrenheit(valueF))")
                    .font(BadwaterFont.inputValue).foregroundStyle(BadwaterColor.ink)
                Text(unit.symbol).font(BadwaterFont.body).foregroundStyle(BadwaterColor.muted)
            }
            HStack(spacing: 8) {
                stepButton("minus") { step(-1) }
                stepButton("plus") { step(1) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
        // One VoiceOver element; swipe up/down adjusts by a degree.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(label)
        .accessibilityLabel(label)
        .accessibilityValue(accessibleValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private var accessibleValue: String {
        "\(unit.fromFahrenheit(valueF)) degrees \(unit == .celsius ? "Celsius" : "Fahrenheit")"
    }

    /// Step by one degree in the *display* unit, then clamp in °F.
    private func step(_ delta: Int) {
        let displayed = unit.fromFahrenheit(valueF) + delta
        let f = unit.toFahrenheit(displayed)
        valueF = min(max(f, rangeF.lowerBound), rangeF.upperBound)
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(BadwaterColor.ink)
        }
        .buttonStyle(.plain)
    }
}

/// A large stepper input card: mono label, big tabular value, and −/+ buttons
/// sized for gloved hands. Tapping the value also allows direct entry.
struct StepperCard: View {
    let label: String
    let unit: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).fieldLabel()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)").font(BadwaterFont.inputValue).foregroundStyle(BadwaterColor.ink)
                Text(unit).font(BadwaterFont.body).foregroundStyle(BadwaterColor.muted)
            }
            HStack(spacing: 8) {
                stepButton("minus") { adjust(-step) }
                stepButton("plus") { adjust(step) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(label)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(step)
            case .decrement: adjust(-step)
            @unknown default: break
            }
        }
    }

    private func adjust(_ delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                .background(BadwaterColor.surfaceSunk, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(BadwaterColor.ink)
        }
        .buttonStyle(.plain)
    }
}

/// A read-only stat card (e.g. dew point, wet-bulb depression).
struct StatCard: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).fieldLabel()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(BadwaterFont.inputValue).foregroundStyle(BadwaterColor.ink)
                Text(unit).font(BadwaterFont.body).foregroundStyle(BadwaterColor.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Metric.cardRadius).strokeBorder(BadwaterColor.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(label)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }
}

/// A single-select chip row for a `CaseIterable` enum of options.
struct ChipPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fieldLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        let selected = option == selection
                        Button {
                            selection = option
                        } label: {
                            Text(label(option))
                                .font(BadwaterFont.labelSmall)
                                .kerning(0.4)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(
                                    selected ? BadwaterColor.accent.opacity(0.16) : BadwaterColor.surface,
                                    in: Capsule())
                                .overlay(Capsule().strokeBorder(
                                    selected ? BadwaterColor.accent : BadwaterColor.hairline,
                                    lineWidth: selected ? 1.5 : 1))
                                .foregroundStyle(selected ? BadwaterColor.accent : BadwaterColor.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(label(option))
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The PIG result card: severity stripe, big tabular readout, and sub-line.
struct ResultCard: View {
    let title: String
    let pig: Int
    let severity: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fieldLabel()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(pig)").font(BadwaterFont.readout(46)).foregroundStyle(severity)
                Text("%").font(BadwaterFont.readout(22)).foregroundStyle(severity)
            }
            Text(subtitle).font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.resultRadius))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Metric.resultRadius,
                bottomLeadingRadius: Metric.resultRadius)
                .fill(severity)
                .frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: Metric.resultRadius).strokeBorder(BadwaterColor.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("result-\(title)")
        .accessibilityLabel("\(title) probability of ignition")
        .accessibilityValue("\(pig) percent. \(subtitle)")
    }
}
