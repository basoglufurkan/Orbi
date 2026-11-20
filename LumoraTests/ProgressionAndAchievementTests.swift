import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Universe progression is deterministic")
@MainActor
struct ProgressionDeterminismTests {
    func history(count: Int) -> [SessionFacts] {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TestFixtures.istanbul
        return (0..<count).map { i in
            let start = TestFixtures.baseDate.addingTimeInterval(Double(i / 3) * 86_400 + Double(i % 3) * 3600)
            let end = start.addingTimeInterval(1500)
            return SessionFacts(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!,
                                startedAt: start, endedAt: end, dayKey: DayKey(end, calendar: c),
                                focusedSeconds: 1500, plannedSeconds: 1500, pauseCount: 0,
                                category: FocusCategory.allCases[i % 5], outcome: .completed, intention: "")
        }
    }

    @Test func replayingTheSameHistoryProducesTheSameUniverse() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TestFixtures.istanbul
        let engine = ProgressionEngine(calendar: c)
        let seed = CelestialSnapshot(draft: ProgressionEngine.seedStarDraft(createdAt: TestFixtures.baseDate, calendar: c))
        let a = engine.replay(history: history(count: 70), seedStar: seed)
        let b = engine.replay(history: history(count: 70), seedStar: seed)
        #expect(a == b)
        #expect(a.filter { $0.kind == .star }.count == 70)
        #expect(a.filter { $0.kind == .planet }.map(\.name) == ["Velora", "Ostra"])
    }

    @Test func storedUniverseMatchesReplay() throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)
        let context = try TestFixtures.makeContext()
        let store = DataStore(container: context.container)
        store.ensureUniverse(createdAt: TestFixtures.baseDate, calendar: clock.calendar)
        let service = RewardService(context: store.context, clock: clock, goalMinutes: { 120 })
        let facts = history(count: 24)
        for f in facts {
            let result = FocusResult(segmentID: f.id, configuration: FocusConfiguration(plannedSeconds: 1500, category: f.category, intention: ""),
                                     startedAt: f.startedAt, endedAt: f.endedAt, plannedSeconds: 1500, focusedSeconds: 1500,
                                     pausedSeconds: 0, pauseCount: 0, endReason: .completed)
            _ = try service.record(result)
        }
        let stored = try store.context.fetch(FetchDescriptor<CelestialObject>()).filter { $0.kind != .seed }
        let seed = CelestialSnapshot(draft: ProgressionEngine.seedStarDraft(createdAt: TestFixtures.baseDate, calendar: clock.calendar))
        let replayed = ProgressionEngine(calendar: clock.calendar).replay(history: facts, seedStar: seed)
        let storedByKey = Dictionary(uniqueKeysWithValues: stored.map { ($0.rewardKey, $0.position) })
        #expect(storedByKey.count == replayed.count)
        for draft in replayed {
            #expect(storedByKey[draft.rewardKey] == draft.position)
        }
    }

    @Test func starsDoNotOverlap() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TestFixtures.istanbul
        let seed = CelestialSnapshot(draft: ProgressionEngine.seedStarDraft(createdAt: TestFixtures.baseDate, calendar: c))
        let stars = ProgressionEngine(calendar: c).replay(history: history(count: 150), seedStar: seed).filter { $0.kind == .star }
        for i in stars.indices {
            for j in stars.indices where j > i {
                #expect(stars[i].position.distance(to: stars[j].position) >= 20,
                        "Stars \(stars[i].ordinal) and \(stars[j].ordinal) overlap")
            }
        }
    }

    @Test func longerSessionsMakeBiggerStarsButNeverExtraStars() {
        let rules = RewardRules.standard
        #expect(rules.starScale(focusedSeconds: 60 * 60, outcome: .completed) > rules.starScale(focusedSeconds: 15 * 60, outcome: .completed))
        #expect(rules.starScale(focusedSeconds: 15 * 60, outcome: .completed) > 0.7)
    }

    @Test func rewardRulesAreConfigurable() {
        var rules = RewardRules.standard
        rules.starsPerConstellation = 3
        rules.planetMilestones = [2]
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TestFixtures.istanbul
        let seed = CelestialSnapshot(draft: ProgressionEngine.seedStarDraft(createdAt: TestFixtures.baseDate, calendar: c))
        let drafts = ProgressionEngine(rules: rules, calendar: c).replay(history: history(count: 3), seedStar: seed)
        #expect(drafts.contains { $0.kind == .planet })
        #expect(drafts.filter { $0.kind == .constellation }.first?.linkedOrdinals == [1, 2, 3])
    }
}

@Suite("Achievements")
struct AchievementTests {
    @Test func catalogHasEighteenUniqueArtifacts() {
        #expect(AchievementCatalog.all.count == 18)
        #expect(Set(AchievementCatalog.all.map(\.id)).count == 18)
        #expect(Set(AchievementCatalog.all.map(\.number)).count == 18)
    }

    @Test func unlocksDeriveFromStats() {
        var stats = ProgressStats()
        stats.qualifyingSessions = 10
        stats.totalFocusSeconds = 3600 * 2
        let ids = Set(AchievementEngine.newlyUnlocked(stats: stats, alreadyUnlocked: []).map(\.id))
        #expect(ids.isSuperset(of: ["sessions.1", "sessions.10", "hours.1"]))
        #expect(!ids.contains("sessions.25"))
    }

    @Test func nothingUnlocksTwice() {
        var stats = ProgressStats()
        stats.qualifyingSessions = 1
        let first = AchievementEngine.newlyUnlocked(stats: stats, alreadyUnlocked: [])
        let second = AchievementEngine.newlyUnlocked(stats: stats, alreadyUnlocked: Set(first.map(\.id)))
        #expect(!first.isEmpty)
        #expect(second.isEmpty)
    }

    @Test func personalBestsAndGoalsAreVerified() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let day = DayKey(rawValue: "2026-10-20")
        let start = day.startDate(calendar: c)!.addingTimeInterval(9 * 3600)
        let sessions = (0..<4).map { i in
            SessionFacts(id: UUID(), startedAt: start + Double(i) * 3700, endedAt: start + Double(i) * 3700 + 3600, dayKey: day,
                         focusedSeconds: 3600, plannedSeconds: 3600, pauseCount: 0, category: .work, outcome: .completed, intention: "")
        }
        let stats = ProgressStats.compute(sessions: sessions, goalMinutes: 120, today: day, calendar: c)
        #expect(stats.goalDays == 1)
        #expect(stats.bestDaySeconds == 4 * 3600)
        #expect(stats.longestCompletedSeconds == 3600)
        let ids = Set(AchievementEngine.newlyUnlocked(stats: stats, alreadyUnlocked: []).map(\.id))
        #expect(ids.isSuperset(of: ["goal.1", "bestday.180", "length.60", "day.4"]))
    }

    @Test func progressTowardLockedArtifacts() {
        var stats = ProgressStats()
        stats.qualifyingSessions = 5
        #expect(AchievementRequirement.sessions(10).progress(in: stats) == 0.5)
    }
}
