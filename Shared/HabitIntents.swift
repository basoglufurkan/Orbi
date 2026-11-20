import AppIntents
import Foundation

/// Keeps (or reopens) a habit for today from the Habits widget. It lives in
/// Shared/ because the widget's `Button(intent:)` needs the type; as a
/// `LiveActivityIntent` the system runs `perform()` in the app's process,
/// which owns SwiftData, and the widget build compiles the work out.
struct ToggleHabitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Keep Habit"
    static let description = IntentDescription("Marks one of your habits as done for today, or opens it again.")
    static let isDiscoverable = false

    @Parameter(title: "Habit")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: habitID), let app = try? AppRuntime.model(),
           let habit = app.habits.fetch(id: id) {
            app.habits.toggleToday(habit, source: "widget")
        }
        #endif
        return .result()
    }
}
