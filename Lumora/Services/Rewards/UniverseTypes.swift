import Foundation

/// A point in universe ("world") coordinates. 1 unit ≈ 1pt at zoom 1.
struct WorldPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    static let zero = WorldPoint(x: 0, y: 0)

    func distance(to other: WorldPoint) -> Double {
        let dx = x - other.x, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    func offset(angle: Double, distance: Double) -> WorldPoint {
        WorldPoint(x: x + cos(angle) * distance, y: y + sin(angle) * distance)
    }

    static func + (a: WorldPoint, b: WorldPoint) -> WorldPoint { WorldPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: WorldPoint, b: WorldPoint) -> WorldPoint { WorldPoint(x: a.x - b.x, y: a.y - b.y) }
}

/// Named areas of the universe. New regions open as sessions accumulate;
/// each day's stars are placed in the newest open region.
enum UniverseRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case homeCluster, roseVeil, ostrasReach, outerDrift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homeCluster: String(localized: "Home Cluster")
        case .roseVeil: String(localized: "Rose Veil")
        case .ostrasReach: String(localized: "Ostra’s Reach")
        case .outerDrift: String(localized: "The Outer Drift")
        }
    }

    /// Qualifying sessions required to open the region.
    var unlockSessions: Int {
        switch self {
        case .homeCluster: 0
        case .roseVeil: 25
        case .ostrasReach: 60
        case .outerDrift: 200
        }
    }

    var center: WorldPoint {
        switch self {
        case .homeCluster: WorldPoint(x: 0, y: 0)
        case .roseVeil: WorldPoint(x: -1150, y: -420)
        case .ostrasReach: WorldPoint(x: 1200, y: 360)
        case .outerDrift: WorldPoint(x: 120, y: 1650)
        }
    }

    /// Accent used for the region's nebula wash.
    var hue: UInt32 {
        switch self {
        case .homeCluster: Palette.cosmicViolet
        case .roseVeil: Palette.nebulaPink
        case .ostrasReach: Palette.starlightCyan
        case .outerDrift: Palette.warmGold
        }
    }

    static func newestOpen(forQualifyingSessions count: Int) -> UniverseRegion {
        allCases.last { count >= $0.unlockSessions } ?? .homeCluster
    }
}

/// A celestial object about to be created by the progression engine.
struct CelestialDraft: Equatable, Sendable {
    var kind: CelestialKind
    var rewardKey: String
    var seed: UInt64
    var bornAt: Date
    var position: WorldPoint
    var scale: Double
    var hue: String
    var name: String
    var region: UniverseRegion
    var ordinal: Int
    var dayKey: DayKey
    var focusedMinutes: Int
    var sourceSessionID: UUID?
    var sourceAchievementID: String?
    var linkedOrdinals: [Int] = []
}

/// Immutable, render-ready copy of a `CelestialObject` (or draft). Renderers
/// and engines work on snapshots so they never touch the model context.
struct CelestialSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: CelestialKind
    var rewardKey: String
    var position: WorldPoint
    var scale: Double
    var hue: String
    var name: String
    var ordinal: Int
    var dayKey: DayKey
    var bornAt: Date
    var focusedMinutes: Int
    var region: UniverseRegion
    var linkedOrdinals: [Int]
    var seed: UInt64
    var sourceSessionID: UUID?

    var category: FocusCategory? { FocusCategory(rawValue: hue) }

    /// Radius (world units) used for hit-testing and overlap avoidance.
    var footprint: Double {
        switch kind {
        case .seed: 16
        case .star: 10 + 6 * scale
        case .planet: 64
        case .moon: 22
        case .nebula: 0
        case .comet: 26
        case .constellation: 0
        }
    }
}

extension CelestialDraft {
    init(_ object: CelestialObject) {
        self.init(kind: object.kind, rewardKey: object.rewardKey, seed: object.unsignedSeed, bornAt: object.bornAt,
                  position: object.position, scale: object.scale, hue: object.hueRaw, name: object.name,
                  region: object.region, ordinal: object.ordinal, dayKey: DayKey(rawValue: object.dayKeyRaw),
                  focusedMinutes: object.focusedMinutes, sourceSessionID: object.sourceSessionID,
                  sourceAchievementID: object.sourceAchievementID, linkedOrdinals: object.linkedOrdinals)
    }
}

extension CelestialSnapshot {
    init(_ object: CelestialObject) {
        self.init(id: object.id, kind: object.kind, rewardKey: object.rewardKey,
                  position: object.position, scale: object.scale, hue: object.hueRaw,
                  name: object.name, ordinal: object.ordinal, dayKey: DayKey(rawValue: object.dayKeyRaw),
                  bornAt: object.bornAt, focusedMinutes: object.focusedMinutes, region: object.region,
                  linkedOrdinals: object.linkedOrdinals, seed: object.unsignedSeed,
                  sourceSessionID: object.sourceSessionID)
    }

    init(draft: CelestialDraft, id: UUID = UUID()) {
        self.init(id: id, kind: draft.kind, rewardKey: draft.rewardKey, position: draft.position,
                  scale: draft.scale, hue: draft.hue, name: draft.name, ordinal: draft.ordinal,
                  dayKey: draft.dayKey, bornAt: draft.bornAt, focusedMinutes: draft.focusedMinutes,
                  region: draft.region, linkedOrdinals: draft.linkedOrdinals, seed: draft.seed,
                  sourceSessionID: draft.sourceSessionID)
    }
}

/// The facts about a stored session that progression and statistics need.
struct SessionFacts: Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var dayKey: DayKey
    var focusedSeconds: Int
    var plannedSeconds: Int
    var pauseCount: Int
    var category: FocusCategory
    var outcome: SessionOutcome
    var intention: String

    var qualifies: Bool { outcome.earnsStar }
    var focusedMinutes: Int { focusedSeconds / 60 }
}

extension SessionFacts {
    init(_ s: FocusSession) {
        self.init(id: s.id, startedAt: s.startedAt, endedAt: s.endedAt, dayKey: s.dayKey,
                  focusedSeconds: s.focusedSeconds, plannedSeconds: s.plannedSeconds,
                  pauseCount: s.pauseCount, category: s.category, outcome: s.outcome,
                  intention: s.intention)
    }
}
