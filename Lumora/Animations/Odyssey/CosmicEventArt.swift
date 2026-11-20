import SwiftUI

/// A small, slowly moving picture of a rare event, for cards and the Codex.
struct CosmicEventArt: View {
    var kind: CosmicEventKind
    var animate = true
    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let live = animate && motion.animatesContinuously && scenePhase == .active
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !live)) { tl in
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, kind: kind, time: live ? tl.date.timeIntervalSinceReferenceDate : 0)
            }
        }
        .accessibilityHidden(true)
    }

    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, kind: CosmicEventKind, time t: Double) {
        let w = size.width, h = size.height
        let c = CGPoint(x: w / 2, y: h / 2)
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.8, time: t == 0 ? nil : t)
        var glow = ctx
        glow.blendMode = .plusLighter
        switch kind {
        case .comet:
            let drift = sin(t * 0.3) * w * 0.03
            let head = CGPoint(x: c.x - w * 0.12 + drift, y: c.y + h * 0.12)
            // A broad, soft tail fanning away from the sun, then the comet itself.
            var tail = glow
            tail.addFilter(.blur(radius: h * 0.05))
            var fan = Path()
            fan.move(to: head)
            fan.addLine(to: CGPoint(x: head.x + w * 0.62, y: head.y - h * 0.62))
            fan.addLine(to: CGPoint(x: head.x + w * 0.74, y: head.y - h * 0.4))
            fan.closeSubpath()
            tail.fill(fan, with: .linearGradient(Gradient(colors: [Color(hex: Palette.warmGold).opacity(0.55), .clear]),
                                                 startPoint: head, endPoint: CGPoint(x: head.x + w * 0.7, y: head.y - h * 0.5)))
            CelestialPainter.comet(&glow, at: head, angle: 2.39, length: w * 0.75, color: Color(hex: Palette.warmGold))
            CelestialPainter.glow(&glow, at: head, radius: w * 0.12, color: Color(hex: 0xFFF1D6), intensity: 0.7)
        case .eclipse:
            let galaxy = GalaxyCatalog.blueprint(3)
            GalaxyPainter.draw(&ctx, galaxy: galaxy, center: c, radius: min(w, h) * 0.46, brightness: 1, time: t, locked: false)
            let r = min(w, h) * 0.13
            let slide = sin(t * 0.25) * r * 0.25
            let disc = CGRect(x: c.x - r + slide, y: c.y - r, width: r * 2, height: r * 2)
            CelestialPainter.glow(&glow, at: CGPoint(x: disc.midX, y: disc.midY), radius: r * 1.5,
                                  color: Color(hex: Palette.warmGold), intensity: 0.55)
            ctx.fill(Path(ellipseIn: disc), with: .color(Color(hex: Palette.deepSpace)))
            ctx.stroke(Path(ellipseIn: disc), with: .color(Color(hex: 0xFFF1D6).opacity(0.85)), lineWidth: 1.4)
        case .meteors:
            for i in 0..<9 {
                let phase = (t * 0.35 + Double(i) * 0.137).truncatingRemainder(dividingBy: 1)
                let x0 = w * (0.15 + 0.09 * Double(i)) + phase * w * 0.25
                let y0 = h * (0.05 + 0.04 * Double(i % 4)) + phase * h * 0.7
                var streak = Path()
                streak.move(to: CGPoint(x: x0, y: y0))
                streak.addLine(to: CGPoint(x: x0 - w * 0.12, y: y0 - h * 0.18))
                glow.stroke(streak, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE0B0).opacity(0.9 * (1 - phase)), .clear]),
                                                          startPoint: CGPoint(x: x0, y: y0),
                                                          endPoint: CGPoint(x: x0 - w * 0.12, y: y0 - h * 0.18)),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        case .aurora:
            // Soft curtains: vertical light hanging from a slow wave, fading downward.
            var veil = glow
            veil.addFilter(.blur(radius: w * 0.012))
            let columns = 48
            for band in 0..<2 {
                let color = band == 0 ? Color(hex: 0x2FD6B5) : Color(hex: 0x8B7CFF)
                for i in 0...columns {
                    let x = w * Double(i) / Double(columns)
                    let top = h * (0.18 + 0.12 * Double(band)) + sin(Double(i) * 0.32 + t * 0.5 + Double(band) * 1.7) * h * 0.08
                    let length = h * (0.32 + 0.1 * sin(Double(i) * 0.9 + t * 0.8 + Double(band)))
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: top))
                    line.addLine(to: CGPoint(x: x, y: top + length))
                    veil.stroke(line, with: .linearGradient(Gradient(colors: [color.opacity(0.0), color.opacity(0.55), color.opacity(0)]),
                                                            startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: top + length)),
                                lineWidth: w / Double(columns) + 1.5)
                }
            }
        case .twinSuns:
            let rise = (sin(t * 0.2) + 1) / 2
            for (i, color) in [Palette.warmGold, Palette.nebulaPink].enumerated() {
                let p = CGPoint(x: c.x + (i == 0 ? -1 : 1) * w * 0.16, y: h * (0.62 - 0.12 * rise) - CGFloat(i) * h * 0.06)
                CelestialPainter.glow(&glow, at: p, radius: w * 0.3, color: Color(hex: color), intensity: 0.5)
                CelestialPainter.star(&glow, at: p, radius: min(w, h) * 0.08, points: 4, color: Color(hex: 0xFFF1D6),
                                      brightness: 1.2, flare: true)
            }
            ctx.fill(Path(CGRect(x: 0, y: h * 0.7, width: w, height: h * 0.3)),
                     with: .linearGradient(Gradient(colors: [Color(hex: Palette.deepSpace).opacity(0), Color(hex: Palette.deepSpace)]),
                                           startPoint: CGPoint(x: 0, y: h * 0.7), endPoint: CGPoint(x: 0, y: h)))
        case .nova:
            let pulse = 0.85 + 0.15 * sin(t * 1.4)
            CelestialPainter.glow(&glow, at: c, radius: min(w, h) * 0.6 * pulse, color: Color(hex: 0x70E1F5), intensity: 0.6)
            for ring in 1...3 {
                let r = min(w, h) * (0.12 * Double(ring) + 0.05 * ((t * 0.3).truncatingRemainder(dividingBy: 1)))
                glow.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                            with: .color(Color(hex: 0xE9FBFF).opacity(0.35 / Double(ring))), lineWidth: 1.2)
            }
            CelestialPainter.star(&glow, at: c, radius: min(w, h) * 0.16 * pulse, points: 4, color: Color(hex: 0xE9FBFF),
                                  brightness: 1.4, flare: true)
        case .alignment:
            // Five worlds on one line, smallest farthest, with a faint thread of light through them.
            let from = CGPoint(x: w * 0.12, y: h * 0.74), to = CGPoint(x: w * 0.9, y: h * 0.26)
            var thread = Path()
            thread.move(to: from)
            thread.addLine(to: to)
            glow.stroke(thread, with: .linearGradient(Gradient(colors: [.clear, Color(hex: 0xFFF1D6).opacity(0.35), .clear]),
                                                      startPoint: from, endPoint: to), lineWidth: 1)
            let palettes = ["amber", "aqua", "rose", "violet", "jade"]
            for i in 0..<5 {
                let u = 0.08 + 0.21 * Double(i) + 0.012 * sin(t * 0.4 + Double(i))
                let p = CGPoint(x: from.x + (to.x - from.x) * u, y: from.y + (to.y - from.y) * u)
                let r = min(w, h) * (0.11 - 0.017 * Double(i))
                CelestialPainter.planet(&ctx, at: p, radius: r, palette: .named(palettes[i]),
                                        ringTilt: -0.3, light: 0.9, showRing: i == 1 || i == 3)
            }
        case .solarStorm:
            // A sun half off the edge, flinging loops of fire and a stream of sparks.
            let r = min(w, h) * 0.24
            let sun = CGPoint(x: w * 0.24, y: h * 0.56)
            CelestialPainter.glow(&glow, at: sun, radius: r * 2.2, color: Color(hex: 0xFF8A3D), intensity: 0.45)
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6DD), Color(hex: 0xFFC56B), Color(hex: 0xF07A3A)]),
                                           center: CGPoint(x: sun.x + r * 0.25, y: sun.y - r * 0.2), startRadius: 0, endRadius: r * 1.2))
            CelestialPainter.glow(&glow, at: sun, radius: r * 1.15, color: Color(hex: 0xFFE2A8), intensity: 0.35)
            for i in 0..<3 {
                let lift = 0.75 + 0.25 * sin(t * 0.7 + Double(i) * 2)
                let a0 = -0.9 + 0.6 * Double(i), a1 = a0 + 0.35
                let p0 = CGPoint(x: sun.x + cos(a0) * r, y: sun.y + sin(a0) * r)
                let p1 = CGPoint(x: sun.x + cos(a1) * r, y: sun.y + sin(a1) * r)
                let peak = CGPoint(x: sun.x + cos((a0 + a1) / 2) * r * (1 + 0.45 * lift),
                                   y: sun.y + sin((a0 + a1) / 2) * r * (1 + 0.45 * lift))
                var loop = Path()
                loop.move(to: p0)
                loop.addQuadCurve(to: p1, control: peak)
                glow.stroke(loop, with: .color(Color(hex: 0xFFB347).opacity(0.6)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            for i in 0..<14 {
                let phase = (t * 0.25 + Double(i) * 0.071).truncatingRemainder(dividingBy: 1)
                let p = CGPoint(x: sun.x + r + phase * w * 0.8, y: sun.y - h * 0.2 + Double(i % 5) * h * 0.1 + sin(Double(i) + t) * 4)
                CelestialPainter.glow(&glow, at: p, radius: 3 + 2 * (1 - phase), color: Color(hex: 0xFFD58A), intensity: 0.9 * (1 - phase))
            }
        case .pulsar:
            // Two beams sweeping round a tiny, fierce core.
            let angle = t * 1.6
            for side in [0.0, Double.pi] {
                var beam = Path()
                let a = angle + side
                let reach = max(w, h)
                beam.move(to: c)
                beam.addLine(to: CGPoint(x: c.x + cos(a - 0.09) * reach, y: c.y + sin(a - 0.09) * reach * 0.55))
                beam.addLine(to: CGPoint(x: c.x + cos(a + 0.09) * reach, y: c.y + sin(a + 0.09) * reach * 0.55))
                beam.closeSubpath()
                glow.fill(beam, with: .radialGradient(Gradient(colors: [Color(hex: 0xBDEFF7).opacity(0.75), .clear]),
                                                      center: c, startRadius: 0, endRadius: reach * 0.6))
            }
            CelestialPainter.glow(&glow, at: c, radius: min(w, h) * 0.22, color: Color(hex: 0x70E1F5), intensity: 0.7)
            CelestialPainter.star(&glow, at: c, radius: min(w, h) * 0.06, points: 4, color: Color(hex: 0xE9FBFF),
                                  brightness: 1.5, flare: true)
        case .moonHalo:
            // A pale moon inside a wide ring, warm on the inside, cool outside.
            let r = min(w, h) * 0.12
            let ring = min(w, h) * (0.4 + 0.015 * sin(t * 0.6))
            for (offset, color) in [(-3.0, 0xFFD9A8), (0.0, 0xFFFFFF), (3.0, 0xA8C8FF)] as [(Double, UInt32)] {
                let rr = ring + offset
                glow.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                            with: .color(Color(hex: color).opacity(0.55)), lineWidth: 1.6)
            }
            var haze = glow
            haze.addFilter(.blur(radius: 6))
            haze.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                        with: .color(Color(hex: 0xE8F0FF).opacity(0.35)), lineWidth: 10)
            CelestialPainter.glow(&glow, at: c, radius: r * 3, color: Color(hex: 0xCFE3FF), intensity: 0.25)
            CelestialPainter.moon(&ctx, at: c, radius: r)
        case .nebulaBloom:
            // Petals of coloured gas opening around a newborn star.
            let open = 0.75 + 0.25 * sin(t * 0.35)
            let colors: [UInt32] = [Palette.nebulaPink, Palette.cosmicViolet, Palette.starlightCyan, Palette.warmGold, 0xC56BCB, 0x6FD8B0]
            for i in 0..<6 {
                let a = Double(i) * .pi / 3 + t * 0.05
                let d = min(w, h) * 0.2 * open
                let p = CGPoint(x: c.x + cos(a) * d * 1.3, y: c.y + sin(a) * d)
                CelestialPainter.glow(&glow, at: p, radius: min(w, h) * 0.32 * open, color: Color(hex: colors[i]), intensity: 0.32)
            }
            CelestialPainter.star(&glow, at: c, radius: min(w, h) * 0.07, points: 4, color: Color(hex: 0xFFF8F0),
                                  brightness: 1.3, flare: true)
        }
    }
}
