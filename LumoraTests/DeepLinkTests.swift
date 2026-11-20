import Foundation
import Testing
@testable import Lumora

struct DeepLinkTests {
    private func link(_ string: String) -> DeepLink? { DeepLink(url: URL(string: string)!) }

    @Test func screensFromBothForms() {
        for screen in DeepLink.Screen.allCases {
            #expect(link("lumora://\(screen.rawValue)") == .screen(screen))
            #expect(link("https://www.mobapptech.com/lumora/\(screen.rawValue)/") == .screen(screen))
            #expect(DeepLink(url: DeepLink.screen(screen).appURL) == .screen(screen))
            #expect(DeepLink(url: DeepLink.screen(screen).webURL) == .screen(screen))
        }
        #expect(link("LUMORA://Universe") == .screen(.universe))
        #expect(link("https://www.mobapptech.com/lumora/") == .screen(.today))
        #expect(link("lumora://settings") == .settings)
        #expect(link("lumora://tasks") == .tasks)
        #expect(link("lumora://insights/year") == .yearInReview)
        #expect(link("https://www.mobapptech.com/lumora/insights/year/") == .yearInReview)
    }

    @Test func focusLinksAreClampedAndOptional() {
        #expect(link("lumora://focus") == .focus(minutes: nil, category: nil))
        #expect(link("lumora://focus?minutes=50&category=Reading") == .focus(minutes: 50, category: .reading))
        #expect(link("lumora://focus?minutes=100000") == .focus(minutes: DeepLink.minuteRange.upperBound, category: nil))
        #expect(link("lumora://focus?minutes=-3&category=nap") == .focus(minutes: DeepLink.minuteRange.lowerBound, category: nil))
        let shared = DeepLink.focus(minutes: 25, category: .coding)
        #expect(shared.webURL.absoluteString == "https://www.mobapptech.com/lumora/focus/?minutes=25&category=coding")
        #expect(DeepLink(url: shared.webURL) == shared)
        #expect(DeepLink(url: shared.appURL) == shared)
    }

    @Test func joinLinksInEveryShape() {
        #expect(link("lumora://together/ab-cdef") == .join(code: "ABCDEF"))
        #expect(link("https://www.mobapptech.com/lumora/join/?code=2QGSZ9") == .join(code: "2QGSZ9"))
        #expect(link("https://www.mobapptech.com/lumora/join/2QGSZ9") == .join(code: "2QGSZ9"))
        #expect(link("lumora://join?code=OOO") == nil)
    }

    @Test func foreignAndUnknownLinksAreIgnored() {
        #expect(link("https://example.com/lumora/universe/") == nil)
        #expect(link("https://www.mobapptech.com/lumora-privacy-policy/") == nil)
        #expect(link("https://www.mobapptech.com/other/universe") == nil)
        #expect(link("lumora://erase") == nil)
        #expect(link("mailto:hi@example.com") == nil)
    }

    @Test func notificationsLeadSomewhereUseful() {
        #expect(NotificationService.link(forNotification: NotificationService.reminderID) == .focus(minutes: nil, category: nil))
        #expect(NotificationService.link(forNotification: NotificationService.eventPrefix + "2026-10-29") == .screen(.today))
        #expect(NotificationService.link(forNotification: NotificationService.focusID) == nil)
    }

    @Test @MainActor func openingOnlyNavigates() throws {
        let context = try TestFixtures.makeContext()
        let app = AppModel(container: context.container, launchOptions: LaunchOptions.parse(["-lumora-ui-testing"]))
        app.preferences.hasCompletedOnboarding = false
        app.open(.screen(.odyssey))
        #expect(app.selectedTab == .today)
        #expect(app.pendingLink == .screen(.odyssey))
        app.preferences.hasCompletedOnboarding = true
        app.openPendingLink()
        #expect(app.selectedTab == .odyssey)
        #expect(app.pendingLink == nil)

        app.open(.settings)
        #expect(app.isShowingSettings)
        app.open(.yearInReview)
        #expect(!app.isShowingSettings)
        #expect(app.selectedTab == .insights)
        #expect(app.pendingYearInReview)

        // The Collection opens over Insights; the plan, habits and tasks live on Plan.
        app.open(.screen(.collection))
        #expect(app.selectedTab == .insights)
        #expect(app.isShowingCollection)
        app.open(.screen(.today))
        #expect(!app.isShowingCollection)
        #expect(app.selectedTab == .today)
        app.open(.habits)
        #expect(app.selectedTab == .plan)
        #expect(app.isShowingHabits)
        app.open(.screen(.insights))
        #expect(!app.isShowingHabits)
        #expect(app.selectedTab == .insights)

        // A focus link prepares the setup screen; it never starts a session.
        app.open(.focus(minutes: 45, category: .study))
        #expect(app.timer.state.phase == .preparing)
        #expect(app.setupPrefill?.minutes == 45)
        #expect(app.setupPrefill?.category == .study)

        // While a session is being set up or run, links leave it alone.
        app.open(.screen(.universe))
        #expect(app.selectedTab == .insights)

        app.open(.join(code: "ABCDEF"))
        #expect(app.together.pendingJoinCode == "ABCDEF")
    }
}
