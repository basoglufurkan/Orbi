import SwiftData
import SwiftUI

@main
struct LumoraApp: App {
    @UIApplicationDelegateAdaptor(LumoraAppDelegate.self) private var appDelegate
    @State private var app: AppModel?
    @State private var startupError: String?

    init() {
        do {
            // Shared with App Intents, which may have created it already.
            _app = State(initialValue: try AppRuntime.model())
        } catch {
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let app {
                RootView()
                    .environment(app)
                    .modelContainer(app.dataStore.container)
            } else {
                StartupErrorView(message: startupError ?? "")
            }
        }

        // iPad: the timer on its own, to keep beside other apps.
        WindowGroup(id: FocusTimerWindow.id) {
            if let app {
                FocusTimerWindow()
                    .environment(app)
                    .modelContainer(app.dataStore.container)
            }
        }
        .defaultSize(width: 420, height: 560)
    }
}

/// Shown only if the local store cannot be opened. Data is never deleted
/// automatically; the user is told what happened.
private struct StartupErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            LMColor.bgBase.ignoresSafeArea()
            VStack(spacing: LMSpace.m) {
                Text("Your universe couldn't be opened.")
                    .font(LMFont.voice(.title))
                    .foregroundStyle(LMColor.textPrimary)
                Text("Nothing has been deleted. Please restart Orbi; if this keeps happening, contact support.")
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textSecondary)
                Text(message)
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
            }
            .multilineTextAlignment(.center)
            .padding(LMSpace.l)
        }
    }
}
