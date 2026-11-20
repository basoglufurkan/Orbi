import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity payload for an in-progress focus session or break.
///
/// Remaining time is rendered by the system from `endDate`
/// (`Text(timerInterval:)`), so the activity stays correct without the app
/// running. Updates are only sent on state changes (pause, resume, break).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Mode: String, Codable, Hashable, Sendable {
            case focusing, paused, onBreak, complete
        }

        var mode: Mode
        /// Effective start: `endDate - plannedDuration` (shifted by pauses).
        var startDate: Date
        var endDate: Date
        /// Frozen remaining seconds while paused.
        var pausedRemaining: TimeInterval?
        /// Frozen progress (0...1) while paused.
        var pausedProgress: Double?
        /// The day plan's next block, if one is coming.
        var nextBlockTitle: String? = nil
        var nextBlockStart: Date? = nil
    }

    var categoryRaw: String
    var intention: String
    var starNumber: Int
}
#endif
