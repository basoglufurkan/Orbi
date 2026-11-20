import Foundation
import SwiftData

enum CelestialKind: String, Codable, CaseIterable, Sendable {
    /// The starter star every universe begins with.
    case seed
    /// One per qualifying session.
    case star
    /// Four same-day stars that connect.
    case constellation
    /// Born at session milestones (10, 60, 120, …).
    case planet
    /// Captured by a planet at intermediate milestones.
    case moon
    /// Painted by a 7-day rhythm.
    case nebula
    /// Marks focus-hour milestones.
    case comet

    var displayName: String {
        switch self {
        case .seed: String(localized: "First star")
        case .star: String(localized: "Star")
        case .constellation: String(localized: "Constellation")
        case .planet: String(localized: "Planet")
        case .moon: String(localized: "Moon")
        case .nebula: String(localized: "Nebula")
        case .comet: String(localized: "Comet")
        }
    }
}

/// A permanent object in the user's universe.
///
/// Objects are append-only: nothing decays, and the only deletion path is
/// "Erase all data". Each object records what created it (`sourceSessionID`
/// or `sourceAchievementID`) and a `rewardKey` that makes reward creation
/// idempotent. Position and look are derived deterministically from `seed`
/// at creation time and then stored, so the universe is identical on relaunch.
@Model
final class CelestialObject {
    var id: UUID = UUID()
    var kindRaw: String = CelestialKind.star.rawValue
    var rewardKey: String = ""
    var seed: Int64 = 0
    var bornAt: Date = Date.distantPast
    var x: Double = 0
    var y: Double = 0
    /// Visual size multiplier (duration → size for stars).
    var scale: Double = 1
    /// Category raw value for stars; palette name for other objects.
    var hueRaw: String = ""
    var name: String = ""
    var regionRaw: String = UniverseRegion.homeCluster.rawValue
    /// Star number for stars, world number for planets, etc.
    var ordinal: Int = 0
    var dayKeyRaw: String = ""
    var focusedMinutes: Int = 0
    var sourceSessionID: UUID?
    var sourceAchievementID: String?
    /// Star ordinals linked by a constellation, or the planet ordinal a moon orbits.
    var linkedOrdinals: [Int] = []

    init(draft: CelestialDraft) {
        self.kindRaw = draft.kind.rawValue
        self.rewardKey = draft.rewardKey
        self.seed = Int64(bitPattern: draft.seed)
        self.bornAt = draft.bornAt
        self.x = draft.position.x
        self.y = draft.position.y
        self.scale = draft.scale
        self.hueRaw = draft.hue
        self.name = draft.name
        self.regionRaw = draft.region.rawValue
        self.ordinal = draft.ordinal
        self.dayKeyRaw = draft.dayKey.rawValue
        self.focusedMinutes = draft.focusedMinutes
        self.sourceSessionID = draft.sourceSessionID
        self.sourceAchievementID = draft.sourceAchievementID
        self.linkedOrdinals = draft.linkedOrdinals
    }

    var kind: CelestialKind { CelestialKind(rawValue: kindRaw) ?? .star }
    var category: FocusCategory? { FocusCategory(rawValue: hueRaw) }
    var region: UniverseRegion { UniverseRegion(rawValue: regionRaw) ?? .homeCluster }
    var position: WorldPoint { WorldPoint(x: x, y: y) }
    var unsignedSeed: UInt64 { UInt64(bitPattern: seed) }
}
