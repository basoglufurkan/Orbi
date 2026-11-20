import SwiftUI

/// The deep-space backdrop: base color plus soft nebula washes. `mood`
/// shifts the palette for focus, breaks and rewards; `light` (0...1)
/// brightens the sky as a session progresses or the universe grows.
struct CosmicBackgroundView: View {
    enum Mood: Equatable { case home, focus, rest, reward }

    var mood: Mood = .home
    var light: Double = 0.5
    var showsStars = true
    var starOpacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SkyPreferences.theme) private var themeRaw = SkyTheme.classic.rawValue
    @AppStorage(PlusAccess.key, store: PlusAccess.defaults) private var plusActive = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LMColor.bgBase
                // Washes sit between the far and mid star layers; overscan
                // so the shift never reveals an edge.
                ParallaxShift(depth: 0.35) { washes(size: geo.size) }
                    .padding(-ParallaxMath.maxOffset)
                if showsStars { StarFieldView(opacity: starOpacity) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var isDark: Bool { colorScheme == .dark }

    @ViewBuilder
    private func washes(size: CGSize) -> some View {
        let l = max(0, min(1, light))
        let strength = (isDark ? 1.0 : 0.55) * (reduceTransparency ? 0.6 : 1)
        switch mood {
        case .rest:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0B1A2E), Color(hex: 0x123049)], startPoint: .top, endPoint: .bottom)
                    .opacity(isDark ? 1 : 0.25)
                RadialGradient(colors: [Color(hex: Palette.starlightCyan).opacity(0.18 * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.75), startRadius: 0, endRadius: size.height * 0.6)
            }
        case .focus:
            ZStack {
                RadialGradient(colors: [Color(hex: Palette.cosmicViolet).opacity((0.10 + 0.16 * l) * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: size.height * 0.55)
                RadialGradient(colors: [Color(hex: Palette.warmGold).opacity(0.08 * max(0, l - 0.6) / 0.4 * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: size.height * 0.4)
            }
        case .reward:
            ZStack {
                RadialGradient(colors: [Color(hex: Palette.cosmicViolet).opacity(0.30 * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: size.height * 0.5)
                RadialGradient(colors: [Color(hex: Palette.warmGold).opacity(0.10 * strength), .clear],
                               center: UnitPoint(x: 0.6, y: 0.2), startRadius: 0, endRadius: size.height * 0.35)
            }
        case .home:
            let theme = SkyTheme.current(raw: themeRaw, plusActive: plusActive).washes
            ZStack {
                RadialGradient(colors: [Color(hex: theme.primary).opacity((0.22 + 0.12 * l) * strength), .clear],
                               center: UnitPoint(x: 0.45, y: 0.42), startRadius: 0, endRadius: size.height * 0.5)
                RadialGradient(colors: [Color(hex: theme.secondary).opacity(0.12 * strength), .clear],
                               center: UnitPoint(x: 0.0, y: 0.55), startRadius: 0, endRadius: size.width * 0.8)
            }
        }
    }
}
