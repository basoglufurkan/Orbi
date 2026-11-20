import Foundation
import SwiftData
import Testing
@testable import Lumora

/// 2026-10-20 in Istanbul, at `hour:minute`.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 20) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TestFixtures.istanbul
    return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func block(_ title: String, _ hour: Int, _ minute: Int = 0, minutes: Int = 60, done: Bool = false,
                   day: Int = 20, category: FocusCategory = .work) -> PlanBlock {
    PlanBlock(id: UUID(), title: title, categoryRaw: category.rawValue, start: at(hour, minute, day: day),
              minutes: minutes, isCompleted: done)
}

private var istanbulCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TestFixtures.istanbul
    return c
}

@Suite("Day plan: the timeline at a moment")
struct DayTimelineTests {
    let report = block("Write the report", 9, minutes: 90)   // 09:00–10:30
    let training = block("Training", 14)                     // 14:00–15:00
    let reading = block("Read", 20, minutes: 30)             // 20:00–20:30

    @Test func statusFollowsTheClockAndTheCheckmark() {
        let t = DayTimeline(blocks: [training, report, reading], now: at(9, 45))
        #expect(t.blocks.map(\.title) == ["Write the report", "Training", "Read"])
        #expect(t.status(of: report) == .active)
        #expect(t.status(of: training) == .upcoming)
        #expect(t.current == report)
        #expect(t.next == training)
        let left: TimeInterval = 45 * 60, until: TimeInterval = (4 * 60 + 15) * 60
        #expect(t.leftInCurrent == left)
        #expect(t.untilNext == until)
        #expect(t.progress(of: report) == 0.5)

        let later = DayTimeline(blocks: [report, training, reading], now: at(11))
        #expect(later.status(of: report) == .passed)
        #expect(later.current == nil)

        var lit = report
        lit.isCompleted = true
        let done = DayTimeline(blocks: [lit, training], now: at(9, 30))
        #expect(done.status(of: lit) == .lit)
        // A block lit early no longer counts as "now"; the plan points at what's next.
        #expect(done.current == nil)
        #expect(done.focus == training)
        #expect(done.litCount == 1)
        #expect(done.plannedMinutes == 150)
    }

    @Test func aDayIsCompleteWhenEveryStopIsLitOrBehind() {
        #expect(!DayTimeline(blocks: [], now: at(12)).isComplete)
        #expect(!DayTimeline(blocks: [report, training], now: at(12)).isComplete)
        #expect(DayTimeline(blocks: [report, training], now: at(15)).isComplete)
        var lit = training
        lit.isCompleted = true
        #expect(DayTimeline(blocks: [report, lit], now: at(11)).isComplete)
    }

    @Test func cursorApproachesWaitsAndTravels() {
        let blocks = [report, training, reading]
        // An hour or more before the first stop: at dawn. Half an hour before: halfway there.
        #expect(DayTimeline(blocks: blocks, now: at(7)).cursor == -1)
        #expect(DayTimeline(blocks: blocks, now: at(8, 30)).cursor == -0.5)
        // Inside a block: at its stop.
        #expect(DayTimeline(blocks: blocks, now: at(10)).cursor == 0)
        // Between blocks: in step with the free time (10:30 → 14:00 is 3.5 h).
        let between = DayTimeline(blocks: blocks, now: at(12, 15)).cursor
        #expect(abs(between - 0.5) < 0.0001)
        // After the last block: drifting home over an hour.
        #expect(DayTimeline(blocks: blocks, now: at(21)).cursor == 2.5)
        #expect(DayTimeline(blocks: blocks, now: at(23)).cursor == 3)
        #expect(DayTimeline(blocks: [], now: at(12)).cursor == 0)
    }

    @Test func aBlockLitEarlySendsTheCometOn() {
        var lit = report  // 09:00–10:30, lit at 09:45
        lit.isCompleted = true
        // Left behind from 09:00; Training starts at 14:00: 45 of 300 minutes travelled.
        let t = DayTimeline(blocks: [lit, training, reading], now: at(9, 45))
        #expect(abs(t.cursor - 0.15) < 0.0001)
        // The last block lit early drifts home from its start.
        var lastLit = reading
        lastLit.isCompleted = true
        #expect(DayTimeline(blocks: [report, training, lastLit], now: at(20, 30)).cursor == 2.5)
    }

    @Test func overlappingBlocksKeepTheCometAtTheOneStillRunning() {
        let long = block("Workshop", 9, minutes: 180)  // 09:00–12:00
        let short = block("Call", 10, minutes: 30)     // 10:00–10:30
        let t = DayTimeline(blocks: [long, short], now: at(11))
        // The call has ended, the workshop still runs.
        #expect(t.current == long)
        #expect(t.cursor == 0)
        #expect(DayTimeline(blocks: [long, short], now: at(10, 15)).current == short)
    }

    @Test func boundariesAreEveryStartAndEndStillAhead() {
        let t = DayTimeline(blocks: [report, training], now: at(10))
        #expect(t.boundaries() == [at(10, 30), at(14), at(15)])
        #expect(t.boundaries(limit: 1) == [at(10, 30)])
    }

    @Test func blocksOnADay() {
        let tomorrow = block("Tomorrow", 9, day: 21)
        let today = DayTimeline.blocks([tomorrow, training, report], on: at(12), calendar: istanbulCalendar)
        #expect(today.map(\.title) == ["Write the report", "Training"])
    }
}

@Suite("Day plan: editing rules")
struct DayPlannerTests {
    func planner(_ now: Date) -> DayPlanner { DayPlanner(calendar: istanbulCalendar, now: now) }

    @Test func roundsUpToTheNextQuarter() {
        let p = planner(at(9))
        #expect(p.roundedUp(at(9, 7)) == at(9, 15))
        #expect(p.roundedUp(at(9, 15)) == at(9, 15))
        #expect(p.roundedUp(at(9, 52)) == at(10))
        #expect(p.roundedUp(at(9, 15).addingTimeInterval(1)) == at(9, 30))
    }

    @Test func suggestsTheFirstFreeStretch() {
        let blocks = [block("A", 9, minutes: 60), block("B", 10, minutes: 30), block("C", 12)]
        // Today at 08:50: 09:00 is taken until 10:30; an hour fits before C at 12:00.
        #expect(planner(at(8, 50)).suggestedStart(on: at(8, 50), minutes: 60, among: blocks) == at(10, 30))
        // Two hours don't fit before C: after it.
        #expect(planner(at(8, 50)).suggestedStart(on: at(8, 50), minutes: 120, among: blocks) == at(13))
        // A later day starts at 09:00.
        #expect(planner(at(8, 50)).suggestedStart(on: at(12, day: 22), minutes: 60, among: blocks) == at(9, day: 22))
        // An empty today: the next quarter hour.
        #expect(planner(at(16, 20)).suggestedStart(on: at(16, 20), minutes: 30, among: []) == at(16, 30))
    }

    @Test func findsOverlapsButNotTheBlockItself() {
        let a = block("A", 9, minutes: 60), b = block("B", 10, minutes: 60)
        let p = planner(at(8))
        #expect(p.overlaps(start: at(9, 30), minutes: 60, excluding: nil, in: [a, b]).map(\.title) == ["A", "B"])
        #expect(p.overlaps(start: at(10), minutes: 60, excluding: b.id, in: [a, b]).isEmpty)
        // Touching ends don't overlap.
        #expect(p.overlaps(start: at(11), minutes: 30, excluding: nil, in: [a, b]).isEmpty)
    }

    @Test func reorderingReflowsTheDayAndKeepsItsRhythm() {
        // 09:00 A (60) · 30 min free · 10:30 B (30) · 11:00 C (90)
        let a = block("A", 9, minutes: 60), b = block("B", 10, 30, minutes: 30), c = block("C", 11, minutes: 90)
        // Move C to the top.
        let moved = DayPlanner.repack([a, b, c], moving: IndexSet(integer: 2), to: 0)
        #expect(moved[c.id] == at(9))
        // C ends 10:30, the first gap (30 min) follows, then A.
        #expect(moved[a.id] == at(11))
        #expect(moved[b.id] == at(12))
        // Moving nothing changes nothing.
        let same = DayPlanner.repack([a, b, c], moving: IndexSet(integer: 1), to: 1)
        #expect(same[a.id] == a.start && same[b.id] == b.start && same[c.id] == c.start)
        #expect(DayPlanner.repack([], moving: IndexSet(), to: 0).isEmpty)
    }

    @Test func runningLatePushesOnlyWhatHasntBegun() {
        let done = block("Lit", 11, done: true), active = block("Now", 9, minutes: 120)
        let next = block("Next", 13), later = block("Later", 15)
        let shifted = planner(at(10)).shifted([done, active, next, later], by: 15)
        #expect(shifted.count == 2)
        #expect(shifted[next.id] == at(13, 15))
        #expect(shifted[later.id] == at(15, 15))
    }

    @Test func focusFromABlockFitsInsideIt() {
        let b = block("Report", 9, minutes: 90)
        // Before it begins: the usual length.
        #expect(planner(at(8)).focusMinutes(for: b, usual: 25) == 25)
        #expect(planner(at(8)).wholeBlockMinutes(for: b) == 90)
        // Ten minutes left: ten minutes of focus.
        #expect(planner(at(10, 20)).focusMinutes(for: b, usual: 25) == 10)
        // Never under the setup screen's minimum.
        #expect(planner(at(10, 28)).focusMinutes(for: b, usual: 25) == 5)
        // Never over its maximum.
        let marathon = block("Marathon", 9, minutes: 300)
        #expect(planner(at(8)).wholeBlockMinutes(for: marathon) == 180)
    }

    @Test func blocksHoldSessionsWithBreaks() {
        #expect(DayPlanner.estimatedSessions(minutes: 90, focusMinutes: 25) == 3)
        #expect(DayPlanner.estimatedSessions(minutes: 60, focusMinutes: 25) == 2)
        #expect(DayPlanner.estimatedSessions(minutes: 55, focusMinutes: 25) == 2)
        #expect(DayPlanner.estimatedSessions(minutes: 15, focusMinutes: 25) == 1)
        #expect(DayPlanner.estimatedSessions(minutes: 900, focusMinutes: 25) == TaskDraft.estimateRange.upperBound)
    }
}

@Suite("Day plan: reminders and alarms")
struct PlanReminderTests {
    @Test func remindersBeforeAndAtTheStart() {
        let report = block("Report", 9, minutes: 90)
        let training = block("Training", 14)
        let items: [(block: PlanBlock, reminders: PlanReminderSettings)] = [
            (training, PlanReminderSettings(beforeMinutes: 15, atStart: true, alarm: false)),
            (report, PlanReminderSettings(beforeMinutes: 10, atStart: true, alarm: false)),
        ]
        let alerts = PlanReminderPlanner.alerts(for: items, now: at(8), alarmsActive: false)
        #expect(alerts.map(\.fireDate) == [at(8, 50), at(9), at(13, 45), at(14)])
        #expect(alerts.map(\.kind) == [.before, .start, .before, .start])
        #expect(alerts[2].minutesBefore == 15)
        #expect(alerts[0].id == "lumora.plan.\(report.id.uuidString).before")
        #expect(PlanReminderPlanner.blockID(fromIdentifier: alerts[3].id) == training.id)
        #expect(PlanReminderPlanner.blockID(fromIdentifier: "lumora.daily.reminder") == nil)
    }

    @Test func nothingForThePastLitOrSilentBlocks() {
        let items: [(block: PlanBlock, reminders: PlanReminderSettings)] = [
            (block("Started", 9), .standard),
            (block("Lit", 12, done: true), .standard),
            (block("Quiet", 13), PlanReminderSettings(beforeMinutes: 0, atStart: false, alarm: false)),
            // 10:05 is past, the start at 10:10 isn't.
            (block("Soon", 10, 10), PlanReminderSettings(beforeMinutes: 5, atStart: true, alarm: false)),
        ]
        let alerts = PlanReminderPlanner.alerts(for: items, now: at(10, 6), alarmsActive: false)
        #expect(alerts.map(\.block.title) == ["Soon"])
        #expect(alerts.map(\.kind) == [.start])
    }

    @Test func anAlarmReplacesTheStartNotificationOnlyWhenAlarmsWork() {
        let b = block("Training", 14)
        let items: [(block: PlanBlock, reminders: PlanReminderSettings)] = [
            (b, PlanReminderSettings(beforeMinutes: 10, atStart: true, alarm: true)),
        ]
        #expect(PlanReminderPlanner.alerts(for: items, now: at(8), alarmsActive: true).map(\.kind) == [.before])
        #expect(PlanReminderPlanner.alerts(for: items, now: at(8), alarmsActive: false).map(\.kind) == [.before, .start])
        #expect(PlanReminderPlanner.alarms(for: items, now: at(8)).map(\.fireDate) == [at(14)])
        #expect(PlanReminderPlanner.alarms(for: items, now: at(14, 1)).isEmpty)
    }

    @Test func soonestFirstWithinTheLimit() {
        let items = (0..<40).map { i in
            (block: block("B\(i)", 8 + i % 12, day: 21 + i / 12), reminders: PlanReminderSettings.standard)
        }
        let alerts = PlanReminderPlanner.alerts(for: items, now: at(6), alarmsActive: false)
        #expect(alerts.count == PlanReminderPlanner.notificationLimit)
        #expect(alerts.map(\.fireDate) == alerts.map(\.fireDate).sorted())
        #expect(PlanReminderPlanner.alarms(for: items.map { ($0.block, PlanReminderSettings(beforeMinutes: 0, atStart: false, alarm: true)) },
                                           now: at(6)).count == PlanReminderPlanner.alarmLimit)
    }

    @Test func notificationsLeadToTheOrbit() {
        let id = PlanReminderPlanner.identifier(block: UUID(), kind: .start)
        #expect(NotificationService.link(forNotification: id) == .plan)
        #expect(NotificationService.analyticsKind(forNotification: id) == "plan_start")
        #expect(NotificationService.analyticsKind(forNotification: PlanReminderPlanner.identifier(block: UUID(), kind: .before)) == "plan_before")
    }
}

@Suite("Day plan: blocks are planned tasks")
@MainActor
struct DayPlanStoreTests {
    let clock = ManualDateProvider(now: at(8), timeZone: TestFixtures.istanbul)

    func make() throws -> (TaskStore, ModelContext) {
        let context = try TestFixtures.makeContext()
        return (TaskStore(context: context, clock: clock), context)
    }

    func blockDraft(_ title: String, start: Date, minutes: Int = 90,
                    reminders: PlanReminderSettings = .standard) -> TaskDraft {
        var d = TaskDraft()
        d.title = title
        d.category = .work
        d.schedule = BlockSchedule(start: start, minutes: minutes, reminders: reminders)
        return d
    }

    @Test func aBlockIsAPlannedTaskOnItsDay() throws {
        let (store, _) = try make()
        let task = store.create(blockDraft("Write the report", start: at(9).addingTimeInterval(42)))
        #expect(task.isPlanned)
        // Whole minutes, and the block's day is its due day.
        #expect(task.scheduledStart == at(9))
        #expect(task.dueDate == istanbulCalendar.startOfDay(for: at(9)))
        #expect(task.planBlock == PlanBlock(id: task.id, title: "Write the report", categoryRaw: "work",
                                            start: at(9), minutes: 90, isCompleted: false))
        #expect(store.planner.section(of: task) == .today)

        // Editing elsewhere (the task editor) keeps the time.
        var draft = TaskDraft(task)
        draft.notes = "Section 3"
        store.update(task, with: draft)
        #expect(task.scheduledStart == at(9))
        #expect(task.scheduledMinutes == 90)

        // Lit like any task; reminders travel with it.
        store.setCompleted(task, true)
        #expect(task.planBlock?.isCompleted == true)
        #expect(task.planReminders == .standard)
    }

    @Test func remindersAreStoredPerBlock() throws {
        let (store, _) = try make()
        let alarm = PlanReminderSettings(beforeMinutes: 30, atStart: false, alarm: true)
        let task = store.create(blockDraft("Training", start: at(14), minutes: 60, reminders: alarm))
        #expect(task.planReminders == alarm)
        #expect(TaskDraft(task).schedule?.reminders == alarm)
    }

    @Test func removingTheTimeKeepsTheTask() throws {
        let (store, _) = try make()
        let task = store.create(blockDraft("Read", start: at(20), minutes: 30))
        store.unschedule(task)
        #expect(task.scheduledStart == nil)
        #expect(task.planBlock == nil)
        #expect(task.isPlanned && !task.isArchived)
        #expect(store.unscheduledTasks().map(\.id) == [task.id])
    }

    @Test func reschedulingMovesBlocksAndTheirDay() throws {
        let (store, _) = try make()
        let a = store.create(blockDraft("A", start: at(9), minutes: 60))
        let b = store.create(blockDraft("B", start: at(11), minutes: 60))
        store.reschedule([a.id: at(9, day: 21), b.id: at(11, 15)])
        #expect(a.scheduledStart == at(9, day: 21))
        #expect(a.dueDate == istanbulCalendar.startOfDay(for: at(9, day: 21)))
        #expect(b.scheduledStart == at(11, 15))
        #expect(store.scheduledTasks(from: istanbulCalendar.startOfDay(for: at(9)), to: at(0, day: 21)).map(\.title) == ["B"])
    }

    @Test func scheduledTasksAreInOrderAndSkipArchived() throws {
        let (store, _) = try make()
        let late = store.create(blockDraft("Late", start: at(18)))
        _ = store.create(blockDraft("Early", start: at(7)))
        let gone = store.create(blockDraft("Gone", start: at(12)))
        store.archive(gone)
        _ = store.create({ var d = TaskDraft(); d.title = "No time"; return d }())
        let today = store.scheduledTasks(from: at(0), to: at(0, day: 21))
        #expect(today.map(\.title) == ["Early", "Late"])
        #expect(today.last?.id == late.id)
    }

    @Test func everySaveTellsThePlanToFollow() throws {
        let (store, _) = try make()
        var saves = 0
        store.didSave = { saves += 1 }
        let task = store.create(blockDraft("A", start: at(9)))
        store.reschedule([task.id: at(10)])
        store.unschedule(task)
        #expect(saves == 3)
    }
}

@Suite("Day plan: the app model keeps widgets and the Live Activity in step")
@MainActor
struct DayPlanAppTests {
    @Test func widgetsAndLiveActivitySeeTodaysPlan() throws {
        let context = try TestFixtures.makeContext()
        let clock = ManualDateProvider(now: at(8), timeZone: TestFixtures.istanbul)
        let app = AppModel(container: context.container, launchOptions: LaunchOptions.parse(["-lumora-ui-testing"]), clock: clock)
        var draft = TaskDraft()
        draft.title = "Training"
        draft.schedule = BlockSchedule(start: at(14), minutes: 60)
        app.tasks.create(draft)
        #expect(app.planBlocks().map(\.title) == ["Training"])
        #expect(app.widgetPlanBlocks().map(\.title) == ["Training"])
        #expect(app.widgets.makeSnapshot(goalMinutes: 120).plan?.map(\.title) == ["Training"])
        #expect(app.nextPlanBlock()?.title == "Training")
    }
}

@Suite("Day plan: links, widgets, Live Activity, route")
struct DayPlanSurfaceTests {
    @Test func planLinksRoundTrip() {
        #expect(DeepLink(url: URL(string: "lumora://plan")!) == .plan)
        #expect(DeepLink(url: URL(string: "lumora://orbit")!) == .plan)
        #expect(DeepLink(url: URL(string: "https://www.mobapptech.com/lumora/plan/")!) == .plan)
        #expect(DeepLink(url: DeepLink.plan.appURL) == .plan)
        #expect(DeepLink.plan.analyticsName == "plan")
    }

    @Test func snapshotsWithoutAPlanStillDecode() throws {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.plan = nil
        let data = try JSONEncoder().encode(snapshot)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "plan")
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: old).plan == nil)

        snapshot.plan = [block("Report", 9)]
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.plan == snapshot.plan)
    }

    @Test @MainActor func liveActivityCarriesTheNextBlock() {
        let segment = TimerSegment(id: UUID(), kind: .focus, focus: TestFixtures.config(), plannedSeconds: 1500, startedAt: at(9))
        let next = block("Training", 14)
        let content = LiveActivityService.content(for: segment, now: at(9, 5), next: next)
        #expect(content.state.nextBlockTitle == "Training")
        #expect(content.state.nextBlockStart == at(14))
        #expect(LiveActivityService.content(for: segment, now: at(9, 5)).state.nextBlockTitle == nil)
    }

    @Test func theRouteWindsBetweenStopsAndEndsInTheMiddle() {
        let route = OrbitRoute(width: 400, count: 4)
        #expect(route.height == route.inset * 2 + route.spacing * 5)
        // Dawn and night sit in the middle; stops alternate sides.
        #expect(abs(route.point(-1).x - 200) < 0.001)
        #expect(abs(route.point(4).x - 200) < 0.001)
        #expect(route.isLeft(0) != route.isLeft(1))
        #expect(route.isLeft(1) != route.isLeft(2))
        #expect(route.point(0).y < route.point(1).y)
        #expect(abs(route.point(1).x - 200) == route.amplitude)
    }
}
