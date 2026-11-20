import Foundation

// Habits as plain values: when one is due, how its streak stands, how bright
// its star burns. Pure, so the app, its widgets and the tests agree. Days are
// `DayKey`s, resolved in the time zone of the moment a habit was kept, so a
// streak never shifts when someone travels.

/// How often a habit is meant to happen.
enum HabitCadence: Equatable, Hashable, Codable, Sendable {
    /// Every day.
    case daily
    /// On chosen weekdays (Gregorian numbers: 1 Sunday … 7 Saturday).
    case weekdays(Set<Int>)
    /// A number of times in each week, on any days.
    case timesPerWeek(Int)

    static let weeklyRange = 1...7
    static let allWeekdays: Set<Int> = Set(1...7)

    /// Stored form: `cadenceRaw`, `weekdayMask` (bit n-1 for weekday n) and `weeklyTarget`.
    init(raw: String, weekdayMask: Int, weeklyTarget: Int) {
        switch raw {
        case "days":
            let days = Set((1...7).filter { weekdayMask & (1 << ($0 - 1)) != 0 })
            self = days.isEmpty || days == Self.allWeekdays ? .daily : .weekdays(days)
        case "weekly":
            self = .timesPerWeek(min(Self.weeklyRange.upperBound, max(Self.weeklyRange.lowerBound, weeklyTarget)))
        default:
            self = .daily
        }
    }

    var raw: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "days"
        case .timesPerWeek: "weekly"
        }
    }

    var weekdayMask: Int {
        guard case let .weekdays(days) = self else { return 0b111_1111 }
        return days.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    var weeklyTarget: Int {
        if case let .timesPerWeek(n) = self { return n }
        return 7
    }

    /// Streaks count weeks for a weekly target, days otherwise.
    var countsWeeks: Bool {
        if case .timesPerWeek = self { return true }
        return false
    }
}

/// Weekday arithmetic on day keys, with the week starting where the person's
/// calendar starts it (Monday in Türkiye, Sunday in the US).
struct HabitCalendar: Sendable {
    var calendar: Calendar

    init(_ calendar: Calendar) { self.calendar = calendar }

    private var gregorian: Calendar { DayKey.gregorian(matching: calendar) }

    /// 1 Sunday … 7 Saturday.
    func weekday(of day: DayKey) -> Int {
        guard let start = day.startDate(calendar: calendar) else { return 1 }
        return gregorian.component(.weekday, from: start)
    }

    /// The first day of the week that holds `day`.
    func weekStart(of day: DayKey) -> DayKey {
        let offset = (weekday(of: day) - calendar.firstWeekday + 7) % 7
        return day.adding(days: -offset, calendar: calendar)
    }

    /// The week's seven days, in order.
    func week(of day: DayKey) -> [DayKey] {
        let start = weekStart(of: day)
        return (0..<7).map { start.adding(days: $0, calendar: calendar) }
    }

    /// Weekdays (1…7) in the order the person's week runs.
    var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// Whole days from `a` to `b` (negative when `b` is earlier).
    func days(from a: DayKey, to b: DayKey) -> Int {
        guard let da = a.startDate(calendar: calendar), let db = b.startDate(calendar: calendar) else { return 0 }
        // Noon-to-noon so a daylight-saving day of 23 or 25 hours still counts as one.
        let noonA = da.addingTimeInterval(12 * 3600), noonB = db.addingTimeInterval(12 * 3600)
        return Int((noonB.timeIntervalSince(noonA) / 86_400).rounded())
    }
}

/// A habit's schedule from the day it began.
struct HabitSchedule: Equatable, Sendable {
    var cadence: HabitCadence
    /// The first day the habit counts.
    var startDay: DayKey

    /// Whether `day` asks for the habit. Every day is open to a weekly target.
    func isDue(on day: DayKey, calendar: HabitCalendar) -> Bool {
        guard day >= startDay else { return false }
        switch cadence {
        case .daily, .timesPerWeek: return true
        case let .weekdays(days): return days.contains(calendar.weekday(of: day))
        }
    }
}

/// Where a day stands for one habit, for the week strip and the heat map.
enum HabitDayState: String, Equatable, Sendable {
    /// Kept.
    case kept
    /// Due and gone by without it: a dim star, never a red mark.
    case missed
    /// Not asked for that day (or before the habit began).
    case rest
    /// Today, still open.
    case open
    /// Still ahead.
    case future
}

/// A habit's numbers at a moment.
struct HabitStats: Equatable, Sendable {
    /// The unbroken run, in days (or weeks for a weekly target). Today, while
    /// still open, never breaks it.
    var current: Int
    var best: Int
    /// Days kept, ever.
    var total: Int
    var countsWeeks: Bool
    var keptToday: Bool
    var dueToday: Bool
    /// Kept this week (weekly targets).
    var keptThisWeek: Int
    /// Kept out of due in the last 30 days, 0…1 (nil before anything was due).
    var recentRate: Double?

    /// The run in days, for brightness: weeks count as seven.
    var currentDays: Int { countsWeeks ? current * 7 : current }

    /// Today is due, not yet kept, and a run is at stake.
    var atRisk: Bool { dueToday && !keptToday && current > 0 }

    static func compute(kept: Set<DayKey>, schedule: HabitSchedule, today: DayKey, calendar: Calendar) -> HabitStats {
        let cal = HabitCalendar(calendar)
        // A day kept before the habit "began" (logged after the fact) moves its start back.
        let start = min(schedule.startDay, kept.min() ?? schedule.startDay)
        let effective = HabitSchedule(cadence: schedule.cadence, startDay: start)
        let past = kept.filter { $0 <= today }
        let keptToday = past.contains(today)
        let dueToday: Bool
        let thisWeek = Set(cal.week(of: today)).intersection(past).count
        let streaks: (current: Int, best: Int)
        switch schedule.cadence {
        case let .timesPerWeek(target):
            streaks = weekStreaks(kept: past, target: target, start: start, today: today, calendar: cal)
            dueToday = thisWeek < target && !keptToday
        case .daily, .weekdays:
            streaks = dayStreaks(kept: past, schedule: effective, today: today, calendar: cal)
            dueToday = effective.isDue(on: today, calendar: cal)
        }
        return HabitStats(current: streaks.current, best: max(streaks.best, streaks.current), total: past.count,
                          countsWeeks: schedule.cadence.countsWeeks, keptToday: keptToday, dueToday: dueToday,
                          keptThisWeek: thisWeek,
                          recentRate: recentRate(kept: past, schedule: effective, today: today, calendar: cal))
    }

    /// Due days count when kept and end a run when missed; a day off counts
    /// only if it was kept anyway. Today, still open, is skipped.
    private static func dayStreaks(kept: Set<DayKey>, schedule: HabitSchedule, today: DayKey,
                                   calendar: HabitCalendar) -> (Int, Int) {
        let span = calendar.days(from: schedule.startDay, to: today)
        guard span >= 0 else { return (0, 0) }
        var run = 0, best = 0
        var day = schedule.startDay
        for _ in 0...span {
            let isKept = kept.contains(day)
            if isKept {
                run += 1
            } else if schedule.isDue(on: day, calendar: calendar), day != today {
                run = 0
            }
            best = max(best, run)
            day = day.adding(days: 1, calendar: calendar.calendar)
        }
        return (run, best)
    }

    /// Weeks that met the target count; a missed one ends the run. This
    /// week, still open, is skipped, and so is a first week that began too
    /// late in the week to reach the target.
    private static func weekStreaks(kept: Set<DayKey>, target: Int, start: DayKey, today: DayKey,
                                     calendar: HabitCalendar) -> (Int, Int) {
        let first = calendar.weekStart(of: start), last = calendar.weekStart(of: today)
        let weeks = calendar.days(from: first, to: last) / 7
        guard weeks >= 0 else { return (0, 0) }
        var counts: [DayKey: Int] = [:]
        for day in kept { counts[calendar.weekStart(of: day), default: 0] += 1 }
        let daysInFirstWeek = 7 - calendar.days(from: first, to: start)
        var run = 0, best = 0
        var week = first
        for index in 0...weeks {
            if (counts[week] ?? 0) >= target {
                run += 1
            } else if week != last, !(index == 0 && daysInFirstWeek < target) {
                run = 0
            }
            best = max(best, run)
            week = week.adding(days: 7, calendar: calendar.calendar)
        }
        return (run, best)
    }

    private static func recentRate(kept: Set<DayKey>, schedule: HabitSchedule, today: DayKey,
                                   calendar: HabitCalendar) -> Double? {
        let from = max(schedule.startDay, today.adding(days: -29, calendar: calendar.calendar))
        let span = calendar.days(from: from, to: today)
        guard span >= 0 else { return nil }
        if case let .timesPerWeek(target) = schedule.cadence {
            // Seven days ask for `target` days kept.
            let keptInWindow = kept.filter { $0 >= from && $0 <= today }.count
            let asked = Double(span + 1) / 7 * Double(target)
            return asked > 0 ? min(1, Double(keptInWindow) / asked) : nil
        }
        var due = 0, done = 0
        var day = from
        for _ in 0...span {
            // Today counts only once it's kept: an open day isn't a miss.
            if schedule.isDue(on: day, calendar: calendar), day != today || kept.contains(day) {
                due += 1
                if kept.contains(day) { done += 1 }
            }
            day = day.adding(days: 1, calendar: calendar.calendar)
        }
        return due > 0 ? Double(done) / Double(due) : nil
    }

    /// One day's state for this habit.
    static func state(of day: DayKey, kept: Set<DayKey>, schedule: HabitSchedule, today: DayKey,
                      calendar: Calendar) -> HabitDayState {
        let cal = HabitCalendar(calendar)
        if kept.contains(day) { return .kept }
        if day > today { return .future }
        let start = min(schedule.startDay, kept.min() ?? schedule.startDay)
        let effective = HabitSchedule(cadence: schedule.cadence, startDay: start)
        guard effective.isDue(on: day, calendar: cal) else { return .rest }
        if day == today { return .open }
        // A weekly target isn't missed day by day.
        if schedule.cadence.countsWeeks { return .rest }
        return .missed
    }
}

/// How brightly a habit's star burns, from the length of its run. The last
/// stage sits at 66 days: about how long a daily habit takes to become
/// automatic (Lally et al., 2010).
enum HabitLuminosity: Int, CaseIterable, Comparable, Sendable {
    case ember, spark, glow, star, giant, nova

    /// The run (in days) each stage begins at.
    var threshold: Int {
        switch self {
        case .ember: 0
        case .spark: 1
        case .glow: 3
        case .star: 7
        case .giant: 21
        case .nova: 66
        }
    }

    static let automaticDays = 66

    init(days: Int) {
        self = Self.allCases.last { days >= $0.threshold } ?? .ember
    }

    var next: HabitLuminosity? { HabitLuminosity(rawValue: rawValue + 1) }

    /// 0.3 (an ember) … 1 (a nova), easing up with each day of the run.
    static func brightness(days: Int) -> Double {
        let d = Double(max(0, days))
        return 0.3 + 0.7 * min(1, log(1 + d) / log(1 + Double(automaticDays)))
    }

    static func < (a: HabitLuminosity, b: HabitLuminosity) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .ember: String(localized: "Ember")
        case .spark: String(localized: "Spark")
        case .glow: String(localized: "Glow")
        case .star: String(localized: "Star")
        case .giant: String(localized: "Giant")
        case .nova: String(localized: "Nova")
        }
    }
}

/// A habit as the widget draws it.
struct HabitWidgetItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var symbol: String
    var hueRaw: String
    var streak: Int
    var countsWeeks: Bool
    /// Days kept, for this habit's star brightness.
    var streakDays: Int
    var keptToday: Bool
    var dueToday: Bool
}
