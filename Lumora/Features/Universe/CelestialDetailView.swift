import SwiftData
import SwiftUI

/// Inspecting a light: what made it, when, and a note for future you.
struct CelestialDetailView: View {
    let object: CelestialSnapshot

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [FocusSession]
    @Query private var objects: [CelestialObject]
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    init(object: CelestialSnapshot) {
        self.object = object
        let sessionID = object.sourceSessionID ?? UUID()
        _sessions = Query(filter: #Predicate<FocusSession> { $0.id == sessionID })
        let day = object.dayKey.rawValue
        let star = CelestialKind.star.rawValue
        _objects = Query(filter: #Predicate<CelestialObject> { $0.dayKeyRaw == day && $0.kindRaw == star },
                         sort: \CelestialObject.ordinal)
    }

    private var session: FocusSession? { object.kind == .star ? sessions.first : nil }

    var body: some View {
        ZStack(alignment: .top) {
            LMColor.bgBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    hero.frame(height: 280)
                    VStack(alignment: .leading, spacing: LMSpace.m) {
                        eyebrow
                        title
                        Text(summaryLine)
                            .font(LMFont.body)
                            .foregroundStyle(LMColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let session { facts(session) }
                        if object.kind == .star { constellationCard }
                        if let session { noteEditor(session) }
                    }
                    .padding(LMSpace.l)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Solid backings keep the floating controls legible over text
            // scrolling beneath them.
            HStack {
                RoundControlButton(systemImage: "chevron.down", label: "Close", size: 48) { dismiss() }
                    .background(Circle().fill(LMColor.bgBase.opacity(0.85)).frame(width: 48, height: 48))
                Spacer()
                ShareCardLink(content: shareCard, caption: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LMColor.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(LMColor.bgBase.opacity(0.85)))
                        .overlay(Circle().strokeBorder(LMColor.hairline, lineWidth: 1))
                }
                .accessibilityLabel(Text("Share"))
            }
            .padding(LMSpace.m)
        }
        .onAppear { note = session?.note ?? "" }
        .onDisappear(perform: saveNote)
        .telemetryScreen("celestial_detail")
        .onAppear { Telemetry.log(.celestialOpened(kind: object.kind.rawValue)) }
    }

    // MARK: Hero

    private var hero: some View {
        let todays = objects.map(CelestialSnapshot.init)
        return Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
            CelestialPainter.glow(&ctx, at: center, radius: size.width * 0.6, color: Color(hex: Palette.cosmicViolet), intensity: 0.35)
            StarFieldPainter.draw(&ctx, size: size, opacity: 0.8, time: nil)
            switch object.kind {
            case .planet:
                CelestialPainter.planet(&ctx, at: center, radius: 78, palette: .named(object.hue))
            case .moon:
                CelestialPainter.moon(&ctx, at: center, radius: 48)
            case .nebula:
                CelestialPainter.nebula(&ctx, at: center, radius: 200, hue: object.hue, seed: object.seed, intensity: 2.4)
            case .comet:
                CelestialPainter.comet(&ctx, at: center, angle: -0.5, length: 160, color: Color(hex: Palette.warmGold))
            case .seed:
                CelestialPainter.star(&ctx, at: center, radius: 30, points: 4, color: Color(hex: Palette.warmGold), brightness: 1.2, flare: true)
            case .star, .constellation:
                // The star with its same-day neighbours, connected.
                let others = todays.filter { $0.id != object.id }
                let scale: Double = 1.6
                func map(_ p: WorldPoint) -> CGPoint {
                    CGPoint(x: center.x + (p.x - object.position.x) * scale, y: center.y + (p.y - object.position.y) * scale)
                }
                var path = Path()
                for (i, s) in todays.enumerated() {
                    if i == 0 { path.move(to: map(s.position)) } else { path.addLine(to: map(s.position)) }
                }
                ctx.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1)
                ctx.blendMode = .plusLighter
                for s in others {
                    let p = map(s.position)
                    CelestialPainter.star(&ctx, at: p, radius: 7, points: s.category?.starPoints ?? 4,
                                          color: CelestialPainter.color(forHue: s.hue), brightness: 0.75)
                    ctx.draw(Text("#\(s.ordinal)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: Palette.warmGold)),
                             at: CGPoint(x: p.x, y: p.y + 20))
                }
                CelestialPainter.star(&ctx, at: center, radius: 30, points: object.category?.starPoints ?? 4,
                                      color: CelestialPainter.color(forHue: object.hue), brightness: 1.3, flare: true)
            }
        }
        .background(LMColor.bgBase)
        .accessibilityHidden(true)
    }

    // MARK: Text

    private var eyebrow: some View {
        HStack(spacing: 6) {
            if let c = object.category { CategoryGlyph(category: c, size: 12) }
            EyebrowText(eyebrowText, color: object.category?.color ?? LMColor.calm)
        }
    }

    private var eyebrowText: String {
        switch object.kind {
        case .star: "\(String(localized: "Star")) #\(object.ordinal) · \(object.category?.displayName ?? "")"
        case .planet: String(localized: "World \(object.ordinal)")
        case .seed: String(localized: "Your first star")
        default: object.kind.displayName
        }
    }

    private var title: some View {
        let date = object.bornAt.formatted(.dateTime.month(.wide).day())
        let subject: String = {
            switch object.kind {
            case .star:
                if let intention = session?.intention, !intention.isEmpty { return intention }
                return object.category?.displayName ?? ""
            case .seed: return String(localized: "First Light")
            default: return object.name
            }
        }()
        return (Text("\(date) — ").font(LMFont.largeTitle) + Text(subject).font(LMFont.voice(.largeTitle)))
            .foregroundStyle(LMColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private var summaryLine: String {
        switch object.kind {
        case .star:
            guard let s = session else { return String(localized: "\(object.focusedMinutes) minutes of focus.") }
            let category = s.category.inlineName
            return s.outcome == .completed
                ? String(localized: "\(s.focusedMinutes) minutes of focus. You completed your \(category) session.")
                : String(localized: "\(s.focusedMinutes) minutes of focus. Ended early — still yours.")
        case .seed: return String(localized: "The small star you were given. Everything began here.")
        case .planet: return String(localized: "Born from \(app.rules.planetMilestones[safe: object.ordinal - 1] ?? 0) sessions of light. A place you can return to forever.")
        case .moon: return String(localized: "Captured by a world after a season of steady focus.")
        case .nebula: return String(localized: "Painted by a week of rhythm. Consistency, not volume, colors the sky.")
        case .comet: return String(localized: "Marks \(object.ordinal) hours of focus — a personal record crossing the sky.")
        case .constellation: return object.name
        }
    }

    private func facts(_ s: FocusSession) -> some View {
        AdaptiveStack(spacing: LMSpace.s) {
            StatisticsCardView(title: String(localized: "Started"), value: LMFormat.time(s.startedAt), fillsHeight: true)
            StatisticsCardView(title: String(localized: "Intention"), value: s.intention.isEmpty ? "—" : s.intention, valueLines: 2, fillsHeight: true)
            StatisticsCardView(title: String(localized: "Pauses"),
                               value: s.pauseCount == 0 ? String(localized: "None") : "\(s.pauseCount)", fillsHeight: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var constellationCard: some View {
        let index = (objects.firstIndex(where: { $0.id == object.id }) ?? 0)
        let n = app.rules.starsPerConstellation
        let position = index % n + 1
        let groupCount = min(n, objects.count - (index / n) * n)
        let text: String = position == 1
            ? String(localized: "First light of \(dayName)'s constellation · \(groupCount) of \(n) stars")
            : String(localized: "Star \(position) of \(dayName)'s constellation · \(groupCount) of \(n) stars")
        return HStack(spacing: LMSpace.s) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(LMColor.textSecondary)
                .accessibilityHidden(true)
            Text(text).font(LMFont.callout.weight(.regular)).foregroundStyle(LMColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(LMSpace.m)
        .glassCard(radius: 22)
    }

    private var dayName: String {
        object.dayKey == app.today ? String(localized: "today") : LMFormat.shortDate(object.bornAt)
    }

    private func noteEditor(_ s: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "A note for future you"))
            TextField(String(localized: "What did this session mean?"), text: $note, axis: .vertical)
                .lineLimit(2...6)
                .font(LMFont.body)
                .foregroundStyle(LMColor.textPrimary)
                .focused($noteFocused)
                .padding(LMSpace.m)
                .glassCard(radius: 20)
                .onSubmit(saveNote)
        }
    }

    private func saveNote() {
        guard let s = session, s.note != note else { return }
        s.note = note
        app.dataStore.save()
    }

    private var shareCard: ShareCardContent {
        let date = object.bornAt.formatted(.dateTime.month(.wide).day().year())
        let title: String = switch object.kind {
        case .star:
            if let intention = session?.intention, !intention.isEmpty { intention } else { object.category?.displayName ?? object.kind.displayName }
        case .seed: String(localized: "First Light")
        default: object.name
        }
        let stat: String = switch object.kind {
        case .star: String(localized: "\(object.focusedMinutes) minutes of focus · \(date)")
        default: String(localized: "Born \(date)")
        }
        return ShareCardContent(subject: .celestial(object), eyebrow: eyebrowText, title: title, stat: stat,
                                accent: object.kind == .star ? (object.category?.hex ?? Palette.starlightCyan) : Palette.warmGold)
    }

    private var shareText: String {
        switch object.kind {
        case .star: String(localized: "Star #\(object.ordinal) in my Orbi universe — \(object.focusedMinutes) minutes of focus. ✦")
        case .planet: String(localized: "\(object.name), a world in my Orbi universe. ✦")
        default: String(localized: "A piece of my Orbi universe. ✦")
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
