import ActivityKit
import Foundation
import os

/// Lock Screen / Dynamic Island presence for focus sessions and breaks.
///
/// Updates are sent only on state changes (start, pause, resume, break, end);
/// countdowns render from dates via `Text(timerInterval:)`, so no per-second
/// updates and no assumption of background execution. `staleDate` is the
/// deadline, so a session that finishes while suspended reads as complete.
///
/// `Activity` is not `Sendable`, so this service tracks activities by ID and
/// resolves them inside detached tasks rather than passing them across actors.
@MainActor
final class LiveActivityService {
    private typealias Content = ActivityContent<FocusActivityAttributes.ContentState>

    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "LiveActivity")
    private var activityID: String?
    private var activityCategory: String?

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    /// The day plan's next block, shown beneath the countdown (set by the app model).
    var nextBlock: (() -> PlanBlock?)?

    func begin(segment: TimerSegment, starNumber: Int, now: Date) {
        guard isAvailable else { return }
        let content = Self.content(for: segment, now: now, next: nextBlock?())
        let category = segment.focus?.category.rawValue ?? "break"
        if activityID != nil {
            if activityCategory == category {
                update(content)
                return
            }
            end()
        }
        let attributes = FocusActivityAttributes(categoryRaw: category,
                                                 intention: segment.focus?.intention ?? "",
                                                 starNumber: starNumber)
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activityID = activity.id
            activityCategory = category
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription)")
        }
    }

    func refresh(segment: TimerSegment, now: Date) {
        update(Self.content(for: segment, now: now, next: nextBlock?()))
    }

    /// Ends the activity, optionally leaving a final "complete" state visible briefly.
    func end(completedFrom start: Date? = nil, to end: Date? = nil) {
        guard let id = activityID else { return }
        activityID = nil
        activityCategory = nil
        var finalContent: Content?
        if let start, let end {
            let state = FocusActivityAttributes.ContentState(
                mode: .complete, startDate: start, endDate: end, pausedRemaining: 0, pausedProgress: 1)
            finalContent = ActivityContent(state: state, staleDate: nil)
        }
        let content = finalContent
        Self.withActivity(id: id) { activity in
            await activity.end(content, dismissalPolicy: content == nil ? .immediate : .after(.now + 90))
        }
    }

    /// Reconnects to (or removes) activities left over from a previous process.
    func endOrphans(keeping segmentActive: Bool) {
        let existing = Activity<FocusActivityAttributes>.activities
        if segmentActive, let first = existing.first {
            activityID = first.id
            activityCategory = first.attributes.categoryRaw
            return
        }
        activityID = nil
        activityCategory = nil
        Task.detached {
            for orphan in Activity<FocusActivityAttributes>.activities {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func update(_ content: Content) {
        guard let id = activityID else { return }
        Self.withActivity(id: id) { activity in
            await activity.update(content)
        }
    }

    private nonisolated static func withActivity(
        id: String, _ body: @escaping @Sendable (Activity<FocusActivityAttributes>) async -> Void
    ) {
        Task.detached {
            for activity in Activity<FocusActivityAttributes>.activities where activity.id == id {
                await body(activity)
            }
        }
    }

    static func content(for segment: TimerSegment, now: Date,
                        next: PlanBlock? = nil) -> ActivityContent<FocusActivityAttributes.ContentState> {
        let mode: FocusActivityAttributes.ContentState.Mode =
            segment.kind.isBreak ? .onBreak : (segment.isPaused ? .paused : .focusing)
        let end = segment.deadline ?? segment.projectedDeadline(resumingAt: now)
        let start = end.addingTimeInterval(-Double(segment.plannedSeconds) / segment.timeScale)
        // Wall-clock seconds, matching the running countdown (differs only under debug time-scale).
        let state = FocusActivityAttributes.ContentState(
            mode: mode, startDate: start, endDate: end,
            pausedRemaining: segment.isPaused ? segment.remaining(at: now) / segment.timeScale : nil,
            pausedProgress: segment.isPaused ? segment.progress(at: now) : nil,
            nextBlockTitle: next?.title, nextBlockStart: next?.start)
        return ActivityContent(state: state, staleDate: segment.isPaused ? nil : end)
    }
}
