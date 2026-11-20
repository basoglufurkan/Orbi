import XCTest

/// Drives the app screens for the App Store preview videos while
/// `simctl io recordVideo` films the simulator. Prints `CAPTURE-MARK <clip> <start|end> <epoch>` so the take can
/// be cut into named clips. Skipped unless the runner is given
/// `LUMORA_CAPTURE=1` (pass `TEST_RUNNER_LUMORA_CAPTURE=1` to xcodebuild).
@MainActor
final class MarketingCaptureTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var turkish: Bool { env["CAPTURE_LANG"] == "tr" }

    private func requireCapture() throws {
        try XCTSkipUnless(env["LUMORA_CAPTURE"] == "1", "Marketing capture runs only from the capture script")
        continueAfterFailure = false
    }

    private func launch(demo: Int, timeScale: Int = 60, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lumora-ui-testing", "-lumora-reset", "-lumora-skip-onboarding",
                               "-lumora-demo", "\(demo)", "-lumora-time-scale", "\(timeScale)"] + extra
        app.launch()
        // A launch can attach to an instance left over from the previous take
        // (old data, no arguments); a second launch always starts clean.
        app.terminate()
        app.launch()
        return app
    }

    private func mark(_ clip: String, _ edge: String) {
        print("CAPTURE-MARK \(clip) \(edge) \(Date().timeIntervalSince1970)")
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Films `seconds` of whatever is on screen, after an optional action.
    private func scene(_ clip: String, _ seconds: Double, _ action: () -> Void = {}) {
        mark(clip, "start")
        action()
        pause(seconds)
        mark(clip, "end")
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tap(_ el: XCUIElement, timeout: Double = 8) {
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "Missing \(el)")
        el.tap()
    }

    /// The summary's actions are pinned to the bottom; scroll a row above
    /// them first, or the tap lands on "Explore My Universe".
    private func revealAbovePinnedActions(_ el: XCUIElement, _ app: XCUIApplication) {
        let pinned = app.buttons["celebration.explore"]
        let window = app.windows.firstMatch
        for _ in 0..<4 where el.frame.maxY > pinned.frame.minY - 8 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            pause(0.8)
        }
    }

    private func dismissChimePrompt(_ app: XCUIApplication) {
        let notNow = app.buttons["celebration.notNow"]
        guard notNow.waitForExistence(timeout: 3) else { return }
        revealAbovePinnedActions(notNow, app)
        notNow.tap()
    }

    /// Start focus from Home and wait for the completion summary.
    private func runSession(_ app: XCUIApplication) {
        tap(app.buttons["home.beginFocus"])
        tap(app.buttons["setup.start"])
        XCTAssertTrue(app.staticTexts["celebration.headline"].waitForExistence(timeout: 60))
    }

    // MARK: Takes

    /// Scenarios 1, 2 and 4: home → Odyssey → plot → launch → focus → star →
    /// summary → landing → discovery → terraform.
    func test1Journey() throws {
        try requireCapture()
        let app = launch(demo: 40)
        XCTAssertTrue(app.buttons["home.beginFocus"].waitForExistence(timeout: 30))
        pause(2)
        scene("01-home", 3.5)

        tap(app.buttons["tab.odyssey"])
        let begin = app.buttons["odyssey.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        pause(1)
        scene("02-odyssey-intro", 3.5)
        begin.tap()
        let awaits = app.buttons["odyssey.awaits"]
        // A seeded history may also earn a rank-up celebration.
        for _ in 0..<6 where !(awaits.exists && awaits.isHittable) {
            if app.buttons["rankup.continue"].exists {
                pause(1.5)
                scene("xx-rank-up", 2.5)
                app.buttons["rankup.continue"].tap()
            }
            pause(0.5)
        }
        pause(1)
        scene("02b-odyssey-hub", 4)

        awaits.tap()
        let plot = app.buttons["world.plot"]
        XCTAssertTrue(plot.waitForExistence(timeout: 8))
        pause(1)
        scene("03-world-uncharted", 3)
        plot.tap()
        let launchButton = app.buttons["plot.launch"]
        XCTAssertTrue(launchButton.waitForExistence(timeout: 8))
        pause(0.8)
        scene("04-plot-sheet", 2.5)
        scene("05-launch-cinematic", 4.5) { launchButton.tap() }
        scene("06-world-en-route", 2.5)

        tap(app.buttons["tab.today"])
        pause(1)
        scene("07-home-en-route", 3)

        tap(app.buttons["home.beginFocus"])
        XCTAssertTrue(app.textFields["setup.intention"].waitForExistence(timeout: 8))
        pause(1)
        // A recent intention chip fills the field without the keyboard shifting the screen.
        let chip = app.buttons[turkish ? "İspanyolca 6. bölüm" : "Spanish chapter 6"]
        scene("08-setup", 2.5) {
            pause(1.2)
            if chip.exists && chip.isHittable { chip.tap() }
        }

        mark("09-focus-timer", "start")
        tap(app.buttons["setup.start"])
        let timer = element(app, "focus.timer")
        XCTAssertTrue(timer.waitForExistence(timeout: 8))
        let ended = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: timer)
        wait(for: [ended], timeout: 60)
        mark("09-focus-timer", "end")

        mark("10-star-birth", "start")
        XCTAssertTrue(app.staticTexts["celebration.headline"].waitForExistence(timeout: 30))
        pause(1)
        mark("10-star-birth", "end")
        scene("11-summary", 3.5)

        dismissChimePrompt(app)
        let land = app.buttons["summary.land"]
        XCTAssertTrue(land.waitForExistence(timeout: 8))
        revealAbovePinnedActions(land, app)
        pause(1)
        scene("12-summary-arrived", 2.5)

        mark("13-arrival", "start")
        land.tap()
        let explore = app.buttons["arrival.explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 15))
        pause(3)
        mark("13-arrival", "end")

        explore.tap()
        // Landing can complete a rank; its celebration greets the Odyssey tab.
        let onward = app.buttons["rankup.continue"]
        if onward.waitForExistence(timeout: 4) {
            pause(1.5)
            scene("xx-rank-up", 2.5)
            onward.tap()
        }
        let cultivate = app.buttons["world.cultivate"]
        XCTAssertTrue(cultivate.waitForExistence(timeout: 10))
        pause(1.2)
        scene("14-world-charted", 3)
        app.swipeUp()
        for _ in 0..<3 where !cultivate.isHittable {
            pause(0.8)
            if !cultivate.isHittable { app.swipeUp() }
        }
        pause(1.2)
        scene("15-terraform-preview", 3)
        scene("16-terraform-grow", 4) { cultivate.tap() }
    }

    /// Scenario 2: the Pomodoro break after a session.
    func test2Break() throws {
        try requireCapture()
        let app = launch(demo: 40)
        XCTAssertTrue(app.buttons["home.beginFocus"].waitForExistence(timeout: 30))
        runSession(app)
        pause(1)
        scene("17-break-button", 2.5)
        scene("18-break", 7) { app.buttons["celebration.break"].tap() }
    }

    /// Scenario 3: a planned task split into sessions, two already done.
    func test3Tasks() throws {
        try requireCapture()
        let app = launch(demo: 40, timeScale: 600)
        tap(app.buttons["tab.plan"], timeout: 30)
        tap(app.buttons["plan.tasksInvite"])
        let title = app.textFields["taskEditor.title"]
        tap(title)
        title.typeText(turkish ? "Gitar: yeni şarkı" : "Guitar: new song")
        let stepper = app.steppers["taskEditor.estimate"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        let increment = stepper.buttons["Increment"].exists ? stepper.buttons["Increment"] : stepper.buttons.element(boundBy: 1)
        increment.tap()
        increment.tap()
        tap(app.buttons["taskEditor.save"])

        for _ in 0..<2 {
            tap(app.buttons["tasks.start"])
            tap(app.buttons["setup.start"])
            XCTAssertTrue(app.staticTexts["celebration.headline"].waitForExistence(timeout: 40))
            tap(app.buttons["celebration.explore"])
            tap(app.buttons["tab.plan"])
        }
        // The full Tasks list, from Plan's "See all".
        tap(app.buttons["plan.tasks"])
        XCTAssertTrue(app.buttons["tasks.start"].waitForExistence(timeout: 8))
        pause(1)
        scene("19-task-list", 3.5)
        scene("20-task-setup", 3.5) { app.buttons["tasks.start"].tap() }
    }

    /// Scenario 5: the personal sky and insights.
    func test4SkyAndInsights() throws {
        try requireCapture()
        let app = launch(demo: 120)
        tap(app.buttons["tab.universe"], timeout: 40)
        XCTAssertTrue(app.staticTexts["universe.counts"].waitForExistence(timeout: 10))
        pause(2)
        scene("21-universe", 4)
        let canvas = element(app, "universe.canvas")
        scene("22-universe-zoom", 1.5) {
            canvas.pinch(withScale: 1.8, velocity: 0.6)
            pause(1)
            canvas.pinch(withScale: 0.55, velocity: -0.6)
        }
        tap(app.buttons["tab.insights"])
        pause(1.5)
        scene("23-insights", 3)
        scene("24-insights-scroll", 3) { app.swipeUp() }
    }

    /// From a fresh demo history: begin the Odyssey, fly to the first world
    /// on one session and land. Leaves the charted world's page open.
    private func landOnFirstWorld() -> XCUIApplication {
        let app = launch(demo: 40, timeScale: 600)
        XCTAssertTrue(app.buttons["home.beginFocus"].waitForExistence(timeout: 30))
        tap(app.buttons["tab.odyssey"])
        tap(app.buttons["odyssey.begin"])
        let onward = app.buttons["rankup.continue"]
        if onward.waitForExistence(timeout: 3) { onward.tap() }
        tap(app.buttons["odyssey.awaits"])
        tap(app.buttons["world.plot"])
        tap(app.buttons["plot.launch"])
        pause(5)
        tap(app.buttons["tab.today"])
        runSession(app)
        let land = app.buttons["summary.land"]
        XCTAssertTrue(land.waitForExistence(timeout: 8))
        revealAbovePinnedActions(land, app)
        land.tap()
        tap(app.buttons["arrival.explore"], timeout: 15)
        if onward.waitForExistence(timeout: 4) { onward.tap() }
        return app
    }

    /// Odyssey worlds in the Universe sky, each beside the day that formed it.
    func test6OdysseySky() throws {
        try requireCapture()
        let app = landOnFirstWorld()
        let onward = app.buttons["rankup.continue"]
        // Terraform a few stages; the sky shows the world as it grows.
        let cultivate = app.buttons["world.cultivate"]
        XCTAssertTrue(cultivate.waitForExistence(timeout: 10))
        app.swipeUp()
        for _ in 0..<3 where cultivate.waitForExistence(timeout: 4) {
            pause(1)
            if cultivate.isHittable { cultivate.tap() }
            pause(2.5)
        }

        // A few more sessions let new worlds form around the galaxy.
        tap(app.buttons["tab.today"])
        for _ in 0..<3 {
            runSession(app)
            tap(app.buttons["celebration.explore"])
            tap(app.buttons["tab.today"])
        }
        tap(app.buttons["tab.universe"])
        pause(1.5)
        scene("26-universe-odyssey", 5) { app.buttons["universe.odyssey"].tap() }
        // Uncharted worlds are hidden by default; the sky options bring them in.
        tap(app.buttons["universe.skyOptions"])
        let uncharted = app.switches["universe.showUncharted"]
        XCTAssertTrue(uncharted.waitForExistence(timeout: 5))
        scene("26b-universe-uncharted", 3.5) { uncharted.tap() }
        tap(app.buttons["Done"])
        let zoomOut = app.buttons["universe.zoomOut"]
        scene("26c-universe-odyssey-wide", 3) {
            for _ in 0..<3 { zoomOut.tap(); pause(0.5) }
        }
        tap(app.buttons["universe.skyOptions"])
        uncharted.tap()
        tap(app.buttons["Done"])
        tap(app.buttons["universe.odyssey"])
        pause(1.2)
        pause(0.8)

        // Tapping a world in the sky opens it in the Odyssey.
        let world = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Rosel Minor,")).firstMatch
        XCTAssertTrue(world.waitForExistence(timeout: 5))
        scene("27-universe-open-world", 3) { world.tap() }
        XCTAssertTrue(app.buttons["world.cultivate"].waitForExistence(timeout: 8), "The world opens from the sky")

        // Share the whole universe as an image.
        tap(app.buttons["tab.universe"])
        pause(1.5)
        scene("28-universe-share", 4) { app.buttons["universe.share"].tap() }
    }

    /// Visiting a charted world grown to City Lights: one full day on its surface.
    func test8SurfaceVisit() throws {
        try requireCapture()
        let app = landOnFirstWorld()
        let cultivate = app.buttons["world.cultivate"]
        XCTAssertTrue(cultivate.waitForExistence(timeout: 10))
        app.swipeUp()
        for _ in 0..<4 where cultivate.waitForExistence(timeout: 4) {
            pause(1)
            if cultivate.isHittable { cultivate.tap() }
            pause(2.5)
        }
        app.swipeDown()
        app.swipeDown()
        let visit = app.buttons["world.visit"]
        XCTAssertTrue(visit.waitForExistence(timeout: 5))
        scene("30-surface-day-cycle", 17) { visit.tap() }
        scene("30b-surface-night", 4) { app.buttons["visit.night"].tap() }
        tap(app.buttons["visit.close"])
    }

    /// A rare event on its day: the hub card, the Home line, witnessing it in
    /// a session, and its Codex entry. Then the Hangar's chain trails.
    func test9RareEvent() throws {
        try requireCapture()
        let app = launch(demo: 40, timeScale: 600, extra: ["-lumora-event-today", "comet"])
        XCTAssertTrue(app.buttons["home.beginFocus"].waitForExistence(timeout: 30))
        tap(app.buttons["tab.odyssey"])
        tap(app.buttons["odyssey.begin"])
        let onward = app.buttons["rankup.continue"]
        if onward.waitForExistence(timeout: 3) { onward.tap() }
        let card = element(app, "odyssey.event")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Bring the card's top just under the header.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)))
        pause(1.2)
        scene("31-event-card", 4)

        tap(app.buttons["tab.today"])
        pause(1.2)
        scene("32-event-home", 3)
        runSession(app)
        dismissChimePrompt(app)
        let witnessed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Veyra")).firstMatch
        XCTAssertTrue(witnessed.waitForExistence(timeout: 8), "The summary shows the witnessed event")
        revealAbovePinnedActions(witnessed, app)
        pause(1)
        scene("33-event-witnessed", 3)

        tap(app.buttons["celebration.explore"])
        tap(app.buttons["tab.odyssey"])
        if onward.waitForExistence(timeout: 4) { onward.tap(); pause(0.8) }
        // The Codex link sits at the very bottom, under the floating tab bar until scrolled clear.
        let codex = app.buttons["odyssey.codex"]
        for _ in 0..<6 { app.swipeUp(); pause(0.3) }
        pause(0.8)
        codex.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        pause(1.2)
        scene("34-event-codex", 3)
        tap(app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Back", "Geri")).firstMatch)
        app.buttons["odyssey.hangar"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        pause(1)
        app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Trail", "İz")).firstMatch.tap()
        pause(1)
        app.swipeUp()
        pause(1)
        scene("35-chain-trails", 3)
    }

    /// Focusing together with a (simulated) friend: invite, they join, start
    /// together, finish, and the bridge of light in the sky.
    func test10Together() throws {
        try requireCapture()
        let app = launch(demo: 30, timeScale: 600, extra: ["-lumora-together-demo"])
        tap(app.buttons["home.beginFocus"], timeout: 30)
        tap(app.buttons["setup.together"])
        let name = app.textFields["together.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        pause(1)
        scene("36-together-sheet", 2.5)
        name.tap()
        name.typeText("Furkan\n")
        tap(app.buttons["together.invite"])
        XCTAssertTrue(element(app, "together.roomCode").waitForExistence(timeout: 5))
        scene("37-together-lobby", 3)
        let start = app.buttons["together.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "The friend joins")
        scene("38-together-joined", 2.5)
        scene("39-together-countdown", 4.5) { start.tap() }
        XCTAssertTrue(element(app, "focus.timer").waitForExistence(timeout: 10))
        scene("40-together-focusing", 2.5)
        let together = element(app, "summary.together")
        XCTAssertTrue(app.staticTexts["celebration.headline"].waitForExistence(timeout: 60))
        dismissChimePrompt(app)
        XCTAssertTrue(together.waitForExistence(timeout: 8))
        revealAbovePinnedActions(together, app)
        pause(1.5)
        scene("41-together-summary", 3)
        tap(app.buttons["celebration.explore"])
        pause(2.5)
        let canvas = element(app, "universe.canvas")
        scene("42-together-bridge", 4) { canvas.pinch(withScale: 2.2, velocity: 0.8) }
    }

    /// The year in review: every card of the story, then sharing one.
    func test11YearInReview() throws {
        try requireCapture()
        let app = launch(demo: 160)
        tap(app.buttons["tab.insights"], timeout: 40)
        tap(app.buttons["insights.year"])
        let card = element(app, "year.card")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        for i in 0..<10 {
            pause(1.2)
            scene(String(format: "43-year-%02d", i), 2)
            guard card.exists else { break }
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        }
    }

    /// Debug preview: a universe where everything has happened.
    func test7FinishedUniverse() throws {
        try requireCapture()
        let app = launch(demo: 3)
        tap(app.buttons["home.settings"], timeout: 30)
        let open = app.buttons["debug.finishedUniverse"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp(); pause(0.4) }
        open.tap()
        let canvas = element(app, "finished.canvas")
        XCTAssertTrue(app.staticTexts["Finished universe"].waitForExistence(timeout: 90))
        pause(2)
        scene("29-finished-universe", 4)
        scene("29b-finished-universe-close", 4) {
            canvas.pinch(withScale: 2.6, velocity: 0.8)
        }
    }

    /// Scenario 6: a universe grown over most of a year.
    func test5YearsOfSky() throws {
        try requireCapture()
        let app = launch(demo: 900)
        tap(app.buttons["tab.universe"], timeout: 120)
        XCTAssertTrue(app.staticTexts["universe.counts"].waitForExistence(timeout: 20))
        pause(2)
        let canvas = element(app, "universe.canvas")
        scene("25-universe-years", 5) { canvas.pinch(withScale: 0.5, velocity: -0.4) }
    }
}
