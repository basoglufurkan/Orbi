import Foundation

/// The single `AppModel` for this process.
///
/// SwiftUI's `LumoraApp` and App Intents (Siri, Shortcuts, Spotlight, the
/// Action Button, Live Activity buttons) all reach the same instance, so an
/// intent run while the app is in the background — or one that launches the
/// app without UI — drives the same `FocusSessionController` and checkpoint
/// the UI shows. Built lazily on first use by whichever entry point runs first.
@MainActor
enum AppRuntime {
    private static var cached: Result<AppModel, any Error>?

    static func model() throws -> AppModel {
        if let cached { return try cached.get() }
        let options = LaunchOptions.parse()
        let result = Result<AppModel, any Error> {
            let inMemory = options.inMemory || LaunchOptions.isRunningUnitTests
            let cloudSync = CloudSync.isEnabled && !inMemory && !options.isUITesting
            let container = try DataStore.makeContainer(inMemory: inMemory, cloudSync: cloudSync)
            return AppModel(container: container, launchOptions: options, cloudSync: cloudSync)
        }
        cached = result
        return try result.get()
    }
}
