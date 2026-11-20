import XCTest

/// End-to-end flows. Sessions run with debug time acceleration
/// (`-lumora-time-scale`), which is compiled out of release builds.
@MainActor
final class LumoraUITests: XCTestCase {
    private func launch(reset: Bool, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-lumora-ui-testing", "-lumora-time-scale", "600"] + (reset ? ["-lumora-reset"] : []) + extra
        app.launch()
        return app
    }

    /// Through the chapters to Pell's first-star invitation; `lightFirstStar`
    /// starts the 25-minute session there, otherwise "Later" lands on Home.
    private func completeOnboarding(_ app: XCUIApplication, lightFirstStar: Bool = false) {
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        let create = app.buttons["onboarding.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 4))
        create.tap()
        let choice = app.buttons[lightFirstStar ? "onboarding.firstStar" : "onboarding.later"]
        XCTAssertTrue(choice.waitForExistence(timeout: 4))
        choice.tap()
    }

    private func runOneSession(_ app: XCUIApplication, alreadyStarted: Bool = false) {
        if !alreadyStarted {
            let begin = app.buttons["home.beginFocus"]
            XCTAssertTrue(begin.waitForExistence(timeout: 6))
            begin.tap()
            let start = app.buttons["setup.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 4))
            start.tap()
        }
        // 25 minutes at 600× ≈ 2.5 s, then the cinematic.
        let headline = app.staticTexts["celebration.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 25), "Completion summary should appear")
        XCTAssertEqual(headline.label, "You did it.")
    }

    func testOnboardingFocusCompletionAndUniverse() {
        let app = launch(reset: true)
        completeOnboarding(app, lightFirstStar: true)
        runOneSession(app, alreadyStarted: true)

        app.buttons["celebration.explore"].tap()
        let counts = app.staticTexts["universe.counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertTrue(counts.label.hasPrefix("1 star"), "Universe should contain the new star, got: \(counts.label)")
    }

    func testAccomplishmentSurvivesRelaunch() {
        var app = launch(reset: true)
        completeOnboarding(app)
        runOneSession(app)
        app.buttons["celebration.explore"].tap()
        XCTAssertTrue(app.staticTexts["universe.counts"].waitForExistence(timeout: 5))

        app.terminate()
        app = launch(reset: false)
        // Onboarding is not shown again and the star is still there.
        XCTAssertFalse(app.buttons["onboarding.next"].waitForExistence(timeout: 2))
        app.buttons["tab.universe"].tap()
        let counts = app.staticTexts["universe.counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        XCTAssertTrue(counts.label.hasPrefix("1 star"), "Star should persist across relaunch, got: \(counts.label)")
    }

    func testPauseResumeAndEndEarly() {
        // Real-time session: control checks only.
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-lumora-ui-testing", "-lumora-reset", "-lumora-skip-onboarding"]
        app.launch()

        app.buttons["home.beginFocus"].tap()
        app.buttons["setup.start"].tap()
        let pause = app.buttons["focus.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 4))
        XCTAssertEqual(pause.label, "Pause")
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 2))
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 2))

        app.buttons["focus.end"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'End session' AND identifier != 'focus.end'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        // Under five minutes: an honest, gentle summary without a star.
        let headline = app.staticTexts["celebration.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 6))
        XCTAssertEqual(headline.label, "A few quiet minutes.")
    }

    func testUniverseNavigationGestures() {
        let app = launch(reset: true, extra: ["-lumora-skip-onboarding"])
        app.buttons["tab.universe"].tap()
        let canvas = app.otherElements["universe.canvas"].firstMatch
        let counts = app.staticTexts["universe.counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 5))
        let target = canvas.exists ? canvas : app.windows.firstMatch
        target.swipeLeft()
        target.pinch(withScale: 1.6, velocity: 1)
        target.pinch(withScale: 0.6, velocity: -1)
        app.buttons["Zoom in"].tap()
        app.buttons["Zoom out"].tap()
        XCTAssertTrue(counts.exists)
        // Region chips fly the camera; Home Cluster is always open.
        app.buttons["Home Cluster"].tap()
        XCTAssertTrue(app.buttons["tab.today"].exists)
    }

    func testPlannedTaskProgressInSummary() {
        let app = launch(reset: true, extra: ["-lumora-skip-onboarding"])

        // Plan a task on Plan (the editor's estimate defaults to 2 sessions).
        let planTab = app.buttons["tab.plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 15))
        planTab.tap()
        let add = app.buttons["plan.tasksInvite"]
        XCTAssertTrue(add.waitForExistence(timeout: 4), "An empty plan should invite adding a task")
        add.tap()
        let title = app.textFields["taskEditor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        title.typeText("Essay draft")
        app.buttons["taskEditor.save"].tap()
        XCTAssertTrue(app.buttons["tasks.start"].waitForExistence(timeout: 4), "The new task should be listed")
        app.buttons["tab.today"].tap()

        // Choose it on the setup screen.
        let begin = app.buttons["home.beginFocus"]
        XCTAssertTrue(begin.waitForExistence(timeout: 4))
        begin.tap()
        let choose = app.buttons["setup.chooseTask"]
        XCTAssertTrue(choose.waitForExistence(timeout: 4))
        choose.tap()
        let row = app.buttons["taskPicker.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        row.tap()
        let selected = app.buttons["setup.selectedTask"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 4))
        XCTAssertTrue(selected.label.contains("Session 1 of 2 for Essay draft"), "got: \(selected.label)")
        XCTAssertEqual(app.textFields["setup.intention"].value as? String, "Essay draft")
        app.buttons["setup.start"].tap()

        let headline = app.staticTexts["celebration.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 25), "Completion summary should appear")
        let card = app.descendants(matching: .any)["celebration.task"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("1 of 2 sessions for Essay draft"), "got: \(card.label)")
    }

    /// A habit from a template: kept with a tap, reopened, then kept by
    /// focusing on it, which the summary reports.
    func testHabitKeptByTapAndByFocus() {
        let app = launch(reset: true, extra: ["-lumora-skip-onboarding"])

        let planTab = app.buttons["tab.plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 15))
        planTab.tap()
        let invite = app.buttons["plan.habitsInvite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 6), "Plan should invite starting a habit")
        invite.tap()
        let template = app.buttons["habits.template.read"]
        XCTAssertTrue(template.waitForExistence(timeout: 4), "An empty Habits screen offers templates")
        template.tap()
        let save = app.buttons["habitEditor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()

        let star = app.buttons["habit.toggle"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 4), "The new habit should be listed")
        XCTAssertEqual(star.value as? String, "Not kept yet")
        star.tap()
        XCTAssertTrue(app.buttons["habit.toggle"].firstMatch.waitForValue("Kept today", timeout: 3))
        app.buttons["habit.toggle"].firstMatch.tap()
        XCTAssertTrue(app.buttons["habit.toggle"].firstMatch.waitForValue("Not kept yet", timeout: 3))

        // Twenty minutes of reading keeps it by itself.
        let focus = app.buttons["habit.focus"].firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        focus.tap()
        let headline = app.staticTexts["celebration.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 25), "Completion summary should appear")
        let card = app.descendants(matching: .any)["celebration.habit"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "The summary should say the habit was kept")
        XCTAssertTrue(card.label.contains("Read 20 minutes"), "got: \(card.label)")
    }

    /// The Odyssey loop: a world has formed → plot a course → launch →
    /// a focus session powers the journey → land and discover the world.
    func testOdysseyExpeditionLandsAfterFocus() {
        let app = launch(reset: true, extra: ["-lumora-skip-onboarding", "-lumora-demo", "3"])
        app.buttons["tab.odyssey"].tap()
        let begin = app.buttons["odyssey.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()
        let awaits = app.buttons["odyssey.awaits"]
        XCTAssertTrue(awaits.waitForExistence(timeout: 5), "A world should have formed from the seeded focus")
        awaits.tap()
        let plot = app.buttons["world.plot"]
        XCTAssertTrue(plot.waitForExistence(timeout: 5))
        plot.tap()
        let launchButton = app.buttons["plot.launch"]
        XCTAssertTrue(launchButton.waitForExistence(timeout: 5))
        launchButton.tap()

        // The launch cinematic dismisses itself (~3.4 s); then focus to power the ship.
        sleep(5)
        app.buttons["tab.today"].tap()
        runOneSession(app)
        let land = app.buttons["summary.land"]
        XCTAssertTrue(land.waitForExistence(timeout: 8), "The first journey takes one session")
        // The summary's actions are pinned to the bottom; bring the row above them.
        if !land.isHittable || land.frame.maxY > app.buttons["celebration.explore"].frame.minY {
            app.staticTexts["celebration.headline"].swipeUp()
        }
        land.tap()
        let explore = app.buttons["arrival.explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 12), "The discovery card appears after landing")
    }
}


extension XCUIElement {
    /// Waits until the element's accessibility value reads `value`.
    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
