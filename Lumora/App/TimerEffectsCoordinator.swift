import Foundation

/// Translates timer events into the outside world: notifications, the Live
/// Activity, ambience, haptics, widgets and (optionally) distraction shields.
/// Celebration haptics and sound are owned by the celebration view instead,
/// because they must start on the same frame as the visuals.
@MainActor
final class TimerEffectsCoordinator: TimerSideEffects {
    private let preferences: () -> UserPreferences
    private let haptics: HapticsService
    private let audio: AudioService
    private let notifications: NotificationService
    private let liveActivities: LiveActivityService
    private let widgets: WidgetSyncService
    private let shield: DistractionShielding
    private let nextStarNumber: () -> Int
    /// App-level observer (e.g. to show "break complete" in the UI).
    var onEvent: ((FocusTimerEngine.Event) -> Void)?
    /// Where the starting session came from, and whether it's with a friend (analytics).
    var focusContext: (() -> (source: String, together: Bool))?

    init(preferences: @escaping () -> UserPreferences, haptics: HapticsService, audio: AudioService,
         notifications: NotificationService, liveActivities: LiveActivityService,
         widgets: WidgetSyncService, shield: DistractionShielding, nextStarNumber: @escaping () -> Int) {
        self.preferences = preferences
        self.haptics = haptics
        self.audio = audio
        self.notifications = notifications
        self.liveActivities = liveActivities
        self.widgets = widgets
        self.shield = shield
        self.nextStarNumber = nextStarNumber
    }

    func timerDidProcess(events: [FocusTimerEngine.Event], state: TimerState, now: Date) {
        let prefs = preferences()
        // Control Center's Focus toggle mirrors whether a session is running.
        if events.contains(where: Self.changesFocus) {
            FocusControlState.publish(active: state.phase.isFocusActive, endsAt: state.segment?.deadline,
                                     pausedAt: state.segment?.pausedAt)
        }
        for event in events {
            logTelemetry(event, prefs: prefs, now: now)
            onEvent?(event)
            switch event {
            case let .focusStarted(segment):
                haptics.sessionStart()
                audio.setAmbient(prefs.ambient.playable, volume: prefs.ambientVolume)
                scheduleFocusNotification(segment, prefs: prefs)
                liveActivities.begin(segment: segment, starNumber: nextStarNumber(), now: now)
                beginShield(segment, prefs: prefs)

            case let .paused(segment):
                notifications.cancelTimerNotifications()
                liveActivities.refresh(segment: segment, now: now)
                audio.stopAmbient()
                // A paused session isn't focus; the apps come back until it resumes.
                shield.endShielding()

            case let .resumed(segment):
                scheduleFocusNotification(segment, prefs: prefs)
                liveActivities.refresh(segment: segment, now: now)
                audio.setAmbient(prefs.ambient.playable, volume: prefs.ambientVolume)
                beginShield(segment, prefs: prefs)

            case let .focusFinished(result):
                notifications.cancelTimerNotifications()
                audio.stopAmbient()
                liveActivities.end(completedFrom: result.startedAt, to: result.endedAt)
                shield.endShielding()
                widgets.publish(goalMinutes: prefs.dailyGoalMinutes)

            case let .breakStarted(segment):
                audio.play(.breakBowl)
                if prefs.ambient != .silence { audio.setAmbient(.tides, volume: prefs.ambientVolume) }
                if prefs.breakNotifications, let deadline = segment.deadline {
                    notifications.scheduleBreakCompletion(at: deadline)
                }
                liveActivities.begin(segment: segment, starNumber: max(0, nextStarNumber() - 1), now: now)

            case .breakFinished:
                notifications.cancelTimerNotifications()
                liveActivities.end()
                audio.stopAmbient()

            case .preparing, .acknowledged, .ignored:
                break
            }
        }
    }

    private func logTelemetry(_ event: FocusTimerEngine.Event, prefs: UserPreferences, now: Date) {
        switch event {
        case let .focusStarted(segment):
            guard let focus = segment.focus else { return }
            let context: (source: String, together: Bool) = focusContext?() ?? ("app", false)
            Telemetry.log(.focusStarted(minutes: segment.plannedSeconds / 60, category: focus.category.rawValue,
                                        ambience: prefs.ambient.playable.rawValue,
                                        hasIntention: !focus.intention.trimmingCharacters(in: .whitespaces).isEmpty,
                                        fromTask: focus.taskID != nil,
                                        shield: FeatureFlags.distractionShield && prefs.distractionShieldEnabled,
                                        together: context.together, source: context.source))
        case let .paused(segment):
            guard segment.kind == .focus else { return }
            Telemetry.log(.focusPaused(elapsedMinutes: Int(segment.elapsed(at: now)) / 60, pauseCount: segment.pauseCount))
        case let .resumed(segment):
            guard segment.kind == .focus else { return }
            Telemetry.log(.focusResumed(pauseCount: segment.pauseCount))
        case let .focusFinished(result):
            let planned = result.plannedSeconds / 60, focused = result.focusedSeconds / 60
            switch result.endReason {
            case .completed:
                Telemetry.log(.focusCompleted(minutes: planned, category: result.configuration.category.rawValue,
                                              pauses: result.pauseCount))
            case .endedByUser:
                Telemetry.log(.focusEndedEarly(plannedMinutes: planned, focusedMinutes: focused,
                                               category: result.configuration.category.rawValue, pauses: result.pauseCount,
                                               percent: result.plannedSeconds > 0 ? result.focusedSeconds * 100 / result.plannedSeconds : 0))
            case .autoEndedAfterPause:
                Telemetry.log(.focusAutoEnded(plannedMinutes: planned, focusedMinutes: focused))
            }
        case let .breakStarted(segment):
            Telemetry.log(.breakStarted(minutes: segment.plannedSeconds / 60, long: segment.kind == .longBreak))
        case let .breakFinished(_, skipped):
            Telemetry.log(.breakFinished(skipped: skipped))
        case .preparing, .acknowledged, .ignored:
            break
        }
    }

    private func beginShield(_ segment: TimerSegment, prefs: UserPreferences) {
        guard FeatureFlags.distractionShield, prefs.distractionShieldEnabled, let deadline = segment.deadline else { return }
        shield.beginShielding(until: deadline)
    }

    private func scheduleFocusNotification(_ segment: TimerSegment, prefs: UserPreferences) {
        guard prefs.focusNotifications, let deadline = segment.deadline else { return }
        notifications.scheduleFocusCompletion(at: deadline, starNumber: nextStarNumber(),
                                              minutes: segment.plannedSeconds / 60)
    }

    private static func changesFocus(_ event: FocusTimerEngine.Event) -> Bool {
        switch event {
        case .focusStarted, .paused, .resumed, .focusFinished: true
        default: false
        }
    }
}
