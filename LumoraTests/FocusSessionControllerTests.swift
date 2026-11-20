import Foundation
import Testing
@testable import Lumora

@Suite("Session controller: lifecycle & recovery")
@MainActor
struct FocusSessionControllerTests {
    @Test func relaunchRecoversRunningSessionAndCompletesOnce() {
        let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)
        let store = InMemoryTimerStateStore()
        let recorder = SpyRecorder()

        let first = FocusSessionController(store: store, recorder: recorder, effects: NoopTimerSideEffects(), clock: clock)
        first.start(TestFixtures.config())
        #expect(store.saved?.phase == .focusing)

        // App is terminated; relaunch 40 minutes later.
        clock.advance(by: 40 * 60)
        let relaunched = FocusSessionController(store: store, recorder: recorder, effects: NoopTimerSideEffects(), clock: clock)
        #expect(relaunched.state.phase == .focusing)
        relaunched.reconcile()
        relaunched.reconcile()
        #expect(relaunched.state.phase == .completed)
        #expect(recorder.recorded.count == 1)
        #expect(relaunched.pendingReward != nil)
    }

    @Test func backgroundForegroundDoesNotLoseTime() {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let store = InMemoryTimerStateStore()
        let controller = FocusSessionController(store: store, recorder: SpyRecorder(), effects: NoopTimerSideEffects(), clock: clock)
        controller.start(TestFixtures.config(minutes: 25))
        clock.advance(by: 10 * 60) // backgrounded, no ticks delivered
        controller.reconcile()   // foreground
        #expect(controller.state.focusSegment?.remaining(at: clock.now) == 900.0)
    }

    @Test func crashBetweenRewardAndCheckpointDoesNotDuplicate() throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let context = try TestFixtures.makeContext()
        let rewards = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        let store = InMemoryTimerStateStore()
        let controller = FocusSessionController(store: store, recorder: rewards, effects: NoopTimerSideEffects(), clock: clock)
        controller.start(TestFixtures.config())
        let checkpointBeforeCompletion = store.saved

        clock.advance(by: 26 * 60)
        controller.reconcile()
        #expect(controller.state.phase == .completed)

        // Simulate a crash: the reward committed but the new checkpoint was lost.
        let staleStore = InMemoryTimerStateStore(checkpointBeforeCompletion)
        let relaunched = FocusSessionController(store: staleStore, recorder: rewards, effects: NoopTimerSideEffects(), clock: clock)
        relaunched.reconcile()

        let sessions = try context.fetch(FetchDescriptorFactory.sessions())
        let stars = try context.fetch(FetchDescriptorFactory.objects()).filter { $0.kind == .star }
        #expect(sessions.count == 1)
        #expect(stars.count == 1)
    }

    @Test func sideEffectsReceiveMeaningfulEventsOnly() {
        let effects = NoopTimerSideEffects()
        let controller = FocusSessionController(store: InMemoryTimerStateStore(), recorder: SpyRecorder(), effects: effects,
                                                clock: ManualDateProvider(now: TestFixtures.baseDate))
        controller.pause() // invalid in idle → ignored, not forwarded
        #expect(effects.received.isEmpty)
        controller.start(TestFixtures.config())
        #expect(effects.received.count == 1)
    }

    @Test func debugFinishNowCompletesWithFullCredit() {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let recorder = SpyRecorder()
        let controller = FocusSessionController(store: InMemoryTimerStateStore(), recorder: recorder,
                                                effects: NoopTimerSideEffects(), clock: clock)
        controller.start(TestFixtures.config(minutes: 25))
        clock.advance(by: 3 * 60)
        controller.debugFinishNow()
        #expect(controller.state.phase == .completed)
        #expect(recorder.recorded.count == 1)
        let result = recorder.recorded.first
        #expect(result?.endReason == .completed)
        #expect(result?.focusedSeconds == 25 * 60)
        #expect(result?.endedAt == clock.now)
        #expect(result?.startedAt == clock.now.addingTimeInterval(-25 * 60))
    }

    @Test func preparingIsNotRestoredAfterRelaunch() {
        let store = InMemoryTimerStateStore(TimerState(phase: .preparing))
        let controller = FocusSessionController(store: store, recorder: SpyRecorder(), effects: NoopTimerSideEffects(),
                                                clock: ManualDateProvider(now: TestFixtures.baseDate))
        #expect(controller.state.phase == .idle)
    }
}

import SwiftData

enum FetchDescriptorFactory {
    static func sessions() -> FetchDescriptor<FocusSession> { FetchDescriptor<FocusSession>() }
    static func objects() -> FetchDescriptor<CelestialObject> { FetchDescriptor<CelestialObject>() }
    static func unlocks() -> FetchDescriptor<AchievementUnlock> { FetchDescriptor<AchievementUnlock>() }
}

@Suite("Control Center focus state")
struct FocusControlStateTests {
    @Test func runningPausedAndExpiredSessions() throws {
        let defaults = try #require(UserDefaults(suiteName: "lumora.tests.control.\(UUID().uuidString)"))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(!FocusControlState.isRunning(now: now, defaults: defaults))
        FocusControlState.publish(active: true, endsAt: now.addingTimeInterval(600), defaults: defaults)
        #expect(FocusControlState.isRunning(now: now, defaults: defaults))
        // A deadline that passed while the app slept reads as finished.
        #expect(!FocusControlState.isRunning(now: now.addingTimeInterval(601), defaults: defaults))
        FocusControlState.publish(active: true, endsAt: nil, defaults: defaults)   // paused
        #expect(FocusControlState.isRunning(now: now.addingTimeInterval(3_600), defaults: defaults))
        FocusControlState.publish(active: false, endsAt: nil, defaults: defaults)
        #expect(!FocusControlState.isRunning(now: now, defaults: defaults))
    }
}
