import Foundation
import SwiftData
import os

/// Owns the SwiftData container and the app's singleton rows.
///
/// Persistence boundary: views read through `@Query`; all writes go through
/// services (`RewardService`, `DataStore`, `SwiftDataTimerStateStore`) on the
/// main actor.
///
/// Two stores, one container:
/// - **Synced** (the original `default.store`): what the person did —
///   sessions, tasks, preferences, achievements, Odyssey choices and focusing
///   together. With iCloud sync on, it mirrors to their private CloudKit
///   database.
/// - **Device** (`device.store`): what can be derived again — the sky
///   (`CelestialObject`, `UniverseProgress`) is rebuilt from session history
///   on each device, so two devices never disagree about a star; and the
///   running timer, which belongs to the device it runs on.
@MainActor
final class DataStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "DataStore")
    private var preferencesCache: UserPreferences?

    init(container: ModelContainer) {
        self.container = container
    }

    /// The CloudKit container. Its private database mirrors the synced store;
    /// Focus together rooms live in its public database.
    nonisolated static let cloudContainerID = "iCloud.com.mobapptech.lumora"

    static let syncedModels: [any PersistentModel.Type] = [
        FocusSession.self, FocusTask.self, AchievementUnlock.self, UserPreferences.self,
        OdysseyWorld.self, Expedition.self, OdysseyLedgerEntry.self, HorizonGoal.self, OdysseyProfile.self,
        SharedFocus.self, Habit.self, HabitCheckIn.self,
    ]
    static let deviceModels: [any PersistentModel.Type] = [CelestialObject.self, UniverseProgress.self, TimerCheckpoint.self]

    static func makeContainer(inMemory: Bool = false, cloudSync: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LumoraSchemaV1.self)
        let synced: ModelConfiguration
        let device: ModelConfiguration
        var legacy: LegacyDeviceData?
        if inMemory {
            synced = ModelConfiguration("Synced", schema: Schema(syncedModels), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            device = ModelConfiguration("Device", schema: Schema(deviceModels), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            // Where SwiftData put the original single store (the shared app
            // group's Application Support when the app group is signed in).
            let folder = ModelConfiguration(isStoredInMemoryOnly: false).url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            legacy = carryOverLegacyStore(folder: folder, schema: schema)
            // The original single store keeps its file name, so everyone's history carries over.
            synced = ModelConfiguration("Synced", schema: Schema(syncedModels), url: folder.appending(path: "default.store"),
                                        cloudKitDatabase: cloudSync ? .private(cloudContainerID) : .none)
            device = ModelConfiguration("Device", schema: Schema(deviceModels), url: folder.appending(path: "device.store"),
                                        cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: LumoraMigrationPlan.self, configurations: synced, device)
        if let legacy {
            // This device's sky, exactly as it was drawn, and a running timer, into their new home.
            let context = ModelContext(container)
            for draft in legacy.sky { context.insert(CelestialObject(draft: draft)) }
            let progress = UniverseProgress(createdAt: legacy.progress.createdAt)
            progress.starCount = legacy.progress.starCount
            progress.constellationCount = legacy.progress.constellationCount
            progress.planetCount = legacy.progress.planetCount
            progress.qualifyingSessionCount = legacy.progress.qualifyingSessionCount
            progress.totalFocusSeconds = legacy.progress.totalFocusSeconds
            progress.ambientLight = legacy.progress.ambientLight
            progress.updatedAt = legacy.progress.updatedAt
            context.insert(progress)
            if let checkpoint = legacy.checkpoint {
                context.insert(TimerCheckpoint(payload: checkpoint.payload, updatedAt: checkpoint.updatedAt))
            }
            try? context.save()
        }
        return container
    }

    /// Before 1.4 everything lived in `default.store`, the sky included. Open
    /// the old store once as it was: move day 1 of the universe onto the
    /// (synced) preferences and hand back the sky, so upgrading never redraws it.
    private struct LegacyDeviceData {
        var sky: [CelestialDraft]
        var progress: (createdAt: Date, starCount: Int, constellationCount: Int, planetCount: Int,
                       qualifyingSessionCount: Int, totalFocusSeconds: Int, ambientLight: Double, updatedAt: Date)
        var checkpoint: (payload: Data, updatedAt: Date)?
    }

    private static func carryOverLegacyStore(folder: URL, schema: Schema) -> LegacyDeviceData? {
        let old = folder.appending(path: "default.store")
        guard FileManager.default.fileExists(atPath: old.path(percentEncoded: false)),
              !FileManager.default.fileExists(atPath: folder.appending(path: "device.store").path(percentEncoded: false))
        else { return nil }
        do {
            let legacy = try ModelContainer(for: schema, migrationPlan: LumoraMigrationPlan.self,
                                            configurations: ModelConfiguration(schema: schema, url: old, cloudKitDatabase: .none))
            let context = ModelContext(legacy)
            guard let p = try context.fetch(FetchDescriptor<UniverseProgress>()).first else { return nil }
            for prefs in try context.fetch(FetchDescriptor<UserPreferences>()) where prefs.universeCreatedAt == nil {
                prefs.universeCreatedAt = p.createdAt
            }
            let objects = try context.fetch(FetchDescriptor<CelestialObject>())
            let checkpoint = try context.fetch(FetchDescriptor<TimerCheckpoint>()).first
            let data = LegacyDeviceData(
                sky: objects.map(CelestialDraft.init),
                progress: (p.createdAt, p.starCount, p.constellationCount, p.planetCount,
                           p.qualifyingSessionCount, p.totalFocusSeconds, p.ambientLight, p.updatedAt),
                checkpoint: checkpoint.map { ($0.payload, $0.updatedAt) })
            // Moved: clear the old copies so this runs once.
            for object in objects { context.delete(object) }
            context.delete(p)
            if let checkpoint { context.delete(checkpoint) }
            try context.save()
            return data
        } catch {
            Logger(subsystem: "com.mobapptech.lumora", category: "DataStore")
                .error("Couldn't carry the old store over: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Singletons

    func preferences() -> UserPreferences {
        if let cached = preferencesCache, cached.modelContext != nil, !cached.isDeleted { return cached }
        if let prefs = try? context.fetch(FetchDescriptor<UserPreferences>()).first {
            preferencesCache = prefs
            return prefs
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        save()
        preferencesCache = prefs
        return prefs
    }

    func progress() -> UniverseProgress? {
        try? context.fetch(FetchDescriptor<UniverseProgress>()).first
    }

    /// Day 1 of the universe: the synced date, else the first session (history
    /// that arrived without one), else `fallback` (a brand-new universe).
    func universeCreatedAt(fallback: Date) -> Date {
        let prefs = preferences()
        if let date = prefs.universeCreatedAt { return date }
        var first = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt)])
        first.fetchLimit = 1
        let date = min(fallback, (try? context.fetch(first).first?.startedAt) ?? fallback)
        prefs.universeCreatedAt = date
        save()
        return date
    }

    /// Creates the universe (progress row + the starter star) once, on day 1.
    @discardableResult
    func ensureUniverse(createdAt now: Date, calendar: Calendar) -> UniverseProgress {
        let createdAt = universeCreatedAt(fallback: now)
        let progress: UniverseProgress
        if let existing = self.progress() {
            progress = existing
        } else {
            progress = UniverseProgress(createdAt: createdAt)
            context.insert(progress)
        }
        // Writing an unchanged value still dirties the row, and every save
        // wakes the sync observer, which calls back here: only write changes.
        if progress.createdAt != createdAt { progress.createdAt = createdAt }
        let seedKey = "seed"
        var d = FetchDescriptor<CelestialObject>(predicate: #Predicate { $0.rewardKey == seedKey })
        d.fetchLimit = 1
        if let seed = try? context.fetch(d).first {
            if seed.bornAt != createdAt {
                context.delete(seed)
                context.insert(CelestialObject(draft: ProgressionEngine.seedStarDraft(createdAt: createdAt, calendar: calendar)))
            }
        } else {
            context.insert(CelestialObject(draft: ProgressionEngine.seedStarDraft(createdAt: createdAt, calendar: calendar)))
        }
        save()
        return progress
    }

    // MARK: Sync

    /// Two devices that each started before syncing can bring their own copy
    /// of a one-of-a-kind row. Folds them into one, keeping the furthest along.
    /// Returns true if anything changed.
    @discardableResult
    func mergeDuplicates() -> Bool {
        var changed = false
        func drop(_ object: some PersistentModel) {
            context.delete(object)
            changed = true
        }

        let allPrefs = (try? context.fetch(FetchDescriptor<UserPreferences>())) ?? []
        if allPrefs.count > 1 {
            // Keep the one that finished onboarding (and has a name), adopting the earliest day 1.
            let keep = allPrefs.max { a, b in
                (a.hasCompletedOnboarding ? 2 : 0) + (a.displayName.isEmpty ? 0 : 1)
                    < (b.hasCompletedOnboarding ? 2 : 0) + (b.displayName.isEmpty ? 0 : 1)
            }!
            keep.universeCreatedAt = allPrefs.compactMap(\.universeCreatedAt).min()
            keep.hasCompletedOnboarding = allPrefs.contains(where: \.hasCompletedOnboarding)
            for p in allPrefs where p !== keep { drop(p) }
            preferencesCache = keep
        }

        let profiles = (try? context.fetch(FetchDescriptor<OdysseyProfile>())) ?? []
        if profiles.count > 1 {
            // Ship parts bought on either device stay owned.
            let keep = profiles.max { $0.ownedPartKeys.count < $1.ownedPartKeys.count }!
            keep.ownedPartKeys = Array(Set(profiles.flatMap(\.ownedPartKeys))).sorted()
            keep.introSeen = profiles.contains(where: \.introSeen)
            keep.celebratedRankLevel = profiles.map(\.celebratedRankLevel).max() ?? keep.celebratedRankLevel
            keep.celebratedGalaxies = profiles.map(\.celebratedGalaxies).max() ?? keep.celebratedGalaxies
            for p in profiles where p !== keep { drop(p) }
        }

        // Worlds share an ordinal when two devices charted "the next world"; keep the most grown.
        let worlds = (try? context.fetch(FetchDescriptor<OdysseyWorld>())) ?? []
        for (_, group) in Dictionary(grouping: worlds, by: \.ordinal) where group.count > 1 {
            let keep = group.max { ($0.statusRank, $0.stage) < ($1.statusRank, $1.stage) }!
            for w in group where w !== keep { drop(w) }
        }

        let ledger = (try? context.fetch(FetchDescriptor<OdysseyLedgerEntry>())) ?? []
        for (_, group) in Dictionary(grouping: ledger, by: \.key) where group.count > 1 {
            for e in group.dropFirst() { drop(e) }
        }

        let unlocks = (try? context.fetch(FetchDescriptor<AchievementUnlock>(sortBy: [SortDescriptor(\.unlockedAt)]))) ?? []
        for (_, group) in Dictionary(grouping: unlocks, by: \.achievementID) where group.count > 1 {
            for u in group.dropFirst() { drop(u) }
        }

        // One horizon at a time: the most recently started one stays.
        let active = ((try? context.fetch(FetchDescriptor<HorizonGoal>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? [])
            .filter { $0.status == .active }
        for h in active.dropFirst() {
            h.status = .rested
            changed = true
        }

        // A habit kept on two devices the same day: one star is enough.
        let checkIns = (try? context.fetch(FetchDescriptor<HabitCheckIn>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let byHabitDay = Dictionary(grouping: checkIns) { "\($0.habit?.id.uuidString ?? "-")|\($0.dayKeyRaw)" }
        // (A check-in whose habit hasn't arrived yet is left alone.)
        for (key, group) in byHabitDay where group.count > 1 && !key.hasPrefix("-") {
            for c in group.dropFirst() { drop(c) }
        }

        if changed { save() }
        return changed
    }

    func save() {
        do {
            if context.hasChanges { try context.save() }
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Erase

    /// The only deletion path in Lumora. Removes every record and the timer
    /// checkpoint, then the caller returns the user to onboarding.
    func eraseAll() throws {
        // Per-object deletes (not batch deletes): they honour relationship
        // delete rules, which SQLite-backed batch deletes can reject.
        try deleteAll(FocusSession.self)
        try deleteAll(FocusTask.self)
        try deleteAll(CelestialObject.self)
        try deleteAll(AchievementUnlock.self)
        try deleteAll(UniverseProgress.self)
        try deleteAll(TimerCheckpoint.self)
        try deleteAll(UserPreferences.self)
        try deleteAll(OdysseyWorld.self)
        try deleteAll(Expedition.self)
        try deleteAll(OdysseyLedgerEntry.self)
        try deleteAll(HorizonGoal.self)
        try deleteAll(OdysseyProfile.self)
        try deleteAll(SharedFocus.self)
        try deleteAll(HabitCheckIn.self)
        try deleteAll(Habit.self)
        try context.save()
        preferencesCache = nil
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }

    // MARK: Export

    struct ExportDocument: Codable {
        struct Session: Codable {
            var id: UUID; var startedAt: Date; var endedAt: Date; var plannedSeconds: Int
            var focusedSeconds: Int; var pausedSeconds: Int; var pauseCount: Int
            var category: String; var intention: String; var note: String; var outcome: String
            var day: String; var timeZone: String; var starNumber: Int
        }
        struct Object: Codable {
            var kind: String; var name: String; var ordinal: Int; var bornAt: Date
            var x: Double; var y: Double; var scale: Double; var hue: String; var region: String
            var sourceSessionID: UUID?; var sourceAchievementID: String?
        }
        struct Unlock: Codable { var id: String; var title: String; var unlockedAt: Date }

        var exportedAt: Date
        var appVersion: String
        var sessions: [Session]
        var universe: [Object]
        var achievements: [Unlock]
    }

    func exportJSON(now: Date = .now) throws -> Data {
        let sessions = try context.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.endedAt)]))
        let objects = try context.fetch(FetchDescriptor<CelestialObject>(sortBy: [SortDescriptor(\.bornAt)]))
        let unlocks = try context.fetch(FetchDescriptor<AchievementUnlock>(sortBy: [SortDescriptor(\.unlockedAt)]))
        let doc = ExportDocument(
            exportedAt: now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            sessions: sessions.map {
                .init(id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt, plannedSeconds: $0.plannedSeconds,
                      focusedSeconds: $0.focusedSeconds, pausedSeconds: $0.pausedSeconds, pauseCount: $0.pauseCount,
                      category: $0.categoryRaw, intention: $0.intention, note: $0.note, outcome: $0.outcomeRaw,
                      day: $0.dayKeyRaw, timeZone: $0.timeZoneID, starNumber: $0.starNumber)
            },
            universe: objects.map {
                .init(kind: $0.kindRaw, name: $0.name, ordinal: $0.ordinal, bornAt: $0.bornAt, x: $0.x, y: $0.y,
                      scale: $0.scale, hue: $0.hueRaw, region: $0.regionRaw,
                      sourceSessionID: $0.sourceSessionID, sourceAchievementID: $0.sourceAchievementID)
            },
            achievements: unlocks.map { .init(id: $0.achievementID, title: $0.definition?.title ?? $0.achievementID, unlockedAt: $0.unlockedAt) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(doc)
    }
}
