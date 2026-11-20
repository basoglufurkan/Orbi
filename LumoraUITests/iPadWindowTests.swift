import XCTest

/// iPad only: the running timer opens in its own window and controls the
/// same session as the main window.
@MainActor
final class iPadWindowTests: XCTestCase {
    func testTimerOpensInItsOwnWindow() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-lumora-ui-testing", "-lumora-reset", "-lumora-skip-onboarding"]
        app.launch()
        app.buttons["home.beginFocus"].tap()
        app.buttons["setup.start"].tap()
        let open = app.buttons["focus.openWindow"]
        XCTAssertTrue(open.waitForExistence(timeout: 6))
        open.tap()
        // Both windows now show the session; pausing in one pauses both.
        let windowPause = app.buttons.matching(NSPredicate(format: "label == 'Pause' AND identifier != 'focus.pauseResume'")).firstMatch
        XCTAssertTrue(windowPause.waitForExistence(timeout: 6), "The timer window shows its own Pause control")
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.lifetime = .keepAlways
        add(attachment)
        windowPause.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Resume'")).firstMatch.waitForExistence(timeout: 4))
    }
}
