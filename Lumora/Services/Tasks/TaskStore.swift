import Foundation
import SwiftData
import os

/// The editable fields of a planned task, as the add/edit sheet holds them.
struct TaskDraft: Equatable, Sendable {
    var title = ""
    var category: FocusCategory = .work
    var notes = ""
    var estimatedSessions = 2
    var dueDate: Date?
    var listName = ""
    /// Set when the task is a block on a day's plan.
    var schedule: BlockSchedule?

    static let estimateRange = 1...12

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedTitle.isEmpty }

    init() {}

    init(_ task: FocusTask) {
        title = task.title
        category = task.category
        notes = task.notes
        estimatedSessions = task.estimatedSessions > 0 ? task.estimatedSessions : 1
        dueDate = task.dueDate
        listName = task.listName
        if let start = task.scheduledStart {
            schedule = BlockSchedule(start: start, minutes: max(BlockSchedule.minuteRange.lowerBound, task.scheduledMinutes),
                                     reminders: task.planReminders)
        }
    }
}

/// All writes to planned tasks. Sessions are linked to tasks by
/// `RewardService`; this service never touches sessions or rewards.
@MainActor
final class TaskStore {
    private let context: ModelContext
    private let clock: DateProvider
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Tasks")
    /// Called after every saved change, so the day plan's reminders, alarms
    /// and widgets follow (set by the app model).
    var didSave: (() -> Void)?

    init(context: ModelContext, clock: DateProvider) {
        self.context = context
        self.clock = clock
    }

    var planner: TaskPlanner { TaskPlanner(calendar: clock.calendar, now: clock.now) }

    @discardableResult
    func create(_ draft: TaskDraft) -> FocusTask {
        let task = FocusTask(title: draft.trimmedTitle, category: draft.category, now: clock.now)
        task.isPlanned = true
        task.sortOrder = nextSortOrder()
        apply(draft, to: task)
        context.insert(task)
        save()
        Telemetry.log(.taskCreated(hasDueDate: draft.dueDate != nil, sessions: draft.estimatedSessions))
        return task
    }

    func update(_ task: FocusTask, with draft: TaskDraft) {
        task.title = draft.trimmedTitle
        task.categoryRaw = draft.category.rawValue
        // Editing an implicit intention adds it to the plan.
        if !task.isPlanned {
            task.isPlanned = true
            task.sortOrder = nextSortOrder()
        }
        apply(draft, to: task)
        save()
    }

    func setCompleted(_ task: FocusTask, _ completed: Bool, viaFocus: Bool = false) {
        if completed, !task.isCompleted { Telemetry.log(.taskCompleted(viaFocus: viaFocus)) }
        task.isCompleted = completed
        task.completedAt = completed ? clock.now : nil
        // A reopened task returns to the end of its section.
        if !completed { task.sortOrder = nextSortOrder() }
        save()
    }

    func setCompleted(taskID: UUID, _ completed: Bool) {
        guard let task = fetch(id: taskID) else { return }
        setCompleted(task, completed, viaFocus: true)
    }

    /// Hides the task from the list and from suggestions; its sessions and
    /// stars are untouched.
    func archive(_ task: FocusTask) {
        Telemetry.log(.taskArchived)
        task.isArchived = true
        save()
    }

    /// Applies a List `onMove` within one section's rows (in display order).
    func move(_ rows: [FocusTask], from source: IndexSet, to destination: Int) {
        let orders = TaskPlanner.reorder(ids: rows.map(\.id), orders: rows.map(\.sortOrder),
                                         moving: source, to: destination)
        for task in rows { if let order = orders[task.id] { task.sortOrder = order } }
        save()
    }

    // MARK: Day plan

    /// Planned tasks with a time whose block begins in `[start, end)`, in order.
    func scheduledTasks(from start: Date, to end: Date) -> [FocusTask] {
        let d = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.isPlanned && !$0.isArchived && $0.scheduledStart != nil })
        return ((try? context.fetch(d)) ?? [])
            .filter { task in task.scheduledStart.map { $0 >= start && $0 < end } ?? false }
            .sorted { a, b in
                guard let pa = a.planBlock, let pb = b.planBlock else { return false }
                return PlanBlock.chronological(pa, pb)
            }
    }

    /// Planned, unfinished tasks without a time: the ones a day can take in.
    func unscheduledTasks() -> [FocusTask] {
        let d = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.isPlanned && !$0.isArchived && !$0.isCompleted },
                                           sortBy: [SortDescriptor(\.sortOrder)])
        return ((try? context.fetch(d)) ?? []).filter { $0.scheduledStart == nil }
    }

    /// Moves blocks to new starts (reordering, running late); each keeps its length.
    func reschedule(_ starts: [UUID: Date]) {
        guard !starts.isEmpty else { return }
        for (id, start) in starts {
            guard let task = fetch(id: id), task.scheduledStart != nil else { continue }
            let start = Self.wholeMinute(start)
            task.scheduledStart = start
            task.dueDate = clock.calendar.startOfDay(for: start)
        }
        save()
    }

    /// Takes the block off its day's plan; the task stays in the list, on that day.
    func unschedule(_ task: FocusTask) {
        task.scheduledStart = nil
        task.scheduledMinutes = 0
        save()
    }

    func fetch(id: UUID) -> FocusTask? {
        var d = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    // MARK: Private

    private func apply(_ draft: TaskDraft, to task: FocusTask) {
        task.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.estimatedSessions = min(TaskDraft.estimateRange.upperBound, max(0, draft.estimatedSessions))
        task.dueDate = draft.dueDate.map { clock.calendar.startOfDay(for: $0) }
        task.listName = draft.listName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schedule = draft.schedule {
            let start = Self.wholeMinute(schedule.start)
            task.scheduledStart = start
            task.scheduledMinutes = min(BlockSchedule.minuteRange.upperBound,
                                        max(BlockSchedule.minuteRange.lowerBound, schedule.minutes))
            task.remindBeforeMinutes = max(0, schedule.reminders.beforeMinutes)
            task.remindAtStart = schedule.reminders.atStart
            task.alarmAtStart = schedule.reminders.alarm
            // A block's day is its due day, so it sits in Today or Upcoming with the rest.
            task.dueDate = clock.calendar.startOfDay(for: start)
        } else {
            task.scheduledStart = nil
            task.scheduledMinutes = 0
        }
    }

    /// Plan times keep whole minutes.
    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    private func nextSortOrder() -> Double {
        var d = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.isPlanned },
                                           sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        d.fetchLimit = 1
        return ((try? context.fetch(d).first?.sortOrder) ?? 0) + 1
    }

    private func save() {
        do {
            guard context.hasChanges else { return }
            try context.save()
            didSave?()
        } catch {
            logger.error("Task save failed: \(error.localizedDescription)")
        }
    }
}
