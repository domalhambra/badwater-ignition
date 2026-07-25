import SwiftUI

/// Typography and metric tokens for Badwater Ignition.
///
/// Identity comes from color, spacing, and an instrument-like layout — not a
/// custom typeface — so the app uses the system faces per Apple platform
/// conventions: **SF Pro** for text and **SF Mono** for the tabular figures,
/// labels, and IRPG references that should read like a field instrument.
enum BadwaterFont {
    /// Large readout value (PIG %, RH %). Rounded, heavy, tabular.
    ///
    /// - Important: this is a **fixed** point size and does not respond to
    ///   Dynamic Type. Prefer ``SwiftUI/View/readout(_:weight:relativeTo:)``,
    ///   which scales. This overload remains for the few places where a value is
    ///   composed into a `Font` rather than applied to a view.
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

/// A readout that **scales with Dynamic Type** instead of sitting at a fixed
/// point size.
///
/// The numbers a crew actually reads — PIG, RH, the input values — were fixed at
/// 22–72 pt and ignored the accessibility text size the operator had set. At arm's
/// length, in smoke, possibly without reading glasses, that is a field-ergonomics
/// problem rather than a checkbox.
///
/// Two deliberate choices:
///
/// - Scaled `relativeTo: .body` rather than `.largeTitle`. Body scales more
///   gently at the accessibility sizes, which keeps a three-digit PIG and its
///   unit on one line in a two-across card layout.
/// - Always paired with `lineLimit(1)` and a `minimumScaleFactor`, so the text
///   shrinks to fit rather than clipping or truncating. A truncated PIG is worse
///   than a small one, and this makes clipping impossible at any text size — the
///   right guarantee for a change whose visual result is hard to eyeball at every
///   size on every device.
private struct ScaledReadout: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat
    private let weight: Font.Weight
    private let minimumScale: CGFloat

    init(size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle,
         minimumScale: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.minimumScale = minimumScale
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
    }
}

extension View {
    /// Apply the Dynamic-Type-scaling readout style at a given base point size.
    func readout(_ size: CGFloat, weight: Font.Weight = .heavy,
                 relativeTo textStyle: Font.TextStyle = .body,
                 minimumScale: CGFloat = 0.5) -> some View {
        modifier(ScaledReadout(size: size, weight: weight,
                               relativeTo: textStyle, minimumScale: minimumScale))
    }
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
