import UIKit
import XCTest

/// The Friends tab's screenshots, as an extension of `ScreenshotTests` so `AX=1 Baseline/scripts/ui-shots.sh`
/// (which runs `ScreenshotTests` only) captures them at accessibility sizes too. Every launch passes
/// `--ui-testing`, which forces the in-memory demo backend (Alex, Jordan, Priya, Sam, a request from Chris),
/// so nothing touches a server; `--friends-state signedOut|setup|ready` picks the starting phase.
///
/// Besides the frames, each test asserts the tab's promises: no raw HRV / heart-rate value ("ms") on any
/// Friends screen, the leaderboard's "never ranked" caption, alphabetical friend cards, and none of the
/// banned words.
extension ScreenshotTests {

    func testFriendsIntro() throws {
        let app = launchFriends(state: "signedOut")
        let card = app.staticTexts["Compete on what you do, not on your body"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "friends-intro: intro card did not appear")
        try friendsCapture(app, screen: "friends-intro")
        friendsAssertPromises(app, screen: "friends-intro")
    }

    func testFriendsSetup() throws {
        let app = launchFriends(state: "setup")
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Set up Friends")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "friends-setup: setup sheet did not appear")
        Thread.sleep(forTimeInterval: 0.6)
        try friendsSave(XCUIScreen.main.screenshot(), as: "friends-setup-0")
        // Sign in with Apple has already made the account: the name step offers deleting it, not only "Not now".
        XCTAssertTrue(app.descendants(matching: .any)["friends-setup-delete"].firstMatch.exists,
                      "friends-setup: no Delete account on the name step")
    }

    func testFriends() throws {
        let app = launchFriends(state: "ready")
        let board = app.staticTexts["Leaderboard"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 20), "friends: leaderboard did not appear")
        Thread.sleep(forTimeInterval: 0.8)
        friendsAssertPromises(app, screen: "friends")
        XCTAssertTrue(app.staticTexts["Ranked on what you do. HRV, resting HR and readiness are never ranked."].firstMatch.exists
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "never ranked")).firstMatch.exists,
                      "friends: the leaderboard caption is missing")
        try friendsCapture(app, screen: "friends")

        // Friend cards are alphabetical (never by any value).
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "friend-row-"))
        let names = rows.allElementsBoundByIndex.map { $0.identifier.replacingOccurrences(of: "friend-row-", with: "") }
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                       "friends: cards are not alphabetical (\(names))")

        // Friend detail.
        // The friend cards sit below the leaderboard; at accessibility sizes they are only built once
        // scrolled near (the tab is a lazy stack), so scroll before looking.
        let alex = app.descendants(matching: .any)["friend-row-Alex"].firstMatch
        if !alex.waitForExistence(timeout: 3) { friendsScrollTo(app, alex) }
        if alex.waitForExistence(timeout: 5) {
            friendsScrollTo(app, alex)
            alex.tap()
            let detail = app.staticTexts["This week"].firstMatch
            XCTAssertTrue(detail.waitForExistence(timeout: 10), "friend-detail: did not open")
            Thread.sleep(forTimeInterval: 0.6)
            friendsAssertPromises(app, screen: "friend-detail")
            try friendsCapture(app, screen: "friend-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else {
            XCTFail("friends: Alex's card did not appear")
        }

        // Invite sheet.
        XCTAssertTrue(openFriendsMenu(app, item: "Invite a friend"), "invite: menu did not open")
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Single use")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 10), "invite-sheet: code did not appear")
        Thread.sleep(forTimeInterval: 0.5)
        try friendsSave(XCUIScreen.main.screenshot(), as: "invite-sheet")
    }

    func testEnterCodeErrors() throws {
        let app = launchFriends(state: "ready")
        XCTAssertTrue(app.staticTexts["Leaderboard"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(openFriendsMenu(app, item: "Enter a code"), "enter-code: menu did not open")

        let field = app.textFields["Friend's code"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "enter-code: field did not appear")
        field.tap()
        field.typeText("xprd-cde2")
        // The first tap can land while the keyboard is still settling and be swallowed: tap again once.
        let expired = app.staticTexts["That code has expired. Ask for a new one."].firstMatch
        for _ in 1...2 where !expired.exists {
            app.buttons["Continue"].firstMatch.tap()
            _ = expired.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(expired.waitForExistence(timeout: 5), "enter-code: expired copy did not appear")
        try friendsSave(XCUIScreen.main.screenshot(), as: "enter-code-expired")

        // Clear and try the demo code that adds Casey (a pending request).
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText("CASEY234")   // the demo seed's Casey code (DEMO2345 has an O, outside the invite alphabet)
        app.buttons["Continue"].firstMatch.tap()
        let connect = app.buttons["Connect"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "enter-code: Connect with Casey? did not appear")
        try friendsSave(XCUIScreen.main.screenshot(), as: "enter-code-peek")
        connect.tap()
        XCTAssertTrue(app.staticTexts["Request sent to Casey."].firstMatch.waitForExistence(timeout: 10),
                      "enter-code: request was not sent")
        app.buttons["Done"].firstMatch.tap()
        let waiting = app.staticTexts["Waiting for Casey to accept"].firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "friends: the pending request to Casey is missing")
    }

    func testCompete() throws {
        let app = launchFriends(state: "ready")
        XCTAssertTrue(app.staticTexts["Leaderboard"].firstMatch.waitForExistence(timeout: 20))
        let segment = app.buttons["Compete"].firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 10))
        segment.tap()
        let newButton = app.buttons["New competition"].firstMatch
        XCTAssertTrue(newButton.waitForExistence(timeout: 10), "compete: New competition did not appear")
        Thread.sleep(forTimeInterval: 1.0)
        friendsAssertPromises(app, screen: "compete")
        try friendsCapture(app, screen: "compete")

        let card = app.descendants(matching: .any)["competition-card"].firstMatch
        if card.waitForExistence(timeout: 5) {
            friendsScrollTo(app, card)
            card.tap()
            XCTAssertTrue(app.staticTexts["Rules"].firstMatch.waitForExistence(timeout: 10), "competition-detail: did not open")
            Thread.sleep(forTimeInterval: 0.8)
            try friendsCapture(app, screen: "competition-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else {
            XCTFail("compete: no competition card")
        }

        let again = app.buttons["New competition"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        friendsScrollTo(app, again)
        again.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["New competition"].firstMatch.waitForExistence(timeout: 10),
                      "compete-create: sheet did not open")
        Thread.sleep(forTimeInterval: 0.6)
        try friendsSave(XCUIScreen.main.screenshot(), as: "compete-create-0")
        friendsAssertPromises(app, screen: "compete-create")
    }

    func testSettingsFriends() throws {
        let app = launchFriends(state: "ready")
        XCTAssertTrue(app.staticTexts["Leaderboard"].firstMatch.waitForExistence(timeout: 20))
        let gear = app.navigationBars.buttons["Settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Friends & sharing")).firstMatch
        XCTAssertTrue(app.navigationBars.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 10),
                      "settings-friends: Settings did not open")
        // Held gutter drags, as the other captures use: a fling (swipeUp) keeps Settings' long list
        // moving, and XCUITest's snapshot of a list in flight can time out.
        for _ in 0..<12 where !(row.exists && row.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.80))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.40))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity.fast, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "settings-friends: row did not appear")
        // A tap while the list is still decelerating only stops it: let it settle, then tap until pushed.
        Thread.sleep(forTimeInterval: 0.8)
        let pushed = app.navigationBars.staticTexts["Friends & sharing"].firstMatch
        for _ in 1...3 where !pushed.exists {
            guard row.exists, row.isHittable else { break }
            row.tap()
            _ = pushed.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(pushed.waitForExistence(timeout: 4), "settings-friends: screen did not open")
        Thread.sleep(forTimeInterval: 0.6)
        try friendsCapture(app, screen: "settings-friends")
    }

    // MARK: - Helpers (file-local: ScreenshotTests' own helpers are private to its file)

    private func launchFriends(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--tab", "friends", "--friends-state", state, "--ui-testing"]
        app.launch()
        // The Friends tab button exists once the first frame is up (a cold first launch can take ~30 s).
        _ = app.buttons["Friends"].firstMatch.waitForExistence(timeout: Self.launchTimeout())
        return app
    }

    /// The toolbar's "Add a friend" menu → one of its items.
    private func openFriendsMenu(_ app: XCUIApplication, item: String) -> Bool {
        let menu = app.navigationBars.buttons["Add a friend"].firstMatch
        guard menu.waitForExistence(timeout: 10) else { return false }
        for _ in 1...3 {
            menu.tap()
            let entry = app.buttons[item].firstMatch
            if entry.waitForExistence(timeout: 3) { entry.tap(); return true }
        }
        return false
    }

    /// No raw physiology, no banned vocabulary.
    private func friendsAssertPromises(_ app: XCUIApplication, screen: String) {
        let ms = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*\\b[0-9]+ ?ms\\b.*")).count
        XCTAssertEqual(ms, 0, "\(screen): a raw HRV value (ms) is on a Friends screen")
        for word in ["Strain", "Recovery", "Coach", "Circles", "Workweek Hustle", "Weekend Warrior", "Goal Day", "Daily Showdown"] {
            let hits = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", word)).count
            XCTAssertEqual(hits, 0, "\(screen): banned word \"\(word)\" appears")
        }
    }

    private func friendsScrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func friendsCapture(_ app: XCUIApplication, screen: String) throws {
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        try friendsSave(XCUIScreen.main.screenshot(), as: "\(screen)-0")
        for n in 1...8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.80))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.34))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity.fast, thenHoldForDuration: 0.15)
            Thread.sleep(forTimeInterval: 0.6)
            let shot = XCUIScreen.main.screenshot()
            if shot.pngRepresentation == previous { break }
            try friendsSave(shot, as: "\(screen)-\(n)")
            previous = shot.pngRepresentation
        }
        // Back to the top for whatever the test does next.
        for _ in 0..<8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.30))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity.fast, thenHoldForDuration: 0.1)
        }
    }

    private func friendsSave(_ screenshot: XCUIScreenshot, as name: String) throws {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let path = ProcessInfo.processInfo.environment["BASELINE_SHOTS_DIR"] ?? "/private/tmp/baseline-shots"
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
