import Foundation

/// Process launch arguments used by UI tests and debug tooling.
///
/// - `-lumora-reset`: erase all data on launch (fresh install state).
/// - `-lumora-skip-onboarding`: start on Home with a named universe.
/// - `-lumora-time-scale <n>`: accelerate sessions n× (DEBUG builds only;
///   the engine clamps this to 1 in release, so production timing can never
///   be affected).
/// - `-lumora-demo <n>`: seed n historical sessions (DEBUG only).
/// - `-lumora-in-memory`: use a throwaway in-memory store.
/// - `-lumora-together-demo`: focus together with a simulated friend (DEBUG only).
/// - `-lumora-event-today <kind>`: this week's rare event is today (DEBUG only).
/// - `-lumora-fake-tilt`: drive gyro parallax with a slow synthetic tilt
///   (DEBUG only; the simulator has no gyroscope).
/// - `-lumora-clock <HH:mm>`: the app's clock starts today at that time and
///   runs on from there (DEBUG only), for day-plan screenshots.
/// - `-lumora-demo-plan`: seed today's plan around now (DEBUG only).
/// - `-lumora-demo-habits`: seed a few habits with weeks of history (DEBUG only).
struct LaunchOptions: Sendable {
    var resetData = false
    var skipOnboarding = false
    var timeScale: Double = 1
    var demoSessions = 0
    var inMemory = false
    var isUITesting = false
    var fakeTilt = false
    /// DEBUG: show the Odyssey art gallery instead of the app (optionally one section).
    var gallery = false
    /// DEBUG: focus together against an in-memory room with a simulated friend.
    var togetherDemo = false
    var gallerySection: String?
    /// DEBUG: Orbi+ on (`-lumora-plus 1`) or off (`0`) regardless of purchases.
    var plusOverride: Bool?
    /// DEBUG: show the after-onboarding free-trial offer again (`-lumora-intro-offer`).
    var introOffer = false
    /// DEBUG: today's time of day the app's clock starts at, in minutes after midnight.
    var clockMinutes: Int?
    /// DEBUG: seed a day plan around now.
    var demoPlan = false
    /// DEBUG: seed habits with history.
    var demoHabits = false

    static func parse(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchOptions {
        var o = LaunchOptions()
        o.resetData = arguments.contains("-lumora-reset")
        o.skipOnboarding = arguments.contains("-lumora-skip-onboarding")
        o.inMemory = arguments.contains("-lumora-in-memory")
        o.isUITesting = arguments.contains("-lumora-ui-testing")
        #if DEBUG
        o.fakeTilt = arguments.contains("-lumora-fake-tilt")
        o.gallery = arguments.contains("-lumora-gallery")
        o.togetherDemo = arguments.contains("-lumora-together-demo")
        o.introOffer = arguments.contains("-lumora-intro-offer")
        o.demoPlan = arguments.contains("-lumora-demo-plan")
        o.demoHabits = arguments.contains("-lumora-demo-habits")
        if let i = arguments.firstIndex(of: "-lumora-clock"), i + 1 < arguments.count {
            let parts = arguments[i + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { o.clockMinutes = parts[0] * 60 + parts[1] }
        }
        if let i = arguments.firstIndex(of: "-lumora-gallery-section"), i + 1 < arguments.count {
            o.gallerySection = arguments[i + 1]
        }
        if let i = arguments.firstIndex(of: "-lumora-plus"), i + 1 < arguments.count {
            o.plusOverride = arguments[i + 1] == "1"
        }
        if let i = arguments.firstIndex(of: "-lumora-time-scale"), i + 1 < arguments.count {
            o.timeScale = Double(arguments[i + 1]) ?? 1
        }
        if let i = arguments.firstIndex(of: "-lumora-demo"), i + 1 < arguments.count {
            o.demoSessions = Int(arguments[i + 1]) ?? 0
        }
        if let i = arguments.firstIndex(of: "-lumora-event-today"), i + 1 < arguments.count {
            CosmicCalendar.forcedToday = CosmicEventKind(rawValue: arguments[i + 1])
        }
        #endif
        return o
    }

    /// True while running under XCTest unit tests (host app should stay inert).
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && !ProcessInfo.processInfo.arguments.contains("-lumora-ui-testing")
    }
}
