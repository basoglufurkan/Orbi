import Foundation
import SwiftData

/// Singleton aggregate of the user's universe. Counters are a cache of what
/// the `CelestialObject` and `FocusSession` tables already prove; they are
/// recomputed by `RewardService` after each reward so they can never drift.
@Model
final class UniverseProgress {
    /// Day 1 of the universe (onboarding completion).
    var createdAt: Date = Date.distantPast
    var starCount: Int = 0
    var constellationCount: Int = 0
    var planetCount: Int = 0
    var qualifyingSessionCount: Int = 0
    var totalFocusSeconds: Int = 0
    /// Ambient brightness the sky has earned (0...1). Each star adds a little;
    /// the universe is "permanently a little brighter than before".
    var ambientLight: Double = 0
    var updatedAt: Date = Date.distantPast

    init(createdAt: Date) {
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
