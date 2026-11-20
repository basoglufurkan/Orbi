import Foundation
import SwiftData

/// Something the person means to do again and again ("Read 20 pages"). Each
/// one burns as a star that brightens with its streak.
///
/// Kept days are `HabitCheckIn` rows, one per day; streaks and the heat map
/// are derived from them (`HabitStats`), never stored. Every property has a
/// default and the relationship is optional, so the model is a lightweight
/// addition and stays CloudKit-compatible.
@Model
final class Habit {
    var id: UUID = UUID()
    var title: String = ""
    /// An SF Symbol drawn inside the habit's star.
    var symbol: String = "sparkle"
    /// The habit's colour and star shape, borrowed from a focus category.
    var hueRaw: String = FocusCategory.creative.rawValue
    var createdAt: Date = Date.distantPast
    /// The first day it counts ("yyyy-MM-dd").
    var startDayRaw: String = ""
    /// "daily", "days" or "weekly" (see `HabitCadence`).
    var cadenceRaw: String = "daily"
    /// Weekdays for "days": bit n-1 set for weekday n (1 Sunday … 7 Saturday).
    var weekdayMask: Int = 0b111_1111
    /// Times a week for "weekly".
    var weeklyTarget: Int = 3
    /// Above 0, a day of focus this long (in `focusCategoryRaw`, or any when
    /// empty) keeps the habit by itself.
    var focusMinutes: Int = 0
    var focusCategoryRaw: String = ""
    var reminderEnabled: Bool = false
    var reminderHour: Int = 8
    var reminderMinute: Int = 0
    /// Order on the Habits screen; lower comes first.
    var sortOrder: Double = 0
    /// Resting habits leave Today and stop reminding; their history stays.
    var isArchived: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn]? = []

    init(title: String, now: Date, startDay: DayKey) {
        self.title = title
        self.createdAt = now
        self.startDayRaw = startDay.rawValue
    }

    var hue: FocusCategory { FocusCategory(storedValue: hueRaw) }

    var cadence: HabitCadence {
        get { HabitCadence(raw: cadenceRaw, weekdayMask: weekdayMask, weeklyTarget: weeklyTarget) }
        set {
            cadenceRaw = newValue.raw
            weekdayMask = newValue.weekdayMask
            if case let .timesPerWeek(n) = newValue { weeklyTarget = n }
        }
    }

    var schedule: HabitSchedule {
        HabitSchedule(cadence: cadence, startDay: DayKey(rawValue: startDayRaw.isEmpty ? DayKey(createdAt).rawValue : startDayRaw))
    }

    /// Days kept.
    var keptDays: Set<DayKey> { Set((checkIns ?? []).map(\.dayKey)) }

    var focusCategory: FocusCategory? { focusCategoryRaw.isEmpty ? nil : FocusCategory(rawValue: focusCategoryRaw) }

    var isFocusLinked: Bool { focusMinutes > 0 }

    func stats(today: DayKey, calendar: Calendar) -> HabitStats {
        HabitStats.compute(kept: keptDays, schedule: schedule, today: today, calendar: calendar)
    }
}

/// One day a habit was kept.
@Model
final class HabitCheckIn {
    var id: UUID = UUID()
    /// The local day it was kept ("yyyy-MM-dd").
    var dayKeyRaw: String = ""
    var createdAt: Date = Date.distantPast
    /// "tap", "focus", "notification" or "widget".
    var sourceRaw: String = "tap"
    var habit: Habit?

    init(day: DayKey, now: Date, source: String) {
        self.dayKeyRaw = day.rawValue
        self.createdAt = now
        self.sourceRaw = source
    }

    var dayKey: DayKey { DayKey(rawValue: dayKeyRaw) }
}
