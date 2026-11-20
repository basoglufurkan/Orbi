import Foundation
import SwiftData
import Testing
@testable import Lumora

/// "2026-10-dd" (October 2026: the 12th is a Monday, the 20th a Tuesday).
private func oct(_ d: Int) -> DayKey { DayKey(rawValue: String(format: "2026-10-%02d", d)) }
private func days(_ ds: [Int]) -> Set<DayKey> { Set(ds.map(oct)) }

private func calendar(_ zone: TimeZone = TestFixtures.istanbul, firstWeekday: Int = 2) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    c.firstWeekday = firstWeekday
    return c
}

private func stats(_ kept: Set<DayKey>, _ cadence: HabitCadence, start: DayKey = oct(1), today: DayKey = oct(20),
                   calendar cal: Calendar = calendar()) -> HabitStats {
    HabitStats.compute(kept: kept, schedule: HabitSchedule(cadence: cadence, startDay: start), today: today, calendar: cal)
}

@Suite("Habits: streaks")
struct HabitStreakTests {
    @Test func aDailyRunCountsUpToToday() {
        let s = stats(days(Array(15...20)), .daily)
        #expect(s.current == 6)
        #expect(s.best == 6)
        #expect(s.keptToday)
        #expect(!s.atRisk)
        #expect(s.total == 6)
    }

    @Test func todayStillOpenNeverBreaksTheRun() {
        let s = stats(days(Array(15...19)), .daily)
        #expect(s.current == 5)
        #expect(!s.keptToday)
        #expect(s.dueToday)
        #expect(s.atRisk)
    }

    @Test func aMissedDayEndsTheRunButBestRemembersIt() {
        let gap = stats(days(Array(10...14) + Array(16...19)), .daily)
        #expect(gap.current == 4)
        #expect(gap.best == 5)
        let broken = stats(days(Array(10...18)), .daily)
        #expect(broken.current == 0)
        #expect(broken.best == 9)
    }

    @Test func daysAheadNeverCount() {
        let s = stats(days([19, 20, 21, 22]), .daily)
        #expect(s.current == 2)
        #expect(s.total == 2)
    }

    @Test func weekdayHabitsRestOnWeekends() {
        let weekdays = HabitCadence.weekdays([2, 3, 4, 5, 6])
        // Mon 12 – Fri 16, the weekend off, Mon 19; Tue 20 still open.
        let s = stats(days([12, 13, 14, 15, 16, 19]), weekdays)
        #expect(s.current == 6)
        #expect(s.dueToday)
        // Kept on Saturday anyway: it counts, never required.
        #expect(stats(days([12, 13, 14, 15, 16, 17, 19]), weekdays).current == 7)
        // A missed Friday breaks it.
        #expect(stats(days([12, 13, 14, 15, 19]), weekdays).current == 1)
        // Saturday asks for nothing.
        #expect(!stats([], weekdays, today: oct(17)).dueToday)
    }

    @Test func weeklyTargetsCountWeeks() {
        let thrice = HabitCadence.timesPerWeek(3)
        // Weeks run Monday to Sunday: 5–11 and 12–18 met, 19–25 under way.
        let s = stats(days([5, 7, 9, 12, 14, 16, 19]), thrice, start: oct(5))
        #expect(s.countsWeeks)
        #expect(s.current == 2)
        #expect(s.keptThisWeek == 1)
        #expect(s.dueToday)
        #expect(s.currentDays == 14)
        // Reaching it this week adds the week.
        let met = stats(days([5, 7, 9, 12, 14, 16, 19, 20, 22]), thrice, start: oct(5), today: oct(22))
        #expect(met.current == 3)
        #expect(!met.dueToday)
        // A week short of it ends the run.
        let short = stats(days([5, 7, 12, 14, 16]), thrice, start: oct(5))
        #expect(short.current == 1)
        #expect(short.best == 1)
    }

    @Test func theWeekStartsWhereThePersonsCalendarStartsIt() {
        let twice = HabitCadence.timesPerWeek(2)
        let kept = days([17, 18])   // Saturday and Sunday
        // Monday weeks: 12–18 holds both days.
        #expect(stats(kept, twice, start: oct(12), calendar: calendar(firstWeekday: 2)).current == 1)
        // Sunday weeks: 11–17 and 18–24 hold one each.
        #expect(stats(kept, twice, start: oct(12), calendar: calendar(firstWeekday: 1)).current == 0)
    }

    @Test func aDayLoggedBeforeTheStartMovesTheStartBack() {
        let s = stats(days([8, 9, 10]), .daily, start: oct(10), today: oct(10))
        #expect(s.current == 3)
    }

    @Test func theRecentRateIgnoresAnOpenToday() {
        let s = stats(days([18, 19]), .daily, start: oct(18))
        #expect(s.recentRate == 1)
        let half = stats(days([18]), .daily, start: oct(18))
        #expect(half.recentRate == 0.5)
    }
}

@Suite("Habits: schedules and days")
struct HabitScheduleTests {
    @Test func cadencesSurviveStorage() {
        for cadence in [HabitCadence.daily, .weekdays([1, 4, 7]), .timesPerWeek(5)] {
            #expect(HabitCadence(raw: cadence.raw, weekdayMask: cadence.weekdayMask, weeklyTarget: cadence.weeklyTarget) == cadence)
        }
        // No days, or every day, is just daily; targets stay in range.
        #expect(HabitCadence(raw: "days", weekdayMask: 0, weeklyTarget: 3) == .daily)
        #expect(HabitCadence(raw: "days", weekdayMask: 0b111_1111, weeklyTarget: 3) == .daily)
        #expect(HabitCadence(raw: "weekly", weekdayMask: 0, weeklyTarget: 0) == .timesPerWeek(1))
        #expect(HabitCadence(raw: "weekly", weekdayMask: 0, weeklyTarget: 12) == .timesPerWeek(7))
        #expect(HabitCadence(raw: "someday", weekdayMask: 0, weeklyTarget: 3) == .daily)
    }

    @Test func weekdaysAndWeekStarts() {
        let monday = HabitCalendar(calendar(firstWeekday: 2)), sunday = HabitCalendar(calendar(firstWeekday: 1))
        #expect(monday.weekday(of: oct(20)) == 3)
        #expect(monday.weekStart(of: oct(20)) == oct(19))
        #expect(sunday.weekStart(of: oct(20)) == oct(18))
        #expect(monday.weekStart(of: oct(18)) == oct(12))
        #expect(monday.week(of: oct(20)).first == oct(19))
        #expect(monday.week(of: oct(20)).last == oct(25))
        #expect(monday.orderedWeekdays == [2, 3, 4, 5, 6, 7, 1])
        #expect(sunday.orderedWeekdays == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func aDayEndsAtLocalMidnight() {
        let cal = calendar()
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 59, second: 59))!
        #expect(DayKey(late, calendar: cal) == oct(20))
        #expect(DayKey(late.addingTimeInterval(1), calendar: cal) == oct(21))
    }

    @Test func daylightSavingDaysCountAsOne() {
        // New York falls back on Sunday 1 November 2026: a 25-hour day.
        let ny = calendar(TimeZone(identifier: "America/New_York")!)
        let nov = { (d: Int) in DayKey(rawValue: String(format: "2026-11-%02d", d)) }
        let cal = HabitCalendar(ny)
        #expect(cal.days(from: oct(30), to: nov(3)) == 4)
        #expect(oct(31).adding(days: 1, calendar: ny) == nov(1))
        #expect(nov(1).adding(days: 1, calendar: ny) == nov(2))
        #expect(cal.weekday(of: nov(1)) == 1)
        let kept = Set((25...31).map(oct) + (1...3).map(nov))
        let s = HabitStats.compute(kept: kept, schedule: HabitSchedule(cadence: .daily, startDay: oct(25)), today: nov(3), calendar: ny)
        #expect(s.current == 10)
        // Spring forward (8 March 2026, a 23-hour day) too.
        let mar = { (d: Int) in DayKey(rawValue: String(format: "2026-03-%02d", d)) }
        #expect(cal.days(from: mar(7), to: mar(9)) == 2)
    }

    @Test func keptDaysDontShiftWhenTravelling() {
        // Kept in Istanbul at 23:30 on the 20th; it's still the 20th in New York.
        let istanbul = calendar(), ny = calendar(TimeZone(identifier: "America/New_York")!)
        let keptAt = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 30))!
        let kept: Set<DayKey> = [DayKey(keptAt, calendar: istanbul)]
        let later = keptAt.addingTimeInterval(3 * 3600)   // 02:30 in Istanbul, 19:30 on the 20th in New York
        let schedule = HabitSchedule(cadence: .daily, startDay: oct(20))
        #expect(HabitStats.compute(kept: kept, schedule: schedule, today: DayKey(later, calendar: ny), calendar: ny).keptToday)
        #expect(!HabitStats.compute(kept: kept, schedule: schedule, today: DayKey(later, calendar: istanbul), calendar: istanbul).keptToday)
    }

    @Test func eachDayHasAState() {
        let cal = calendar()
        let schedule = HabitSchedule(cadence: .weekdays([2, 3, 4, 5, 6]), startDay: oct(12))
        let kept = days([12])
        func state(_ d: Int) -> HabitDayState {
            HabitStats.state(of: oct(d), kept: kept, schedule: schedule, today: oct(20), calendar: cal)
        }
        #expect(state(12) == .kept)
        #expect(state(13) == .missed)
        #expect(state(17) == .rest)
        #expect(state(20) == .open)
        #expect(state(21) == .future)
        #expect(state(11) == .rest)
        // A weekly target is never "missed" day by day.
        let weekly = HabitSchedule(cadence: .timesPerWeek(2), startDay: oct(12))
        #expect(HabitStats.state(of: oct(13), kept: [], schedule: weekly, today: oct(20), calendar: cal) == .rest)
    }

    @Test func brightnessGrowsToANovaAtSixtySixDays() {
        #expect(HabitLuminosity(days: 0) == .ember)
        #expect(HabitLuminosity(days: 1) == .spark)
        #expect(HabitLuminosity(days: 7) == .star)
        #expect(HabitLuminosity(days: 65) == .giant)
        #expect(HabitLuminosity(days: 66) == .nova)
        #expect(HabitLuminosity.brightness(days: 0) == 0.3)
        #expect(HabitLuminosity.brightness(days: 66) == 1)
        #expect(HabitLuminosity.brightness(days: 400) == 1)
        let ramp = (0...70).map(HabitLuminosity.brightness(days:))
        #expect(zip(ramp, ramp.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func habitsLinkFromBothForms() {
        #expect(DeepLink(url: URL(string: "lumora://habits")!) == .habits)
        #expect(DeepLink(url: URL(string: "https://www.mobapptech.com/lumora/habits/")!) == .habits)
        #expect(DeepLink(url: DeepLink.habits.appURL) == .habits)
        #expect(NotificationService.link(forNotification: HabitReminderPlanner.identifier(habitID: UUID(), day: oct(20))) == .habits)
    }
}

@Suite("Habits: reminders")
struct HabitReminderTests {
    let cal = calendar()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))! }

    private func input(_ title: String, _ cadence: HabitCadence, hour: Int, kept: [Int] = [], streak: Int = 0) -> HabitReminderInput {
        HabitReminderInput(id: UUID(), title: title, schedule: HabitSchedule(cadence: cadence, startDay: oct(1)),
                           hour: hour, minute: 0, kept: days(kept), streak: streak, countsWeeks: cadence.countsWeeks)
    }

    @Test func remindersFollowOpenDaysOnly() {
        // 08:00 has passed today: the first one is tomorrow.
        let morning = HabitReminderPlanner.alerts(for: [input("Run", .daily, hour: 8)], now: now, calendar: cal)
        #expect(morning.count == 6)
        #expect(morning.first?.day == oct(21))
        // Kept today: today stays quiet.
        let kept = HabitReminderPlanner.alerts(for: [input("Read", .daily, hour: 21, kept: [20])], now: now, calendar: cal)
        #expect(kept.first?.day == oct(21))
        // Weekdays only.
        let weekdays = HabitReminderPlanner.alerts(for: [input("Write", .weekdays([2, 3, 4, 5, 6]), hour: 21)], now: now, calendar: cal)
        #expect(weekdays.map(\.day) == [oct(20), oct(21), oct(22), oct(23), oct(26)])
    }

    @Test func aWeekThatReachedItsTargetStaysQuiet() {
        let alerts = HabitReminderPlanner.alerts(for: [input("Swim", .timesPerWeek(2), hour: 18, kept: [19, 20])], now: now, calendar: cal)
        #expect(alerts.map(\.day) == [oct(26)])
    }

    @Test func onlyTodaysReminderSpeaksOfTheStreak() {
        let alerts = HabitReminderPlanner.alerts(for: [input("Read", .daily, hour: 21, streak: 4)], now: now, calendar: cal)
        #expect(alerts.first?.day == oct(20))
        #expect(alerts.first?.streak == 4)
        #expect(alerts.dropFirst().allSatisfy { $0.streak == nil })
    }

    @Test func soonestFirstWithinTheLimit() {
        let many = (0..<20).map { input("Habit \($0)", .daily, hour: 7 + $0 % 12) }
        let alerts = HabitReminderPlanner.alerts(for: many, now: now, calendar: cal)
        #expect(alerts.count == HabitReminderPlanner.limit)
        #expect(zip(alerts, alerts.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
        #expect(alerts.allSatisfy { $0.fireDate > now })
    }

    @Test func identifiersCarryTheHabitAndDay() {
        let id = UUID()
        let identifier = HabitReminderPlanner.identifier(habitID: id, day: oct(20))
        #expect(identifier.hasPrefix(NotificationService.habitPrefix))
        let parsed = HabitReminderPlanner.parse(identifier)
        #expect(parsed?.habitID == id)
        #expect(parsed?.day == oct(20))
        #expect(HabitReminderPlanner.parse("lumora.plan.x.before") == nil)
        #expect(NotificationService.analyticsKind(forNotification: identifier) == "habit_reminder")
    }
}

@Suite("Habits: the store")
@MainActor
struct HabitStoreTests {
    let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)

    private func store() throws -> (HabitStore, ModelContext) {
        let context = try TestFixtures.makeContext()
        return (HabitStore(context: context, clock: clock), context)
    }

    private func draft(_ title: String, focus: Int = 0, category: FocusCategory? = nil) -> HabitDraft {
        var d = HabitDraft()
        d.title = title
        d.focusMinutes = focus
        d.focusCategory = category
        return d
    }

    @Test func keepingAndReopeningToday() throws {
        let (habits, _) = try store()
        let read = habits.create(draft("  Read  "))
        #expect(read.title == "Read")
        #expect(read.schedule.startDay == oct(20))
        #expect(habits.toggleToday(read))
        #expect(habits.isKept(read, on: oct(20)))
        // Keeping twice leaves one star.
        #expect(!habits.setKept(read, on: oct(20), true))
        #expect(read.checkIns?.count == 1)
        #expect(!habits.toggleToday(read))
        #expect(read.checkIns?.isEmpty == true)
        // Tomorrow can't be kept yet; yesterday can still be logged.
        #expect(!habits.setKept(read, on: oct(21), true))
        #expect(habits.setKept(read, on: oct(19), true))
        #expect(read.stats(today: oct(20), calendar: clock.calendar).current == 1)
    }

    @Test func midnightOpensANewDay() throws {
        let (habits, _) = try store()
        let read = habits.create(draft("Read"))
        clock.set(clock.calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 59))!)
        habits.toggleToday(read)
        clock.advance(by: 120)   // 00:01 on the 21st
        #expect(habits.today == oct(21))
        let s = read.stats(today: habits.today, calendar: clock.calendar)
        #expect(!s.keptToday)
        #expect(s.current == 1)
        #expect(s.atRisk)
    }

    @Test func focusKeepsFocusLinkedHabits() throws {
        let (habits, context) = try store()
        let read = habits.create(draft("Read", focus: 20, category: .reading))
        let deep = habits.create(draft("Deep work", focus: 60))
        let tap = habits.create(draft("Water"))
        func session(_ minutes: Int, _ category: FocusCategory, outcome: SessionOutcome = .completed) {
            let start = clock.now.addingTimeInterval(-Double(minutes) * 60)
            context.insert(FocusSession(id: UUID(), startedAt: start, endedAt: clock.now, plannedSeconds: minutes * 60,
                                        focusedSeconds: minutes * 60, pausedSeconds: 0, pauseCount: 0, category: category,
                                        intention: "", outcome: outcome, dayKey: oct(20), timeZoneID: "Europe/Istanbul"))
        }
        session(12, .reading)
        session(3, .reading, outcome: .tooShort)
        #expect(habits.creditFocus().isEmpty)
        #expect(habits.focusedMinutesToday(for: read) == 12)
        session(10, .reading)
        session(30, .work)
        let kept = habits.creditFocus()
        #expect(kept.map(\.title) == ["Read"])
        #expect(read.checkIns?.first?.sourceRaw == "focus")
        #expect(habits.focusedMinutesToday(for: deep) == 52)
        #expect(!habits.isKept(tap, on: oct(20)))
        // Already kept: nothing more.
        session(20, .coding)
        #expect(habits.creditFocus().map(\.title) == ["Deep work"])
        #expect(habits.creditFocus().isEmpty)
    }

    @Test func archivedHabitsLeaveTodayButKeepTheirHistory() throws {
        let (habits, _) = try store()
        let a = habits.create(draft("A"))
        let b = habits.create(draft("B"))
        habits.toggleToday(a)
        habits.setArchived(a, true)
        #expect(habits.activeHabits().map(\.title) == ["B"])
        #expect(habits.widgetItems().map(\.id) == [b.id])
        habits.setArchived(a, false)
        #expect(habits.activeHabits().map(\.title) == ["B", "A"])
        #expect(habits.isKept(a, on: oct(20)))
    }

    @Test func deletingAHabitTakesItsDaysWithIt() throws {
        let (habits, context) = try store()
        let a = habits.create(draft("A"))
        habits.setKept(a, on: oct(19), true)
        habits.setKept(a, on: oct(20), true)
        habits.delete(a)
        #expect(try context.fetchCount(FetchDescriptor<HabitCheckIn>()) == 0)
    }

    @Test func reminderInputsOnlyForHabitsThatWantThem() throws {
        let (habits, _) = try store()
        var quiet = draft("Quiet")
        quiet.reminderEnabled = false
        var loud = draft("Loud")
        loud.reminderEnabled = true
        loud.reminderHour = 21
        habits.create(quiet)
        habits.create(loud)
        #expect(habits.reminderInputs().map(\.title) == ["Loud"])
        #expect(habits.reminderInputs().first?.hour == 21)
    }

    @Test func twoDevicesKeepingTheSameDayFoldIntoOne() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let dataStore = DataStore(container: container)
        let habits = HabitStore(context: dataStore.context, clock: clock)
        let a = habits.create(draft("A"))
        for _ in 0..<2 {
            let c = HabitCheckIn(day: oct(20), now: clock.now, source: "tap")
            dataStore.context.insert(c)
            c.habit = a
        }
        dataStore.save()
        #expect(a.checkIns?.count == 2)
        #expect(dataStore.mergeDuplicates())
        #expect(a.checkIns?.count == 1)
        #expect(!dataStore.mergeDuplicates())
    }
}

@Suite("Habits: upgrading the store")
@MainActor
struct HabitMigrationTests {
    /// A store written before habits existed (schema 1.6) opens with them,
    /// history intact, and takes habits right away.
    @Test func aStoreFromBeforeHabitsOpensWithThem() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "habit-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let synced = folder.appending(path: "default.store"), device = folder.appending(path: "device.store")
        let habitTypes: Set<ObjectIdentifier> = [ObjectIdentifier(Habit.self), ObjectIdentifier(HabitCheckIn.self)]
        let before = DataStore.syncedModels.filter { !habitTypes.contains(ObjectIdentifier($0)) }
        #expect(before.count == DataStore.syncedModels.count - 2)

        do {
            let old = try ModelContainer(for: Schema(before),
                                         configurations: ModelConfiguration("Synced", schema: Schema(before), url: synced,
                                                                            cloudKitDatabase: .none))
            let context = ModelContext(old)
            let task = FocusTask(title: "Essay", category: .study, now: TestFixtures.baseDate)
            task.isPlanned = true
            context.insert(task)
            try context.save()
        }

        let schema = Schema(versionedSchema: LumoraSchemaV1.self)
        let container = try ModelContainer(
            for: schema, migrationPlan: LumoraMigrationPlan.self,
            configurations: ModelConfiguration("Synced", schema: Schema(DataStore.syncedModels), url: synced, cloudKitDatabase: .none),
            ModelConfiguration("Device", schema: Schema(DataStore.deviceModels), url: device, cloudKitDatabase: .none))
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<FocusTask>()).map(\.title) == ["Essay"])
        let habits = HabitStore(context: context, clock: ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul))
        let habit = habits.create({ var d = HabitDraft(); d.title = "Read"; return d }())
        habits.toggleToday(habit)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<HabitCheckIn>()) == 1)
        #expect(LumoraSchemaV1.versionIdentifier == Schema.Version(1, 7, 0))
    }
}
