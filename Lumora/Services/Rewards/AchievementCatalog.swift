import Foundation

enum AchievementRarity: String, Codable, Sendable {
    case common, rare, holographic

    var label: String {
        switch self {
        case .common: String(localized: "Artifact")
        case .rare: String(localized: "Rare")
        case .holographic: String(localized: "Holographic")
        }
    }
}

/// What must be true in `ProgressStats` for an achievement to unlock.
enum AchievementRequirement: Equatable, Sendable {
    case sessions(Int)
    case focusHours(Int)
    case completedSessionMinutes(Int)
    case sessionsInOneDay(Int)
    case goalDays(Int)
    case rhythmDays(Int)
    case bestDayMinutes(Int)

    func isSatisfied(by s: ProgressStats) -> Bool {
        switch self {
        case let .sessions(n): s.qualifyingSessions >= n
        case let .focusHours(h): s.totalFocusSeconds >= h * 3600
        case let .completedSessionMinutes(m): s.longestCompletedSeconds >= m * 60
        case let .sessionsInOneDay(n): s.maxQualifyingSessionsInDay >= n
        case let .goalDays(n): s.goalDays >= n
        case let .rhythmDays(n): s.longestRhythm >= n
        case let .bestDayMinutes(m): s.bestDaySeconds >= m * 60
        }
    }

    /// 0...1 progress toward the requirement, for "in orbit" cards.
    func progress(in s: ProgressStats) -> Double {
        func ratio(_ a: Int, _ b: Int) -> Double { b > 0 ? min(1, Double(a) / Double(b)) : 1 }
        switch self {
        case let .sessions(n): return ratio(s.qualifyingSessions, n)
        case let .focusHours(h): return ratio(s.totalFocusSeconds, h * 3600)
        case let .completedSessionMinutes(m): return ratio(s.longestCompletedSeconds, m * 60)
        case let .sessionsInOneDay(n): return ratio(s.maxQualifyingSessionsInDay, n)
        case let .goalDays(n): return ratio(s.goalDays, n)
        case let .rhythmDays(n): return ratio(s.longestRhythm, n)
        case let .bestDayMinutes(m): return ratio(s.bestDaySeconds, m * 60)
        }
    }
}

/// Visual motif for the artifact card.
enum ArtifactMotif: String, Sendable {
    case spark, constellation, ring, sun, planet, orbit, nebula, comet, moon, tide
}

struct AchievementDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let title: String
    let detail: String
    let lore: String
    let rarity: AchievementRarity
    let motif: ArtifactMotif
    let requirement: AchievementRequirement

    /// Rare and holographic artifacts get the milestone celebration.
    var isMilestone: Bool { rarity != .common }
}

/// The 18 cosmic artifacts.
enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        .init(id: "sessions.1", number: 1, title: String(localized: "First Light"),
              detail: String(localized: "Complete your first session"),
              lore: String(localized: "The first star you made. Everything begins here."),
              rarity: .common, motif: .spark, requirement: .sessions(1)),
        .init(id: "day.4", number: 2, title: String(localized: "Connected"),
              detail: String(localized: "Four sessions in one day"),
              lore: String(localized: "Four lights reached for each other and held on."),
              rarity: .common, motif: .constellation, requirement: .sessionsInOneDay(4)),
        .init(id: "sessions.10", number: 3, title: String(localized: "Star Collector"),
              detail: String(localized: "Complete 10 sessions"),
              lore: String(localized: "Ten small suns, and a world begins to gather."),
              rarity: .common, motif: .constellation, requirement: .sessions(10)),
        .init(id: "goal.1", number: 4, title: String(localized: "Full Circle"),
              detail: String(localized: "Reach your daily goal"),
              lore: String(localized: "A whole day's light, gathered on purpose."),
              rarity: .common, motif: .ring, requirement: .goalDays(1)),
        .init(id: "rhythm.3", number: 5, title: String(localized: "Kindling"),
              detail: String(localized: "Focus on 3 days in a rhythm"),
              lore: String(localized: "A small fire you came back to tend."),
              rarity: .common, motif: .spark, requirement: .rhythmDays(3)),
        .init(id: "hours.1", number: 6, title: String(localized: "First Hour"),
              detail: String(localized: "Gather one hour of focus"),
              lore: String(localized: "Sixty minutes that were entirely yours."),
              rarity: .common, motif: .sun, requirement: .focusHours(1)),
        .init(id: "rhythm.7", number: 7, title: String(localized: "Cosmic Rhythm"),
              detail: String(localized: "Focus on 7 consecutive days"),
              lore: String(localized: "A week of returning. A nebula unfurled to mark it."),
              rarity: .holographic, motif: .nebula, requirement: .rhythmDays(7)),
        .init(id: "length.60", number: 8, title: String(localized: "Tidal Mind"),
              detail: String(localized: "Complete a 60-minute session"),
              lore: String(localized: "One long, unbroken tide of attention."),
              rarity: .common, motif: .tide, requirement: .completedSessionMinutes(60)),
        .init(id: "sessions.25", number: 9, title: String(localized: "Quarter Sky"),
              detail: String(localized: "Complete 25 sessions"),
              lore: String(localized: "A second region of sky opens to you."),
              rarity: .common, motif: .orbit, requirement: .sessions(25)),
        .init(id: "hours.10", number: 10, title: String(localized: "Steady Glow"),
              detail: String(localized: "Gather 10 hours of focus"),
              lore: String(localized: "Ten hours, and the whole sky is a little warmer."),
              rarity: .common, motif: .sun, requirement: .focusHours(10)),
        .init(id: "goal.7", number: 11, title: String(localized: "Seven Circles"),
              detail: String(localized: "Reach your daily goal on 7 days"),
              lore: String(localized: "Seven full days of light, kept like rings."),
              rarity: .rare, motif: .ring, requirement: .goalDays(7)),
        .init(id: "bestday.180", number: 12, title: String(localized: "Supernova"),
              detail: String(localized: "Focus for 3 hours in one day"),
              lore: String(localized: "A day so bright it left a mark on the sky."),
              rarity: .rare, motif: .comet, requirement: .bestDayMinutes(180)),
        .init(id: "sessions.50", number: 13, title: String(localized: "Fifty Lights"),
              detail: String(localized: "Complete 50 sessions"),
              lore: String(localized: "Half a hundred stars, each one chosen."),
              rarity: .common, motif: .constellation, requirement: .sessions(50)),
        .init(id: "hours.30", number: 14, title: String(localized: "New Horizon"),
              detail: String(localized: "Reach a personal milestone: your first 30 hours"),
              lore: String(localized: "Thirty hours. The horizon moved, and so did you."),
              rarity: .rare, motif: .planet, requirement: .focusHours(30)),
        .init(id: "sessions.100", number: 15, title: String(localized: "Hundred Suns"),
              detail: String(localized: "100 sessions completed"),
              lore: String(localized: "One hundred sessions of focus. A hundred small suns, each one something you chose to do."),
              rarity: .rare, motif: .sun, requirement: .sessions(100)),
        .init(id: "rhythm.30", number: 16, title: String(localized: "Lunar Cycle"),
              detail: String(localized: "Keep a 30-day rhythm"),
              lore: String(localized: "A full turn of the moon, and you kept returning."),
              rarity: .holographic, motif: .moon, requirement: .rhythmDays(30)),
        .init(id: "hours.100", number: 17, title: String(localized: "Deep Orbit"),
              detail: String(localized: "Complete 100 focused hours"),
              lore: String(localized: "A hundred hours in orbit around what matters."),
              rarity: .holographic, motif: .orbit, requirement: .focusHours(100)),
        .init(id: "sessions.250", number: 18, title: String(localized: "Galaxy Keeper"),
              detail: String(localized: "Complete 250 sessions"),
              lore: String(localized: "A galaxy, kept one session at a time."),
              rarity: .holographic, motif: .nebula, requirement: .sessions(250)),
    ]

    private static let byID: [String: AchievementDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definition(for id: String) -> AchievementDefinition? { byID[id] }
}

/// Derives unlocks from verified statistics. Never awards twice.
enum AchievementEngine {
    static func newlyUnlocked(stats: ProgressStats, alreadyUnlocked: Set<String>) -> [AchievementDefinition] {
        AchievementCatalog.all.filter { !alreadyUnlocked.contains($0.id) && $0.requirement.isSatisfied(by: stats) }
    }
}
