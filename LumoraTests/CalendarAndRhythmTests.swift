import Foundation
import Testing
@testable import Lumora

@Suite("Calendar boundaries")
struct CalendarBoundaryTests {
    func calendar(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    @Test func dayKeyDependsOnTimeZone() {
        // 2026-10-20 23:30 UTC is already the 21st in Istanbul (UTC+3).
        let date = ISO8601DateFormatter().date(from: "2026-10-20T23:30:00Z")!
        #expect(DayKey(date, calendar: calendar("UTC")).rawValue == "2026-10-20")
        #expect(DayKey(date, calendar: calendar("Europe/Istanbul")).rawValue == "2026-10-21")
    }

    @Test(arguments: [Calendar.Identifier.islamicUmmAlQura, .buddhist, .japanese, .persian, .hebrew])
    func dayKeyIsGregorianWhateverTheUserCalendar(_ identifier: Calendar.Identifier) {
        var c = Calendar(identifier: identifier)
        c.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let date = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        let key = DayKey(date, calendar: c)
        #expect(key.rawValue == "2026-10-20")
        #expect(key.adding(days: 12, calendar: c).rawValue == "2026-11-01")
        #expect(key.startDate(calendar: c).map { DayKey($0, calendar: c) } == key)
    }

    @Test func dayKeyArithmeticCrossesMonthAndYear() {
        let c = calendar("UTC")
        #expect(DayKey(rawValue: "2026-10-31").adding(days: 1, calendar: c).rawValue == "2026-11-01")
        #expect(DayKey(rawValue: "2026-12-31").adding(days: 1, calendar: c).rawValue == "2027-01-01")
        #expect(DayKey(rawValue: "2028-03-01").adding(days: -1, calendar: c).rawValue == "2028-02-29")
    }

    @Test @MainActor func sessionSpanningMidnightBelongsToTheDayItEnds() throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)
        let context = try TestFixtures.makeContext()
        let service = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TestFixtures.istanbul
        let start = c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 50))!
        let reward = try service.record(TestFixtures.result(start: start, minutes: 25))
        #expect(reward.star?.dayKey.rawValue == "2026-10-21")
    }

    @Test @MainActor func storedDayDoesNotShiftAfterTimeZoneChange() throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)
        let context = try TestFixtures.makeContext()
        let service = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate))
        clock.setTimeZone(TimeZone(identifier: "America/Los_Angeles")!)
        let session = try #require(try context.fetch(FetchDescriptorFactory.sessions()).first)
        #expect(session.dayKeyRaw == "2026-10-20")
        #expect(session.timeZoneID == "Europe/Istanbul")
    }

    @Test func widgetSnapshotResetsAtMidnight() {
        let c = calendar("UTC")
        var snapshot = WidgetSnapshot.placeholder
        snapshot.dayKey = "2026-10-20"
        snapshot.todayMinutes = 70
        let sameDay = c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 59))!
        let nextDay = c.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 0, minute: 1))!
        #expect(snapshot.minutesToday(now: sameDay, calendar: c) == 70)
        #expect(snapshot.minutesToday(now: nextDay, calendar: c) == 0)
    }
}

@Suite("Rhythm (streaks with a weekly rest day)")
struct RhythmTests {
    let c: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let today = DayKey(rawValue: "2026-10-20")

    func days(_ offsets: [Int]) -> Set<DayKey> {
        Set(offsets.map { today.adding(days: -$0, calendar: c) })
    }

    @Test func consecutiveDaysCount() {
        let s = RhythmCalculator.status(focusDays: days([0, 1, 2, 3]), today: today, calendar: c)
        #expect(s.days == 4)
        #expect(!s.pendingToday)
    }

    @Test func todayPendingDoesNotBreakTheRhythm() {
        let s = RhythmCalculator.status(focusDays: days([1, 2, 3]), today: today, calendar: c)
        #expect(s.days == 3)
        #expect(s.pendingToday)
        #expect(!s.isPaused)
    }

    @Test func oneRestDayPerWeekIsFree() {
        // Focus on days 0,1,2, rest on 3, focus 4,5.
        let s = RhythmCalculator.status(focusDays: days([0, 1, 2, 4, 5]), today: today, calendar: c)
        #expect(s.days == 6)
    }

    @Test func twoConsecutiveMissesPauseTheRhythm() {
        let s = RhythmCalculator.status(focusDays: days([0, 3, 4, 5]), today: today, calendar: c)
        #expect(s.days == 1)
    }

    @Test func secondMissWithinAWeekPausesTheRhythm() {
        // Misses on days 5 and 2 (3 days apart): day 5 uses the free rest day,
        // day 2 pauses the rhythm, so it restarts and counts only days 1 and 0.
        let s = RhythmCalculator.status(focusDays: days([0, 1, 3, 4, 6, 7]), today: today, calendar: c)
        #expect(s.days == 2)
        #expect(RhythmCalculator.longest(focusDays: days([0, 1, 3, 4, 6, 7]), calendar: c) == 5) // days 7…3, day 5 resting
    }

    @Test func restDaysAWeekApartAreBothForgiven() {
        // Misses on days 2 and 9: seven days apart.
        let focus = days(Array(0...12).filter { $0 != 2 && $0 != 9 })
        #expect(RhythmCalculator.status(focusDays: focus, today: today, calendar: c).days == 13)
    }

    @Test func lapsedRhythmIsReportedAsPausedNotBroken() {
        let s = RhythmCalculator.status(focusDays: days([5, 6, 7]), today: today, calendar: c)
        #expect(s.days == 0)
        #expect(s.isPaused)
    }

    @Test func longestRhythmSurvivesALapse() {
        let focus = days([0, 1] + Array(10...19))
        #expect(RhythmCalculator.longest(focusDays: focus, calendar: c) == 10)
    }

    @Test func emptyHistoryHasNoRhythm() {
        let s = RhythmCalculator.status(focusDays: [], today: today, calendar: c)
        #expect(s.days == 0)
        #expect(!s.isPaused)
    }
}
