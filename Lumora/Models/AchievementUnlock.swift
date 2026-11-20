import Foundation
import SwiftData

/// A permanently unlocked achievement ("cosmic artifact").
/// Definitions live in `AchievementCatalog`; only the unlock is stored.
@Model
final class AchievementUnlock {
    var achievementID: String = ""
    var unlockedAt: Date = Date.distantPast
    var sourceSessionID: UUID?
    var hasBeenSeen: Bool = false

    init(achievementID: String, unlockedAt: Date, sourceSessionID: UUID?) {
        self.achievementID = achievementID
        self.unlockedAt = unlockedAt
        self.sourceSessionID = sourceSessionID
    }

    var definition: AchievementDefinition? { AchievementCatalog.definition(for: achievementID) }
}
