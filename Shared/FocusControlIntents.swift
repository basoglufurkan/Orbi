import AppIntents
import Foundation

// Intents that control a running session. They live in Shared/ because the
// Live Activity's buttons (`Button(intent:)`) need the types in the widget
// extension too. As `LiveActivityIntent`s, the system always runs `perform()`
// in the *app's* process, which owns SwiftData and the timer; the widget
// build compiles the work out (`WIDGET_EXTENSION`) and never touches it.

/// Pauses the running focus session.
struct PauseFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Focus"
    static let description = IntentDescription("Pauses the focus session that's running in Orbi.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        let outcome = try FocusIntentRunner.live().pause()
        return .result(dialog: outcome.dialog)
        #endif
    }
}

/// Resumes a paused focus session.
struct ResumeFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Focus"
    static let description = IntentDescription("Resumes a paused focus session in Orbi.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        let outcome = try FocusIntentRunner.live().resume()
        return .result(dialog: outcome.dialog)
        #endif
    }
}

/// Ends the running focus session early. Focused time is kept and recorded once.
struct EndFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Focus"
    static let description = IntentDescription("Ends the current focus session early. The time you focused is kept.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        let outcome = try FocusIntentRunner.live().end()
        return .result(dialog: outcome.dialog)
        #endif
    }
}
