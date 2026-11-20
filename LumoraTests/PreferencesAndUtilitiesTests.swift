import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Settings & utilities")
@MainActor
struct PreferencesAndUtilitiesTests {
    @Test func preferencesPersistAcrossContexts() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let store = DataStore(container: container)
        let prefs = store.preferences()
        prefs.dailyGoalMinutes = 150
        prefs.appearance = .dawn
        prefs.motion = .reduced
        prefs.autoStartBreaks = true
        prefs.ambient = .rain
        store.save()

        let other = ModelContext(container)
        let reloaded = try #require(try other.fetch(FetchDescriptor<UserPreferences>()).first)
        #expect(reloaded.dailyGoalMinutes == 150)
        #expect(reloaded.appearance == .dawn)
        #expect(reloaded.motion == .reduced)
        #expect(reloaded.autoStartBreaks)
        #expect(reloaded.ambient == .rain)
        #expect(reloaded.timerDefaults.autoStartBreaks)
    }

    @Test func timerCheckpointPersistsInSwiftData() throws {
        let context = try TestFixtures.makeContext()
        let store = SwiftDataTimerStateStore(context: context)
        let engine = FocusTimerEngine()
        let state = engine.reduce(.idle, .startFocus(TestFixtures.config(), id: UUID(), timeScale: 1),
                                  now: TestFixtures.baseDate, defaults: TimerDefaults()).0
        try store.save(state)
        try store.save(state)
        #expect(SwiftDataTimerStateStore(context: context).load() == state)
        #expect(try context.fetch(FetchDescriptor<TimerCheckpoint>()).count == 1)
    }

    @Test func eraseAllRemovesEverythingFromAnOnDiskStore() throws {
        // On-disk SQLite store with related tasks, as on device.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("erase-\(UUID().uuidString).store")
        let schema = Schema(versionedSchema: LumoraSchemaV1.self)
        let container = try ModelContainer(for: schema, migrationPlan: LumoraMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let store = DataStore(container: container)
        store.ensureUniverse(createdAt: TestFixtures.baseDate, calendar: .current)
        let service = RewardService(context: store.context, clock: ManualDateProvider(now: TestFixtures.baseDate), goalMinutes: { 120 })
        _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate))
        try store.eraseAll()
        #expect(try store.context.fetch(FetchDescriptor<FocusTask>()).isEmpty)
        #expect(try store.context.fetch(FetchDescriptor<CelestialObject>()).isEmpty)
        #expect(try store.context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(store.preferences().hasCompletedOnboarding == false)
    }

    @Test func exportProducesValidJSON() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let store = DataStore(container: container)
        let service = RewardService(context: store.context, clock: ManualDateProvider(now: TestFixtures.baseDate), goalMinutes: { 120 })
        _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate))
        let data = try store.exportJSON()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((object?["sessions"] as? [Any])?.count == 1)
    }

    @Test func clockFormatting() {
        #expect(LMFormat.clock(1500) == "25:00")
        #expect(LMFormat.clock(0.2) == "00:01")
        #expect(LMFormat.clock(3725) == "1:02:05")
        #expect(LMFormat.clock(-5) == "00:00")
    }

    @Test func seededRandomIsStable() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        #expect((0..<10).map { _ in a.next() } == (0..<10).map { _ in b.next() })
        #expect(StableHash.fnv1a("lumora") == StableHash.fnv1a("lumora"))
    }

    @Test func motionPreferenceResolution() {
        #expect(MotionPreference.system.resolve(systemReduceMotion: true, lowPower: false) == .reduced)
        #expect(MotionPreference.reduced.resolve(systemReduceMotion: false, lowPower: false) == .reduced)
        #expect(MotionPreference.simplified.resolve(systemReduceMotion: false, lowPower: false) == .simplified)
        #expect(MotionPreference.system.resolve(systemReduceMotion: false, lowPower: true) == .simplified)
    }

    @Test func celebrationPlansMatchSpec() {
        let base = SessionReward(sessionID: UUID(), outcome: .completed, category: .coding, intention: "", focusedMinutes: 25,
                                 plannedMinutes: 25, endedAt: .now, star: nil, newObjects: [], newAchievements: [],
                                 todayMinutesBefore: 0, todayMinutes: 25, goalMinutes: 120, todayStars: [],
                                 totalQualifyingSessions: 1, starsPerConstellation: 4)
        let standard = CelebrationPlan.make(for: base, motion: .full)
        #expect(standard.duration == 5.6)
        #expect(standard.skippableAfter == 1.5)
        #expect(CelebrationPlan.make(for: base, motion: .reduced).duration == 1.2)
        var early = base
        early.outcome = .endedEarly
        #expect(CelebrationPlan.make(for: early, motion: .full).scale == 0.6)
    }
}
