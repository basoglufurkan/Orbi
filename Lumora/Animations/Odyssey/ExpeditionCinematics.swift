import SwiftUI

/// Liftoff: the ship ignites on your home world, climbs through the
/// atmosphere and jumps to warp toward the new world. ~3 s, tap to skip.
struct LaunchCinematicView: View {
    var world: WorldState
    var loadout: ShipLoadout
    var onDone: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @State private var start = Date.now
    @State private var finished = false

    private var duration: Double { motion == .reduced ? 1.6 : 3.4 }

    var body: some View {
        ZStack {
            Color(hex: Palette.deepSpace).ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished)) { tl in
                let t = tl.date.timeIntervalSince(start)
                ZStack {
                    Canvas { ctx, size in
                        if motion == .reduced {
                            drawReduced(&ctx, size: size, t: t)
                        } else {
                            drawLaunch(&ctx, size: size, t: t)
                        }
                    }
                    .ignoresSafeArea()
                    VStack(spacing: LMSpace.xs) {
                        Spacer()
                        EyebrowText(String(localized: "Course set"), color: LMColor.calm)
                        Text(world.blueprint.name.isEmpty ? String(localized: "Uncharted world") : world.blueprint.name)
                            .font(LMFont.voice(.largeTitle)).foregroundStyle(.white)
                        Text("Your focus is the fuel.").font(LMFont.callout).foregroundStyle(Color(hex: 0xB9BCE3))
                    }
                    .padding(.bottom, 90)
                    .opacity(beat(t, 1.0, 1.6))
                }
                .onChange(of: t >= duration) { _, done in
                    if done, !finished { finish() }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if Date.now.timeIntervalSince(start) > 0.8 { finish() } }
        .onAppear {
            start = .now
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                app.haptics.sessionStart()
            }
            AccessibilityNotification.Announcement(String(localized: "Launched. Your focus powers the journey.")).post()
        }
        .accessibilityAction(named: Text("Skip")) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }

    private func drawLaunch(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let climb = LMCurve.easeInOutCubic.value(beat(t, 0.6, 2.0))
        // Stars rush downward as the ship climbs.
        StarFieldPainter.draw(&ctx, size: size, offset: CGPoint(x: 0, y: climb * h * 1.4), opacity: 0.9, time: t)

        // Home world sinks away below.
        let home = CGPoint(x: w / 2, y: h * 1.06 + climb * h * 0.75)
        CelestialPainter.planet(&ctx, at: home, radius: w * 0.78, palette: .named("rose"), showRing: false)

        // Warp streaks.
        let warp = beat(t, 1.7, 2.9)
        if warp > 0 {
            var rng = SeededRandom(seed: 0x00A1_7A1D)
            let c = CGPoint(x: w / 2, y: h * 0.32)
            ctx.blendMode = .plusLighter
            for _ in 0..<70 {
                let a = rng.range(0, 2 * .pi)
                let d0 = rng.range(20, Double(h) * 0.5) * (1 - warp * 0.3)
                let len = rng.range(30, 160) * warp
                let p0 = CGPoint(x: c.x + cos(a) * d0, y: c.y + sin(a) * d0)
                let p1 = CGPoint(x: c.x + cos(a) * (d0 + len), y: c.y + sin(a) * (d0 + len))
                var line = Path()
                line.move(to: p0)
                line.addLine(to: p1)
                ctx.stroke(line, with: .linearGradient(Gradient(colors: [.white.opacity(0), Color(hex: Palette.starlightCyan).opacity(0.8 * warp)]),
                                                       startPoint: p0, endPoint: p1), lineWidth: 1.4)
            }
            ctx.blendMode = .normal
            // The destination appears as a point of light.
            CelestialPainter.glow(&ctx, at: c, radius: 30 + 40 * warp, color: Color(hex: world.blueprint.palette.atmosphere), intensity: 0.6 * warp)
        }

        // The ship.
        let thrust = 0.25 + 0.75 * beat(t, 0.2, 0.7)
        let shipY = h * 0.66 - CGFloat(climb) * h * 0.3 - CGFloat(beat(t, 1.8, 2.6)) * h * 0.3
        let shake = t > 0.4 && t < 1.2 ? sin(t * 70) * 1.2 : 0
        let scale = 1 - 0.75 * beat(t, 2.0, 2.9)
        RocketPainter.draw(&ctx, loadout: loadout, center: CGPoint(x: w / 2 + shake, y: shipY),
                           length: 96 * scale, heading: 0, thrust: thrust, time: t)
    }

    private func drawReduced(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.8, time: nil)
        RocketPainter.draw(&ctx, loadout: loadout, center: CGPoint(x: size.width / 2, y: size.height * 0.45),
                           length: 96, heading: 0, thrust: 0.8, time: nil)
    }
}

/// Arrival: the ship drops out of warp, the world swells into view, the
/// ship slips into orbit, and the world reveals itself. Then the discovery.
struct ArrivalView: View {
    var expedition: ExpeditionState
    /// Runs before the world opens, e.g. to dismiss the screen underneath.
    var onExplore: () -> Void = {}
    var onDone: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @State private var start = Date.now
    @State private var showCard = false
    @State private var finished = false

    private var world: WorldState { expedition.world }
    private var cardAt: Double { motion == .reduced ? 0.8 : 5.0 }

    var body: some View {
        let loadout = app.odyssey.snapshot.loadout
        ZStack {
            Color(hex: Palette.deepSpace).ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished)) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    if motion == .reduced {
                        drawReduced(&ctx, size: size)
                    } else {
                        drawArrival(&ctx, size: size, t: t, loadout: loadout,
                                    wall: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                .ignoresSafeArea()
            }
            if showCard {
                DiscoveryCard(world: world) {
                    onExplore()
                    app.odysseyFocusWorld = world.ordinal
                    app.selectedTab = .odyssey
                    close()
                } onContinue: { close() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { revealCard() }
        .task {
            start = .now
            app.haptics.playCelebration(milestone: world.blueprint.rarity == .legendary, reduced: motion == .reduced)
            app.audio.play(world.blueprint.rarity == .legendary ? .milestone : .gentleCelebration)
            try? await Task.sleep(for: .seconds(cardAt))
            revealCard()
        }
        .accessibilityAction(named: Text("Skip")) { revealCard() }
    }

    private func revealCard() {
        guard !showCard else { return }
        withAnimation(LMSpring.settle) { showCard = true }
        app.haptics.success()
        AccessibilityNotification.Announcement(String(localized: "You landed on \(world.blueprint.name)")).post()
    }

    private func close() {
        finished = true
        onDone()
    }

    private func drawArrival(_ ctx: inout GraphicsContext, size: CGSize, t: Double, loadout: ShipLoadout, wall: Double) {
        let w = size.width, h = size.height
        let bp = world.blueprint
        let planetCenter = CGPoint(x: w / 2, y: h * 0.34)

        // 0–1.3 s: decelerating warp.
        let decel = 1 - beat(t, 0, 1.3)
        StarFieldPainter.draw(&ctx, size: size, offset: CGPoint(x: 0, y: wall * 6), opacity: 0.9, time: wall)
        if decel > 0 {
            var rng = SeededRandom(seed: 0x0A11_1BED)
            ctx.blendMode = .plusLighter
            for _ in 0..<60 {
                let a = rng.range(0, 2 * .pi)
                let d0 = rng.range(30, Double(h) * 0.55)
                let len = rng.range(40, 200) * decel
                let p0 = CGPoint(x: planetCenter.x + cos(a) * d0, y: planetCenter.y + sin(a) * d0)
                let p1 = CGPoint(x: planetCenter.x + cos(a) * (d0 + len), y: planetCenter.y + sin(a) * (d0 + len))
                var line = Path()
                line.move(to: p0)
                line.addLine(to: p1)
                ctx.stroke(line, with: .color(Color(hex: Palette.starlightCyan).opacity(0.6 * decel)), lineWidth: 1.2)
            }
            ctx.blendMode = .normal
        }

        // 0.8–3.2 s: the world swells from a point to fill the sky.
        let grow = LMCurve.easeOutCubic.value(beat(t, 0.8, 3.2))
        let radius = 6 + (w * 0.3 - 6) * CGFloat(grow)
        // 2.6–4.4 s: the silhouette turns into the real world.
        let reveal = beat(t, 2.6, 4.4)
        if reveal < 1 {
            WorldPainter.draw(&ctx, world: bp, center: planetCenter, radius: radius, stage: world.stage, time: wall, silhouette: true)
        }
        if reveal > 0 {
            var lit = ctx
            lit.opacity = reveal
            WorldPainter.draw(&lit, world: bp, center: planetCenter, radius: radius, stage: world.stage, time: wall)
        }
        // 4.4 s: signal received — a soft bloom.
        let flash = beat(t, 4.3, 5.2)
        if flash > 0, flash < 1 {
            ctx.blendMode = .plusLighter
            CelestialPainter.glow(&ctx, at: planetCenter, radius: radius * 2.6, color: Color(hex: bp.palette.atmosphere),
                                  intensity: 0.5 * sin(.pi * flash))
            ctx.blendMode = .normal
        }

        // Ship: rises from below, then slips into an orbit around the world.
        let approach = LMCurve.easeOutCubic.value(beat(t, 0.4, 2.6))
        let orbitR = radius * 1.55
        let orbitStart = CGPoint(x: planetCenter.x - orbitR, y: planetCenter.y + orbitR * 0.35)
        let from = CGPoint(x: w / 2, y: h * 1.05)
        var ship = lerp(from, orbitStart, approach)
        var heading = atan2(orbitStart.x - from.x, -(orbitStart.y - from.y))
        if t > 2.6 {
            let a = Double.pi + (t - 2.6) * 0.9
            ship = CGPoint(x: planetCenter.x + cos(a) * orbitR, y: planetCenter.y - sin(a) * orbitR * 0.35)
            // Tangent of the ellipse, so the ship faces where it is going.
            let dx = -sin(a) * orbitR, dy = -cos(a) * orbitR * 0.35
            heading = atan2(dx, -dy)
        }
        let behind = t > 2.6 && sin(Double.pi + (t - 2.6) * 0.9) < 0 && t > 3.5
        if !behind {
            RocketPainter.draw(&ctx, loadout: loadout, center: ship, length: 38 + 20 * (1 - approach),
                               heading: heading, thrust: 0.9 - 0.5 * beat(t, 2.4, 3.4), time: wall)
        }
    }

    private func drawReduced(_ ctx: inout GraphicsContext, size: CGSize) {
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.8, time: nil)
        WorldPainter.draw(&ctx, world: world.blueprint, center: CGPoint(x: size.width / 2, y: size.height * 0.34),
                          radius: size.width * 0.3, stage: world.stage, time: nil)
    }
}

/// The discovery card shown after landing.
private struct DiscoveryCard: View {
    var world: WorldState
    var onExplore: () -> Void
    var onContinue: () -> Void

    var body: some View {
        let bp = world.blueprint
        let find = WorldLexicon.find(bp.findIndex)
        VStack(alignment: .leading, spacing: LMSpace.s) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                EyebrowText(String(localized: "Signal received · \(bp.archetype.displayName)"), color: LMColor.calm)
                RarityChip(rarity: bp.rarity)
            }
            Text(bp.name).font(LMFont.voice(.largeTitle)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(WorldLexicon.lore(bp.archetype, variant: bp.loreVariant))
                .font(LMFont.body).foregroundStyle(Color(hex: 0xB9BCE3))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: LMSpace.m) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(LMColor.reward)
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText(String(localized: "Found · \(find.kindLabel)"), color: LMColor.reward)
                    Text(find.title).font(LMFont.headline).foregroundStyle(.white)
                    Text(find.detail).font(LMFont.callout).foregroundStyle(Color(hex: 0xB9BCE3))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Added to your Codex").font(LMFont.footnote).foregroundStyle(LMColor.calm)
                }
            }
            .padding(LMSpace.m)
            .glassCard(border: LMColor.rewardFill.opacity(0.35))
            CosmicButton(title: "Explore \(bp.name)", systemImage: "scope", kind: .reward) { onExplore() }
                .accessibilityIdentifier("arrival.explore")
            Button(String(localized: "Continue")) { onContinue() }
                .font(LMFont.headline.weight(.medium)).foregroundStyle(Color(hex: 0xB9BCE3))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(LMSpace.l)
        // The scrim starts below the world (centred at 34%, radius 0.3 × width),
        // so the reveal stays bright while the text stays readable.
        .background(LinearGradient(stops: [.init(color: .clear, location: 0.44),
                                           .init(color: Color(hex: Palette.deepSpace).opacity(0.85), location: 0.56),
                                           .init(color: Color(hex: Palette.deepSpace), location: 0.7)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}
