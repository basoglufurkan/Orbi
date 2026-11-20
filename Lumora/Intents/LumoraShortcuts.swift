import AppIntents

/// Zero-setup shortcuts: Siri, Spotlight, the Shortcuts app and the Action Button.
struct LumoraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: [
            "Start a focus in \(.applicationName)",
            "Start focusing in \(.applicationName)",
            "Start a \(\.$category) focus in \(.applicationName)",
            "Focus with \(.applicationName)",
        ], shortTitle: "Start Focus", systemImageName: "sparkle")

        AppShortcut(intent: StartTimedFocusIntent(), phrases: [
            "Start a \(\.$length) focus in \(.applicationName)",
            "Focus for \(\.$length) in \(.applicationName)",
        ], shortTitle: "Timed Focus", systemImageName: "timer")

        AppShortcut(intent: PauseFocusIntent(), phrases: [
            "Pause my focus in \(.applicationName)",
            "Pause \(.applicationName)",
        ], shortTitle: "Pause Focus", systemImageName: "pause")

        AppShortcut(intent: ResumeFocusIntent(), phrases: [
            "Resume my focus in \(.applicationName)",
            "Resume \(.applicationName)",
        ], shortTitle: "Resume Focus", systemImageName: "play")

        AppShortcut(intent: EndFocusIntent(), phrases: [
            "End my focus in \(.applicationName)",
            "Stop focusing in \(.applicationName)",
        ], shortTitle: "End Focus", systemImageName: "stop")
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
