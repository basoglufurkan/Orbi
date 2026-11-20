import Foundation
import SwiftData

/// Versioned schema. Every property has a default, so additions are
/// lightweight migrations that SwiftData infers on open.
///
/// - 1.0.0: initial release.
/// - 1.1.0: task planning on `FocusTask` (`isPlanned`, `notes`,
///   `estimatedSessions`, `dueDate`, `isCompleted`, `completedAt`,
///   `sortOrder`, `listName`), all defaulted or optional.
/// - 1.2.0: the Odyssey (`OdysseyWorld`, `Expedition`, `OdysseyLedgerEntry`,
///   `HorizonGoal`, `OdysseyProfile`) — new entities only, inferred.
/// - 1.3.0: focusing together (`SharedFocus`) — a new entity, inferred.
/// - 1.4.0: iCloud sync — `UserPreferences.universeCreatedAt` (optional), so
///   day 1 of the universe travels with the history. The sky entities moved
///   to a device-only store and are rebuilt from history.
/// - 1.5.0: `UserPreferences.rareEventNotifications` (defaulted).
/// - 1.6.0: the day plan — `FocusTask.scheduledStart` (optional),
///   `scheduledMinutes`, `remindBeforeMinutes`, `remindAtStart`,
///   `alarmAtStart` (defaulted).
/// - 1.7.0: habits (`Habit`, `HabitCheckIn`) — new entities only, inferred.
///
/// Add `LumoraSchemaV2` + a custom migration stage here only for a change
/// that can't be inferred (a rename, a type change, a data transform); that
/// also means freezing the current models as nested types of this enum.
enum LumoraSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 7, 0) }

    static var models: [any PersistentModel.Type] {
        [FocusSession.self, FocusTask.self, CelestialObject.self, AchievementUnlock.self,
         UniverseProgress.self, UserPreferences.self, TimerCheckpoint.self,
         OdysseyWorld.self, Expedition.self, OdysseyLedgerEntry.self, HorizonGoal.self, OdysseyProfile.self,
         SharedFocus.self, Habit.self, HabitCheckIn.self]
    }
}

enum LumoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LumoraSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
