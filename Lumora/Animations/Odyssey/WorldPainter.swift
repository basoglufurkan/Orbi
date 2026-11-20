import SwiftUI

/// Procedural art for discoverable worlds. Pure vector and gradient drawing
/// on a `GraphicsContext`; deterministic from the blueprint's seed.
///
/// Contract:
/// - `center`/`radius` are the planet disc; extras (rings, moons, halos,
///   twin partner, fragments) may extend to about 2.4 × radius.
/// - `stage` layers terraforming on top of the class look; every stage must
///   look clearly more beautiful than the one before.
/// - `time` (seconds; nil = static frame) drives slow motion only.
/// - `silhouette` draws an unexplored world: a dark disc with rim light.
enum WorldPainter {
    nonisolated static func draw(_ ctx: inout GraphicsContext, world: WorldBlueprint, center: CGPoint, radius r: CGFloat,
                                 stage: WorldStage, time: Double?, silhouette: Bool = false) {
        guard r > 0.5 else { return }
        let k = Kit(world: world, center: center, radius: Double(r), stage: stage.rawValue, time: time,
                    dark: ctx.environment.colorScheme != .light)
        if silhouette {
            Art.silhouette(&ctx, k)
            return
        }
        switch world.archetype {
        case .twin: Art.twin(&ctx, k)
        case .ringworld: Art.ringworld(&ctx, k)
        default: Art.world(&ctx, k)
        }
    }
}

/// A self-animating world, sized by its frame.
struct WorldView: View {
    var world: WorldBlueprint
    var stage: WorldStage = .discovered
    var silhouette = false
    var animate = true
    /// Planet radius as a fraction of the smaller side (room for rings/halos).
    var scale: CGFloat = 0.36

    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let live = animate && motion.animatesContinuously && scenePhase == .active
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side * scale
            // Rings, moons and wonders may reach ~2.2 × radius: draw into a
            // canvas that overflows the frame instead of clipping them. The
            // layout size and hit area stay the frame.
            let pad = radius * 0.8
            TimelineView(.animation(minimumInterval: motion.frameInterval(20), paused: !live)) { tl in
                Canvas { ctx, size in
                    WorldPainter.draw(&ctx, world: world, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                      radius: radius, stage: stage,
                                      time: live ? tl.date.timeIntervalSinceReferenceDate : nil, silhouette: silhouette)
                }
            }
            .frame(width: geo.size.width + pad * 2, height: geo.size.height + pad * 2)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

// MARK: - Toolkit

/// Everything one drawing call needs, precomputed once.
private struct Kit {
    var world: WorldBlueprint
    var a: WorldArchetype
    var c: CGPoint
    var r: Double
    var stage: Int
    var t: Double
    var live: Bool
    var lod: Int
    var lx: Double
    var ly: Double
    var hi: UInt32
    var mid: UInt32
    var sh: UInt32
    var acc: UInt32
    var atm: UInt32
    var dark: Bool
    var tilt: Double
    var spin: Double
    /// Spin at time zero: features placed at `x - spin0` face the viewer in static frames.
    var spin0: Double
    var globe: Globe
    var twinIndex = 0

    init(world: WorldBlueprint, center: CGPoint, radius: Double, stage: Int, time: Double?, dark: Bool) {
        self.world = world
        a = world.archetype
        c = center
        r = radius
        self.stage = stage
        t = time ?? 0
        live = time != nil
        lod = Kit.lod(for: radius)
        lx = cos(world.lightAngle)
        ly = sin(world.lightAngle)
        let p = world.palette
        hi = p.highlight; mid = p.mid; sh = p.shadow; acc = p.accent; atm = p.atmosphere
        self.dark = dark
        tilt = world.tilt
        var rng = SeededRandom(seed: world.seed ^ 0x5017)
        let phase = rng.range(0, 2 * .pi)
        let period = rng.range(220, 320)
        spin0 = phase
        spin = phase + t * 2 * .pi / period
        globe = Globe(c: center, r: radius, spin: spin, tilt: world.tilt)
    }

    static func lod(for r: Double) -> Int { r >= 40 ? 2 : (r >= 15 ? 1 : 0) }

    mutating func move(to p: CGPoint, radius: Double) {
        c = p
        r = radius
        lod = Kit.lod(for: radius)
        globe = Globe(c: p, r: radius, spin: spin, tilt: tilt)
    }

    /// A point in planet units (1 = radius) around the centre.
    func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: Double(c.x) + x * r, y: Double(c.y) + y * r) }
    /// A point toward the light (negative = away from it).
    func lit(_ f: Double) -> CGPoint { P(lx * f, ly * f) }
    var cover: Path { disc(c, r * 1.04) }
    func rng(_ salt: UInt64) -> SeededRandom { SeededRandom(seed: world.seed ^ salt) }
    /// Additive light outside the disc only on dark backgrounds.
    var add: GraphicsContext.BlendMode { dark ? .plusLighter : .normal }
    func lw(_ f: Double, _ minimum: Double = 0.5) -> CGFloat { CGFloat(max(minimum, r * f)) }
    func pick(_ large: Int, _ small: Int, _ tiny: Int) -> Int { lod == 2 ? large : (lod == 1 ? small : tiny) }
    func phase(_ speed: Double, _ period: Double) -> CGFloat {
        guard period > 0 else { return 0 }
        return CGFloat((t * speed).truncatingRemainder(dividingBy: period))
    }
    /// 1 on the night side, -1 on the day side, for a unit-disc offset.
    func night(_ x: Double, _ y: Double) -> Double { -(x * lx + y * ly) }
}

/// Orthographic sphere projection with spin, a slight pitch toward the
/// viewer (so latitudes curve) and the world's axial tilt.
private struct Globe {
    let c: CGPoint
    let r: Double
    let spin: Double
    let tilt: Double
    private let ct: Double, st: Double, cp: Double, sp: Double

    init(c: CGPoint, r: Double, spin: Double, tilt: Double, pitch: Double = 0.3) {
        self.c = c; self.r = r; self.spin = spin; self.tilt = tilt
        ct = cos(tilt); st = sin(tilt); cp = cos(pitch); sp = sin(pitch)
    }

    func unit(_ lon: Double, _ lat: Double) -> (x: Double, y: Double, z: Double) {
        let cl = cos(lat), a = lon + spin
        let x0 = cl * sin(a), y0 = -sin(lat), z0 = cl * cos(a)
        let y1 = y0 * cp + z0 * sp
        let z1 = z0 * cp - y0 * sp
        return (x0 * ct - y1 * st, x0 * st + y1 * ct, z1)
    }

    /// Screen point; hidden points are pinned to the limb.
    func screen(_ u: (x: Double, y: Double, z: Double)) -> CGPoint {
        var x = u.x, y = u.y
        if u.z < 0 {
            let d = max(1e-6, (x * x + y * y).squareRoot())
            x /= d; y /= d
        }
        return CGPoint(x: Double(c.x) + x * r, y: Double(c.y) + y * r)
    }

    func point(_ lon: Double, _ lat: Double) -> CGPoint { screen(unit(lon, lat)) }

    /// A round surface spot of angular radius `s`, foreshortened toward the limb.
    func spot(_ lon: Double, _ lat: Double, _ s: Double, into path: inout Path) {
        let u = unit(lon, lat)
        guard u.z > -0.02 else { return }
        let z = max(0.12, u.z)
        let rad = s * r
        let p = screen(u)
        let e = Path(ellipseIn: CGRect(x: -rad * z, y: -rad, width: 2 * rad * z, height: 2 * rad))
        path.addPath(e, transform: CGAffineTransform(rotationAngle: atan2(u.y, u.x))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
    }

    /// Maps a local, screen-sized frame onto the surface at lon/lat.
    func frame(_ lon: Double, _ lat: Double) -> (t: CGAffineTransform, z: Double)? {
        let u = unit(lon, lat)
        guard u.z > 0.03 else { return nil }
        let ang = atan2(u.y, u.x)
        let p = screen(u)
        let t = CGAffineTransform(rotationAngle: tilt - ang)
            .concatenating(CGAffineTransform(scaleX: u.z, y: 1))
            .concatenating(CGAffineTransform(rotationAngle: ang))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
        return (t, u.z)
    }

    /// An organic blob (continent, sea, lake) around lon/lat.
    func blob(_ lon: Double, _ lat: Double, _ size: Double, _ jit: [Double]) -> Path? {
        guard unit(lon, lat).z > -size * 0.9 else { return nil }
        let k = 1 / max(0.35, cos(lat))
        let n = jit.count
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let rr = size * jit[i]
            pts.append(point(lon + rr * cos(a) * k, lat + rr * sin(a)))
        }
        return smoothClosed(pts)
    }

    /// A surface curve; only the visible runs are added.
    func curve(_ ll: [(Double, Double)], into path: inout Path, smooth: Bool = true) {
        var run: [CGPoint] = []
        run.reserveCapacity(ll.count)
        for (lon, lat) in ll {
            let u = unit(lon, lat)
            if u.z > 0 {
                run.append(screen(u))
            } else {
                Globe.flush(&run, &path, smooth)
            }
        }
        Globe.flush(&run, &path, smooth)
    }

    private static func flush(_ run: inout [CGPoint], _ path: inout Path, _ smooth: Bool) {
        if run.count >= 2 {
            if smooth { smoothOpen(run, into: &path) } else { path.addLines(run) }
        }
        run.removeAll(keepingCapacity: true)
    }
}

/// A tilted ellipse around a centre (rings, orbits, halos). Angles in
/// 0...π are the near (front) half, π...2π the far half.
private struct Orbit {
    let c: CGPoint
    let a: Double
    let squash: Double
    let rot: Double

    func point(_ th: Double) -> CGPoint {
        let x = a * cos(th), y = a * squash * sin(th)
        return CGPoint(x: Double(c.x) + x * cos(rot) - y * sin(rot), y: Double(c.y) + x * sin(rot) + y * cos(rot))
    }

    func arc(_ a0: Double, _ a1: Double, _ n: Int = 36) -> Path {
        var p = Path()
        p.addLines((0...n).map { point(a0 + (a1 - a0) * Double($0) / Double(n)) })
        return p
    }

    func half(front: Bool, _ n: Int = 36) -> Path { front ? arc(0, .pi, n) : arc(.pi, 2 * .pi, n) }

    /// Half of a flat annulus between absolute radii `ri` and `ro`.
    func band(_ ri: Double, _ ro: Double, front: Bool, _ n: Int = 30) -> Path {
        let a0 = front ? 0.0 : Double.pi
        let outer = Orbit(c: c, a: ro, squash: squash, rot: rot)
        let inner = Orbit(c: c, a: ri, squash: squash, rot: rot)
        var pts: [CGPoint] = []
        pts.reserveCapacity(2 * n + 2)
        for i in 0...n { pts.append(outer.point(a0 + .pi * Double(i) / Double(n))) }
        for i in 0...n { pts.append(inner.point(a0 + .pi * Double(n - i) / Double(n))) }
        var p = Path()
        p.addLines(pts)
        p.closeSubpath()
        return p
    }
}

private func mixHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func m(_ s: UInt32) -> UInt32 {
        let x = Double((a >> s) & 0xFF), y = Double((b >> s) & 0xFF)
        return UInt32(max(0, min(255, (x + (y - x) * t).rounded()))) << s
    }
    return m(16) | m(8) | m(0)
}

private func C(_ h: UInt32, _ o: Double = 1) -> Color { Color(hex: h, opacity: max(0, min(1, o))) }

private func fract(_ x: Double) -> Double { x - floor(x) }

private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

private func disc(_ p: CGPoint, _ rad: Double) -> Path {
    Path(ellipseIn: CGRect(x: Double(p.x) - rad, y: Double(p.y) - rad, width: rad * 2, height: rad * 2))
}

private func dotRect(_ p: CGPoint, _ s: Double) -> CGRect {
    CGRect(x: Double(p.x) - s, y: Double(p.y) - s, width: s * 2, height: s * 2)
}

private func smoothClosed(_ p: [CGPoint]) -> Path {
    var path = Path()
    let n = p.count
    guard n > 2 else { return path }
    path.move(to: mid(p[n - 1], p[0]))
    for i in 0..<n { path.addQuadCurve(to: mid(p[i], p[(i + 1) % n]), control: p[i]) }
    path.closeSubpath()
    return path
}

private func smoothOpen(_ p: [CGPoint], into path: inout Path) {
    guard p.count >= 2 else { return }
    path.move(to: p[0])
    if p.count == 2 {
        path.addLine(to: p[1])
        return
    }
    for i in 1..<(p.count - 1) { path.addQuadCurve(to: mid(p[i], p[i + 1]), control: p[i]) }
    path.addLine(to: p[p.count - 1])
}

/// Smoothed random radii around 1 for organic outlines.
private func jitter(_ n: Int, _ rough: Double, _ rng: inout SeededRandom) -> [Double] {
    let raw = (0..<n).map { _ in 1 + rng.range(-rough, rough) }
    return (0..<n).map { i in (raw[(i + n - 1) % n] + raw[i] * 2 + raw[(i + 1) % n]) / 4 }
}

private func radial(_ stops: [(UInt32, Double, Double)], _ center: CGPoint, _ r0: Double, _ r1: Double) -> GraphicsContext.Shading {
    .radialGradient(Gradient(stops: stops.map { Gradient.Stop(color: C($0.0, $0.1), location: $0.2) }),
                    center: center, startRadius: r0, endRadius: max(r0 + 0.01, r1))
}

private func linear(_ stops: [(UInt32, Double, Double)], _ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading {
    .linearGradient(Gradient(stops: stops.map { Gradient.Stop(color: C($0.0, $0.1), location: $0.2) }), startPoint: a, endPoint: b)
}

private func glow(_ ctx: inout GraphicsContext, _ p: CGPoint, _ rad: Double, _ hex: UInt32, _ a: Double) {
    guard rad > 0.4, a > 0.002 else { return }
    ctx.fill(disc(p, rad), with: radial([(hex, a, 0), (hex, a * 0.4, 0.35), (hex, 0, 1)], p, 0, rad))
}

// MARK: - Art

private enum Art {

    // MARK: Pipelines

    static func world(_ ctx: inout GraphicsContext, _ k: Kit) {
        if k.stage >= 5 { wonder(&ctx, k, front: false) }
        backdrop(&ctx, k)
        halo(&ctx, k)
        orbiters(&ctx, k, front: false)
        body(&ctx, k)
        foreground(&ctx, k)
        orbiters(&ctx, k, front: true)
        if k.stage >= 5 { wonder(&ctx, k, front: true) }
    }

    /// The clipped planet: surface, terraforming layers and lighting.
    static func body(_ ctx: inout GraphicsContext, _ k: Kit) {
        let shape = bodyPath(k)
        ctx.drawLayer { l in
            l.clip(to: shape)
            surface(&l, k)
            if k.stage == 0 { l.fill(k.cover, with: .color(C(mixHex(k.sh, 0x10122E, 0.5), 0.14))) }
            if k.stage >= 2 { flow(&l, k) }
            clouds(&l, k)
            if k.world.hasRings, k.a != .ringworld { ringShadow(&l, k) }
            nightMask(&l, k)
            if k.stage >= 3 { bloom(&l, k) }
            if k.stage >= 4 { cities(&l, k) }
            rim(&l, k)
            specular(&l, k)
        }
    }

    static func bodyPath(_ k: Kit) -> Path {
        switch k.a {
        case .crystal:
            var rng = k.rng(0xB0D1)
            let n = 13
            var pts: [CGPoint] = []
            for i in 0..<n {
                let a = (Double(i) + rng.range(-0.25, 0.25)) / Double(n) * 2 * .pi + k.tilt
                let rr = rng.range(0.95, 1.03)
                pts.append(k.P(cos(a) * rr, sin(a) * rr))
            }
            var p = Path()
            p.addLines(pts)
            p.closeSubpath()
            return p
        case .shattered:
            var rng = k.rng(0xB0D2)
            let n = 26
            let notch = Int(rng.next() % UInt64(n))
            let notch2 = (notch + 9 + Int(rng.next() % 5)) % n
            var pts: [CGPoint] = []
            for i in 0..<n {
                let a = (Double(i) + rng.range(-0.3, 0.3)) / Double(n) * 2 * .pi
                var rr = rng.range(0.97, 1.01)
                if i == notch || i == notch2 {
                    rr = 0.83
                } else if (i + 1) % n == notch || (i + n - 1) % n == notch || (i + 1) % n == notch2 {
                    rr = 0.93
                }
                pts.append(k.P(cos(a) * rr, sin(a) * rr))
            }
            var p = Path()
            p.addLines(pts)
            p.closeSubpath()
            return p
        default:
            return disc(k.c, k.r)
        }
    }

    static func base(_ l: inout GraphicsContext, _ k: Kit, _ c0: UInt32, _ c1: UInt32, _ c2: UInt32) {
        l.fill(k.cover, with: radial([(c0, 1, 0), (c1, 1, 0.45), (c2, 1, 1)], k.lit(0.42), 0, k.r * 1.55))
    }

    // MARK: Lighting

    static func halo(_ ctx: inout GraphicsContext, _ k: Kit) {
        let st = Double(k.stage)
        var scale = 1.0
        switch k.a {
        case .phantom: scale = 1.3
        case .dysonPearl: scale = 0.6
        case .crystal: scale = 0.85
        default: break
        }
        let a = (k.stage == 0 ? 0.2 : 0.4 + 0.06 * st) * scale
        let reach = k.stage == 0 ? 1.24 : 1.38 + 0.04 * st
        let hc = k.lit(0.06)
        let e = 1 / reach
        ctx.fill(disc(hc, k.r * reach), with: radial([(k.atm, 0, 0), (k.atm, 0, e * 0.9), (k.atm, a, e),
                                                       (k.atm, a * 0.3, e + (1 - e) * 0.35), (k.atm, 0, 1)],
                                                      hc, 0, k.r * reach))
    }

    static func nightMask(_ l: inout GraphicsContext, _ k: Kit) {
        let s: Double
        switch k.a {
        case .phantom: s = 0.5
        case .dysonPearl: return
        case .livingEye: s = 0.8
        default: s = 0.92
        }
        l.fill(k.cover, with: radial([(0x03041A, 0, 0), (0x03041A, 0, 0.3), (0x03041A, s * 0.5, 0.47), (0x03041A, s * 0.86, 0.64),
                                      (0x03041A, s, 0.8)], k.lit(0.45), 0, k.r * 1.45))
    }

    static func rim(_ l: inout GraphicsContext, _ k: Kit) {
        let st = Double(k.stage)
        var scale = 1.0
        switch k.a {
        case .phantom: scale = 1.4
        case .dysonPearl: scale = 0.5
        case .crystal: scale = 0.7
        case .ember: scale = 0.8
        default: break
        }
        let a0 = (k.stage == 0 ? 0.14 : 0.3 + 0.03 * st) * scale
        let a1 = (k.stage == 0 ? 0.3 : 0.6 + 0.05 * st) * scale
        l.blendMode = .plusLighter
        l.fill(k.cover, with: radial([(k.atm, 0, 0), (k.atm, 0, 0.8), (k.atm, a0 * 0.3, 0.93), (k.atm, a0, 1)], k.c, 0, k.r))
        l.fill(k.cover, with: radial([(k.atm, 0, 0), (k.atm, 0, 0.8), (k.atm, a1, 1)], k.lit(-0.3), 0, k.r * 1.3))
        l.blendMode = .normal
    }

    static func specular(_ l: inout GraphicsContext, _ k: Kit) {
        var soft = 0.16, sharp = 0.0
        switch k.a {
        case .oceanic: soft = 0.3; sharp = 0.75
        case .ember: soft = 0.12; sharp = 0.6
        case .crystal: soft = 0.08; sharp = 0.4
        case .glacier: soft = 0.12; sharp = 0.3
        case .livingEye: soft = 0.14; sharp = 0.55
        case .reef: soft = 0.22; sharp = 0.3
        case .dysonPearl: soft = 0.2; sharp = 0.45
        case .phantom: soft = 0.1
        default: break
        }
        l.blendMode = .plusLighter
        glow(&l, k.lit(0.5), k.r * 0.5, 0xFFFFFF, soft)
        if sharp > 0 { glow(&l, k.lit(0.58), k.r * 0.14, 0xFFFFFF, sharp) }
        l.blendMode = .normal
    }

    // MARK: Surfaces

    static func surface(_ l: inout GraphicsContext, _ k: Kit) {
        switch k.a {
        case .verdant: verdant(&l, k)
        case .oceanic: oceanic(&l, k)
        case .crystal: crystal(&l, k)
        case .ember: ember(&l, k)
        case .glacier: glacier(&l, k)
        case .gasGiant: gasGiant(&l, k)
        case .machine: machine(&l, k)
        case .shattered: shattered(&l, k)
        case .phantom: phantom(&l, k)
        case .dune: dune(&l, k)
        case .reef: reef(&l, k)
        case .dysonPearl: dyson(&l, k)
        case .livingEye: eye(&l, k)
        case .twin, .ringworld: twinBody(&l, k)
        }
    }

    struct Land { var lon: Double; var lat: Double; var size: Double; var jit: [Double]; var jit2: [Double]; var river: [Double] }

    static func continents(_ k: Kit) -> [Land] {
        var rng = k.rng(0x7E1D)
        let n = k.pick(8, 7, 5)
        var out: [Land] = []
        for i in 0..<8 {
            let lon = Double(i) * 0.8 + rng.range(-0.25, 0.25)
            let lat = rng.range(-0.9, 0.9)
            let size = rng.range(0.38, 0.62)
            let j1 = jitter(14, 0.45, &rng), j2 = jitter(10, 0.55, &rng)
            let river = (0..<6).map { _ in rng.range(-0.6, 0.6) }
            if i < n { out.append(Land(lon: lon, lat: lat, size: size, jit: j1, jit2: j2, river: river)) }
        }
        return out
    }

    static func verdant(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, 0x5CC6E8, 0x1F6FB8, mixHex(k.sh, 0x0A1E4A, 0.6))
        var land = Path(), shelf = Path(), forest = Path()
        for c in continents(k) {
            guard let p = k.globe.blob(c.lon, c.lat, c.size, c.jit) else { continue }
            land.addPath(p)
            if let q = k.globe.blob(c.lon, c.lat, c.size * 1.16, c.jit) { shelf.addPath(q) }
            if k.lod == 2, let q = k.globe.blob(c.lon + c.size * 0.12, c.lat + c.size * 0.05, c.size * 0.5, c.jit2) { forest.addPath(q) }
        }
        l.fill(shelf, with: .color(C(0x7FE3F0, 0.22)))
        l.fill(land, with: linear([(mixHex(k.hi, k.mid, 0.35), 1, 0), (k.mid, 1, 0.4), (mixHex(k.mid, k.sh, 0.45), 1, 1)],
                                  k.lit(1), k.lit(-1)))
        l.fill(forest, with: .color(C(mixHex(k.mid, 0x0E3A2A, 0.5), 0.55)))
        if k.lod >= 1 {
            l.stroke(land, with: .color(C(k.hi, 0.4)), lineWidth: k.lw(0.01, 0.45))
            l.blendMode = .plusLighter
            l.fill(forest, with: .color(C(k.acc, 0.1 + 0.03 * Double(k.stage))))
            l.blendMode = .normal
        }
        var caps = Path()
        k.globe.spot(0, 1.42, 0.34, into: &caps)
        if k.stage >= 2 { verdantRivers(&l, k) }
        k.globe.spot(2, -1.45, 0.28, into: &caps)
        l.fill(caps, with: .color(C(0xFFFFFF, 0.75)))
    }

    /// Rivers of light running from each continent's heart to its coast.
    static func verdantRivers(_ l: inout GraphicsContext, _ k: Kit) {
        var path = Path()
        for c in continents(k) {
            let kk = 1 / max(0.4, cos(c.lat))
            for b in 0..<2 {
                var ang = c.river[0] * 5 + Double(b) * 2.6
                var ll: [(Double, Double)] = []
                for j in 0..<6 {
                    let d = c.size * (0.05 + 0.17 * Double(j))
                    ang += c.river[j] * 0.6
                    ll.append((c.lon + d * cos(ang) * kk, c.lat + d * sin(ang)))
                }
                k.globe.curve(ll, into: &path)
            }
        }
        let dw = k.lw(0.011, 0.85)
        l.blendMode = .plusLighter
        l.stroke(path, with: .color(C(0x7FE8FF, 0.35)), style: StrokeStyle(lineWidth: dw * 3.4, lineCap: .round, lineJoin: .round))
        l.stroke(path, with: .color(C(0xA8F4FF, 0.95)), style: StrokeStyle(lineWidth: dw, lineCap: .round, lineJoin: .round))
        l.blendMode = .normal
        var lakes = Path()
        for c in continents(k) { k.globe.spot(c.lon + c.size * 0.1, c.lat - c.size * 0.15, 0.04, into: &lakes) }
        l.fill(lakes, with: .color(C(0x7FE8FF, 0.9)))
    }

    static func oceanic(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, mixHex(k.hi, k.mid, 0.45), k.mid, k.sh)
        var rng = k.rng(0x0CEA)
        var deep = Path()
        for _ in 0..<4 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-1, 1), s = rng.range(0.35, 0.6)
            let j = jitter(9, 0.35, &rng)
            if k.lod >= 1, let p = k.globe.blob(lon, lat, s, j) { deep.addPath(p) }
        }
        l.fill(deep, with: .color(C(k.sh, 0.3)))
        var shallow = Path(), isles = Path()
        let chains = k.pick(5, 4, 2)
        for i in 0..<5 {
            let lon0 = Double(i) * 1.25 + rng.range(-0.3, 0.3), lat0 = rng.range(-0.85, 0.85), dir = rng.range(-1, 1)
            let sizes = (0..<5).map { _ in rng.range(0.04, 0.09) }
            let jits = (0..<5).map { _ in jitter(7, 0.5, &rng) }
            guard i < chains else { continue }
            for j in 0..<5 {
                let f = Double(j)
                let lon = lon0 + f * 0.14, lat = lat0 + f * 0.08 * dir + 0.05 * sin(f * 2.1)
                k.globe.spot(lon, lat, sizes[j] * 2.4, into: &shallow)
                if let p = k.globe.blob(lon, lat, sizes[j], jits[j]) { isles.addPath(p) }
            }
        }
        l.fill(shallow, with: .color(C(mixHex(k.acc, k.hi, 0.5), 0.34)))
        l.fill(isles, with: linear([(0xF6EBC8, 1, 0), (0x8FD08A, 1, 0.6), (0x4E9A6A, 1, 1)], k.lit(1), k.lit(-1)))
        let sLon = 0.6 - k.spin + k.t * 2 * .pi / 260 + rng.range(-0.3, 0.3), sLat = rng.range(0.35, 0.6)
        storm(&l, k, lon: sLon, lat: sLat, size: 0.34)
    }

    static func storm(_ l: inout GraphicsContext, _ k: Kit, lon: Double, lat: Double, size: Double) {
        let u = k.globe.unit(lon, lat)
        guard u.z > 0.05 else { return }
        var path = Path()
        spiral(k.globe, lon, lat, size, -k.t * 2 * .pi / 70, arms: 3, into: &path)
        l.stroke(path, with: .color(C(0xFFFFFF, 0.22)), style: StrokeStyle(lineWidth: k.lw(0.07, 1.2), lineCap: .round))
        l.stroke(path, with: .color(C(0xFFFFFF, 0.65)), style: StrokeStyle(lineWidth: k.lw(0.022, 0.5), lineCap: .round))
        glow(&l, k.globe.screen(u), k.r * size * 0.45, 0xFFFFFF, 0.55)
    }

    static func spiral(_ g: Globe, _ lon: Double, _ lat: Double, _ size: Double, _ rot: Double, arms: Int, into path: inout Path) {
        let kk = 1 / max(0.35, cos(lat))
        for arm in 0..<arms {
            var ll: [(Double, Double)] = []
            for i in 0..<12 {
                let f = Double(i) / 11
                let ang = rot + Double(arm) * 2 * .pi / Double(arms) + f * 3.6
                let rr = size * (0.1 + 0.9 * f)
                ll.append((lon + rr * cos(ang) * kk, lat + rr * sin(ang)))
            }
            g.curve(ll, into: &path)
        }
    }

    struct Vtx { var p: CGPoint; var x: Double; var y: Double; var z: Double }

    static func crystal(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, k.mid, k.sh)
        let rows = k.pick(8, 6, 4), cols = k.pick(14, 10, 7)
        var rng = k.rng(0xC7A1)
        var grid: [Vtx] = []
        grid.reserveCapacity((rows + 1) * cols)
        for i in 0...rows {
            for j in 0..<cols {
                let jl = (i == 0 || i == rows) ? 0 : rng.range(-0.3, 0.3) * .pi / Double(rows)
                let jo = rng.range(-0.3, 0.3) * 2 * .pi / Double(cols)
                let lat = -Double.pi / 2 + Double.pi * Double(i) / Double(rows) + jl
                let lon = 2 * Double.pi * (Double(j) + (i % 2 == 0 ? 0 : 0.5)) / Double(cols) + jo
                let u = k.globe.unit(lon, lat)
                grid.append(Vtx(p: k.globe.screen(u), x: u.x, y: u.y, z: u.z))
            }
        }
        let noise = (0..<(rows * cols * 2)).map { _ in rng.range(-0.24, 0.24) }
        let ln = (0.8 * 0.8 + 0.6 * 0.6).squareRoot()
        let L = (k.lx * 0.8 / ln, k.ly * 0.8 / ln, 0.6 / ln)
        var buckets = Array(repeating: Path(), count: 5)
        var edges = Path()
        for i in 0..<rows {
            for j in 0..<cols {
                let a = grid[i * cols + j], b = grid[i * cols + (j + 1) % cols]
                let c = grid[(i + 1) * cols + j], d = grid[(i + 1) * cols + (j + 1) % cols]
                for (ti, tri) in [[a, b, d], [a, d, c]].enumerated() {
                    let nx = tri[0].x + tri[1].x + tri[2].x
                    let ny = tri[0].y + tri[1].y + tri[2].y
                    let nz = tri[0].z + tri[1].z + tri[2].z
                    guard nz > -0.3 else { continue }
                    let nl = max(1e-6, (nx * nx + ny * ny + nz * nz).squareRoot())
                    let bright = 0.42 + 0.58 * (nx * L.0 + ny * L.1 + nz * L.2) / nl + noise[(i * cols + j) * 2 + ti]
                    let idx = max(0, min(4, Int(bright * 5)))
                    var tp = Path()
                    tp.addLines([tri[0].p, tri[1].p, tri[2].p])
                    tp.closeSubpath()
                    buckets[idx].addPath(tp)
                    if k.lod >= 1 { edges.addPath(tp) }
                }
            }
        }
        let shades: [UInt32] = [mixHex(k.sh, 0x070616, 0.3), mixHex(k.sh, k.mid, 0.45), mixHex(k.mid, k.sh, 0.15),
                                mixHex(k.mid, k.acc, 0.45), mixHex(k.hi, k.mid, 0.3)]
        for (i, p) in buckets.enumerated() { l.fill(p, with: .color(C(shades[i]))) }
        l.stroke(edges, with: .color(C(k.sh, 0.22)), lineWidth: k.lw(0.009, 0.4))
        l.blendMode = .plusLighter
        l.stroke(edges, with: .color(C(0xFFFFFF, 0.2)), lineWidth: k.lw(0.004, 0.3))
        if k.stage >= 2 {
            // Light runs along a lattice of facet edges.
            var lattice = Path()
            var lr = k.rng(0x1A77)
            for i in 1..<rows {
                for j in 0..<cols where lr.unit() < 0.45 {
                    let a = grid[i * cols + j], b = grid[i * cols + (j + 1) % cols], c = grid[(i + 1) * cols + j]
                    if a.z > 0, b.z > 0 { lattice.move(to: a.p); lattice.addLine(to: b.p) }
                    if a.z > 0, c.z > 0, lr.unit() < 0.5 { lattice.move(to: a.p); lattice.addLine(to: c.p) }
                }
            }
            let dw = k.lw(0.012, 0.85)
            l.stroke(lattice, with: .color(C(k.acc, 0.35)), style: StrokeStyle(lineWidth: dw * 3.5, lineCap: .round))
            l.stroke(lattice, with: .color(C(mixHex(k.acc, 0xFFFFFF, 0.4), 0.95)), style: StrokeStyle(lineWidth: dw, lineCap: .round))
            if k.lod >= 1 {
                l.stroke(lattice, with: .color(C(0xFFFFFF)), style: StrokeStyle(lineWidth: dw * 1.2, lineCap: .round,
                                                                               dash: [dw * 2, dw * 8], dashPhase: -k.phase(dw * 5, dw * 10)))
            }
        }
        // Refraction sparkles at a few facet corners.
        if k.lod >= 1 {
            var s1 = Path(), s2 = Path()
            for i in 0..<9 {
                let v = grid[(i * 37 + 11) % grid.count]
                guard v.z > 0.25 else { continue }
                let s = k.r * (k.lod == 2 ? 0.075 : 0.11)
                let p = v.p
                var st = Path()
                st.addLines([CGPoint(x: p.x, y: p.y - s), CGPoint(x: p.x + s * 0.16, y: p.y - s * 0.16),
                             CGPoint(x: p.x + s, y: p.y), CGPoint(x: p.x + s * 0.16, y: p.y + s * 0.16),
                             CGPoint(x: p.x, y: p.y + s), CGPoint(x: p.x - s * 0.16, y: p.y + s * 0.16),
                             CGPoint(x: p.x - s, y: p.y), CGPoint(x: p.x - s * 0.16, y: p.y - s * 0.16)])
                st.closeSubpath()
                if i % 2 == 0 { s1.addPath(st) } else { s2.addPath(st) }
            }
            let tw = k.live ? 0.5 + 0.5 * sin(k.t * 1.3) : 0.8
            l.fill(s1, with: .color(C(0xFFFFFF, 0.35 + 0.6 * tw)))
            l.fill(s2, with: .color(C(0xFFFFFF, 0.95 - 0.6 * tw)))
        }
        l.blendMode = .normal
    }

    static func ember(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, mixHex(k.sh, 0x6A5470, 0.45), mixHex(k.sh, 0x120A12, 0.4), 0x050207)
        var rng = k.rng(0xE3B)
        let rows = k.pick(7, 5, 4), cols = k.pick(13, 9, 6)
        var nodes: [(Double, Double)] = []
        for i in 0..<rows {
            for j in 0..<cols {
                let lat = -1.25 + 2.5 * Double(i) / Double(rows - 1) + rng.range(-0.12, 0.12)
                let lon = 2 * .pi * (Double(j) + (i % 2 == 0 ? 0 : 0.5)) / Double(cols) + rng.range(-0.18, 0.18)
                nodes.append((lon, lat))
            }
        }
        var cracks = Path()
        for i in 0..<rows {
            for j in 0..<cols {
                let a = nodes[i * cols + j]
                var e = nodes[i * cols + (j + 1) % cols]
                if j + 1 == cols { e.0 += 2 * .pi }
                let skipE = rng.unit() < 0.15, skipS = rng.unit() < 0.22
                let m1 = (rng.range(-0.07, 0.07), rng.range(-0.07, 0.07))
                let m2 = (rng.range(-0.07, 0.07), rng.range(-0.07, 0.07))
                if !skipE {
                    k.globe.curve([a, ((a.0 + e.0) / 2 + m1.0, (a.1 + e.1) / 2 + m1.1), e], into: &cracks, smooth: false)
                }
                if i + 1 < rows, !skipS {
                    let s = nodes[(i + 1) * cols + j]
                    k.globe.curve([a, ((a.0 + s.0) / 2 + m2.0, (a.1 + s.1) / 2 + m2.1), s], into: &cracks, smooth: false)
                }
            }
        }
        let pulse = k.live ? 0.85 + 0.15 * sin(k.t * 0.7) : 0.95
        let round = StrokeStyle(lineWidth: k.lw(0.07, 1.4), lineCap: .round, lineJoin: .round)
        l.blendMode = .plusLighter
        l.stroke(cracks, with: .color(C(k.acc, 0.22 * pulse)), style: round)
        var mid = round
        mid.lineWidth = k.lw(0.022, 0.6)
        l.stroke(cracks, with: .color(C(mixHex(k.mid, k.acc, 0.55), 0.95)), style: mid)
        if k.lod >= 1 {
            var core = round
            core.lineWidth = k.lw(0.008, 0.35)
            l.stroke(cracks, with: .color(C(k.hi, 0.85 * pulse)), style: core)
        }
        for _ in 0..<4 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-0.9, 0.9)
            let u = k.globe.unit(lon, lat)
            if u.z > 0.1 { glow(&l, k.globe.screen(u), k.r * 0.2, k.acc, 0.45 * pulse) }
        }
        l.blendMode = .normal
    }

    static func glacier(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, mixHex(k.mid, k.sh, 0.12), mixHex(k.sh, 0x10183A, 0.3))
        var rng = k.rng(0x61AC)
        var sheets = Path()
        for _ in 0..<5 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-1, 1), s = rng.range(0.3, 0.5)
            let j = jitter(10, 0.4, &rng)
            if let p = k.globe.blob(lon, lat, s, j) { sheets.addPath(p) }
        }
        l.fill(sheets, with: linear([(k.mid, 0.55, 0), (mixHex(k.mid, k.sh, 0.4), 0.6, 1)], k.lit(1), k.lit(-1)))
        if k.lod >= 1 {
            var bands = Path()
            for i in 0..<3 {
                let lat0 = -0.9 + Double(i) * 0.75 + rng.range(-0.1, 0.1)
                k.globe.curve((0...24).map { (Double($0) / 24 * 2 * .pi, lat0 + 0.05 * sin(Double($0) * 1.3)) }, into: &bands)
            }
            l.stroke(bands, with: .color(C(0x7FB8E8, 0.22)), style: StrokeStyle(lineWidth: k.lw(0.08, 1.2), lineCap: .round))
        }
        var crev = Path()
        let n = k.pick(18, 10, 4)
        for i in 0..<16 {
            let lon0 = rng.range(0, 2 * .pi), lat0 = rng.range(-1.1, 1.1), ang = rng.range(0, .pi), len = rng.range(0.45, 1.0)
            let js = (0..<14).map { _ in rng.range(-0.04, 0.04) }
            guard i < n else { continue }
            var ll: [(Double, Double)] = []
            for j in 0..<7 {
                let f = Double(j) / 6
                ll.append((lon0 + cos(ang) * len * f + js[j * 2], lat0 + sin(ang) * len * f * 0.6 + js[j * 2 + 1]))
            }
            k.globe.curve(ll, into: &crev, smooth: false)
        }
        let style = StrokeStyle(lineWidth: k.lw(0.022, 0.6), lineCap: .round, lineJoin: .round)
        l.stroke(crev, with: .color(C(mixHex(k.sh, 0x1B3B7A, 0.3), 0.75)), style: style)
        if k.lod >= 1 {
            l.blendMode = .plusLighter
            l.stroke(crev, with: .color(C(k.acc, 0.45)), lineWidth: k.lw(0.005, 0.35))
            l.blendMode = .normal
        }
    }

    // Gas giant bands live in the planet's tilted frame (unit radius).
    static func gasTransform(_ k: Kit) -> CGAffineTransform {
        CGAffineTransform(scaleX: k.r, y: k.r)
            .concatenating(CGAffineTransform(rotationAngle: k.tilt))
            .concatenating(CGAffineTransform(translationX: k.c.x, y: k.c.y))
    }

    /// A latitude line: the front arc of its projected ellipse, gently turbulent.
    static func gasEdge(_ y0: Double, _ ph: Double, _ t: Double, wobble: Double = 0.014) -> [CGPoint] {
        let xr = max(0.15, (1 - y0 * y0)).squareRoot()
        var pts: [CGPoint] = []
        for i in 0...14 {
            let x = -1.1 + 2.2 * Double(i) / 14
            let q = max(0, 1 - (x / xr) * (x / xr))
            pts.append(CGPoint(x: x, y: y0 + 0.3 * xr * q.squareRoot() + wobble * sin(x * 7 + ph + t * 0.05)))
        }
        return pts
    }

    static func gasGiant(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, k.mid, k.sh)
        var rng = k.rng(0x6A5)
        let n = k.pick(11, 7, 5)
        var edges: [Double] = [-1.3]
        for i in 1..<n { edges.append(-1.05 + 2.1 * Double(i) / Double(n) + rng.range(-0.05, 0.05)) }
        edges.append(1.2)
        let phases = (0...n).map { _ in rng.range(0, 6.28) }
        let colors: [UInt32] = [k.hi, mixHex(k.mid, k.sh, 0.35), k.acc, k.mid, mixHex(k.hi, k.mid, 0.5),
                                mixHex(k.mid, k.sh, 0.55), k.atm]
        let T = gasTransform(k)
        for i in 0..<n {
            let top = gasEdge(edges[i], phases[i], k.t)
            let bottom = gasEdge(edges[i + 1], phases[i + 1], k.t)
            var p = Path()
            p.addLines(top.map { $0.applying(T) })
            p.addLines(bottom.reversed().map { $0.applying(T) })
            p.closeSubpath()
            l.fill(p, with: .color(C(colors[(i * 3 + Int(k.world.seed % 5)) % colors.count], 0.5)))
        }
        if k.lod == 2 {
            var fine = Path()
            for i in 0..<6 {
                let y0 = rng.range(-0.9, 0.9)
                smoothOpen(gasEdge(y0, Double(i) * 1.7, k.t, wobble: 0.02).map { $0.applying(T) }, into: &fine)
            }
            l.stroke(fine, with: .color(C(k.hi, 0.22)), lineWidth: k.lw(0.007, 0.4))
        }
        // The great storm oval, turning slowly.
        let sLon = 0.4 - k.spin + k.t * 2 * .pi / 300 + rng.range(-0.4, 0.4), sLat = rng.range(-0.5, -0.25)
        guard let f = k.globe.frame(sLon, sLat) else { return }
        let w = k.r * 0.2, h = k.r * 0.105
        let shape = CGAffineTransform(scaleX: w, y: h).concatenating(f.t)
        var e = l
        e.concatenate(shape)
        e.fill(disc(.zero, 1.25), with: radial([(mixHex(k.mid, k.sh, 0.4), 0.6, 0.7), (mixHex(k.mid, k.sh, 0.4), 0, 1)], .zero, 0, 1.25))
        e.fill(disc(.zero, 1), with: radial([(mixHex(k.acc, 0xFFFFFF, 0.3), 1, 0), (mixHex(k.mid, 0xC0503A, 0.35), 1, 0.55),
                                             (mixHex(k.mid, k.sh, 0.45), 1, 1)], .zero, 0, 1))
        if k.lod >= 1 {
            let rot = k.t * 2 * .pi / 45
            var swirl = Path()
            swirl.addPath(Orbit(c: .zero, a: 0.62, squash: 0.85, rot: rot).arc(0, 4, 18))
            swirl.addPath(Orbit(c: .zero, a: 0.36, squash: 0.8, rot: rot + 2.5).arc(0, 3.6, 14))
            l.stroke(swirl.applying(shape), with: .color(C(k.hi, 0.55)), style: StrokeStyle(lineWidth: k.lw(0.01, 0.4), lineCap: .round))
            l.stroke(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)).applying(shape),
                     with: .color(C(k.hi, 0.45)), lineWidth: k.lw(0.008, 0.4))
        }
    }

    static func machine(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, k.mid, k.sh)
        var grid = Path()
        let lonN = k.pick(18, 12, 8)
        let latStep = k.lod == 2 ? 0.3 : 0.45
        var lat = -1.2
        while lat <= 1.21 {
            k.globe.curve((0...24).map { (Double($0) / 24 * 2 * .pi, lat) }, into: &grid)
            lat += latStep
        }
        for j in 0..<lonN {
            let lon = Double(j) / Double(lonN) * 2 * .pi
            k.globe.curve((0...10).map { (lon, -1.35 + 2.7 * Double($0) / 10) }, into: &grid)
        }
        l.stroke(grid, with: .color(C(k.sh, 0.38)), lineWidth: k.lw(0.006, 0.35))
        // Equatorial trench with a lit seam.
        var eq = Path()
        k.globe.curve((0...28).map { (Double($0) / 28 * 2 * .pi, 0) }, into: &eq)
        l.stroke(eq, with: .color(C(k.sh, 0.75)), lineWidth: k.lw(0.06, 1.4))
        l.blendMode = .plusLighter
        l.stroke(eq, with: .color(C(k.acc, 0.8)), lineWidth: k.lw(0.012, 0.5))
        l.blendMode = .normal
        // Gear rings turning on the surface.
        var rng = k.rng(0x6EA4)
        let gn = k.pick(3, 2, 1)
        for i in 0..<3 {
            let lon = Double(i) * 2.1 - 0.5 + rng.range(-0.3, 0.3) - k.spin0, glat = rng.range(-0.7, 0.7)
            let size = rng.range(0.28, 0.38), dir: Double = i % 2 == 0 ? 1 : -1
            guard i < gn, let f = k.globe.frame(lon, glat) else { continue }
            gear(&l, k, f.t, size * k.r, dir)
        }
        // A faint grid of lights at the crossings.
        if k.lod >= 1 {
            var dots = Path()
            var dl = -1.2
            while dl <= 1.21 {
                for j in 0..<lonN {
                    let u = k.globe.unit(Double(j) / Double(lonN) * 2 * .pi, dl)
                    guard u.z > 0.15 else { continue }
                    dots.addEllipse(in: dotRect(k.globe.screen(u), max(0.45, k.r * 0.009)))
                }
                dl += latStep
            }
            l.blendMode = .plusLighter
            l.fill(dots, with: .color(C(k.acc, 0.55)))
            l.blendMode = .normal
        }
    }

    static func gear(_ l: inout GraphicsContext, _ k: Kit, _ t: CGAffineTransform, _ R: Double, _ dir: Double) {
        let teeth = R * 0.24
        let outer = disc(.zero, R).applying(t)
        let ph = k.phase(R * 0.05 * dir, teeth * 2)
        l.stroke(outer, with: .color(C(mixHex(k.hi, k.acc, 0.35), 0.95)),
                 style: StrokeStyle(lineWidth: R * 0.16, dash: [teeth, teeth], dashPhase: ph))
        l.stroke(disc(.zero, R * 0.86).applying(t), with: .color(C(k.sh, 0.55)), lineWidth: R * 0.05)
        l.stroke(disc(.zero, R * 0.62).applying(t), with: .color(C(mixHex(k.hi, k.mid, 0.4), 0.8)), lineWidth: R * 0.06)
        l.blendMode = .plusLighter
        l.stroke(disc(.zero, R * 0.4).applying(t), with: .color(C(k.acc, 0.75)),
                 style: StrokeStyle(lineWidth: R * 0.05, dash: [R * 0.12, R * 0.08], dashPhase: -ph))
        l.blendMode = .normal
        l.fill(disc(.zero, R * 0.16).applying(t), with: .color(C(k.hi)))
    }

    /// Seams of the broken core, in screen space around the centre.
    static func seamLines(_ k: Kit) -> (seams: [[CGPoint]], ring: [CGPoint]) {
        var rng = k.rng(0x5A77)
        let rot = k.spin * 0.2
        var seams: [[CGPoint]] = []
        for i in 0..<7 {
            let a0 = Double(i) / 7 * 2 * .pi + rng.range(-0.3, 0.3) + rot
            var a = a0
            var pts = [k.P(cos(a0) * 0.06, sin(a0) * 0.06)]
            for j in 1...5 {
                a += rng.range(-0.28, 0.28)
                let rr = 0.06 + Double(j) * 0.21
                pts.append(k.P(cos(a) * rr, sin(a) * rr))
            }
            seams.append(pts)
        }
        var ring: [CGPoint] = []
        for j in 0...22 {
            let a = Double(j) / 22 * 2 * .pi + rot
            let rr = 0.46 + rng.range(-0.05, 0.05)
            ring.append(k.P(cos(a) * rr, sin(a) * rr))
        }
        return (seams, ring)
    }

    static func shattered(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, k.mid, k.sh)
        let lines = seamLines(k)
        // Alternate plates a shade darker.
        var plates = Path()
        for i in stride(from: 0, to: lines.seams.count - 1, by: 2) {
            plates.addLines(lines.seams[i] + lines.seams[i + 1].reversed())
            plates.closeSubpath()
        }
        l.fill(plates, with: .color(C(k.sh, 0.28)))
        var seams = Path()
        let arms = k.pick(7, 6, 4)
        for (i, s) in lines.seams.enumerated() where i < arms { seams.addLines(s) }
        if k.lod >= 1 { seams.addLines(lines.ring) }
        let pulse = k.live ? 0.8 + 0.2 * sin(k.t * 0.6) : 0.9
        l.blendMode = .plusLighter
        glow(&l, k.c, k.r * 0.75, k.acc, 0.4 * pulse)
        l.stroke(seams, with: .color(C(k.acc, 0.32 * pulse)), style: StrokeStyle(lineWidth: k.lw(0.08, 1.5), lineCap: .round, lineJoin: .round))
        l.stroke(seams, with: .color(C(mixHex(k.acc, 0xFFFFFF, 0.55), 0.95)), style: StrokeStyle(lineWidth: k.lw(0.018, 0.5), lineCap: .round, lineJoin: .round))
        l.blendMode = .normal
    }

    static func phantom(_ l: inout GraphicsContext, _ k: Kit) {
        l.fill(k.cover, with: radial([(k.atm, 0.1, 0), (k.mid, 0.16, 0.55), (k.mid, 0.34, 0.86), (k.atm, 0.6, 1)], k.c, 0, k.r))
        var rng = k.rng(0xF4A7)
        var mist = Path()
        let n = k.pick(6, 4, 2)
        for i in 0..<6 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-0.9, 0.9), size = rng.range(0.25, 0.5)
            guard i < n else { continue }
            spiral(k.globe, lon, lat, size, k.t * 0.02, arms: 2, into: &mist)
        }
        l.stroke(mist, with: .color(C(k.atm, 0.14)), style: StrokeStyle(lineWidth: k.lw(0.13, 1.6), lineCap: .round))
        l.stroke(mist, with: .color(C(k.atm, 0.3)), style: StrokeStyle(lineWidth: k.lw(0.03, 0.5), lineCap: .round))
        let beat = k.live ? 1 + 0.08 * sin(k.t * 2 * .pi / 7) : 1
        l.blendMode = .plusLighter
        glow(&l, k.c, k.r * 0.8 * beat, k.acc, 0.45)
        glow(&l, k.c, k.r * 0.4 * beat, mixHex(k.acc, k.mid, 0.3), 0.6)
        glow(&l, k.c, k.r * 0.16 * beat, 0xFFFFFF, 0.95)
        l.blendMode = .normal
    }

    static func canyonPath(_ k: Kit) -> Path {
        var rng = k.rng(0xCA77)
        var path = Path()
        let n = k.pick(4, 3, 2)
        for i in 0..<4 {
            var lon = Double(i) * 1.6 + rng.range(-0.3, 0.3), lat = rng.range(-0.8, 0.8)
            var dir = rng.range(-0.6, 0.6)
            var ll: [(Double, Double)] = []
            for _ in 0..<9 {
                ll.append((lon, lat))
                dir += rng.range(-0.5, 0.5)
                lon += 0.12 * cos(dir)
                lat += 0.12 * sin(dir)
            }
            var bdir = dir + 1.2
            var blon = ll[4].0, blat = ll[4].1
            var bl: [(Double, Double)] = [ll[4]]
            for _ in 0..<4 {
                bdir += rng.range(-0.4, 0.4)
                blon += 0.1 * cos(bdir)
                blat += 0.1 * sin(bdir)
                bl.append((blon, blat))
            }
            guard i < n else { continue }
            k.globe.curve(ll, into: &path, smooth: false)
            k.globe.curve(bl, into: &path, smooth: false)
        }
        return path
    }

    static func dune(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, k.mid, k.sh)
        var rng = k.rng(0xD07E)
        var ergs = Path(), flats = Path()
        for i in 0..<6 {
            let lon = Double(i) * 1.05 + rng.range(-0.3, 0.3), lat = rng.range(-0.9, 0.9), s = rng.range(0.3, 0.55)
            let j = jitter(10, 0.4, &rng)
            guard let p = k.globe.blob(lon, lat, s, j) else { continue }
            if i % 2 == 0 { ergs.addPath(p) } else { flats.addPath(p) }
        }
        l.fill(ergs, with: .color(C(mixHex(k.mid, k.sh, 0.4), 0.35)))
        l.fill(flats, with: .color(C(k.hi, 0.28)))
        if k.lod >= 1 {
            var rip = Path(), crest = Path()
            let rows = k.lod == 2 ? 20 : 10
            for i in 0..<rows {
                let lat0 = -1.15 + 2.3 * Double(i) / Double(rows - 1)
                var ll: [(Double, Double)] = [], ll2: [(Double, Double)] = []
                for j in 0...28 {
                    let lon = Double(j) / 28 * 2 * .pi
                    let lat = lat0 + 0.035 * sin(lon * 11 + Double(i) * 1.9)
                    ll.append((lon, lat))
                    ll2.append((lon, lat + 0.016))
                }
                k.globe.curve(ll, into: &rip)
                if k.lod == 2 { k.globe.curve(ll2, into: &crest) }
            }
            l.stroke(rip, with: .color(C(k.sh, 0.38)), lineWidth: k.lw(0.011, 0.45))
            l.stroke(crest, with: .color(C(0xFFFFFF, 0.3)), lineWidth: k.lw(0.007, 0.4))
        }
        let canyons = canyonPath(k)
        l.stroke(canyons, with: .color(C(k.hi, 0.45)), style: StrokeStyle(lineWidth: k.lw(0.05, 1.2), lineCap: .round, lineJoin: .round))
        l.stroke(canyons, with: .color(C(mixHex(k.sh, 0x1A0A08, 0.3), 0.85)), style: StrokeStyle(lineWidth: k.lw(0.03, 0.8), lineCap: .round, lineJoin: .round))
        var band = Path()
        k.globe.curve((0...24).map { (Double($0) / 24 * 2 * .pi, 0.3 + 0.08 * sin(Double($0) * 0.8)) }, into: &band)
        l.stroke(band, with: .color(C(k.atm, 0.2)), style: StrokeStyle(lineWidth: k.lw(0.17, 2), lineCap: .round))
    }

    static func reef(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, mixHex(k.hi, k.mid, 0.55), mixHex(k.mid, k.sh, 0.15), k.sh)
        var rng = k.rng(0x4EEF)
        var deep = Path()
        for _ in 0..<3 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-1, 1), s = rng.range(0.4, 0.6)
            let j = jitter(9, 0.35, &rng)
            if let p = k.globe.blob(lon, lat, s, j) { deep.addPath(p) }
        }
        l.fill(deep, with: .color(C(k.sh, 0.28)))
        var land = Path(), tex = Path()
        let n = k.pick(6, 6, 4)
        for i in 0..<6 {
            let lon = Double(i) * 1.05 + rng.range(-0.3, 0.3), lat = rng.range(-0.9, 0.9), size = rng.range(0.26, 0.44)
            let j = jitter(18, 0.62, &rng), j2 = jitter(12, 0.6, &rng)
            let lobe = (rng.range(-0.8, 0.8), rng.range(-0.8, 0.8))
            guard i < n, let p = k.globe.blob(lon, lat, size, j) else { continue }
            land.addPath(p)
            if let q = k.globe.blob(lon + lobe.0 * size, lat + lobe.1 * size, size * 0.55, j2) { land.addPath(q) }
            if k.lod >= 1, let q = k.globe.blob(lon - size * 0.1, lat + size * 0.08, size * 0.45, j2) { tex.addPath(q) }
        }
        l.stroke(land, with: .color(C(k.hi, 0.4)), lineWidth: k.lw(0.09, 1.5))
        l.fill(land, with: linear([(0xFFE0B8, 1, 0), (0xFF9E7A, 1, 0.55), (mixHex(0xE0605A, k.sh, 0.3), 1, 1)], k.lit(1), k.lit(-1)))
        l.fill(tex, with: .color(C(0xD9577A, 0.4)))
        let s = 0.45 + 0.11 * Double(k.stage)
        l.blendMode = .plusLighter
        l.stroke(land, with: .color(C(k.acc, 0.35 * s)), lineWidth: k.lw(0.035, 1))
        l.stroke(land, with: .color(C(k.acc, 0.9 * s)), lineWidth: k.lw(0.008, 0.45))
        l.blendMode = .normal
    }

    static func dysonTiles(_ k: Kit) -> Path {
        var tiles = Path()
        var rng = k.rng(0xD150)
        let rows = k.pick(9, 6, 4)
        let step = Double.pi / Double(rows)
        let hexR = step * (k.lod == 0 ? 0.4 : 0.43)
        for i in 0..<rows {
            let lat = -Double.pi / 2 + step * (Double(i) + 0.5)
            let n = max(3, Int((2 * .pi * cos(lat) / step).rounded()))
            let kk = 1 / max(0.25, cos(lat))
            for j in 0..<n {
                let open = rng.unit() < 0.1
                let lon = (Double(j) + (i % 2 == 0 ? 0 : 0.5)) * 2 * .pi / Double(n)
                guard !open, k.globe.unit(lon, lat).z > -0.1 else { continue }
                var pts: [CGPoint] = []
                for v in 0..<6 {
                    let a = Double(v) * .pi / 3 + .pi / 6
                    pts.append(k.globe.point(lon + hexR * cos(a) * kk, lat + hexR * sin(a)))
                }
                tiles.addLines(pts)
                tiles.closeSubpath()
            }
        }
        return tiles
    }

    static func dyson(_ l: inout GraphicsContext, _ k: Kit) {
        l.fill(k.cover, with: radial([(0xFFFFFF, 1, 0), (k.hi, 1, 0.35), (k.mid, 1, 0.8), (mixHex(k.mid, 0xFF7A3D, 0.5), 1, 1)], k.c, 0, k.r))
        let tiles = dysonTiles(k)
        l.fill(tiles, with: linear([(mixHex(k.sh, k.mid, 0.6), 1, 0), (mixHex(k.sh, 0x1A0C05, 0.2), 1, 0.65), (0x0D0603, 1, 1)],
                                   k.lit(1), k.lit(-1)))
        l.blendMode = .plusLighter
        if k.lod >= 1 { l.stroke(tiles, with: .color(C(k.hi, 0.3)), lineWidth: k.lw(0.006, 0.35)) }
        if k.stage >= 2 {
            let dw = k.lw(0.01, 0.5)
            l.stroke(tiles, with: .color(C(k.acc, 0.3)), lineWidth: dw * 3)
            l.stroke(tiles, with: .color(C(mixHex(k.acc, 0xFFFFFF, 0.5), 0.9)),
                     style: StrokeStyle(lineWidth: dw, lineCap: .round, dash: [dw * 3, dw * 6], dashPhase: -k.phase(dw * 4, dw * 9)))
        }
        l.blendMode = .normal
    }

    static func eyeGaze(_ k: Kit) -> (lon: Double, lat: Double) {
        (-k.spin + 0.18 + 0.22 * sin(k.t / 23), 0.14 + 0.09 * sin(k.t / 31))
    }

    static func veins(_ l: inout GraphicsContext, _ k: Kit, bright: Bool) {
        var rng = k.rng(0x7E1A)
        let g = eyeGaze(k)
        var path = Path()
        let n = k.pick(11, 7, 3)
        for i in 0..<11 {
            let a0 = Double(i) / 11 * 2 * .pi + rng.range(-0.2, 0.2)
            var a = a0
            var ll: [(Double, Double)] = []
            for j in 0..<7 {
                let d = 1.5 - Double(j) * 0.11
                a += rng.range(-0.12, 0.12)
                ll.append((g.lon + d * cos(a), g.lat + d * sin(a) * 0.8))
            }
            var ba = a0 + rng.range(-0.6, 0.6)
            var bl: [(Double, Double)] = [ll[3]]
            for j in 1..<4 {
                ba += rng.range(-0.15, 0.15)
                let d = 1.17 - Double(j) * 0.1
                bl.append((g.lon + d * cos(ba), g.lat + d * sin(ba) * 0.8))
            }
            guard i < n else { continue }
            k.globe.curve(ll, into: &path)
            k.globe.curve(bl, into: &path)
        }
        if bright {
            let dw = k.lw(0.012, 0.5)
            l.blendMode = .plusLighter
            l.stroke(path, with: .color(C(k.acc, 0.3)), style: StrokeStyle(lineWidth: dw * 4, lineCap: .round))
            l.stroke(path, with: .color(C(mixHex(k.acc, 0xFFFFFF, 0.4), 0.9)), style: StrokeStyle(lineWidth: dw, lineCap: .round))
            if k.lod >= 1 {
                l.stroke(path, with: .color(C(0xFFFFFF, 0.9)), style: StrokeStyle(lineWidth: dw * 0.8, lineCap: .round,
                                                                                    dash: [dw * 3, dw * 9], dashPhase: k.phase(dw * 4, dw * 12)))
            }
            l.blendMode = .normal
        } else {
            l.stroke(path, with: .color(C(k.mid, 0.45)), style: StrokeStyle(lineWidth: k.lw(0.011, 0.45), lineCap: .round))
        }
    }

    static func eye(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, mixHex(k.mid, k.sh, 0.3), mixHex(k.sh, k.mid, 0.3), 0x12041A)
        veins(&l, k, bright: false)
        let g = eyeGaze(k)
        guard let f = k.globe.frame(g.lon, g.lat) else { return }
        var e = l
        e.concatenate(f.t)
        let R = k.r * 0.6
        e.fill(disc(.zero, R * 1.18), with: radial([(k.mid, 0, 0.78), (k.mid, 0.4, 0.86), (k.mid, 0, 1)], .zero, 0, R * 1.18))
        e.fill(disc(.zero, R), with: radial([(k.acc, 1, 0), (mixHex(k.acc, k.hi, 0.5), 1, 0.32), (k.mid, 1, 0.62),
                                             (mixHex(k.mid, k.sh, 0.5), 1, 0.9), (k.sh, 1, 1)], .zero, 0, R))
        if k.lod >= 1 {
            var rng = k.rng(0xE7E)
            var f1 = Path(), f2 = Path()
            let n = k.pick(64, 30, 0)
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi + rng.range(-0.04, 0.04)
                let r0 = R * rng.range(0.3, 0.42), r1 = R * rng.range(0.72, 0.96)
                let bend = rng.range(-0.12, 0.12)
                var p = Path()
                p.move(to: CGPoint(x: cos(a) * r0, y: sin(a) * r0))
                p.addQuadCurve(to: CGPoint(x: cos(a + bend) * r1, y: sin(a + bend) * r1),
                               control: CGPoint(x: cos(a + bend * 1.6) * (r0 + r1) / 2, y: sin(a + bend * 1.6) * (r0 + r1) / 2))
                if i % 2 == 0 { f1.addPath(p) } else { f2.addPath(p) }
            }
            e.stroke(f1, with: .color(C(k.hi, 0.32)), lineWidth: R * 0.018)
            e.stroke(f2, with: .color(C(k.acc, 0.32)), lineWidth: R * 0.014)
            e.stroke(disc(.zero, R * 0.5), with: .color(C(k.hi, 0.3)), lineWidth: R * 0.025)
        }
        e.stroke(disc(.zero, R * 0.97), with: .color(C(k.sh, 0.85)), lineWidth: R * 0.07)
        let breathe = k.live ? 1 + 0.08 * sin(k.t * 2 * .pi / 9) : 1
        let pr = R * 0.3 * breathe
        e.fill(disc(.zero, pr), with: radial([(0x030008, 1, 0), (0x14041E, 1, 0.8), (mixHex(k.sh, k.mid, 0.3), 1, 1)], .zero, 0, pr))
        if k.lod >= 1 {
            var sp = Path()
            let rot = k.t * 2 * .pi / 40
            for arm in 0..<3 {
                var pts: [CGPoint] = []
                for i in 0..<10 {
                    let fr = Double(i) / 9
                    let a = -rot + Double(arm) * 2.094 + fr * 3.2
                    let rr = pr * (0.15 + 0.75 * fr)
                    pts.append(CGPoint(x: cos(a) * rr, y: sin(a) * rr))
                }
                smoothOpen(pts, into: &sp)
            }
            e.blendMode = .plusLighter
            e.stroke(sp, with: .color(C(k.mid, 0.5)), style: StrokeStyle(lineWidth: pr * 0.1, lineCap: .round))
            e.blendMode = .normal
        }
        e.fill(disc(CGPoint(x: k.lx * pr * 1.25, y: k.ly * pr * 1.25), pr * 0.22), with: .color(C(0xFFFFFF, 0.85)))
    }

    static func twinBody(_ l: inout GraphicsContext, _ k: Kit) {
        base(&l, k, k.hi, k.mid, k.sh)
        var rng = k.rng(0x7171 &+ UInt64(k.twinIndex))
        var bands = Path()
        for _ in 0..<5 {
            let lat0 = rng.range(-1.0, 1.0), ph = rng.range(0, 6)
            k.globe.curve((0...20).map { (Double($0) / 20 * 2 * .pi, lat0 + 0.06 * sin(Double($0) * 0.9 + ph)) }, into: &bands)
        }
        l.stroke(bands, with: .color(C(k.hi, 0.2)), style: StrokeStyle(lineWidth: k.lw(0.1, 1.2), lineCap: .round))
        var blobs = Path()
        for _ in 0..<4 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-0.8, 0.8), s = rng.range(0.3, 0.5)
            let j = jitter(10, 0.45, &rng)
            if let p = k.globe.blob(lon, lat, s, j) { blobs.addPath(p) }
        }
        l.fill(blobs, with: .color(C(k.twinIndex == 0 ? mixHex(k.mid, k.sh, 0.45) : mixHex(k.hi, k.mid, 0.3), 0.6)))
        if k.twinIndex == 1 {
            var cap = Path()
            k.globe.spot(0, 1.4, 0.4, into: &cap)
            l.fill(cap, with: .color(C(0xFFFFFF, 0.7)))
        }
    }

    // MARK: Stage layers

    static func clouds(_ l: inout GraphicsContext, _ k: Kit) {
        var amount = 0.0
        var color: UInt32 = 0xFFFFFF
        var swirl = false
        switch k.a {
        case .verdant: amount = 0.6; swirl = true
        case .oceanic: amount = 0.5; swirl = true
        case .reef: amount = 0.3
        case .twin: amount = 0.3
        case .glacier: amount = 0.25
        case .dune: color = mixHex(k.hi, 0xFFFFFF, 0.4)
        case .ember: color = mixHex(k.acc, 0xFFE2C0, 0.5)
        case .gasGiant: color = mixHex(k.hi, 0xFFFFFF, 0.5)
        case .phantom, .shattered: color = k.atm
        case .crystal: color = 0xF4EEFF
        case .machine: color = 0xE6F3FF
        case .livingEye: color = mixHex(k.hi, 0xFFFFFF, 0.3)
        case .dysonPearl, .ringworld: return
        }
        if k.stage >= 1 { amount = 1 }
        guard amount > 0 else { return }
        let g = Globe(c: k.c, r: k.r, spin: k.spin * 1.25 + 0.9, tilt: k.tilt)
        var rng = k.rng(0xC10D)
        var outer = Path(), inner = Path()
        let n = k.pick(13, 8, 4)
        let puffs = k.lod == 2 ? 11 : 6
        for i in 0..<13 {
            let lat = asin(rng.range(-0.88, 0.88))
            let lon0 = rng.range(0, 2 * .pi), len = rng.range(0.5, 1.0), size = rng.range(0.07, 0.12), ph = rng.range(0, 6)
            let jit = (0..<11).map { _ in rng.range(0.7, 1.25) }
            let wob = (0..<11).map { _ in rng.range(-0.5, 0.5) }
            guard i < n else { continue }
            let kk = 1 / max(0.4, cos(lat))
            for j in 0..<puffs {
                let f = Double(j) / Double(puffs - 1)
                let lon = lon0 + f * len * kk
                let la = lat + 0.03 * sin(f * 3 + ph + k.t * 0.02) + wob[j] * size * 0.6
                let taper = 0.4 + 0.6 * sin(f * .pi)
                g.spot(lon, la, size * taper * jit[j], into: &outer)
                g.spot(lon + 0.01, la + size * 0.15, size * taper * jit[j] * 0.6, into: &inner)
            }
        }
        if swirl, k.lod >= 1 {
            for c in 0..<2 {
                let lon = Double(c) * 3 + 0.4 - k.spin0 * 1.25 + rng.range(-0.3, 0.3), lat = rng.range(0.3, 0.8) * (c == 0 ? 1 : -1)
                let rot = k.t * 0.04
                let kk = 1 / max(0.4, cos(lat))
                for arm in 0..<2 {
                    for i in 0..<9 {
                        let f = Double(i) / 8
                        let ang = rot + Double(arm) * .pi + f * 3.4
                        let rr = 0.2 * (0.12 + 0.88 * f)
                        g.spot(lon + rr * cos(ang) * kk, lat + rr * sin(ang), 0.045 * (1.1 - 0.5 * f), into: &inner)
                    }
                }
                g.spot(lon, lat, 0.05, into: &outer)
            }
        }
        let alpha = amount * (k.a == .ember ? 0.5 : 1)
        if k.a == .ember { l.blendMode = .plusLighter }
        l.fill(outer, with: .color(C(color, 0.26 * alpha)))
        l.fill(inner, with: .color(C(color, 0.46 * alpha)))
        l.blendMode = .normal
    }

    static func streams(_ l: inout GraphicsContext, _ k: Kit, salt: UInt64, count: Int, color: UInt32, core: UInt32 = 0xFFFFFF,
                        width: Double, lat: Double = 1.1, length: ClosedRange<Double> = 0.7...1.6, polyline: Bool = false,
                        ink: UInt32? = nil) {
        var rng = k.rng(salt)
        var path = Path()
        let n = max(1, count)
        for i in 0..<n {
            let lon0 = Double(i) / Double(n) * 2 * .pi + rng.range(-0.4, 0.4)
            let lat0 = rng.range(-lat, lat)
            let len = rng.range(length.lowerBound, length.upperBound)
            let slope = rng.range(-0.5, 0.5), f1 = rng.range(3, 8), a1 = rng.range(0.04, 0.12), ph = rng.range(0, 6)
            var ll: [(Double, Double)] = []
            for j in 0...10 {
                let f = Double(j) / 10
                ll.append((lon0 + len * f, lat0 + slope * len * f * 0.5 + a1 * sin(f * f1 + ph)))
            }
            k.globe.curve(ll, into: &path, smooth: !polyline)
        }
        let dw = k.lw(width, 0.8)
        if let ink {
            l.stroke(path, with: .color(C(ink, 0.5)), style: StrokeStyle(lineWidth: dw * 2.4, lineCap: .round, lineJoin: .round))
        }
        l.blendMode = .plusLighter
        l.stroke(path, with: .color(C(color, 0.34)), style: StrokeStyle(lineWidth: dw * 3.6, lineCap: .round, lineJoin: .round))
        l.stroke(path, with: .color(C(color, 0.95)), style: StrokeStyle(lineWidth: dw * 1.2, lineCap: .round, lineJoin: .round))
        if k.lod >= 1 {
            l.stroke(path, with: .color(C(core, 0.9)), style: StrokeStyle(lineWidth: dw * 0.7, lineCap: .round,
                                                                         dash: [dw * 3, dw * 10], dashPhase: -k.phase(dw * 4, dw * 13)))
        }
        l.blendMode = .normal
    }

    static func flow(_ l: inout GraphicsContext, _ k: Kit) {
        switch k.a {
        case .verdant:
            l.blendMode = .plusLighter
            l.fill(k.cover, with: radial([(0x7FE8FF, 0.3, 0), (0x7FE8FF, 0, 1)], k.lit(0.35), 0, k.r * 1.1))
            l.blendMode = .normal
        case .oceanic:
            streams(&l, k, salt: 0xF101, count: k.pick(6, 4, 2), color: 0x9BF6FF, width: 0.012, lat: 0.9, length: 1.2...2.2)
        case .reef:
            streams(&l, k, salt: 0xF10B, count: k.pick(6, 4, 2), color: k.acc, width: 0.012, length: 0.9...1.8)
        case .crystal, .dysonPearl:
            break
        case .ember:
            coolSeas(&l, k)
        case .glacier:
            meltLakes(&l, k)
        case .gasGiant:
            jetStreams(&l, k)
        case .machine:
            channels(&l, k)
        case .shattered:
            streams(&l, k, salt: 0xF107, count: k.pick(5, 3, 2), color: k.acc, width: 0.014, polyline: true)
        case .phantom:
            streams(&l, k, salt: 0xF108, count: k.pick(5, 3, 2), color: k.acc, width: 0.012, length: 1.5...2.6)
        case .dune:
            canyonWater(&l, k)
        case .livingEye:
            veins(&l, k, bright: true)
        case .twin, .ringworld:
            streams(&l, k, salt: 0xF10D &+ UInt64(k.twinIndex), count: k.pick(4, 3, 2), color: k.acc, width: 0.016, length: 0.8...1.6)
        }
    }

    static func coolSeas(_ l: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0xC001)
        var seas = Path()
        for _ in 0..<4 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-0.8, 0.8), s = rng.range(0.28, 0.45)
            let j = jitter(10, 0.4, &rng)
            if let p = k.globe.blob(lon, lat, s, j) { seas.addPath(p) }
        }
        l.fill(seas, with: linear([(0x3A5A80, 1, 0), (0x101A33, 1, 1)], k.lit(1), k.lit(-1)))
        l.blendMode = .plusLighter
        l.stroke(seas, with: .color(C(k.acc, 0.32)), lineWidth: k.lw(0.06, 1.5))
        l.stroke(seas, with: .color(C(k.hi, 0.85)), lineWidth: k.lw(0.01, 0.5))
        l.blendMode = .normal
        streams(&l, k, salt: 0xF103, count: k.pick(5, 3, 2), color: 0xFFB13D, core: 0xFFF2C0, width: 0.016, length: 0.5...1.0)
    }

    static func meltLakes(_ l: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0x1A4E)
        var lakes = Path()
        for _ in 0..<8 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-1, 1), s = rng.range(0.06, 0.14)
            k.globe.spot(lon, lat, s, into: &lakes)
        }
        l.blendMode = .plusLighter
        l.stroke(lakes, with: .color(C(0x7DF9FF, 0.3)), lineWidth: k.lw(0.05, 1.4))
        l.blendMode = .normal
        l.fill(lakes, with: linear([(0x6FF0FF, 1, 0), (0x1C7FB8, 1, 1)], k.lit(1), k.lit(-1)))
        l.stroke(lakes, with: .color(C(0xFFFFFF, 0.65)), lineWidth: k.lw(0.008, 0.4))
        streams(&l, k, salt: 0xF104, count: k.pick(6, 4, 2), color: 0x7DF9FF, width: 0.012, length: 0.4...0.9, ink: 0x1C5FA0)
    }

    static func jetStreams(_ l: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0x7E75)
        var path = Path()
        let T = gasTransform(k)
        let n = k.pick(4, 3, 2)
        for i in 0..<4 {
            let y0 = rng.range(-0.75, 0.7), ph = rng.range(0, 6)
            guard i < n else { continue }
            smoothOpen(gasEdge(y0, ph, k.t * 1.6).map { $0.applying(T) }, into: &path)
        }
        let dw = k.lw(0.013, 0.6)
        l.blendMode = .plusLighter
        l.stroke(path, with: .color(C(k.acc, 0.3)), lineWidth: dw * 4)
        l.stroke(path, with: .color(C(mixHex(k.acc, 0xFFFFFF, 0.5), 0.9)),
                 style: StrokeStyle(lineWidth: dw, lineCap: .round, dash: [dw * 8, dw * 5], dashPhase: -k.phase(dw * 6, dw * 13)))
        l.blendMode = .normal
    }

    static func channels(_ l: inout GraphicsContext, _ k: Kit) {
        var path = Path()
        var rng = k.rng(0xC4A7)
        let n = k.pick(9, 6, 3)
        let lonN = Double(k.pick(18, 12, 8))
        for i in 0..<9 {
            let along = rng.unit() < 0.55
            let fixedLat = Double(Int(rng.next() % 9) - 4) * 0.3
            let start = rng.range(0, 2 * .pi), len = rng.range(0.7, 1.5)
            guard i < n else { continue }
            if along {
                k.globe.curve((0...10).map { (start + len * Double($0) / 10, fixedLat) }, into: &path)
            } else {
                let lon = (start * lonN / (2 * .pi)).rounded() * 2 * .pi / lonN
                k.globe.curve((0...10).map { (lon, -1.2 + 2.4 * Double($0) / 10) }, into: &path)
            }
        }
        let dw = k.lw(0.012, 0.6)
        l.blendMode = .plusLighter
        l.stroke(path, with: .color(C(k.acc, 0.3)), style: StrokeStyle(lineWidth: dw * 3.5, lineCap: .round))
        l.stroke(path, with: .color(C(k.acc, 0.85)), style: StrokeStyle(lineWidth: dw, lineCap: .round))
        if k.lod >= 1 {
            l.stroke(path, with: .color(C(0xFFFFFF, 0.95)),
                     style: StrokeStyle(lineWidth: dw * 0.8, lineCap: .round, dash: [dw * 2, dw * 7], dashPhase: -k.phase(dw * 6, dw * 9)))
        }
        l.blendMode = .normal
    }

    static func canyonWater(_ l: inout GraphicsContext, _ k: Kit) {
        let canyons = canyonPath(k)
        l.blendMode = .plusLighter
        l.stroke(canyons, with: .color(C(k.acc, 0.35)), style: StrokeStyle(lineWidth: k.lw(0.055, 1.5), lineCap: .round, lineJoin: .round))
        l.blendMode = .normal
        l.stroke(canyons, with: .color(C(mixHex(k.acc, 0x1E6FA8, 0.3))), style: StrokeStyle(lineWidth: k.lw(0.016, 0.6), lineCap: .round, lineJoin: .round))
        l.blendMode = .plusLighter
        l.stroke(canyons, with: .color(C(0xFFFFFF, 0.6)), style: StrokeStyle(lineWidth: k.lw(0.005, 0.35), lineCap: .round, lineJoin: .round))
        l.blendMode = .normal
        var rng = k.rng(0x0A5E)
        var oases = Path()
        for _ in 0..<6 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-0.9, 0.9), s = rng.range(0.04, 0.08)
            k.globe.spot(lon, lat, s, into: &oases)
        }
        l.stroke(oases, with: .color(C(0x7CFFCB, 0.75)), lineWidth: k.lw(0.025, 0.8))
        l.fill(oases, with: .color(C(k.acc)))
    }

    static func bloomColors(_ k: Kit) -> (UInt32, UInt32) {
        switch k.a {
        case .verdant: (k.acc, 0xFFE27A)
        case .oceanic: (0x7CF5FF, 0xB9A8FF)
        case .reef: (k.acc, 0xFFD58A)
        case .ember: (0xFFD58A, 0x7CFFCB)
        case .glacier: (0x9EFFD8, 0x70E1F5)
        case .gasGiant: (0xFF8FB8, mixHex(k.acc, 0xFFFFFF, 0.3))
        case .machine: (0x7CFFCB, 0x70E1F5)
        case .crystal: (0xFF8FB8, 0x70E1F5)
        case .phantom: (0xFFFFFF, k.acc)
        case .dune: (0x7CFFCB, 0x70E1F5)
        case .shattered: (0xFF8FB8, 0xB9A8FF)
        case .dysonPearl: (0x70E1F5, 0xFFFFFF)
        case .livingEye: (0x7CFFCB, 0xFFD58A)
        case .twin, .ringworld: (k.acc, 0xFFD58A)
        }
    }

    static func bloom(_ l: inout GraphicsContext, _ k: Kit) {
        let (c1, c2) = bloomColors(k)
        var rng = k.rng(0xB100)
        let n = k.pick(52, 24, 9)
        var nightA = Path(), nightB = Path(), day = Path()
        var patches: [CGPoint] = []
        for i in 0..<52 {
            let lon = rng.range(0, 2 * .pi), lat = asin(rng.range(-0.95, 0.95)), s = rng.range(0.011, 0.026)
            guard i < n else { continue }
            let u = k.globe.unit(lon, lat)
            guard u.z > 0.05 else { continue }
            let p = k.globe.screen(u)
            let rect = dotRect(p, max(0.65, k.r * s * (k.lod == 2 ? 1.25 : 1.5)))
            if k.night(u.x, u.y) > -0.2 {
                if i % 2 == 0 { nightA.addEllipse(in: rect) } else { nightB.addEllipse(in: rect) }
                if i % 5 == 0, patches.count < 6 { patches.append(p) }
            } else {
                day.addEllipse(in: rect)
            }
        }
        let tw = k.live ? 0.5 + 0.5 * sin(k.t * 1.1) : 0.7
        l.blendMode = .plusLighter
        l.fill(k.cover, with: radial([(c1, 0.2, 0), (c1, 0.08, 0.6), (c1, 0, 1)], k.lit(-0.6), 0, k.r * 1.1))
        for (i, p) in patches.enumerated() { glow(&l, p, k.r * 0.26, i % 2 == 0 ? c1 : c2, 0.42) }
        l.fill(day, with: .color(C(c1, 0.4)))
        l.fill(nightA, with: .color(C(c1, 0.6 + 0.4 * tw)))
        l.fill(nightB, with: .color(C(c2, 1 - 0.4 * tw)))
        l.blendMode = .normal
    }

    static func cities(_ l: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0xC171)
        let count = k.pick(16, 12, 8)
        let per = k.pick(9, 5, 2)
        var dotsA = Path(), dotsB = Path(), roads = Path()
        var glows: [CGPoint] = []
        let gold: UInt32 = k.a == .machine ? 0x9BEFFF : 0xFFD58A
        for i in 0..<count {
            let lon0 = Double(i) / Double(count) * 2 * .pi + rng.range(-0.15, 0.15)
            let lat0 = rng.range(-1.0, 1.0)
            let offs = (0..<9).map { _ in (rng.range(-0.14, 0.14), rng.range(-0.1, 0.1)) }
            let u = k.globe.unit(lon0, lat0)
            guard u.z > 0.08, k.night(u.x, u.y) > -0.05 else { continue }
            let center = k.globe.screen(u)
            glows.append(center)
            dotsA.addEllipse(in: dotRect(center, max(0.8, k.r * 0.024)))
            for j in 0..<per {
                let p = k.globe.point(lon0 + offs[j].0, lat0 + offs[j].1)
                let rect = dotRect(p, max(0.55, k.r * 0.013))
                if j % 2 == 0 { dotsB.addEllipse(in: rect) } else { dotsA.addEllipse(in: rect) }
                if k.lod == 2 {
                    roads.move(to: center)
                    roads.addLine(to: p)
                }
            }
        }
        l.blendMode = .plusLighter
        for p in glows.prefix(6) { glow(&l, p, k.r * 0.22, gold, 0.6) }
        l.stroke(roads, with: .color(C(gold, 0.4)), lineWidth: k.lw(0.005, 0.4))
        let tw = k.live ? 0.5 + 0.5 * sin(k.t * 0.9 + 1) : 0.7
        l.fill(dotsA, with: .color(C(mixHex(gold, 0xFFFFFF, 0.45), 0.75 + 0.25 * tw)))
        l.fill(dotsB, with: .color(C(gold, 1 - 0.3 * tw)))
        l.blendMode = .normal
    }

    // MARK: Rings and orbiters

    static func orbiters(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        if k.world.hasRings, k.a != .ringworld { rings(&ctx, k, front: front) }
        switch k.a {
        case .machine: machineRing(&ctx, k, front: front)
        case .phantom: ghostRings(&ctx, k, front: front)
        case .shattered: fragments(&ctx, k, front: front)
        default: break
        }
        moons(&ctx, k, front: front)
        if k.stage >= 4 { station(&ctx, k, front: front) }
    }

    static func ringScale(_ k: Kit) -> Double { k.a == .gasGiant ? 1 : 0.92 }

    static func rings(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        let o = Orbit(c: k.c, a: k.r, squash: 0.3, rot: k.tilt)
        let sc = ringScale(k)
        let bands: [(Double, Double, UInt32, Double)]
        if k.lod == 0 {
            bands = [(1.24, 1.62, mixHex(k.hi, k.atm, 0.5), 0.6)]
        } else {
            let ice: UInt32 = 0xE6ECFF
            bands = [(1.22, 1.33, mixHex(mixHex(k.mid, k.sh, 0.25), ice, 0.3), 0.45),
                     (1.345, 1.47, mixHex(mixHex(k.hi, k.atm, 0.5), ice, 0.45), 0.88),
                     (1.5, 1.6, mixHex(mixHex(k.mid, k.hi, 0.45), ice, 0.35), 0.7),
                     (1.625, 1.665, mixHex(k.hi, ice, 0.5), 0.5)]
        }
        let f = front ? 1.0 : 0.9
        for b in bands {
            ctx.fill(o.band(k.r * b.0 * sc, k.r * b.1 * sc, front: front),
                     with: linear([(b.2, b.3 * f, 0), (mixHex(b.2, k.sh, 0.45), b.3 * f * 0.65, 1)], k.lit(1.7), k.lit(-1.7)))
        }
        // The planet's shadow falls across the rings, away from the light.
        var s = ctx
        s.clip(to: shadowCapsule(k))
        s.fill(o.band(k.r * 1.2 * sc, k.r * 1.68 * sc, front: front), with: .color(C(0x05061A, 0.62)))
        if front, k.stage >= 3, k.lod >= 1 {
            // Ice glitter in the rings once life blooms.
            var glit = Path()
            for i in 0..<14 {
                let th = Double(i) * 0.224 + k.t * 2 * .pi / 160
                let rr = (1.3 + 0.3 * fract(Double(i) * 0.618)) * sc
                glit.addEllipse(in: dotRect(Orbit(c: k.c, a: k.r * rr, squash: 0.3, rot: k.tilt).point(th), max(0.5, k.r * 0.01)))
            }
            ctx.blendMode = k.add
            ctx.fill(glit, with: .color(C(0xFFFFFF, 0.8)))
            ctx.blendMode = .normal
        }
    }

    static func shadowCapsule(_ k: Kit) -> Path {
        let px = -k.ly, py = k.lx
        var p = Path()
        p.addLines([k.P(px * 0.98, py * 0.98), k.P(px * 0.98 - k.lx * 3, py * 0.98 - k.ly * 3),
                    k.P(-px * 0.98 - k.lx * 3, -py * 0.98 - k.ly * 3), k.P(-px * 0.98, -py * 0.98)])
        p.closeSubpath()
        return p
    }

    static func ringShadow(_ l: inout GraphicsContext, _ k: Kit) {
        let sc = ringScale(k)
        let o = Orbit(c: k.lit(-0.24), a: k.r, squash: 0.3, rot: k.tilt)
        l.fill(o.band(k.r * 1.22 * sc, k.r * 1.6 * sc, front: true), with: .color(C(0x05061A, 0.24)))
    }

    static func moons(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        guard k.world.moonCount > 0 else { return }
        var rng = k.rng(0x300A)
        let tints: [UInt32] = [0xDCE3EE, k.atm, 0xE8D9C9, 0xC9D6FF]
        for i in 0..<k.world.moonCount {
            let a = 1.42 + 0.2 * Double(i) + rng.range(0, 0.08)
            let sq = rng.range(0.16, 0.32)
            let rot = k.tilt * 0.8 + rng.range(-0.3, 0.3)
            let period = rng.range(40, 120)
            let ph = rng.range(0, 2 * .pi)
            let size = rng.range(0.09, 0.15)
            let tint = tints[Int(rng.next() % 4)]
            let o = Orbit(c: k.c, a: k.r * a, squash: sq, rot: rot)
            if k.lod == 2 {
                ctx.stroke(o.half(front: front, 40), with: .color(C(0xFFFFFF, front ? 0.07 : 0.045)), lineWidth: 0.6)
            }
            let th = ph + k.t * 2 * .pi / period * (i % 2 == 0 ? 1 : -1)
            guard (sin(th) >= 0) == front else { continue }
            moon(&ctx, k, o.point(th), max(1.2, k.r * size * (0.9 + 0.12 * sin(th))), tint)
        }
    }

    static func moon(_ ctx: inout GraphicsContext, _ k: Kit, _ p: CGPoint, _ s: Double, _ tint: UInt32) {
        if k.lod >= 1 {
            ctx.blendMode = k.add
            glow(&ctx, p, s * 2.6, tint, 0.14)
            ctx.blendMode = .normal
        }
        let lp = CGPoint(x: Double(p.x) + k.lx * s * 0.45, y: Double(p.y) + k.ly * s * 0.45)
        ctx.fill(disc(p, s), with: radial([(0xFFFFFF, 1, 0), (tint, 1, 0.45), (mixHex(tint, 0x1A1D3A, 0.75), 1, 1)], lp, 0, s * 1.7))
        if k.lod == 2, s > 4 {
            var cr = Path()
            cr.addEllipse(in: dotRect(CGPoint(x: Double(p.x) - s * 0.3, y: Double(p.y) + s * 0.15), s * 0.2))
            cr.addEllipse(in: dotRect(CGPoint(x: Double(p.x) + s * 0.25, y: Double(p.y) - s * 0.3), s * 0.12))
            ctx.fill(cr, with: .color(C(mixHex(tint, 0x2A2F4A, 0.5), 0.35)))
        }
        let nc = CGPoint(x: Double(p.x) + k.lx * s * 0.5, y: Double(p.y) + k.ly * s * 0.5)
        ctx.fill(disc(p, s), with: radial([(0x05061A, 0, 0), (0x05061A, 0, 0.55), (0x05061A, 0.82, 1)], nc, 0, s * 1.6))
    }

    static func station(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        var rng = k.rng(0x57A7)
        let rot = k.tilt + rng.range(0.35, 0.6)
        let ph = rng.range(0, 2 * .pi)
        let o = Orbit(c: k.c, a: k.r * 1.3, squash: 0.32, rot: rot)
        let o2 = Orbit(c: k.c, a: k.r * 1.13, squash: 0.32, rot: rot)
        if k.lod == 2 {
            ctx.stroke(o.half(front: front, 40), with: .color(C(0xFFFFFF, 0.07)), lineWidth: 0.6)
        }
        var spark = Path()
        let n = k.pick(8, 5, 3)
        for i in 0..<n {
            let th = Double(i) / Double(n) * 2 * .pi + k.t * 2 * .pi / 26 + ph
            guard (sin(th) >= 0) == front else { continue }
            spark.addEllipse(in: dotRect(o2.point(th), max(0.55, k.r * 0.012)))
        }
        ctx.blendMode = k.add
        ctx.fill(spark, with: .color(C(0xFFF3D0, 0.95)))
        ctx.blendMode = .normal
        let th = ph + k.t * 2 * .pi / 50
        guard (sin(th) >= 0) == front else { return }
        let p = o.point(th)
        let q = o.point(th + 0.01)
        let ang = atan2(Double(q.y - p.y), Double(q.x - p.x))
        let s = max(1.6, k.r * 0.065)
        let T = CGAffineTransform(rotationAngle: ang).concatenating(CGAffineTransform(translationX: p.x, y: p.y))
        var panels = Path()
        panels.addRect(CGRect(x: -s * 1.9, y: -s * 0.36, width: s * 1.05, height: s * 0.72))
        panels.addRect(CGRect(x: s * 0.85, y: -s * 0.36, width: s * 1.05, height: s * 0.72))
        var hull = Path()
        hull.addRect(CGRect(x: -s * 0.9, y: -s * 0.09, width: s * 1.8, height: s * 0.18))
        hull.addEllipse(in: CGRect(x: -s * 0.42, y: -s * 0.42, width: s * 0.84, height: s * 0.84))
        ctx.fill(panels.applying(T), with: .color(C(0x6F8CFF, 0.95)))
        ctx.fill(hull.applying(T), with: .color(C(0xEEF1FF)))
        let blink = k.live ? fract(k.t / 1.7 + ph) < 0.2 : true
        ctx.blendMode = k.add
        glow(&ctx, p, s * 2.2, 0xFF8FB8, blink ? 0.85 : 0.25)
        ctx.blendMode = .normal
    }

    static func machineRing(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        let o = Orbit(c: k.c, a: k.r * 1.36, squash: 0.3, rot: k.tilt - 0.12)
        let arc = o.half(front: front, 44)
        ctx.stroke(arc, with: .color(C(k.sh, 0.95)), lineWidth: k.lw(0.05, 1.3))
        ctx.stroke(arc, with: linear([(k.hi, 1, 0), (k.mid, 1, 1)], k.lit(1.4), k.lit(-1.4)), lineWidth: k.lw(0.024, 0.7))
        var docks = Path()
        let rot = k.t * 2 * .pi / 150
        for i in 0..<8 {
            let th = Double(i) / 8 * 2 * .pi + rot
            guard (sin(th) >= 0) == front else { continue }
            let p = o.point(th)
            let s = k.lw(0.035, 1)
            docks.addRect(CGRect(x: p.x - s, y: p.y - s * 0.6, width: s * 2, height: s * 1.2))
        }
        ctx.fill(docks, with: .color(C(k.hi, 0.95)))
        if k.stage >= 2 {
            let dw = k.lw(0.012, 0.6)
            ctx.blendMode = k.add
            ctx.stroke(arc, with: .color(C(k.acc, 0.9)),
                       style: StrokeStyle(lineWidth: dw, lineCap: .round, dash: [dw * 3, dw * 6], dashPhase: -k.phase(dw * 5, dw * 9)))
            if k.stage >= 5 {
                ctx.stroke(arc, with: .color(C(0xFFD58A, 0.25)), lineWidth: k.lw(0.12, 2))
            }
            ctx.blendMode = .normal
        }
    }

    static func ghostRings(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        let n = k.pick(3, 2, 1)
        let lit = k.stage >= 5 ? 0.55 : 0.2 + 0.05 * Double(k.stage)
        ctx.blendMode = k.add
        for i in 0..<n {
            let o = Orbit(c: k.c, a: k.r * (1.2 + 0.2 * Double(i)), squash: 0.26 + 0.05 * Double(i), rot: k.tilt + 0.22 * Double(i) - 0.2)
            let arc = o.half(front: front, 40)
            let f = front ? 1.0 : 0.6
            ctx.stroke(arc, with: .color(C(k.atm, lit * 0.3 * f)), lineWidth: k.lw(0.05, 1.2))
            let d = k.r * 0.06
            ctx.stroke(arc, with: .color(C(k.atm, lit * f)),
                       style: StrokeStyle(lineWidth: k.lw(0.01, 0.5), lineCap: .round, dash: [d, d * 0.6],
                                          dashPhase: k.phase(d * 0.3 * (i % 2 == 0 ? 1 : -1), d * 1.6)))
        }
        ctx.blendMode = .normal
    }

    struct Fragment { var p: CGPoint; var poly: Path; var s: Double; var front: Bool }

    static func fragmentList(_ k: Kit) -> [Fragment] {
        var rng = k.rng(0xF4A6)
        let n = k.pick(8, 6, 4)
        var out: [Fragment] = []
        for i in 0..<8 {
            let a = rng.range(1.18, 1.68), sq = rng.range(0.35, 0.6), rot = k.tilt + rng.range(-0.3, 0.3)
            let period = rng.range(80, 150), ph = rng.range(0, 2 * .pi), size = rng.range(0.09, 0.2)
            let spinRate = rng.range(-0.05, 0.05), nv = 5 + Int(rng.next() % 3)
            let jit = (0..<7).map { _ in rng.range(0.6, 1.1) }
            guard i < n else { continue }
            let th = ph + k.t * 2 * .pi / period
            let p = Orbit(c: k.c, a: k.r * a, squash: sq, rot: rot).point(th)
            let s = k.r * size * (0.9 + 0.12 * sin(th))
            let selfRot = ph + k.t * spinRate
            var poly = Path()
            poly.addLines((0..<nv).map { v in
                let ang = Double(v) / Double(nv) * 2 * .pi + selfRot
                return CGPoint(x: Double(p.x) + cos(ang) * s * jit[v], y: Double(p.y) + sin(ang) * s * jit[v])
            })
            poly.closeSubpath()
            out.append(Fragment(p: p, poly: poly, s: s, front: sin(th) >= 0))
        }
        return out
    }

    static func fragments(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        for f in fragmentList(k) where f.front == front {
            let a = CGPoint(x: Double(f.p.x) + k.lx * f.s, y: Double(f.p.y) + k.ly * f.s)
            let b = CGPoint(x: Double(f.p.x) - k.lx * f.s, y: Double(f.p.y) - k.ly * f.s)
            ctx.fill(f.poly, with: linear([(k.hi, 1, 0), (k.mid, 1, 0.4), (k.sh, 1, 1)], a, b))
            if k.lod >= 1 {
                ctx.blendMode = k.add
                ctx.stroke(f.poly, with: .color(C(k.acc, 0.55)), lineWidth: k.lw(0.012, 0.5))
                ctx.blendMode = .normal
            }
        }
    }

    // MARK: Class extras

    static func backdrop(_ ctx: inout GraphicsContext, _ k: Kit) {
        ctx.blendMode = k.add
        switch k.a {
        case .livingEye: corona(&ctx, k)
        case .dysonPearl:
            glow(&ctx, k.c, k.r * (1.9 + 0.08 * Double(k.stage)), k.hi, 0.32 + 0.04 * Double(k.stage))
            leakRays(&ctx, k)
        case .phantom: glow(&ctx, k.c, k.r * 1.7, k.mid, 0.16 + 0.03 * Double(k.stage))
        case .ember: glow(&ctx, k.c, k.r * 1.55, k.atm, 0.16 + 0.03 * Double(k.stage))
        default: break
        }
        ctx.blendMode = .normal
    }

    static func foreground(_ ctx: inout GraphicsContext, _ k: Kit) {
        switch k.a {
        case .glacier:
            aurora(&ctx, k, strength: 0.6 + 0.1 * Double(k.stage))
            geysers(&ctx, k)
        case .ember: heatHaze(&ctx, k)
        case .crystal: shards(&ctx, k)
        default: break
        }
    }

    static func corona(_ ctx: inout GraphicsContext, _ k: Kit) {
        let breathe = k.live ? 1 + 0.07 * sin(k.t * 2 * .pi / 10) : 1
        let boost = k.stage >= 5 ? 1.45 : 1 + 0.06 * Double(k.stage)
        let n = k.pick(44, 26, 14)
        var rng = k.rng(0xC0A0)
        var rays = Path()
        for i in 0..<n {
            let ang = Double(i) / Double(n) * 2 * .pi + rng.range(-0.05, 0.05)
            let len = rng.range(0.1, 0.24) * breathe * boost
            let w = 0.03
            rays.move(to: k.P(cos(ang - w) * 0.96, sin(ang - w) * 0.96))
            rays.addLine(to: k.P(cos(ang) * (1 + len), sin(ang) * (1 + len)))
            rays.addLine(to: k.P(cos(ang + w) * 0.96, sin(ang + w) * 0.96))
            rays.closeSubpath()
        }
        let outer = 1.5 * breathe * boost
        ctx.fill(rays, with: radial([(k.atm, 0.5, 0), (k.mid, 0.2, 0.45), (k.mid, 0, 1)], k.c, k.r * 0.95, k.r * outer))
        glow(&ctx, k.c, k.r * 1.35 * breathe, k.mid, 0.3)
    }

    static func leakRays(_ ctx: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0x1EA4)
        var rays = Path()
        let n = k.pick(14, 9, 6)
        let boost = 1 + 0.1 * Double(k.stage)
        for i in 0..<14 {
            let ang = rng.range(0, 2 * .pi), len = rng.range(0.35, 0.85), w = rng.range(0.012, 0.035), ph = rng.range(0, 6)
            guard i < n else { continue }
            let pulse = k.live ? 0.7 + 0.3 * sin(k.t * 0.45 + ph) : 0.9
            let tip = 1 + len * pulse * boost
            rays.move(to: k.P(cos(ang - w) * 0.92, sin(ang - w) * 0.92))
            rays.addLine(to: k.P(cos(ang) * tip, sin(ang) * tip))
            rays.addLine(to: k.P(cos(ang + w) * 0.92, sin(ang + w) * 0.92))
            rays.closeSubpath()
        }
        ctx.fill(rays, with: radial([(0xFFFFFF, 0.8, 0), (k.hi, 0.35, 0.35), (k.mid, 0, 1)], k.c, k.r * 0.9, k.r * 2.0))
    }

    static func heatHaze(_ ctx: inout GraphicsContext, _ k: Kit) {
        for i in 0..<2 {
            let f = Double(i)
            let wob = k.live ? sin(k.t * 0.8 + f * 2) : 0.5
            let c = CGPoint(x: Double(k.c.x) + k.r * 0.012 * sin(k.t * 0.6 + f), y: Double(k.c.y) + k.r * 0.012 * cos(k.t * 0.5 + f))
            ctx.stroke(disc(c, k.r * (1.05 + 0.07 * f + 0.015 * wob)), with: .color(C(k.atm, 0.13 - 0.05 * f)), lineWidth: k.lw(0.05, 1))
        }
    }

    static func shards(_ ctx: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0x5A4D)
        let n = k.pick(5, 3, 2)
        let base = atan2(k.ly, k.lx)
        ctx.blendMode = k.add
        for i in 0..<5 {
            let ang = base + rng.range(-1.3, 1.3), len = rng.range(0.3, 0.75), w = rng.range(0.035, 0.07), ph = rng.range(0, 6)
            guard i < n else { continue }
            let pulse = k.live ? 0.85 + 0.15 * sin(k.t * 0.4 + ph) : 1
            let a = k.P(cos(ang - w) * 0.95, sin(ang - w) * 0.95), b = k.P(cos(ang + w) * 0.95, sin(ang + w) * 0.95)
            let tip = k.P(cos(ang) * (1 + len * pulse), sin(ang) * (1 + len * pulse))
            var p = Path()
            p.addLines([a, tip, b])
            p.closeSubpath()
            ctx.fill(p, with: linear([(0xFFFFFF, 0.55, 0), (i % 2 == 0 ? k.acc : k.hi, 0, 1)], k.P(cos(ang) * 0.95, sin(ang) * 0.95), tip))
        }
        ctx.blendMode = .normal
    }

    static func aurora(_ ctx: inout GraphicsContext, _ k: Kit, strength: Double) {
        var ring = Path(), rays = Path()
        for pole in [1.0, -1.0] {
            var ll: [(Double, Double)] = []
            for i in 0...30 {
                let f = Double(i) / 30
                ll.append((f * 2 * .pi - k.spin, pole * (1.12 + 0.06 * sin(f * 2 * .pi * 5 + k.t * 0.2))))
            }
            k.globe.curve(ll, into: &ring)
            if k.lod >= 1 {
                for i in 0..<k.pick(40, 22, 0) {
                    let f = Double(i) / Double(k.pick(40, 22, 1))
                    let lon = f * 2 * .pi - k.spin
                    let lat = pole * (1.12 + 0.06 * sin(f * 2 * .pi * 5 + k.t * 0.2))
                    let len = 0.1 + 0.06 * sin(f * 37 + k.t * 0.5)
                    k.globe.curve([(lon, lat), (lon, lat + pole * len)], into: &rays, smooth: false)
                }
            }
        }
        let green = mixHex(k.acc, 0x9EFFB0, 0.5)
        ctx.blendMode = k.add
        ctx.stroke(ring, with: .color(C(k.acc, 0.2 * strength)), style: StrokeStyle(lineWidth: k.lw(0.13, 2), lineCap: .round))
        ctx.stroke(rays, with: .color(C(green, 0.35 * strength)), style: StrokeStyle(lineWidth: k.lw(0.012, 0.5), lineCap: .round))
        ctx.stroke(ring, with: .color(C(green, 0.6 * strength)), style: StrokeStyle(lineWidth: k.lw(0.025, 0.6), lineCap: .round))
        ctx.blendMode = .normal
    }

    static func geysers(_ ctx: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0x6E75)
        for _ in 0..<4 {
            let lon = rng.range(0, 2 * .pi), lat = rng.range(-0.8, 0.9), ph = rng.range(0, 6)
            let u = k.globe.unit(lon, lat)
            let d = (u.x * u.x + u.y * u.y).squareRoot()
            guard u.z > 0, d > 0.2 else { continue }
            let p = k.globe.screen(u)
            let dx = u.x / d, dy = u.y / d, px = -dy, py = dx
            let pulse = k.live ? 0.6 + 0.4 * sin(k.t * 0.9 + ph) : 0.8
            let len = k.r * (0.14 + 0.14 * pulse) * max(0.25, d)
            let w = k.r * 0.04
            let tip = CGPoint(x: Double(p.x) + dx * len, y: Double(p.y) + dy * len)
            var plume = Path()
            plume.move(to: CGPoint(x: Double(p.x) - px * w * 0.3, y: Double(p.y) - py * w * 0.3))
            plume.addQuadCurve(to: CGPoint(x: Double(tip.x) - px * w * 1.3, y: Double(tip.y) - py * w * 1.3),
                               control: CGPoint(x: Double(p.x) + dx * len * 0.5 - px * w * 0.3, y: Double(p.y) + dy * len * 0.5 - py * w * 0.3))
            plume.addQuadCurve(to: CGPoint(x: Double(tip.x) + px * w * 1.3, y: Double(tip.y) + py * w * 1.3),
                               control: CGPoint(x: Double(tip.x) + dx * w, y: Double(tip.y) + dy * w))
            plume.addQuadCurve(to: CGPoint(x: Double(p.x) + px * w * 0.3, y: Double(p.y) + py * w * 0.3),
                               control: CGPoint(x: Double(p.x) + dx * len * 0.5 + px * w * 0.3, y: Double(p.y) + dy * len * 0.5 + py * w * 0.3))
            plume.closeSubpath()
            ctx.fill(plume, with: linear([(0xFFFFFF, 0.9, 0), (k.atm, 0, 1)], p, tip))
            ctx.blendMode = k.add
            glow(&ctx, p, k.r * 0.08, 0xFFFFFF, 0.6 * pulse)
            ctx.blendMode = .normal
        }
    }

    // MARK: Wonders

    static func wonder(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        if !front { aura(&ctx, k) }
        let lights = k.pick(30, 16, 0)
        switch k.a {
        case .verdant:
            gardens(&ctx, k, front: front, k.acc, 0xFFE27A)
        case .reef:
            gardens(&ctx, k, front: front, k.acc, 0xFFD58A)
        case .oceanic:
            haloRing(&ctx, k, front: front, radius: 1.55, squash: 0.3, rot: k.tilt - 0.3, color: 0x70E1F5, lights: lights)
            if front { elevator(&ctx, k, color: 0x9BF6FF) }
        case .dune:
            haloRing(&ctx, k, front: front, radius: 1.5, squash: 0.3, rot: k.tilt + 0.25, color: 0xFFD58A, lights: lights)
            if front { elevator(&ctx, k, color: 0xFFD58A) }
        case .crystal:
            shardHalo(&ctx, k, front: front)
        case .ember:
            haloRing(&ctx, k, front: front, radius: 1.4, squash: 0.3, rot: k.tilt, color: 0xFF9A6B, lights: lights)
            if front { crown(&ctx, k, color: 0xFFD58A) }
        case .glacier:
            haloRing(&ctx, k, front: front, radius: 1.48, squash: 0.3, rot: k.tilt - 0.2, color: 0xC9F2FF, lights: lights)
            if front { crown(&ctx, k, color: 0x9EFFD8) }
        case .gasGiant:
            haloRing(&ctx, k, front: front, radius: 1.85, squash: 0.42, rot: k.tilt + 0.45, color: 0xFFD58A, lights: lights + 6)
            if front { crown(&ctx, k, color: 0xFFF4DE) }
        case .machine:
            if front {
                crown(&ctx, k, color: 0xFFD58A)
                elevator(&ctx, k, color: 0x70E1F5)
            }
        case .shattered:
            threads(&ctx, k, front: front)
            haloRing(&ctx, k, front: front, radius: 1.26, squash: 0.3, rot: k.tilt + 0.2, color: k.acc, lights: lights)
        case .phantom:
            haloRing(&ctx, k, front: front, radius: 1.75, squash: 0.28, rot: k.tilt + 0.3, color: 0xFFFFFF, lights: lights)
            if front { crown(&ctx, k, color: k.acc) }
        case .dysonPearl:
            haloRing(&ctx, k, front: front, radius: 1.5, squash: 0.3, rot: k.tilt, color: 0xFFD58A, lights: lights)
            if front { jets(&ctx, k) }
        case .livingEye:
            haloRing(&ctx, k, front: front, radius: 1.62, squash: 0.3, rot: k.tilt - 0.15, color: k.acc, lights: lights)
        case .twin, .ringworld:
            break
        }
    }

    static func aura(_ ctx: inout GraphicsContext, _ k: Kit) {
        let col = mixHex(0xFFD58A, k.atm, 0.45)
        ctx.blendMode = k.add
        glow(&ctx, k.c, k.r * 2.2, col, 0.2)
        glow(&ctx, k.c, k.r * 1.75, k.atm, 0.18)
        if k.lod >= 1 {
            var rays = Path()
            let n = 14
            let rot = k.t * 2 * .pi / 240
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi + rot
                let len = i % 2 == 0 ? 2.15 : 1.7
                let w = 0.035
                rays.move(to: k.P(cos(a - w) * 0.9, sin(a - w) * 0.9))
                rays.addLine(to: k.P(cos(a) * len, sin(a) * len))
                rays.addLine(to: k.P(cos(a + w) * 0.9, sin(a + w) * 0.9))
                rays.closeSubpath()
            }
            ctx.fill(rays, with: radial([(col, 0.16, 0), (col, 0.05, 0.5), (col, 0, 1)], k.c, k.r * 0.9, k.r * 2.15))
        }
        ctx.blendMode = .normal
    }

    static func haloRing(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool, radius: Double, squash: Double, rot: Double,
                         color: UInt32, lights: Int) {
        let o = Orbit(c: k.c, a: k.r * radius, squash: squash, rot: rot)
        let arc = o.half(front: front, 48)
        let f = front ? 1.0 : 0.7
        ctx.blendMode = k.add
        ctx.stroke(arc, with: .color(C(color, 0.15 * f)), style: StrokeStyle(lineWidth: k.lw(0.13, 2.5), lineCap: .round))
        ctx.stroke(arc, with: .color(C(color, 0.6 * f)), style: StrokeStyle(lineWidth: k.lw(0.03, 1), lineCap: .round))
        ctx.stroke(arc, with: .color(C(0xFFFFFF, 0.9 * f)), style: StrokeStyle(lineWidth: k.lw(0.008, 0.5), lineCap: .round))
        if lights > 0 {
            var dots = Path()
            let spin = k.t * 2 * .pi / 80
            let s = max(0.7, k.r * 0.016)
            for i in 0..<lights {
                let th = Double(i) / Double(lights) * 2 * .pi + spin
                guard (sin(th) >= 0) == front else { continue }
                dots.addEllipse(in: dotRect(o.point(th), s))
            }
            ctx.fill(dots, with: .color(C(0xFFF6E0, f)))
        }
        ctx.blendMode = .normal
    }

    static func elevator(_ ctx: inout GraphicsContext, _ k: Kit, color: UInt32) {
        let ang = k.tilt - .pi / 2 + 0.3
        let dx = cos(ang), dy = sin(ang)
        let a = k.P(dx * 0.97, dy * 0.97), b = k.P(dx * 1.95, dy * 1.95)
        var beam = Path()
        beam.move(to: a)
        beam.addLine(to: b)
        ctx.blendMode = k.add
        ctx.stroke(beam, with: .color(C(color, 0.18)), style: StrokeStyle(lineWidth: k.lw(0.07, 2), lineCap: .round))
        ctx.stroke(beam, with: .linearGradient(Gradient(colors: [C(0xFFFFFF, 0.95), C(color, 0.85), C(0xFFFFFF, 0.9)]),
                                               startPoint: a, endPoint: b), lineWidth: k.lw(0.012, 0.6))
        var climbers = Path()
        for i in 0..<3 {
            let f = k.live ? fract(k.t / 18 + Double(i) / 3) : Double(i) / 3 + 0.15
            let p = CGPoint(x: Double(a.x) + Double(b.x - a.x) * f, y: Double(a.y) + Double(b.y - a.y) * f)
            climbers.addEllipse(in: dotRect(p, max(0.7, k.r * 0.018)))
        }
        ctx.fill(climbers, with: .color(C(0xFFFFFF)))
        glow(&ctx, a, k.r * 0.16, color, 0.6)
        glow(&ctx, b, k.r * 0.34, color, 0.45)
        ctx.blendMode = .normal
        let sr = max(1.4, k.r * 0.075)
        let ring = Orbit(c: b, a: sr * 2.3, squash: 0.35, rot: ang + .pi / 2)
        ctx.stroke(ring.arc(0, 2 * .pi, 32), with: .color(C(color, 0.9)), lineWidth: k.lw(0.012, 0.6))
        ctx.fill(disc(b, sr), with: radial([(0xFFFFFF, 1, 0), (color, 1, 0.6), (mixHex(color, 0x10122E, 0.6), 1, 1)], b, 0, sr))
    }

    static func crown(_ ctx: inout GraphicsContext, _ k: Kit, color: UInt32) {
        let ux = sin(k.tilt), uy = -cos(k.tilt)
        let cc = k.P(ux * 1.32, uy * 1.32)
        let o = Orbit(c: cc, a: k.r * 0.66, squash: 0.26, rot: k.tilt)
        let n = k.pick(10, 7, 5)
        let rot = k.t * 2 * .pi / 100
        let pole = k.P(ux * 0.9, uy * 0.9)
        let sats = (0..<n).map { o.point(Double($0) / Double(n) * 2 * .pi + rot) }
        ctx.blendMode = k.add
        if k.lod >= 1 {
            var fan = Path()
            for s in sats {
                fan.move(to: pole)
                fan.addLine(to: s)
            }
            ctx.stroke(fan, with: .linearGradient(Gradient(colors: [C(color, 0.05), C(color, 0.4)]), startPoint: pole, endPoint: cc),
                       lineWidth: k.lw(0.006, 0.4))
        }
        let ring = o.arc(0, 2 * .pi, 40)
        ctx.stroke(ring, with: .color(C(color, 0.16)), lineWidth: k.lw(0.08, 2))
        ctx.stroke(ring, with: .color(C(color, 0.8)), lineWidth: k.lw(0.012, 0.6))
        var dots = Path()
        for s in sats {
            dots.addEllipse(in: dotRect(s, max(0.9, k.r * 0.03)))
            if k.lod == 2 { glow(&ctx, s, k.r * 0.1, color, 0.5) }
        }
        ctx.fill(dots, with: .color(C(0xFFFFFF)))
        glow(&ctx, pole, k.r * 0.22, color, 0.35)
        ctx.blendMode = .normal
    }

    static func gardens(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool, _ c1: UInt32, _ c2: UInt32) {
        let o = Orbit(c: k.c, a: k.r * 1.55, squash: 0.3, rot: k.tilt + 0.15)
        let f = front ? 1.0 : 0.65
        let arc = o.half(front: front, 40)
        ctx.blendMode = k.add
        ctx.stroke(arc, with: .color(C(c1, 0.14 * f)), lineWidth: k.lw(0.1, 2))
        ctx.stroke(arc, with: .color(C(c1, 0.55 * f)), lineWidth: k.lw(0.009, 0.5))
        let n = k.pick(12, 8, 6)
        let rot = k.t * 2 * .pi / 140
        var podsA = Path(), podsB = Path()
        for i in 0..<n {
            let th = Double(i) / Double(n) * 2 * .pi + rot
            guard (sin(th) >= 0) == front else { continue }
            let p = o.point(th)
            let s = max(1.2, k.r * 0.055) * (0.85 + 0.2 * sin(th))
            glow(&ctx, p, s * 3.2, i % 2 == 0 ? c1 : c2, 0.45 * f)
            if i % 2 == 0 { podsA.addEllipse(in: dotRect(p, s)) } else { podsB.addEllipse(in: dotRect(p, s)) }
        }
        ctx.blendMode = .normal
        ctx.fill(podsA, with: .color(C(mixHex(c1, 0xFFFFFF, 0.4))))
        ctx.fill(podsB, with: .color(C(mixHex(c2, 0xFFFFFF, 0.4))))
    }

    static func shardHalo(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        let o = Orbit(c: k.c, a: k.r * 1.55, squash: 0.3, rot: k.tilt - 0.2)
        let cols: [UInt32] = [k.acc, 0xFF8FB8, 0xFFD58A, 0xFFFFFF]
        var paths = [Path(), Path(), Path(), Path()]
        let n = k.pick(18, 11, 7)
        let rot = k.t * 2 * .pi / 120
        let f = front ? 1.0 : 0.65
        for i in 0..<n {
            let th = Double(i) / Double(n) * 2 * .pi + rot
            guard (sin(th) >= 0) == front else { continue }
            let p = o.point(th)
            let s = max(1.6, k.r * 0.07) * (0.8 + 0.25 * sin(th))
            let tumble = th * 1.5 + Double(i)
            let T = CGAffineTransform(rotationAngle: tumble).concatenating(CGAffineTransform(translationX: p.x, y: p.y))
            var d = Path()
            d.addLines([CGPoint(x: 0, y: -s * 1.6), CGPoint(x: s * 0.55, y: 0), CGPoint(x: 0, y: s * 1.6), CGPoint(x: -s * 0.55, y: 0)])
            d.closeSubpath()
            paths[i % 4].addPath(d, transform: T)
        }
        ctx.blendMode = k.add
        let arc = o.half(front: front, 44)
        ctx.stroke(arc, with: .linearGradient(Gradient(colors: [C(k.acc, 0.35 * f), C(0xFF8FB8, 0.35 * f), C(0xFFD58A, 0.35 * f)]),
                                              startPoint: o.point(.pi), endPoint: o.point(0)), lineWidth: k.lw(0.05, 1.5))
        for (i, p) in paths.enumerated() { ctx.fill(p, with: .color(C(cols[i], 0.95 * f))) }
        ctx.blendMode = .normal
    }

    static func threads(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        var path = Path()
        for f in fragmentList(k) where f.front == front {
            let dx = Double(f.p.x - k.c.x), dy = Double(f.p.y - k.c.y)
            let d = max(1e-3, (dx * dx + dy * dy).squareRoot())
            path.move(to: k.P(dx / d * 0.9, dy / d * 0.9))
            path.addLine(to: f.p)
        }
        ctx.blendMode = k.add
        ctx.stroke(path, with: .color(C(k.acc, 0.25)), style: StrokeStyle(lineWidth: k.lw(0.05, 1.5), lineCap: .round))
        ctx.stroke(path, with: .color(C(mixHex(k.acc, 0xFFFFFF, 0.6), 0.9)), style: StrokeStyle(lineWidth: k.lw(0.01, 0.5), lineCap: .round))
        ctx.blendMode = .normal
    }

    static func jets(_ ctx: inout GraphicsContext, _ k: Kit) {
        let ux = sin(k.tilt), uy = -cos(k.tilt)
        ctx.blendMode = k.add
        for s in [1.0, -1.0] {
            let a = k.P(ux * 0.9 * s, uy * 0.9 * s), b = k.P(ux * 2.1 * s, uy * 2.1 * s)
            var p = Path()
            p.move(to: a)
            p.addLine(to: b)
            let flick = k.live ? 0.85 + 0.15 * sin(k.t * 1.3 + s) : 1
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [C(k.hi, 0.5 * flick), C(k.acc, 0)]), startPoint: a, endPoint: b),
                       style: StrokeStyle(lineWidth: k.lw(0.16, 3), lineCap: .round))
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [C(0xFFFFFF, 0.95), C(k.acc, 0)]), startPoint: a, endPoint: b),
                       style: StrokeStyle(lineWidth: k.lw(0.03, 1), lineCap: .round))
        }
        ctx.blendMode = .normal
    }

    // MARK: Twin worlds

    static func twin(_ ctx: inout GraphicsContext, _ k: Kit) {
        var rng = k.rng(0x7717)
        let ph = rng.range(0, 2 * .pi)
        let th = ph + k.t * 2 * .pi / 110
        let vx0 = cos(th), vy0 = 0.62 * sin(th)
        let vx = vx0 * cos(k.tilt) - vy0 * sin(k.tilt), vy = vx0 * sin(k.tilt) + vy0 * cos(k.tilt)
        var k1 = k, k2 = k
        k1.move(to: k.P(vx * 0.52, vy * 0.52), radius: k.r * 0.56 * (1 + 0.05 * sin(th)))
        k2.move(to: k.P(-vx * 1.0, -vy * 1.0), radius: k.r * 0.38 * (1 - 0.05 * sin(th)))
        k2.twinIndex = 1
        k2.hi = mixHex(k.acc, 0xFFFFFF, 0.55)
        k2.mid = k.acc
        k2.sh = mixHex(k.acc, 0x0A0C2A, 0.78)
        k2.atm = mixHex(k.acc, 0xFFFFFF, 0.3)
        k2.acc = k.hi
        k2.globe = Globe(c: k2.c, r: k2.r, spin: k.spin * 1.4 + 2, tilt: k.tilt)
        if k.stage >= 5 { aura(&ctx, k) }
        halo(&ctx, k1)
        halo(&ctx, k2)
        if k.stage >= 4 { station(&ctx, k, front: false) }
        let firstInFront = sin(th) > 0
        body(&ctx, firstInFront ? k2 : k1)
        bridge(&ctx, k, k1, k2)
        body(&ctx, firstInFront ? k1 : k2)
        if k.stage >= 4 { station(&ctx, k, front: true) }
        if k.stage >= 5 { lemniscate(&ctx, k, k1, k2) }
    }

    static func bridge(_ ctx: inout GraphicsContext, _ k: Kit, _ a: Kit, _ b: Kit) {
        let dx = Double(b.c.x - a.c.x), dy = Double(b.c.y - a.c.y)
        let d = max(1e-3, (dx * dx + dy * dy).squareRoot())
        let ux = dx / d, uy = dy / d
        let A = CGPoint(x: Double(a.c.x) + ux * a.r * 0.7, y: Double(a.c.y) + uy * a.r * 0.7)
        let B = CGPoint(x: Double(b.c.x) - ux * b.r * 0.7, y: Double(b.c.y) - uy * b.r * 0.7)
        let sway = k.live ? sin(k.t * 0.25) * 0.1 : 0.05
        let bend = (0.3 + sway) * k.r
        let ctrl = CGPoint(x: (Double(A.x) + Double(B.x)) / 2 - uy * bend, y: (Double(A.y) + Double(B.y)) / 2 + ux * bend)
        var path = Path()
        path.move(to: A)
        path.addQuadCurve(to: B, control: ctrl)
        let s = [0.5, 0.7, 0.82, 0.88, 0.94, 1.0][min(5, k.stage)]
        let grad = Gradient(colors: [C(a.atm, 1), C(b.atm, 1)])
        ctx.blendMode = k.add
        var wide = ctx
        wide.opacity = 0.16 * s
        wide.stroke(path, with: .linearGradient(grad, startPoint: A, endPoint: B), style: StrokeStyle(lineWidth: k.lw(0.24, 3), lineCap: .round))
        var mids = ctx
        mids.opacity = 0.45 * s
        mids.stroke(path, with: .linearGradient(grad, startPoint: A, endPoint: B), style: StrokeStyle(lineWidth: k.lw(0.07, 1.2), lineCap: .round))
        ctx.stroke(path, with: .color(C(0xFFFFFF, 0.85 * s)), style: StrokeStyle(lineWidth: k.lw(0.016, 0.5), lineCap: .round))
        if k.stage >= 2 {
            let dw = k.lw(0.03, 1)
            ctx.stroke(path, with: .color(C(0xFFFFFF, 0.95)),
                       style: StrokeStyle(lineWidth: dw, lineCap: .round, dash: [0.1, dw * 4], dashPhase: -k.phase(dw * 3, dw * 4 + 0.1)))
        }
        ctx.blendMode = .normal
    }

    static func lemniscate(_ ctx: inout GraphicsContext, _ k: Kit, _ a: Kit, _ b: Kit) {
        let dx = Double(b.c.x - a.c.x), dy = Double(b.c.y - a.c.y)
        let d = max(1e-3, (dx * dx + dy * dy).squareRoot())
        let axis = atan2(dy, dx)
        let mc = mid(a.c, b.c)
        let A = min(k.r * 1.9, d * 0.9 + k.r * 0.45)
        func pt(_ s: Double) -> CGPoint {
            let den = 1 + sin(s) * sin(s)
            let x = A * cos(s) / den, y = 1.25 * A * sin(s) * cos(s) / den
            return CGPoint(x: Double(mc.x) + x * cos(axis) - y * sin(axis), y: Double(mc.y) + x * sin(axis) + y * cos(axis))
        }
        var path = Path()
        path.addLines((0...72).map { pt(Double($0) / 72 * 2 * .pi) })
        ctx.blendMode = k.add
        ctx.stroke(path, with: .color(C(0xFFD58A, 0.14)), lineWidth: k.lw(0.12, 2.5))
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [C(a.atm, 0.85), C(0xFFFFFF, 0.9), C(b.atm, 0.85)]),
                                               startPoint: pt(0), endPoint: pt(.pi)), lineWidth: k.lw(0.016, 0.6))
        var dots = Path()
        let n = k.pick(24, 12, 6)
        for i in 0..<n {
            dots.addEllipse(in: dotRect(pt(Double(i) / Double(n) * 2 * .pi + k.t * 2 * .pi / 60), max(0.7, k.r * 0.016)))
        }
        ctx.fill(dots, with: .color(C(0xFFF6E0)))
        ctx.blendMode = .normal
    }

    // MARK: Ringworld

    static func ringworld(_ ctx: inout GraphicsContext, _ k: Kit) {
        let st = k.stage
        let o = Orbit(c: k.c, a: k.r * 1.42, squash: 0.3, rot: k.tilt)
        let w = k.lw(0.18, 2.2)
        if st >= 5 {
            aura(&ctx, k)
            secondRing(&ctx, k, front: false)
        }
        moons(&ctx, k, front: false)
        if st >= 4 { station(&ctx, k, front: false) }
        ctx.blendMode = k.add
        glow(&ctx, k.c, k.r * (1.15 + 0.12 * Double(st)), k.acc, 0.3 + 0.06 * Double(st))
        ctx.blendMode = .normal
        // Far arc: the lit inner face, lands and seas under shadow squares.
        let back = o.half(front: false, 56)
        if st >= 1 {
            ctx.blendMode = k.add
            ctx.stroke(back, with: .color(C(k.atm, 0.24)), lineWidth: w * 2)
            ctx.blendMode = .normal
        }
        ctx.stroke(back, with: .color(C(k.hi, 0.95)), lineWidth: w)
        ctx.stroke(back, with: linear([(0x4C9AD8, 1, 0), (0x2C5F9A, 1, 1)], k.lit(1.5), k.lit(-1.5)), lineWidth: w * 0.78)
        let seg = k.r * 0.26
        ctx.stroke(back, with: .color(C(mixHex(0x6FCB8F, k.mid, 0.2), 0.95)),
                   style: StrokeStyle(lineWidth: w * 0.5, dash: [seg, seg * 0.45], dashPhase: k.phase(k.r * 0.01, seg * 1.45)))
        if st >= 2 {
            ctx.blendMode = k.add
            ctx.stroke(back, with: .color(C(0x70E1F5, 0.35)), lineWidth: w * 0.32)
            ctx.stroke(back, with: .color(C(0xE9FBFF, 0.95)),
                       style: StrokeStyle(lineWidth: w * 0.09, dash: [w * 0.6, w * 0.5], dashPhase: -k.phase(w * 0.5, w * 1.1)))
            ctx.blendMode = .normal
        }
        let sq = k.r * 0.42
        ctx.stroke(back, with: .color(C(0x05061A, 0.7)),
                   style: StrokeStyle(lineWidth: w * 0.8, dash: [sq, sq * 0.95], dashPhase: k.phase(k.r * 0.004, sq * 1.95)))
        if st >= 3 {
            var specks = Path()
            var rng = k.rng(0xB10B)
            for _ in 0..<k.pick(30, 16, 8) {
                let th = .pi + rng.range(0.05, .pi - 0.05)
                let off = rng.range(-0.3, 0.3) * Double(w)
                let p = o.point(th)
                specks.addEllipse(in: dotRect(CGPoint(x: Double(p.x), y: Double(p.y) + off), max(0.5, k.r * 0.012)))
            }
            ctx.blendMode = k.add
            ctx.fill(specks, with: .color(C(0x7CFFCB, 0.9)))
            ctx.blendMode = .normal
        }
        // The small star.
        let sr = k.r * 0.32
        ctx.blendMode = k.add
        glow(&ctx, k.c, sr * 3, 0xFFFFFF, 0.45)
        if k.lod >= 1 {
            var flare = Path()
            flare.move(to: k.P(-0.75, 0)); flare.addLine(to: k.P(0.75, 0))
            flare.move(to: k.P(0, -0.6)); flare.addLine(to: k.P(0, 0.6))
            ctx.stroke(flare, with: .color(C(0xFFFFFF, 0.35)), lineWidth: k.lw(0.008, 0.4))
        }
        ctx.blendMode = .normal
        ctx.fill(disc(k.c, sr), with: radial([(0xFFFFFF, 1, 0), (0xFFF6DA, 1, 0.5), (k.acc, 1, 1)], k.c, 0, sr))
        // Near arc: the dark outer hull.
        let front = o.half(front: true, 56)
        ctx.stroke(front, with: .color(C(k.hi, 0.7)), lineWidth: w)
        ctx.stroke(front, with: linear([(mixHex(k.sh, k.mid, 0.45), 1, 0), (k.sh, 1, 1)], k.lit(1.5), k.lit(-1.5)), lineWidth: w * 0.78)
        ctx.stroke(front, with: .color(C(k.mid, 0.45)), style: StrokeStyle(lineWidth: w * 0.08, dash: [w * 0.6, w * 0.5]))
        if st >= 4 {
            var lights = Path()
            var rng = k.rng(0x11E7)
            for _ in 0..<k.pick(40, 20, 10) {
                let th = rng.range(0.05, .pi - 0.05)
                let off = rng.range(-0.3, 0.3) * Double(w)
                let p = o.point(th)
                lights.addEllipse(in: dotRect(CGPoint(x: Double(p.x), y: Double(p.y) + off), max(0.5, k.r * 0.011)))
            }
            ctx.blendMode = k.add
            ctx.fill(lights, with: .color(C(0xFFD58A, 0.95)))
            ctx.blendMode = .normal
        }
        moons(&ctx, k, front: true)
        if st >= 4 { station(&ctx, k, front: true) }
        if st >= 5 {
            secondRing(&ctx, k, front: true)
            var spokes = Path()
            for i in 0..<6 {
                let th = Double(i) / 6 * 2 * .pi + k.t * 2 * .pi / 200
                spokes.move(to: k.c)
                spokes.addLine(to: o.point(th))
            }
            ctx.blendMode = k.add
            ctx.stroke(spokes, with: radial([(0xFFFFFF, 0.5, 0), (0xFFD58A, 0.15, 0.6), (0xFFD58A, 0, 1)], k.c, 0, k.r * 1.5),
                       lineWidth: k.lw(0.012, 0.5))
            ctx.blendMode = .normal
        }
    }

    static func secondRing(_ ctx: inout GraphicsContext, _ k: Kit, front: Bool) {
        haloRing(&ctx, k, front: front, radius: 1.12, squash: 0.92, rot: k.tilt + .pi / 2, color: 0xFFD58A, lights: k.pick(24, 12, 0))
    }

    // MARK: Silhouette

    static func silhouette(_ ctx: inout GraphicsContext, _ k: Kit) {
        let hint = k.atm
        let ink: UInt32 = 0x0B0D26
        ctx.blendMode = k.add
        glow(&ctx, k.c, k.r * 1.6, hint, 0.08)
        ctx.blendMode = .normal
        let ringed = k.world.hasRings || k.a == .ringworld || k.a == .machine
        let ro = Orbit(c: k.c, a: k.r * (k.a == .ringworld ? 1.42 : 1.4), squash: 0.3, rot: k.tilt)
        if ringed {
            ctx.stroke(ro.half(front: false), with: .color(C(ink)), lineWidth: k.lw(k.a == .ringworld ? 0.18 : 0.22, 2))
            ctx.stroke(ro.half(front: false), with: .color(C(hint, 0.22)), lineWidth: k.lw(0.008, 0.5))
        }
        if k.a == .twin {
            let p = k.P(-0.85 * cos(k.tilt), -0.85 * sin(k.tilt) + 0.15)
            ctx.fill(disc(p, k.r * 0.42), with: .color(C(ink)))
            ctx.stroke(disc(p, k.r * 0.42), with: .color(C(hint, 0.25)), lineWidth: k.lw(0.012, 0.5))
        }
        let shape: Path
        switch k.a {
        case .ringworld: shape = disc(k.c, k.r * 0.34)
        case .twin: shape = disc(k.P(0.35 * cos(k.tilt), 0.35 * sin(k.tilt)), k.r * 0.62)
        default: shape = bodyPath(k)
        }
        ctx.fill(shape, with: radial([(0x161A40, 1, 0), (ink, 1, 0.6), (0x05061A, 1, 1)], k.lit(0.4), 0, k.r * 1.5))
        ctx.drawLayer { l in
            l.clip(to: shape)
            l.blendMode = .plusLighter
            l.fill(k.cover, with: radial([(hint, 0, 0), (hint, 0, 0.8), (hint, 0.5, 1)], k.lit(-0.3), 0, k.r * 1.3))
            let sweep = k.live ? fract(k.t / 9) : 0.4
            let along = -1.6 + 3.2 * sweep
            let px = -k.ly, py = k.lx
            let a = k.P(px * (along - 0.25), py * (along - 0.25)), b = k.P(px * (along + 0.25), py * (along + 0.25))
            l.fill(k.cover, with: linear([(0xFFFFFF, 0, 0), (0xFFFFFF, 0.07, 0.5), (0xFFFFFF, 0, 1)], a, b))
            l.blendMode = .normal
            let pulse = k.live ? 0.5 + 0.5 * sin(k.t * 1.1) : 0.6
            let size = max(6, k.r * 1.05)
            let center = k.a == .twin ? k.P(0.35 * cos(k.tilt), 0.35 * sin(k.tilt)) : k.c
            l.draw(Text(verbatim: "?").font(.system(size: size * (k.a == .ringworld ? 0.5 : 1), weight: .light, design: .rounded))
                .foregroundStyle(C(hint, 0.14 + 0.14 * pulse)), at: center)
        }
        if ringed {
            ctx.stroke(ro.half(front: true), with: .color(C(ink)), lineWidth: k.lw(k.a == .ringworld ? 0.18 : 0.22, 2))
            ctx.stroke(ro.half(front: true), with: .color(C(hint, 0.3)), lineWidth: k.lw(0.008, 0.5))
        }
        switch k.a {
        case .shattered:
            for f in fragmentList(k) {
                ctx.fill(f.poly, with: .color(C(ink)))
                ctx.stroke(f.poly, with: .color(C(hint, 0.3)), lineWidth: k.lw(0.008, 0.4))
            }
        case .phantom:
            ctx.stroke(Orbit(c: k.c, a: k.r * 1.3, squash: 0.26, rot: k.tilt).arc(0, 2 * .pi, 48), with: .color(C(hint, 0.18)),
                       style: StrokeStyle(lineWidth: k.lw(0.01, 0.5), dash: [k.r * 0.06, k.r * 0.04]))
        case .ringworld, .dysonPearl:
            ctx.blendMode = k.add
            glow(&ctx, k.c, k.r * 0.5, 0xFFD58A, 0.18)
            ctx.blendMode = .normal
        default:
            break
        }
    }
}
