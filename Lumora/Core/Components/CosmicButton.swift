import SwiftUI

/// Buttons (Components · Primary / secondary / ghost / round). Every control
/// is ≥ 44pt, springs to 0.97 on press with the Snap spring, and fires a
/// light selection haptic through the shared haptics service.
struct CosmicButtonStyle: ButtonStyle {
    enum Kind { case starlight, reward, secondary, ghost }

    var kind: Kind = .starlight
    var height: CGFloat = 60

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // Accessibility sizes wrap instead of shrinking or truncating.
        let large = typeSize.isAccessibilitySize
        configuration.label
            .font(LMFont.headline)
            .lineLimit(large ? 4 : 1)
            .minimumScaleFactor(large ? 1 : 0.8)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: large)
            .foregroundStyle(foreground)
            .padding(.vertical, large ? LMSpace.s : 0)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, large ? LMSpace.m : LMSpace.l)
            .background(background(pressed: pressed))
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(LMSpring.snap, value: pressed)
            .contentShape(shape)
            // Never let a parent stack squeeze a wrapped label.
            .fixedSize(horizontal: false, vertical: large)
    }

    /// A capsule; wrapped multi-line labels get a rounded rectangle so a
    /// tall button doesn't balloon into an oval.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? LMRadius.card : 999, style: .continuous)
    }

    private var foreground: Color {
        switch kind {
        case .starlight: LMColor.starlightLabel
        case .reward: LMColor.onAccent
        case .secondary, .ghost: LMColor.textPrimary
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        let glow = pressed ? 1.6 : 1.0
        switch kind {
        case .starlight:
            shape.fill(LMColor.starlightFill)
                .shadow(color: LMColor.focus.opacity(0.55 * glow * (isEnabled ? 1 : 0)), radius: 22)
                .background(shape.stroke(LMColor.focus.opacity(0.14 * glow), lineWidth: 6).padding(-6))
        case .reward:
            shape.fill(LMColor.rewardFill)
                .shadow(color: LMColor.rewardFill.opacity(0.45 * glow * (isEnabled ? 1 : 0)), radius: 22)
                .background(shape.stroke(LMColor.rewardFill.opacity(0.14 * glow), lineWidth: 6).padding(-6))
        case .secondary:
            shape.fill(reduceTransparency ? AnyShapeStyle(LMColor.glassSolid) : AnyShapeStyle(LMColor.glassTint))
                .overlay(shape.strokeBorder(LMColor.hairline, lineWidth: 1))
        case .ghost:
            shape.fill(Color.clear)
        }
    }
}

/// Convenience wrapper with an optional leading glyph and haptic tick.
struct CosmicButton: View {
    var title: LocalizedStringKey
    var systemImage: String?
    var kind: CosmicButtonStyle.Kind = .starlight
    var height: CGFloat = 60
    var action: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            app.haptics.selection()
            action()
        } label: {
            HStack(spacing: LMSpace.s) {
                // The glyph is decorative; at accessibility sizes the words get the room.
                if let systemImage, !typeSize.isAccessibilitySize {
                    Image(systemName: systemImage).font(.body.weight(.semibold))
                }
                Text(title)
            }
        }
        .buttonStyle(CosmicButtonStyle(kind: kind, height: height))
    }
}

/// Round control (pause / stop / back / ambient), 52 or 76pt.
struct RoundControlButton: View {
    var systemImage: String
    var label: LocalizedStringKey
    var size: CGFloat = 52
    var prominent = false
    var action: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(LMColor.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? LMColor.textPrimary.opacity(0.08) : Color.clear))
                .overlay(Circle().strokeBorder(LMColor.hairline.opacity(prominent ? 2 : 1.4), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(label))
        .frame(minWidth: 44, minHeight: 44)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(LMSpring.snap, value: configuration.isPressed)
    }
}
