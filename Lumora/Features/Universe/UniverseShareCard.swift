import SwiftUI
import UniformTypeIdentifiers

/// What the universe share card shows: the whole sky, the Navigator rank
/// earned so far, and how long the universe has been growing.
struct UniverseShareContent: Equatable, Sendable {
    var scene: UniverseScene
    var rank: NavigatorRank
    var day: Int
    var stat: String
}

/// A 1080×1350 card of your universe: every star, constellation, planet and
/// charted world framed whole, above your rank. Same size, type and fixed
/// text settings as the other share cards.
struct UniverseShareCardView: View {
    let content: UniverseShareContent

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                Self.drawSky(&ctx, size: size, scene: content.scene)
            }
            text
        }
        .frame(width: ShareCardView.pointSize.width, height: ShareCardView.pointSize.height)
        .background(Color(hex: Palette.deepSpace))
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private var text: some View {
        VStack(spacing: 8) {
            Canvas { ctx, size in RankInsignia.draw(&ctx, in: size, level: content.rank.level, time: 0) }
                .frame(width: 58, height: 58)
            Text(String(localized: "Rank \(content.rank.level) · \(content.rank.title)").localizedUppercase)
                .font(LMFont.eyebrow).lmTracking(1.6)
                .foregroundStyle(Color(hex: Palette.warmGold))
            Text("Day \(content.day) of my universe")
                .font(LMFont.voice(.title))
                .foregroundStyle(Color(hex: 0xFFF1D6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(content.stat)
                .font(LMFont.footnote)
                .foregroundStyle(Color(hex: 0xB9BCE3))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            ShareCardBrand()
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    /// The sky fills the top of the card, framed to hold everything in it.
    nonisolated private static func drawSky(_ ctx: inout GraphicsContext, size: CGSize, scene: UniverseScene) {
        let sky = CGSize(width: size.width, height: size.height * 0.58)
        CelestialPainter.glow(&ctx, at: CGPoint(x: sky.width / 2, y: sky.height / 2), radius: size.width * 0.75,
                              color: Color(hex: Palette.cosmicViolet), intensity: 0.3)
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.8, time: nil)
        let points = scene.all.map(\.position) + scene.voyages.map(\.position) + scene.galaxies.map(\.center)
        let camera = UniverseCamera.fitting(points.isEmpty ? [.zero] : points, in: sky, padding: 34, zoomRange: 0.1...1.2)
        UniverseRenderer.draw(&ctx, size: sky, scene: scene, camera: camera,
                              options: .init(time: nil, dark: true, showLabels: false, showGhost: false,
                                             minimumStarRadius: 3.4, minimumPlanetRadius: 15, alwaysDetailed: true))
        ctx.blendMode = .normal
        ShareCardView.drawFloor(&ctx, size: size)
    }
}

/// The universe card as a shareable PNG, rendered only when the share sheet asks.
struct UniverseShareImage: Transferable {
    let content: UniverseShareContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            guard let data = await ShareCardRenderer.image(rendering: UniverseShareCardView(content: card.content))?.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { _ in "Orbi – Universe.png" }
    }
}
