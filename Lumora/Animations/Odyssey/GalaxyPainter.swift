import SwiftUI

/// Procedural galaxies (spiral, barred, ring, elliptical, irregular).
///
/// Contract: draws within a disc of `radius` around `center` (soft halo may
/// reach 1.3 × radius). `brightness` 0...1 grows as the galaxy's worlds are
/// charted. `locked` galaxies are faint and desaturated. `time` (nil =
/// static) slowly rotates the arms. Must stay cheap: it is drawn several
/// times on the cosmic map at 30 fps.
enum GalaxyPainter {
    nonisolated static func draw(_ ctx: inout GraphicsContext, galaxy: GalaxyBlueprint, center: CGPoint, radius: CGFloat,
                                 brightness: Double, time: Double?, locked: Bool) {
        guard radius > 2 else { return }
        let look = Look(galaxy: galaxy, radius: radius, brightness: brightness, locked: locked, time: time)
        let frame = Frame(galaxy: galaxy, center: center, radius: radius, time: time)
        var stars = Stars()
        var knots: [Knot] = []
        var heroes: [CGPoint] = []

        var glow = ctx
        glow.blendMode = .plusLighter
        var plane = frame.plane(glow)

        // 1. Outer halo and disc wash.
        let haloR: CGFloat = galaxy.shape == .elliptical ? 1.28 : 1.25
        fillDisc(&plane, radius: haloR, stops: [
            (look.arm, 0.10 * look.wash, 0), (look.dust, 0.05 * look.wash, 0.45), (look.dust, 0, 1),
        ])

        // 2. Shape body: washes, dust lanes and star particles.
        switch galaxy.shape {
        case .spiral2, .spiral4:
            spiral(&plane, &stars, &knots, &heroes, galaxy: galaxy, look: look, arms: galaxy.shape == .spiral2 ? 2 : 4)
        case .barred:
            barred(&plane, &stars, &knots, &heroes, galaxy: galaxy, look: look)
        case .ring:
            ring(&plane, &stars, &knots, &heroes, galaxy: galaxy, look: look)
        case .elliptical:
            elliptical(&plane, &stars, &heroes, galaxy: galaxy, look: look)
        case .irregular:
            irregular(&plane, &stars, &knots, &heroes, galaxy: galaxy, look: look)
        }

        // 3. Core bulge (under the stars so they sparkle across it).
        if galaxy.shape != .elliptical { bulge(&glow, frame: frame, galaxy: galaxy, look: look) }

        // 4. Star particles, batched by colour and twinkle group.
        stars.render(&glow, frame: frame, look: look)

        // 5. Star-forming knots, hero stars and the nucleus.
        for knot in knots { drawKnot(&glow, knot, frame: frame, look: look) }
        for (i, p) in heroes.enumerated() { drawHero(&glow, at: frame.project(p), index: i, look: look) }
        nucleus(&glow, frame: frame, galaxy: galaxy, look: look)
    }

    // MARK: - Shapes

    private struct Arm {
        var offset: Double
        var r0: Double
        var k: Double
        var span: Double
        var width: Double

        /// Point on the arm at `s` (0 = root, 1 = tip) and its outward normal.
        nonisolated func point(_ s: Double) -> (p: CGPoint, n: CGPoint) {
            let theta = s * span
            let r = r0 * exp(k * theta)
            let a = offset + theta
            let ca = cos(a), sa = sin(a)
            var tx = k * ca - sa, ty = k * sa + ca
            let tl = max(1e-6, (tx * tx + ty * ty).squareRoot())
            tx /= tl; ty /= tl
            var nx = ty, ny = -tx
            if nx * ca + ny * sa < 0 { nx = -nx; ny = -ny }
            return (CGPoint(x: r * ca, y: r * sa), CGPoint(x: nx, y: ny))
        }

        nonisolated func width(at s: Double) -> Double {
            width * (0.4 + 0.6 * s) * (1 - 0.55 * GalaxyPainter.smooth(0.75, 1, s))
        }
    }

    nonisolated private static func spiral(_ plane: inout GraphicsContext, _ stars: inout Stars, _ knots: inout [Knot],
                                           _ heroes: inout [CGPoint], galaxy: GalaxyBlueprint, look: Look, arms n: Int) {
        var rng = SeededRandom(seed: galaxy.seed ^ 0xA2B1)
        let two = n == 2
        let pitch = two ? rng.range(0.27, 0.33) : rng.range(0.40, 0.48)
        let r0 = two ? 0.10 : 0.13
        let r1 = two ? 0.98 : 0.95
        let span = log(r1 / r0) / pitch
        let base = rng.range(0, 2 * .pi)
        let arms: [Arm] = (0..<n).map { i in
            let jitter = two ? 0 : rng.range(-0.18, 0.18)
            return Arm(offset: base + Double(i) * 2 * .pi / Double(n) + jitter, r0: r0, k: pitch * rng.range(0.94, 1.06),
                       span: span * (two ? 1 : rng.range(0.85, 1.0)), width: two ? 0.17 : 0.12)
        }

        // Disc wash: warm centre fading into the arm colour.
        fillDisc(&plane, radius: 1.0, stops: [
            (look.core, 0.22 * look.wash, 0), (look.arm, 0.11 * look.wash, 0.35), (look.dust, 0.04 * look.wash, 0.75),
            (look.dust, 0, 1),
        ])
        armWashes(&plane, arms: arms, look: look, seed: galaxy.seed)
        for arm in arms { dustLane(&plane, arm: arm, look: look) }

        // Stars: bulge, disc and arms (arms carry the young blue and pink stars).
        let total = look.starCount
        var bulgeRng = SeededRandom(seed: galaxy.seed ^ 0xB0B0)
        bulgeStars(&stars, &bulgeRng, count: total * 18 / 100, size: two ? 0.22 : 0.17, look: look)
        var discRng = SeededRandom(seed: galaxy.seed ^ 0xD15C)
        discStars(&stars, &discRng, count: total * 22 / 100, look: look)
        var armRng = SeededRandom(seed: galaxy.seed ^ 0xA4A4)
        armStars(&stars, &armRng, arms: arms, count: total * 60 / 100, look: look)

        var knotRng = SeededRandom(seed: galaxy.seed ^ 0x4B07)
        armKnots(&knots, &heroes, &knotRng, arms: arms, look: look)
    }

    nonisolated private static func barred(_ plane: inout GraphicsContext, _ stars: inout Stars, _ knots: inout [Knot],
                                           _ heroes: inout [CGPoint], galaxy: GalaxyBlueprint, look: Look) {
        var rng = SeededRandom(seed: galaxy.seed ^ 0xBA22)
        let barL = rng.range(0.36, 0.42)
        let span = rng.range(3.2, 3.6)
        let k = log(0.97 / barL) / span
        let arms = [0.0, Double.pi].map { Arm(offset: $0, r0: barL, k: k, span: span, width: 0.15) }

        fillDisc(&plane, radius: 1.0, stops: [
            (look.core, 0.18 * look.wash, 0), (look.arm, 0.10 * look.wash, 0.38), (look.dust, 0.035 * look.wash, 0.78),
            (look.dust, 0, 1),
        ])
        // Inner pseudo-ring through the bar ends.
        annulus(&plane, radius: barL, width: 0.09, tone: look.arm, alpha: 0.16 * look.wash)
        armWashes(&plane, arms: arms, look: look, seed: galaxy.seed)
        for arm in arms { dustLane(&plane, arm: arm, look: look) }

        // The bar: an elongated, brilliant lozenge of old stars.
        var bar = plane
        bar.scaleBy(x: 1, y: 0.27)
        fillDisc(&bar, radius: barL * 1.18, stops: [
            (look.white, 0.55 * look.core01, 0), (look.core, 0.42 * look.core01, 0.3), (look.arm, 0.14 * look.core01, 0.72),
            (look.arm, 0, 1),
        ])
        var spine = plane
        spine.scaleBy(x: 1, y: 0.12)
        fillDisc(&spine, radius: barL, stops: [
            (look.white, 0.45 * look.core01, 0), (look.core, 0.25 * look.core01, 0.6), (look.core, 0, 1),
        ])
        // Offset dust lanes on the leading edges of the bar.
        for sign in [1.0, -1.0] {
            var pts: [CGPoint] = [], widths: [CGFloat] = []
            for i in 0...8 {
                let s = Double(i) / 8
                let x = barL * (1.0 - 0.88 * s), y = -(0.025 + 0.05 * s)
                pts.append(CGPoint(x: sign * x, y: sign * y))
                widths.append(CGFloat(0.03 * sin(.pi * (0.1 + 0.85 * s))))
            }
            fillLane(&plane, ribbon(pts, widths: widths), look: look, strength: 0.5)
        }

        let total = look.starCount
        var bulgeRng = SeededRandom(seed: galaxy.seed ^ 0xB0B0)
        bulgeStars(&stars, &bulgeRng, count: total * 14 / 100, size: 0.15, look: look)
        var barRng = SeededRandom(seed: galaxy.seed ^ 0xBA75)
        for _ in 0..<(total * 18 / 100) {
            let x = (barRng.unit() * 2 - 1) * barL
            let y = gauss(&barRng) * 0.045 * (1 - 0.5 * abs(x) / barL)
            stars.add(CGPoint(x: x, y: y), cls: barRng.unit() < 0.7 ? 0 : 1, rng: &barRng, look: look)
        }
        var discRng = SeededRandom(seed: galaxy.seed ^ 0xD15C)
        discStars(&stars, &discRng, count: total * 18 / 100, look: look)
        var armRng = SeededRandom(seed: galaxy.seed ^ 0xA4A4)
        armStars(&stars, &armRng, arms: arms, count: total * 50 / 100, look: look)

        var knotRng = SeededRandom(seed: galaxy.seed ^ 0x4B07)
        armKnots(&knots, &heroes, &knotRng, arms: arms, look: look)
    }

    nonisolated private static func ring(_ plane: inout GraphicsContext, _ stars: inout Stars, _ knots: inout [Knot],
                                         _ heroes: inout [CGPoint], galaxy: GalaxyBlueprint, look: Look) {
        var rng = SeededRandom(seed: galaxy.seed ^ 0x2196)
        let ringR = rng.range(0.62, 0.68)
        let bright = rng.range(0, 2 * .pi)

        // A faint outer lens, then the quiet core.
        annulus(&plane, radius: 0.9, width: 0.16, tone: look.dust, alpha: 0.07 * look.wash)
        fillDisc(&plane, radius: 0.4, stops: [
            (look.core, 0.18 * look.wash, 0), (look.arm, 0.05 * look.wash, 0.6), (look.arm, 0, 1),
        ])
        // The ring: a wide haze, a bright band of young stars and a crisp crest.
        annulus(&plane, radius: ringR, width: 0.2, tone: look.arm, alpha: 0.2 * look.wash)
        annulus(&plane, radius: ringR + 0.01, width: 0.085, tone: look.young, alpha: 0.3 * look.wash)
        annulus(&plane, radius: ringR, width: 0.03, tone: look.white, alpha: 0.22 * look.wash)
        // Brighter arc on one side, as young stars bunch up.
        for j in 0..<(look.detail >= 1 ? 5 : 3) {
            let a = bright + Double(j) * 0.5
            let p = CGPoint(x: cos(a) * ringR, y: sin(a) * ringR)
            var b = plane
            b.translateBy(x: p.x, y: p.y)
            b.rotate(by: .radians(a))
            b.scaleBy(x: 1, y: 2.2)
            glowDisc(&b, at: .zero, radius: 0.12 - 0.012 * Double(j), color: j % 2 == 0 ? look.young : look.pink,
                     alpha: 0.2 * look.wash * (1 - 0.15 * Double(j)))
        }
        // Dark lane just inside the bright band.
        var dark = plane
        dark.blendMode = .normal
        annulus(&dark, radius: ringR - 0.085, width: 0.05, tone: look.lane, alpha: 0.45 * look.laneAlpha)

        let total = look.starCount
        var coreRng = SeededRandom(seed: galaxy.seed ^ 0xB0B0)
        bulgeStars(&stars, &coreRng, count: total * 10 / 100, size: 0.11, look: look)
        var ringRng = SeededRandom(seed: galaxy.seed ^ 0x2157)
        for _ in 0..<(total * 64 / 100) {
            let a = ringRng.unit() * 2 * .pi
            var d = gauss(&ringRng) * 0.045
            if d > 0 { d *= 1.5 }
            let r = ringR + d
            let u = ringRng.unit()
            let cls = u < 0.42 ? 2 : (u < 0.62 ? 3 : 1)
            stars.add(CGPoint(x: cos(a) * r, y: sin(a) * r), cls: cls, rng: &ringRng, look: look)
        }
        var discRng = SeededRandom(seed: galaxy.seed ^ 0xD15C)
        for _ in 0..<(total * 26 / 100) {
            let a = discRng.unit() * 2 * .pi
            let r = 0.3 + 0.68 * discRng.unit().squareRoot()
            stars.add(CGPoint(x: cos(a) * r, y: sin(a) * r), cls: discRng.unit() < 0.5 ? 0 : 1, rng: &discRng, look: look, dim: 0.55)
        }

        var knotRng = SeededRandom(seed: galaxy.seed ^ 0x4B07)
        for i in 0..<look.knotCount {
            let a = knotRng.unit() * 2 * .pi
            let r = ringR + gauss(&knotRng) * 0.03
            let size = knotRng.range(0.035, 0.07)
            knots.append(Knot(p: CGPoint(x: cos(a) * r, y: sin(a) * r), size: size, pink: i % 3 != 2))
        }
        for _ in 0..<look.heroCount {
            let a = knotRng.unit() * 2 * .pi
            heroes.append(CGPoint(x: cos(a) * ringR, y: sin(a) * ringR))
        }
    }

    nonisolated private static func elliptical(_ plane: inout GraphicsContext, _ stars: inout Stars, _ heroes: inout [CGPoint],
                                               galaxy: GalaxyBlueprint, look: Look) {
        // Smooth, ancient light: a de Vaucouleurs-like stack of gradients.
        fillDisc(&plane, radius: 1.0, stops: [
            (look.white, 0.9 * look.core01, 0), (look.core, 0.7 * look.core01, 0.06), (look.core, 0.45 * look.core01, 0.18),
            (look.arm, 0.26 * look.core01, 0.38), (look.arm, 0.12 * look.core01, 0.62), (look.dust, 0.04 * look.core01, 0.85),
            (look.dust, 0, 1),
        ])
        fillDisc(&plane, radius: 0.42, stops: [
            (look.white, 0.30 * look.core01, 0), (look.core, 0.16 * look.core01, 0.4), (look.core, 0, 1),
        ])

        let total = look.starCount
        var rng = SeededRandom(seed: galaxy.seed ^ 0xE111)
        for _ in 0..<(total * 55 / 100) {
            let a = rng.unit() * 2 * .pi
            let r = 0.85 * pow(rng.unit(), 2.1)
            stars.add(CGPoint(x: cos(a) * r, y: sin(a) * r), cls: rng.unit() < 0.65 ? 0 : 1, rng: &rng, look: look,
                      dim: 0.8, sizeScale: 0.65)
        }
        // A faint halo of globular clusters.
        var gc = SeededRandom(seed: galaxy.seed ^ 0x61C1)
        let count = look.locked ? 4 : Int(8 + 10 * look.b)
        for i in 0..<18 {
            let a = gc.unit() * 2 * .pi
            let r = gc.range(0.55, 1.2)
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            guard i < count else { continue }
            stars.addCluster(p, look: look)
        }
        if !look.locked, look.detail >= 1 {
            var hr = SeededRandom(seed: galaxy.seed ^ 0x4E40)
            for _ in 0..<max(1, look.heroCount / 2) {
                let a = hr.unit() * 2 * .pi
                heroes.append(CGPoint(x: cos(a) * hr.range(0.2, 0.6), y: sin(a) * hr.range(0.2, 0.6)))
            }
        }
    }

    nonisolated private static func irregular(_ plane: inout GraphicsContext, _ stars: inout Stars, _ knots: inout [Knot],
                                              _ heroes: inout [CGPoint], galaxy: GalaxyBlueprint, look: Look) {
        var rng = SeededRandom(seed: galaxy.seed ^ 0x1229)
        let clumpCount = 6 + Int(rng.unit() * 3)
        var clumps: [(p: CGPoint, s: Double)] = []
        for i in 0..<clumpCount {
            let t = Double(i) / Double(clumpCount - 1)
            let x = -0.62 + 1.24 * t + rng.range(-0.12, 0.12)
            let y = rng.range(-0.34, 0.34) * (1 - 0.5 * abs(x)) + 0.12 * sin(t * 5 + rng.range(0, 3))
            clumps.append((CGPoint(x: x, y: y), rng.range(0.13, 0.27)))
        }

        // Amorphous body.
        for j in 0..<3 {
            let p = CGPoint(x: rng.range(-0.3, 0.3), y: rng.range(-0.15, 0.15))
            glowDisc(&plane, at: p, radius: 0.78 - 0.12 * Double(j), color: j == 1 ? look.dust : look.arm, alpha: 0.10 * look.wash)
        }
        // Nebular clumps in arm, cyan-white and pink.
        for (i, c) in clumps.enumerated() {
            let color = i % 3 == 0 ? look.pink : (i % 3 == 1 ? look.young : look.arm)
            glowDisc(&plane, at: c.p, radius: c.s * 1.7, color: color, alpha: 0.18 * look.wash)
            if look.detail >= 1 {
                glowDisc(&plane, at: c.p, radius: c.s * 0.7, color: look.white, alpha: 0.10 * look.wash)
            }
        }
        // Dark dust patches between the clumps.
        var dark = plane
        dark.blendMode = .normal
        for j in 0..<2 {
            let a = clumps[1 + j * 2].p, b = clumps[2 + j * 2].p
            let p = CGPoint(x: (a.x + b.x) / 2 + rng.range(-0.05, 0.05), y: (a.y + b.y) / 2 + rng.range(-0.06, 0.06))
            let r = rng.range(0.12, 0.2)
            dark.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.6, width: r * 2, height: r * 1.2)), with: .radialGradient(
                Gradient(colors: [look.lane.color(0.45 * look.laneAlpha), look.lane.color(0)]),
                center: p, startRadius: 0, endRadius: r))
        }

        let total = look.starCount
        var cr = SeededRandom(seed: galaxy.seed ^ 0xC1C1)
        for _ in 0..<(total * 58 / 100) {
            let c = clumps[Int(cr.unit() * Double(clumps.count)) % clumps.count]
            let p = CGPoint(x: c.p.x + gauss(&cr) * c.s * 0.5, y: c.p.y + gauss(&cr) * c.s * 0.5)
            let u = cr.unit()
            stars.add(p, cls: u < 0.45 ? 2 : (u < 0.7 ? 3 : 1), rng: &cr, look: look)
        }
        var dr = SeededRandom(seed: galaxy.seed ^ 0xD15C)
        for _ in 0..<(total * 42 / 100) {
            let p = CGPoint(x: gauss(&dr) * 0.4, y: gauss(&dr) * 0.26)
            guard p.x * p.x + p.y * p.y < 1 else { _ = dr.unit(); _ = dr.unit(); _ = dr.unit(); _ = dr.unit(); continue }
            stars.add(p, cls: dr.unit() < 0.5 ? 0 : 1, rng: &dr, look: look, dim: 0.65)
        }
        for (i, c) in clumps.enumerated() where i < look.knotCount {
            knots.append(Knot(p: c.p, size: c.s * 0.32, pink: i % 3 != 1))
        }
        var kr = SeededRandom(seed: galaxy.seed ^ 0x4B07)
        for i in 0..<max(0, look.knotCount - clumps.count) {
            let c = clumps[i % clumps.count]
            knots.append(Knot(p: CGPoint(x: c.p.x + gauss(&kr) * c.s * 0.6, y: c.p.y + gauss(&kr) * c.s * 0.6),
                              size: kr.range(0.025, 0.045), pink: true))
        }
        for i in 0..<look.heroCount {
            let c = clumps[(i * 2) % clumps.count]
            heroes.append(CGPoint(x: c.p.x + gauss(&kr) * c.s * 0.3, y: c.p.y + gauss(&kr) * c.s * 0.3))
        }
    }

    // MARK: - Shared layers

    /// Arms painted as a chain of overlapping soft clouds, each stretched
    /// along the arm, so the light falls off smoothly with no hard edges.
    nonisolated private static func armWashes(_ plane: inout GraphicsContext, arms: [Arm], look: Look, seed: UInt64) {
        let perArm = arms.count == 2 ? [10, 15, 21][look.detail] : [6, 9, 12][look.detail]
        for (ai, arm) in arms.enumerated() {
            var rng = SeededRandom(seed: seed ^ UInt64(ai &+ 1) &* 0xC10D)
            for j in 0..<perArm {
                let s = (Double(j) + rng.range(0.3, 0.7)) / Double(perArm)
                let (p, n) = arm.point(s)
                let w = arm.width(at: s)
                let fade = 1 - 0.4 * s
                var b = plane
                b.translateBy(x: p.x, y: p.y)
                b.rotate(by: .radians(atan2(n.y, n.x)))
                b.scaleBy(x: 1, y: 2.6)
                let tone = j % 3 == 2 ? look.dust : look.arm
                glowDisc(&b, at: .zero, radius: w * rng.range(1.0, 1.3), color: tone, alpha: 0.24 * look.wash * fade)
                if look.detail >= 1 {
                    glowDisc(&b, at: CGPoint(x: w * 0.12, y: 0), radius: w * 0.5, color: look.young,
                             alpha: 0.2 * look.wash * fade)
                }
            }
        }
    }

    /// A soft glowing annulus (one gradient fill, no stroke edges).
    nonisolated private static func annulus(_ plane: inout GraphicsContext, radius r: Double, width w: Double, tone: Tone,
                                            alpha: Double) {
        let outer = r + w
        fillDisc(&plane, radius: outer, stops: [
            (tone, 0, 0), (tone, 0, max(0, (r - w) / outer)), (tone, alpha * 0.55, (r - w * 0.35) / outer),
            (tone, alpha, r / outer), (tone, alpha * 0.45, (r + w * 0.35) / outer), (tone, 0, 1),
        ])
    }

    nonisolated private static func dustLane(_ plane: inout GraphicsContext, arm: Arm, look: Look) {
        guard look.detail >= 1 || look.radius > 40 else { return }
        var pts: [CGPoint] = [], widths: [CGFloat] = []
        let steps = look.detail >= 2 ? 28 : 18
        for i in 0...steps {
            let s = 0.02 + 0.8 * Double(i) / Double(steps)
            let (p, n) = arm.point(s)
            let w = arm.width(at: s)
            pts.append(CGPoint(x: p.x - n.x * w * 0.3, y: p.y - n.y * w * 0.3))
            widths.append(CGFloat(w * 0.22 * sin(.pi * (0.06 + 0.9 * Double(i) / Double(steps)))))
        }
        fillLane(&plane, ribbon(pts, widths: widths), look: look, strength: 1)
    }

    nonisolated private static func fillLane(_ plane: inout GraphicsContext, _ path: Path, look: Look, strength: Double) {
        var dark = plane
        dark.blendMode = .normal
        let a = 0.6 * look.laneAlpha * strength
        dark.fill(path, with: .radialGradient(Gradient(stops: [
            .init(color: look.lane.color(a * 0.5), location: 0),
            .init(color: look.lane.color(a), location: 0.3),
            .init(color: look.lane.color(a * 0.75), location: 0.65),
            .init(color: look.lane.color(0), location: 0.95),
        ]), center: .zero, startRadius: 0, endRadius: 1))
    }

    nonisolated private static func bulgeStars(_ stars: inout Stars, _ rng: inout SeededRandom, count: Int, size: Double, look: Look) {
        for _ in 0..<count {
            let a = rng.unit() * 2 * .pi
            let r = abs(gauss(&rng)) * size * 0.75
            stars.add(CGPoint(x: cos(a) * r, y: sin(a) * r), cls: rng.unit() < 0.85 ? 0 : 1, rng: &rng, look: look, sizeScale: 0.85)
        }
    }

    nonisolated private static func discStars(_ stars: inout Stars, _ rng: inout SeededRandom, count: Int, look: Look) {
        for _ in 0..<count {
            let a = rng.unit() * 2 * .pi
            let r = min(1.0, -0.3 * log(1 - rng.unit() * 0.96))
            stars.add(CGPoint(x: cos(a) * r, y: sin(a) * r), cls: rng.unit() < 0.5 ? 0 : 1, rng: &rng, look: look, dim: 0.6)
        }
    }

    nonisolated private static func armStars(_ stars: inout Stars, _ rng: inout SeededRandom, arms: [Arm], count: Int, look: Look) {
        for i in 0..<count {
            let arm = arms[i % arms.count]
            let s = pow(rng.unit(), 0.9)
            let (p, n) = arm.point(s)
            let w = arm.width(at: s)
            let off = (gauss(&rng) * 0.42 + 0.12) * w
            let along = gauss(&rng) * 0.02
            let u = rng.unit()
            let cls = u < 0.38 ? 2 : (u < 0.56 ? 3 : 1)
            stars.add(CGPoint(x: p.x + n.x * off - n.y * along, y: p.y + n.y * off + n.x * along), cls: cls, rng: &rng, look: look)
        }
    }

    nonisolated private static func armKnots(_ knots: inout [Knot], _ heroes: inout [CGPoint], _ rng: inout SeededRandom,
                                             arms: [Arm], look: Look) {
        for i in 0..<14 {
            let arm = arms[i % arms.count]
            let s = rng.range(0.25, 0.92)
            let (p, n) = arm.point(s)
            let off = arm.width(at: s) * rng.range(-0.05, 0.35)
            let size = rng.range(0.03, 0.06)
            guard i < look.knotCount else { continue }
            knots.append(Knot(p: CGPoint(x: p.x + n.x * off, y: p.y + n.y * off), size: size, pink: i % 4 != 3))
        }
        for i in 0..<look.heroCount {
            let arm = arms[i % arms.count]
            let (p, n) = arm.point(rng.range(0.15, 0.85))
            let off = rng.range(-0.02, 0.04)
            heroes.append(CGPoint(x: p.x + n.x * off, y: p.y + n.y * off))
        }
    }

    nonisolated private static func bulge(_ glow: inout GraphicsContext, frame: Frame, galaxy: GalaxyBlueprint, look: Look) {
        let size: Double
        switch galaxy.shape {
        case .spiral2: size = 0.34
        case .spiral4: size = 0.27
        case .barred: size = 0.26
        case .ring: size = 0.2
        case .irregular: size = 0.16
        case .elliptical: size = 0
        }
        var b = frame.bulge(glow)
        let c = look.core01
        fillDisc(&b, radius: size, stops: [
            (look.white, 0.9 * c, 0), (look.core, 0.7 * c, 0.14), (look.core, 0.32 * c, 0.4), (look.arm, 0.08 * c, 0.75),
            (look.arm, 0, 1),
        ])
    }

    nonisolated private static func nucleus(_ glow: inout GraphicsContext, frame: Frame, galaxy: GalaxyBlueprint, look: Look) {
        let p = frame.center
        let scale: Double = galaxy.shape == .elliptical ? 1.2 : (galaxy.shape == .irregular ? 0.5 : 1)
        let r = max(1.5, look.radius * 0.07 * (0.7 + 0.45 * look.b) * scale)
        CelestialPainter.glow(&glow, at: p, radius: r, color: look.white.color(1), intensity: 0.85 * look.core01)
        let d = max(0.8, r * 0.18)
        glow.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)),
                  with: .color(.white.opacity(0.9 * look.core01)))
    }

    // MARK: - Knots and heroes

    private struct Knot {
        var p: CGPoint
        var size: Double
        var pink: Bool
    }

    nonisolated private static func drawKnot(_ glow: inout GraphicsContext, _ k: Knot, frame: Frame, look: Look) {
        let p = frame.project(k.p)
        let r = max(1.4, k.size * look.radius)
        let tone = k.pink ? look.pink : look.young
        CelestialPainter.glow(&glow, at: p, radius: r * 1.6, color: tone.color(1), intensity: 0.5 * look.wash)
        if look.detail >= 1 {
            CelestialPainter.glow(&glow, at: p, radius: r * 0.55, color: look.white.color(1), intensity: 0.45 * look.wash)
        }
    }

    nonisolated private static func drawHero(_ glow: inout GraphicsContext, at p: CGPoint, index: Int, look: Look) {
        let tw = 0.75 + 0.25 * sin(look.t * (1.1 + 0.37 * Double(index)) + Double(index) * 2.1)
        let r = max(1.6, look.radius * 0.03) * (look.locked ? 0.7 : 1)
        let a = look.locked ? 0.35 : 0.9 * tw
        CelestialPainter.glow(&glow, at: p, radius: r * 2.4, color: look.young.color(1), intensity: 0.55 * a)
        let d = max(0.7, r * 0.28)
        glow.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)), with: .color(.white.opacity(a)))
        guard look.radius > 70, !look.locked else { return }
        let len = r * (3.2 + 1.2 * tw)
        for (dx, dy) in [(1.0, 0.0), (0.0, 1.0)] {
            var line = Path()
            line.move(to: CGPoint(x: p.x - dx * len, y: p.y - dy * len))
            line.addLine(to: CGPoint(x: p.x + dx * len, y: p.y + dy * len))
            glow.stroke(line, with: .linearGradient(
                Gradient(colors: [look.young.color(0), .white.opacity(0.75 * a), look.young.color(0)]),
                startPoint: CGPoint(x: p.x - dx * len, y: p.y - dy * len), endPoint: CGPoint(x: p.x + dx * len, y: p.y + dy * len)),
                        lineWidth: max(0.5, r * 0.16))
        }
    }

    // MARK: - Star batches

    /// Star particles collected into a handful of paths (4 colours × 3
    /// twinkle groups, plus soft halos), so hundreds of stars cost ~16 fills.
    private struct Stars {
        var dots = [Path](repeating: Path(), count: 12)
        var halos = [Path](repeating: Path(), count: 4)
        var outerHalos = [Path](repeating: Path(), count: 4)
        var dimDots = [Path](repeating: Path(), count: 4)
        var clusters: [CGPoint] = []
        var points: [(p: CGPoint, r: CGFloat, slot: Int, halo: Bool, dim: Bool)] = []

        /// Adds one star in plane coordinates. Always consumes the same random
        /// draws, so lighting more stars never reshuffles the existing ones.
        nonisolated mutating func add(_ p: CGPoint, cls: Int, rng: inout SeededRandom, look: Look, dim: Double = 1,
                                      sizeScale: Double = 1) {
            let rank = rng.unit()
            let sizeU = rng.unit()
            let group = Int(rng.unit() * 3) % 3
            guard rank < look.litFraction else { return }
            let size = look.starSize * sizeScale * (0.55 + 1.7 * sizeU * sizeU * sizeU)
            let isDim = dim < 0.9 && sizeU < 0.7
            points.append((p, CGFloat(size), cls * 3 + group, sizeU > 0.8 && look.radius > 45, isDim))
        }

        nonisolated mutating func addCluster(_ p: CGPoint, look: Look) {
            clusters.append(p)
        }

        nonisolated mutating func render(_ glow: inout GraphicsContext, frame: Frame, look: Look) {
            for s in points {
                let q = frame.project(s.p)
                let r = s.r * 0.5
                let rect = CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)
                if s.dim {
                    dimDots[s.slot / 3].addEllipse(in: rect)
                } else {
                    dots[s.slot].addEllipse(in: rect)
                }
                if s.halo {
                    let h = s.r * 0.9, o = s.r * 1.6
                    halos[s.slot / 3].addEllipse(in: CGRect(x: q.x - h, y: q.y - h, width: h * 2, height: h * 2))
                    outerHalos[s.slot / 3].addEllipse(in: CGRect(x: q.x - o, y: q.y - o, width: o * 2, height: o * 2))
                }
            }
            for cls in 0..<4 {
                let tone = look.starTones[cls]
                if !outerHalos[cls].isEmpty { glow.fill(outerHalos[cls], with: .color(tone.color(0.035 * look.starAlpha))) }
                if !halos[cls].isEmpty { glow.fill(halos[cls], with: .color(tone.color(0.12 * look.starAlpha))) }
                if !dimDots[cls].isEmpty { glow.fill(dimDots[cls], with: .color(tone.color(0.5 * look.starAlpha))) }
                for g in 0..<3 where !dots[cls * 3 + g].isEmpty {
                    glow.fill(dots[cls * 3 + g], with: .color(tone.color(look.starAlpha * look.twinkle[g])))
                }
            }
            // Globular clusters: tight fuzzy balls of old light.
            let cr = max(1.3, look.radius * 0.024)
            for c in clusters {
                let q = frame.project(c)
                CelestialPainter.glow(&glow, at: q, radius: cr * 2, color: look.core.color(1), intensity: 0.45 * look.starAlpha)
                let d = max(0.5, cr * 0.32)
                glow.fill(Path(ellipseIn: CGRect(x: q.x - d, y: q.y - d, width: d * 2, height: d * 2)),
                          with: .color(look.white.color(0.85 * look.starAlpha)))
            }
        }
    }

    // MARK: - Look and frame

    /// Everything brightness/locked/radius decide: palette, intensities, LOD.
    private struct Look {
        var core, arm, dust, young, pink, white, lane: Tone
        var starTones: [Tone]
        var b: Double
        var locked: Bool
        var radius: CGFloat
        var t: Double
        /// 0 small, 1 medium, 2 large.
        var detail: Int
        var wash: Double
        var core01: Double
        var laneAlpha: Double
        var starAlpha: Double
        var starSize: Double
        var starCount: Int
        var litFraction: Double
        var knotCount: Int
        var heroCount: Int
        var twinkle: [Double]

        nonisolated init(galaxy: GalaxyBlueprint, radius: CGFloat, brightness: Double, locked: Bool, time: Double?) {
            let b = locked ? 0 : max(0, min(1, brightness))
            self.b = b
            self.locked = locked
            self.radius = radius
            t = (time ?? 0).truncatingRemainder(dividingBy: 3600)
            detail = radius < 55 ? 0 : (radius < 110 ? 1 : 2)

            // Colour: desaturated until worlds are charted; nearly grey when locked.
            let desat = locked ? 0.82 : 0.42 * (1 - b)
            let ghost = Tone(hex: 0xA9A6D6)
            func tone(_ hex: UInt32) -> Tone {
                let c = Tone(hex: hex).desaturated(desat)
                return locked ? c.mixed(ghost, 0.25) : c
            }
            core = tone(galaxy.core)
            arm = tone(galaxy.arm).mixed(Tone(hex: 0xFFFFFF), 0.12)
            dust = tone(galaxy.dust).mixed(Tone(hex: galaxy.arm), 0.25).lifted(0.25)
            young = tone(galaxy.arm).mixed(Tone(hex: 0xCFE4FF), 0.6)
            pink = tone(0xFF8FB8).mixed(tone(galaxy.dust).lifted(0.3), 0.28)
            white = tone(0xFFF8F0)
            lane = Tone(hex: 0x090B1F).mixed(Tone(hex: galaxy.dust), 0.1)
            starTones = [core.mixed(white, 0.25), arm.mixed(white, 0.4), young.mixed(white, 0.25), pink.mixed(white, 0.25)]

            wash = locked ? 0.42 : 0.62 + 0.5 * b
            core01 = locked ? 0.32 : 0.55 + 0.45 * b
            laneAlpha = locked ? 0.6 : 0.8 + 0.2 * b
            starAlpha = locked ? 0.55 : 0.78 + 0.22 * b
            starSize = Double(max(0.6, min(1.7, radius * 0.0095)))
            // LOD: ~70 particles at 30 pt growing to 350 at 180 pt.
            starCount = Int(max(60, min(350, 70 + (radius - 30) * 1.87)))
            litFraction = locked ? 0.13 : 0.42 + 0.58 * b
            let lod = Double(max(0, min(1, (radius - 30) / 150)))
            knotCount = locked ? 0 : Int((3 + 11 * b) * (0.45 + 0.55 * lod))
            heroCount = locked ? 1 : Int((2 + 6 * b) * (0.4 + 0.6 * lod))
            if time == nil {
                twinkle = [0.9, 0.82, 0.74]
            } else {
                let tt = t
                twinkle = [0.82 + 0.18 * sin(tt * 1.3), 0.74 + 0.26 * sin(tt * 2.1 + 2), 0.7 + 0.3 * sin(tt * 0.83 + 4)]
            }
        }
    }

    /// Projection from the galaxy plane (unit disc) to the screen: spin,
    /// chirality, inclination squash, then on-screen tilt rotation.
    private struct Frame {
        var center: CGPoint
        var radius: CGFloat
        var squash: CGFloat
        var bulgeSquash: CGFloat
        var screenAngle: Double
        var chirality: CGFloat
        var spin: Double
        private var sc, ss, pc, ps: CGFloat

        nonisolated init(galaxy: GalaxyBlueprint, center: CGPoint, radius: CGFloat, time: Double?) {
            var rng = SeededRandom(seed: galaxy.seed ^ 0xF4A3)
            self.center = center
            self.radius = radius
            let incl = 0.45 + min(0.6, abs(galaxy.tilt)) * 1.05
            var sq = CGFloat(cos(incl))
            if galaxy.shape == .elliptical { sq = (1 - (1 - sq) * 0.45) * CGFloat(rng.range(0.7, 0.86)) } else { _ = rng.unit() }
            squash = sq
            bulgeSquash = 1 - (1 - sq) * 0.45
            screenAngle = galaxy.tilt * 1.4 + rng.range(-0.25, 0.25)
            chirality = rng.unit() < 0.5 ? -1 : 1
            let period = 300.0
            let phase = (time ?? 0).truncatingRemainder(dividingBy: period) / period
            spin = rng.range(0, 2 * .pi) - phase * 2 * .pi
            sc = CGFloat(cos(spin)); ss = CGFloat(sin(spin))
            pc = CGFloat(cos(screenAngle)); ps = CGFloat(sin(screenAngle))
        }

        nonisolated func project(_ p: CGPoint) -> CGPoint {
            let x1 = p.x * sc - p.y * ss, y1 = p.x * ss + p.y * sc
            let x2 = x1 * radius * chirality, y2 = y1 * radius * squash
            return CGPoint(x: center.x + x2 * pc - y2 * ps, y: center.y + x2 * ps + y2 * pc)
        }

        nonisolated func plane(_ ctx: GraphicsContext) -> GraphicsContext {
            var c = ctx
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: .radians(screenAngle))
            c.scaleBy(x: radius * chirality, y: radius * squash)
            c.rotate(by: .radians(spin))
            return c
        }

        nonisolated func bulge(_ ctx: GraphicsContext) -> GraphicsContext {
            var c = ctx
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: .radians(screenAngle))
            c.scaleBy(x: radius, y: radius * bulgeSquash)
            return c
        }
    }

    // MARK: - Helpers

    nonisolated private static func fillDisc(_ ctx: inout GraphicsContext, radius r: Double, stops: [(Tone, Double, Double)]) {
        let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: stops.map { .init(color: $0.0.color(max(0, min(1, $0.1))), location: $0.2) }),
            center: .zero, startRadius: 0, endRadius: r))
    }

    nonisolated private static func glowDisc(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: Double, color: Tone, alpha: Double) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: color.color(alpha), location: 0),
                .init(color: color.color(alpha * 0.4), location: 0.4),
                .init(color: color.color(0), location: 1),
            ]), center: p, startRadius: 0, endRadius: r))
    }

    /// A closed ribbon around a polyline with per-point half-widths.
    nonisolated private static func ribbon(_ pts: [CGPoint], widths: [CGFloat]) -> Path {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in pts.indices {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            var dx = b.x - a.x, dy = b.y - a.y
            let l = max(1e-6, (dx * dx + dy * dy).squareRoot())
            dx /= l; dy /= l
            let w = widths[i]
            left.append(CGPoint(x: pts[i].x - dy * w, y: pts[i].y + dx * w))
            right.append(CGPoint(x: pts[i].x + dy * w, y: pts[i].y - dx * w))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    nonisolated private static func gauss(_ rng: inout SeededRandom) -> Double {
        (rng.unit() + rng.unit() + rng.unit() + rng.unit() - 2) * 1.732
    }

    nonisolated private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Plain sRGB colour maths (cheap, no UIKit round-trips).
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

        nonisolated func desaturated(_ t: Double) -> Tone {
            let l = 0.3 * r + 0.59 * g + 0.11 * b
            return mixed(Tone(r: l, g: l, b: l), t)
        }

        /// Raises the darkest colours so they still read when added as light.
        nonisolated func lifted(_ t: Double) -> Tone {
            let m = max(r, g, b)
            guard m < 0.75 else { return self }
            let k = 1 + t * (0.75 - m) / max(0.05, m) * 2
            return Tone(r: min(1, r * k), g: min(1, g * k), b: min(1, b * k))
        }

        nonisolated func color(_ opacity: Double) -> Color {
            Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
        }
    }
}
