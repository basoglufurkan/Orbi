import Foundation
import Testing
@testable import Lumora

struct DailyInvitationTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func todayCountsOnlyBeforeTheTimeAndWithoutAFocus() {
        let morning = date(29, 10)
        let days = NotificationService.reminderDays(now: morning, hour: 18, minute: 0, focusedToday: false, calendar: calendar)
        #expect(days.count == NotificationService.reminderDaysAhead)
        #expect(days.first == date(29, 18))
        #expect(days.last == date(29 + NotificationService.reminderDaysAhead - 1, 18))

        // Focused this morning: tonight stays quiet, tomorrow is invited.
        let focused = NotificationService.reminderDays(now: morning, hour: 18, minute: 0, focusedToday: true, calendar: calendar)
        #expect(focused.first == date(30, 18))
        #expect(focused.count == NotificationService.reminderDaysAhead)

        // Past the time: the next one is tomorrow.
        let evening = NotificationService.reminderDays(now: date(29, 18, 30), hour: 18, minute: 0, focusedToday: false, calendar: calendar)
        #expect(evening.first == date(30, 18))
    }

    @Test func invitationsLeadToTheFocusSetup() {
        #expect(NotificationService.link(forNotification: NotificationService.reminderID + ".2026-10-29") == .focus(minutes: nil, category: nil))
        // What the invitation carries in its userInfo, and what tapping it follows.
        let carried = DeepLink.focus(minutes: nil, category: nil).appURL
        #expect(carried.absoluteString == "lumora://focus")
        #expect(DeepLink(url: carried) == .focus(minutes: nil, category: nil))
    }

    @Test @MainActor func aFocusTodayIsNoticed() throws {
        let context = try TestFixtures.makeContext()
        let app = AppModel(container: context.container, launchOptions: LaunchOptions.parse(["-lumora-ui-testing"]))
        app.preferences.hasCompletedOnboarding = true
        #expect(!app.hasFocusedToday)
        app.timer.start(FocusConfiguration(plannedSeconds: 25 * 60, category: .work, intention: ""))
        #expect(app.hasFocusedToday)
    }

    @Test @MainActor func newInstallsGetTheEveningInvitation() throws {
        let context = try TestFixtures.makeContext()
        let app = AppModel(container: context.container, launchOptions: LaunchOptions.parse(["-lumora-ui-testing"]))
        #expect(app.preferences.dailyReminderEnabled)
        #expect(app.preferences.dailyReminderHour == 18)
    }
}
