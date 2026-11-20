import SwiftUI

/// Draws one frame of the completion sequence at time `t` (seconds since
/// zero). Pure function of (t, plan, layout) — no state, no side effects —
/// which is what keeps the cinematic deterministic, skippable and safe to
/// interrupt at any frame.
enum CelebrationRenderer {
    static func draw(_ ctx: inout GraphicsContext, t: Double, plan: CelebrationPlan, layout L: CelebrationLayout,
                     particles: [CelebrationParticle], planetPalette: CelestialPainter.PlanetPalette?, dark: Bool, ambientTime: Double?) {
        switch plan.kind {
        case .tooShort: drawTooShort(&ctx, t: t, L: L)
        case .reduced: drawReduced(&ctx, t: t, plan: plan, L: L, ambientTime: ambientTime)
        case .standard, .endedEarly, .milestone:
            drawFull(&ctx, t: t, plan: plan, L: L, particles: particles, planetPalette: planetPalette, dark: dark, ambientTime: ambientTime)
        }
    }

    // MARK: Full sequence

    private static func drawFull(_ ctx: inout GraphicsContext, t: Double, plan: CelebrationPlan, L: CelebrationLayout,
                                 particles: [CelebrationParticle], planetPalette: CelestialPainter.PlanetPalette?,
                                 dark: Bool, ambientTime: Double?) {
        let s = plan.scale
        let milestone = plan.kind == .milestone
        let gold = Color(hex: Palette.warmGold)
        let camE = milestone ? 0 : LMCurve.easeInOutCubic.value(beat(t, 2.8, 3.8))
        let worldScale = 3.2 + (1 - 3.2) * camE

        // Background stars with 3-layer parallax during the camera move.
        let travel = CGPoint(x: (L.origin.x - L.starFinal.x) * (1 - camE) * 2.4, y: (L.origin.y - L.starFinal.y) * (1 - camE) * 2.4)
        StarFieldPainter.draw(&ctx, size: L.size, offset: travel, opacity: (dark ? 0.85 : 0.45) * (1 - 0.2 * beat(t, 0.4, 0.9) * (1 - beat(t, 0.9, 1.6))),
                              time: ambientTime, tint: dark ? .white : Color(hex: 0x5B4BE0))

        if dark { ctx.blendMode = .plusLighter }

        // 09 · Environment glows (+12%), permanent.
        let envU = LMCurve.easeOutQuad.value(beat(t, 4.2, 5.0))
        let envCenter = milestone ? L.origin : L.starFinal
        CelestialPainter.glow(&ctx, at: envCenter, radius: L.size.width * 0.75, color: Color(hex: Palette.cosmicViolet),
                              intensity: (0.10 + 0.12 * envU) * (t > 2.8 ? 1 : beat(t, 2.0, 2.8)))

        // 01–02 · Ring closes in gold, then fades to 50% and away.
        let ringOpacity = t < 0.12 ? 1 : (t < 0.5 ? 1 - 0.5 * beat(t, 0.12, 0.5) : 0.5 * (1 - beat(t, 0.5, 0.9)))
        if ringOpacity > 0.01 {
            ctx.blendMode = .normal
            OrbitalProgressView.draw(&ctx, center: L.origin, radius: L.ringRadius, progress: 1, lineWidth: 2.5,
                                     trackWidth: 1.5, headSize: 0, trackColor: .white.opacity(0.08), opacity: ringOpacity)
            if dark { ctx.blendMode = .plusLighter }
        }

        // 03 · Contract: core 1 → 0.5 (anticipate), +40% brightness; gone by 1.05.
        if t < 1.05 {
            let c = beat(t, 0.4, 0.9)
            let coreScale = 1 - 0.5 * LMCurve.anticipate.value(c)
            let fade = 1 - beat(t, 0.9, 1.05)
            var core = ctx
            core.opacity = fade
            GlowingCelestialBodyView.draw(&core, center: L.origin, progress: 1, tint: L.starColor, warmth: 1,
                                          breath: 1, dimmed: false, scale: coreScale, brightness: 1 + 0.4 * c)
        }

        // 04 · Light wave (0.90–2.10) + screen bloom.
        let waveU = beat(t, 0.9, 2.1)
        if waveU > 0, waveU < 1 {
            let r = L.ringRadius * (0.1 + 4.1 * LMCurve.easeOutExpo.value(waveU)) * (0.6 + 0.4 * s)
            ctx.stroke(Path(ellipseIn: CGRect(x: L.origin.x - r, y: L.origin.y - r, width: r * 2, height: r * 2)),
                       with: .color(gold.opacity(0.9 * (1 - waveU))), lineWidth: 2.5 - 1.5 * waveU)
            ctx.stroke(Path(ellipseIn: CGRect(x: L.origin.x - r * 0.92, y: L.origin.y - r * 0.92, width: r * 1.84, height: r * 1.84)),
                       with: .color(Color.white.opacity(0.35 * (1 - waveU))), lineWidth: 6 * (1 - waveU))
        }
        let bloomU = beat(t, 0.9, 1.7)
        if bloomU > 0, bloomU < 1 {
            CelestialPainter.glow(&ctx, at: L.origin, radius: L.size.height * 0.55, color: gold,
                                  intensity: 0.55 * s * (1 - LMCurve.easeOutQuad.value(bloomU)))
        }

        // 05–06 · Particles: radial impulse with drag, then spiral into the attractor.
        if t >= 1.0, t < 2.8 {
            let k = 3.2
            let gatherU = LMCurve.easeInOutCubic.value(beat(t, 1.9, 2.8))
            let burstT = min(t - 1.0, 0.9)
            for p in particles {
                let travel = p.speed / k * (1 - exp(-k * burstT)) * (0.55 + 0.45 * s)
                var dx = cos(p.angle) * travel, dy = sin(p.angle) * travel
                if gatherU > 0 {
                    let rot = gatherU * p.swirl
                    let rx = dx * cos(rot) - dy * sin(rot), ry = dx * sin(rot) + dy * cos(rot)
                    dx = rx * (1 - gatherU); dy = ry * (1 - gatherU)
                }
                let pos = CGPoint(x: L.origin.x + dx, y: L.origin.y + dy)
                let alpha = beat(t, 1.0, 1.12) * (1 - 0.7 * gatherU)
                let r = p.radius * (1 - 0.4 * gatherU)
                ctx.fill(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)),
                         with: .color(p.color.opacity(alpha)))
            }
        }

        if milestone {
            drawPlanetBirth(&ctx, t: t, L: L, palette: planetPalette ?? .named("rose"), dark: dark)
            ctx.blendMode = .normal
            return
        }

        // 07 · Camera travels home: dolly-out ×3.2 with lateral pan.
        let starPos = lerp(L.origin, L.starFinal, camE)
        func neighborScreen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: starPos.x + (p.x - L.starFinal.x) * worldScale, y: starPos.y + (p.y - L.starFinal.y) * worldScale)
        }
        let neighborAlpha = beat(t, 2.9, 3.6)
        let twinkle = ambientTime.map { 0.9 + 0.1 * sin($0 * 1.3) } ?? 1

        // 08 · Constellation lines (existing, then the new one draws in 0.6 s).
        if neighborAlpha > 0, !L.neighbors.isEmpty {
            ctx.blendMode = .normal
            let lineColor = (dark ? Color.white : Color(hex: 0x5B4BE0)).opacity(0.45 * neighborAlpha)
            var path = Path()
            let pts = L.neighbors.map(neighborScreen)
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(lineColor), lineWidth: 1.2)
            if let prev = L.previous {
                let q = LMCurve.easeInOutCubic.value(beat(t, 3.8, 4.4))
                if q > 0 {
                    let a = neighborScreen(prev)
                    var line = Path()
                    line.move(to: a)
                    line.addLine(to: lerp(a, starPos, q))
                    let complete = L.constellationComplete ? beat(t, 4.4, 5.0) : 0
                    ctx.stroke(line, with: .color((dark ? Color.white : Color(hex: 0x5B4BE0)).opacity(0.55 + 0.3 * complete)), lineWidth: 1.4)
                    if complete > 0 {
                        ctx.stroke(path, with: .color(gold.opacity(0.35 * complete)), lineWidth: 1.4)
                    }
                }
            }
            if dark { ctx.blendMode = .plusLighter }
            for (i, p) in L.neighbors.enumerated() {
                CelestialPainter.star(&ctx, at: neighborScreen(p), radius: 6, points: L.neighborPoints[i],
                                      color: L.neighborColors[i], brightness: 0.8 * neighborAlpha * twinkle)
            }
        }

        // Next empty slot pulses once.
        if let slot = L.nextSlot, t > 4.0 {
            let u = beat(t, 4.0, 4.8)
            let r = 9 * (1 + 0.35 * sin(.pi * u))
            ctx.blendMode = .normal
            ctx.stroke(Path(ellipseIn: CGRect(x: slot.x - r, y: slot.y - r, width: r * 2, height: r * 2)),
                       with: .color((dark ? Color.white : Color(hex: 0x5B4BE0)).opacity(0.35 * beat(t, 4.0, 4.2))),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            if dark { ctx.blendMode = .plusLighter }
        }

        // 06–08 · The new star: born at 2.3 with the Bloom spring, travels, settles.
        if t >= 2.3 {
            let birth = bloomSpring((t - 2.3) / 0.6)
            let settle = t >= 3.8 ? 1 + 0.12 * sin(.pi * beat(t, 3.8, 4.25)) : 1
            let bornRadius: CGFloat = 18 * CGFloat(s)
            let r = lerp(bornRadius, L.starRadius * CGFloat(s), camE) * CGFloat(birth) * CGFloat(settle)
            // Motion streak ≤ 40 pt during travel.
            if camE > 0.02, camE < 0.98 {
                let back = lerp(L.origin, L.starFinal, max(0, camE - 0.12))
                let dx = starPos.x - back.x, dy = starPos.y - back.y
                let len = hypot(dx, dy)
                let k = len > 40 ? 40 / len : 1
                var streak = Path()
                streak.move(to: CGPoint(x: starPos.x - dx * k, y: starPos.y - dy * k))
                streak.addLine(to: starPos)
                ctx.stroke(streak, with: .linearGradient(Gradient(colors: [L.starColor.opacity(0), L.starColor.opacity(0.7)]),
                                                         startPoint: CGPoint(x: starPos.x - dx * k, y: starPos.y - dy * k), endPoint: starPos),
                           style: StrokeStyle(lineWidth: r * 0.6, lineCap: .round))
            }
            CelestialPainter.glow(&ctx, at: starPos, radius: r * 5, color: L.starColor, intensity: 0.5 * (1 - 0.4 * camE))
            CelestialPainter.star(&ctx, at: starPos, radius: max(0.1, r), points: L.starPoints, color: L.starColor,
                                  brightness: 1.2 * twinkle, flare: camE > 0.95)
        }
        ctx.blendMode = .normal
    }

    /// Milestone variant: the star joins a ring of dust that condenses into a
    /// planet (2.2 s), rings sweep in, gold rays turn slowly.
    private static func drawPlanetBirth(_ ctx: inout GraphicsContext, t: Double, L: CelebrationLayout, palette: CelestialPainter.PlanetPalette, dark: Bool) {
        let gold = Color(hex: Palette.warmGold)
        // The new world rises a little as it forms, leaving room for the headline.
        let rise = LMCurve.easeInOutCubic.value(beat(t, 2.8, 4.6))
        let c = lerp(L.origin, CGPoint(x: L.origin.x, y: L.size.height * 0.27), rise)
        let raysU = beat(t, 3.4, 4.6)
        if raysU > 0 {
            var rays = ctx
            rays.opacity = 0.16 * raysU
            let spin = t * 0.04
            for i in 0..<16 {
                let a = Double(i) / 16 * 2 * .pi + spin
                var path = Path()
                path.move(to: c)
                path.addLine(to: CGPoint(x: c.x + cos(a - 0.05) * L.size.height, y: c.y + sin(a - 0.05) * L.size.height))
                path.addLine(to: CGPoint(x: c.x + cos(a + 0.05) * L.size.height, y: c.y + sin(a + 0.05) * L.size.height))
                path.closeSubpath()
                rays.fill(path, with: .radialGradient(Gradient(colors: [gold.opacity(0.9), gold.opacity(0)]),
                                                      center: c, startRadius: 0, endRadius: L.size.height * 0.6))
            }
        }
        // Ring of dust condensing.
        let dustU = beat(t, 2.6, 5.0)
        if dustU > 0, dustU < 1 {
            var rng = SeededRandom(seed: 0xD057)
            let radius = 150 - 85 * LMCurve.easeInOutCubic.value(dustU)
            for _ in 0..<70 {
                let a = rng.range(0, 2 * .pi) + t * 0.9
                let rr = radius * rng.range(0.85, 1.15)
                let p = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr * 0.42)
                let size = rng.range(0.8, 2.2)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2)),
                         with: .color((rng.unit() > 0.5 ? gold : Color.white).opacity(0.75 * (1 - dustU * 0.6))))
            }
        }
        // The star, until the planet swallows it.
        let starFade = 1 - beat(t, 3.4, 4.2)
        if t >= 2.3, starFade > 0 {
            let r = 18 * CGFloat(bloomSpring((t - 2.3) / 0.6))
            CelestialPainter.star(&ctx, at: c, radius: r, points: L.starPoints, color: L.starColor, brightness: 1.2 * starFade)
        }
        // Planet condenses (2.2 s), rings sweep in.
        let grow = LMCurve.easeOutCubic.value(beat(t, 3.0, 5.2))
        if grow > 0 {
            var pc = ctx
            pc.blendMode = .normal
            let ringU = LMCurve.emerge.value(beat(t, 5.0, 6.0))
            CelestialPainter.planet(&pc, at: c, radius: 72 * CGFloat(grow), palette: palette,
                                    ringTilt: -0.9 + 0.68 * ringU, ringOpacity: ringU, light: 1)
        }
    }


    // MARK: Reduce Motion (1.2 s crossfade, no camera, no particles)

    private static func drawReduced(_ ctx: inout GraphicsContext, t: Double, plan: CelebrationPlan, L: CelebrationLayout, ambientTime: Double?) {
        let fadeOut = 1 - beat(t, 0, 0.4)
        let fadeIn = beat(t, 0, 0.4)
        if fadeOut > 0 {
            OrbitalProgressView.draw(&ctx, center: L.origin, radius: L.ringRadius, progress: 1, headSize: 0, opacity: fadeOut)
            var core = ctx
            core.opacity = fadeOut
            GlowingCelestialBodyView.draw(&core, center: L.origin, progress: 1, tint: L.starColor, warmth: 1, breath: 1, dimmed: false)
        }
        let lineU = beat(t, 0.4, 0.8)
        if !L.neighbors.isEmpty {
            var path = Path()
            path.move(to: L.neighbors[0])
            for p in L.neighbors.dropFirst() { path.addLine(to: p) }
            if let _ = L.previous { path.addLine(to: L.starFinal) }
            ctx.stroke(path, with: .color(Color.white.opacity(0.5 * lineU)), lineWidth: 1.2)
            for (i, p) in L.neighbors.enumerated() {
                CelestialPainter.star(&ctx, at: p, radius: 6, points: L.neighborPoints[i], color: L.neighborColors[i], brightness: 0.8 * fadeIn)
            }
        }
        CelestialPainter.star(&ctx, at: L.starFinal, radius: L.starRadius * CGFloat(plan.scale), points: L.starPoints,
                              color: L.starColor, brightness: 1.1 * fadeIn, flare: true)
    }

    // MARK: Too short (no star: a gentle fade)

    private static func drawTooShort(_ ctx: inout GraphicsContext, t: Double, L: CelebrationLayout) {
        let fade = 1 - beat(t, 0, 0.5)
        guard fade > 0 else { return }
        var core = ctx
        core.opacity = fade
        GlowingCelestialBodyView.draw(&core, center: L.origin, progress: 0.3, tint: L.starColor, warmth: 0, breath: 1, dimmed: true)
    }
}
