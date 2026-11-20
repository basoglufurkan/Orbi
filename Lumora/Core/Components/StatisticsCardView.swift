import SwiftUI

/// Stat card (Components · Cards): eyebrow, large value, optional detail.
struct StatisticsCardView: View {
    var title: String
    var value: String
    var detail: String?
    var accent: Color = LMColor.textTertiary
    var highlight: Color?
    var valueLines = 1
    /// Stretch to the tallest sibling (use inside a `.fixedSize(vertical:)` row).
    var fillsHeight = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Narrow three-up rows shrink the eyebrow rather than split a word.
            EyebrowText(title, color: highlight ?? accent)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.6)
            Text(value)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(LMColor.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? max(3, valueLines) : valueLines)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.7)
                .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            if let detail {
                Text(detail)
                    .font(LMFont.footnote)
                    .foregroundStyle(highlight ?? LMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, 14)
        .glassCard(radius: 22, border: highlight.map { $0.opacity(0.4) })
        .accessibilityElement(children: .combine)
    }
}
