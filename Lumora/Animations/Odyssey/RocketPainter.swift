import SwiftUI

/// The user's ship. Hull shape, paint and engine trail come from the loadout.
///
/// Contract: `center` is the ship's middle; `length` is nose-to-tail.
/// `heading` is the travel direction in radians, 0 = nose pointing up,
/// positive = clockwise. `thrust` 0...1 scales the engine flame and trail
/// (trail extends behind the ship up to ~3 × length at full thrust).
/// `time` (nil = static) flickers the flame.
enum RocketPainter {
    nonisolated static func draw(_ ctx: inout GraphicsContext, loadout: ShipLoadout, center: CGPoint, length: CGFloat,
                                 heading: Double, thrust: Double, time: Double?) {
        guard length > 2 else { return }
        let L = length
        let th = max(0, min(1, thrust))
        let t = (time ?? 0).truncatingRemainder(dividingBy: 3600)
        let tones = Tones(loadout: loadout)
        let engines = engineMounts(loadout.hull)

        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(heading))

        // Exhaust first, so the hull sits on top of its own light.
        if th > 0.01 {
            var glow = c
            glow.blendMode = .plusLighter
            trail(&glow, engines: engines, L: L, thrust: th, t: t, live: time != nil, tones: tones)
            for (i, e) in engines.enumerated() {
                flame(&glow, engine: e, index: i, L: L, thrust: th, t: t, live: time != nil, tones: tones)
            }
        }

        switch loadout.hull {
        case .lantern: lantern(&c, L: L, tones: tones)
        case .swift: swift(&c, L: L, tones: tones)
        case .ark: ark(&c, L: L, tones: tones)
        case .manta: manta(&c, L: L, tones: tones)
        }
    }

    // MARK: - Engines

    /// Nozzle exit (x, y) and width, in units of length.
    private struct Engine {
        var x: Double
        var y: Double
        var w: Double
    }

    nonisolated private static func engineMounts(_ hull: ShipHull) -> [Engine] {
        switch hull {
        case .lantern: [Engine(x: 0, y: 0.445, w: 0.17)]
        case .swift: [Engine(x: 0, y: 0.46, w: 0.095)]
        case .ark: [Engine(x: -0.31, y: 0.43, w: 0.105), Engine(x: 0.31, y: 0.43, w: 0.105)]
        case .manta: [Engine(x: -0.085, y: 0.36, w: 0.065), Engine(x: 0.085, y: 0.36, w: 0.065)]
        }
    }

    nonisolated private static func flame(_ g: inout GraphicsContext, engine e: Engine, index: Int, L: CGFloat, thrust: Double,
                                          t: Double, live: Bool, tones: Tones) {
        let ph = Double(index) * 1.7
        let flicker = live ? 0.09 * sin(t * 31 + ph) + 0.06 * sin(t * 53 + 1 + ph) + 0.05 * sin(t * 17.3 + ph * 2) : 0
        let x = CGFloat(e.x) * L, y = CGFloat(e.y) * L, w = CGFloat(e.w) * L
        let len = L * CGFloat((0.2 + 0.62 * thrust) * (1 + flicker))

        CelestialPainter.glow(&g, at: CGPoint(x: x, y: y + w * 0.3), radius: w * (1.6 + 1.4 * thrust),
                              color: tones.outer.color(1), intensity: 0.5 * thrust)
        let outer = teardrop(x: x, y: y, halfWidth: w * 0.52, length: len)
        g.fill(outer, with: .linearGradient(Gradient(stops: [
            .init(color: tones.outer.color(0.95), location: 0),
            .init(color: tones.outer.color(0.55), location: 0.45),
            .init(color: tones.outer.color(0), location: 1),
        ]), startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + len)))
        let innerLen = len * CGFloat(0.58 + 0.06 * sin(t * 41 + ph) * (live ? 1 : 0))
        let inner = teardrop(x: x, y: y, halfWidth: w * 0.3, length: innerLen)
        g.fill(inner, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.95), location: 0),
            .init(color: tones.inner.color(0.9), location: 0.35),
            .init(color: tones.inner.color(0), location: 1),
        ]), startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + innerLen)))
        // Shock diamonds on big, hot engines.
        if L > 80, thrust > 0.45 {
            for k in 0..<3 {
                let cy = y + innerLen * CGFloat(0.22 + 0.24 * Double(k))
                let r = w * CGFloat(0.16 - 0.035 * Double(k))
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: cy - r * 1.5, width: r * 2, height: r * 3)),
                       with: .color(.white.opacity(0.5 * thrust * (1 - 0.25 * Double(k)))))
            }
        }
    }

    nonisolated private static func trail(_ g: inout GraphicsContext, engines: [Engine], L: CGFloat, thrust: Double, t: Double,
                                          live: Bool, tones: Tones) {
        let y0 = CGFloat(engines.map(\.y).max() ?? 0.45) * L
        let tl = L * 3 * CGFloat(thrust)

        // Soft continuous plume per engine, fading into space.
        for e in engines {
            let ex = CGFloat(e.x) * L, hw = max(CGFloat(e.w) * L * 0.5, L * 0.03)
            let endX = engines.count > 1 ? ex * 0.45 : ex
            for (spread, alpha) in [(CGFloat(1.6), 0.13), (CGFloat(0.8), 0.2)] {
                var plume = Path()
                plume.move(to: CGPoint(x: ex - hw * spread * 0.7, y: y0))
                plume.addCurve(to: CGPoint(x: endX, y: y0 + tl),
                               control1: CGPoint(x: ex - hw * spread * 1.2, y: y0 + tl * 0.3),
                               control2: CGPoint(x: endX - hw * 0.3, y: y0 + tl * 0.8))
                plume.addCurve(to: CGPoint(x: ex + hw * spread * 0.7, y: y0),
                               control1: CGPoint(x: endX + hw * 0.3, y: y0 + tl * 0.8),
                               control2: CGPoint(x: ex + hw * spread * 1.2, y: y0 + tl * 0.3))
                plume.closeSubpath()
                g.fill(plume, with: .linearGradient(Gradient(stops: [
                    .init(color: tones.outer.color(alpha * thrust), location: 0),
                    .init(color: tones.outer.color(alpha * 0.4 * thrust), location: 0.4),
                    .init(color: tones.outer.color(0), location: 1),
                ]), startPoint: CGPoint(x: ex, y: y0), endPoint: CGPoint(x: ex, y: y0 + tl)))
            }
        }

        // Drifting sparks: deterministic, recycled along the plume.
        var rng = SeededRandom(seed: 0x7A11_5EED)
        let count = L < 60 ? 18 : 40
        let rate = 0.85
        for i in 0..<count {
            let phase = rng.unit()
            let speed = rng.range(0.75, 1.25)
            let lateral = (rng.unit() + rng.unit() + rng.unit() - 1.5) * 1.4
            let sizeU = rng.unit()
            let e = engines[i % engines.count]
            var a = phase + (live ? t * rate * speed : 0)
            a -= a.rounded(.down)
            let fade = pow(1 - a, 1.5) * thrust
            guard fade > 0.02 else { continue }
            let y = y0 + CGFloat(pow(a, 0.85)) * tl
            let ex = CGFloat(e.x) * L * CGFloat(1 - 0.55 * a)
            let wobble = CGFloat(sin(a * 7 + phase * 20)) * L * 0.025 * CGFloat(a)
            let x = ex + CGFloat(lateral) * (CGFloat(e.w) * L * 0.22 + L * 0.1 * CGFloat(a)) + wobble
            let size = max(0.6, min(L * 0.026, 1.2 + L * 0.012) * CGFloat(1 - 0.6 * a) * CGFloat(0.45 + sizeU))
            let tone = tones.inner.mixed(tones.outer, min(1, a * 2.2))
            let halo = size * 1.3
            g.fill(Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                   with: .color(tone.color(0.09 * fade)))
            g.fill(Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
                   with: .color(tone.color(0.9 * fade)))
        }
    }

    nonisolated private static func teardrop(x: CGFloat, y: CGFloat, halfWidth w: CGFloat, length len: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x - w, y: y))
        p.addCurve(to: CGPoint(x: x, y: y + len), control1: CGPoint(x: x - w * 1.15, y: y + len * 0.4),
                   control2: CGPoint(x: x - w * 0.2, y: y + len * 0.85))
        p.addCurve(to: CGPoint(x: x + w, y: y), control1: CGPoint(x: x + w * 0.2, y: y + len * 0.85),
                   control2: CGPoint(x: x + w * 1.15, y: y + len * 0.4))
        p.addQuadCurve(to: CGPoint(x: x - w, y: y), control: CGPoint(x: x, y: y - w * 0.4))
        return p
    }

    // MARK: - Hulls

    /// Classic rounded retro-future rocket: ogive nose, porthole, three fins.
    nonisolated private static func lantern(_ c: inout GraphicsContext, L: CGFloat, tones: Tones) {
        let u = Units(L)
        // Side fins (behind the body).
        for s: CGFloat in [-1, 1] {
            var fin = Path()
            fin.move(to: u.p(0.12 * s, 0.02))
            fin.addCurve(to: u.p(0.285 * s, 0.33), control1: u.p(0.22 * s, 0.1), control2: u.p(0.28 * s, 0.2))
            fin.addLine(to: u.p(0.295 * s, 0.455))
            fin.addQuadCurve(to: u.p(0.09 * s, 0.35), control: u.p(0.2 * s, 0.36))
            fin.closeSubpath()
            shade(&c, fin, tones.trim, x0: u.v(s < 0 ? -0.3 : 0.08), x1: u.v(s < 0 ? -0.08 : 0.3), top: u.v(0.02),
                  bottom: u.v(0.46), tones: tones, L: L)
        }
        // Engine bell.
        var bell = Path()
        bell.move(to: u.p(-0.075, 0.34))
        bell.addLine(to: u.p(0.075, 0.34))
        bell.addQuadCurve(to: u.p(0.098, 0.445), control: u.p(0.08, 0.41))
        bell.addLine(to: u.p(-0.098, 0.445))
        bell.addQuadCurve(to: u.p(-0.075, 0.34), control: u.p(-0.08, 0.41))
        bell.closeSubpath()
        metal(&c, bell, x0: u.v(-0.1), x1: u.v(0.1), tones: tones, L: L)

        var body = Path()
        body.move(to: u.p(0, -0.5))
        body.addCurve(to: u.p(0.155, -0.02), control1: u.p(0.08, -0.47), control2: u.p(0.155, -0.3))
        body.addCurve(to: u.p(0.105, 0.36), control1: u.p(0.155, 0.18), control2: u.p(0.13, 0.3))
        body.addLine(to: u.p(-0.105, 0.36))
        body.addCurve(to: u.p(-0.155, -0.02), control1: u.p(-0.13, 0.3), control2: u.p(-0.155, 0.18))
        body.addCurve(to: u.p(0, -0.5), control1: u.p(-0.155, -0.3), control2: u.p(-0.08, -0.47))
        body.closeSubpath()
        shade(&c, body, tones.body, x0: u.v(-0.155), x1: u.v(0.155), top: u.v(-0.5), bottom: u.v(0.36), tones: tones, L: L,
              outline: false)
        // Nose cap and tail band in trim.
        overlay(&c, clip: body, rect: CGRect(x: u.v(-0.2), y: u.v(-0.52), width: u.v(0.4), height: u.v(0.2)), tone: tones.trim,
                x0: u.v(-0.155), x1: u.v(0.155), top: u.v(-0.5), bottom: u.v(0.36), tones: tones, L: L)
        overlay(&c, clip: body, rect: CGRect(x: u.v(-0.2), y: u.v(0.2), width: u.v(0.4), height: u.v(0.06)), tone: tones.trim,
                x0: u.v(-0.155), x1: u.v(0.155), top: u.v(-0.5), bottom: u.v(0.36), tones: tones, L: L)
        if L >= 36 {
            panel(&c, clip: body, tones: tones, L: L) { p in
                p.move(to: u.p(-0.16, 0.07)); p.addQuadCurve(to: u.p(0.16, 0.07), control: u.p(0, 0.1))
                p.move(to: u.p(0.07, 0.07)); p.addLine(to: u.p(0.07, 0.2))
                p.move(to: u.p(-0.16, -0.32)); p.addQuadCurve(to: u.p(0.16, -0.32), control: u.p(0, -0.29))
            }
        }
        outline(&c, body, L: L)
        // Centre fin, seen edge-on.
        var keel = Path()
        keel.addRoundedRect(in: CGRect(x: u.v(-0.024), y: u.v(0.19), width: u.v(0.048), height: u.v(0.28)),
                            cornerSize: CGSize(width: u.v(0.024), height: u.v(0.024)))
        shade(&c, keel, tones.trim, x0: u.v(-0.024), x1: u.v(0.024), top: u.v(0.19), bottom: u.v(0.47), tones: tones, L: L)
        // Porthole with rivets.
        window(&c, center: u.p(0, -0.12), rx: u.v(0.072), ry: u.v(0.072), tones: tones, L: L, rimWidth: u.v(0.022))
        if L >= 60 {
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi
                let p = u.p(0.098 * cos(a), -0.12 + 0.098 * sin(a))
                let r = u.v(0.007)
                c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(tones.trim.lit(0.5).color(0.85)))
            }
        }
    }

    /// Sleek needle with swept wings and canards.
    nonisolated private static func swift(_ c: inout GraphicsContext, L: CGFloat, tones: Tones) {
        let u = Units(L)
        for s: CGFloat in [-1, 1] {
            var wing = Path()
            wing.move(to: u.p(0.05 * s, -0.04))
            wing.addLine(to: u.p(0.3 * s, 0.29))
            wing.addQuadCurve(to: u.p(0.3 * s, 0.37), control: u.p(0.33 * s, 0.34))
            wing.addLine(to: u.p(0.055 * s, 0.32))
            wing.closeSubpath()
            shade(&c, wing, tones.body, x0: u.v(s < 0 ? -0.32 : 0.04), x1: u.v(s < 0 ? -0.04 : 0.32), top: u.v(-0.04),
                  bottom: u.v(0.37), tones: tones, L: L)
            // Trim leading edge.
            var edge = Path()
            edge.move(to: u.p(0.05 * s, -0.04))
            edge.addLine(to: u.p(0.3 * s, 0.29))
            edge.addQuadCurve(to: u.p(0.3 * s, 0.37), control: u.p(0.33 * s, 0.34))
            var k = c
            k.clip(to: wing)
            k.stroke(edge, with: .color(tones.trim.color(1)), style: StrokeStyle(lineWidth: u.v(0.04), lineCap: .round))
            if L >= 36 {
                var line = Path()
                line.move(to: u.p(0.1 * s, 0.13)); line.addLine(to: u.p(0.2 * s, 0.33))
                k.stroke(line, with: .color(tones.body.dark(0.6).color(0.35)), lineWidth: max(0.5, L * 0.005))
            }
            // Canards.
            var canard = Path()
            canard.move(to: u.p(0.045 * s, -0.25))
            canard.addLine(to: u.p(0.13 * s, -0.14))
            canard.addLine(to: u.p(0.125 * s, -0.11))
            canard.addLine(to: u.p(0.05 * s, -0.15))
            canard.closeSubpath()
            shade(&c, canard, tones.trim, x0: u.v(s < 0 ? -0.13 : 0.04), x1: u.v(s < 0 ? -0.04 : 0.13), top: u.v(-0.25),
                  bottom: u.v(-0.11), tones: tones, L: L)
        }
        var bell = Path()
        bell.move(to: u.p(-0.04, 0.4))
        bell.addLine(to: u.p(0.04, 0.4))
        bell.addLine(to: u.p(0.052, 0.462))
        bell.addLine(to: u.p(-0.052, 0.462))
        bell.closeSubpath()
        metal(&c, bell, x0: u.v(-0.055), x1: u.v(0.055), tones: tones, L: L)

        var body = Path()
        body.move(to: u.p(0, -0.5))
        body.addCurve(to: u.p(0.07, -0.05), control1: u.p(0.02, -0.42), control2: u.p(0.07, -0.2))
        body.addLine(to: u.p(0.064, 0.37))
        body.addQuadCurve(to: u.p(0.045, 0.415), control: u.p(0.064, 0.4))
        body.addLine(to: u.p(-0.045, 0.415))
        body.addQuadCurve(to: u.p(-0.064, 0.37), control: u.p(-0.064, 0.4))
        body.addLine(to: u.p(-0.07, -0.05))
        body.addCurve(to: u.p(0, -0.5), control1: u.p(-0.07, -0.2), control2: u.p(-0.02, -0.42))
        body.closeSubpath()
        shade(&c, body, tones.body, x0: u.v(-0.07), x1: u.v(0.07), top: u.v(-0.5), bottom: u.v(0.42), tones: tones, L: L,
              outline: false)
        // Racing stripe and needle tip in trim.
        overlay(&c, clip: body, rect: CGRect(x: u.v(-0.013), y: u.v(-0.12), width: u.v(0.026), height: u.v(0.52)),
                tone: tones.trim, x0: u.v(-0.07), x1: u.v(0.07), top: u.v(-0.5), bottom: u.v(0.42), tones: tones, L: L)
        overlay(&c, clip: body, rect: CGRect(x: u.v(-0.1), y: u.v(-0.52), width: u.v(0.2), height: u.v(0.09)), tone: tones.trim,
                x0: u.v(-0.07), x1: u.v(0.07), top: u.v(-0.5), bottom: u.v(0.42), tones: tones, L: L)
        if L >= 36 {
            panel(&c, clip: body, tones: tones, L: L) { p in
                p.move(to: u.p(-0.07, 0.02)); p.addLine(to: u.p(0.07, 0.02))
                p.move(to: u.p(-0.07, 0.24)); p.addLine(to: u.p(0.07, 0.24))
            }
        }
        outline(&c, body, L: L)
        window(&c, center: u.p(0, -0.24), rx: u.v(0.034), ry: u.v(0.085), tones: tones, L: L, rimWidth: u.v(0.012))
        // Wingtip navigation lights.
        var glow = c
        glow.blendMode = .plusLighter
        for s: CGFloat in [-1, 1] {
            CelestialPainter.glow(&glow, at: u.p(0.305 * s, 0.335), radius: u.v(0.05), color: tones.window.color(1), intensity: 0.8)
        }
    }

    /// Broad, sturdy explorer: a domed command hull on a wing plate with
    /// two cone-nosed engine pods.
    nonisolated private static func ark(_ c: inout GraphicsContext, L: CGFloat, tones: Tones) {
        let u = Units(L)
        // Wing plate joining hull and pods.
        var plate = Path()
        plate.addLines([u.p(-0.16, -0.1), u.p(-0.31, 0.02), u.p(-0.31, 0.27), u.p(-0.16, 0.31),
                        u.p(0.16, 0.31), u.p(0.31, 0.27), u.p(0.31, 0.02), u.p(0.16, -0.1)])
        plate.closeSubpath()
        shade(&c, plate, tones.trim.dark(0.15), x0: u.v(-0.31), x1: u.v(0.31), top: u.v(-0.1), bottom: u.v(0.31), tones: tones, L: L)
        if L >= 36 {
            panel(&c, clip: plate, tones: tones, L: L) { p in
                for s: CGFloat in [-1, 1] {
                    p.move(to: u.p(0.2 * s, 0.0)); p.addLine(to: u.p(0.2 * s, 0.3))
                }
            }
        }
        for s: CGFloat in [-1, 1] {
            let px: CGFloat = 0.31 * s
            var bell = Path()
            bell.move(to: u.p(px - 0.04, 0.34))
            bell.addLine(to: u.p(px + 0.04, 0.34))
            bell.addLine(to: u.p(px + 0.052, 0.43))
            bell.addLine(to: u.p(px - 0.052, 0.43))
            bell.closeSubpath()
            metal(&c, bell, x0: u.v(px - 0.055), x1: u.v(px + 0.055), tones: tones, L: L)
            var pod = Path()
            pod.move(to: u.p(px, -0.25))
            pod.addCurve(to: u.p(px + 0.062, -0.1), control1: u.p(px + 0.035, -0.235), control2: u.p(px + 0.062, -0.17))
            pod.addLine(to: u.p(px + 0.062, 0.33))
            pod.addQuadCurve(to: u.p(px + 0.045, 0.355), control: u.p(px + 0.062, 0.355))
            pod.addLine(to: u.p(px - 0.045, 0.355))
            pod.addQuadCurve(to: u.p(px - 0.062, 0.33), control: u.p(px - 0.062, 0.355))
            pod.addLine(to: u.p(px - 0.062, -0.1))
            pod.addCurve(to: u.p(px, -0.25), control1: u.p(px - 0.062, -0.17), control2: u.p(px - 0.035, -0.235))
            pod.closeSubpath()
            let x0 = u.v(px - 0.062), x1 = u.v(px + 0.062)
            shade(&c, pod, tones.body, x0: x0, x1: x1, top: u.v(-0.25), bottom: u.v(0.355), tones: tones, L: L, outline: false)
            overlay(&c, clip: pod, rect: CGRect(x: x0 - 1, y: u.v(-0.26), width: x1 - x0 + 2, height: u.v(0.1)), tone: tones.trim,
                    x0: x0, x1: x1, top: u.v(-0.25), bottom: u.v(0.355), tones: tones, L: L)
            overlay(&c, clip: pod, rect: CGRect(x: x0 - 1, y: u.v(0.24), width: x1 - x0 + 2, height: u.v(0.035)), tone: tones.trim,
                    x0: x0, x1: x1, top: u.v(-0.25), bottom: u.v(0.355), tones: tones, L: L)
            if L >= 36 {
                panel(&c, clip: pod, tones: tones, L: L) { p in
                    p.move(to: u.p(px - 0.07, 0.07)); p.addLine(to: u.p(px + 0.07, 0.07))
                }
            }
            outline(&c, pod, L: L)
        }

        var body = Path()
        body.move(to: u.p(0, -0.5))
        body.addCurve(to: u.p(0.175, -0.25), control1: u.p(0.11, -0.49), control2: u.p(0.175, -0.38))
        body.addLine(to: u.p(0.19, 0.18))
        body.addQuadCurve(to: u.p(0.13, 0.34), control: u.p(0.19, 0.31))
        body.addLine(to: u.p(-0.13, 0.34))
        body.addQuadCurve(to: u.p(-0.19, 0.18), control: u.p(-0.19, 0.31))
        body.addLine(to: u.p(-0.175, -0.25))
        body.addCurve(to: u.p(0, -0.5), control1: u.p(-0.175, -0.38), control2: u.p(-0.11, -0.49))
        body.closeSubpath()
        shade(&c, body, tones.body, x0: u.v(-0.19), x1: u.v(0.19), top: u.v(-0.5), bottom: u.v(0.34), tones: tones, L: L,
              outline: false)
        // Trim chevron across the shoulders.
        var chevron = Path()
        chevron.addLines([u.p(-0.22, -0.2), u.p(0, -0.1), u.p(0.22, -0.2), u.p(0.22, -0.155), u.p(0, -0.055), u.p(-0.22, -0.155)])
        chevron.closeSubpath()
        var k = c
        k.clip(to: body)
        shade(&k, chevron, tones.trim, x0: u.v(-0.19), x1: u.v(0.19), top: u.v(-0.5), bottom: u.v(0.34), tones: tones, L: L,
              outline: false)
        if L >= 36 {
            panel(&c, clip: body, tones: tones, L: L) { p in
                p.addRoundedRect(in: CGRect(x: u.v(-0.1), y: u.v(0.05), width: u.v(0.2), height: u.v(0.2)),
                                 cornerSize: CGSize(width: u.v(0.02), height: u.v(0.02)))
                p.move(to: u.p(0, 0.05)); p.addLine(to: u.p(0, 0.25))
                p.move(to: u.p(-0.19, 0.29)); p.addLine(to: u.p(0.19, 0.29))
            }
        }
        outline(&c, body, L: L)
        // Bridge visor.
        var visor = Path()
        visor.move(to: u.p(-0.115, -0.31))
        visor.addQuadCurve(to: u.p(0.115, -0.31), control: u.p(0, -0.4))
        visor.addLine(to: u.p(0.1, -0.255))
        visor.addQuadCurve(to: u.p(-0.1, -0.255), control: u.p(0, -0.32))
        visor.closeSubpath()
        glass(&c, visor, center: u.p(-0.04, -0.35), radius: u.v(0.17), tones: tones, L: L)
        // Cabin lights.
        if L >= 30 {
            for i in -1...1 {
                window(&c, center: u.p(0.07 * CGFloat(i), -0.005), rx: u.v(0.02), ry: u.v(0.02), tones: tones, L: L,
                       rimWidth: u.v(0.008))
            }
        }
        // Antenna beacon.
        var mast = Path()
        mast.move(to: u.p(0, -0.49)); mast.addLine(to: u.p(0, -0.545))
        c.stroke(mast, with: .color(tones.metal.color(0.9)), lineWidth: max(0.5, u.v(0.012)))
        var glow = c
        glow.blendMode = .plusLighter
        CelestialPainter.glow(&glow, at: u.p(0, -0.55), radius: u.v(0.04), color: tones.trim.lit(0.3).color(1), intensity: 0.9)
    }

    /// Elegant ray-like flying wing with cephalic lobes and a tail stinger.
    nonisolated private static func manta(_ c: inout GraphicsContext, L: CGFloat, tones: Tones) {
        let u = Units(L)
        // Engine nacelles.
        for s: CGFloat in [-1, 1] {
            let rect = CGRect(x: u.v(0.085 * s - 0.032), y: u.v(0.15), width: u.v(0.064), height: u.v(0.215))
            metal(&c, Path(roundedRect: rect, cornerRadius: u.v(0.03)), x0: rect.minX, x1: rect.maxX, tones: tones, L: L)
        }
        // Tail stinger.
        var sting = Path()
        sting.move(to: u.p(-0.014, 0.3)); sting.addLine(to: u.p(0.014, 0.3)); sting.addLine(to: u.p(0, 0.5)); sting.closeSubpath()
        shade(&c, sting, tones.trim, x0: u.v(-0.014), x1: u.v(0.014), top: u.v(0.3), bottom: u.v(0.5), tones: tones, L: L)

        var wing = Path()
        var leading = Path()
        for s: CGFloat in [1, -1] {
            let seg = { (p: inout Path, first: Bool) in
                if first { p.move(to: u.p(0, -0.4)) }
                p.addCurve(to: u.p(0.07 * s, -0.5), control1: u.p(0.015 * s, -0.45), control2: u.p(0.035 * s, -0.5))
                p.addCurve(to: u.p(0.125 * s, -0.37), control1: u.p(0.11 * s, -0.5), control2: u.p(0.13 * s, -0.43))
                p.addCurve(to: u.p(0.465 * s, 0.12), control1: u.p(0.26 * s, -0.26), control2: u.p(0.43 * s, -0.04))
            }
            var edge = Path()
            seg(&edge, true)
            leading.addPath(edge)
            if s > 0 {
                seg(&wing, true)
                wing.addCurve(to: u.p(0.4, 0.205), control1: u.p(0.485, 0.175), control2: u.p(0.45, 0.205))
                wing.addCurve(to: u.p(0.12, 0.3), control1: u.p(0.3, 0.2), control2: u.p(0.18, 0.24))
                wing.addCurve(to: u.p(0, 0.33), control1: u.p(0.07, 0.34), control2: u.p(0.03, 0.33))
                wing.addCurve(to: u.p(-0.12, 0.3), control1: u.p(-0.03, 0.33), control2: u.p(-0.07, 0.34))
                wing.addCurve(to: u.p(-0.4, 0.205), control1: u.p(-0.18, 0.24), control2: u.p(-0.3, 0.2))
                wing.addCurve(to: u.p(-0.465, 0.12), control1: u.p(-0.45, 0.205), control2: u.p(-0.485, 0.175))
                wing.addCurve(to: u.p(-0.125, -0.37), control1: u.p(-0.43, -0.04), control2: u.p(-0.26, -0.26))
                wing.addCurve(to: u.p(-0.07, -0.5), control1: u.p(-0.13, -0.43), control2: u.p(-0.11, -0.5))
                wing.addCurve(to: u.p(0, -0.4), control1: u.p(-0.035, -0.5), control2: u.p(-0.015, -0.45))
                wing.closeSubpath()
            }
        }
        shade(&c, wing, tones.body, x0: u.v(-0.47), x1: u.v(0.47), top: u.v(-0.5), bottom: u.v(0.33), tones: tones, L: L,
              outline: false)
        var k = c
        k.clip(to: wing)
        // Darker trailing half gives the wing camber.
        k.fill(wing, with: .linearGradient(Gradient(colors: [.clear, tones.body.dark(0.7).color(0.35)]),
                                           startPoint: u.p(0, -0.1), endPoint: u.p(0, 0.32)))
        k.stroke(leading, with: .color(tones.trim.color(0.95)), style: StrokeStyle(lineWidth: u.v(0.035), lineCap: .round))
        if L >= 36 {
            panel(&c, clip: wing, tones: tones, L: L) { p in
                for s: CGFloat in [-1, 1] {
                    p.move(to: u.p(0.09 * s, -0.12)); p.addQuadCurve(to: u.p(0.42 * s, 0.13), control: u.p(0.3 * s, -0.02))
                    p.move(to: u.p(0.09 * s, 0.08)); p.addQuadCurve(to: u.p(0.33 * s, 0.2), control: u.p(0.22 * s, 0.12))
                }
            }
        }
        outline(&c, wing, L: L)
        // Raised central spine.
        var spine = Path()
        spine.move(to: u.p(0, -0.42))
        spine.addCurve(to: u.p(0, 0.3), control1: u.p(0.11, -0.3), control2: u.p(0.1, 0.2))
        spine.addCurve(to: u.p(0, -0.42), control1: u.p(-0.1, 0.2), control2: u.p(-0.11, -0.3))
        spine.closeSubpath()
        shade(&c, spine, tones.body.lit(0.12), x0: u.v(-0.085), x1: u.v(0.085), top: u.v(-0.42), bottom: u.v(0.3), tones: tones,
              L: L)
        window(&c, center: u.p(0, -0.22), rx: u.v(0.032), ry: u.v(0.07), tones: tones, L: L, rimWidth: u.v(0.012))
        // Bioluminescent dots along the wings.
        var glow = c
        glow.blendMode = .plusLighter
        let dots = L >= 36 ? 5 : 3
        for s: CGFloat in [-1, 1] {
            for i in 0..<dots {
                let f = (Double(i) + 0.5) / Double(dots)
                let x = 0.14 + 0.27 * f
                let y = -0.2 + 0.32 * f - 0.05 * sin(f * .pi)
                CelestialPainter.glow(&glow, at: u.p(CGFloat(x) * s, CGFloat(y)), radius: u.v(0.026 * (1.2 - 0.4 * f)),
                                      color: tones.window.color(1), intensity: 0.85)
            }
        }
    }

    // MARK: - Shading

    /// Fills a part with cylindrical shading, specular highlight, top/bottom
    /// light falloff, a coloured rim light on the shadow side and an outline.
    nonisolated private static func shade(_ c: inout GraphicsContext, _ path: Path, _ tone: Tone, x0: CGFloat, x1: CGFloat,
                                          top: CGFloat, bottom: CGFloat, tones: Tones, L: CGFloat, outline doOutline: Bool = true) {
        c.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: tone.lit(0.6).color(1), location: 0),
            .init(color: tone.lit(0.22).color(1), location: 0.28),
            .init(color: tone.color(1), location: 0.55),
            .init(color: tone.dark(0.45).color(1), location: 0.86),
            .init(color: tone.dark(0.62).color(1), location: 1),
        ]), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
        var k = c
        k.clip(to: path)
        k.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.14), location: 0),
            .init(color: .clear, location: 0.35),
            .init(color: .clear, location: 0.7),
            .init(color: Color(hex: 0x0B0A24).opacity(0.28), location: 1),
        ]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        // Specular streak.
        let w = x1 - x0, h = bottom - top
        let spec = CGRect(x: x0 + w * 0.17, y: top + h * 0.06, width: max(0.8, w * 0.17), height: h * 0.72)
        k.fill(Path(ellipseIn: spec), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.6), .white.opacity(0)]),
                                                         startPoint: CGPoint(x: spec.minX, y: 0), endPoint: CGPoint(x: spec.maxX, y: 0)))
        // Rim light on the far edge.
        var rim = k
        rim.blendMode = .plusLighter
        rim.stroke(path, with: .linearGradient(Gradient(stops: [
            .init(color: tones.rim.color(0), location: 0),
            .init(color: tones.rim.color(0), location: 0.55),
            .init(color: tones.rim.color(0.85), location: 1),
        ]), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)), lineWidth: max(1, L * 0.035))
        if doOutline { outline(&c, path, L: L) }
    }

    /// Paints `tone` over the part of `clip` inside `rect`, with the same shading.
    nonisolated private static func overlay(_ c: inout GraphicsContext, clip: Path, rect: CGRect, tone: Tone, x0: CGFloat, x1: CGFloat,
                                            top: CGFloat, bottom: CGFloat, tones: Tones, L: CGFloat) {
        var k = c
        k.clip(to: clip)
        shade(&k, Path(rect), tone, x0: x0, x1: x1, top: top, bottom: bottom, tones: tones, L: L, outline: false)
        // A fine highlight seam along the overlay's top edge.
        if L >= 30 {
            var seam = Path()
            seam.move(to: CGPoint(x: rect.minX, y: rect.maxY)); seam.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            k.stroke(seam, with: .color(tones.body.dark(0.6).color(0.45)), lineWidth: max(0.4, L * 0.005))
        }
    }

    nonisolated private static func metal(_ c: inout GraphicsContext, _ path: Path, x0: CGFloat, x1: CGFloat, tones: Tones, L: CGFloat) {
        c.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: tones.metal.lit(0.45).color(1), location: 0),
            .init(color: tones.metal.color(1), location: 0.35),
            .init(color: tones.metal.dark(0.6).color(1), location: 1),
        ]), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
        outline(&c, path, L: L)
    }

    nonisolated private static func outline(_ c: inout GraphicsContext, _ path: Path, L: CGFloat) {
        c.stroke(path, with: .color(Color(hex: 0x0B0A24).opacity(0.55)), lineWidth: max(0.5, L * 0.007))
    }

    nonisolated private static func panel(_ c: inout GraphicsContext, clip: Path, tones: Tones, L: CGFloat, _ build: (inout Path) -> Void) {
        var p = Path()
        build(&p)
        var k = c
        k.clip(to: clip)
        let w = max(0.45, L * 0.0055)
        k.stroke(p.offsetBy(dx: 0, dy: w), with: .color(.white.opacity(0.22)), lineWidth: w)
        k.stroke(p, with: .color(Color(hex: 0x0B0A24).opacity(0.4)), lineWidth: w)
    }

    /// A porthole: metal rim, deep glass, a reflection and a soft inner glow.
    nonisolated private static func window(_ c: inout GraphicsContext, center p: CGPoint, rx: CGFloat, ry: CGFloat, tones: Tones,
                                           L: CGFloat, rimWidth: CGFloat) {
        let outer = CGRect(x: p.x - rx - rimWidth, y: p.y - ry - rimWidth, width: (rx + rimWidth) * 2, height: (ry + rimWidth) * 2)
        c.fill(Path(ellipseIn: outer), with: .linearGradient(Gradient(colors: [tones.trim.lit(0.55).color(1), tones.trim.dark(0.5).color(1)]),
                                                         startPoint: CGPoint(x: outer.minX, y: outer.minY),
                                                         endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
        let rect = CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2)
        glass(&c, Path(ellipseIn: rect), center: CGPoint(x: p.x - rx * 0.35, y: p.y - ry * 0.4), radius: max(rx, ry) * 1.7,
              tones: tones, L: L)
    }

    nonisolated private static func glass(_ c: inout GraphicsContext, _ shape: Path, center: CGPoint, radius: CGFloat, tones: Tones,
                                          L: CGFloat) {
        c.fill(shape, with: .radialGradient(Gradient(stops: [
            .init(color: tones.window.lit(0.75).color(1), location: 0),
            .init(color: tones.window.color(1), location: 0.35),
            .init(color: tones.window.dark(0.7).color(1), location: 1),
        ]), center: center, startRadius: 0, endRadius: radius))
        var k = c
        k.clip(to: shape)
        let b = shape.boundingRect
        // Curved reflection across the upper-left of the glass.
        let refl = CGRect(x: b.minX + b.width * 0.12, y: b.minY + b.height * 0.1, width: b.width * 0.42, height: b.height * 0.32)
        k.fill(Path(ellipseIn: refl), with: .color(.white.opacity(0.55)))
        let dot = max(0.5, min(b.width, b.height) * 0.09)
        k.fill(Path(ellipseIn: CGRect(x: b.maxX - b.width * 0.3, y: b.maxY - b.height * 0.32, width: dot, height: dot)),
               with: .color(.white.opacity(0.5)))
        var glow = c
        glow.blendMode = .plusLighter
        CelestialPainter.glow(&glow, at: CGPoint(x: b.midX, y: b.midY), radius: max(b.width, b.height) * 0.9,
                              color: tones.window.color(1), intensity: 0.22)
    }

    // MARK: - Colour

    private struct Units {
        var L: CGFloat
        nonisolated init(_ L: CGFloat) { self.L = L }
        nonisolated func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * L, y: y * L) }
        nonisolated func v(_ x: CGFloat) -> CGFloat { x * L }
    }

    private struct Tones {
        var body, trim, window, metal, rim, inner, outer: Tone

        nonisolated init(loadout: ShipLoadout) {
            let p = loadout.paint.colors
            body = Tone(hex: p.body)
            trim = Tone(hex: p.trim)
            window = Tone(hex: p.window)
            metal = Tone(hex: 0x8A90B4).mixed(Tone(hex: p.body), 0.15)
            rim = Tone(hex: p.trim).mixed(Tone(hex: 0xFFFFFF), 0.35)
            let f = loadout.trail.colors
            inner = Tone(hex: f.inner)
            outer = Tone(hex: f.outer)
        }
    }

    private struct Tone {
        var r, g, b: Double

        nonisolated init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        nonisolated init(hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        nonisolated func mixed(_ o: Tone, _ t: Double) -> Tone {
            Tone(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
        }

        nonisolated func lit(_ t: Double) -> Tone { mixed(Tone(r: 1, g: 1, b: 1), t) }
        nonisolated func dark(_ t: Double) -> Tone { mixed(Tone(hex: 0x16133F), t) }

        nonisolated func color(_ opacity: Double) -> Color {
            Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
        }
    }
}

/// A self-animating ship preview.
struct RocketView: View {
    var loadout: ShipLoadout
    var heading: Double = 0
    var thrust: Double = 0.6
    var animate = true

    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let live = animate && motion.animatesContinuously && scenePhase == .active
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !live)) { tl in
            Canvas { ctx, size in
                RocketPainter.draw(&ctx, loadout: loadout, center: CGPoint(x: size.width / 2, y: size.height * 0.42),
                                   length: min(size.width, size.height) * 0.5, heading: heading, thrust: thrust,
                                   time: live ? tl.date.timeIntervalSinceReferenceDate : nil)
            }
        }
        .accessibilityHidden(true)
    }
}
