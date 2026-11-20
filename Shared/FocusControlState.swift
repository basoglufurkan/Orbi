import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the Control Center toggle needs to draw itself: whether a focus
/// session is running. The app writes it on every timer change; the control
/// reads it from the App Group. A deadline in the past counts as finished,
/// so the toggle is right even if the app was suspended when the session ended.
enum FocusControlState {
    static let controlKind = "com.mobapptech.lumora.focus-control"
    private static let activeKey = "control.focus.active"
    private static let endsAtKey = "control.focus.endsAt"
    private static let pausedAtKey = "control.focus.pausedAt"
    /// A pause this long ends the session (TimerRules.maxPauseSeconds).
    static let maxPause: TimeInterval = 10 * 60

    static func isRunning(now: Date = .now, defaults: UserDefaults = AppGroup.defaults) -> Bool {
        guard defaults.bool(forKey: activeKey) else { return false }
        if let endsAt = defaults.object(forKey: endsAtKey) as? Date { return endsAt > now }
        // Paused: the session ends on its own once the pause runs out, even
        // if the app is suspended and can't say so.
        guard let pausedAt = defaults.object(forKey: pausedAtKey) as? Date else { return true }
        return now.timeIntervalSince(pausedAt) < maxPause
    }

    /// `endsAt` is nil while paused; then `pausedAt` says since when.
    static func publish(active: Bool, endsAt: Date?, pausedAt: Date? = nil, defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(active, forKey: activeKey)
        if let endsAt { defaults.set(endsAt, forKey: endsAtKey) } else { defaults.removeObject(forKey: endsAtKey) }
        if let pausedAt { defaults.set(pausedAt, forKey: pausedAtKey) } else { defaults.removeObject(forKey: pausedAtKey) }
        #if canImport(WidgetKit)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: controlKind) }
        #endif
    }
}

/// Control Center's Focus toggle: on starts a session with your usual
/// length and category, off ends the running one (its time is kept). A
/// `LiveActivityIntent`, so it always runs in the app's process.
struct SetFocusRunningIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Focus in Orbi"
    static let description = IntentDescription("Starts a focus session with your usual length, or ends the one that's running.")

    @Parameter(title: "Focusing")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let runner = try FocusIntentRunner.live()
        _ = value ? try runner.start(minutes: nil, category: nil) : runner.end()
        #endif
        return .result()
    }
}
