import Foundation
import Testing
import UserNotifications
@testable import Lumora

/// A tapped notification, handed to `NotificationService` the way UIKit does:
/// through the Objective-C delegate method with a completion handler. That
/// handler must come back on the main thread. Off it, UIKit aborts while it
/// snapshots the scene, which is what killed Lumora on the launch screen when a
/// notification launched it.
@Suite("Notification taps") @MainActor
struct NotificationTapTests {
    nonisolated private static let blockID = UUID()

    nonisolated static let taps: [(identifier: String, action: String, link: String?)] = [
        // A plan reminder: opens Today's orbit.
        (PlanReminderPlanner.identifier(block: blockID, kind: .start), UNNotificationDefaultActionIdentifier, DeepLink.plan.appURL.absoluteString),
        // Its "Begin focus" button.
        (PlanReminderPlanner.identifier(block: blockID, kind: .start), NotificationService.planFocusAction, nil),
        // A finished focus: no link, nothing to open.
        (NotificationService.focusID, UNNotificationDefaultActionIdentifier, nil),
        // The daily invitation from an earlier version, without a link.
        (NotificationService.reminderID + ".2026-11-09", UNNotificationDefaultActionIdentifier, nil),
    ]

    @Test(arguments: taps)
    func everyTapCompletesOnTheMainThread(_ tap: (identifier: String, action: String, link: String?)) async throws {
        let app = try Self.coldLaunchedApp()
        let response = try NotificationFixtures.response(identifier: tap.identifier, action: tap.action, link: tap.link)
        #expect(await Self.deliver(response, to: app.notifications))
    }

    @Test func bannersAreDecidedOnTheMainThread() async throws {
        let app = try Self.coldLaunchedApp()
        let notification = try NotificationFixtures.notification(
            identifier: PlanReminderPlanner.identifier(block: Self.blockID, kind: .before), link: nil)
        let delegate: any UNUserNotificationCenterDelegate = app.notifications
        let (options, onMain) = await withCheckedContinuation { continuation in
            delegate.userNotificationCenter?(.current(), willPresent: notification) { @Sendable options in
                continuation.resume(returning: (options, pthread_main_np() != 0))
            }
        }
        #expect(onMain)
        #expect(options == [.banner, .sound, .list])
    }

    /// Lumora wasn't running: the process starts, builds its model, and the
    /// tap arrives before any screen is up. It leads to Today's orbit.
    @Test func coldLaunchFromAPlanReminderOpensTodaysOrbit() async throws {
        let app = try Self.coldLaunchedApp()
        app.selectedTab = .insights
        let response = try NotificationFixtures.response(
            identifier: PlanReminderPlanner.identifier(block: Self.blockID, kind: .start),
            action: UNNotificationDefaultActionIdentifier, link: DeepLink.plan.appURL.absoluteString)
        #expect(await Self.deliver(response, to: app.notifications))
        #expect(app.isShowingDayOrbit)
        #expect(app.selectedTab == .plan)
        #expect(app.focusSource == "notification")
    }

    /// "Begin focus" on a block's notification starts that block's focus.
    @Test func coldLaunchFromBeginFocusStartsTheBlock() async throws {
        let app = try Self.coldLaunchedApp()
        var draft = TaskDraft()
        draft.title = "Write the report"
        draft.schedule = BlockSchedule(start: app.clock.now, minutes: 60)
        let task = app.tasks.create(draft)
        let response = try NotificationFixtures.response(
            identifier: PlanReminderPlanner.identifier(block: task.id, kind: .start),
            action: NotificationService.planFocusAction, link: nil)
        #expect(await Self.deliver(response, to: app.notifications))
        #expect(app.timer.state.phase == .focusing)
        #expect(app.timer.state.focusSegment?.focus?.taskID == task.id)
    }

    /// A fresh model, as `AppRuntime` builds it on a cold launch, for someone
    /// past onboarding.
    private static func coldLaunchedApp() throws -> AppModel {
        let context = try TestFixtures.makeContext()
        return AppModel(container: context.container,
                        launchOptions: LaunchOptions.parse(["-lumora-ui-testing", "-lumora-skip-onboarding"]))
    }

    /// Hands the response over as UIKit does and waits for the completion
    /// handler; true when it ran on the main thread.
    private static func deliver(_ response: UNNotificationResponse, to service: NotificationService) async -> Bool {
        let delegate: any UNUserNotificationCenterDelegate = service
        return await withCheckedContinuation { continuation in
            delegate.userNotificationCenter?(.current(), didReceive: response) { @Sendable in
                continuation.resume(returning: pthread_main_np() != 0)
            }
        }
    }
}

/// `UNNotification` and `UNNotificationResponse` have no public initializers;
/// tests build them with the class factories the system itself uses.
enum NotificationFixtures {
    struct Unavailable: Error {}

    static func notification(identifier: String, link: String?) throws -> UNNotification {
        let content = UNMutableNotificationContent()
        content.title = "Orbi"
        if let link { content.userInfo = [NotificationService.linkKey: link] }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let make = NSSelectorFromString("notificationWithRequest:date:")
        guard (UNNotification.self as AnyObject).responds(to: make),
              let made = (UNNotification.self as AnyObject).perform(make, with: request, with: Date())?.takeUnretainedValue(),
              let notification = made as? UNNotification else { throw Unavailable() }
        return notification
    }

    static func response(identifier: String, action: String, link: String?) throws -> UNNotificationResponse {
        let notification = try notification(identifier: identifier, link: link)
        let make = NSSelectorFromString("responseWithNotification:actionIdentifier:")
        guard (UNNotificationResponse.self as AnyObject).responds(to: make),
              let made = (UNNotificationResponse.self as AnyObject).perform(make, with: notification, with: action)?.takeUnretainedValue(),
              let response = made as? UNNotificationResponse else { throw Unavailable() }
        return response
    }
}
