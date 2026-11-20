import SwiftUI

/// Render-ready, precomputed description of a universe. Built once per data
/// change (never per frame) so the canvas closure only transforms and draws.
struct UniverseScene: Equatable, Sendable {
    struct Constellation: Equatable, Sendable {
        var id: UUID
        var points: [WorldPoint]
        var hue: String
        var dayKey: DayKey
    }

    struct Ghost: Equatable, Sendable {
        var name: String
        var detail: String
        var position: WorldPoint
    }

    /// An Odyssey world, shown beside the stars of the session that formed it.
    struct Voyage: Equatable, Sendable {
        var world: WorldState
        var position: WorldPoint
        /// Landed on by the moment shown; otherwise drawn veiled.
        var charted: Bool
    }

    /// A session focused together: your star, a companion star in your
    /// friend's name, and a bridge of light between them.
    struct Bridge: Equatable, Sendable {
        var star: WorldPoint
        var friend: WorldPoint
        var friendName: String
        var seed: UInt64
    }

    /// An ignited Odyssey galaxy, glowing behind the day it ignited.
    struct SkyGalaxy: Equatable, Sendable {
        var blueprint: GalaxyBlueprint
        var center: WorldPoint
    }

    var stars: [CelestialSnapshot] = []
    var planets: [CelestialSnapshot] = []
    var moons: [CelestialSnapshot] = []
    var nebulae: [CelestialSnapshot] = []
    var comets: [CelestialSnapshot] = []
    var seed: CelestialSnapshot?
    var constellations: [Constellation] = []
    /// Today's stars not yet part of a constellation (drawn dashed).
    var todayChain: [WorldPoint] = []
    var todayBounds: CGRect?
    var ghost: Ghost?
    var openRegions: Set<UniverseRegion> = [.homeCluster]
    var ambientLight: Double = 0
    var qualifyingSessions = 0
    var voyages: [Voyage] = []
    var galaxies: [SkyGalaxy] = []
    var bridges: [Bridge] = []
    /// Formed worlds not yet landed on, whether or not they're drawn.
    var unchartedCount = 0

    /// Where you last landed (else your newest world), for the camera.
    var odysseyFocus: WorldPoint? {
        let landed = voyages.filter(\.charted).max { ($0.world.visitedAt ?? .distantPast) < ($1.world.visitedAt ?? .distantPast) }
        return (landed ?? voyages.max { $0.world.ordinal < $1.world.ordinal })?.position
    }

    var all: [CelestialSnapshot] {
        planets + moons + comets + stars + (seed.map { [$0] } ?? []) + nebulae
    }

    var isEmpty: Bool { stars.isEmpty && planets.isEmpty }

    init() {}

    init(objects: [CelestialSnapshot], today: DayKey, qualifyingSessions: Int, ambientLight: Double,
         rules: RewardRules = .standard, visibleUntil: Date? = nil, ghostDetail: (Int) -> String = { "\($0)" }) {
        let visible = visibleUntil.map { cutoff in objects.filter { $0.bornAt <= cutoff } } ?? objects
        self.qualifyingSessions = qualifyingSessions
        self.ambientLight = ambientLight
        for o in visible {
            switch o.kind {
            case .star: stars.append(o)
            case .planet: planets.append(o)
            case .moon: moons.append(o)
            case .nebula: nebulae.append(o)
            case .comet: comets.append(o)
            case .seed: seed = o
            case .constellation: break
            }
        }
        stars.sort { $0.ordinal < $1.ordinal }
        let byOrdinal = Dictionary(uniqueKeysWithValues: stars.map { ($0.ordinal, $0) })
        var linked = Set<Int>()
        for c in visible where c.kind == .constellation {
            let pts = c.linkedOrdinals.compactMap { byOrdinal[$0]?.position }
            guard pts.count >= 2 else { continue }
            linked.formUnion(c.linkedOrdinals)
            constellations.append(Constellation(id: c.id, points: pts, hue: c.hue, dayKey: c.dayKey))
        }
        let todays = stars.filter { $0.dayKey == today }
        todayChain = todays.filter { !linked.contains($0.ordinal) }.map(\.position)
        if !todays.isEmpty {
            let xs = todays.map(\.position.x), ys = todays.map(\.position.y)
            todayBounds = CGRect(x: xs.min()! - 26, y: ys.min()! - 26,
                                 width: xs.max()! - xs.min()! + 52, height: ys.max()! - ys.min()! + 52)
        }
        let count = visibleUntil == nil ? qualifyingSessions : stars.count
        openRegions = Set(UniverseRegion.allCases.filter { count >= $0.unlockSessions })
        if visibleUntil == nil, let next = rules.nextPlanet(after: qualifyingSessions),
           let index = rules.planetMilestones.firstIndex(of: next.sessions) {
            ghost = Ghost(name: next.name, detail: ghostDetail(next.sessions - qualifyingSessions),
                          position: UniverseLayout.planetAnchor(index: index))
        }
    }

    /// Adds Odyssey worlds that had formed by `visibleUntil` (all when nil),
    /// each beside the star of the session that formed it, and each ignited
    /// galaxy behind the day it ignited (the home galaxy by your first light).
    /// A world counts as charted only once landed on; uncharted ones are
    /// left out unless `includeUncharted`. Call after `init`.
    mutating func addOdyssey(worlds: [WorldState], visibleUntil: Date? = nil, includeUncharted: Bool = true) {
        let shown = (visibleUntil.map { cutoff in worlds.filter { $0.emergedAt <= cutoff } } ?? worlds)
            .sorted { $0.ordinal < $1.ordinal }
        voyages = []
        galaxies = []
        unchartedCount = 0
        guard !shown.isEmpty else { return }
        let byTime = stars.sorted { $0.bornAt < $1.bornAt }
        /// The star born at (or last before) a moment: that session's light.
        func anchor(at date: Date) -> WorldPoint {
            byTime.last { $0.bornAt <= date.addingTimeInterval(1) }?.position ?? seed?.position ?? byTime.first?.position ?? .zero
        }
        // Spacing in world units, from what is actually drawn: a galaxy's disc
        // reaches ~1.3 × its radius (its halo fades to 2.2 ×), a world with
        // rings and moons ~2.4 × its radius, a planet's ring ~1.8 ×. Bodies
        // (planets, moons, comets, the next world's ghost, worlds, galaxies)
        // must never overlap; stars are kept clear when there's room.
        let worldGap = 300.0, galaxyGap = 520.0
        let galaxyReach = Double(UniverseRenderer.odysseyGalaxyRadius) * 1.3
        let worldReach = Double(UniverseRenderer.odysseyWorldRadius) * 2.4
        let planetReach = Double(UniverseRenderer.planetRadius) * 1.8
        let worldToGalaxy = galaxyReach + worldReach + 30
        var bodies: [(WorldPoint, Double)] = planets.map { ($0.position, planetReach) }
            + moons.map { ($0.position, 30) } + comets.map { ($0.position, 40) }
        if let ghost { bodies.append((ghost.position, Double(UniverseRenderer.planetRadius) + 50)) }
        let lights = (stars + (seed.map { [$0] } ?? [])).map { ($0.position, $0.footprint) }
        var placedWorlds: [WorldPoint] = []
        var placedGalaxies: [WorldPoint] = []

        for g in Set(shown.map(\.galaxy)).sorted() {
            let first = shown.first { $0.galaxy == g }!
            let base = g == 0 ? (seed?.position ?? anchor(at: first.emergedAt)) : anchor(at: first.emergedAt)
            var rng = SeededRandom(seed: StableHash.fnv1a("lumora.sky.galaxy.\(g)"))
            let candidate = base.offset(angle: rng.range(0, 2 * .pi), distance: 260)
            let center = Self.freeSpot(candidate, hard: { p in
                bodies.allSatisfy { $0.0.distance(to: p) >= $0.1 + galaxyReach }
                    && placedGalaxies.allSatisfy { $0.distance(to: p) >= galaxyGap }
            }, soft: { p in
                lights.allSatisfy { $0.0.distance(to: p) >= $0.1 + 40 }
            })
            placedGalaxies.append(center)
            galaxies.append(SkyGalaxy(blueprint: GalaxyCatalog.blueprint(g), center: center))
        }
        for world in shown {
            var rng = SeededRandom(seed: world.blueprint.seed ^ 0x5C1E)
            // Each world leaves its session's star in its own direction.
            let angle = Double(world.ordinal) * UniverseLayout.goldenAngle + rng.range(-0.35, 0.35)
            let candidate = anchor(at: world.emergedAt).offset(angle: angle, distance: 150 + rng.range(0, 70))
            let clear = Double(UniverseRenderer.odysseyWorldRadius) + 40
            let position = Self.freeSpot(candidate, hard: { p in
                bodies.allSatisfy { $0.0.distance(to: p) >= $0.1 + worldReach + 20 }
                    && placedWorlds.allSatisfy { $0.distance(to: p) >= worldGap }
                    && placedGalaxies.allSatisfy { $0.distance(to: p) >= worldToGalaxy }
            }, soft: { p in
                lights.allSatisfy { $0.0.distance(to: p) >= $0.1 + clear }
            })
            placedWorlds.append(position)
            let landed = world.isCharted && (visibleUntil.map { cutoff in (world.visitedAt ?? .distantFuture) <= cutoff } ?? true)
            voyages.append(Voyage(world: world, position: position, charted: landed))
        }
        // Everything is placed first, so hiding uncharted worlds never moves the rest.
        unchartedCount = voyages.filter { !$0.charted }.count
        if !includeUncharted { voyages.removeAll { !$0.charted } }
    }

    /// Adds a bridge for each together session whose star is in the sky.
    mutating func addBridges(_ shared: [(sessionID: UUID, friendName: String, roomCode: String)]) {
        let starBySession = Dictionary(stars.compactMap { s in s.sourceSessionID.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        bridges = shared.compactMap { item in
            guard let star = starBySession[item.sessionID] else { return nil }
            let seed = StableHash.fnv1a("lumora.bridge.\(item.roomCode)")
            let angle = Double(seed % 628) / 100
            return Bridge(star: star.position, friend: star.position.offset(angle: angle, distance: 78),
                          friendName: item.friendName, seed: seed)
        }
    }

    /// Nearest spot to `candidate` (deterministic spiral) that keeps clear of
    /// everything; failing that, of the `hard` things only — a crowded sky
    /// may put a star near a world, but never a world on a planet.
    static func freeSpot(_ candidate: WorldPoint, hard: (WorldPoint) -> Bool, soft: (WorldPoint) -> Bool) -> WorldPoint {
        func spiral(_ accept: (WorldPoint) -> Bool) -> WorldPoint? {
            if accept(candidate) { return candidate }
            for step in 1...2500 {
                let p = candidate.offset(angle: Double(step) * UniverseLayout.goldenAngle, distance: 16 * Double(step).squareRoot())
                if accept(p) { return p }
            }
            return nil
        }
        return spiral { hard($0) && soft($0) } ?? spiral(hard) ?? candidate
    }

    /// Points to frame on Home: the hero world (or first star), recent
    /// stars, and the next world's ghost — padded by their drawn extents
    /// (planet radius, ghost labels) so nothing is clipped.
    func homeFocusPoints() -> [WorldPoint] {
        var pts: [WorldPoint] = []
        func addExtent(_ c: WorldPoint, radius: Double, below: Double) {
            pts += [WorldPoint(x: c.x - radius, y: c.y - radius), WorldPoint(x: c.x + radius, y: c.y + radius + below)]
        }
        if let p = planets.last { addExtent(p.position, radius: 70, below: 0) } else if let s = seed { pts.append(s.position) }
        pts += stars.suffix(10).map(\.position)
        if let g = ghost, planets.isEmpty { addExtent(g.position, radius: 46, below: 40) }
        return pts.isEmpty ? [.zero] : pts
    }
}

/// Camera: what world point sits at the view's center, and at what zoom.
struct UniverseCamera: Equatable {
    var center: WorldPoint
    var zoom: Double

    static let zoomRange = 0.22...3.0
    static let home = UniverseCamera(center: .zero, zoom: 1)

    func toScreen(_ p: WorldPoint, size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - center.x) * zoom, y: size.height / 2 + (p.y - center.y) * zoom)
    }

    func toWorld(_ p: CGPoint, size: CGSize) -> WorldPoint {
        WorldPoint(x: center.x + (p.x - size.width / 2) / zoom, y: center.y + (p.y - size.height / 2) / zoom)
    }

    /// Smallest camera that fits `points` (with padding) into `size`.
    static func fitting(_ points: [WorldPoint], in size: CGSize, padding: CGFloat = 70,
                        zoomRange: ClosedRange<Double> = 0.4...1.8) -> UniverseCamera {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              size.width > 0, size.height > 0 else { return .home }
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let zoom = min(Double(size.width - padding * 2) / w, Double(size.height - padding * 2) / h)
        return UniverseCamera(center: WorldPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
                              zoom: min(zoomRange.upperBound, max(zoomRange.lowerBound, zoom)))
    }

    func interpolated(to other: UniverseCamera, t: Double) -> UniverseCamera {
        // Interpolate zoom geometrically so dollies feel uniform.
        let z = exp(log(zoom) + (log(other.zoom) - log(zoom)) * t)
        return UniverseCamera(center: WorldPoint(x: center.x + (other.center.x - center.x) * t,
                                                 y: center.y + (other.center.y - center.y) * t), zoom: z)
    }
}

/// A timed camera move ("Explorer region fly-to · 900 ms · Emerge").
struct CameraFlight: Equatable {
    var from: UniverseCamera
    var to: UniverseCamera
    var start: Date
    var duration: Double
    var curve: LMCurve = .emerge

    func camera(at date: Date) -> UniverseCamera {
        let t = duration > 0 ? date.timeIntervalSince(start) / duration : 1
        return from.interpolated(to: to, t: curve.value(t))
    }

    func isFinished(at date: Date) -> Bool { date.timeIntervalSince(start) >= duration }
}
