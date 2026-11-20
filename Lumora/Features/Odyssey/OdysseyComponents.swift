import SwiftUI

enum OdysseyFormat {
    /// "1,240" with the locale's grouping.
    static func stardust(_ amount: Int) -> String { amount.formatted(.number) }
}

/// "✦ 1,240" — the stardust balance.
struct StardustPill: View {
    var amount: Int
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            StardustGlyph().frame(width: compact ? 11 : 14, height: compact ? 11 : 14)
            Text(OdysseyFormat.stardust(amount))
                .font((compact ? LMFont.footnote : LMFont.callout).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(LMColor.reward)
        .padding(.horizontal, compact ? 10 : 14)
        .frame(minHeight: compact ? 28 : 36)
        .background(Capsule().fill(LMColor.rewardFill.opacity(0.12)))
        .overlay(Capsule().strokeBorder(LMColor.rewardFill.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(amount) stardust"))
    }
}

/// A four-point sparkle filled with warm gold: the stardust mark.
struct StardustGlyph: View {
    var body: some View {
        StarShape(points: 4, innerRatio: 0.3).fill(LinearGradient(colors: [Color(hex: 0xFFF3C4), Color(hex: Palette.warmGold)],
                                                                   startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }
}

/// A slim glowing progress track with an optional ship riding the leading edge.
struct JourneyBar: View {
    var fraction: Double
    var tint: Color = LMColor.calm
    var showsShip = false
    var loadout = ShipLoadout()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = CGFloat(max(0, min(1, fraction)))
            ZStack(alignment: .leading) {
                Capsule().fill(LMColor.textPrimary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, w * f))
                    .shadow(color: tint.opacity(0.6), radius: 6)
                if showsShip {
                    Canvas { ctx, size in
                        RocketPainter.draw(&ctx, loadout: loadout, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           length: size.height * 0.9, heading: .pi / 2, thrust: 0.7, time: nil)
                    }
                    .frame(width: 34, height: 26)
                    .offset(x: max(0, min(w - 34, w * f - 17)))
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: showsShip ? 26 : 8)
        .accessibilityElement()
        .accessibilityLabel(Text("Journey"))
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}

/// Section title used across Odyssey screens.
struct OdysseySectionHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(LMFont.title).foregroundStyle(LMColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing).font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
            }
        }
    }
}

/// Rarity chip: Rare / Legendary.
struct RarityChip: View {
    var rarity: WorldRarity

    var body: some View {
        if rarity != .common {
            Text(rarity.label.localizedUppercase)
                .font(LMFont.eyebrow).lmTracking(1.2)
                .foregroundStyle(rarity == .legendary ? LMColor.onAccent : LMColor.reward)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(Capsule().fill(rarity == .legendary ? AnyShapeStyle(LinearGradient(colors: [Color(hex: Palette.warmGold), Color(hex: Palette.nebulaPink)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(LMColor.rewardFill.opacity(0.15))))
        }
    }
}

/// A small non-interactive world for rows and cards. Worlds stay veiled
/// until charted; arrival rows keep the veil so landing does the reveal.
struct WorldThumb: View {
    var world: WorldState
    var size: CGFloat = 64
    var veiled: Bool?

    var body: some View {
        WorldView(world: world.blueprint, stage: world.stage, silhouette: veiled ?? !world.isCharted,
                  animate: false, scale: 0.34)
            .frame(width: size, height: size)
    }
}
