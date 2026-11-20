import SwiftUI
import UniformTypeIdentifiers

/// One page of the year-in-review story.
enum YearCard: Hashable, Sendable {
    case intro, total, brightestDay, longestSession, topCategory, rhythm, odyssey, rank, finale

    /// The pages this year has something to say on, in story order.
    static func cards(for review: YearReview) -> [YearCard] {
        var cards: [YearCard] = [.intro, .total]
        if review.brightestDay != nil { cards.append(.brightestDay) }
        if review.longestSession != nil { cards.append(.longestSession) }
        if review.topCategory != nil { cards.append(.topCategory) }
        if review.longestRun >= 2 { cards.append(.rhythm) }
        if review.worldsCharted > 0 || review.rareEvents > 0 { cards.append(.odyssey) }
        cards += [.rank, .finale]
        return cards
    }
}

/// A story card, laid out for 9:16. The same view is shown in the story and
/// rendered at 1080×1920 for sharing, always dark.
struct YearCardView: View {
    static let pointSize = CGSize(width: 360, height: 640)

    var card: YearCard
    var review: YearReview
    var scene: UniverseScene
    /// Room under the words; the story leaves space for its Share button.
    var bottomInset: CGFloat = 56

    var body: some View {
        ZStack {
            Canvas { ctx, size in Self.drawBackdrop(&ctx, size: size, card: card, review: review, scene: scene) }
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                Text(eyebrow.localizedUppercase)
                    .font(LMFont.eyebrow).lmTracking(1.6)
                    .foregroundStyle(Color(hex: accent))
                if let big {
                    Text(big)
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .foregroundStyle(Color(hex: 0xFFF1D6))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Text(title)
                    .font(LMFont.voice(.title))
                    .foregroundStyle(Color(hex: 0xFFF1D6))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(LMFont.callout)
                        .foregroundStyle(Color(hex: 0xB9BCE3))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ShareCardBrand().padding(.top, 18)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(hex: Palette.deepSpace))
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    // MARK: Words

    private var eyebrow: String {
        switch card {
        case .intro: String(localized: "Your year in light")
        case .total: String(localized: "Focus")
        case .brightestDay: String(localized: "Your brightest day")
        case .longestSession: String(localized: "Your longest session")
        case .topCategory: String(localized: "Where your light went")
        case .rhythm: String(localized: "Your rhythm")
        case .odyssey: String(localized: "The Odyssey")
        case .rank: String(localized: "Navigator")
        case .finale: String(localized: "Your universe")
        }
    }

    private var big: String? {
        switch card {
        case .intro: String(review.year)
        case .total: LMFormat.minutes(review.totalMinutes)
        case .brightestDay: review.brightestDay.map { LMFormat.minutes($0.minutes) }
        case .longestSession: review.longestSession.map { String(localized: "\($0.minutes) min") }
        case .topCategory: review.topCategory.map { $0.fraction.formatted(.percent.precision(.fractionLength(0))) }
        case .rhythm: String(review.longestRun)
        case .odyssey: review.worldsCharted > 0 ? String(review.worldsCharted) : String(review.rareEvents)
        case .rank, .finale: nil
        }
    }

    private var title: String {
        switch card {
        case .intro:
            String(localized: "A year of your own stars.")
        case .total:
            review.sessions == 1 ? String(localized: "of focus, in 1 session.")
                : String(localized: "of focus, in \(review.sessions) sessions.")
        case .brightestDay:
            review.brightestDay.map { String(localized: "on \($0.date.formatted(.dateTime.month(.wide).day())).") } ?? ""
        case .longestSession:
            review.longestSession.map { String(localized: "of \($0.category.inlineName), without letting go.") } ?? ""
        case .topCategory:
            review.topCategory.map { String(localized: "of your light went to \($0.category.inlineName).") } ?? ""
        case .rhythm:
            String(localized: "days in a row. Steady light.")
        case .odyssey:
            review.worldsCharted == 1 ? String(localized: "world charted.")
                : review.worldsCharted > 0 ? String(localized: "worlds charted.")
                : String(localized: "rare events witnessed.")
        case .rank:
            review.rank.title
        case .finale:
            String(localized: "Every light here is a moment you chose to focus.")
        }
    }

    private var detail: String? {
        switch card {
        case .intro:
            String(localized: "Here's what your focus became.")
        case .total:
            review.activeDays == 1 ? String(localized: "1 day of light")
                : String(localized: "\(review.activeDays) days of light")
        case .longestSession:
            review.longestSession.map { $0.date.formatted(.dateTime.month(.wide).day()) }
        case .odyssey:
            [review.firstWorldName.map { String(localized: "First landing: \($0)") },
             review.worldsCharted > 0 && review.rareEvents > 0
                ? (review.rareEvents == 1 ? String(localized: "1 rare event witnessed") : String(localized: "\(review.rareEvents) rare events witnessed"))
                : nil]
                .compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        case .rank:
            String(localized: "Rank \(review.rank.level)") + (review.horizons > 0
                ? " · " + (review.horizons == 1 ? String(localized: "1 horizon reached") : String(localized: "\(review.horizons) horizons reached"))
                : "")
        case .finale:
            String(localized: "\(review.sessions) stars this year")
        default:
            nil
        }
    }

    private var accent: UInt32 {
        switch card {
        case .intro, .rank, .finale: Palette.warmGold
        case .total, .rhythm: Palette.starlightCyan
        case .brightestDay, .longestSession: Palette.warmGold
        case .topCategory: Palette.nebulaPink
        case .odyssey: Palette.starlightCyan
        }
    }

    // MARK: Art

    nonisolated private static func drawBackdrop(_ ctx: inout GraphicsContext, size: CGSize, card: YearCard,
                                                 review: YearReview, scene: UniverseScene) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: Palette.deepSpace)))
        let art = CGPoint(x: size.width / 2, y: size.height * 0.34)
        var glow = ctx
        glow.blendMode = .plusLighter
        let tint: UInt32 = card == .topCategory ? Palette.nebulaPink : (card == .total || card == .rhythm ? Palette.starlightCyan : Palette.cosmicViolet)
        CelestialPainter.glow(&glow, at: art, radius: size.width * 0.9, color: Color(hex: tint), intensity: 0.32)
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.85, time: nil)

        switch card {
        case .intro, .brightestDay:
            // A constellation of the year's brightest moments.
            var rng = SeededRandom(seed: UInt64(review.year) &* 7_919 &+ (card == .brightestDay ? 101 : 0))
            let points = (0..<7).map { _ in CGPoint(x: art.x + rng.range(-120, 120), y: art.y + rng.range(-90, 90)) }
                .sorted { $0.x < $1.x }
            var line = Path()
            line.addLines(points)
            ctx.stroke(line, with: .color(.white.opacity(0.35)), lineWidth: 1)
            for (i, p) in points.enumerated() {
                CelestialPainter.star(&glow, at: p, radius: i == 3 ? 16 : 7, points: 4,
                                      color: Color(hex: i == 3 ? Palette.warmGold : 0xE9E4FF), brightness: 1.2, flare: i == 3)
            }
        case .total:
            var rng = SeededRandom(seed: 0x70_7A1)
            for _ in 0..<min(220, max(12, review.sessions)) {
                let a = rng.range(0, 2 * .pi), d = rng.range(0, 1).squareRoot() * 150
                CelestialPainter.star(&glow, at: CGPoint(x: art.x + cos(a) * d, y: art.y + sin(a) * d * 0.8),
                                      radius: rng.range(1.5, 4), points: 4,
                                      color: CelestialPainter.color(forHue: FocusCategory.allCases[Int(rng.range(0, 4.99))].rawValue),
                                      brightness: 1, flare: false, detailed: false)
            }
        case .longestSession:
            for ring in 0..<3 {
                let r = CGFloat(60 + ring * 34)
                ctx.stroke(Path(ellipseIn: CGRect(x: art.x - r, y: art.y - r * 0.4, width: r * 2, height: r * 0.8)),
                           with: .color(.white.opacity(0.14 - Double(ring) * 0.03)), lineWidth: 1)
            }
            CelestialPainter.planet(&ctx, at: art, radius: 52, palette: .named(review.longestSession?.category.rawValue ?? "work"))
        case .topCategory:
            CelestialPainter.star(&glow, at: art, radius: 54, points: review.topCategory?.category.starPoints ?? 4,
                                  color: CelestialPainter.color(forHue: review.topCategory?.category.rawValue ?? "work"),
                                  brightness: 1.3, flare: true)
        case .rhythm:
            let n = min(review.longestRun, 30)
            let cols = min(n, 10), rows = Int((Double(n) / 10).rounded(.up))
            for i in 0..<n {
                let x = art.x + (CGFloat(i % 10) - CGFloat(cols - 1) / 2) * 26
                let y = art.y + (CGFloat(i / 10) - CGFloat(rows - 1) / 2) * 30
                CelestialPainter.star(&glow, at: CGPoint(x: x, y: y), radius: 6, points: 4,
                                      color: Color(hex: Palette.starlightCyan), brightness: 1, flare: false, detailed: false)
            }
        case .odyssey:
            CelestialPainter.planet(&ctx, at: art, radius: 70, palette: .named("coding"))
            CelestialPainter.comet(&glow, at: CGPoint(x: art.x + 100, y: art.y - 80), angle: 2.5, length: 120,
                                   color: Color(hex: Palette.warmGold))
        case .rank:
            var insignia = ctx
            insignia.translateBy(x: art.x - 90, y: art.y - 90)
            RankInsignia.draw(&insignia, in: CGSize(width: 180, height: 180), level: review.rank.level, time: 0)
        case .finale:
            let sky = CGSize(width: size.width, height: size.height * 0.62)
            let points = scene.all.map(\.position) + scene.voyages.map(\.position) + scene.galaxies.map(\.center)
            let camera = UniverseCamera.fitting(points.isEmpty ? [.zero] : points, in: sky, padding: 30, zoomRange: 0.1...1.2)
            UniverseRenderer.draw(&ctx, size: sky, scene: scene, camera: camera,
                                  options: .init(time: nil, dark: true, showLabels: false, showGhost: false,
                                                 minimumStarRadius: 3, minimumPlanetRadius: 13, alwaysDetailed: true))
            ctx.blendMode = .normal
        }
        // A floor so the words sit on darker sky.
        ctx.fill(Path(CGRect(x: 0, y: size.height * 0.5, width: size.width, height: size.height * 0.5)),
                 with: .linearGradient(Gradient(colors: [Color(hex: Palette.deepSpace, opacity: 0), Color(hex: Palette.deepSpace, opacity: 0.9)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.5), endPoint: CGPoint(x: 0, y: size.height)))
    }
}

/// A story card as a 1080×1920 PNG, rendered when the share sheet asks.
struct YearCardImage: Transferable {
    var card: YearCard
    var review: YearReview
    var scene: UniverseScene

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            let data = await MainActor.run { () -> Data? in
                let renderer = ImageRenderer(content: YearCardView(card: item.card, review: item.review, scene: item.scene)
                    .frame(width: YearCardView.pointSize.width, height: YearCardView.pointSize.height))
                renderer.scale = 3
                renderer.isOpaque = true
                return renderer.uiImage?.pngData()
            }
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName { "Orbi – \($0.review.year).png" }
    }
}

/// The story: tap to move on, hold still and it moves on by itself.
struct YearInReviewView: View {
    var review: YearReview
    var scene: UniverseScene
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionLevel) private var motion
    @State private var index = 0
    @State private var pageStart = Date.now

    static let pageSeconds = 6.0

    var body: some View {
        let cards = YearCard.cards(for: review)
        let card = cards[min(index, cards.count - 1)]
        ZStack(alignment: .top) {
            YearCardView(card: card, review: review, scene: scene, bottomInset: 120)
                .id(card)
                .transition(.opacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    value.location.x < 120 ? go(-1, count: cards.count) : go(1, count: cards.count)
                })
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("Next")) { go(1, count: cards.count) }
                .accessibilityAction(named: Text("Previous")) { go(-1, count: cards.count) }
                .accessibilityIdentifier("year.card")

            VStack(spacing: LMSpace.s) {
                progress(count: cards.count)
                HStack {
                    Spacer()
                    RoundControlButton(systemImage: "xmark", label: "Close", size: 40) { dismiss() }
                        .accessibilityIdentifier("year.close")
                }
                Spacer()
                ShareLink(item: YearCardImage(card: card, review: review, scene: scene),
                          message: Text(verbatim: String(localized: "My year in Orbi ✦") + "\n" + DeepLink.landingPage.absoluteString),
                          preview: SharePreview(Text("My year in light"), image: YearCardImage(card: card, review: review, scene: scene))) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 48))
                .simultaneousGesture(TapGesture().onEnded { Telemetry.log(.yearReviewShared) })
                .padding(.horizontal, LMSpace.xl)
                .accessibilityIdentifier("year.share")
            }
            .padding(.horizontal, LMSpace.m)
            .padding(.bottom, LMSpace.xs)
        }
        .background(Color(hex: Palette.deepSpace))
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task(id: index) {
            pageStart = .now
            guard motion.animatesContinuously else { return }
            try? await Task.sleep(for: .seconds(Self.pageSeconds))
            if !Task.isCancelled, index < cards.count - 1 { go(1, count: cards.count) }
        }
        .telemetryScreen("year_review")
    }

    private func progress(count: Int) -> some View {
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !motion.animatesContinuously)) { tl in
            let f = min(1, tl.date.timeIntervalSince(pageStart) / Self.pageSeconds)
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule().fill(Color.white)
                                .frame(width: geo.size.width * (i < index ? 1 : (i == index ? (motion.animatesContinuously ? f : 1) : 0)))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .padding(.top, LMSpace.xs)
        .accessibilityHidden(true)
    }

    private func go(_ step: Int, count: Int) {
        let next = index + step
        guard next >= 0, next < count else {
            if next >= count { dismiss() }
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) { index = next }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
