import UIKit
import XCTest

/// App Store marketing set: one test, six frames (01 Home, 02 Trends, 03 Progress, 04 Sleep, 05 Habits,
/// 06 Workouts), each the top of a seeded screen, written as
/// `<shots dir>/marketing/NN-<screen>.png` (and attached to the test result). Baseline/scripts/frame-shots.swift
/// turns them into captioned 1320×2868 App Store frames.
///
/// Apple's required size for the 6.9-inch class is 1320×2868 px (iPhone 17 Pro Max class). XCUIScreen
/// captures at the simulator's native pixel size and never rescales, so this test must run on a 6.9-inch
/// simulator: `MARKETING_SIM=1 Baseline/scripts/ui-shots.sh` creates "Baseline Marketing" (iPhone 17 Pro Max,
/// newest iOS runtime), runs only `testMarketingSet` there with the 9:41 status-bar override, and shuts it
/// down. On any other device the frames are still written and the test only logs the size mismatch.
final class MarketingShots: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        // The 9:41 / full battery status bar comes from `xcrun simctl status_bar … override`, applied by
        // ui-shots.sh on the host before the test starts (XCUITest cannot run simctl). See BASELINE.md.
    }

    /// Required pixel size of the 6.9-inch App Store screenshot class.
    static let requiredSize = CGSize(width: 1320, height: 2868)

    func testMarketingSet() throws {
        // 01 Home: the top of Home (strap status pill hidden by the marketing flag).
        do {
            // `-baseline.marketing YES` hides the strap status pill in the bar (DEBUG only), so the frame
            // is the top of Home: the "Today" title, the day switcher, readiness, the HRV and Resting HR rings.
            let app = launchTab("home", firstCard: NSPredicate(format: "label == %@", "HRV"))
            try settleAndSave(app, as: "01-home")
        }

        // 02 Trends: the top of the tab (the "Trends" segment, 30-day charts).
        do {
            let app = launchTab("trends", firstCard: NSPredicate(format: "label == %@", "HRV"))
            try settleAndSave(app, as: "02-trends")
        }

        // 03 Progress: Trends → the "Progress" segment of the pinned section control. The section is
        // embedded, so the bar still reads "Trends"; the segment's selected trait and the first card say
        // the switch happened.
        do {
            let app = launchTab("trends", firstCard: NSPredicate(format: "label == %@", "HRV"))
            if selectTrendsSection(app, "Progress") {
                let card = app.staticTexts["HRV baseline"].firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 20), "03-progress: first card (HRV baseline) did not appear")
            }
            try settleAndSave(app, as: "03-progress")
        }

        // 04 Sleep: the top of the tab.
        do {
            let app = launchTab("sleep", firstCard: NSPredicate(format: "label == %@", "Stages"))
            try settleAndSave(app, as: "04-sleep")
        }

        // 05 Habits: Trends → the "Habits" segment → the journal patterns ("What moves your HRV").
        do {
            let app = launchTab("trends", firstCard: NSPredicate(format: "label == %@", "HRV"))
            if selectTrendsSection(app, "Habits") {
                let card = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "What moves your")).firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 20), "05-habits: first card (What moves your …) did not appear")
            }
            try settleAndSave(app, as: "05-habits")
        }

        // 06 Workouts: Home → effort card's "All workouts" link.
        do {
            let app = launchTab("home", firstCard: NSPredicate(format: "label == %@", "HRV"))
            let link = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "All workouts")).firstMatch
            XCTAssertTrue(scrollUntilHittable(app, link), "marketing: All workouts link did not appear")
            if link.exists && link.isHittable {
                tapUntilPushed(app, link, title: "Workouts")
                waitForPushed(app, title: "Workouts", firstCard: NSPredicate(format: "label CONTAINS[c] %@", "workout"), screen: "06-workouts")
            }
            try save(XCUIScreen.main.screenshot(), as: "06-workouts")
        }
    }

    // MARK: - Drivers (mirrors ScreenshotTests; kept separate so the two files stay independent)

    /// Launches the seeded app on `tab` with onboarding skipped (and `--ui-testing`, which pins the tab
    /// bar), waits for the navigation title `--tab` lands on and for `firstCard`.
    private func launchTab(_ tab: String, firstCard: NSPredicate) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding", "--tab", tab, "-baseline.marketing", "YES", "--ui-testing"]
        app.launch()
        let expected = Self.launchTitle(for: tab)
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", expected)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "marketing: \(tab) \"\(expected)\" navigation title did not appear")
        // The demo seed runs after launch; the first card can lag the title by a few seconds.
        let card = app.staticTexts.matching(firstCard).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "marketing: \(tab) first card (\(firstCard.predicateFormat)) did not appear")
        return app
    }

    /// The navigation-bar title `--tab <tab>` lands on: Home's title is the selected day, "Today" on a cold
    /// launch, so `home` (and its `today` alias) waits for that word; `trends` and `sleep` are their own
    /// titles. Matched case-insensitively.
    private static func launchTitle(for tab: String) -> String {
        switch tab {
        case "today", "home": return "Today"
        default: return tab
        }
    }

    /// Trends' pinned section control: taps the segment named `label` until it carries the selected trait
    /// (a tap that lands while the seeded screen is still settling can be swallowed; three tries).
    @discardableResult
    private func selectTrendsSection(_ app: XCUIApplication, _ label: String) -> Bool {
        let segment = app.buttons[label].firstMatch
        guard segment.waitForExistence(timeout: 20) else {
            XCTFail("marketing: \(label) segment did not appear")
            return false
        }
        for attempt in 1...3 {
            segment.tap()
            if segment.wait(for: \.isSelected, toEqual: true, timeout: 6) { return true }
            print("marketing: \(label) segment not selected on tap \(attempt); retrying")
        }
        XCTFail("marketing: \(label) segment did not become selected")
        return false
    }

    /// Taps `element` and waits for the pushed screen's title; a tap that lands while the seeded screen is
    /// still settling can be swallowed (seen under load: the Progress button tapped, Trends still showing),
    /// so it taps again, at most three times in all.
    private func tapUntilPushed(_ app: XCUIApplication, _ element: XCUIElement, title: String) {
        let nav = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
        for attempt in 1...3 {
            element.tap()
            if nav.waitForExistence(timeout: 6) { return }
            print("marketing: \(title) did not push on tap \(attempt); retrying")
            guard element.exists && element.isHittable else { return }
        }
    }

    private func waitForPushed(_ app: XCUIApplication, title: String, firstCard: NSPredicate, screen: String) {
        let nav = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
        XCTAssertTrue(nav.waitForExistence(timeout: 10), "\(screen): navigation title did not appear")
        let card = app.staticTexts.matching(firstCard).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "\(screen): first card (\(firstCard.predicateFormat)) did not appear")
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// Lets the first paint and any chart animation settle, then captures.
    private func settleAndSave(_ app: XCUIApplication, as name: String) throws {
        Thread.sleep(forTimeInterval: 1.0)
        try save(XCUIScreen.main.screenshot(), as: name)
    }

    /// One held drag in the 20pt left gutter by `fraction` of the screen height (no fling), the same
    /// gesture ScreenshotTests uses so a chart never swallows the scroll.
    private func scroll(_ app: XCUIApplication, fraction: CGFloat, velocity: XCUIGestureVelocity = .fast) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.80))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.80 - fraction))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: velocity, thenHoldForDuration: 0.3)
    }

    /// Scrolls until `element` is hittable and clear of Home's floating "Journal" bar (a row under the
    /// bar reads as hittable but the tap lands on the bar; same rule as ScreenshotTests).
    @discardableResult
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 10)
        let bar = app.buttons["Journal"].firstMatch
        for _ in 0..<12 {
            let clear = !bar.exists || element.frame.maxY <= bar.frame.minY - 8
            if element.exists && element.isHittable && clear { return true }
            scroll(app, fraction: 0.46)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return element.exists && element.isHittable
    }

    // MARK: - Output

    private static let marketingDir: URL = {
        let path = ProcessInfo.processInfo.environment["BASELINE_SHOTS_DIR"] ?? "/private/tmp/baseline-shots"
        return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("marketing", isDirectory: true)
    }()

    private func save(_ screenshot: XCUIScreenshot, as name: String) throws {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = MarketingShots.marketingDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: file, options: .atomic)

        // Say so, loudly but without failing, when this is not a 6.9-inch capture: the frame is fine for
        // checking the screen, not for App Store Connect.
        let image = screenshot.image
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        if pixels != Self.requiredSize {
            let note = "\(name).png is \(Int(pixels.width))×\(Int(pixels.height)) px; App Store Connect's 6.9-inch class needs "
                + "\(Int(Self.requiredSize.width))×\(Int(Self.requiredSize.height)). Run on an iPhone 17 Pro Max simulator "
                + "(MARKETING_SIM=1 Baseline/scripts/ui-shots.sh)."
            print("marketing: \(note)")
            let warning = XCTAttachment(string: note)
            warning.name = "\(name)-size-warning"
            warning.lifetime = .keepAlways
            add(warning)
        }
    }
}
