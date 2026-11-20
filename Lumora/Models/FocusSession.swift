import Foundation
import SwiftData

/// How a focus session ended.
enum SessionOutcome: String, Codable, Sendable {
    /// Ran to zero.
    case completed
    /// Ended by the user (or auto-ended after a long pause) after the
    /// qualifying minimum: still earns a smaller star.
    case endedEarly
    /// Ended before the qualifying minimum. Recorded for honesty, no reward.
    case tooShort

    var earnsStar: Bool { self != .tooShort }
}

/// One focus session in history. Created exactly once per timer segment;
/// `id` equals the timer segment identifier, which is how duplicate
/// completion records are prevented.
///
/// All properties have defaults and relationships are optional so the schema
/// stays compatible with a future CloudKit-backed configuration (CloudKit does
/// not support unique constraints, so uniqueness is enforced by `RewardService`).
@Model
final class FocusSession {
    var id: UUID = UUID()
    var startedAt: Date = Date.distantPast
    var endedAt: Date = Date.distantPast
    var plannedSeconds: Int = 0
    var focusedSeconds: Int = 0
    var pausedSeconds: Int = 0
    var pauseCount: Int = 0
    var categoryRaw: String = FocusCategory.work.rawValue
    var intention: String = ""
    var note: String = ""
    var outcomeRaw: String = SessionOutcome.completed.rawValue
    /// Local calendar day at completion, in the time zone of that moment.
    var dayKeyRaw: String = ""
    var timeZoneID: String = ""
    /// Star number earned by this session, or 0 when none.
    var starNumber: Int = 0
    var task: FocusTask?

    init(id: UUID, startedAt: Date, endedAt: Date, plannedSeconds: Int, focusedSeconds: Int,
         pausedSeconds: Int, pauseCount: Int, category: FocusCategory, intention: String,
         outcome: SessionOutcome, dayKey: DayKey, timeZoneID: String) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSeconds = plannedSeconds
        self.focusedSeconds = focusedSeconds
        self.pausedSeconds = pausedSeconds
        self.pauseCount = pauseCount
        self.categoryRaw = category.rawValue
        self.intention = intention
        self.outcomeRaw = outcome.rawValue
        self.dayKeyRaw = dayKey.rawValue
        self.timeZoneID = timeZoneID
    }

    var category: FocusCategory { FocusCategory(storedValue: categoryRaw) }
    var outcome: SessionOutcome { SessionOutcome(rawValue: outcomeRaw) ?? .completed }
    var dayKey: DayKey { DayKey(rawValue: dayKeyRaw) }
    var focusedMinutes: Int { focusedSeconds / 60 }
    var qualifies: Bool { outcome.earnsStar }
}
