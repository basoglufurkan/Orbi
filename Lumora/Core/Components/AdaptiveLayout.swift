import SwiftUI

/// A row at regular text sizes that stacks vertically at accessibility
/// Dynamic Type sizes, so side-by-side cards and labels never squeeze.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

/// Fills the available height (so inner spacers push content apart) and
/// scrolls only when the content is taller than the screen: small iPhones
/// and large Dynamic Type.
struct FittingScrollView<Content: View>: View {
    var alignment: Alignment = .top
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: alignment)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}

/// One item of an `AdaptiveStack` of glyph + label tiles: an icon over its
/// label in a row, or icon beside label in the stacked list.
struct AdaptiveStackItem<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            HStack(spacing: LMSpace.s) { content }
        } else {
            VStack(spacing: 4) { content }.frame(maxWidth: .infinity)
        }
    }
}
