import SwiftUI

/// Typography (Foundations · Typography). SF Pro ships on device; the
/// Instrument Serif "voice" maps to New York Italic. Every style is built on a
/// Dynamic Type text style so it scales to AX5.
enum LMFont {
    /// Emotional moments only ("You did it.").
    static func voice(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif).italic()
    }

    static let largeTitle = Font.system(.largeTitle, weight: .light)
    static let title = Font.system(.title2, weight: .semibold)
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout, weight: .medium)
    static let footnote = Font.system(.footnote, weight: .medium)
    static let eyebrow = Font.system(.caption2, weight: .bold)

    /// The focus timer: ExtraLight, tabular digits. Size is supplied by the
    /// caller through `@ScaledMetric` and capped at 120pt.
    static func timer(size: CGFloat) -> Font {
        .system(size: size, weight: .ultraLight).monospacedDigit()
    }
}

/// Small caps "eyebrow" label: bold, tracked +14%, uppercased.
struct EyebrowText: View {
    let text: String
    var color: Color = LMColor.textTertiary

    init(_ text: String, color: Color = LMColor.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.localizedUppercase)
            .font(LMFont.eyebrow)
            .lmTracking(1.6)
            .foregroundStyle(color)
    }
}
