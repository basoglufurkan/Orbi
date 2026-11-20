import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("iCloud sync")
@MainActor
struct CloudSyncTests {
    private let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)

    private func makeStore() throws -> (Lumora.DataStore, RewardService) {
        let context = try TestFixtures.makeContext()
        let store = Lumora.DataStore(container: context.container)
        let rewards = RewardService(context: store.context, clock: clock, goalMinutes: { 120 })
        return (store, rewards)
    }

    private func positions(_ store: Lumora.DataStore) throws -> [String: WorldPoint] {
        Dictionary(uniqueKeysWithValues: try store.context.fetch(FetchDescriptor<CelestialObject>()).map { ($0.rewardKey, $0.position) })
    }

    @Test func aNewDeviceDrawsTheSameSkyFromHistory() throws {
        let (store, rewards) = try makeStore()
        store.ensureUniverse(createdAt: TestFixtures.baseDate, calendar: clock.calendar)
        for day in 0..<6 {
            for slot in 0..<3 {
                let start = TestFixtures.baseDate.addingTimeInterval(TimeInterval(day * 86_400 + slot * 3_600))
                _ = try rewards.record(TestFixtures.result(start: start, category: slot == 1 ? .reading : .coding))
            }
        }
        #expect(!rewards.rebuildUniverseIfNeeded(createdAt: TestFixtures.baseDate))   // already drawn
        let original = try positions(store)
        let stars = try store.context.fetch(FetchDescriptor<FocusSession>()).map(\.starNumber).sorted()

        // The sky lives in the device store; a new device has none of it.
        for object in try store.context.fetch(FetchDescriptor<CelestialObject>()) { store.context.delete(object) }
        for progress in try store.context.fetch(FetchDescriptor<UniverseProgress>()) { store.context.delete(progress) }
        try store.context.save()

        let universe = store.ensureUniverse(createdAt: clock.now.addingTimeInterval(30 * 86_400), calendar: clock.calendar)
        #expect(universe.createdAt == TestFixtures.baseDate)   // day 1 came with the history
        #expect(rewards.rebuildUniverseIfNeeded(createdAt: universe.createdAt))
        #expect(try positions(store) == original)
        #expect(try store.context.fetch(FetchDescriptor<FocusSession>()).map(\.starNumber).sorted() == stars)
        #expect(store.progress()?.starCount == 18)
    }

    @Test func dayOneFallsBackToTheFirstSession() throws {
        let (store, _) = try makeStore()
        let first = TestFixtures.baseDate.addingTimeInterval(-3 * 86_400)
        store.context.insert(FocusSession(id: UUID(), startedAt: first, endedAt: first.addingTimeInterval(1_500),
                                          plannedSeconds: 1_500, focusedSeconds: 1_500, pausedSeconds: 0, pauseCount: 0,
                                          category: .work, intention: "", outcome: .completed,
                                          dayKey: DayKey(first, calendar: clock.calendar), timeZoneID: "Europe/Istanbul"))
        #expect(store.universeCreatedAt(fallback: TestFixtures.baseDate) == first)
        #expect(store.preferences().universeCreatedAt == first)
    }

    @Test func rowsBroughtByTwoDevicesFoldIntoOne() throws {
        let (store, _) = try makeStore()
        let context = store.context
        let early = TestFixtures.baseDate.addingTimeInterval(-86_400)

        let here = UserPreferences()
        here.universeCreatedAt = TestFixtures.baseDate
        let there = UserPreferences()
        there.displayName = "Furkan"
        there.hasCompletedOnboarding = true
        there.universeCreatedAt = early
        context.insert(here)
        context.insert(there)

        let a = OdysseyProfile(createdAt: early)
        a.ownedPartKeys = ["hull.comet"]
        let b = OdysseyProfile(createdAt: early)
        b.ownedPartKeys = ["paint.ember", "hull.comet"]
        context.insert(a)
        context.insert(b)

        for _ in 0..<2 {
            context.insert(OdysseyLedgerEntry(key: "expedition-1", date: early, amount: -40, kind: .expedition, note: ""))
            context.insert(AchievementUnlock(achievementID: "first-star", unlockedAt: early, sourceSessionID: nil))
        }
        context.insert(HorizonGoal(kind: .sessions, target: 5, startedAt: early, endsAt: nil))
        let newer = HorizonGoal(kind: .sessions, target: 8, startedAt: TestFixtures.baseDate, endsAt: nil)
        context.insert(newer)
        try context.save()

        #expect(store.mergeDuplicates())
        let prefs = try context.fetch(FetchDescriptor<UserPreferences>())
        #expect(prefs.count == 1)
        #expect(prefs.first?.displayName == "Furkan")
        #expect(prefs.first?.universeCreatedAt == early)
        #expect(store.preferences() === prefs.first)

        let profiles = try context.fetch(FetchDescriptor<OdysseyProfile>())
        #expect(profiles.count == 1)
        #expect(Set(profiles.first?.ownedPartKeys ?? []) == ["hull.comet", "paint.ember"])
        #expect(try context.fetch(FetchDescriptor<OdysseyLedgerEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AchievementUnlock>()).count == 1)
        let active = try context.fetch(FetchDescriptor<HorizonGoal>()).filter { $0.status == .active }
        #expect(active.count == 1 && active.first === newer)

        #expect(!store.mergeDuplicates())   // nothing left to fold
    }
}
