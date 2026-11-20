import Foundation
import Testing
@testable import Lumora

@Suite("App Intents: parameters & runner")
@MainActor
struct AppIntentsTests {
    // MARK: Planner

    @Test func missingParametersUseDefaultsAndLastChoice() {
        let plan = FocusIntentPlanner.plan(minutes: nil, category: nil, defaultMinutes: 45,
                                           lastCategory: .reading, lastAmbient: .rain, preset: nil)
        #expect(plan.configuration.plannedSeconds == 45 * 60)
        #expect(plan.configuration.category == .reading)
        #expect(plan.configuration.intention.isEmpty)
        #expect(plan.ambient == .rain)
    }

    @Test func minutesAreClampedToTheSetupRange() {
        #expect(FocusIntentPlanner.clamped(1) == 5)
        #expect(FocusIntentPlanner.clamped(0) == 5)
        #expect(FocusIntentPlanner.clamped(-10) == 5)
        #expect(FocusIntentPlanner.clamped(25) == 25)
        #expect(FocusIntentPlanner.clamped(500) == 180)
        let plan = FocusIntentPlanner.plan(minutes: 1000, category: nil, defaultMinutes: 25,
                                           lastCategory: .work, lastAmbient: .silence, preset: nil)
        #expect(plan.configuration.plannedSeconds == 180 * 60)
    }

    @Test func explicitCategoryBeatsFocusFilterBeatsLastChoice() {
        let preset = FocusFilterPreset(category: .coding, ambient: .brownNoise)
        let fromPreset = FocusIntentPlanner.plan(minutes: 25, category: nil, defaultMinutes: 25,
                                                 lastCategory: .study, lastAmbient: .silence, preset: preset)
        #expect(fromPreset.configuration.category == .coding)
        #expect(fromPreset.ambient == .brownNoise)

        let explicit = FocusIntentPlanner.plan(minutes: 25, category: .creative, defaultMinutes: 25,
                                               lastCategory: .study, lastAmbient: .silence, preset: preset)
        #expect(explicit.configuration.category == .creative)
        #expect(explicit.ambient == .brownNoise)

        let partial = FocusIntentPlanner.plan(minutes: nil, category: nil, defaultMinutes: 25, lastCategory: .study,
                                              lastAmbient: .tides, preset: FocusFilterPreset(category: nil, ambient: .rain))
        #expect(partial.configuration.category == .study)
        #expect(partial.ambient == .rain)
    }

    @Test func spokenLengthsMapToMinutes() {
        #expect(FocusLength.allCases.map(\.minutes) == FocusConfiguration.presetsMinutes)
    }

    // MARK: Focus filter preset

    @Test func focusFilterPresetRoundTripsAndClearsWhenFocusEnds() throws {
        let suite = "lumora.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FocusFilterPresetStore(defaults: defaults)

        #expect(store.load() == nil)
        store.save(FocusFilterPreset(category: .work, ambient: .deepSpace))
        #expect(store.load() == FocusFilterPreset(category: .work, ambient: .deepSpace))

        // The system re-runs the filter with empty values when the Focus turns off.
        store.save(FocusFilterPreset(category: nil, ambient: nil))
        #expect(store.load() == nil)
        #expect(defaults.data(forKey: FocusFilterPresetStore.key) == nil)
    }

    // MARK: Runner

    private struct Harness {
        let clock: ManualDateProvider
        let recorder: SpyRecorder
        let timer: FocusSessionController
        let dataStore: DataStore
        let runner: FocusIntentRunner
        let defaults: UserDefaults
        let suite: String
    }

    private func makeHarness(onboarded: Bool = true) throws -> Harness {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let recorder = SpyRecorder()
        let timer = FocusSessionController(store: InMemoryTimerStateStore(), recorder: recorder,
                                           effects: NoopTimerSideEffects(), clock: clock)
        let dataStore = DataStore(container: try DataStore.makeContainer(inMemory: true))
        dataStore.preferences().hasCompletedOnboarding = onboarded
        let suite = "lumora.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let runner = FocusIntentRunner(timer: timer, dataStore: dataStore,
                                       presets: FocusFilterPresetStore(defaults: defaults))
        return Harness(clock: clock, recorder: recorder, timer: timer, dataStore: dataStore,
                       runner: runner, defaults: defaults, suite: suite)
    }

    @Test func startUsesParametersAndRemembersTheChoice() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        let outcome = try h.runner.start(minutes: 15, category: .coding)

        #expect(h.timer.state.phase == .focusing)
        #expect(h.timer.state.focusSegment?.plannedSeconds == 15 * 60)
        #expect(h.timer.state.focusSegment?.focus?.category == .coding)
        #expect(outcome == .started(FocusConfiguration(plannedSeconds: 15 * 60, category: .coding, intention: "")))
        #expect(h.dataStore.preferences().lastCategory == .coding)
    }

    @Test func startAppliesTheActiveFocusFilter() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        h.runner.presets.save(FocusFilterPreset(category: .study, ambient: .rain))
        _ = try h.runner.start(minutes: nil, category: nil)

        #expect(h.timer.state.focusSegment?.focus?.category == .study)
        #expect(h.timer.state.focusSegment?.plannedSeconds == h.dataStore.preferences().defaultFocusMinutes * 60)
        #expect(h.dataStore.preferences().ambient == .rain)
    }

    @Test func startWhileFocusingDoesNotReplaceTheSession() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        _ = try h.runner.start(minutes: 25, category: .work)
        let firstID = h.timer.state.focusSegment?.id

        #expect(try h.runner.start(minutes: 60, category: .reading) == .alreadyFocusing)
        #expect(h.timer.state.focusSegment?.id == firstID)
        #expect(h.timer.state.focusSegment?.plannedSeconds == 25 * 60)
    }

    @Test func startBeforeOnboardingThrows() throws {
        let h = try makeHarness(onboarded: false)
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        #expect(throws: FocusIntentError.needsOnboarding) { try h.runner.start(minutes: nil, category: nil) }
        #expect(h.timer.state.phase == .idle)
    }

    @Test func pauseResumeAndEndKeepTimeDerivedAndRewardOnce() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        #expect(h.runner.pause() == .notFocusing)
        #expect(h.runner.resume() == .notPaused)
        #expect(h.runner.end() == .notFocusing)

        _ = try h.runner.start(minutes: 25, category: .work)
        h.clock.advance(by: 5 * 60)
        #expect(h.runner.pause() == .paused)
        #expect(h.timer.state.phase == .paused)
        #expect(h.runner.pause() == .paused) // idempotent, no second pause counted
        #expect(h.timer.state.focusSegment?.pauseCount == 1)

        h.clock.advance(by: 3 * 60) // paused time is not focus time
        #expect(h.runner.resume() == .resumed)
        let remaining = try #require(h.timer.state.focusSegment?.remaining(at: h.clock.now))
        #expect(abs(remaining - 20 * 60) < 0.001)

        h.clock.advance(by: 5 * 60)
        #expect(h.runner.end() == .ended(focusedMinutes: 10))
        #expect(h.runner.end() == .notFocusing)
        #expect(h.recorder.recorded.count == 1)
        #expect(h.timer.state.phase == .interrupted)
    }

    @Test func intentAfterSessionFinishedInBackgroundCompletesItOnce() throws {
        let h = try makeHarness()
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        _ = try h.runner.start(minutes: 25, category: .work)
        h.clock.advance(by: 30 * 60) // finished while suspended

        #expect(h.runner.pause() == .notFocusing)
        #expect(h.timer.state.phase == .completed)
        _ = try h.runner.start(minutes: nil, category: nil)
        #expect(h.timer.state.phase == .focusing)
        #expect(h.recorder.recorded.count == 1)
        #expect(h.recorder.recorded.first?.endReason == .completed)
    }
}
