import UIKit
import XCTest

/// Screenshot harness: one test per Baseline screen (tabs, pushed screens, Settings' Devices / Apple Health /
/// Import / Compare / Export) plus the three welcome steps and the launch frame. Each test launches the
/// app with its DEBUG launch arguments, waits for the screen's first card, captures the top of the screen,
/// then scrolls up until the content stops moving (at most 12 scrolls), capturing after each scroll. Every PNG
/// is written as `<screen>-<n>.png` to `$BASELINE_SHOTS_DIR` (default `/private/tmp/baseline-shots`) and
/// attached to the test result, so a scrolled screen can be verified headlessly. Run it through
/// `Baseline/scripts/ui-shots.sh` for a fixed 9:41 status bar. See BASELINE.md.
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        // Clean status bar (9:41, full battery, full bars) for every frame. XCUITest cannot run
        // `xcrun simctl status_bar … override` itself (it runs inside the simulator, simctl on the host),
        // so the override is applied by Baseline/scripts/ui-shots.sh before the suite starts and cleared
        // after; see BASELINE.md. Nothing to do here but say so: run through the script for clean frames.
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
        // `-baseline.eveningCheckIn.enabled YES` seeds the AppStorage key through UserDefaults' argument
        // domain, so the Notifications card shows the evening toggle on with its time row, without the
        // tap that would ask for notification permission (a system alert over the capture).
        try captureTab("settings", firstCard: NSPredicate(format: "label CONTAINS[c] %@", "connected"),
                       extraArguments: ["-baseline.eveningCheckIn.enabled", "YES"])
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

    // MARK: - Settings pushes (seeded, onboarding skipped)

    /// Settings → Devices: with no strap bonded the empty state, the "Add strap" button and the pairing
    /// help; then the "Add strap" chooser sheet, captured once as `devices-add-0`.
    func testDevices() throws {
        let app = launchTab("settings")
        try openSettingsRow(app, "Devices")
        try capturePushed(app, screen: "devices", title: "Devices",
                          firstCard: NSPredicate(format: "label == %@", "No strap yet"))

        let add = app.buttons["Add strap"].firstMatch
        XCTAssertTrue(scrollUntilHittable(app, add), "devices: Add strap button did not appear")
        add.tap()
        let chooser = app.staticTexts["Which strap are you adding?"].firstMatch
        let shown = chooser.waitForExistence(timeout: 10)
        try save(XCUIScreen.main.screenshot(), as: "devices-add-0")
        XCTAssertTrue(shown, "devices: Add strap sheet did not appear (screenshot still written)")
    }

    /// Settings → Apple Health: the access card, what Baseline reads and writes back.
    func testAppleHealth() throws {
        let app = launchTab("settings")
        try openSettingsRow(app, "Apple Health")
        try capturePushed(app, screen: "apple-health", title: "Apple Health",
                          firstCard: NSPredicate(format: "label == %@", "Baseline reads"))
    }

    /// Settings → Import data: the WHOOP export and Apple Health export cards.
    func testImport() throws {
        let app = launchTab("settings")
        try openSettingsRow(app, "Import data")
        try capturePushed(app, screen: "import", title: "Import",
                          firstCard: NSPredicate(format: "label == %@", "WHOOP export"))
    }

    /// Settings → Compare sources: under the demo seed only the strap's own nights exist (no WHOOP or
    /// Apple Health import), so this is the empty state; with an import it is the metric card and the
    /// night-by-night list.
    func testCompare() throws {
        let app = launchTab("settings")
        try openSettingsRow(app, "Compare sources")
        try capturePushed(app, screen: "compare", title: "Compare",
                          firstCard: NSPredicate(format: "label == %@ OR label CONTAINS %@",
                                                 "Nothing to compare yet", "Baseline vs"))
    }

    /// Settings → Export CSV: the one card (what the zip holds, the stored-history line, the button).
    func testExport() throws {
        let app = launchTab("settings")
        try openSettingsRow(app, "Export CSV")
        try capturePushed(app, screen: "export", title: "Export",
                          firstCard: NSPredicate(format: "label == %@", "CSV export"))
    }

    /// Taps the Settings row whose folded label (title + subtitle) starts with `title`.
    private func openSettingsRow(_ app: XCUIApplication, _ title: String) throws {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(scrollUntilHittable(app, row), "settings: \(title) row did not appear")
        row.tap()
    }

    // MARK: - Launch

    /// The earliest frame XCUITest can grab after launch, before waiting for any card, so the launch
    /// background (navy, never white) and the first paint can be checked as `launch-0` / `launch-1`.
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding"]
        app.launch()
        try save(XCUIScreen.main.screenshot(), as: "launch-0")
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "today")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "launch: Today title did not appear")
        try save(XCUIScreen.main.screenshot(), as: "launch-1")
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

    private func captureTab(_ tab: String, firstCard: NSPredicate, extraArguments: [String] = []) throws {
        let app = launchTab(tab, extraArguments: extraArguments)
        // The demo seed runs after launch and the screen's `.task` rebuilds once `repo.loaded` flips, so
        // the first card can lag the title by a few seconds.
        let card = app.staticTexts.matching(firstCard).firstMatch
        let cardShown = card.waitForExistence(timeout: 20)

        try captureScrolled(app, screen: tab)

        XCTAssertTrue(cardShown, "\(tab): first card (\(firstCard.predicateFormat)) did not appear (screenshots still written)")
    }

    /// Launches the seeded app on `tab` with onboarding skipped and waits for the tab's navigation title.
    private func launchTab(_ tab: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding", "--tab", tab] + extraArguments
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

    /// Top capture, then scroll up and capture until two consecutive captures are pixel-identical below
    /// the status bar (the content stopped moving) or twelve scrolls have been taken.
    private func captureScrolled(_ app: XCUIApplication, screen: String) throws {
        var previous = XCUIScreen.main.screenshot()
        var previousContent = Self.contentBelowStatusBar(previous)
        try save(previous, as: "\(screen)-0")

        for n in 1...12 {
            scrollUp(app)
            // Let the bounce at the end settle before comparing frames.
            Thread.sleep(forTimeInterval: 0.6)
            let shot = XCUIScreen.main.screenshot()
            let content = Self.contentBelowStatusBar(shot)
            if content == previousContent { break }
            try save(shot, as: "\(screen)-\(n)")
            previous = shot
            previousContent = content
        }
    }

    /// Height of the band ignored when two frames are compared: the status bar (clock, battery, signal)
    /// on every iPhone Baseline targets sits inside the top 62pt, including the Dynamic Island models.
    /// With `ui-shots.sh`'s status-bar override the band is static anyway; cropping it makes the
    /// scroll-stop detection hold when the suite is run without the override (the minute may tick
    /// between two captures) or when the host's clock rolls over.
    private static let statusBarBandPoints: CGFloat = 62

    /// The screenshot's pixels below the status bar as PNG data, the frame-to-frame comparison key.
    private static func contentBelowStatusBar(_ screenshot: XCUIScreenshot) -> Data {
        let image = screenshot.image
        guard let cg = image.cgImage else { return screenshot.pngRepresentation }
        let band = Int((statusBarBandPoints * image.scale).rounded(.up))
        let rect = CGRect(x: 0, y: band, width: cg.width, height: max(cg.height - band, 1))
        guard let cropped = cg.cropping(to: rect) else { return screenshot.pngRepresentation }
        return UIImage(cgImage: cropped).pngData() ?? screenshot.pngRepresentation
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
