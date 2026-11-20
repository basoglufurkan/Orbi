#if DEBUG
import Foundation

/// Debug-only: fills the universe with realistic history by sending synthetic
/// results through the real `RewardService`, so previews and screenshots
/// exercise exactly the production reward path.
@MainActor
enum DemoDataSeeder {
    static func seed(sessions count: Int, into app: AppModel) {
        guard count > 0 else { return }
        let cal = app.clock.calendar
        let now = app.clock.now
        let durations = [25, 25, 45, 15, 25, 60, 25, 45]
        // Sample history reads naturally in Turkish screenshots too.
        let intentions = Locale.current.language.languageCode == "tr"
            ? ["Kimlik modülünü düzenle", "İspanyolca 6. bölüm", "API testleri", "Eskiz defteri", "Tasarım incelemesi", "Derin çalışma", "Makale taslağı", ""]
            : ["Refactor auth module", "Spanish chapter 6", "API tests", "Sketchbook", "Design review", "Deep work", "Essay draft", ""]
        let days = max(1, count / 3)
        let created = cal.date(byAdding: .day, value: -(days + 1), to: now) ?? now
        app.dataStore.ensureUniverse(createdAt: created, calendar: cal)
        if let progress = app.dataStore.progress() { progress.createdAt = min(progress.createdAt, created) }

        var produced = 0
        var day = days
        while produced < count, day >= 0 {
            guard let dayStart = cal.date(byAdding: .day, value: -day, to: cal.startOfDay(for: now)) else { break }
            // Every 6th day is a rest day; most days have 2–4 sessions.
            let perDay = day % 6 == 5 ? 0 : 2 + (day * 7 + 3) % 3
            for k in 0..<perDay where produced < count {
                let minutes = durations[(produced + day) % durations.count]
                let start = dayStart.addingTimeInterval(TimeInterval(9 * 3600 + k * 5400))
                guard start.addingTimeInterval(TimeInterval(minutes * 60)) < now else { continue }
                let config = FocusConfiguration(plannedSeconds: minutes * 60,
                                                category: FocusCategory.allCases[(produced * 3 + day) % 5],
                                                intention: intentions[(produced + k) % intentions.count])
                let result = FocusResult(segmentID: UUID(), configuration: config, startedAt: start,
                                         endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                         plannedSeconds: minutes * 60, focusedSeconds: minutes * 60,
                                         pausedSeconds: 0, pauseCount: 0, endReason: .completed)
                _ = try? app.rewards.record(result)
                produced += 1
            }
            day -= 1
        }
        app.dataStore.save()
    }

    /// A day plan around now, in every state: a lit stop, a passed one, one
    /// under way and a few ahead (`-lumora-demo-plan`). Skipped once today has blocks.
    static func seedPlan(into app: AppModel) {
        let cal = app.clock.calendar
        let now = app.clock.now
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
        guard app.tasks.scheduledTasks(from: dayStart, to: dayEnd).isEmpty else { return }
        let base = app.planner.roundedUp(now).addingTimeInterval(-15 * 60)
        let turkish = Locale.current.language.languageCode == "tr"
        let plan: [(String, String, FocusCategory, Double, Int, Bool, Bool)] = [
            ("Morning pages", "Sabah sayfaları", .creative, -180, 30, true, false),
            ("Call with Ece", "Ece ile görüşme", .work, -120, 30, false, false),
            ("Write the report", "Raporu yaz", .work, -30, 90, false, false),
            ("Training", "Spor", .study, 105, 60, false, true),
            ("Read a chapter", "Bir bölüm oku", .reading, 225, 45, false, false),
            ("Evening review", "Akşam değerlendirmesi", .creative, 330, 20, false, false),
        ]
        for (english, local, category, offset, minutes, lit, alarm) in plan {
            var draft = TaskDraft()
            draft.title = turkish ? local : english
            draft.category = category
            draft.estimatedSessions = DayPlanner.estimatedSessions(minutes: minutes, focusMinutes: 25)
            draft.schedule = BlockSchedule(start: base.addingTimeInterval(offset * 60), minutes: minutes,
                                           reminders: PlanReminderSettings(beforeMinutes: 10, atStart: true, alarm: alarm))
            let task = app.tasks.create(draft)
            if lit { app.tasks.setCompleted(task, true) }
        }
    }
    /// A few habits with weeks of history, at every brightness (`-lumora-demo-habits`).
    /// Skipped once there are habits.
    static func seedHabits(into app: AppModel) {
        guard app.habits.activeHabits().isEmpty else { return }
        let cal = app.clock.calendar
        let today = DayKey(app.clock.now, calendar: cal)
        let turkish = Locale.current.language.languageCode == "tr"
        // (title, symbol, hue, cadence, focus minutes, days ago it began, days missed (ago), kept today)
        let habits: [(String, String, String, FocusCategory, HabitCadence, Int, Int, Set<Int>, Bool)] = [
            ("Read 20 minutes", "20 dakika oku", "book.fill", .reading, .daily, 20, 80, [41, 40, 12], true),
            ("Meditate", "Meditasyon", "figure.mind.and.body", .coding, .daily, 0, 30, [9], false),
            ("Move your body", "Hareket et", "figure.walk", .study, .timesPerWeek(4), 0, 50, [], false),
            ("Journal", "Günlük yaz", "pencil.and.scribble", .creative, .weekdays([2, 3, 4, 5, 6]), 0, 25, [3], true),
            ("Learn Spanish", "İspanyolca çalış", "character.book.closed.fill", .work, .daily, 15, 8, [], false),
        ]
        for (english, local, symbol, hue, cadence, focus, began, missed, keptToday) in habits {
            var draft = HabitDraft()
            draft.title = turkish ? local : english
            draft.symbol = symbol
            draft.hue = hue
            draft.cadence = cadence
            draft.focusMinutes = focus
            draft.focusCategory = focus > 0 ? hue : nil
            draft.reminderEnabled = false
            let habit = app.habits.create(draft)
            habit.startDayRaw = today.adding(days: -began, calendar: cal).rawValue
            let schedule = habit.schedule
            for ago in stride(from: began, through: 1, by: -1) {
                let day = today.adding(days: -ago, calendar: cal)
                guard !missed.contains(ago), schedule.isDue(on: day, calendar: HabitCalendar(cal)) else { continue }
                // A weekly habit: four days a week.
                if case .timesPerWeek = cadence, HabitCalendar(cal).weekday(of: day) % 2 == 1 { continue }
                let checkIn = HabitCheckIn(day: day, now: app.clock.now, source: "tap")
                app.dataStore.context.insert(checkIn)
                checkIn.habit = habit
            }
            if keptToday { app.habits.setKept(habit, on: today, true) }
        }
        app.dataStore.save()
    }
}
#endif
