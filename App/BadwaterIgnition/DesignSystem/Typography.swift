import SwiftUI

/// Typography and metric tokens for Badwater Ignition.
///
/// Identity comes from color, spacing, and an instrument-like layout — not a
/// custom typeface — so the app uses the system faces per Apple platform
/// conventions: **SF Pro** for text and **SF Mono** for the tabular figures,
/// labels, and IRPG references that should read like a field instrument.
enum BadwaterFont {
    /// Large readout value (PIG %, RH %). Rounded, heavy, tabular.
    static func readout(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }

    /// Input value in a stepper card.
    static let inputValue = Font.system(size: 32, weight: .bold, design: .rounded).monospacedDigit()

    /// Screen / section title.
    static let title = Font.system(size: 22, weight: .bold, design: .rounded)

    /// Card and control body text.
    static let body = Font.system(.body, design: .rounded)

    /// Uppercase mono labels, page references, chips.
    static let label = Font.system(.caption, design: .monospaced)
    static let labelSmall = Font.system(.caption2, design: .monospaced)
}

/// Shared spacing / radius metrics so the layout stays on a consistent grid.
enum Metric {
    static let screenPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    /// Breathing room between the labeled input groups (Weather / Calendar·Time /
    /// Site) so the sections read as distinct chunks, not one long list.
    static let sectionSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let resultRadius: CGFloat = 18
    /// Minimum interactive target — sized generously for gloved hands.
    static let tapTarget: CGFloat = 48
    /// Baseline height of a ``StatusStrip`` row. The strip reserves this height in
    /// every state (scaled with Dynamic Type) so a warning turning on or off never
    /// shifts the layout around it.
    static let statusStripHeight: CGFloat = 34
}

extension Text {
    /// Uppercase mono label styling used for field labels and IRPG references.
    func fieldLabel() -> some View {
        self.font(BadwaterFont.label)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(BadwaterColor.muted)
    }
}
