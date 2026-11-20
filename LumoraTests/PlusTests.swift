import Foundation
import Testing
@testable import Lumora

/// Orbi+ reads one shared flag, so these run one at a time and put it back.
@Suite("Orbi+", .serialized)
@MainActor
struct PlusTests {
    let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)

    private func withPlus(_ active: Bool, _ body: () throws -> Void) rethrows {
        let before = PlusAccess.defaults.object(forKey: PlusAccess.key)
        PlusAccess.defaults.set(active, forKey: PlusAccess.key)
        defer { PlusAccess.defaults.set(before, forKey: PlusAccess.key) }
        try body()
    }

    @Test func lockedSoundsFallBackToTheDeepSpaceHum() {
        withPlus(false) {
            #expect(AmbientSound.rain.playable == .deepSpace)
            #expect(AmbientSound.campfire.playable == .deepSpace)
            #expect(AmbientSound.brownNoise.playable == .brownNoise)
            #expect(AmbientSound.silence.playable == .silence)
        }
        withPlus(true) {
            #expect(AmbientSound.solarWind.playable == .solarWind)
        }
        #expect(AmbientSound.allCases.filter { !$0.isPlus } == [.silence, .deepSpace, .brownNoise])
    }

    @Test func skyThemesNeedPlus() {
        #expect(SkyTheme.current(raw: "ember", plusActive: true) == .ember)
        #expect(SkyTheme.current(raw: "ember", plusActive: false) == .classic)
        #expect(SkyTheme.current(raw: "nonsense", plusActive: true) == .classic)
        #expect(!SkyTheme.classic.isPlus)
    }

    @Test func plusFinishesRestWithoutPlusButStayOwned() throws {
        let context = try TestFixtures.makeContext()
        let rewards = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        let odyssey = OdysseyService(context: context, clock: clock)
        rewards.didCommit = { [weak odyssey] reward in odyssey?.sync(after: reward.sessionID) }
        var sessions = 0
        while odyssey.snapshot.balance < odyssey.rules.price(of: .paint(.eclipse)), sessions < 40 {
            _ = try rewards.record(TestFixtures.result(start: clock.now, minutes: 60))
            clock.advance(by: 3 * 3600)
            sessions += 1
        }
        try withPlus(false) {
            #expect(throws: OdysseyError.plusRequired) { try odyssey.buy(.paint(.eclipse)) }
        }
        try withPlus(true) {
            try odyssey.buy(.paint(.eclipse))
            odyssey.refreshPlus()
            #expect(odyssey.snapshot.loadout.paint == .eclipse)
        }
        withPlus(false) {
            odyssey.refreshPlus()
            #expect(odyssey.snapshot.loadout.paint == .pearl)
            #expect(odyssey.snapshot.ownedParts.contains(.paint(.eclipse)))
        }
        #expect(ShipLoadout(hull: .ark, paint: .opal, trail: .supernova).withoutPlus == ShipLoadout(hull: .ark, paint: .pearl, trail: .ion))
    }

    @Test func plusLinkOpensThePaywall() {
        #expect(DeepLink(url: URL(string: "lumora://plus")!) == .plus)
        #expect(DeepLink(url: URL(string: "https://www.mobapptech.com/lumora/plus/")!) == .plus)
        #expect(DeepLink.plus.appURL.absoluteString == "lumora://plus")
    }

    @Test func earlierWeeksAndMonths() {
        let calendar = clock.calendar
        let now = clock.now
        let today = DayKey(now, calendar: calendar)
        let lastWeek = TestFixtures.result(start: now.addingTimeInterval(-8 * 86_400), minutes: 30)
        let facts = [SessionFacts(id: lastWeek.segmentID, startedAt: lastWeek.startedAt, endedAt: lastWeek.endedAt,
                                  dayKey: DayKey(lastWeek.startedAt, calendar: calendar), focusedSeconds: 30 * 60,
                                  plannedSeconds: 30 * 60, pauseCount: 0, category: .coding, outcome: .completed, intention: "")]
        let current = InsightsModel.make(facts: facts, period: .week, today: today, calendar: calendar, now: now)
        #expect(current.totalMinutes == 0)
        #expect(current.hasEarlier)
        let previous = InsightsModel.make(facts: facts, period: .week, today: today, calendar: calendar, now: now, offset: 1)
        #expect(previous.totalMinutes == 30)
        #expect(previous.bars.last?.day == today.adding(days: -7, calendar: calendar))
        #expect(!previous.hasEarlier)

        let monthBack = InsightsModel.make(facts: facts, period: .month, today: today, calendar: calendar, now: now, offset: 1)
        let shown = calendar.component(.month, from: monthBack.rangeStart)
        #expect(shown == calendar.component(.month, from: calendar.date(byAdding: .month, value: -1, to: now)!))
    }

    @Test func csvQuotesWhatNeedsIt() {
        let start = clock.now
        let fact = SessionFacts(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(1500), dayKey: DayKey(start, calendar: clock.calendar),
                                focusedSeconds: 1500, plannedSeconds: 1500, pauseCount: 1, category: .reading,
                                outcome: .completed, intention: "Read \"Dune\", chapter 2")
        let lines = InsightsModel.csv(facts: [fact]).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("day,started,ended,focused_minutes"))
        #expect(lines[1].hasSuffix(",25,25,1,reading,completed,yes,\"Read \"\"Dune\"\", chapter 2\""))
    }
}
