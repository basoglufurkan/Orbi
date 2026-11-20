import Foundation

/// What Pell says, and where. Every line speaks to the person directly, by
/// name when Lumora knows it.
extension PellTip {
    /// First time on Today: Pell says hello, and asks for a name if it has none.
    static func hello(name: String) -> PellTip {
        guard !name.isEmpty else {
            return PellTip(id: "home.hello", message: String(localized: "Hi, I'm Pell. I'll be around while you focus. What should I call you?"),
                           mood: .curious, action: .askName, actionTitle: String(localized: "Tell Pell your name"))
        }
        return PellTip(id: "home.hello",
                       message: String(localized: "Hi \(name), I'm Pell. Tap any light in your sky to see the session that made it."),
                       mood: .happy)
    }

    /// Back after a few quiet days.
    static func welcomeBack(name: String, day: DayKey) -> PellTip {
        PellTip(id: "home.return.\(day.rawValue)",
                message: name.isEmpty
                    ? String(localized: "Welcome back! Missed days only rest. Shall we light one more star?")
                    : String(localized: "Welcome back, \(name)! Missed days only rest. Shall we light one more star?"),
                mood: .happy, edge: .leading)
    }

    /// Today's goal reached.
    static func goalReached(name: String, day: DayKey) -> PellTip {
        PellTip(id: "home.goal.\(day.rawValue)",
                message: name.isEmpty
                    ? String(localized: "You reached today's goal! Anything more is a gift to your sky.")
                    : String(localized: "You reached today's goal, \(name)! Anything more is a gift to your sky."),
                mood: .proud)
    }

    /// First time preparing a session.
    static func setup(name: String, offersShield: Bool) -> PellTip {
        let message: String = switch (name.isEmpty, offersShield) {
        case (true, true): String(localized: "Choose a length and what you'll work on. Want fewer distractions? Quiet your apps below.")
        case (true, false): String(localized: "Choose a length and what you'll work on. I'll be right here until your star is born.")
        case (false, true): String(localized: "Choose a length and what you'll work on, \(name). Want fewer distractions? Quiet your apps below.")
        case (false, false): String(localized: "Choose a length and what you'll work on, \(name). I'll be right here until your star is born.")
        }
        return PellTip(id: "setup.first", message: message, mood: .curious, edge: .leading, scope: .focus)
    }

    /// Preparing a session late at night.
    static func lateNight(name: String, day: DayKey) -> PellTip {
        PellTip(id: "setup.late.\(day.rawValue)",
                message: name.isEmpty
                    ? String(localized: "It's late. A short one, then rest? Your sky will still be here tomorrow.")
                    : String(localized: "It's late, \(name). A short one, then rest? Your sky will still be here tomorrow."),
                mood: .sleepy, edge: .leading, scope: .focus)
    }

    static let universe = PellTip(
        id: "universe.first",
        message: String(localized: "This is everything you've built. Pinch to zoom, drag to wander, and slide through your journey below."),
        mood: .curious, edge: .leading)

    static let insights = PellTip(
        id: "insights.first",
        message: String(localized: "Here's how your focus has been going. The more days you show up, the more I can tell you."),
        mood: .happy, edge: .leading)
}
