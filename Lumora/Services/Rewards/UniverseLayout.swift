import Foundation

/// Deterministic placement of celestial objects.
///
/// Each focus *day* gets an anchor on a golden-angle spiral inside the newest
/// open region; that day's stars chain outward from the anchor, which is what
/// makes four same-day stars read as a constellation. Every random choice
/// comes from `SeededRandom` seeded by stable identifiers, and candidates
/// that would overlap existing objects are nudged along a deterministic
/// search path. Same inputs → same universe, always.
enum UniverseLayout {
    static let goldenAngle = 2.399_963_229_728_653
    static let starClearance = 30.0
    /// Bumped when placement changes, so every device redraws its sky with
    /// the same rules (see `AppModel`).
    static let version = 3

    /// Fixed home for each planet index; later worlds spiral outward.
    static func planetAnchor(index: Int) -> WorldPoint {
        switch index {
        case 0: return UniverseRegion.homeCluster.center
        case 1: return UniverseRegion.ostrasReach.center
        case 2: return WorldPoint(x: -460, y: 560)
        case 3: return UniverseRegion.outerDrift.center
        default:
            let angle = Double(index) * goldenAngle
            return WorldPoint.zero.offset(angle: angle, distance: 900 + 260 * Double(index - 3))
        }
    }

    static let seedStarPosition = WorldPoint(x: -64, y: -150)

    /// Anchor for the `dayIndex`-th focus day placed in `region`.
    ///
    /// The home cluster spirals out from its centre. A region opened later
    /// grows from its `gateway` — just past the sky's edge, on the way to the
    /// region — fanning outward, so the sky widens with no empty gap.
    static func dayAnchor(region: UniverseRegion, dayIndex: Int, seed: UInt64, gateway: WorldPoint? = nil) -> WorldPoint {
        var rng = SeededRandom(seed: seed)
        guard region != .homeCluster, let gateway else {
            let regionTwist = Double(StableHash.fnv1a(region.rawValue) % 628) / 100
            let angle = Double(dayIndex) * goldenAngle + regionTwist + rng.range(-0.18, 0.18)
            let radius = 190 + 92 * Double(dayIndex).squareRoot() + rng.range(-18, 18)
            return region.center.offset(angle: angle, distance: radius)
        }
        let outward = atan2(region.center.y - gateway.y, region.center.x - gateway.x)
        // Golden-angle steps folded into a fan that opens as the region fills.
        let turn = (Double(dayIndex) * goldenAngle).truncatingRemainder(dividingBy: 2 * .pi) / .pi - 1
        let fan = min(.pi * 0.7, 0.5 + 0.12 * Double(dayIndex))
        let angle = outward + turn * fan + rng.range(-0.15, 0.15)
        let radius = 40 + 92 * Double(dayIndex).squareRoot() + rng.range(-14, 14)
        return gateway.offset(angle: angle, distance: radius)
    }

    /// Where a newly opened region starts: a short step from the earlier star
    /// nearest the region, toward its centre (never beyond it). Starting from
    /// a real star keeps the new region beside the sky that's already there;
    /// stepping past the farthest star along the region's direction could
    /// land far off to the side of every star.
    static func gateway(to region: UniverseRegion, beyond earlier: [WorldPoint]) -> WorldPoint {
        let c = region.center
        guard let near = earlier.min(by: { $0.distance(to: c) < $1.distance(to: c) }) else { return c }
        let dx = c.x - near.x, dy = c.y - near.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > gatewayStep else { return c }
        return WorldPoint(x: near.x + dx / length * gatewayStep, y: near.y + dy / length * gatewayStep)
    }

    static let gatewayStep = 160.0

    /// Next link in a day's chain of stars.
    static func chainStep(from previous: WorldPoint, indexInDay: Int, seed: UInt64) -> WorldPoint {
        var rng = SeededRandom(seed: seed)
        let base = Double(seed % 628) / 100
        let angle = base + Double(indexInDay) * 1.05 + rng.range(-0.5, 0.5)
        return previous.offset(angle: angle, distance: rng.range(46, 74))
    }

    /// Small jitter for the first star of a day around its anchor.
    static func jitter(_ point: WorldPoint, seed: UInt64, amount: Double) -> WorldPoint {
        var rng = SeededRandom(seed: seed ^ 0xA5A5_A5A5)
        return point.offset(angle: rng.range(0, 2 * .pi), distance: rng.range(0, amount))
    }

    /// Moves `candidate` to the nearest free spot (deterministic spiral search).
    static func placeFree(_ candidate: WorldPoint, clearance: Double, occupied: [CelestialSnapshot]) -> WorldPoint {
        func isFree(_ p: WorldPoint) -> Bool {
            for o in occupied where o.footprint > 0 {
                if o.position.distance(to: p) < clearance + o.footprint { return false }
            }
            return true
        }
        if isFree(candidate) { return candidate }
        for step in 1...160 {
            let angle = Double(step) * goldenAngle
            let distance = 8 * Double(step).squareRoot() * 2
            let p = candidate.offset(angle: angle, distance: distance)
            if isFree(p) { return p }
        }
        return candidate
    }
}
