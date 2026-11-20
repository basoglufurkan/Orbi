import SwiftUI

/// Glass 1 (cards): thin material + space tint + hairline. Falls back to a
/// solid raised surface with Reduce Transparency, as specified.
struct GlassBackground: ViewModifier {
    var radius: CGFloat = LMRadius.card
    var tint: Color? = nil
    var border: Color? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(LMColor.glassSolid)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(colorScheme == .dark ? Color(hex: Palette.deepSpace).opacity(0.4) : Color.white.opacity(0.5)))
                        .overlay(shape.fill(LMColor.glassTint))
                }
            }
            .overlay { if let tint { shape.fill(tint.opacity(0.08)).allowsHitTesting(false) } }
            .overlay(shape.strokeBorder(border ?? LMColor.hairline, lineWidth: 1))
    }
}

extension View {
    func glassCard(radius: CGFloat = LMRadius.card, tint: Color? = nil, border: Color? = nil) -> some View {
        modifier(GlassBackground(radius: radius, tint: tint, border: border))
    }
}
