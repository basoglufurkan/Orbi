import Foundation
import SwiftData

/// A world that has emerged in the user's universe. Created exactly once per
/// ordinal (enforced by `OdysseyService`), never deleted except by "Erase all
/// data". Name and class are stored so they stay stable even if the
/// generator's content changes in a future version.
@Model
final class OdysseyWorld {

    var ordinal: Int = 0
    var seed: Int64 = 0
    var galaxyIndex: Int = 0
    var archetypeRaw: String = WorldArchetype.verdant.rawValue
    var name: String = ""
    var emergedAt: Date = Date.distantPast
    /// The focus session whose minutes made this world emerge (nil if it
    /// emerged while catching up with older history).
    var emergedSessionID: UUID?
    var statusRaw: String = WorldStatus.uncharted.rawValue
    var visitedAt: Date?
    var stage: Int = 0
    var lastCultivatedAt: Date?

    init(blueprint: WorldBlueprint, galaxyIndex: Int, emergedAt: Date, sessionID: UUID?) {
        ordinal = blueprint.ordinal
        seed = Int64(bitPattern: blueprint.seed)
        self.galaxyIndex = galaxyIndex
        archetypeRaw = blueprint.archetype.rawValue
        name = blueprint.name
        self.emergedAt = emergedAt
        emergedSessionID = sessionID
    }

    var status: WorldStatus {
        get { WorldStatus(rawValue: statusRaw) ?? .uncharted }
        set { statusRaw = newValue.rawValue }
    }

    var worldStage: WorldStage { WorldStage(rawValue: stage) ?? .discovered }

    /// How far along a world is, for keeping the right copy after a sync.
    var statusRank: Int {
        switch status {
        case .uncharted: 0
        case .enRoute: 1
        case .charted: 2
        }
    }
}

enum ExpeditionStatus: String, Codable, Sendable {
    case enRoute, arrived, recalled
}

/// A journey to a world. Its progress is never stored: it is the sum of the
/// focus minutes recorded after `startedAt`, so it can't drift or be lost.
@Model
final class Expedition {
    var id: UUID = UUID()
    var worldOrdinal: Int = 0
    var startedAt: Date = Date.distantPast
    var requiredMinutes: Int = 25
    var stardustCost: Int = 0
    var statusRaw: String = ExpeditionStatus.enRoute.rawValue
    var arrivedAt: Date?
    /// The session whose minutes completed the journey.
    var arrivalSessionID: UUID?
    /// The landing cinematic has been shown.
    var arrivalSeen: Bool = false

    init(worldOrdinal: Int, startedAt: Date, requiredMinutes: Int, stardustCost: Int) {
        self.worldOrdinal = worldOrdinal
        self.startedAt = startedAt
        self.requiredMinutes = requiredMinutes
        self.stardustCost = stardustCost
    }

    var status: ExpeditionStatus {
        get { ExpeditionStatus(rawValue: statusRaw) ?? .enRoute }
        set { statusRaw = newValue.rawValue }
    }
}

enum LedgerKind: String, Codable, Sendable {
    case expedition, refund, cultivation, shipPart, horizonReward, cosmicEvent
}

/// Stardust that was spent (negative) or granted outside focus (positive).
/// `key` makes every entry idempotent: the same purchase can't be charged twice.
@Model
final class OdysseyLedgerEntry {
    var key: String = ""
    var date: Date = Date.distantPast
    var amount: Int = 0
    var kindRaw: String = LedgerKind.expedition.rawValue
    var note: String = ""

    init(key: String, date: Date, amount: Int, kind: LedgerKind, note: String) {
        self.key = key
        self.date = date
        self.amount = amount
        kindRaw = kind.rawValue
        self.note = note
    }
}

enum HorizonStatus: String, Codable, Sendable {
    case active, achieved, rested
}

/// A goal the user chose ("Horizon"). Progress is derived from data recorded
/// after `startedAt`; a weekly goal that ends unmet simply rests — no penalty.
@Model
final class HorizonGoal {
    var id: UUID = UUID()
    var kindRaw: String = HorizonKind.sessions.rawValue
    var target: Int = 5
    var startedAt: Date = Date.distantPast
    var endsAt: Date?
    var statusRaw: String = HorizonStatus.active.rawValue
    var achievedAt: Date?
    var achievedSessionID: UUID?
    var rewardStardust: Int = 0
    var rewardSeen: Bool = false

    init(kind: HorizonKind, target: Int, startedAt: Date, endsAt: Date?) {
        kindRaw = kind.rawValue
        self.target = target
        self.startedAt = startedAt
        self.endsAt = endsAt
        rewardStardust = kind.rewardStardust(target: target)
    }

    var kind: HorizonKind { HorizonKind(rawValue: kindRaw) ?? .sessions }
    var status: HorizonStatus {
        get { HorizonStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

/// Singleton: the user's ship, owned parts and Odyssey milestones.
@Model
final class OdysseyProfile {
    var introSeen: Bool = false
    var ownedPartKeys: [String] = []
    var hullRaw: String = ShipHull.lantern.rawValue
    var paintRaw: String = ShipPaint.pearl.rawValue
    var trailRaw: String = ShipTrail.ion.rawValue
    /// Highest rank level already celebrated (so each rank-up shows once).
    var celebratedRankLevel: Int = 1
    /// Galaxies already celebrated as ignited.
    var celebratedGalaxies: Int = 1
    var createdAt: Date = Date.distantPast

    init(createdAt: Date) { self.createdAt = createdAt }

    var loadout: ShipLoadout {
        ShipLoadout(hull: ShipHull(rawValue: hullRaw) ?? .lantern,
                    paint: ShipPaint(rawValue: paintRaw) ?? .pearl,
                    trail: ShipTrail(rawValue: trailRaw) ?? .ion)
    }

    var ownedParts: Set<ShipPart> {
        ShipPart.starter.union(ownedPartKeys.compactMap(ShipPart.init(key:)))
    }
}
