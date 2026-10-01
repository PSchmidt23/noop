import UIKit
import XCTest

/// App Store marketing set: one test, six frames, each the top of a seeded screen, written as
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
        // 01 Today: scrolled until the hero tiles sit just under the navigation bar. The seeded sim has no
        // strap, so the "Pair your strap" card opens the screen; it is the right first thing for a person
        // without a strap and the wrong one for a store frame, and any part of it left under the
        // translucent bar ghosts through. The held gutter drag delivers an unpredictable share of its
        // length at the fast velocity (a 115pt drag moved nothing, the next one flung 476pt), so this
        // frame's drags run slowly (300pt/s, no fling) and the position is reached by feedback: measure
        // the HRV tile against the bar after every step, steps at most 12% of the screen, either
        // direction, until the tile's top is 12pt under the bar (±14pt) or ten steps have been taken.
        do {
            let app = launchTab("today", firstCard: NSPredicate(format: "label == %@", "HRV"))
            let hrv = app.staticTexts["HRV"].firstMatch
            let bar = app.navigationBars.firstMatch
            let height = app.frame.height
            for step in 0..<10 {
                guard hrv.exists, bar.exists, height > 0 else { break }
                let tileTop = hrv.frame.minY - 24          // the tile's padding above its label
                let target = bar.frame.maxY + 12
                let delta = tileTop - target               // > 0: content must move up by delta
                print("marketing: 01-today step \(step) tileTop=\(tileTop) target=\(target) delta=\(delta)")
                if abs(delta) <= 14 { break }
                let fraction = min(abs(delta) / height, 0.12)
                if delta > 0 { scroll(app, fraction: fraction, velocity: Self.precise) }
                else { scrollBack(app, fraction: fraction, velocity: Self.precise) }
                Thread.sleep(forTimeInterval: 0.8)
            }
            try save(XCUIScreen.main.screenshot(), as: "01-today")
        }

        // 02 Progress: Trends → the Progress toolbar button.
        do {
            let app = launchTab("trends", firstCard: NSPredicate(format: "label == %@", "HRV"))
            let button = app.buttons["Progress"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 20), "marketing: Progress toolbar button did not appear")
            if button.exists {
                tapUntilPushed(app, button, title: "Progress")
                waitForPushed(app, title: "Progress", firstCard: NSPredicate(format: "label == %@", "HRV baseline"), screen: "02-progress")
            }
            try save(XCUIScreen.main.screenshot(), as: "02-progress")
        }

        // 03 Trends, 04 Sleep, 05 Journal: the top of each tab.
        do {
            let app = launchTab("trends", firstCard: NSPredicate(format: "label == %@", "HRV"))
            try settleAndSave(app, as: "03-trends")
        }
        do {
            let app = launchTab("sleep", firstCard: NSPredicate(format: "label == %@", "Stages"))
            try settleAndSave(app, as: "04-sleep")
        }
        do {
            let app = launchTab("journal", firstCard: NSPredicate(format: "label == %@", "Habits"))
            try settleAndSave(app, as: "05-journal")
        }

        // 06 Workouts: Today → effort card's "All workouts" link.
        do {
            let app = launchTab("today", firstCard: NSPredicate(format: "label == %@", "HRV"))
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

    /// Launches the seeded app on `tab` with onboarding skipped, waits for the nav title and `firstCard`.
    private func launchTab(_ tab: String, firstCard: NSPredicate) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-seed", "--skip-onboarding", "--tab", tab]
        app.launch()
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", tab)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "marketing: \(tab) navigation title did not appear")
        // The demo seed runs after launch; the first card can lag the title by a few seconds.
        let card = app.staticTexts.matching(firstCard).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "marketing: \(tab) first card (\(firstCard.predicateFormat)) did not appear")
        return app
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

    /// Points per second for a drag that must land where it points (no fling): the Today frame's loop.
    private static let precise = XCUIGestureVelocity(300)

    /// The reverse of `scroll`: content moves down by `fraction` of the screen (same gutter, same hold).
    private func scrollBack(_ app: XCUIApplication, fraction: CGFloat, velocity: XCUIGestureVelocity = .fast) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.34))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.34 + fraction))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: velocity, thenHoldForDuration: 0.3)
    }

    @discardableResult
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<12 {
            if element.exists && element.isHittable { return true }
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
