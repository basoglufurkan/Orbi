import SwiftUI

@main
struct LumoraWatchApp: App {
    @State private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
                .onAppear { session.activate() }
        }
    }
}

enum WatchStyle {
    static let space = Color(red: 0.04, green: 0.05, blue: 0.13)
    static let violet = Color(red: 0.545, green: 0.486, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.835, blue: 0.541)
    static let cyan = Color(red: 0.439, green: 0.882, blue: 0.961)
    static let text = Color(red: 0.96, green: 0.95, blue: 1.0)
    static let secondary = Color(red: 0.725, green: 0.737, blue: 0.89)
}

struct WatchRootView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        ZStack {
            if session.celebrating {
                StarBirthView { session.celebrating = false }
                    .transition(.opacity)
            } else if session.state.isFocusing {
                WatchFocusView()
            } else {
                WatchHomeView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: session.celebrating)
        .animation(.easeInOut(duration: 0.3), value: session.state.isFocusing)
    }
}
