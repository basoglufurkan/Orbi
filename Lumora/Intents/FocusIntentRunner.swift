import AppIntents
import Foundation

/// Pure decisions for intent parameters: what a "Start focus" request with
/// optional minutes and category turns into, given preferences and any
/// active Focus filter preset.
enum FocusIntentPlanner {
    struct Plan: Equatable, Sendable {
        var configuration: FocusConfiguration
        var ambient: AmbientSound
    }

    /// Explicit parameters win, then the Focus filter preset, then the
    /// user's last choice — the same defaults the setup screen shows.
    static func plan(minutes: Int?, category: FocusCategory?,
                     defaultMinutes: Int, lastCategory: FocusCategory, lastAmbient: AmbientSound,
                     preset: FocusFilterPreset?) -> Plan {
        let resolvedMinutes = clamped(minutes ?? defaultMinutes)
        let resolvedCategory = category ?? preset?.category ?? lastCategory
        let config = FocusConfiguration(plannedSeconds: resolvedMinutes * 60, category: resolvedCategory, intention: "")
        return Plan(configuration: config, ambient: preset?.ambient ?? lastAmbient)
    }

    /// Siri and Shortcuts can pass any integer; keep it inside the range the setup screen allows.
    static func clamped(_ minutes: Int) -> Int {
        let range = FocusConfiguration.customRangeMinutes
        return min(max(minutes, range.lowerBound), range.upperBound)
    }
}

enum FocusIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case needsOnboarding

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .needsOnboarding: "Open Orbi once to name your universe, then try again."
        }
    }
}

/// Runs intent requests against the timer. Every change goes through
/// `FocusSessionController` (and so through `send`), so rewards stay
/// exactly-once and time stays derived from dates, exactly as when the user
/// taps the same controls in the app.
@MainActor
struct FocusIntentRunner {
    enum Outcome: Equatable {
        case started(FocusConfiguration)
        case alreadyFocusing
        case paused
        case resumed
        case ended(focusedMinutes: Int)
        case notFocusing
        case notPaused

        var dialog: IntentDialog {
            switch self {
            case let .started(config):
                IntentDialog("Focusing on \(config.category.displayName) for \(config.plannedSeconds / 60) minutes.")
            case .alreadyFocusing: IntentDialog("A focus session is already running.")
            case .paused: IntentDialog("Paused. Your light is waiting.")
            case .resumed: IntentDialog("Resumed.")
            case let .ended(minutes):
                minutes == 0 ? IntentDialog("Session ended.")
                    : IntentDialog("Session ended. \(minutes) focused minutes kept.")
            case .notFocusing: IntentDialog("There's no focus session running.")
            case .notPaused: IntentDialog("There's no paused session to resume.")
            }
        }
    }

    let timer: FocusSessionController
    let dataStore: DataStore
    let presets: FocusFilterPresetStore

    /// The runner for this process's shared `AppModel`.
    static func live() throws -> FocusIntentRunner {
        let app = try AppRuntime.model()
        app.prepareForIntent()
        return FocusIntentRunner(timer: app.timer, dataStore: app.dataStore, presets: .standard)
    }

    func start(minutes: Int?, category: FocusCategory?) throws -> Outcome {
        let prefs = dataStore.preferences()
        guard prefs.hasCompletedOnboarding else { throw FocusIntentError.needsOnboarding }
        timer.reconcile()
        guard !timer.state.phase.isFocusActive else { return .alreadyFocusing }

        let plan = FocusIntentPlanner.plan(minutes: minutes, category: category,
                                           defaultMinutes: prefs.defaultFocusMinutes,
                                           lastCategory: prefs.lastCategory, lastAmbient: prefs.ambient,
                                           preset: presets.load())
        // Remember the choice, as the setup screen does; the ambience is read when the session starts.
        prefs.lastCategory = plan.configuration.category
        prefs.ambient = plan.ambient
        dataStore.save()
        timer.start(plan.configuration)
        return .started(plan.configuration)
    }

    func pause() -> Outcome {
        timer.reconcile()
        guard timer.state.phase == .focusing else {
            return timer.state.phase == .paused ? .paused : .notFocusing
        }
        timer.pause()
        return .paused
    }

    func resume() -> Outcome {
        timer.reconcile()
        guard timer.state.phase == .paused else {
            return timer.state.phase == .focusing ? .resumed : .notPaused
        }
        timer.resume()
        return .resumed
    }

    func end() -> Outcome {
        timer.reconcile()
        guard timer.state.phase.isFocusActive else { return .notFocusing }
        timer.endEarly()
        return .ended(focusedMinutes: (timer.state.pendingResult?.focusedSeconds ?? 0) / 60)
    }
}
