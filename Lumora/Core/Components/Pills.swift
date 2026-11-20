import SwiftUI

/// Status pill ("12-day rhythm", "Break · 5:00").
struct StatusPill: View {
    var text: String
    var systemImage: String?
    var tint: Color = LMColor.reward

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.semibold)) }
            Text(text).font(LMFont.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Category chip: shape glyph + label, hue on selection.
struct CategoryChip: View {
    var category: FocusCategory
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CategoryGlyph(category: category, size: 16)
                Text(category.displayName).font(LMFont.headline.weight(.medium))
            }
            .foregroundStyle(LMColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? category.color.opacity(0.12) : LMColor.textPrimary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? category.color : LMColor.hairline, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(Text(category.displayName))
    }
}

struct CategoryGlyph: View {
    var category: FocusCategory
    var size: CGFloat = 16

    var body: some View {
        StarShape(points: category.starPoints)
            .fill(category.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Duration orb: 60pt, 72pt when selected, Bloom spring. `diameter` is the
/// selected size; narrow screens and large text pass a different one.
struct DurationOrb: View {
    var minutes: Int?
    var isSelected: Bool
    var diameter: CGFloat = 72
    var action: () -> Void

    var body: some View {
        let size = isSelected ? diameter : diameter - 12
        Button(action: action) {
            VStack(spacing: 0) {
                if let minutes {
                    Text("\(minutes)").font(.system(.title2, weight: .semibold).monospacedDigit())
                    Text("MIN").font(LMFont.eyebrow).lmTracking(1).foregroundStyle(LMColor.textSecondary)
                } else {
                    Image(systemName: "plus").font(.title3)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // The orb grows with text only so far; past that the Large
            // Content Viewer shows the value.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .foregroundStyle(LMColor.textPrimary)
            .frame(width: size, height: size)
            .background(Circle().fill(isSelected ? LMColor.focus.opacity(0.35) : LMColor.textPrimary.opacity(0.04)))
            .overlay(Circle().strokeBorder(isSelected ? LMColor.focus : LMColor.hairline,
                                           style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: minutes == nil && !isSelected ? [4, 4] : [])))
            .shadow(color: isSelected ? LMColor.focus.opacity(0.5) : .clear, radius: 16)
            .frame(width: diameter + 4, height: diameter + 4)
            .animation(LMSpring.bloom, value: isSelected)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(minutes.map { Text("\($0) minutes") } ?? Text("Custom duration"))
        .accessibilityShowsLargeContentViewer {
            Text(minutes.map { "\($0) min" } ?? String(localized: "Custom"))
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Generic selectable chip (ambient sound, filters).
struct SelectChip: View {
    var title: String
    var systemImage: String?
    var isSelected: Bool
    var tint: Color = LMColor.calm
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.semibold)) }
                Text(title).font(LMFont.headline.weight(.medium))
            }
            .foregroundStyle(LMColor.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? tint.opacity(0.12) : LMColor.textPrimary.opacity(0.04)))
            .overlay(Capsule().strokeBorder(isSelected ? tint : LMColor.hairline, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Segmented control styled as a glass capsule (Week / Month, Night / Dawn / Auto).
struct CosmicSegmented<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var ns
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Options stack at accessibility sizes so each label stays whole.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(LMSpring.settle) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(LMFont.headline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? LMColor.starlightLabel : LMColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, stacked ? LMSpace.xs : 0)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                Capsule().fill(LMColor.starlightFill).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: stacked ? 26 : 30, style: .continuous).fill(LMColor.textPrimary.opacity(0.06)))
    }
}
