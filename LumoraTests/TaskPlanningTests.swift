import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Tasks: derived progress, completion, ordering, session linking")
@MainActor
struct TaskPlanningTests {
    let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)

    func make() throws -> (TaskStore, RewardService, ModelContext) {
        let context = try TestFixtures.makeContext()
        return (TaskStore(context: context, clock: clock),
                RewardService(context: context, clock: clock, goalMinutes: { 120 }), context)
    }

    func draft(_ title: String, estimate: Int = 3, due: Date? = nil, category: FocusCategory = .creative) -> TaskDraft {
        var d = TaskDraft()
        d.title = title
        d.category = category
        d.estimatedSessions = estimate
        d.dueDate = due
        return d
    }

    func result(for task: FocusTask, start: Date, focusedMinutes: Int? = nil, reason: FocusEndReason = .completed) -> FocusResult {
        var r = TestFixtures.result(start: start, focusedMinutes: focusedMinutes, category: task.category,
                                    reason: reason, intention: task.title)
        r.configuration.taskID = task.id
        return r
    }

    // MARK: Derived progress

    @Test func progressCountsOnlyStarEarningSessions() {
        let p = TaskProgress(sessionsDone: 2, focusedMinutes: 50, estimate: 4)
        #expect(p.fraction == 0.5)
        #expect(!p.reachedEstimate)
        #expect(TaskProgress(sessionsDone: 4, focusedMinutes: 100, estimate: 4).reachedEstimate)
        #expect(!TaskProgress(sessionsDone: 7, focusedMinutes: 0, estimate: 0).reachedEstimate)
        #expect(TaskProgress(sessionsDone: 7, focusedMinutes: 0, estimate: 0).fraction == 0)
    }

    @Test func linkingASessionByTaskIDUpdatesProgress() throws {
        let (store, rewards, _) = try make()
        let task = store.create(draft("Essay draft", estimate: 4))
        #expect(task.progress == TaskProgress(sessionsDone: 0, focusedMinutes: 0, estimate: 4))

        let first = try rewards.record(result(for: task, start: TestFixtures.baseDate))
        #expect(task.progress == TaskProgress(sessionsDone: 1, focusedMinutes: 25, estimate: 4))
        #expect(first.task == TaskSnapshot(id: task.id, title: "Essay draft", category: .creative,
                                           progress: TaskProgress(sessionsDone: 1, focusedMinutes: 25, estimate: 4),
                                           isCompleted: false))

        // Ended early still counts; too short doesn't.
        let second = try rewards.record(result(for: task, start: TestFixtures.baseDate.addingTimeInterval(3600),
                                               focusedMinutes: 10, reason: .endedByUser))
        #expect(second.task?.progress.sessionsDone == 2)
        let third = try rewards.record(result(for: task, start: TestFixtures.baseDate.addingTimeInterval(7200),
                                              focusedMinutes: 2, reason: .endedByUser))
        #expect(third.outcome == .tooShort)
        #expect(task.progress == TaskProgress(sessionsDone: 2, focusedMinutes: 35, estimate: 4))
        #expect(task.sessions?.count == 3)
    }

    @Test func linkingByTaskIDWinsOverAnEditedIntention() throws {
        let (store, rewards, context) = try make()
        let task = store.create(draft("Essay draft"))
        var r = result(for: task, start: TestFixtures.baseDate)
        r.configuration.intention = "Essay draft, intro only"
        _ = try rewards.record(r)
        #expect(task.progress.sessionsDone == 1)
        #expect(try context.fetch(FetchDescriptor<FocusTask>()).count == 1)
    }

    @Test func recordingTwiceStaysExactlyOnceForTheTask() throws {
        let (store, rewards, context) = try make()
        let task = store.create(draft("Essay draft", estimate: 2))
        let r = result(for: task, start: TestFixtures.baseDate)
        let a = try rewards.record(r)
        let b = try rewards.record(r)
        #expect(a == b)
        #expect(task.progress.sessionsDone == 1)
        // Reconstructed after a relaunch, the summary shows the same progress.
        let fresh = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        #expect(fresh.reward(for: r.segmentID)?.task == a.task)
    }

    @Test func implicitIntentionsHaveNoTaskCard() throws {
        let (_, rewards, _) = try make()
        let reward = try rewards.record(TestFixtures.result(start: TestFixtures.baseDate, intention: "Deep work"))
        #expect(reward.task == nil)
    }

    @Test func summaryReportsWhenTheEstimateIsReached() throws {
        let (store, rewards, _) = try make()
        let task = store.create(draft("Sketch", estimate: 1))
        let reward = try rewards.record(result(for: task, start: TestFixtures.baseDate))
        #expect(reward.task?.progress.reachedEstimate == true)
        #expect(reward.task?.isCompleted == false)
    }

    // MARK: Completion

    @Test func completingAndReopening() throws {
        let (store, _, _) = try make()
        let task = store.create(draft("Essay draft"))
        let other = store.create(draft("Read chapter"))
        clock.advance(by: 600)
        store.setCompleted(task, true)
        #expect(task.isCompleted)
        #expect(task.completedAt == clock.now)
        #expect(store.planner.section(of: task) == .completed)

        store.setCompleted(taskID: task.id, false)
        #expect(!task.isCompleted)
        #expect(task.completedAt == nil)
        // Reopened tasks go to the end of Today.
        #expect(store.planner.arrange([task, other])[.today]?.map(\.title) == ["Read chapter", "Essay draft"])
    }

    @Test func archivingKeepsSessions() throws {
        let (store, rewards, context) = try make()
        let task = store.create(draft("Essay draft"))
        _ = try rewards.record(result(for: task, start: TestFixtures.baseDate))
        store.archive(task)
        #expect(task.isArchived)
        #expect(try context.fetch(FetchDescriptor<FocusSession>()).first?.task?.id == task.id)
    }

    // MARK: Sections and ordering

    @Test func sectionsByDueDayWithoutOverdue() throws {
        let (store, _, _) = try make()
        let cal = clock.calendar
        let yesterday = cal.date(byAdding: .day, value: -1, to: clock.now)!
        let tonight = cal.date(bySettingHour: 23, minute: 30, second: 0, of: clock.now)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: clock.now)!
        let nextWeek = cal.date(byAdding: .day, value: 7, to: clock.now)!

        let anytime = store.create(draft("Anytime"))
        let late = store.create(draft("Carried over", due: yesterday))
        let today = store.create(draft("Tonight", due: tonight))
        let later = store.create(draft("Next week", due: nextWeek))
        let soon = store.create(draft("Tomorrow", due: tomorrow))

        let planner = store.planner
        #expect(planner.section(of: anytime) == .today)
        #expect(planner.section(of: late) == .today)
        #expect(planner.section(of: today) == .today)
        let arranged = planner.arrange([anytime, late, today, later, soon])
        #expect(arranged[.today]?.map(\.title) == ["Anytime", "Carried over", "Tonight"])
        // Upcoming is chronological, regardless of creation order.
        #expect(arranged[.upcoming]?.map(\.title) == ["Tomorrow", "Next week"])
        // Due dates are stored as the start of their day.
        #expect(today.dueDate == cal.startOfDay(for: tonight))

        // When the day comes, an upcoming task moves into Today.
        clock.advance(by: 86_400)
        #expect(store.planner.section(of: soon) == .today)
    }

    @Test func newTasksAppendAndManualMovesReorder() throws {
        let (store, _, _) = try make()
        let a = store.create(draft("A")), b = store.create(draft("B")), c = store.create(draft("C"))
        #expect(a.sortOrder < b.sortOrder && b.sortOrder < c.sortOrder)

        // Drag C to the top.
        store.move([a, b, c], from: IndexSet(integer: 2), to: 0)
        #expect(store.planner.arrange([a, b, c])[.today]?.map(\.title) == ["C", "A", "B"])
        // Drag C (now first) below B.
        store.move([c, a, b], from: IndexSet(integer: 0), to: 3)
        #expect(store.planner.arrange([a, b, c])[.today]?.map(\.title) == ["A", "B", "C"])
    }

    @Test func reorderSpreadsTiesAndKeepsSlots() {
        let ids = (0..<3).map { _ in UUID() }
        let tied = TaskPlanner.reorder(ids: ids, orders: [0, 0, 0], moving: IndexSet(integer: 0), to: 3)
        #expect(tied[ids[1]] == 0 && tied[ids[2]] == 1 && tied[ids[0]] == 2)

        // A section reuses its own order values, so other sections keep theirs.
        let kept = TaskPlanner.reorder(ids: ids, orders: [2, 5, 9], moving: IndexSet(integer: 1), to: 0)
        #expect(kept[ids[1]] == 2 && kept[ids[0]] == 5 && kept[ids[2]] == 9)
    }

    @Test func draftsAreTrimmedAndClamped() throws {
        let (store, _, _) = try make()
        var d = draft("  Essay draft  ", estimate: 40)
        d.notes = "  outline first \n"
        d.listName = " Thesis "
        let task = store.create(d)
        #expect(task.title == "Essay draft")
        #expect(task.notes == "outline first")
        #expect(task.listName == "Thesis")
        #expect(task.estimatedSessions == TaskDraft.estimateRange.upperBound)
        #expect(task.isPlanned)
        #expect(!TaskDraft().isValid)
    }

    /// Compares against the localized strings, so it passes in any test language.
    @Test func dueLabelsStayGentle() {
        let cal = clock.calendar, now = clock.now
        let past = cal.date(byAdding: .day, value: -2, to: now)!
        #expect(TaskFormat.due(now, now: now, calendar: cal) == String(localized: "Today"))
        #expect(TaskFormat.due(cal.date(byAdding: .day, value: 1, to: now)!, now: now, calendar: cal) == String(localized: "Tomorrow"))
        #expect(TaskFormat.due(past, now: now, calendar: cal) == String(localized: "Since \(LMFormat.shortDate(past))"))
        #expect(TaskFormat.sessions(TaskProgress(sessionsDone: 2, focusedMinutes: 50, estimate: 4)) == String(localized: "\(2) of \(4) sessions"))
        #expect(TaskFormat.sessions(TaskProgress(sessionsDone: 0, focusedMinutes: 0, estimate: 0)) == String(localized: "No sessions yet"))
    }
}
