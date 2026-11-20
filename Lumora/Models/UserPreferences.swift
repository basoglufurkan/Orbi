import Foundation
import SwiftData

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case night, dawn, auto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .night: String(localized: "Night")
        case .dawn: String(localized: "Dawn")
        case .auto: String(localized: "Auto")
        }
    }
}

/// Singleton user preferences. Every field has a default so new fields can
/// be added in lightweight migrations.
@Model
final class UserPreferences {
    var displayName: String = ""
    var hasCompletedOnboarding: Bool = false

    var defaultFocusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var longBreakInterval: Int = 4
    var autoStartBreaks: Bool = false

    var dailyGoalMinutes: Int = 120

    var appearanceRaw: String = AppearancePreference.night.rawValue
    var motionRaw: String = MotionPreference.system.rawValue

    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var ambientRaw: String = AmbientSound.silence.rawValue
    var ambientVolume: Double = 0.6
    var finalMinuteTick: Bool = false

    var focusNotifications: Bool = true
    var breakNotifications: Bool = true
    /// The daily invitation, sent only on days without a focus yet.
    var dailyReminderEnabled: Bool = true
    var dailyReminderHour: Int = 18
    var dailyReminderMinute: Int = 0
    var hasSeenNotificationPrompt: Bool = false
    /// A morning note on the day of a rare event.
    var rareEventNotifications: Bool = true

    var lastCategoryRaw: String = FocusCategory.work.rawValue
    var distractionShieldEnabled: Bool = false

    /// Day 1 of the universe. Kept here (synced) rather than on the
    /// device-only `UniverseProgress`, so a new phone draws the same sky.
    var universeCreatedAt: Date?

    init() {}

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .night }
        set { appearanceRaw = newValue.rawValue }
    }

    var motion: MotionPreference {
        get { MotionPreference(rawValue: motionRaw) ?? .system }
        set { motionRaw = newValue.rawValue }
    }

    var ambient: AmbientSound {
        get { AmbientSound(rawValue: ambientRaw) ?? .silence }
        set { ambientRaw = newValue.rawValue }
    }

    var lastCategory: FocusCategory {
        get { FocusCategory(storedValue: lastCategoryRaw) }
        set { lastCategoryRaw = newValue.rawValue }
    }

    var timerDefaults: TimerDefaults {
        TimerDefaults(shortBreakSeconds: shortBreakMinutes * 60,
                      longBreakSeconds: longBreakMinutes * 60,
                      longBreakInterval: longBreakInterval,
                      autoStartBreaks: autoStartBreaks)
    }
}
