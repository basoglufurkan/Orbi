import Foundation
import Testing
@testable import Lumora

@Suite("Focus timer engine")
struct FocusTimerEngineTests {
    let engine = FocusTimerEngine()
    let defaults = TimerDefaults(shortBreakSeconds: 300, longBreakSeconds: 900, longBreakInterval: 4, autoStartBreaks: false)
    let t0 = TestFixtures.baseDate

    func started(minutes: Int = 25) -> TimerState {
        engine.reduce(.idle, .startFocus(TestFixtures.config(minutes: minutes), id: UUID(), timeScale: 1), now: t0, defaults: defaults).0
    }

    @Test func startCreatesFocusingSegmentWithFullTime() {
        let s = started()
        #expect(s.phase == .focusing)
        #expect(s.segment?.remaining(at: t0) == 1500)
        #expect(s.segment?.deadline == t0.addingTimeInterval(1500))
    }

    @Test func remainingIsDerivedFromDatesNotTicks() {
        let s = started()
        #expect(s.segment?.remaining(at: t0.addingTimeInterval(600)) == 900)
        #expect(s.segment?.progress(at: t0.addingTimeInterval(750)) == 0.5)
    }

    @Test func pauseFreezesTimeAndResumeShiftsDeadline() {
        var s = started()
        s = engine.reduce(s, .pause, now: t0.addingTimeInterval(600), defaults: defaults).0
        #expect(s.phase == .paused)
        // Time passes while paused: remaining must not change.
        #expect(s.segment?.remaining(at: t0.addingTimeInterval(900)) == 900)
        s = engine.reduce(s, .resume, now: t0.addingTimeInterval(900), defaults: defaults).0
        #expect(s.phase == .focusing)
        #expect(s.segment?.remaining(at: t0.addingTimeInterval(900)) == 900)
        #expect(s.segment?.deadline == t0.addingTimeInterval(1500 + 300))
        #expect(s.segment?.pauseCount == 1)
    }

    @Test func completesExactlyAtDeadline() {
        let s = started()
        let (next, events) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(1500), defaults: defaults)
        #expect(next.phase == .completed)
        #expect(next.pendingResult?.endReason == .completed)
        #expect(next.pendingResult?.focusedSeconds == 1500)
        #expect(events.contains { if case .focusFinished = $0 { true } else { false } })
    }

    @Test func notCompletedOneSecondBeforeDeadline() {
        let s = started()
        let (next, events) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(1499), defaults: defaults)
        #expect(next.phase == .focusing)
        #expect(events.isEmpty)
    }

    @Test func completionWhileInactiveIsStampedAtDeadline() {
        let s = started()
        // App suspended; user returns three hours later.
        let (next, _) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(3 * 3600), defaults: defaults)
        #expect(next.phase == .completed)
        #expect(next.pendingResult?.endedAt == t0.addingTimeInterval(1500))
    }

    @Test func reconcileIsIdempotent() {
        let s = started()
        let (a, e1) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(2000), defaults: defaults)
        let (b, e2) = engine.reduce(a, .reconcile, now: t0.addingTimeInterval(2100), defaults: defaults)
        #expect(a == b)
        #expect(e1.count == 1)
        #expect(e2.isEmpty)
    }

    @Test func pauseArrivingAfterDeadlineCompletesInstead() {
        let s = started()
        let (next, events) = engine.reduce(s, .pause, now: t0.addingTimeInterval(1500.2), defaults: defaults)
        #expect(next.phase == .completed)
        #expect(events.contains(.ignored(.pause)))
    }

    @Test func pauseJustBeforeCompletionKeepsRemainingTime() {
        var s = started()
        s = engine.reduce(s, .pause, now: t0.addingTimeInterval(1499.5), defaults: defaults).0
        #expect(s.phase == .paused)
        let later = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(1700), defaults: defaults).0
        #expect(later.phase == .paused)
        #expect(later.segment?.remaining(at: t0.addingTimeInterval(1700)) == 0.5)
    }

    @Test func rapidDuplicateTapsAreIgnored() {
        var s = started()
        s = engine.reduce(s, .pause, now: t0.addingTimeInterval(10), defaults: defaults).0
        let (again, events) = engine.reduce(s, .pause, now: t0.addingTimeInterval(10.1), defaults: defaults)
        #expect(again == s)
        #expect(events == [.ignored(.pause)])
        let (restart, e2) = engine.reduce(started(), .startFocus(TestFixtures.config(), id: UUID(), timeScale: 1), now: t0, defaults: defaults)
        #expect(restart.phase == .focusing)
        #expect(e2.count == 1)
    }

    @Test func endingEarlyRecordsFocusedTime() {
        var s = started()
        s = engine.reduce(s, .pause, now: t0.addingTimeInterval(600), defaults: defaults).0
        let (next, _) = engine.reduce(s, .endFocus, now: t0.addingTimeInterval(700), defaults: defaults)
        #expect(next.phase == .interrupted)
        #expect(next.pendingResult?.endReason == .endedByUser)
        #expect(next.pendingResult?.focusedSeconds == 600)
        #expect(next.pendingResult?.pausedSeconds == 100)
    }

    @Test func longPauseAutoEndsAndKeepsTheStar() {
        var s = started()
        s = engine.reduce(s, .pause, now: t0.addingTimeInterval(900), defaults: defaults).0
        let (next, _) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(900 + 601), defaults: defaults)
        #expect(next.phase == .interrupted)
        #expect(next.pendingResult?.endReason == .autoEndedAfterPause)
        #expect(next.pendingResult?.focusedSeconds == 900)
        #expect(next.pendingResult?.endedAt == t0.addingTimeInterval(900 + 600))
    }

    @Test func autoStartedBreakBeginsAtDeadline() {
        var auto = defaults
        auto.autoStartBreaks = true
        let s = started()
        let (next, events) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(1600), defaults: auto)
        #expect(next.phase == .onBreak)
        #expect(next.segment?.kind == .shortBreak)
        #expect(next.segment?.startedAt == t0.addingTimeInterval(1500))
        #expect(next.pendingResult != nil)
        #expect(events.count == 2)
    }

    @Test func longBreakAfterConfiguredInterval() {
        var s = TimerState.idle
        var now = t0
        for _ in 0..<4 {
            s = engine.reduce(s, .startFocus(TestFixtures.config(), id: UUID(), timeScale: 1), now: now, defaults: defaults).0
            now += 1500
            s = engine.reduce(s, .startBreak(id: UUID()), now: now, defaults: defaults).0
            if s.focusCountInCycle == 0 { break }
            s = engine.reduce(s, .skipBreak, now: now, defaults: defaults).0
        }
        #expect(s.segment?.kind == .longBreak)
        #expect(s.focusCountInCycle == 0)
    }

    @Test func breakFinishesToIdle() {
        var s = started()
        s = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(1500), defaults: defaults).0
        s = engine.reduce(s, .startBreak(id: UUID()), now: t0.addingTimeInterval(1510), defaults: defaults).0
        #expect(s.phase == .onBreak)
        let (done, events) = engine.reduce(s, .reconcile, now: t0.addingTimeInterval(1510 + 300), defaults: defaults)
        #expect(done.phase == .idle)
        #expect(events.contains { if case .breakFinished(_, skipped: false) = $0 { true } else { false } })
    }

    @Test func preparingCanBeCancelled() {
        let s = engine.reduce(.idle, .prepare, now: t0, defaults: defaults).0
        #expect(s.phase == .preparing)
        #expect(engine.reduce(s, .cancelPreparation, now: t0, defaults: defaults).0.phase == .idle)
    }

    @Test func timeScaleIsSanitized() {
        #expect(FocusTimerEngine.sanitized(.nan) == 1)
        #expect(FocusTimerEngine.sanitized(0.25) == 1)
        #expect(FocusTimerEngine.sanitized(-5) == 1)
    }

    @Test func derivedBreakIDIsStable() {
        let id = UUID()
        #expect(FocusTimerEngine.derivedID(from: id, salt: "break") == FocusTimerEngine.derivedID(from: id, salt: "break"))
        #expect(FocusTimerEngine.derivedID(from: id, salt: "break") != id)
    }

    @Test func stateRoundTripsThroughCodable() throws {
        var s = started()
        s = engine.reduce(s, .pause, now: t0.addingTimeInterval(42), defaults: defaults).0
        let decoded = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }
}
