import Foundation
import Observation
import os

/// Persists finished focus segments and their rewards. Must be idempotent:
/// recording the same `FocusResult` twice returns the original reward.
@MainActor
protocol FocusResultRecording: AnyObject {
    func record(_ result: FocusResult) throws -> SessionReward
    func reward(for sessionID: UUID) -> SessionReward?
}

/// Reacts to timer events (notifications, Live Activity, haptics, audio, widgets).
@MainActor
protocol TimerSideEffects: AnyObject {
    func timerDidProcess(events: [FocusTimerEngine.Event], state: TimerState, now: Date)
}

@MainActor
final class NoopTimerSideEffects: TimerSideEffects {
    private(set) var received: [FocusTimerEngine.Event] = []
    func timerDidProcess(events: [FocusTimerEngine.Event], state: TimerState, now: Date) {
        received.append(contentsOf: events)
    }
}

/// Observable façade over `FocusTimerEngine`.
///
/// Order of operations for every action is fixed and crash-safe:
/// 1. reduce (pure), 2. persist rewards (idempotent), 3. checkpoint the new
/// state, 4. publish + side effects. If the app dies between 2 and 3, the
/// next launch re-derives the same completion and the recorder dedupes it.
@MainActor
@Observable
final class FocusSessionController {
    private(set) var state: TimerState
    /// Reward for the most recently finished focus segment.
    private(set) var latestReward: SessionReward?
    private(set) var lastError: String?

    @ObservationIgnored private let engine: FocusTimerEngine
    @ObservationIgnored private let store: TimerStateStore
    @ObservationIgnored private let recorder: FocusResultRecording
    @ObservationIgnored private let effects: TimerSideEffects
    @ObservationIgnored private let clock: DateProvider
    @ObservationIgnored var timerDefaults: () -> TimerDefaults
    /// Debug-only acceleration source (ignored in release by the engine).
    @ObservationIgnored var timeScale: () -> Double = { 1 }
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    /// A start was refused because an earlier session still isn't saved.
    @ObservationIgnored var onBlockedStart: (() -> Void)?
    @ObservationIgnored private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Timer")

    init(engine: FocusTimerEngine = FocusTimerEngine(),
         store: TimerStateStore,
         recorder: FocusResultRecording,
         effects: TimerSideEffects,
         clock: DateProvider,
         timerDefaults: @escaping () -> TimerDefaults = { TimerDefaults() }) {
        self.engine = engine
        self.store = store
        self.recorder = recorder
        self.effects = effects
        self.clock = clock
        self.timerDefaults = timerDefaults
        var restored = store.load() ?? .idle
        // The setup screen is transient UI; never restore into it.
        if restored.phase == .preparing { restored.phase = .idle }
        self.state = restored
    }

    // MARK: Intents

    func prepare() {
        guard settleUnrecorded() else { return }
        send(.prepare)
    }
    func cancelPreparation() { send(.cancelPreparation) }
    func start(_ configuration: FocusConfiguration) {
        guard settleUnrecorded() else { return }
        send(.startFocus(configuration, id: UUID(), timeScale: timeScale()))
    }

    /// A new session clears the pending result. If that result never made it
    /// into the store (a save failed), try once more first; while it still
    /// can't be saved, don't start, so the session isn't lost. Siri, the
    /// watch or Control Center can start one while the app shows the error.
    private func settleUnrecorded() -> Bool {
        guard state.pendingResult != nil, pendingReward == nil else { return true }
        retryPendingRecord()
        guard pendingReward != nil else { onBlockedStart?(); return false }
        return true
    }
    func pause() { send(.pause) }
    func resume() { send(.resume) }
    func endEarly() { send(.endFocus) }
    func startBreak() { send(.startBreak(id: UUID())) }
    func skipBreak() { send(.skipBreak) }
    func acknowledge() { send(.acknowledge) }
    /// Call on launch, foreground, time-zone and significant-time changes.
    func reconcile() { send(.reconcile) }

    /// Developer installs only (`BuildInfo.isDeveloperInstall`): lets the
    /// running segment reach its end right now, as if its time had passed, so
    /// a 25-minute session can be tried without waiting. Moving the start back
    /// keeps the result honest: full credit, true length.
    func debugFinishNow() {
        guard BuildInfo.isDeveloperInstall else { return }
        if state.segment?.isPaused == true { resume() }
        guard var segment = state.segment, let deadline = segment.deadline else { return }
        let ahead = deadline.timeIntervalSince(clock.now)
        guard ahead > 0 else { return }
        segment.startedAt.addTimeInterval(-ahead)
        state.segment = segment
        send(.reconcile)
    }

    /// Retries persisting the pending result if a previous save failed.
    func retryPendingRecord() {
        guard let pending = state.pendingResult else { return }
        do {
            latestReward = try recorder.record(pending)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Drops any running segment without recording it (used by "Erase all data").
    func reset() {
        wakeTask?.cancel()
        wakeTask = nil
        state = .idle
        latestReward = nil
        try? store.save(.idle)
    }

    // MARK: Derived

    var now: Date { clock.now }

    /// Reward for the result awaiting acknowledgement, loading it from the
    /// store after a relaunch if needed.
    var pendingReward: SessionReward? {
        guard let pending = state.pendingResult else { return nil }
        if let latestReward, latestReward.sessionID == pending.segmentID { return latestReward }
        return recorder.reward(for: pending.segmentID)
    }

    // MARK: Core

    func send(_ action: FocusTimerEngine.Action) {
        let now = clock.now
        let (next, events) = engine.reduce(state, action, now: now, defaults: timerDefaults())

        for event in events {
            if case let .focusFinished(result) = event {
                do {
                    latestReward = try recorder.record(result)
                } catch {
                    lastError = error.localizedDescription
                    logger.error("Failed to record focus result: \(error.localizedDescription)")
                }
            }
        }

        if next != state {
            do {
                try store.save(next)
            } catch {
                lastError = error.localizedDescription
                logger.error("Failed to checkpoint timer: \(error.localizedDescription)")
            }
            state = next
        }

        let meaningful = events.filter { if case .ignored = $0 { false } else { true } }
        if !meaningful.isEmpty {
            effects.timerDidProcess(events: meaningful, state: state, now: now)
        }
        scheduleWake(now: now)
    }

    /// One wake-up at the next moment the state can change on its own
    /// (deadline or pause auto-end). Not a source of truth: if it never fires
    /// (suspension), `reconcile()` on foreground produces the same result.
    private func scheduleWake(now: Date) {
        wakeTask?.cancel()
        wakeTask = nil
        guard let seg = state.segment else { return }
        let target: Date?
        if let deadline = seg.deadline {
            target = deadline
        } else if let pausedAt = seg.pausedAt {
            target = pausedAt.addingTimeInterval(engine.rules.maxPauseSeconds)
        } else {
            target = nil
        }
        guard let target else { return }
        let delay = max(0, target.timeIntervalSince(now))
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 0.05))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }
}
