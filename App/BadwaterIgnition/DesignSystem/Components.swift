import SwiftUI
import BadwaterCore

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
///
/// When a ``Sensitivity/Envelope`` is supplied it gains a **cell-edge marker**.
/// The IRPG tables are step functions, so a reading a step or two from a cell
/// edge can swing PIG by a whole fire-behavior band. The marker surfaces that in
/// three layers, and — critically — costs nothing to read when the number is
/// firm:
/// - **Layer 1 (always on):** the severity stripe stays solid when firm and
///   becomes a subtle gradient toward the neighbouring band when the plausible
///   envelope crosses one. A pre-attentive "this one's on the move" cue at zero
///   added height.
/// - **Layer 2 (reserved slot):** one amber caution line naming the notable
///   neighbour, in a fixed-height slot so the card never changes size as inputs
///   change (no input-driven jitter).
/// - **Layer 3 (tap to expand):** the full envelope and the band transition, for
///   crews who want to verify — matching the app's show-your-work ethic.
struct ResultCard: View {
    let title: String
    let pig: Int
    let severity: Color
    let subtitle: String
    /// The firmness envelope for this shading; `nil` disables the marker.
    var sensitivity: Sensitivity.Envelope? = nil
    /// The reading envelope explored, e.g. `"±2°F · ±3% RH"` (expanded detail).
    var toleranceSummary: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    /// Height of the reserved caption slot, scaled with Dynamic Type so the slot
    /// still fits (and still prevents jitter) at accessibility text sizes.
    @ScaledMetric(relativeTo: .caption2) private var captionSlotHeight: CGFloat = 16

    /// The neighbouring reading worth surfacing — present exactly when the
    /// envelope crosses a fire-behavior band.
    private var crossing: Sensitivity.Reading? { sensitivity?.notable }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fieldLabel()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(pig)").font(BadwaterFont.readout(46)).foregroundStyle(severity)
                Text("%").font(BadwaterFont.readout(22)).foregroundStyle(severity)
            }
            Text(subtitle).font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            edgeCaption
            if expanded, let env = sensitivity { firmnessDetail(env) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BadwaterColor.surface, in: RoundedRectangle(cornerRadius: Metric.resultRadius))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Metric.resultRadius,
                bottomLeadingRadius: Metric.resultRadius)
                .fill(stripeStyle)
                .frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: Metric.resultRadius).strokeBorder(BadwaterColor.hairline))
        .contentShape(Rectangle())
        .onTapGesture {
            guard sensitivity != nil else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: crossing)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("result-\(title)")
        .accessibilityLabel("\(title) probability of ignition")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(sensitivity != nil ? "Double tap for reading firmness detail" : "")
        .accessibilityAction(named: "Reading firmness detail") {
            if sensitivity != nil { expanded.toggle() }
        }
    }

    /// Layer 1 — solid when firm, a subtle current→neighbour gradient on an edge.
    private var stripeStyle: AnyShapeStyle {
        if let nb = crossing {
            return AnyShapeStyle(LinearGradient(
                colors: [severity, nb.band.color], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(severity)
    }

    /// Layer 2 — one amber line in a fixed-height slot (empty when firm), so the
    /// card holds its size no matter how the inputs move. The slot only exists
    /// when a firmness envelope is supplied, so a plain ``ResultCard`` (e.g. the
    /// Watch hero, showing a frozen reading) is unchanged.
    @ViewBuilder private var edgeCaption: some View {
        if let env = sensitivity {
            ZStack(alignment: .leading) {
                Color.clear.frame(height: captionSlotHeight)
                if let nb = env.notable {
                    HStack(spacing: 3) {
                        Image(systemName: env.direction == .higher ? "arrow.up.forward" : "arrow.down.forward")
                        Text("COULD READ \(nb.pig)% · \(nb.descriptor)")
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .font(BadwaterFont.labelSmall)
                    .foregroundStyle(BadwaterColor.caution)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Layer 3 — the full envelope and the band transition (or reassurance).
    @ViewBuilder private func firmnessDetail(_ env: Sensitivity.Envelope) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(BadwaterColor.hairline).frame(height: 1).padding(.top, 4)
            Text("Reading firmness").fieldLabel()
            Text("PIG \(env.pigLow)–\(env.pigHigh)%" + (toleranceSummary.map { " over \($0)" } ?? ""))
                .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.ink)
            if let nb = env.notable {
                Text("\(env.baselineBand.title) → \(nb.band.title) at \(nb.descriptor)")
                    .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            } else {
                Text("Band holds — firm.")
                    .font(BadwaterFont.labelSmall).foregroundStyle(BadwaterColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var accessibilityValueText: String {
        var v = "\(pig) percent. \(subtitle)"
        if let env = sensitivity, let nb = crossing {
            let dir = env.direction == .higher ? "higher" : "lower"
            v += ". Near a band edge — could read \(nb.pig) percent, \(nb.band.title), \(dir), at \(nb.descriptor)"
        }
        return v
    }
}
