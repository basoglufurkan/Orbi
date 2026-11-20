import SwiftUI

/// Draws a `UniverseScene` through a camera. Stateless; called from a
/// `Canvas` closure. Culls everything outside the viewport and drops to a
/// cheap level of detail when zoomed far out. With `Options.sprites` the
/// expensive objects come from bitmaps (`SkySprites`), so moving the sky
/// costs little more than moving pictures.
enum UniverseRenderer {
    struct Options {
        var time: Double?
        var selectedID: UUID?
        var dark = true
        var showLabels = true
        var showGhost = true
        /// Lines between the stars of each constellation.
        var showConstellations = true
        /// Today's dashed chain and its frame.
        var showToday = true
        var starOpacity: Double = 1
        var extraLight: Double = 0
        /// Floors for drawn sizes, so a sky framed whole (a share card) stays legible.
        var minimumStarRadius: CGFloat = 1.2
        var minimumPlanetRadius: CGFloat = 0
        /// Draw stars with their points and flares at any zoom.
        var alwaysDetailed = false
        /// Bitmap cache for a live, moving sky; nil draws everything as vectors (share cards).
        var sprites: SkySprites?
        var displayScale: CGFloat = 3
    }

    static func starRadius(_ s: CelestialSnapshot) -> CGFloat { 3 + 2.6 * s.scale }
    static let planetRadius: CGFloat = 44
    static let moonRadius: CGFloat = 12
    static let odysseyWorldRadius: CGFloat = 30
    static let odysseyGalaxyRadius: CGFloat = 115

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, scene: UniverseScene,
                     camera: UniverseCamera, options: Options) {
        let zoom = camera.zoom
        let viewport = CGRect(origin: .zero, size: size).insetBy(dx: -80, dy: -80)
        let detailed = options.alwaysDetailed || zoom >= 0.45
        let t = options.time
        let light = min(1, scene.ambientLight + options.extraLight)
        if options.dark { ctx.blendMode = .plusLighter }

        // 1 · Region washes (open regions glow, closed ones barely).
        for region in UniverseRegion.allCases {
            let p = camera.toScreen(region.center, size: size)
            let r = CGFloat(820 * zoom)
            guard viewport.insetBy(dx: -r, dy: -r).contains(p) else { continue }
            let open = scene.openRegions.contains(region)
            CelestialPainter.glow(&ctx, at: p, radius: r, color: Color(hex: region.hue),
                                  intensity: (open ? 0.10 + 0.08 * light : 0.035) * (options.dark ? 1 : 0.6))
        }

        // 2 · Nebulae.
        for n in scene.nebulae {
            let p = camera.toScreen(n.position, size: size)
            let r = CGFloat(260 * n.scale * zoom)
            guard viewport.insetBy(dx: -r, dy: -r).contains(p) else { continue }
            let intensity = ((1 + light * 0.3) * 10).rounded() / 10
            if let sprites = options.sprites,
               let s = sprites.sprite("nebula|\(n.hue)|\(n.seed)|\(intensity)", radius: r, maxRadius: 64, extent: 2.6,
                                      scale: 1, dark: options.dark, draw: { c, at, radius in
                                          c.blendMode = .plusLighter
                                          CelestialPainter.nebula(&c, at: at, radius: radius, hue: n.hue, seed: n.seed, intensity: intensity)
                                      }) {
                ctx.drawSprite(s.image, madeRadius: s.radius, extent: 2.6, at: p, radius: r)
            } else {
                CelestialPainter.nebula(&ctx, at: p, radius: r, hue: n.hue, seed: n.seed, intensity: 1 + light * 0.3)
            }
        }

        ctx.blendMode = .normal

        // 2b · Ignited Odyssey galaxies, glowing behind the days they ignited.
        for g in scene.galaxies {
            let p = camera.toScreen(g.center, size: size)
            let r = odysseyGalaxyRadius * zoom
            guard viewport.insetBy(dx: -r * 2.2, dy: -r * 2.2).contains(p) else { continue }
            if let sprites = options.sprites,
               let s = sprites.sprite("galaxy|\(g.blueprint.seed)", radius: r, maxRadius: 180, extent: 4.6,
                                      scale: min(2, options.displayScale), dark: options.dark, draw: { c, at, radius in
                                          GalaxyPainter.draw(&c, galaxy: g.blueprint, center: at, radius: radius,
                                                             brightness: 0.5, time: nil, locked: false)
                                      }) {
                ctx.drawSprite(s.image, madeRadius: s.radius, extent: 4.6, at: p, radius: r)
            } else {
                GalaxyPainter.draw(&ctx, galaxy: g.blueprint, center: p, radius: r, brightness: 0.5, time: t, locked: false)
            }
            if options.showLabels, zoom >= 0.4 {
                label(&ctx, g.blueprint.name.uppercased(), size: 10, weight: .bold, tracking: 1.4,
                      color: options.dark ? Palette.warmGold : 0x9A6200, at: CGPoint(x: p.x, y: p.y + r * 0.95 + 12), options)
            }
        }

        // 3 · Constellation lines.
        let lineColor = options.dark ? Color.white : Color(hex: 0x5B4BE0)
        for c in scene.constellations where options.showConstellations {
            var path = Path()
            let pts = c.points.map { camera.toScreen($0, size: size) }
            guard pts.contains(where: { viewport.contains($0) }) else { continue }
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(lineColor.opacity(0.32 * options.starOpacity)), lineWidth: 1)
        }
        // 3b · Bridges of light to friends you focused with.
        for b in scene.bridges {
            let a = camera.toScreen(b.star, size: size), f = camera.toScreen(b.friend, size: size)
            guard viewport.contains(a) || viewport.contains(f) else { continue }
            var line = Path()
            line.move(to: a)
            line.addLine(to: f)
            var glow = ctx
            if options.dark { glow.blendMode = .plusLighter }
            let gradient = Gradient(colors: [Color(hex: Palette.warmGold), Color(hex: Palette.starlightCyan)])
            glow.stroke(line, with: .linearGradient(gradient, startPoint: a, endPoint: f),
                        style: StrokeStyle(lineWidth: min(4, max(2, 3.5 * zoom)), lineCap: .round))
            glow.opacity = 0.9
            ctx.stroke(line, with: .linearGradient(gradient, startPoint: a, endPoint: f),
                       style: StrokeStyle(lineWidth: min(1.4, max(1, 1.2 * zoom)), lineCap: .round))
            // A spark travels the bridge, back and forth.
            if let t {
                let u = (sin(t * 0.9 + Double(b.seed % 100)) + 1) / 2
                let p = CGPoint(x: a.x + (f.x - a.x) * u, y: a.y + (f.y - a.y) * u)
                CelestialPainter.glow(&glow, at: p, radius: max(4, 10 * zoom), color: .white, intensity: 0.8)
            }
            CelestialPainter.star(&glow, at: f, radius: max(2, 6 * zoom), points: 4,
                                  color: Color(hex: Palette.starlightCyan), brightness: 1.1, flare: zoom > 0.6, detailed: zoom >= 0.45)
            if options.showLabels, zoom >= 0.6 {
                label(&ctx, b.friendName, size: 11, weight: .semibold, color: options.dark ? Palette.starlightCyan : 0x0F7A90,
                      at: CGPoint(x: f.x, y: f.y + max(12, 14 * zoom)), options)
            }
        }

        if options.showToday, scene.todayChain.count >= 2 {
            var path = Path()
            let pts = scene.todayChain.map { camera.toScreen($0, size: size) }
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(Color(hex: Palette.starlightCyan).opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        // 4 · Today marker.
        if options.showToday, options.showLabels, let b = scene.todayBounds, zoom > 0.5 {
            let o = camera.toScreen(WorldPoint(x: b.minX, y: b.minY), size: size)
            let rect = CGRect(x: o.x, y: o.y, width: b.width * zoom, height: b.height * zoom)
            if viewport.intersects(rect) {
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 18), with: .color(Color(hex: Palette.starlightCyan).opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                label(&ctx, String(localized: "TODAY"), size: 10, weight: .bold, tracking: 1.4,
                      color: options.dark ? Palette.starlightCyan : 0x0F7A90, at: CGPoint(x: rect.midX, y: rect.minY - 10), options)
            }
        }

        // 5 · Ghost of the next world.
        if options.showGhost, let g = scene.ghost {
            let p = camera.toScreen(g.position, size: size)
            let r = planetRadius * zoom
            if viewport.contains(p) {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(lineColor.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                if options.showLabels {
                    label(&ctx, g.name, size: 13, weight: .semibold, color: options.dark ? 0xB9BCE3 : 0x454A78,
                          at: CGPoint(x: p.x, y: p.y + r + 14), options)
                    label(&ctx, g.detail, size: 12, weight: .medium, color: options.dark ? 0x8C90C2 : 0x5E6290,
                          at: CGPoint(x: p.x, y: p.y + r + 31), options)
                }
            }
        }

        // 6 · Locked regions.
        if options.showLabels {
            for region in UniverseRegion.allCases where !scene.openRegions.contains(region) {
                let p = camera.toScreen(region.center, size: size)
                guard viewport.contains(p) else { continue }
                if let sprites = options.sprites,
                   let lock = sprites.label("lock-symbol", scale: options.displayScale, content: {
                       AnyView(Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(Color(hex: 0x8C90C2)))
                   }) {
                    ctx.draw(lock, at: CGPoint(x: p.x, y: p.y - 14))
                } else {
                    ctx.draw(Text(Image(systemName: "lock")).font(.system(size: 12)).foregroundStyle(Color(hex: 0x8C90C2)),
                             at: CGPoint(x: p.x, y: p.y - 14))
                }
                label(&ctx, region.displayName, size: 12, weight: .semibold, color: options.dark ? 0xB9BCE3 : 0x454A78, at: p, options)
                label(&ctx, String(localized: "Opens at \(region.unlockSessions) sessions"), size: 11, weight: .regular,
                      color: 0x8C90C2, at: CGPoint(x: p.x, y: p.y + 15), options)
            }
        }

        // 6b · Odyssey worlds, beside the stars of the sessions that formed them.
        for v in scene.voyages {
            let p = camera.toScreen(v.position, size: size)
            let r = max(options.minimumPlanetRadius * 0.8, odysseyWorldRadius * zoom)
            guard viewport.insetBy(dx: -r * 2.4, dy: -r * 2.4).contains(p) else { continue }
            let world = v.world
            if let sprites = options.sprites,
               let s = sprites.sprite("world|\(world.blueprint.seed)|\(world.stage.rawValue)|\(v.charted)", radius: r,
                                      maxRadius: 100, extent: 4.8, scale: options.displayScale, dark: options.dark,
                                      draw: { c, at, radius in
                                          WorldPainter.draw(&c, world: world.blueprint, center: at, radius: radius,
                                                            stage: world.stage, time: nil, silhouette: !v.charted)
                                      }) {
                ctx.drawSprite(s.image, madeRadius: s.radius, extent: 4.8, at: p, radius: r)
            } else {
                WorldPainter.draw(&ctx, world: world.blueprint, center: p, radius: r, stage: world.stage,
                                  time: t, silhouette: !v.charted)
            }
            if options.showLabels, zoom >= 0.45 {
                label(&ctx, world.blueprint.name, size: 12, weight: .semibold, color: options.dark ? 0xB9BCE3 : 0x454A78,
                      at: CGPoint(x: p.x, y: p.y + r * 1.5 + 12), options)
            }
        }

        if options.dark { ctx.blendMode = .plusLighter }

        // 7 · Planets and moons.
        for planet in scene.planets {
            let p = camera.toScreen(planet.position, size: size)
            let r = max(options.minimumPlanetRadius, planetRadius * zoom)
            guard viewport.insetBy(dx: -r * 2, dy: -r * 2).contains(p) else { continue }
            var pc = ctx
            pc.blendMode = .normal
            CelestialPainter.planet(&pc, at: p, radius: r, palette: .named(planet.hue),
                                    ringTilt: -0.22 + Double(planet.seed % 20) / 100, light: 0.8 + light * 0.4,
                                    showRing: planet.ordinal != 2)
        }
        for moon in scene.moons {
            var pos = moon.position
            if let t, let planet = scene.planets.first(where: { moon.linkedOrdinals.first == $0.ordinal }) {
                let angle = t * 2 * .pi / 120
                let dx = moon.position.x - planet.position.x, dy = moon.position.y - planet.position.y
                pos = WorldPoint(x: planet.position.x + dx * cos(angle) - dy * sin(angle),
                                 y: planet.position.y + dx * sin(angle) + dy * cos(angle))
            }
            let p = camera.toScreen(pos, size: size)
            guard viewport.contains(p) else { continue }
            var mc = ctx
            mc.blendMode = .normal
            CelestialPainter.moon(&mc, at: p, radius: moonRadius * zoom)
        }
        for comet in scene.comets {
            let p = camera.toScreen(comet.position, size: size)
            guard viewport.contains(p) else { continue }
            let drift = t.map { sin($0 / 7 + Double(comet.seed % 9)) * 3 } ?? 0
            CelestialPainter.comet(&ctx, at: CGPoint(x: p.x + drift, y: p.y), angle: Double(comet.seed % 314) / 100 - 0.6,
                                   length: 60 * zoom, color: Color(hex: Palette.warmGold))
        }

        // 8 · Stars (culled, LOD).
        for star in scene.stars {
            let p = camera.toScreen(star.position, size: size)
            guard viewport.contains(p) else { continue }
            var twinkle = 1.0, breathe = 1.0
            if let t {
                let speed: Double = 0.5 + Double(star.seed % 7) / 7
                let phase: Double = Double(star.seed % 628) / 100
                // Light flickers a little faster than the rays breathe.
                twinkle = 0.84 + 0.16 * sin(t * speed + phase)
                breathe = 0.95 + 0.05 * sin(t * speed * 0.6 + phase * 1.7)
            }
            let r = max(options.minimumStarRadius, starRadius(star) * zoom) * breathe
            let color = CelestialPainter.color(forHue: star.hue)
            let points = star.category?.starPoints ?? 4
            let flare = star.scale > 1.15 && detailed
            // Sprites carry the steady brightness; the twinkle is the bitmap's opacity.
            let base = ((0.85 + light * 0.3) * options.starOpacity * 20).rounded() / 20
            if detailed, let sprites = options.sprites,
               let s = sprites.sprite("star|\(points)|\(star.hue)|\(flare)|\(base)", radius: r, maxRadius: 40,
                                      extent: flare ? 8.8 : 6.6, scale: options.displayScale, dark: options.dark,
                                      draw: { c, at, radius in
                                          CelestialPainter.star(&c, at: at, radius: radius, points: points, color: color,
                                                                brightness: base, flare: flare, detailed: true)
                                      }) {
                var sc = ctx
                sc.opacity = twinkle
                sc.drawSprite(s.image, madeRadius: s.radius, extent: flare ? 8.8 : 6.6, at: p, radius: r)
            } else {
                CelestialPainter.star(&ctx, at: p, radius: r, points: points, color: color,
                                      brightness: twinkle * (0.85 + light * 0.3) * options.starOpacity,
                                      flare: flare, detailed: detailed)
            }
        }

        // 9 · The starter star.
        if let seed = scene.seed {
            let p = camera.toScreen(seed.position, size: size)
            if viewport.contains(p) {
                let twinkle = t.map { 0.9 + 0.1 * sin($0 * 0.8) } ?? 1
                CelestialPainter.star(&ctx, at: p, radius: max(2, 7 * zoom), points: 4,
                                      color: Color(hex: Palette.warmGold), brightness: twinkle, flare: false, detailed: detailed)
            }
        }

        ctx.blendMode = .normal

        // 10 · Selection.
        if let id = options.selectedID, let o = scene.all.first(where: { $0.id == id }) {
            let p = camera.toScreen(o.position, size: size)
            let r = max(18, CGFloat(o.footprint) * zoom + 8)
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(hex: Palette.starlightCyan).opacity(0.8)), lineWidth: 1.2)
        }
    }

    /// A label: a cached bitmap on a live sky, typeset directly otherwise.
    private static func label(_ ctx: inout GraphicsContext, _ string: String, size: CGFloat, weight: Font.Weight,
                              tracking: CGFloat = 0, color: UInt32, at point: CGPoint, _ options: Options) {
        let text = Text(string).font(.system(size: size, weight: weight)).lmTracking(tracking).foregroundStyle(Color(hex: color))
        if let sprites = options.sprites {
            if let image = sprites.label("\(string)|\(size)|\(weight)|\(tracking)|\(color)", scale: options.displayScale,
                                         content: { AnyView(text) }) {
                ctx.draw(image, at: point)
            } else {
                ctx.draw(text, at: point)
            }
        } else {
            ctx.draw(text, at: point)
        }
    }

    /// Nearest Odyssey world within a 44pt target, or one's drawn disc.
    static func hitTestVoyage(_ point: CGPoint, scene: UniverseScene, camera: UniverseCamera, size: CGSize) -> WorldState? {
        var best: (WorldState, CGFloat)?
        for v in scene.voyages {
            let p = camera.toScreen(v.position, size: size)
            let d = hypot(p.x - point.x, p.y - point.y)
            let target = max(22, odysseyWorldRadius * 1.2 * camera.zoom)
            if d <= target, d < (best?.1 ?? .infinity) { best = (v.world, d) }
        }
        return best?.0
    }

    /// Nearest tappable object within a 44pt target (independent of drawn size).
    static func hitTest(_ point: CGPoint, scene: UniverseScene, camera: UniverseCamera, size: CGSize) -> CelestialSnapshot? {
        var best: (CelestialSnapshot, CGFloat)?
        for o in scene.all {
            let p = camera.toScreen(o.position, size: size)
            let d = hypot(p.x - point.x, p.y - point.y)
            let target = max(22, CGFloat(o.footprint) * camera.zoom)
            if d <= target, d < (best?.1 ?? .infinity) { best = (o, d) }
        }
        return best?.0
    }
}
