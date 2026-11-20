import Foundation

/// The Odyssey economy and pacing, in one tunable place.
///
/// Everything here is a pure function of verified data (stored focus
/// sessions and what the user chose to spend), so balances and discoveries
/// can always be recomputed and never drift, duplicate or disappear.
struct OdysseyRules: Equatable, Sendable {
    /// Stardust for each qualifying session: one per focused minute plus a
    /// bonus for finishing. Short sessions still earn; nothing is lost.
    var completionBonus = 5
    /// Minutes of total focus before the first world emerges.
    var firstWorldMinutes = 50
    /// Gap growth between worlds, so there is always something just ahead.
    var gapBase = 60
    var gapStep = 15
    var gapCap = 10
    /// Terraform costs per stage (index = stage). Legendary worlds cost more.
    var stageCosts = [0, 40, 80, 140, 220, 320]
    var legendaryStageMultiplier = 1.5

    static let standard = OdysseyRules()

    // MARK: Stardust

    func stardust(for session: SessionFacts) -> Int {
        guard session.qualifies else { return 0 }
        return session.focusedMinutes + (session.outcome == .completed ? completionBonus : 0)
    }

    // MARK: World emergence

    /// Cumulative focus minutes at which world `ordinal` (1-based) emerges.
    func emergenceThreshold(ordinal: Int) -> Int {
        guard ordinal > 1 else { return firstWorldMinutes }
        var total = firstWorldMinutes
        for i in 1..<ordinal { total += gapBase + gapStep * min(i, gapCap) }
        return total
    }

    func worldsEmerged(totalMinutes: Int) -> Int {
        var k = 0
        while emergenceThreshold(ordinal: k + 1) <= totalMinutes, k < 10_000 { k += 1 }
        return k
    }

    // MARK: Galaxies

    /// How many worlds galaxy `index` holds before the next one ignites.
    func galaxyCapacity(_ index: Int) -> Int { 6 + 2 * index }

    /// The galaxy world `ordinal` belongs to, and its slot inside it.
    func placement(ofWorld ordinal: Int) -> (galaxy: Int, slot: Int) {
        var remaining = ordinal - 1
        var g = 0
        while remaining >= galaxyCapacity(g) {
            remaining -= galaxyCapacity(g)
            g += 1
        }
        return (g, remaining)
    }

    /// Galaxies that exist given `worlds` emerged worlds (the home galaxy always does).
    func galaxiesIgnited(worlds: Int) -> Int {
        guard worlds > 0 else { return 1 }
        return placement(ofWorld: worlds).galaxy + 1
    }

    // MARK: Expeditions

    /// Focus minutes the journey takes. The first trip is a single session.
    func travelMinutes(for world: WorldBlueprint) -> Int {
        guard world.ordinal > 1 else { return 25 }
        let hops = 1 + Int(world.seed % 3)
        return world.rarity == .legendary ? 100 : 25 * hops
    }

    /// Stardust for fuel. The first trip is free.
    func expeditionCost(for world: WorldBlueprint) -> Int {
        guard world.ordinal > 1 else { return 0 }
        return 10 + travelMinutes(for: world) / 2
    }

    // MARK: Terraforming

    func cultivationCost(to stage: WorldStage, rarity: WorldRarity) -> Int {
        let base = stageCosts[min(stage.rawValue, stageCosts.count - 1)]
        return rarity == .legendary ? Int(Double(base) * legendaryStageMultiplier) : base
    }

    // MARK: Ship

    func price(of part: ShipPart) -> Int {
        switch part {
        case .hull(.lantern), .paint(.pearl), .trail(.ion): 0
        case .paint(.nebula), .trail(.solar): 90
        case .paint(.aurora), .hull(.swift): 160
        case .trail(.aurora), .paint(.solar): 220
        case .hull(.ark), .paint(.abyss): 320
        case .trail(.comet): 400
        case .hull(.manta): 520
        case .paint(.eclipse), .paint(.opal): 260
        case .trail(.supernova): 360
        // Chain trails are earned, never sold.
        case .trail(.dawnline), .trail(.starlit), .trail(.prism): 0
        }
    }

    /// Stardust for witnessing the week's rare event.
    var eventReward = 60

    /// Some parts are earned through rank rather than bought.
    func requiredRank(for part: ShipPart) -> Int {
        switch part {
        case .hull(.manta): 5
        case .trail(.comet): 4
        default: 1
        }
    }

    // MARK: Experience

    func experience(focusMinutes: Int, chartedWorlds: Int, stages: Int, galaxies: Int, horizons: Int) -> Int {
        focusMinutes + chartedWorlds * 30 + stages * 20 + max(0, galaxies - 1) * 100 + horizons * 50
    }
}
