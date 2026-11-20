import Foundation

/// Everything the completion sequence needs, reconstructed from persisted
/// data (so it can be re-shown after a relaunch and is never "optimistic").
struct SessionReward: Equatable, Sendable {
    var sessionID: UUID
    var outcome: SessionOutcome
    var category: FocusCategory
    var intention: String
    var focusedMinutes: Int
    var plannedMinutes: Int
    var endedAt: Date
    var star: CelestialSnapshot?
    /// Non-star objects this session created (constellation, planet, …).
    var newObjects: [CelestialSnapshot]
    var newAchievements: [AchievementDefinition]
    var todayMinutesBefore: Int
    var todayMinutes: Int
    var goalMinutes: Int
    /// Today's stars in order, including this one.
    var todayStars: [CelestialSnapshot]
    var totalQualifyingSessions: Int
    var starsPerConstellation: Int
    /// The planned task this session counted toward, with its progress
    /// including this session.
    var task: TaskSnapshot? = nil

    var constellationFormed: CelestialSnapshot? { newObjects.first { $0.kind == .constellation } }
    var planetBorn: CelestialSnapshot? { newObjects.first { $0.kind == .planet } }
    var moonCaptured: CelestialSnapshot? { newObjects.first { $0.kind == .moon } }

    /// Planet births and rare artifacts get the milestone celebration.
    var isMilestone: Bool {
        planetBorn != nil || newAchievements.contains(where: \.isMilestone)
    }

    var goalProgressBefore: Double { goalMinutes > 0 ? min(1, Double(todayMinutesBefore) / Double(goalMinutes)) : 0 }
    var goalProgress: Double { goalMinutes > 0 ? min(1, Double(todayMinutes) / Double(goalMinutes)) : 0 }

    /// Stars still needed today to complete the next constellation.
    var starsUntilConstellation: Int {
        let n = max(2, starsPerConstellation)
        let rem = todayStars.count % n
        return rem == 0 ? n : n - rem
    }
}

/// A planned task as the summary shows it ("2 of 4 sessions for Essay draft").
struct TaskSnapshot: Equatable, Sendable {
    var id: UUID
    var title: String
    var category: FocusCategory
    var progress: TaskProgress
    var isCompleted: Bool
}
