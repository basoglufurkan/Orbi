import SwiftUI

/// Procedural drawing of every celestial object, shared by the universe
/// renderer, the focus scene, the celebration and the detail views so the
/// same star always looks the same. Pure vector + gradient work on a
/// `GraphicsContext`; no bitmap assets.
enum CelestialPainter {
    struct PlanetPalette {
        var highlight: Color
        var mid: Color
        var shadow: Color
        var ring: Color

        static func named(_ name: String) -> PlanetPalette {
            switch name {
            case "aqua": PlanetPalette(highlight: Color(hex: 0xD8FBFF), mid: Color(hex: 0x70E1F5), shadow: Color(hex: 0x1F4E7A), ring: Color(hex: 0xBDEFF7))
            case "amber": PlanetPalette(highlight: Color(hex: 0xFFF1C9), mid: Color(hex: 0xFFB86B), shadow: Color(hex: 0x6B3A5E), ring: Color(hex: 0xFFD58A))
            case "violet": PlanetPalette(highlight: Color(hex: 0xE9E4FF), mid: Color(hex: 0x8B7CFF), shadow: Color(hex: 0x231B5C), ring: Color(hex: 0xC4BCFF))
            case "jade": PlanetPalette(highlight: Color(hex: 0xE2FFF1), mid: Color(hex: 0x6FD8B0), shadow: Color(hex: 0x173F4A), ring: Color(hex: 0xA8F0D2))
            default: PlanetPalette(highlight: Color(hex: 0xFFE3A3), mid: Color(hex: 0xF29BB8), shadow: Color(hex: 0x3A2C6E), ring: Color(hex: 0xE8C48A))
            }
        }
    }

    static func color(forHue hue: String) -> Color {
        if let category = FocusCategory(rawValue: hue) { return category.color }
        switch hue {
        case "seed": return Color(hex: Palette.softWhite)
        case "gold": return Color(hex: Palette.warmGold)
        case "moon": return Color(hex: 0xDDE6F2)
        default: return Color(hex: Palette.cosmicViolet)
        }
    }

    // MARK: Glow

    static func glow(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, intensity: Double) {
        guard radius > 0.5, intensity > 0.001 else { return }
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: color.opacity(intensity), location: 0),
                .init(color: color.opacity(intensity * 0.35), location: 0.35),
                .init(color: color.opacity(0), location: 1),
            ]), center: p, startRadius: 0, endRadius: radius))
    }

    // MARK: Star

    /// A category star, drawn like starlight through a lens: a wide coloured
    /// halo, slim tapering rays in the category's count (4 work, 5 study,
    /// 6 coding, 8 creative; reading is a round heart with long hairline rays), a
    /// shorter set of rays between them, and a small white-hot core.
    /// The brightest stars add long diffraction spikes.
    static func star(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, points: Int,
                     color: Color, brightness: Double = 1, flare: Bool = false, detailed: Bool = true) {
        let b = max(0, min(1.6, brightness))
        if !detailed {
            let dot = ctx.environment.colorScheme == .light ? Color(hex: Palette.cosmicViolet) : color
            glow(&ctx, at: p, radius: radius * 1.6, color: dot, intensity: 0.35 * min(1, b))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius * 0.45, y: p.y - radius * 0.45, width: radius * 0.9, height: radius * 0.9)),
                     with: .color((ctx.environment.colorScheme == .light ? dot : .white).opacity(0.95 * min(1, b))))
            return
        }
        if ctx.environment.colorScheme == .light {
            // Dawn: white light vanishes on a pale sky, so the same star is drawn
            // in deep, saturated colour with a soft ink edge.
            glow(&ctx, at: p, radius: radius * 2.2, color: color, intensity: 0.25 * b)
            let rays = sparkle(center: p, radius: radius * 1.5, points: max(points, 4), waist: points == 0 ? 0.08 : 0.18)
            // Near-white reading stars need far more ink to show on a pale sky.
            let ink = Color(hex: Palette.midnightIndigo).opacity(points < 3 ? 0.6 : 0.25)
            let core = radius * 0.34
            let heart = Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2))
            for shape in [rays, heart] {
                ctx.fill(shape, with: .color(color))
                ctx.fill(shape, with: .color(ink))
            }
            return
        }

        // Halo: the star's colour spilling into the sky.
        glow(&ctx, at: p, radius: radius * 3.1, color: color, intensity: 0.30 * b)
        glow(&ctx, at: p, radius: radius * 1.2, color: .white, intensity: 0.32 * b)

        if flare {
            var f = ctx
            f.opacity = 0.6 * min(1, b)
            for angle in [0.0, .pi / 2] {
                let len = radius * 4.2
                let a = CGPoint(x: p.x - cos(angle) * len, y: p.y - sin(angle) * len)
                let z = CGPoint(x: p.x + cos(angle) * len, y: p.y + sin(angle) * len)
                var path = Path()
                path.move(to: a)
                path.addLine(to: z)
                f.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), .white, color.opacity(0)]),
                                                     startPoint: a, endPoint: z), lineWidth: 0.7)
            }
        }

        // Rays: long and slim, white at the heart, fading to colour, then nothing.
        let rayGradient = Gradient(stops: [
            .init(color: .white, location: 0),
            .init(color: .white.opacity(0.9), location: 0.18),
            .init(color: color.opacity(0.85), location: 0.45),
            .init(color: color.opacity(0), location: 1),
        ])
        let round = points < 3
        let count = round ? 4 : points
        let long = radius * (round ? 2.5 : 2.2)
        let rays = sparkle(center: p, radius: long, points: count, waist: round ? 0.09 : (count >= 6 ? 0.13 : 0.16))
        var rc = ctx
        rc.opacity = min(1, b)
        rc.fill(rays, with: .radialGradient(rayGradient, center: p, startRadius: 0, endRadius: long))
        // Shorter rays between the long ones give the twinkle its depth.
        let short = sparkle(center: p, radius: long * 0.5, points: count, waist: 0.2, rotation: .pi / Double(count))
        rc.opacity = min(1, b) * 0.55
        rc.fill(short, with: .radialGradient(rayGradient, center: p, startRadius: 0, endRadius: long * 0.5))

        // Core: small and white-hot; reading stars keep a fuller round heart.
        let core = radius * (round ? 0.42 : 0.36)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                 with: .radialGradient(Gradient(stops: [
                     .init(color: .white, location: 0),
                     .init(color: .white, location: 0.55),
                     .init(color: color.opacity(0.9), location: 1),
                 ]), center: p, startRadius: 0, endRadius: core))
    }

    /// Slim, concave rays meeting at a narrow waist, like a lens sparkle.
    /// `waist` is how far from the centre two rays meet, as a fraction of `radius`.
    static func sparkle(center p: CGPoint, radius: CGFloat, points: Int, waist: CGFloat, rotation: Double = 0) -> Path {
        var path = Path()
        let n = max(points, 2)
        func at(_ angle: Double, _ r: CGFloat) -> CGPoint { CGPoint(x: p.x + cos(angle) * r, y: p.y + sin(angle) * r) }
        // Each edge hugs its ray's axis most of the way in, so rays stay needle-thin.
        let hug = radius * 0.22
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi - .pi / 2 + rotation
            let mid = a + .pi / Double(n)
            let next = a + 2 * .pi / Double(n)
            let valley = at(mid, radius * waist)
            if i == 0 { path.move(to: at(a, radius)) }
            path.addCurve(to: valley, control1: at(a, hug), control2: at(mid, radius * waist * 0.6))
            path.addCurve(to: at(next, radius), control1: at(mid, radius * waist * 0.6), control2: at(next, hug))
        }
        path.closeSubpath()
        return path
    }

    // MARK: Planet

    static func planet(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, palette: PlanetPalette,
                       ringTilt: Double = -0.22, ringOpacity: Double = 1, light: Double = 1, showRing: Bool = true) {
        glow(&ctx, at: p, radius: r * 2.3, color: palette.mid, intensity: 0.28 * light)

        let ringRadius = r * 1.75
        let squash = 0.24
        func ringArc(from: Double, to: Double) -> Path {
            var path = Path()
            path.addArc(center: .zero, radius: ringRadius, startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
            return path.applying(CGAffineTransform(scaleX: 1, y: squash)
                .concatenating(CGAffineTransform(rotationAngle: ringTilt))
                .concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
        }
        if showRing, ringOpacity > 0 {
            var back = ctx
            back.opacity = ringOpacity * 0.7
            back.stroke(ringArc(from: .pi, to: 2 * .pi), with: .color(palette.ring.opacity(0.75)), lineWidth: max(1, r * 0.05))
            back.stroke(ringArc(from: .pi, to: 2 * .pi).applying(scaleAbout(p, 0.86)), with: .color(palette.ring.opacity(0.28)), lineWidth: max(1.5, r * 0.11))
        }

        let sphere = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: palette.highlight, location: 0),
                .init(color: palette.mid, location: 0.42),
                .init(color: palette.shadow, location: 1),
            ]), center: CGPoint(x: p.x - r * 0.32, y: p.y - r * 0.36), startRadius: 0, endRadius: r * 1.55))
        // Terminator shading for a sense of volume.
        ctx.fill(sphere, with: .linearGradient(
            Gradient(colors: [.clear, .black.opacity(0.32)]),
            startPoint: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.2), endPoint: CGPoint(x: p.x + r, y: p.y + r)))

        if showRing, ringOpacity > 0 {
            var front = ctx
            front.opacity = ringOpacity
            front.stroke(ringArc(from: 0, to: .pi), with: .color(palette.ring), lineWidth: max(1, r * 0.05))
            front.stroke(ringArc(from: 0, to: .pi).applying(scaleAbout(p, 0.86)), with: .color(palette.ring.opacity(0.35)), lineWidth: max(1.5, r * 0.11))
        }
    }

    // MARK: Moon

    static func moon(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, light: Double = 1) {
        glow(&ctx, at: p, radius: r * 2.6, color: Color(hex: 0xCFE3FF), intensity: 0.22 * light)
        let sphere = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(sphere, with: .radialGradient(
            Gradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xDCE3EE), Color(hex: 0x8D97AE)]),
            center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.6))
        for (dx, dy, s) in [(-0.3, 0.12, 0.2), (0.22, -0.3, 0.11), (0.3, 0.3, 0.08)] {
            let c = CGPoint(x: p.x + r * dx, y: p.y + r * dy)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: r * s * 2, height: r * s * 2)),
                     with: .color(Color(hex: 0x8D97AE).opacity(0.45)))
        }
    }

    // MARK: Nebula

    static func nebula(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, hue: String, seed: UInt64, intensity: Double = 1) {
        let colors: [Color]
        switch hue {
        case "roseVeil": colors = [Color(hex: Palette.nebulaPink), Color(hex: Palette.cosmicViolet), Color(hex: 0xC56BCB)]
        case "ostrasReach": colors = [Color(hex: Palette.starlightCyan), Color(hex: 0x3D6DD8), Color(hex: Palette.cosmicViolet)]
        case "outerDrift": colors = [Color(hex: Palette.warmGold), Color(hex: Palette.nebulaPink), Color(hex: 0x7A5CFF)]
        default: colors = [Color(hex: Palette.cosmicViolet), Color(hex: Palette.nebulaPink), Color(hex: Palette.starlightCyan)]
        }
        var rng = SeededRandom(seed: seed)
        for i in 0..<5 {
            let c = CGPoint(x: p.x + rng.range(-0.45, 0.45) * r, y: p.y + rng.range(-0.3, 0.3) * r)
            glow(&ctx, at: c, radius: r * rng.range(0.45, 0.8), color: colors[i % colors.count], intensity: 0.16 * intensity)
        }
    }

    // MARK: Comet

    static func comet(_ ctx: inout GraphicsContext, at p: CGPoint, angle: Double, length: CGFloat, color: Color) {
        let tail = CGPoint(x: p.x - cos(angle) * length, y: p.y - sin(angle) * length)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: p)
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.8)]),
                                               startPoint: tail, endPoint: p), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        glow(&ctx, at: p, radius: 14, color: color, intensity: 0.7)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white))
    }

    // MARK: Helpers

    private static func scaleAbout(_ p: CGPoint, _ s: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -p.x, y: -p.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
    }
}
