import Foundation

enum SegmentKind: String, Codable, Sendable {
    case focus, shortBreak, longBreak
    var isBreak: Bool { self != .focus }
}

enum AmbientSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case silence, deepSpace, brownNoise, rain, tides, solarWind, campfire

    var id: String { rawValue }

    /// Soundscapes that come with Orbi+.
    var isPlus: Bool {
        switch self {
        case .silence, .deepSpace, .brownNoise: false
        case .rain, .tides, .solarWind, .campfire: true
        }
    }

    /// What actually plays: a Orbi+ sound falls back to the deep space hum
    /// while Orbi+ isn't active.
    var playable: AmbientSound { isPlus && !PlusAccess.isActive ? .deepSpace : self }

    var title: String {
        switch self {
        case .silence: String(localized: "Silence")
        case .deepSpace: String(localized: "Deep space hum")
        case .rain: String(localized: "Rain on glass")
        case .tides: String(localized: "Slow tides")
        case .brownNoise: String(localized: "Brown noise")
        case .solarWind: String(localized: "Solar wind")
        case .campfire: String(localized: "Campfire")
        }
    }
}

/// What the user chose on the setup screen.
struct FocusConfiguration: Codable, Equatable, Sendable {
    var plannedSeconds: Int
    var category: FocusCategory
    var intention: String
    var taskID: UUID?

    static let presetsMinutes = [15, 25, 45, 60]
    static let customRangeMinutes = 5...180
}

/// Break-related preferences the engine needs.
struct TimerDefaults: Equatable, Sendable {
    var shortBreakSeconds: Int = 5 * 60
    var longBreakSeconds: Int = 15 * 60
    var longBreakInterval: Int = 4
    var autoStartBreaks: Bool = false
}

/// Engine-wide constants.
struct TimerRules: Equatable, Sendable {
    /// A pause longer than this auto-ends the session; the star is kept.
    var maxPauseSeconds: TimeInterval = 10 * 60
    static let standard = TimerRules()
}

/// One running unit of time: a focus session or a break.
///
/// Remaining time is always *derived* from absolute dates (start, accumulated
/// pause, pause start) — never from counting ticks — so it stays correct
/// across backgrounding, device lock, termination and relaunch.
struct TimerSegment: Codable, Equatable, Sendable {
    var id: UUID
    var kind: SegmentKind
    var focus: FocusConfiguration?
    var plannedSeconds: Int
    var startedAt: Date
    var pausedAt: Date?
    var accumulatedPause: TimeInterval = 0
    var pauseCount: Int = 0
    /// Segment-seconds that elapse per wall-clock second. Always 1 in release
    /// builds; debug builds may accelerate to preview a session in seconds.
    var timeScale: Double = 1

    var isPaused: Bool { pausedAt != nil }

    /// Focused (non-paused) segment time elapsed at `now`, clamped to the plan.
    func elapsed(at now: Date) -> TimeInterval {
        let reference = pausedAt ?? now
        let wall = max(0, reference.timeIntervalSince(startedAt) - accumulatedPause)
        return min(Double(plannedSeconds), wall * timeScale)
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, Double(plannedSeconds) - elapsed(at: now))
    }

    func progress(at now: Date) -> Double {
        plannedSeconds > 0 ? elapsed(at: now) / Double(plannedSeconds) : 1
    }

    /// Wall-clock end while running; nil while paused.
    var deadline: Date? {
        guard pausedAt == nil else { return nil }
        return startedAt.addingTimeInterval(accumulatedPause + Double(plannedSeconds) / timeScale)
    }

    /// Wall-clock end if resumed at `now`.
    func projectedDeadline(resumingAt now: Date) -> Date {
        now.addingTimeInterval(remaining(at: now) / timeScale)
    }

    func isFinished(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// Total paused wall time up to `now` (including an ongoing pause).
    func pausedSeconds(at now: Date) -> TimeInterval {
        accumulatedPause + (pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

/// Explicit states: Idle → Preparing → Focusing ⇄ Paused → Completed,
/// plus Interrupted (ended early) and OnBreak.
enum TimerPhase: String, Codable, Sendable {
    case idle, preparing, focusing, paused, completed, interrupted, onBreak

    var isFocusActive: Bool { self == .focusing || self == .paused }
}

enum FocusEndReason: String, Codable, Sendable {
    case completed, endedByUser, autoEndedAfterPause
}

/// The immutable record of a finished focus segment, handed to the reward
/// layer exactly as the engine computed it.
struct FocusResult: Codable, Equatable, Sendable {
    var segmentID: UUID
    var configuration: FocusConfiguration
    var startedAt: Date
    var endedAt: Date
    var plannedSeconds: Int
    var focusedSeconds: Int
    var pausedSeconds: Int
    var pauseCount: Int
    var endReason: FocusEndReason
}

struct TimerState: Codable, Equatable, Sendable {
    var phase: TimerPhase = .idle
    var segment: TimerSegment?
    /// Focus segments completed since the last long break.
    var focusCountInCycle: Int = 0
    /// A finished focus segment whose celebration/summary hasn't been acknowledged.
    var pendingResult: FocusResult?
    /// Time scale of the most recent focus segment (debug acceleration only),
    /// reused for the break that follows it.
    var timeScale: Double = 1

    static let idle = TimerState()

    var focusSegment: TimerSegment? { segment?.kind == .focus ? segment : nil }
    var breakSegment: TimerSegment? { segment?.kind.isBreak == true ? segment : nil }
}
