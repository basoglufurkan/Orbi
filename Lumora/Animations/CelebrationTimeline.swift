import SwiftUI

/// Timing for one completion sequence. All beats are expressed as time
/// ranges on a single clock, so visuals, haptics and sound share one origin
/// and stay in sync (Session completion · 5.6 s · skippable after 1.5 s).
struct CelebrationPlan: Equatable {
    enum Kind: Equatable { case standard, endedEarly, milestone, reduced, tooShort }

    var kind: Kind
    var duration: Double
    var summaryAt: Double
    var skippableAfter: Double
    /// Size multiplier for the new star and the release (ended early: 0.6).
    var scale: Double

    static func make(for reward: SessionReward, motion: MotionLevel) -> CelebrationPlan {
        if reward.outcome == .tooShort {
            return CelebrationPlan(kind: .tooShort, duration: 0.8, summaryAt: 0.5, skippableAfter: 0, scale: 0)
        }
        if motion == .reduced {
            return CelebrationPlan(kind: .reduced, duration: 1.2, summaryAt: 0.8, skippableAfter: 0,
                                   scale: reward.outcome == .endedEarly ? 0.6 : 1)
        }
        if reward.planetBorn != nil {
            return CelebrationPlan(kind: .milestone, duration: 8.4, summaryAt: 7.4, skippableAfter: 1.5, scale: 1)
        }
        if reward.outcome == .endedEarly {
            return CelebrationPlan(kind: .endedEarly, duration: 5.6, summaryAt: 4.6, skippableAfter: 1.5, scale: 0.6)
        }
        return CelebrationPlan(kind: .standard, duration: 5.6, summaryAt: 4.6, skippableAfter: 1.5, scale: 1)
    }

    var soundCue: SoundCue? {
        switch kind {
        case .standard: .celebration
        case .endedEarly: .gentleCelebration
        case .milestone: .milestone
        case .reduced: .quickCelebration
        case .tooShort: nil
        }
    }
}

/// Normalized progress of `t` through the beat `[a, b]`.
@inline(__always)
func beat(_ t: Double, _ a: Double, _ b: Double) -> Double {
    b > a ? min(1, max(0, (t - a) / (b - a))) : (t >= b ? 1 : 0)
}

@inline(__always)
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

@inline(__always)
func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
}

/// Damped spring approximating the Bloom spring (0.55 / 0.72) for
/// timeline-driven rendering. 0 → 1 with a gentle overshoot.
func bloomSpring(_ u: Double) -> Double {
    guard u > 0 else { return 0 }
    guard u < 1.6 else { return 1 }
    return 1 - exp(-5.2 * u) * cos(7.4 * u)
}

/// Screen-space geometry for a celebration, derived once from the reward.
struct CelebrationLayout {
    var size: CGSize
    /// Where the focus core was (the sequence starts there).
    var origin: CGPoint
    var ringRadius: CGFloat
    /// The new star's resting place in today's constellation.
    var starFinal: CGPoint
    var starRadius: CGFloat
    var starPoints: Int
    var starColor: Color
    /// Today's other stars, in order, at their resting places.
    var neighbors: [CGPoint]
    var neighborColors: [Color]
    var neighborPoints: [Int]
    /// The neighbor the new constellation line draws from.
    var previous: CGPoint?
    /// The next empty slot, pulsed once.
    var nextSlot: CGPoint?
    var constellationComplete: Bool

    init(size: CGSize, reward: SessionReward, plan: CelebrationPlan) {
        self.size = size
        origin = FocusSceneView.center(for: size)
        ringRadius = FocusSceneView.ringRadius(for: size)
        let category = reward.category
        starPoints = category.starPoints
        starColor = category.color
        starRadius = CGFloat(7 + 4 * (reward.star?.scale ?? 1)) * (plan.kind == .endedEarly ? 0.8 : 1)
        constellationComplete = reward.constellationFormed != nil

        let area = CGRect(x: 56, y: size.height * 0.09, width: size.width - 112, height: size.height * 0.24)
        let stars = reward.todayStars
        guard let newStar = reward.star else {
            starFinal = CGPoint(x: area.midX, y: area.midY)
            neighbors = []; neighborColors = []; neighborPoints = []
            return
        }
        // Show today's stars, but only the current constellation group.
        let n = max(2, reward.starsPerConstellation)
        let index = stars.firstIndex(where: { $0.id == newStar.id }) ?? (stars.count - 1)
        let groupStart = (index / n) * n
        let group = Array(stars[groupStart...min(stars.count - 1, index)])
        let pts = group.map(\.position)
        let minX = pts.map(\.x).min() ?? 0, maxX = pts.map(\.x).max() ?? 0
        let minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 0
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let scale = min(Double(area.width) / w, Double(area.height) / h, 2.2)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        func map(_ p: WorldPoint) -> CGPoint {
            group.count == 1
                ? CGPoint(x: area.midX + area.width * 0.12, y: area.midY)
                : CGPoint(x: area.midX + (p.x - cx) * scale, y: area.midY + (p.y - cy) * scale)
        }
        starFinal = map(newStar.position)
        let others = group.filter { $0.id != newStar.id }
        neighbors = others.map { map($0.position) }
        neighborColors = others.map { CelestialPainter.color(forHue: $0.hue) }
        neighborPoints = others.map { $0.category?.starPoints ?? 4 }
        previous = neighbors.last
        if !constellationComplete {
            let dir: CGPoint
            if let prev = previous {
                dir = CGPoint(x: starFinal.x - prev.x, y: starFinal.y - prev.y)
            } else {
                dir = CGPoint(x: 46, y: -28)
            }
            let len = max(1, hypot(dir.x, dir.y))
            let step: CGFloat = 52
            nextSlot = CGPoint(x: starFinal.x + dir.x / len * step * 0.8 - dir.y / len * step * 0.6,
                               y: starFinal.y + dir.y / len * step * 0.8 + dir.x / len * step * 0.6)
        }
    }
}

/// Precomputed particle for the energy release.
struct CelebrationParticle {
    var angle: Double
    var speed: Double
    var radius: CGFloat
    var color: Color
    var swirl: Double

    static func make(count: Int, category: FocusCategory, seed: UInt64) -> [CelebrationParticle] {
        var rng = SeededRandom(seed: seed)
        let palette = [category.color, Color(hex: Palette.warmGold), .white, Color(hex: Palette.cosmicViolet), category.color]
        return (0..<count).map { i in
            CelebrationParticle(angle: rng.range(0, 2 * .pi), speed: rng.range(160, 430),
                                radius: rng.range(0.8, 2.6), color: palette[i % palette.count],
                                swirl: rng.range(1.6, 2.8))
        }
    }
}
