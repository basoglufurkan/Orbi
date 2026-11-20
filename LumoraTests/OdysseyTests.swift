import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Odyssey: generation and pacing")
struct OdysseyGenerationTests {
    @Test func worldsAreDeterministic() {
        for ordinal in [1, 2, 9, 13, 57, 200] {
            #expect(WorldGenerator.blueprint(ordinal: ordinal) == WorldGenerator.blueprint(ordinal: ordinal))
        }
        #expect(WorldGenerator.blueprint(ordinal: 3).name != WorldGenerator.blueprint(ordinal: 4).name)
    }

    @Test func firstDeckShowsEveryCommonClassOnce() {
        let commons = (1...13).filter { $0 % 9 != 0 }.map { WorldGenerator.blueprint(ordinal: $0).archetype }
        #expect(Set(commons).count == 12)
        #expect(commons.first == .verdant)
    }

    @Test func everyNinthWorldIsLegendary() {
        #expect(WorldGenerator.blueprint(ordinal: 9).archetype == .ringworld)
        #expect(WorldGenerator.blueprint(ordinal: 18).archetype == .dysonPearl)
        #expect(WorldGenerator.blueprint(ordinal: 27).archetype == .livingEye)
        #expect(WorldGenerator.blueprint(ordinal: 9).rarity == .legendary)
        #expect((1...8).allSatisfy { WorldGenerator.blueprint(ordinal: $0).rarity != .legendary })
    }

    @Test func findsDoNotRepeatEarly() {
        let finds = (1...min(40, WorldLexicon.findCount)).map(WorldGenerator.findIndex(ordinal:))
        #expect(Set(finds).count == finds.count)
    }

    @Test func emergenceAlwaysHasSomethingAhead() {
        let rules = OdysseyRules.standard
        #expect(rules.emergenceThreshold(ordinal: 1) == 50)
        var previousGap = 0
        for k in 2...30 {
            let gap = rules.emergenceThreshold(ordinal: k) - rules.emergenceThreshold(ordinal: k - 1)
            #expect(gap >= previousGap)
            #expect(gap <= 60 + 15 * 10)
            previousGap = gap
        }
        #expect(rules.worldsEmerged(totalMinutes: 49) == 0)
        #expect(rules.worldsEmerged(totalMinutes: 50) == 1)
        #expect(rules.worldsEmerged(totalMinutes: rules.emergenceThreshold(ordinal: 7)) == 7)
    }

    @Test func galaxiesFillThenIgnite() {
        let rules = OdysseyRules.standard
        #expect(rules.placement(ofWorld: 1) == (0, 0))
        #expect(rules.placement(ofWorld: 6) == (0, 5))
        #expect(rules.placement(ofWorld: 7) == (1, 0))
        #expect(rules.placement(ofWorld: 15) == (2, 0))
        #expect(rules.galaxiesIgnited(worlds: 0) == 1)
        #expect(rules.galaxiesIgnited(worlds: 7) == 2)
    }

    @Test func ranksClimbWithExperience() {
        #expect(NavigatorRank.rank(forXP: 0).level == 1)
        #expect(NavigatorRank.rank(forXP: 499).level == 2)
        #expect(NavigatorRank.rank(forXP: 500).level == 3)
        #expect(NavigatorRank.rank(forXP: 1_000_000).next == nil)
    }

    @Test func shipPartKeysRoundTrip() {
        for part in ShipPart.all { #expect(ShipPart(key: part.key) == part) }
        #expect(ShipPart(key: "hull.nope") == nil)
    }

    @Test func galaxiesAreDeterministicAndNamed() {
        #expect(GalaxyCatalog.blueprint(3) == GalaxyCatalog.blueprint(3))
        #expect(GalaxyCatalog.blueprint(0).mapPosition == .zero)
        #expect(!GalaxyCatalog.blueprint(42).name.isEmpty)
    }
}

@Suite("Odyssey: journeys, stardust and goals")
@MainActor
struct OdysseyServiceTests {
    let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)

    struct World {
        let context: ModelContext
        let rewards: RewardService
        let odyssey: OdysseyService
    }

    func makeWorld() throws -> World {
        let context = try TestFixtures.makeContext()
        let rewards = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        let odyssey = OdysseyService(context: context, clock: clock)
        rewards.didCommit = { [weak odyssey] reward in odyssey?.sync(after: reward.sessionID) }
        return World(context: context, rewards: rewards, odyssey: odyssey)
    }

    /// Records a completed session of `minutes`, ending now, then advances time.
    @discardableResult
    func focus(_ w: World, minutes: Int = 25, reason: FocusEndReason = .completed, focused: Int? = nil) throws -> SessionReward {
        let start = clock.now
        let reward = try w.rewards.record(TestFixtures.result(start: start, minutes: minutes, focusedMinutes: focused, reason: reason))
        clock.advance(by: 3600)
        return reward
    }

    @Test func stardustIsDerivedFromFocus() throws {
        let w = try makeWorld()
        try focus(w, minutes: 25)
        try focus(w, minutes: 25, reason: .endedByUser, focused: 12)
        try focus(w, minutes: 25, reason: .endedByUser, focused: 2)   // too short: no stardust
        #expect(w.odyssey.snapshot.stardustEarned == 30 + 12)
        #expect(w.odyssey.snapshot.balance == 42)
    }

    @Test func worldsEmergeOnScheduleAndExactlyOnce() throws {
        let w = try makeWorld()
        let first = try focus(w)          // 25
        #expect(w.odyssey.snapshot.worlds.isEmpty)
        let second = try focus(w)         // 50 → world 1
        let snap = w.odyssey.snapshot
        #expect(snap.worlds.map(\.ordinal) == [1])
        #expect(w.odyssey.summary(for: second.sessionID).emerged.map(\.ordinal) == [1])
        #expect(w.odyssey.summary(for: first.sessionID).emerged.isEmpty)
        w.odyssey.sync()
        w.odyssey.sync()
        #expect(try w.context.fetchCount(FetchDescriptor<OdysseyWorld>()) == 1)
    }

    @Test func firstJourneyIsFreeAndArrivesThroughFocus() throws {
        let w = try makeWorld()
        try focus(w); try focus(w)
        try w.odyssey.plotCourse(to: 1)
        #expect(w.odyssey.snapshot.balance == 60)            // free
        #expect(w.odyssey.snapshot.expedition?.requiredMinutes == 25)
        #expect(throws: OdysseyError.expeditionUnderway) { try w.odyssey.plotCourse(to: 1) }
        let landing = try focus(w)
        let summary = w.odyssey.summary(for: landing.sessionID)
        #expect(summary.arrival?.world.ordinal == 1)
        let snap = w.odyssey.snapshot
        #expect(snap.expedition == nil)
        #expect(snap.pendingArrival?.world.ordinal == 1)
        #expect(snap.worlds.first?.status == .charted)
        w.odyssey.markArrivalSeen(try #require(snap.pendingArrival).id)
        #expect(w.odyssey.snapshot.pendingArrival == nil)
    }

    @Test func journeyProgressCountsOnlyFocusAfterDeparture() throws {
        let w = try makeWorld()
        for _ in 0..<6 { try focus(w) }  // 150 min → world 1 and 2
        #expect(w.odyssey.snapshot.worlds.count == 2)
        try w.odyssey.plotCourse(to: 2)
        let e = try #require(w.odyssey.snapshot.expedition)
        #expect(e.progressMinutes == 0)
        try focus(w, minutes: 15)
        #expect(w.odyssey.snapshot.expedition?.progressMinutes == min(15, e.requiredMinutes))
    }

    @Test func recallRefundsFuelInFull() throws {
        let w = try makeWorld()
        for _ in 0..<6 { try focus(w) }
        let before = w.odyssey.snapshot.balance
        try w.odyssey.plotCourse(to: 2)
        let cost = try #require(w.odyssey.snapshot.expedition).cost
        #expect(cost > 0)
        #expect(w.odyssey.snapshot.balance == before - cost)
        w.odyssey.recallExpedition()
        #expect(w.odyssey.snapshot.balance == before)
        #expect(w.odyssey.snapshot.worlds.first { $0.ordinal == 2 }?.status == .uncharted)
    }

    @Test func terraformingCostsStardustAndCannotOverspend() throws {
        let w = try makeWorld()
        try focus(w); try focus(w)
        try w.odyssey.plotCourse(to: 1)
        try focus(w)                                 // arrive; balance 90
        #expect(try w.odyssey.cultivate(1) == .breath)  // −40
        #expect(w.odyssey.snapshot.balance == 50)
        #expect(throws: OdysseyError.insufficientStardust(needed: 30)) { try w.odyssey.cultivate(1) }
        #expect(w.odyssey.snapshot.worlds.first?.stage == .breath)
    }

    @Test func cannotTerraformUnvisitedWorlds() throws {
        let w = try makeWorld()
        try focus(w); try focus(w)
        #expect(throws: OdysseyError.worldUnavailable) { try w.odyssey.cultivate(1) }
    }

    @Test func hangarChargesOnceAndRespectsRank() throws {
        let w = try makeWorld()
        for _ in 0..<5 { try focus(w, minutes: 25) }     // 150 stardust
        try w.odyssey.buy(.paint(.nebula))               // 90
        #expect(w.odyssey.snapshot.balance == 60)
        try w.odyssey.buy(.paint(.nebula))               // already owned: no charge
        #expect(w.odyssey.snapshot.balance == 60)
        #expect(w.odyssey.snapshot.loadout.paint == .nebula)
        #expect(throws: OdysseyError.rankTooLow(required: 5)) { try w.odyssey.buy(.hull(.manta)) }
    }

    @Test func horizonRewardsOnceWhenReached() throws {
        let w = try makeWorld()
        w.odyssey.startHorizon(kind: .sessions, target: 2)
        try focus(w)
        #expect(w.odyssey.snapshot.horizon?.progressUnits == 1)
        let reaching = try focus(w)
        let reward = HorizonKind.sessions.rewardStardust(target: 2)
        #expect(w.odyssey.summary(for: reaching.sessionID).horizon?.reward == reward)
        #expect(w.odyssey.snapshot.horizon == nil)
        #expect(w.odyssey.snapshot.balance == 60 + reward)
        w.odyssey.sync()
        #expect(w.odyssey.snapshot.balance == 60 + reward)
    }

    @Test func weeklyHorizonRestsWithoutPenalty() throws {
        let w = try makeWorld()
        w.odyssey.startHorizon(kind: .weeklyHours, target: 20)
        try focus(w)
        clock.advance(by: 8 * 86_400)
        w.odyssey.sync()
        let snap = w.odyssey.snapshot
        #expect(snap.horizon == nil)
        #expect(snap.balance == 30)
    }

    @Test func nextWorldTeaserCountsDown() throws {
        let w = try makeWorld()
        try focus(w, minutes: 30)
        let teaser = try #require(w.odyssey.snapshot.nextEmergence)
        #expect(teaser.blueprint.ordinal == 1)
        #expect(teaser.minutesRemaining == 20)
        #expect(teaser.fraction > 0.5)
    }

    @Test func rankUpIsReportedUntilCelebrated() throws {
        let w = try makeWorld()
        for _ in 0..<7 { try focus(w) }   // 175 XP+ → Pathfinder
        let last = try focus(w)
        #expect(w.odyssey.summary(for: last.sessionID).rankUp?.level == 2)
        w.odyssey.markRankCelebrated()
        #expect(w.odyssey.summary(for: last.sessionID).rankUp == nil)
    }

    // MARK: Rare events

    @Test func oneEventEachWeekWhicheverDayYouAsk() {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = clock.calendar.timeZone
        var kinds = Set<CosmicEventKind>()
        for week in 0..<20 {
            let start = iso.dateInterval(of: .weekOfYear, for: TestFixtures.baseDate.addingTimeInterval(Double(week) * 7 * 86_400))!.start
            let event = CosmicCalendar.event(inWeekOf: start, calendar: clock.calendar)
            #expect(event.date >= start && event.date < start.addingTimeInterval(7 * 86_400))
            for day in 0..<7 {
                #expect(CosmicCalendar.event(inWeekOf: start.addingTimeInterval(Double(day) * 86_400 + 43_200),
                                             calendar: clock.calendar) == event)
            }
            kinds.insert(event.kind)
        }
        #expect(kinds.count >= 4)
    }

    @Test func everyKindOfEventComesRound() {
        // Over two years of weeks, each of the rare events turns up.
        let kinds = Set((0..<104).map { week in
            CosmicCalendar.event(inWeekOf: TestFixtures.baseDate.addingTimeInterval(Double(week) * 7 * 86_400),
                                 calendar: clock.calendar).kind
        })
        #expect(kinds == Set(CosmicEventKind.allCases))
    }

    @Test func theFirstSessionOnTheDayWitnessesTheEventOnce() throws {
        let w = try makeWorld()
        _ = w.odyssey.snapshot   // the Odyssey begins now
        let event = CosmicCalendar.upcoming(from: clock.now, calendar: clock.calendar)
        clock.set(event.date.addingTimeInterval(9 * 3600))
        let first = try focus(w)
        let second = try focus(w)
        #expect(w.odyssey.summary(for: first.sessionID).event == event)
        #expect(w.odyssey.summary(for: second.sessionID).event == nil)
        w.odyssey.sync()
        let snap = w.odyssey.snapshot
        #expect(snap.witnessedEvents.map(\.kind) == [event.kind])
        #expect(snap.balance == 60 + OdysseyRules.standard.eventReward)
    }

    @Test func eventsBeforeTheOdysseyBeganDoNotCount() throws {
        let w = try makeWorld()
        let lastWeek = CosmicCalendar.event(inWeekOf: clock.now.addingTimeInterval(-7 * 86_400), calendar: clock.calendar)
        _ = w.odyssey.snapshot   // the Odyssey begins today
        _ = try w.rewards.record(TestFixtures.result(start: lastWeek.date.addingTimeInterval(10 * 3600)))
        #expect(w.odyssey.snapshot.witnessedEvents.isEmpty)
    }

    // MARK: Horizon chains

    @Test func horizonChainsEarnTrailsThatStayEarned() throws {
        let w = try makeWorld()
        var last: SessionReward?
        for _ in 0..<2 {
            w.odyssey.startHorizon(kind: .sessions, target: 1)
            last = try focus(w)
        }
        var snap = w.odyssey.snapshot
        #expect(snap.horizonChain == 2)
        #expect(snap.ownedParts.contains(.trail(.dawnline)))
        #expect(w.odyssey.summary(for: try #require(last).sessionID).chainTrail == .dawnline)
        #expect(throws: OdysseyError.chainRequired(4)) { try w.odyssey.buy(.trail(.starlit)) }

        // A weekly horizon that rests unfinished breaks the chain, not the trail.
        w.odyssey.startHorizon(kind: .weeklyHours, target: 20)
        clock.advance(by: 8 * 86_400)
        w.odyssey.sync()
        snap = w.odyssey.snapshot
        #expect(snap.horizonChain == 0)
        #expect(snap.bestHorizonChain == 2)
        #expect(snap.ownedParts.contains(.trail(.dawnline)))
        w.odyssey.equip(.trail(.dawnline))
        #expect(w.odyssey.snapshot.loadout.trail == .dawnline)
    }

    @Test func eraseAllRemovesTheOdyssey() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let store = DataStore(container: container)
        let rewards = RewardService(context: store.context, clock: clock, goalMinutes: { 120 })
        let odyssey = OdysseyService(context: store.context, clock: clock)
        rewards.didCommit = { [weak odyssey] r in odyssey?.sync(after: r.sessionID) }
        for _ in 0..<3 { _ = try rewards.record(TestFixtures.result(start: clock.now)); clock.advance(by: 3600) }
        try odyssey.plotCourse(to: 1)
        try store.eraseAll()
        #expect(try store.context.fetchCount(FetchDescriptor<OdysseyWorld>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<Expedition>()) == 0)
    }
}
