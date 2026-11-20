import Foundation

/// Habits on the app model: reminders and widgets that follow every change,
/// focus sessions that keep focus-linked habits, and a focus started from a
/// habit in one tap.
extension AppModel {
    /// Reschedules habit reminders and refreshes the widgets. Cheap enough
    /// to call after every change.
    func syncHabits() {
        let now = clock.now, cal = clock.calendar
        let alerts = HabitReminderPlanner.alerts(for: habits.reminderInputs(), now: now, calendar: cal)
        Task { [notifications] in await notifications.updateHabitReminders(alerts, calendar: cal) }
        widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
    }

    /// A recorded session may have reached a focus-linked habit's minutes.
    func creditHabits(after reward: SessionReward) {
        let kept = habits.creditFocus()
        guard !kept.isEmpty else { return }
        habitsKeptByFocus[reward.sessionID] = kept.map(\.title)
    }

    /// Today's focus toward the habit, and how long a session should run to reach it.
    func habitFocusMinutes(for habit: Habit) -> Int {
        let left = habit.focusMinutes - habits.focusedMinutesToday(for: habit)
        let target = left > 0 ? left : max(habit.focusMinutes, preferences.defaultFocusMinutes)
        return min(FocusConfiguration.customRangeMinutes.upperBound,
                   max(FocusConfiguration.customRangeMinutes.lowerBound, target))
    }

    /// Starts focusing on a habit. From the Habits sheet it waits until the
    /// sheet has gone, because the focus flow is a full-screen cover.
    func requestHabitFocus(_ habitID: UUID, source: String = "habits") {
        if isShowingHabits || isShowingDayOrbit {
            pendingHabitFocus = habitID
            isShowingHabits = false
            isShowingDayOrbit = false
        } else {
            startHabitFocus(habitID, source: source)
        }
    }

    /// Called when the Habits sheet (or the orbit) has finished closing.
    func runPendingHabitFocus() {
        guard let id = pendingHabitFocus else { return }
        pendingHabitFocus = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.startHabitFocus(id, source: "habits")
        }
    }

    private func startHabitFocus(_ habitID: UUID, source: String) {
        guard preferences.hasCompletedOnboarding, !timer.state.phase.isFocusActive,
              timer.state.pendingResult == nil, let habit = habits.fetch(id: habitID) else { return }
        let category = habit.focusCategory ?? habit.hue
        focusSource = source == "habits" ? "habit" : source
        showBreakComplete = false
        timer.start(FocusConfiguration(plannedSeconds: habitFocusMinutes(for: habit) * 60, category: category,
                                       intention: habit.title, taskID: nil))
    }

    /// "Done" on a habit's reminder, or its widget button: keep that day.
    func keepHabit(_ habitID: UUID, day: DayKey? = nil, source: String) {
        guard let habit = habits.fetch(id: habitID) else { return }
        if habits.setKept(habit, on: day ?? habits.today, true, source: source) {
            haptics.success()
        }
    }
}
