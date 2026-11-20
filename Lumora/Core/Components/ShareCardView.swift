import SwiftUI
import UniformTypeIdentifiers

/// What a share card shows: one object drawn by `CelestialPainter`, an
/// eyebrow, a serif title and a short stat line.
struct ShareCardContent: Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        case celestial(CelestialSnapshot)
        case artifact(ArtifactMotif)
    }

    var subject: Subject
    var eyebrow: String
    var title: String
    var stat: String
    /// Accent for the eyebrow; gold for rewards, the category color for stars.
    var accent: UInt32 = Palette.warmGold
}

/// A 1080×1350 portrait card (4:5) in the Lumora style. Laid out at 360×450
/// points and rendered at 3×, always dark, at a fixed text size so every
/// card looks the same whatever the viewer's settings.
struct ShareCardView: View {
    static let pointSize = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3
    static var pixelSize: CGSize { CGSize(width: pointSize.width * renderScale, height: pointSize.height * renderScale) }

    let content: ShareCardContent

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                Self.drawBackdrop(&ctx, size: size)
                if case .celestial(let object) = content.subject {
                    Self.drawObject(&ctx, object, at: Self.artCenter(in: size))
                }
            }
            if case .artifact(let motif) = content.subject {
                // The motif is drawn at its collection size; scaling keeps it
                // vector-sharp in the renderer. Its own -40pt overdraw lets the
                // glow fade out instead of stopping at a square edge.
                ArtifactMotifView(motif: motif, earned: true)
                    .frame(width: 120, height: 120)
                    .scaleEffect(2.1)
                    .position(Self.artCenter(in: Self.pointSize))
            }
            text
        }
        .frame(width: Self.pointSize.width, height: Self.pointSize.height)
        .background(Color(hex: Palette.deepSpace))
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private var text: some View {
        VStack(spacing: 10) {
            Text(content.eyebrow.localizedUppercase)
                .font(LMFont.eyebrow).lmTracking(1.6)
                .foregroundStyle(Color(hex: content.accent))
            Text(content.title)
                .font(LMFont.voice(.largeTitle))
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
                .padding(.top, 18)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
    }

    nonisolated static func artCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.38)
    }

    nonisolated static func drawBackdrop(_ ctx: inout GraphicsContext, size: CGSize) {
        let center = artCenter(in: size)
        CelestialPainter.glow(&ctx, at: center, radius: size.width * 0.75, color: Color(hex: Palette.cosmicViolet), intensity: 0.3)
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.8, time: nil)
        drawFloor(&ctx, size: size)
    }

    /// A soft floor so the text sits on darker sky.
    nonisolated static func drawFloor(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45)),
                 with: .linearGradient(Gradient(colors: [Color(hex: Palette.deepSpace, opacity: 0), Color(hex: Palette.deepSpace, opacity: 0.85)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.55), endPoint: CGPoint(x: 0, y: size.height)))
    }

    nonisolated private static func drawObject(_ ctx: inout GraphicsContext, _ object: CelestialSnapshot, at center: CGPoint) {
        switch object.kind {
        case .planet:
            CelestialPainter.planet(&ctx, at: center, radius: 82, palette: .named(object.hue))
        case .moon:
            CelestialPainter.moon(&ctx, at: center, radius: 56)
        case .nebula:
            CelestialPainter.nebula(&ctx, at: center, radius: 170, hue: object.hue, seed: object.seed, intensity: 2.4)
        case .comet:
            CelestialPainter.comet(&ctx, at: CGPoint(x: center.x + 40, y: center.y - 20), angle: -0.5, length: 170, color: Color(hex: Palette.warmGold))
        case .seed:
            CelestialPainter.star(&ctx, at: center, radius: 40, points: 4, color: Color(hex: Palette.warmGold), brightness: 1.2, flare: true)
        case .star, .constellation:
            ctx.blendMode = .plusLighter
            CelestialPainter.star(&ctx, at: center, radius: 40, points: object.category?.starPoints ?? 4,
                                  color: CelestialPainter.color(forHue: object.hue), brightness: 1.3, flare: true)
        }
    }
}

/// The small "✦ ORBI" mark at the foot of every share card.
struct ShareCardBrand: View {
    var body: some View {
        HStack(spacing: 6) {
            StarShape(points: 4, innerRatio: 0.38)
                .fill(Color(hex: Palette.warmGold))
                .frame(width: 9, height: 9)
            Text("ORBI")
                .font(.system(size: 10, weight: .semibold))
                .lmTracking(3.2)
                .foregroundStyle(Color(hex: Palette.softWhite).opacity(0.7))
        }
    }
}

// MARK: Rendering

enum ShareCardRenderer {
    /// Renders the card at 1080×1350 pixels.
    @MainActor
    static func image(for content: ShareCardContent) -> UIImage? {
        image(rendering: ShareCardView(content: content))
    }

    /// Renders any card view laid out at `ShareCardView.pointSize`.
    @MainActor
    static func image(rendering card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCardView.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @MainActor
    static func pngData(for content: ShareCardContent) -> Data? {
        image(for: content)?.pngData()
    }
}

/// The card as a shareable PNG. It renders only when the share sheet asks for
/// it, so showing a share button costs nothing.
struct ShareCardImage: Transferable {
    let content: ShareCardContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            guard let data = await ShareCardRenderer.pngData(for: card.content) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { "Orbi – \($0.content.title).png" }
    }
}

/// Share button that offers the rendered card with `caption` as the message.
struct ShareCardLink<Label: View>: View {
    let content: ShareCardContent
    let caption: String
    @ViewBuilder var label: () -> Label

    var body: some View {
        let card = ShareCardImage(content: content)
        ShareLink(item: card,
                  message: Text(verbatim: caption + "\n" + DeepLink.landingPage.absoluteString),
                  preview: SharePreview(Text(content.title), image: card),
                  label: label)
    }
}
