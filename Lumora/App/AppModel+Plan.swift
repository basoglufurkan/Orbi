import Foundation

/// A focus session asked for from a plan block.
struct PlanFocusRequest: Equatable, Sendable {
    var blockID: UUID
    /// nil means the usual length (capped by what's left of the block).
    var minutes: Int?
    var source: String
}

/// The day plan's side of the app model: keeping reminders, alarms, widgets
/// and the Live Activity in step with the planned blocks, and starting a
/// focus from a block in one tap.
extension AppModel {
    /// How many days ahead reminders and alarms are prepared.
    static let planHorizonDays = 8

    var planner: DayPlanner { DayPlanner(calendar: clock.calendar, now: clock.now) }

    /// Blocks from the start of today through `days` days.
    func planBlocks(days: Int = 1) -> [PlanBlock] {
        let cal = clock.calendar
        let start = cal.startOfDay(for: clock.now)
        let end = cal.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400)
        return tasks.scheduledTasks(from: start, to: end).compactMap(\.planBlock)
    }

    /// Reschedules the plan's notifications and alarms and refreshes the
    /// widgets. Cheap enough to call after every task change.
    func syncPlan() {
        let cal = clock.calendar, now = clock.now
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: Self.planHorizonDays, to: start) ?? now
        let items = tasks.scheduledTasks(from: start, to: end).compactMap { task in
            task.planBlock.map { (block: $0, reminders: task.planReminders) }
        }
        let alarms = planAlarms
        let alerts = PlanReminderPlanner.alerts(for: items, now: now, alarmsActive: alarms.isAuthorized)
        let wantedAlarms = PlanReminderPlanner.alarms(for: items, now: now)
        Task { [notifications] in await notifications.updatePlanReminders(alerts, calendar: cal) }
        Task { await alarms.sync(wantedAlarms) }
        widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
    }

    /// The next block not yet begun, today or tomorrow (for the Live Activity).
    func nextPlanBlock() -> PlanBlock? {
        DayTimeline(blocks: planBlocks(days: 2), now: clock.now).next
    }

    /// Today's and tomorrow's blocks, for the widgets.
    func widgetPlanBlocks() -> [PlanBlock] {
        Array(planBlocks(days: 2).prefix(24))
    }

    /// Starts focusing on a block. From a plan screen it waits until that
    /// screen has gone, because the focus flow is a full-screen cover.
    func requestPlanFocus(_ blockID: UUID, minutes: Int? = nil, source: String = "plan") {
        let request = PlanFocusRequest(blockID: blockID, minutes: minutes, source: source)
        if isShowingDayOrbit || isShowingPlanner || isShowingTasks || isShowingSettings || isShowingHabits {
            pendingPlanFocus = request
            isShowingDayOrbit = false
            isShowingPlanner = false
            isShowingTasks = false
            isShowingSettings = false
            isShowingHabits = false
        } else {
            startPlanFocus(request)
        }
    }

    /// Called when a plan screen has finished closing.
    func runPendingPlanFocus() {
        guard let request = pendingPlanFocus else { return }
        pendingPlanFocus = nil
        // The cover can only appear once the dismissal has fully settled.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.startPlanFocus(request)
        }
    }

    private func startPlanFocus(_ request: PlanFocusRequest) {
        guard preferences.hasCompletedOnboarding, !timer.state.phase.isFocusActive,
              timer.state.pendingResult == nil,
              let task = tasks.fetch(id: request.blockID), let block = task.planBlock else { return }
        let planner = self.planner
        let minutes = request.minutes ?? planner.focusMinutes(for: block, usual: preferences.defaultFocusMinutes)
        Telemetry.log(.planFocusStarted(minutes: minutes, during: block.contains(clock.now), source: request.source))
        focusSource = "plan"
        showBreakComplete = false
        let prefs = preferences
        prefs.lastCategory = task.category
        dataStore.save()
        timer.start(FocusConfiguration(plannedSeconds: minutes * 60, category: task.category,
                                       intention: task.title, taskID: task.id))
    }
}
