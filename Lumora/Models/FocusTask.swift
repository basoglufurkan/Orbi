import Foundation
import SwiftData

/// Something the user focuses on ("Essay draft"), with its category.
///
/// Two kinds share this model: intentions remembered implicitly from the
/// setup screen's free text, and tasks planned on the Tasks screen
/// (`isPlanned`). Progress (sessions done, focused minutes) is never stored
/// here; it is derived from the linked `sessions` (see `TaskProgress`).
///
/// Every property has a default so additions stay lightweight migrations and
/// the model stays CloudKit-compatible.
@Model
final class FocusTask {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = FocusCategory.work.rawValue
    var createdAt: Date = Date.distantPast
    var lastUsedAt: Date = Date.distantPast
    var isArchived: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.task)
    var sessions: [FocusSession]? = []

    // Planning (schema 1.1)
    /// Created on the Tasks screen, so it appears in the task list.
    var isPlanned: Bool = false
    var notes: String = ""
    /// Planned focus sessions (pomodoros); 0 means no estimate.
    var estimatedSessions: Int = 0
    var dueDate: Date?
    var isCompleted: Bool = false
    var completedAt: Date?
    /// Manual order within the task list; lower comes first.
    var sortOrder: Double = 0
    /// Optional project or list name ("Thesis"); empty means none.
    var listName: String = ""

    // Day plan (schema 1.6)
    /// Set when the task is a block on a day's plan: when it begins.
    var scheduledStart: Date?
    /// The block's length in minutes; meaningful only with `scheduledStart`.
    var scheduledMinutes: Int = 0
    /// A reminder this many minutes before the block begins; 0 means none.
    var remindBeforeMinutes: Int = 10
    /// A notification when the block begins.
    var remindAtStart: Bool = true
    /// An alarm (AlarmKit, iOS 26.1+) when the block begins.
    var alarmAtStart: Bool = false

    init(title: String, category: FocusCategory, now: Date) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.createdAt = now
        self.lastUsedAt = now
    }

    var category: FocusCategory { FocusCategory(storedValue: categoryRaw) }

    var progress: TaskProgress { TaskProgress(sessions: sessions ?? [], estimate: estimatedSessions) }

    /// The task as a block on its day's plan, when it has a time.
    var planBlock: PlanBlock? {
        guard let scheduledStart else { return nil }
        return PlanBlock(id: id, title: title, categoryRaw: categoryRaw, start: scheduledStart,
                         minutes: max(BlockSchedule.minuteRange.lowerBound, scheduledMinutes), isCompleted: isCompleted)
    }

    var planReminders: PlanReminderSettings {
        PlanReminderSettings(beforeMinutes: remindBeforeMinutes, atStart: remindAtStart, alarm: alarmAtStart)
    }
}

/// Derived progress for a task: only star-earning sessions count.
struct TaskProgress: Equatable, Sendable {
    var sessionsDone: Int
    var focusedMinutes: Int
    var estimate: Int

    init(sessionsDone: Int, focusedMinutes: Int, estimate: Int) {
        self.sessionsDone = sessionsDone
        self.focusedMinutes = focusedMinutes
        self.estimate = estimate
    }

    init(sessions: [FocusSession], estimate: Int) {
        let counted = sessions.filter(\.qualifies)
        self.init(sessionsDone: counted.count,
                  focusedMinutes: counted.reduce(0) { $0 + $1.focusedSeconds } / 60,
                  estimate: max(0, estimate))
    }

    var hasEstimate: Bool { estimate > 0 }
    var reachedEstimate: Bool { hasEstimate && sessionsDone >= estimate }
    /// 0…1 toward the estimate; 0 without one.
    var fraction: Double { hasEstimate ? min(1, Double(sessionsDone) / Double(estimate)) : 0 }
}
