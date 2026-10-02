import UIKit
import XCTest

/// Screenshot harness: one test per Baseline screen — the three tabs (`home`, `trends`, `sleep`), the
/// journal sheet over Home (`journal`, via Home's "Journal" button), Settings (`settings`, via the gear) and
/// its Devices / Apple Health / Import / Compare / Export / Accuracy pushes, Trends' embedded Progress and Habits
/// sections (via the pinned segments), Workouts and its detail — plus the three welcome steps and the launch
/// frame. Each test launches the app with its DEBUG launch arguments (`--tab home|trends|sleep`, always with
/// `--ui-testing`, which pins the tab bar so a scrolled capture is deterministic),
/// waits for the screen's first card, captures the top of the screen, then scrolls up until the content
/// stops moving (at most 12 scrolls), capturing after each scroll. Every PNG is written as
/// `<screen>-<n>.png` to `$BASELINE_SHOTS_DIR` (default `/private/tmp/baseline-shots`) and attached to the
/// test result, so a scrolled screen can be verified headlessly. Run it through
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

    func testHome() throws {
        try captureTab("home", firstCard: "HRV")
    }

    func testTrends() throws {
        try captureTab("trends", firstCard: "HRV")
    }

    func testSleep() throws {
        try captureTab("sleep", firstCard: "Sleep timing")
    }

    /// Home → the floating "Journal" button → `JournalSheet` at its medium detent (the journal is not a
    /// tab). Captures the sheet as it opens over Home (`journal-0`), lifts it to the large detent and
    /// captures again (`journal-1`). The sheet is not scrolled: its habits fit one screen, and a gutter
    /// drag over a sheet with nothing left to scroll makes XCUITest's event synthesis time out.
    func testJournal() throws {
        let app = launchTab("home")
        XCTAssertTrue(openJournal(app), "home: Journal button did not open the sheet")
        let card = app.staticTexts["Habits"].firstMatch
        let cardShown = card.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 0.6)
        // The sheet has one medium detent, so the one frame is the whole capture.
        try save(XCUIScreen.main.screenshot(), as: "journal-0")
        XCTAssertTrue(cardShown, "journal: first card (Habits) did not appear (screenshots still written)")
    }

    func testSettings() throws {
        // The strap card's status line ("Connected" / "Not connected") is a plain Text; the row titles
        // below it sit inside buttons, whose children XCUITest folds into one label.
        // `-baseline.eveningCheckIn.enabled YES` seeds the AppStorage key through UserDefaults' argument
        // domain, so the Notifications card shows the evening toggle on with its time row, without the
        // tap that would ask for notification permission (a system alert over the capture).
        let app = launchSettings(extraArguments: ["-baseline.eveningCheckIn.enabled", "YES"])
        try capturePushed(app, screen: "settings", title: nil,
                          firstCard: NSPredicate(format: "label CONTAINS[c] %@", "connected"))
    }

    // MARK: - Sections and pushed screens (seeded, onboarding skipped)

    /// Trends → the "Progress" segment of the pinned section control → the Progress section (HRV /
    /// resting HR / sleep baselines over months), embedded in the Trends screen: the navigation title
    /// stays "Trends", so the switch is confirmed by the segment's selected state and the first card.
    func testProgress() throws {
        let app = launchTab("trends")
        selectTrendsSection(app, "Progress")
        try capturePushed(app, screen: "progress", title: nil,
                          firstCard: NSPredicate(format: "label == %@", "HRV baseline"))
    }

    /// Trends → the "Habits" segment → the journal patterns (what moves your HRV / Resting HR, dose rows),
    /// embedded like Progress.
    func testHabits() throws {
        let app = launchTab("trends")
        selectTrendsSection(app, "Habits")
        try capturePushed(app, screen: "habits", title: nil,
                          firstCard: NSPredicate(format: "label BEGINSWITH %@", "What moves your"))
    }

    /// Home → effort card's "All workouts" link → the Workouts list, then its first row → the detail.
    func testWorkouts() throws {
        let app = launchTab("home")
        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "All workouts")).firstMatch
        XCTAssertTrue(scrollUntilHittable(app, link), "home: All workouts link did not appear")
        link.tap()
        try capturePushed(app, screen: "workouts", title: "Workouts",
                          firstCard: NSPredicate(format: "label CONTAINS[c] %@", "workout"))

        // Back to Home and in again, so the list is at its top with the newest row on screen. The rows
        // are plain NavigationLinks whose children stay separate elements, so the row is reached through
        // its "… bpm" text.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 10), "home: All workouts link did not reappear")
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
        let app = launchSettings()
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
        let app = launchSettings()
        try openSettingsRow(app, "Apple Health")
        try capturePushed(app, screen: "apple-health", title: "Apple Health",
                          firstCard: NSPredicate(format: "label == %@", "Baseline reads"))
    }

    /// Settings → Import data: the WHOOP export and Apple Health export cards.
    func testImport() throws {
        let app = launchSettings()
        try openSettingsRow(app, "Import data")
        try capturePushed(app, screen: "import", title: "Import",
                          firstCard: NSPredicate(format: "label == %@", "WHOOP export"))
    }

    /// Settings → Compare sources: under the demo seed only the strap's own nights exist (no WHOOP or
    /// Apple Health import), so this is the empty state; with an import it is the metric card and the
    /// night-by-night list.
    func testCompare() throws {
        let app = launchSettings()
        try openSettingsRow(app, "Compare sources")
        try capturePushed(app, screen: "compare", title: "Compare",
                          firstCard: NSPredicate(format: "label == %@ OR label CONTAINS %@",
                                                 "Nothing to compare yet", "Baseline vs"))
    }

    /// Settings → Export CSV: the one card (what the zip holds, the stored-history line, the button).
    func testExport() throws {
        let app = launchSettings()
        try openSettingsRow(app, "Export CSV")
        try capturePushed(app, screen: "export", title: "Export",
                          firstCard: NSPredicate(format: "label == %@", "CSV export"))
    }

    /// Settings → About → "How accurate is this?": the Accuracy screen, one card per evidence tier
    /// (High / Medium / Low accuracy) listing every metric with its caveat and the studies behind it. The
    /// row sits in the About card at the foot of Settings, so the row lookup scrolls down to it.
    func testAccuracy() throws {
        let app = launchSettings()
        try openSettingsRow(app, "How accurate is this?")
        try capturePushed(app, screen: "accuracy", title: "Accuracy",
                          firstCard: NSPredicate(format: "label == %@", "High accuracy"))
    }

    /// Home with Settings pushed from the gear in the bar (every tab root carries it; Home is the launch
    /// tab). Waits for the "Settings" navigation title.
    private func launchSettings(extraArguments: [String] = []) -> XCUIApplication {
        let app = launchTab("home", extraArguments: extraArguments)
        XCTAssertTrue(openSettings(app), "home: Settings gear did not push Settings")
        return app
    }

    /// Taps the Settings row whose folded label (title + subtitle) starts with `title`.
    private func openSettingsRow(_ app: XCUIApplication, _ title: String) throws {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(scrollUntilHittable(app, row), "settings: \(title) row did not appear")
        row.tap()
    }

    // MARK: - Sample data (Release path: no demo seed)

    /// The App Review path: launched WITHOUT the demo seed (an empty store), Settings › About › "Show
    /// sample data" on, back to Home, which now wears the "Sample data" pill over populated cards
    /// (`sample-home-0`), then the toggle off again so the simulator's store is left as it was found.
    func testSampleData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-testing"]
        app.launch()
        let home = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Today")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10), "sample: Today title did not appear")
        XCTAssertTrue(openSettings(app), "sample: Settings gear did not push Settings")

        let toggle = app.switches["sample-data-toggle"].firstMatch
        XCTAssertTrue(scrollUntilHittable(app, toggle), "sample: Show sample data toggle did not appear")
        // A previous run that failed mid-way may have left the sample in the store: start from off.
        if Self.isOn(toggle) {
            Self.flip(toggle)
            XCTAssertTrue(Self.wait(toggle, labelContains: "Off"), "sample: leftover sample data did not clear")
        }
        Self.flip(toggle)
        XCTAssertTrue(Self.wait(toggle, labelContains: "60 made-up nights"), "sample: insert did not finish")

        app.navigationBars.buttons.firstMatch.tap()   // back to Home
        let pill = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sample data is shown")).firstMatch
        let pillShown = pill.waitForExistence(timeout: 20)
        let ring = app.staticTexts["HRV"].firstMatch
        let ringShown = ring.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 0.8)   // the rings' value arcs animate in
        try save(XCUIScreen.main.screenshot(), as: "sample-home-0")
        XCTAssertTrue(pillShown, "sample: Home did not show the Sample data pill (screenshot still written)")
        XCTAssertTrue(ringShown, "sample: Home did not show the HRV ring (screenshot still written)")

        XCTAssertTrue(openSettings(app), "sample: Settings gear did not push Settings again")
        XCTAssertTrue(scrollUntilHittable(app, toggle), "sample: toggle did not reappear")
        Self.flip(toggle)
        XCTAssertTrue(Self.wait(toggle, labelContains: "Off"), "sample: removal did not finish")
    }

    private static func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    /// Flips a SwiftUI `Toggle` that carries a row label. XCUITest exposes it as an outer `Switch` (the
    /// whole row, labelled) wrapping the inner UISwitch at the trailing edge; tapping the outer element's
    /// centre lands on the label text, which does not flip an iOS switch. Tap the inner switch when it
    /// is exposed, else the row's trailing edge.
    private static func flip(_ toggle: XCUIElement) {
        let knob = toggle.switches.firstMatch
        if knob.exists && knob.isHittable {
            knob.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
    }

    /// Waits (up to 30 s) for the switch's folded label (title + subtitle) to contain `text`: the card's
    /// subtitle reports "Adding 60 nights…" / "Removing…" while a write runs, then the settled state.
    private static func wait(_ toggle: XCUIElement, labelContains text: String, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if toggle.exists, toggle.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return toggle.exists && toggle.label.contains(text)
    }

    // MARK: - Launch

    /// The earliest frame XCUITest can grab after launch, before waiting for any card, so the launch
    /// background (the `LaunchBackground` asset: BaselineTheme's off-white wash in both appearances, so
    /// nothing flashes between the launch screen and the first paint) and the first paint can be checked
    /// as `launch-0` / `launch-1`. Lands on Home, whose title is the selected day: "Today" at launch.
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding", "--ui-testing"]
        app.launch()
        try save(XCUIScreen.main.screenshot(), as: "launch-0")
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Today")).firstMatch
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

    /// Launches the seeded app on `tab` (`home`, `trends` or `sleep`) with onboarding skipped (and
    /// `--ui-testing`, which pins the tab bar so the scroll loop never sees it animating) and waits for the
    /// navigation title that `--tab` lands on. `-baseline.profileSet YES` seeds Settings › Profile's
    /// "entered" flag through UserDefaults' argument domain, so Progress' Fitness card estimates from the
    /// demo profile instead of asking for a date of birth and sex.
    private func launchTab(_ tab: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding", "--tab", tab, "-baseline.profileSet", "YES", "--ui-testing"]
            + extraArguments
        app.launch()
        let expected = Self.launchTitle(for: tab)
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", expected)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "\(tab): \"\(expected)\" navigation title did not appear")
        return app
    }

    /// The navigation-bar title `--tab <tab>` lands on. Home's title is the selected day, "Today" on a cold
    /// launch (`BaselineDaySwitcher.title`), so `home` (and its `today` alias) waits for that word; `trends`
    /// and `sleep` are their own titles. Matched case-insensitively.
    private static func launchTitle(for tab: String) -> String {
        switch tab {
        case "today", "home": return "Today"
        default: return tab
        }
    }

    /// The gear in the bar (accessibility label "Settings", a NavigationLink that pushes SettingsScreen):
    /// taps it until the pushed screen's "Settings" title appears (a tap that lands while the seeded screen
    /// is still settling can be swallowed; three tries). The gear and the pushed title share the word, so
    /// the gear is looked up among the bar's buttons and the title among its static texts.
    @discardableResult
    private func openSettings(_ app: XCUIApplication) -> Bool {
        let gear = app.navigationBars.buttons["Settings"].firstMatch
        guard gear.waitForExistence(timeout: 20) else {
            XCTFail("home: Settings gear did not appear")
            return false
        }
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Settings")).firstMatch
        for _ in 1...3 {
            gear.tap()
            if title.waitForExistence(timeout: 6) { return true }
            guard gear.exists && gear.isHittable else { break }
        }
        return title.exists
    }

    /// Home's floating "Journal" button (a glass capsule in the bottom safe-area bar): taps it until the
    /// sheet's own "Journal" bar title appears (three tries).
    @discardableResult
    private func openJournal(_ app: XCUIApplication) -> Bool {
        let button = app.buttons["Journal"].firstMatch
        guard button.waitForExistence(timeout: 20) else {
            XCTFail("home: Journal button did not appear")
            return false
        }
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Journal")).firstMatch
        for _ in 1...3 {
            button.tap()
            if title.waitForExistence(timeout: 6) { return true }
            guard button.exists && button.isHittable else { break }
        }
        return title.exists
    }

    /// Trends' pinned section control: taps the segment named `label` until it carries the selected trait
    /// (a tap that lands while the seeded screen is still settling can be swallowed; three tries). The
    /// navigation title stays "Trends" whichever section shows, so the trait, not a title, is the signal.
    @discardableResult
    private func selectTrendsSection(_ app: XCUIApplication, _ label: String) -> Bool {
        let segment = app.buttons[label].firstMatch
        guard segment.waitForExistence(timeout: 20) else {
            XCTFail("trends: \(label) segment did not appear")
            return false
        }
        for _ in 1...3 {
            segment.tap()
            if segment.wait(for: \.isSelected, toEqual: true, timeout: 6) { return true }
        }
        XCTFail("trends: \(label) segment did not become selected")
        return false
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

    /// Scrolls up (at most twelve times) until `element` exists, is hittable and sits clear of Home's
    /// floating bottom bar (the "Journal" button): XCUITest reports a row under that bar as hittable, but
    /// the tap lands on the bar, exactly as content under a tab bar is out of reach.
    @discardableResult
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<12 {
            if element.exists && element.isHittable && Self.clearOfBottomBar(app, element) { return true }
            scrollUp(app)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return element.exists && element.isHittable
    }

    /// True unless the floating "Journal" bar is on screen and `element` overlaps its band.
    private static func clearOfBottomBar(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        let bar = app.buttons["Journal"].firstMatch
        guard bar.exists else { return true }
        return element.frame.maxY <= bar.frame.minY - 8
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
        app.launchArguments = ["--reset-onboarding", "--welcome-step", String(step), "--ui-testing"]
        app.launch()

        let shown = app.staticTexts[marker].firstMatch.waitForExistence(timeout: 10)
        let name = "welcome-\(step)"
        try save(XCUIScreen.main.screenshot(), as: "\(name)-0")
        XCTAssertTrue(shown, "\(name): \"\(marker)\" did not appear (screenshot still written)")
    }

    /// Top capture (`<screen>-0`), then scroll up and capture until two consecutive captures are
    /// pixel-identical below the status bar (the content stopped moving) or twelve scrolls have been taken.
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
