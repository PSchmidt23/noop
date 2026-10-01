import XCTest

/// Screenshot harness: one test per Baseline screen plus the three welcome steps. Each test launches the
/// app with its DEBUG launch arguments, waits for the screen's first card, captures the top of the screen,
/// then swipes up until the content stops moving (at most 8 swipes), capturing after each swipe. Every PNG
/// is written as `<screen>-<n>.png` to `$BASELINE_SHOTS_DIR` (default `/private/tmp/baseline-shots`) and
/// attached to the test result, so a scrolled screen can be verified headlessly. See BASELINE.md.
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Tabs (seeded, onboarding skipped)

    func testToday() throws {
        try captureTab("today", firstCard: "HRV")
    }

    func testTrends() throws {
        try captureTab("trends", firstCard: "HRV")
    }

    func testSleep() throws {
        try captureTab("sleep", firstCard: "Stages")
    }

    func testJournal() throws {
        try captureTab("journal", firstCard: "Habits")
    }

    func testSettings() throws {
        // The strap card's status line ("Connected" / "Not connected") is a plain Text; the row titles
        // below it sit inside buttons, whose children XCUITest folds into one label.
        try captureTab("settings", firstCard: NSPredicate(format: "label CONTAINS[c] %@", "connected"))
    }

    // MARK: - Pushed screens (seeded, onboarding skipped)

    /// Trends → "Progress" toolbar button → the Progress screen (HRV / resting HR / sleep / sleep timing).
    func testProgress() throws {
        let app = launchTab("trends")
        // The toolbar can lag the seeded first paint by a few seconds on a fresh install.
        let button = app.buttons["Progress"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "trends: Progress toolbar button did not appear")
        button.tap()
        try capturePushed(app, screen: "progress", title: "Progress",
                          firstCard: NSPredicate(format: "label == %@", "HRV baseline"))
    }

    /// Today → effort card's "All workouts" link → the Workouts list, then its first row → the detail.
    func testWorkouts() throws {
        let app = launchTab("today")
        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "All workouts")).firstMatch
        XCTAssertTrue(scrollUntilHittable(app, link), "today: All workouts link did not appear")
        link.tap()
        try capturePushed(app, screen: "workouts", title: "Workouts",
                          firstCard: NSPredicate(format: "label CONTAINS[c] %@", "workout"))

        // Back to Today and in again, so the list is at its top with the newest row on screen. The rows
        // are plain NavigationLinks whose children stay separate elements, so the row is reached through
        // its "… bpm" text.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 10), "today: All workouts link did not reappear")
        link.tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "bpm")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "workouts: no workout row to open (screenshots still written)")
        guard row.exists else { return }
        row.tap()
        try capturePushed(app, screen: "workout-detail", title: nil,
                          firstCard: NSPredicate(format: "label == %@", "Session"))
    }

    // MARK: - Welcome (onboarding reset; a page TabView, so no scroll)

    func testWelcomeStep0() throws {
        try captureWelcome(step: 0, marker: "Your HRV and resting heart rate, against your own baseline.")
    }

    func testWelcomeStep1() throws {
        try captureWelcome(step: 1, marker: "Pair your strap")
    }

    func testWelcomeStep2() throws {
        try captureWelcome(step: 2, marker: "Apple Health")
    }

    // MARK: - Drivers

    /// Launches on `tab` with the demo seed, waits for the nav title and `firstCard` (the exact label of a
    /// static text the seeded screen always shows), then captures the top and every scroll position below.
    private func captureTab(_ tab: String, firstCard: String) throws {
        try captureTab(tab, firstCard: NSPredicate(format: "label == %@", firstCard))
    }

    private func captureTab(_ tab: String, firstCard: NSPredicate) throws {
        let app = launchTab(tab)
        // The demo seed runs after launch and the screen's `.task` rebuilds once `repo.loaded` flips, so
        // the first card can lag the title by a few seconds.
        let card = app.staticTexts.matching(firstCard).firstMatch
        let cardShown = card.waitForExistence(timeout: 20)

        try captureScrolled(app, screen: tab)

        XCTAssertTrue(cardShown, "\(tab): first card (\(firstCard.predicateFormat)) did not appear (screenshots still written)")
    }

    /// Launches the seeded app on `tab` with onboarding skipped and waits for the tab's navigation title.
    private func launchTab(_ tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding", "--tab", tab]
        app.launch()
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", tab)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "\(tab): navigation title did not appear")
        return app
    }

    /// A screen pushed by a tap: waits for `title` (when given) and `firstCard`, then captures top and
    /// every scroll position below as `<screen>-<n>.png`.
    private func capturePushed(_ app: XCUIApplication, screen: String, title: String?, firstCard: NSPredicate) throws {
        if let title {
            let nav = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
            XCTAssertTrue(nav.waitForExistence(timeout: 10), "\(screen): navigation title did not appear")
        }
        let card = app.staticTexts.matching(firstCard).firstMatch
        let cardShown = card.waitForExistence(timeout: 20)
        try captureScrolled(app, screen: screen)
        XCTAssertTrue(cardShown, "\(screen): first card (\(firstCard.predicateFormat)) did not appear (screenshots still written)")
    }

    /// Scrolls up (at most twelve times) until `element` exists and is hittable.
    @discardableResult
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<12 {
            if element.exists && element.isHittable { return true }
            scrollUp(app)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return element.exists && element.isHittable
    }

    /// One deterministic scroll of ~45% of the screen: a drag in the 20pt left gutter, held at the end so
    /// there is no fling. A centre swipe would land on a chart (Trends scrubs instead of scrolling) or a
    /// control, and would decelerate by an unpredictable distance.
    private func scrollUp(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.80))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.34))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity.fast, thenHoldForDuration: 0.15)
    }

    /// Launches the welcome flow on `step` and captures it once; the pager would change page on a swipe,
    /// so the step is not scrolled.
    private func captureWelcome(step: Int, marker: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--welcome-step", String(step)]
        app.launch()

        let shown = app.staticTexts[marker].firstMatch.waitForExistence(timeout: 10)
        let name = "welcome-\(step)"
        try save(XCUIScreen.main.screenshot(), as: "\(name)-0")
        XCTAssertTrue(shown, "\(name): \"\(marker)\" did not appear (screenshot still written)")
    }

    /// Top capture, then scroll up and capture until two consecutive captures are pixel-identical (the
    /// content stopped moving) or twelve scrolls have been taken.
    private func captureScrolled(_ app: XCUIApplication, screen: String) throws {
        var previous = XCUIScreen.main.screenshot()
        try save(previous, as: "\(screen)-0")

        for n in 1...12 {
            scrollUp(app)
            // Let the bounce at the end settle before comparing frames.
            Thread.sleep(forTimeInterval: 0.6)
            let shot = XCUIScreen.main.screenshot()
            if shot.pngRepresentation == previous.pngRepresentation { break }
            try save(shot, as: "\(screen)-\(n)")
            previous = shot
        }
    }

    // MARK: - Output

    private static let shotsDir: URL = {
        let path = ProcessInfo.processInfo.environment["BASELINE_SHOTS_DIR"] ?? "/private/tmp/baseline-shots"
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    /// Writes the PNG to the shots directory (created on first use; simulator processes can write host
    /// paths) and attaches it to the test result.
    private func save(_ screenshot: XCUIScreenshot, as name: String) throws {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = ScreenshotTests.shotsDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: file, options: .atomic)
    }
}
