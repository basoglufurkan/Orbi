import Foundation
import UserNotifications
import os

/// Local notifications: focus/break completion, a daily invitation on days
/// without a focus yet (it opens the focus setup), a morning note on the
/// day of a rare event, the day plan's reminders before and as each block
/// begins, and a habit's reminder on days it's still open. Nothing else
/// during focus.
@MainActor
final class NotificationService: NSObject {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Notifications")
    /// Where a tapped notification leads.
    var onOpenLink: ((DeepLink) -> Void)?
    /// "Begin focus" on a plan block's notification.
    var onPlanFocus: ((UUID) -> Void)?
    /// "Done" on a habit's reminder: keep that habit on that day.
    var onHabitDone: ((UUID, DayKey) -> Void)?

    nonisolated static let focusID = "lumora.focus.complete"
    nonisolated static let breakID = "lumora.break.complete"
    /// Each day's invitation is `reminderID.YYYY-MM-DD`; the bare ID was the old repeating one.
    nonisolated static let reminderID = "lumora.daily.reminder"
    /// A notification's deep link (`DeepLink.appURL`), followed when it's tapped.
    nonisolated static let linkKey = "link"
    /// How many days of invitations are queued ahead. Opening Lumora tops them
    /// up; after this long without it, the invitations stop by themselves.
    nonisolated static let reminderDaysAhead = 14
    nonisolated static let eventPrefix = "lumora.event."
    nonisolated static let trialReminderID = "lumora.plus.trialReminder"
    /// Day plan reminders: `lumora.plan.<block>.before|start`.
    nonisolated static let planPrefix = PlanReminderPlanner.prefix
    nonisolated static let planCategory = "lumora.plan.block"
    nonisolated static let planFocusAction = "lumora.plan.focus"
    /// Habit reminders: `lumora.habit.<habit>.<yyyy-MM-dd>`.
    nonisolated static let habitPrefix = HabitReminderPlanner.prefix
    nonisolated static let habitCategory = "lumora.habit.day"
    nonisolated static let habitDoneAction = "lumora.habit.done"
    /// When the rare-event note arrives on its day.
    static let eventHour = 9

    override init() {
        super.init()
        center.delegate = self
        let focus = UNNotificationAction(identifier: Self.planFocusAction, title: String(localized: "Begin focus"),
                                         options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "sparkle"))
        // Keeping a habit from its reminder needs no trip into the app.
        let done = UNNotificationAction(identifier: Self.habitDoneAction, title: String(localized: "Mark as done"),
                                        options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.planCategory, actions: [focus], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.habitCategory, actions: [done], intentIdentifiers: [], options: []),
        ])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization(source: String = "app") async -> Bool {
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription)")
            granted = false
        }
        Telemetry.log(.notificationPermission(granted: granted, source: source))
        return granted
    }

    func scheduleFocusCompletion(at date: Date, starNumber: Int, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Star #\(starNumber) is born ✦")
        content.body = String(localized: "\(minutes) minutes of focus. Come see it take its place.")
        content.sound = .default
        content.interruptionLevel = .active
        schedule(id: Self.focusID, content: content, at: date)
    }

    func scheduleBreakCompletion(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your break is complete")
        content.body = String(localized: "Pell will keep the light warm whenever you're ready.")
        content.sound = .default
        content.interruptionLevel = .active
        schedule(id: Self.breakID, content: content, at: date)
    }

    /// Before a Orbi+ free trial becomes a paid plan; opens Settings, where it's managed.
    func scheduleTrialReminder(at date: Date, daysLeft: Int, price: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your Orbi+ trial ends in \(daysLeft) days")
        content.body = String(localized: "After that it's \(price) a year. To cancel, go to Settings › Apple Account › Subscriptions.")
        content.sound = .default
        content.userInfo[Self.linkKey] = DeepLink.settings.appURL.absoluteString
        schedule(id: Self.trialReminderID, content: content, at: date)
    }

    func cancelTimerNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.focusID, Self.breakID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.focusID, Self.breakID])
    }

    /// Queues the daily invitation for the coming days at `hour:minute`,
    /// skipping today once there's been a focus (or the time has passed).
    /// Called whenever the app comes forward and whenever a session starts.
    func updateDailyReminder(enabled: Bool, hour: Int, minute: Int, focusedToday: Bool,
                             now: Date, calendar: Calendar) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.reminderID) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your sky is waiting")
        content.body = String(localized: "One small session is enough to add a star today.")
        content.sound = .default
        content.userInfo = [Self.linkKey: DeepLink.focus(minutes: nil, category: nil).appURL.absoluteString]
        for day in Self.reminderDays(now: now, hour: hour, minute: minute, focusedToday: focusedToday, calendar: calendar) {
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: day)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            let id = Self.reminderID + "." + DayKey(day, calendar: calendar).rawValue
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch {
                logger.error("Reminder scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    /// When the coming invitations fire: `hour:minute` on each of the next
    /// days, starting today unless today has had a focus or the time has passed.
    nonisolated static func reminderDays(now: Date, hour: Int, minute: Int, focusedToday: Bool,
                                         calendar: Calendar, count: Int = reminderDaysAhead) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let days = (0...count).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            if offset == 0, focusedToday || fire <= now { return nil }
            return fire
        }
        return Array(days.prefix(count))
    }

    /// Replaces the scheduled rare-event notes with one for each of `events`
    /// whose morning is still ahead.
    func updateEventReminders(_ events: [CosmicEvent], enabled: Bool, now: Date, calendar: Calendar) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.eventPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }
        for event in events {
            var when = calendar.dateComponents([.year, .month, .day], from: event.date)
            when.hour = Self.eventHour
            guard let fire = calendar.date(from: when), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Today: \(event.kind.title) ✦")
            content.body = String(localized: "\(event.kind.lore) Focus once today to witness it.")
            content.sound = .default
            content.interruptionLevel = .active
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: Self.eventPrefix + event.day.rawValue, content: content, trigger: trigger))
            } catch {
                logger.error("Event reminder scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    /// Replaces the day plan's pending reminders with `alerts` (already
    /// limited and ordered by `PlanReminderPlanner`).
    func updatePlanReminders(_ alerts: [PlanAlert], calendar: Calendar) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.planPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for alert in alerts {
            let content = UNMutableNotificationContent()
            let block = alert.block
            let start = PlanFormat.time(block.start), end = PlanFormat.time(block.end)
            switch alert.kind {
            case .before:
                content.title = String(localized: "\(block.title) begins in \(alert.minutesBefore) min")
                content.body = String(localized: "At \(start). A few breaths to settle in.")
            case .start:
                content.title = String(localized: "Time for \(block.title) ✦")
                content.body = String(localized: "\(start)–\(end) · The light is gathering.")
            }
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = Self.planPrefix + "day"
            content.categoryIdentifier = Self.planCategory
            content.userInfo = [Self.linkKey: DeepLink.plan.appURL.absoluteString]
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
            } catch {
                logger.error("Plan reminder scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    /// Replaces the pending habit reminders with `alerts` (already limited
    /// and ordered by `HabitReminderPlanner`).
    func updateHabitReminders(_ alerts: [HabitAlert], calendar: Calendar) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.habitPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(alert.title) ✦")
            if let streak = alert.streak {
                content.body = alert.countsWeeks
                    ? String(localized: "Your \(streak)-week streak is glowing. Keep it lit today.")
                    : String(localized: "Your \(streak)-day streak is glowing. Keep it lit today.")
            } else {
                content.body = String(localized: "A small step today, and its star burns a little brighter.")
            }
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = Self.habitPrefix + "day"
            content.categoryIdentifier = Self.habitCategory
            content.userInfo = [Self.linkKey: DeepLink.habits.appURL.absoluteString]
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: alert.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
            } catch {
                logger.error("Habit reminder scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    private func schedule(id: String, content: UNMutableNotificationContent, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { [logger] error in
            if let error { logger.error("Notification scheduling failed: \(error.localizedDescription)") }
        }
    }
}

/// Both callbacks run on the main actor. UIKit calls each one's completion
/// handler when the method returns, on the thread it returns on, and the tap's
/// handler snapshots the scene, which aborts off the main thread. Nonisolated,
/// they returned on a background thread and a notification that launched
/// Lumora crashed it on the launch screen.
extension NotificationService: @MainActor UNUserNotificationCenterDelegate {
    /// In the foreground the app's own celebration replaces the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        if id.hasPrefix(NotificationService.planPrefix) || id.hasPrefix(NotificationService.habitPrefix) {
            return [.banner, .sound, .list]
        }
        return id.hasPrefix(NotificationService.reminderID) || id.hasPrefix(NotificationService.eventPrefix)
            || id == NotificationService.trialReminderID ? [.banner, .sound] : []
    }

    /// A tapped notification follows its deep link: the daily invitation
    /// carries `lumora://focus` (the setup screen), and a rare event's note
    /// opens Today, where it shows. A finished focus or break needs no link:
    /// the app shows its reward or next step by itself.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        if response.actionIdentifier == Self.planFocusAction,
           let block = PlanReminderPlanner.blockID(fromIdentifier: request.identifier) {
            Telemetry.log(.notificationOpened(kind: "plan_focus"))
            onPlanFocus?(block)
            return
        }
        if response.actionIdentifier == Self.habitDoneAction,
           let habit = HabitReminderPlanner.parse(request.identifier) {
            Telemetry.log(.notificationOpened(kind: "habit_done"))
            onHabitDone?(habit.habitID, habit.day)
            return
        }
        let carried = (request.content.userInfo[Self.linkKey] as? String).flatMap(URL.init(string:)).flatMap(DeepLink.init(url:))
        guard let link = carried ?? Self.link(forNotification: request.identifier) else { return }
        Telemetry.log(.notificationOpened(kind: Self.analyticsKind(forNotification: request.identifier)))
        onOpenLink?(link)
    }

    nonisolated static func analyticsKind(forNotification id: String) -> String {
        if id.hasPrefix(reminderID) { return "daily_invitation" }
        if id.hasPrefix(eventPrefix) { return "cosmic_event" }
        if id == trialReminderID { return "trial_reminder" }
        if id.hasPrefix(planPrefix) { return id.hasSuffix(".before") ? "plan_before" : "plan_start" }
        if id.hasPrefix(habitPrefix) { return "habit_reminder" }
        return id.contains("break") ? "break_complete" : "focus_complete"
    }

    /// Links for notifications that don't carry one (scheduled by earlier versions).
    nonisolated static func link(forNotification id: String) -> DeepLink? {
        if id.hasPrefix(reminderID) { return .focus(minutes: nil, category: nil) }
        if id.hasPrefix(eventPrefix) { return .screen(.today) }
        if id.hasPrefix(planPrefix) { return .plan }
        if id.hasPrefix(habitPrefix) { return .habits }
        return nil
    }
}
