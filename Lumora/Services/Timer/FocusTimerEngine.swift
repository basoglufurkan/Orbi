import Foundation

/// The Pomodoro state machine. A pure reducer: given a state, an action and
/// the current time it returns the next state plus domain events. It owns no
/// timers, performs no I/O and knows nothing about animation, so it is fully
/// deterministic and unit-testable.
///
/// Every action first *reconciles* the state with `now` — so a pause that
/// arrives after the deadline completes the session instead, a session that
/// finished while the app was suspended is completed at its deadline, and an
/// over-long pause auto-ends the session.
struct FocusTimerEngine: Sendable {
    enum Action: Equatable, Sendable {
        case prepare
        case cancelPreparation
        case startFocus(FocusConfiguration, id: UUID, timeScale: Double)
        case pause
        case resume
        case endFocus
        case startBreak(id: UUID)
        case skipBreak
        case acknowledge
        case reconcile
    }

    enum Event: Equatable, Sendable {
        case preparing
        case focusStarted(TimerSegment)
        case paused(TimerSegment)
        case resumed(TimerSegment)
        case focusFinished(FocusResult)
        case breakStarted(TimerSegment)
        case breakFinished(TimerSegment, skipped: Bool)
        case acknowledged
        /// The action is not valid in the current phase; state is unchanged.
        case ignored(Action)
    }

    var rules: TimerRules = .standard

    func reduce(_ state: TimerState, _ action: Action, now: Date, defaults: TimerDefaults) -> (TimerState, [Event]) {
        var (s, events) = reconcile(state, now: now, defaults: defaults)

        switch action {
        case .reconcile:
            break

        case .prepare:
            switch s.phase {
            case .idle, .completed, .interrupted:
                s.pendingResult = nil
                s.phase = .preparing
                s.segment = nil
                events.append(.preparing)
            case .onBreak:
                if let seg = s.segment { events.append(.breakFinished(seg, skipped: true)) }
                s.segment = nil
                s.pendingResult = nil
                s.phase = .preparing
                events.append(.preparing)
            case .preparing, .focusing, .paused:
                events.append(.ignored(action))
            }

        case .cancelPreparation:
            if s.phase == .preparing {
                s.phase = .idle
            } else {
                events.append(.ignored(action))
            }

        case let .startFocus(config, id, timeScale):
            guard !s.phase.isFocusActive, config.plannedSeconds > 0 else {
                events.append(.ignored(action))
                break
            }
            if s.phase == .onBreak, let seg = s.segment {
                events.append(.breakFinished(seg, skipped: true))
            }
            let segment = TimerSegment(id: id, kind: .focus, focus: config,
                                       plannedSeconds: config.plannedSeconds, startedAt: now,
                                       timeScale: Self.sanitized(timeScale))
            s.segment = segment
            s.timeScale = segment.timeScale
            s.pendingResult = nil
            s.phase = .focusing
            events.append(.focusStarted(segment))

        case .pause:
            guard s.phase == .focusing, var seg = s.segment else {
                events.append(.ignored(action))
                break
            }
            seg.pausedAt = now
            seg.pauseCount += 1
            s.segment = seg
            s.phase = .paused
            events.append(.paused(seg))

        case .resume:
            guard s.phase == .paused, var seg = s.segment, let pausedAt = seg.pausedAt else {
                events.append(.ignored(action))
                break
            }
            seg.accumulatedPause += max(0, now.timeIntervalSince(pausedAt))
            seg.pausedAt = nil
            s.segment = seg
            s.phase = .focusing
            events.append(.resumed(seg))

        case .endFocus:
            guard s.phase.isFocusActive, let seg = s.segment else {
                events.append(.ignored(action))
                break
            }
            let result = Self.result(for: seg, endedAt: now, reason: .endedByUser)
            s.segment = nil
            s.phase = .interrupted
            s.pendingResult = result
            events.append(.focusFinished(result))

        case let .startBreak(id):
            guard s.phase == .completed || s.phase == .interrupted || s.phase == .idle else {
                events.append(.ignored(action))
                break
            }
            let seg = makeBreak(id: id, state: &s, startingAt: now, defaults: defaults,
                                timeScale: s.timeScale)
            s.pendingResult = nil
            s.segment = seg
            s.phase = .onBreak
            events.append(.breakStarted(seg))

        case .skipBreak:
            guard s.phase == .onBreak, let seg = s.segment else {
                events.append(.ignored(action))
                break
            }
            s.segment = nil
            s.phase = .idle
            events.append(.breakFinished(seg, skipped: true))

        case .acknowledge:
            switch s.phase {
            case .completed, .interrupted:
                s.phase = .idle
                s.pendingResult = nil
                events.append(.acknowledged)
            case .onBreak, .idle:
                if s.pendingResult != nil {
                    s.pendingResult = nil
                    events.append(.acknowledged)
                } else {
                    events.append(.ignored(action))
                }
            default:
                events.append(.ignored(action))
            }
        }
        return (s, events)
    }

    /// Brings the state up to date with `now`. Idempotent.
    func reconcile(_ state: TimerState, now: Date, defaults: TimerDefaults) -> (TimerState, [Event]) {
        var s = state
        var events: [Event] = []

        if s.phase == .focusing, let seg = s.segment, let deadline = seg.deadline, now >= deadline {
            // Completed — possibly long ago while suspended. Credit the full
            // plan and stamp the true completion moment, not "now".
            let result = Self.result(for: seg, endedAt: deadline, reason: .completed)
            s.segment = nil
            s.pendingResult = result
            s.focusCountInCycle += 1
            events.append(.focusFinished(result))

            if defaults.autoStartBreaks {
                let breakID = Self.derivedID(from: seg.id, salt: "break")
                let brk = makeBreak(id: breakID, state: &s, startingAt: deadline,
                                    defaults: defaults, timeScale: seg.timeScale)
                s.segment = brk
                s.phase = .onBreak
                events.append(.breakStarted(brk))
            } else {
                s.phase = .completed
            }
        }

        if s.phase == .paused, let seg = s.segment, let pausedAt = seg.pausedAt,
           now.timeIntervalSince(pausedAt) >= rules.maxPauseSeconds {
            let endedAt = pausedAt.addingTimeInterval(rules.maxPauseSeconds)
            let result = Self.result(for: seg, endedAt: endedAt, reason: .autoEndedAfterPause)
            s.segment = nil
            s.phase = .interrupted
            s.pendingResult = result
            events.append(.focusFinished(result))
        }

        if s.phase == .onBreak, let seg = s.segment, seg.isFinished(at: now) {
            s.segment = nil
            s.phase = s.pendingResult == nil ? .idle : .completed
            events.append(.breakFinished(seg, skipped: false))
        }

        if s.phase == .preparing, s.segment != nil {
            s.segment = nil
        }
        return (s, events)
    }

    // MARK: - Helpers

    private func makeBreak(id: UUID, state s: inout TimerState, startingAt start: Date,
                           defaults: TimerDefaults, timeScale: Double) -> TimerSegment {
        let isLong = defaults.longBreakInterval > 0 && s.focusCountInCycle >= defaults.longBreakInterval
        if isLong { s.focusCountInCycle = 0 }
        let seconds = isLong ? defaults.longBreakSeconds : defaults.shortBreakSeconds
        return TimerSegment(id: id, kind: isLong ? .longBreak : .shortBreak, focus: nil,
                            plannedSeconds: max(1, seconds), startedAt: start,
                            timeScale: Self.sanitized(timeScale))
    }

    static func result(for seg: TimerSegment, endedAt: Date, reason: FocusEndReason) -> FocusResult {
        let focused = reason == .completed ? Double(seg.plannedSeconds) : seg.elapsed(at: endedAt)
        return FocusResult(
            segmentID: seg.id,
            configuration: seg.focus ?? FocusConfiguration(plannedSeconds: seg.plannedSeconds, category: .work, intention: ""),
            startedAt: seg.startedAt,
            endedAt: endedAt,
            plannedSeconds: seg.plannedSeconds,
            focusedSeconds: Int(focused.rounded(.down)),
            pausedSeconds: Int(seg.pausedSeconds(at: endedAt).rounded()),
            pauseCount: seg.pauseCount,
            endReason: reason
        )
    }

    /// Time acceleration is a debug-only affordance and can never affect
    /// production timing.
    static func sanitized(_ scale: Double) -> Double {
        #if DEBUG
        return scale.isFinite && scale >= 1 ? min(scale, 3600) : 1
        #else
        return 1
        #endif
    }

    /// Stable UUID derived from another, so replaying a reconcile produces
    /// the same break identifier.
    static func derivedID(from id: UUID, salt: String) -> UUID {
        var a = SeededRandom(seed: StableHash.fnv1a(id.uuidString + salt))
        let hi = a.next(), lo = a.next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: hi >> (UInt64(i) * 8))
            bytes[i + 8] = UInt8(truncatingIfNeeded: lo >> (UInt64(i) * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
