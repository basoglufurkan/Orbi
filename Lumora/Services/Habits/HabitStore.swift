import Foundation
import SwiftData
import os

/// The editable fields of a habit, as the add/edit sheet holds them.
struct HabitDraft: Equatable, Sendable {
    var title = ""
    var symbol = "sparkle"
    var hue: FocusCategory = .creative
    var cadence: HabitCadence = .daily
    /// Above 0, focusing this long in a day keeps the habit.
    var focusMinutes = 0
    /// nil: any focus counts.
    var focusCategory: FocusCategory?
    var reminderEnabled = false
    var reminderHour = 8
    var reminderMinute = 0

    static let titleLimit = 60
    static let focusOptions = [10, 15, 20, 25, 30, 45, 60, 90]

    var trimmedTitle: String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.titleLimit))
    }

    /// A habit needs a name, and a weekday habit at least one day.
    var isValid: Bool {
        guard !trimmedTitle.isEmpty else { return false }
        if case let .weekdays(days) = cadence { return !days.isEmpty }
        return true
    }

    init() {}

    init(_ habit: Habit) {
        title = habit.title
        symbol = habit.symbol
        hue = habit.hue
        cadence = habit.cadence
        focusMinutes = habit.focusMinutes
        focusCategory = habit.focusCategory
        reminderEnabled = habit.reminderEnabled
        reminderHour = habit.reminderHour
        reminderMinute = habit.reminderMinute
    }

    init(_ template: HabitTemplate) {
        title = template.title
        symbol = template.symbol
        hue = template.hue
        cadence = template.cadence
        focusMinutes = template.focusMinutes
        focusCategory = template.focusMinutes > 0 ? template.hue : nil
        reminderHour = template.reminderHour
    }
}

/// A ready-made habit to start from.
struct HabitTemplate: Identifiable, Sendable {
    var id: String
    var title: String
    var symbol: String
    var hue: FocusCategory
    var cadence: HabitCadence
    var focusMinutes: Int
    var reminderHour: Int

    static var all: [HabitTemplate] {
        [
            HabitTemplate(id: "read", title: String(localized: "Read 20 minutes"), symbol: "book.fill", hue: .reading,
                          cadence: .daily, focusMinutes: 20, reminderHour: 21),
            HabitTemplate(id: "move", title: String(localized: "Move your body"), symbol: "figure.walk", hue: .study,
                          cadence: .timesPerWeek(4), focusMinutes: 0, reminderHour: 18),
            HabitTemplate(id: "meditate", title: String(localized: "Meditate"), symbol: "figure.mind.and.body", hue: .coding,
                          cadence: .daily, focusMinutes: 0, reminderHour: 7),
            HabitTemplate(id: "water", title: String(localized: "Drink water"), symbol: "drop.fill", hue: .coding,
                          cadence: .daily, focusMinutes: 0, reminderHour: 10),
            HabitTemplate(id: "journal", title: String(localized: "Journal"), symbol: "pencil.and.scribble", hue: .creative,
                          cadence: .daily, focusMinutes: 0, reminderHour: 22),
            HabitTemplate(id: "language", title: String(localized: "Learn a language"), symbol: "character.book.closed.fill",
                          hue: .study, cadence: .weekdays([2, 3, 4, 5, 6]), focusMinutes: 15, reminderHour: 19),
            HabitTemplate(id: "deep", title: String(localized: "Deep work"), symbol: "brain.head.profile", hue: .work,
                          cadence: .weekdays([2, 3, 4, 5, 6]), focusMinutes: 50, reminderHour: 9),
            HabitTemplate(id: "screens", title: String(localized: "No screens in bed"), symbol: "moon.zzz.fill", hue: .work,
                          cadence: .daily, focusMinutes: 0, reminderHour: 22),
        ]
    }
}

enum HabitSymbols {
    static let all = [
        "sparkle", "book.fill", "figure.walk", "figure.run", "dumbbell.fill", "figure.mind.and.body",
        "drop.fill", "leaf.fill", "brain.head.profile", "pencil.and.scribble", "character.book.closed.fill", "globe",
        "moon.zzz.fill", "sun.max.fill", "heart.fill", "music.note", "paintbrush.pointed.fill", "fork.knife",
        "cup.and.saucer.fill", "pills.fill", "bed.double.fill", "iphone.slash", "hands.sparkles.fill", "star.fill",
    ]
}

/// All writes to habits and their kept days.
@MainActor
final class HabitStore {
    private let context: ModelContext
    private let clock: DateProvider
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Habits")
    /// Called after every saved change, so reminders and widgets follow (set by the app model).
    var didSave: (() -> Void)?

    init(context: ModelContext, clock: DateProvider) {
        self.context = context
        self.clock = clock
    }

    var today: DayKey { DayKey(clock.now, calendar: clock.calendar) }

    @discardableResult
    func create(_ draft: HabitDraft, template: String? = nil) -> Habit {
        let habit = Habit(title: draft.trimmedTitle, now: clock.now, startDay: today)
        habit.sortOrder = nextSortOrder()
        apply(draft, to: habit)
        context.insert(habit)
        save()
        Telemetry.log(.habitCreated(cadence: draft.cadence.raw, focusMinutes: draft.focusMinutes,
                                    reminder: draft.reminderEnabled, template: template ?? "none"))
        return habit
    }

    func update(_ habit: Habit, with draft: HabitDraft) {
        habit.title = draft.trimmedTitle
        apply(draft, to: habit)
        save()
    }

    /// Rests the habit: off Today and quiet, with its history kept.
    func setArchived(_ habit: Habit, _ archived: Bool) {
        if archived { Telemetry.log(.habitArchived(total: habit.keptDays.count)) }
        habit.isArchived = archived
        if !archived { habit.sortOrder = nextSortOrder() }
        save()
    }

    /// Deletes the habit and every day it was kept.
    func delete(_ habit: Habit) {
        context.delete(habit)
        save()
    }

    func move(_ rows: [Habit], from source: IndexSet, to destination: Int) {
        let orders = TaskPlanner.reorder(ids: rows.map(\.id), orders: rows.map(\.sortOrder), moving: source, to: destination)
        for habit in rows { if let order = orders[habit.id] { habit.sortOrder = order } }
        save()
    }

    // MARK: Keeping

    func isKept(_ habit: Habit, on day: DayKey) -> Bool {
        (habit.checkIns ?? []).contains { $0.dayKeyRaw == day.rawValue }
    }

    /// Marks `day` kept or not. Days ahead can't be kept. Returns whether anything changed.
    @discardableResult
    func setKept(_ habit: Habit, on day: DayKey, _ kept: Bool, source: String = "tap") -> Bool {
        guard day <= today else { return false }
        let existing = (habit.checkIns ?? []).filter { $0.dayKeyRaw == day.rawValue }
        if kept {
            guard existing.isEmpty else { return false }
            let checkIn = HabitCheckIn(day: day, now: clock.now, source: source)
            context.insert(checkIn)
            checkIn.habit = habit
            save()
            let stats = habit.stats(today: today, calendar: clock.calendar)
            Telemetry.log(.habitCheckedIn(source: source, streak: stats.current, backfill: day != today))
            return true
        } else {
            guard !existing.isEmpty else { return false }
            for c in existing { context.delete(c) }
            save()
            return true
        }
    }

    /// Keeps or reopens today. Returns whether it's now kept.
    @discardableResult
    func toggleToday(_ habit: Habit, source: String = "tap") -> Bool {
        let kept = !isKept(habit, on: today)
        setKept(habit, on: today, kept, source: source)
        return kept
    }

    /// Keeps today for every focus-linked habit whose minutes today's focus
    /// has reached. Returns the habits kept just now.
    @discardableResult
    func creditFocus() -> [Habit] {
        let day = today
        let linked = activeHabits().filter { $0.isFocusLinked && !isKept($0, on: day) }
        guard !linked.isEmpty else { return [] }
        let raw = day.rawValue
        let sessions = ((try? context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.dayKeyRaw == raw }))) ?? [])
            .map { (category: $0.category, seconds: $0.focusedSeconds, qualifies: $0.qualifies) }
        var kept: [Habit] = []
        for habit in linked
        where Self.focusedMinutes(sessions, category: habit.focusCategory) >= habit.focusMinutes {
            let checkIn = HabitCheckIn(day: day, now: clock.now, source: "focus")
            context.insert(checkIn)
            checkIn.habit = habit
            kept.append(habit)
        }
        guard !kept.isEmpty else { return [] }
        save()
        for habit in kept {
            Telemetry.log(.habitCheckedIn(source: "focus", streak: habit.stats(today: day, calendar: clock.calendar).current,
                                          backfill: false))
        }
        return kept
    }

    /// Today's focus toward a focus-linked habit, in minutes.
    func focusedMinutesToday(for habit: Habit) -> Int {
        let raw = today.rawValue
        let sessions = ((try? context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.dayKeyRaw == raw }))) ?? [])
            .map { (category: $0.category, seconds: $0.focusedSeconds, qualifies: $0.qualifies) }
        return Self.focusedMinutes(sessions, category: habit.focusCategory)
    }

    /// Minutes of star-earning focus, in `category` or in any when nil.
    nonisolated static func focusedMinutes(_ sessions: [(category: FocusCategory, seconds: Int, qualifies: Bool)],
                                           category: FocusCategory?) -> Int {
        sessions.filter { $0.qualifies && (category == nil || $0.category == category) }
            .reduce(0) { $0 + $1.seconds } / 60
    }

    // MARK: Reading

    func activeHabits() -> [Habit] {
        let d = FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(d)) ?? []
    }

    func fetch(id: UUID) -> Habit? {
        var d = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// The habits as the widget and the watch draw them.
    func widgetItems() -> [HabitWidgetItem] {
        let day = today, cal = clock.calendar
        return activeHabits().prefix(12).map { habit in
            let stats = habit.stats(today: day, calendar: cal)
            return HabitWidgetItem(id: habit.id, title: habit.title, symbol: habit.symbol, hueRaw: habit.hueRaw,
                                   streak: stats.current, countsWeeks: stats.countsWeeks, streakDays: stats.currentDays,
                                   keptToday: stats.keptToday, dueToday: stats.dueToday || stats.keptToday)
        }
    }

    /// What reminders need to know about each habit that wants them.
    func reminderInputs() -> [HabitReminderInput] {
        let day = today, cal = clock.calendar
        return activeHabits().filter(\.reminderEnabled).map { habit in
            let stats = habit.stats(today: day, calendar: cal)
            return HabitReminderInput(id: habit.id, title: habit.title, schedule: habit.schedule,
                                      hour: habit.reminderHour, minute: habit.reminderMinute,
                                      kept: habit.keptDays, streak: stats.current, countsWeeks: stats.countsWeeks)
        }
    }

    // MARK: Private

    private func apply(_ draft: HabitDraft, to habit: Habit) {
        habit.symbol = draft.symbol
        habit.hueRaw = draft.hue.rawValue
        habit.cadence = draft.cadence
        habit.focusMinutes = max(0, min(600, draft.focusMinutes))
        habit.focusCategoryRaw = draft.focusMinutes > 0 ? (draft.focusCategory?.rawValue ?? "") : ""
        habit.reminderEnabled = draft.reminderEnabled
        habit.reminderHour = min(23, max(0, draft.reminderHour))
        habit.reminderMinute = min(59, max(0, draft.reminderMinute))
    }

    private func nextSortOrder() -> Double {
        var d = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        d.fetchLimit = 1
        return ((try? context.fetch(d).first?.sortOrder) ?? 0) + 1
    }

    private func save() {
        do {
            guard context.hasChanges else { return }
            try context.save()
            didSave?()
        } catch {
            logger.error("Habit save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: Reminders

/// One habit, as the reminder planner sees it.
struct HabitReminderInput: Sendable {
    var id: UUID
    var title: String
    var schedule: HabitSchedule
    var hour: Int
    var minute: Int
    var kept: Set<DayKey>
    var streak: Int
    var countsWeeks: Bool
}

/// A reminder to keep a habit on one day.
struct HabitAlert: Equatable, Sendable {
    var habitID: UUID
    var title: String
    var day: DayKey
    var fireDate: Date
    /// The run at stake, said only on today's reminder (later ones can't know it).
    var streak: Int?
    var countsWeeks: Bool

    var id: String { HabitReminderPlanner.identifier(habitID: habitID, day: day) }
}

/// Which habit reminders to queue: one per open day, at the habit's time,
/// over the coming week, soonest first. Kept days, days off and weeks that
/// already reached their target stay quiet. Re-run after every change.
enum HabitReminderPlanner {
    static let prefix = "lumora.habit."
    /// iOS keeps 64 pending notifications; the day plan, the daily invitation
    /// and rare events use most of the rest.
    static let limit = 14
    static let daysAhead = 7

    static func identifier(habitID: UUID, day: DayKey) -> String {
        prefix + habitID.uuidString + "." + day.rawValue
    }

    /// The habit and day in a reminder's identifier.
    static func parse(_ identifier: String) -> (habitID: UUID, day: DayKey)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let rest = identifier.dropFirst(prefix.count)
        guard let dot = rest.lastIndex(of: "."), let id = UUID(uuidString: String(rest[..<dot])) else { return nil }
        let day = String(rest[rest.index(after: dot)...])
        guard day.count == 10 else { return nil }
        return (id, DayKey(rawValue: day))
    }

    static func alerts(for habits: [HabitReminderInput], now: Date, calendar: Calendar,
                       daysAhead: Int = daysAhead, limit: Int = limit) -> [HabitAlert] {
        let cal = HabitCalendar(calendar)
        let today = DayKey(now, calendar: calendar)
        var result: [HabitAlert] = []
        for habit in habits {
            var announced = false
            for offset in 0..<max(0, daysAhead) {
                let day = today.adding(days: offset, calendar: calendar)
                guard !habit.kept.contains(day), habit.schedule.isDue(on: day, calendar: cal),
                      let start = day.startDate(calendar: calendar),
                      let fire = calendar.date(bySettingHour: habit.hour, minute: habit.minute, second: 0, of: start),
                      fire > now else { continue }
                if case let .timesPerWeek(target) = habit.schedule.cadence {
                    let week = Set(cal.week(of: day))
                    if habit.kept.intersection(week).count >= target { continue }
                }
                let streak = !announced && day == today && habit.streak > 0 ? habit.streak : nil
                announced = true
                result.append(HabitAlert(habitID: habit.id, title: habit.title, day: day, fireDate: fire,
                                         streak: streak, countsWeeks: habit.countsWeeks))
            }
        }
        result.sort { ($0.fireDate, $0.title) < ($1.fireDate, $1.title) }
        return Array(result.prefix(max(0, limit)))
    }
}
