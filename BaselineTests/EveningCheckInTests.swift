import XCTest
import UserNotifications
@testable import Baseline

/// `EveningCheckInScheduler`'s pure parts: the stored time, the daily calendar trigger and the request
/// the center receives. Nothing here touches `UNUserNotificationCenter`.
final class EveningCheckInTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "baseline.tests.eveningCheckIn"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultTime_isHalfPastNine() {
        XCTAssertEqual(EveningCheckInScheduler.defaultMinutes, 21 * 60 + 30)
        XCTAssertEqual(EveningCheckInScheduler.minutes(defaults), EveningCheckInScheduler.defaultMinutes)
        let c = EveningCheckInScheduler.components(minutesSinceMidnight: EveningCheckInScheduler.defaultMinutes)
        XCTAssertEqual(c.hour, 21)
        XCTAssertEqual(c.minute, 30)
        XCTAssertNil(c.day, "no day component: the trigger must repeat every day")
    }

    func testStoredTime_isReadBackClamped() {
        defaults.set(7 * 60 + 5, forKey: EveningCheckInScheduler.minutesKey)
        XCTAssertEqual(EveningCheckInScheduler.minutes(defaults), 425)
        defaults.set(-10, forKey: EveningCheckInScheduler.minutesKey)
        XCTAssertEqual(EveningCheckInScheduler.minutes(defaults), 0)
        defaults.set(5000, forKey: EveningCheckInScheduler.minutesKey)
        XCTAssertEqual(EveningCheckInScheduler.minutes(defaults), 24 * 60 - 1)
    }

    func testDateRoundTrip() {
        for minutes in [0, 425, 21 * 60 + 30, 23 * 60 + 59] {
            let date = EveningCheckInScheduler.date(minutesSinceMidnight: minutes)
            XCTAssertEqual(EveningCheckInScheduler.minutes(from: date), minutes)
        }
    }

    func testRequest_isOneDailyRepeatingCalendarTrigger() throws {
        let request = EveningCheckInScheduler.request(minutesSinceMidnight: 20 * 60 + 15)
        XCTAssertEqual(request.identifier, "baseline-evening-checkin")
        XCTAssertEqual(request.content.categoryIdentifier, "baseline-evening-checkin")
        XCTAssertEqual(request.content.title, "Evening check-in")
        XCTAssertEqual(request.content.body, "Log tonight's habits so Baseline can learn what moves your HRV.")
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(trigger.dateComponents.minute, 15)
        XCTAssertEqual(trigger.dateComponents.day, nil)
    }

    @MainActor
    func testIdentifiers_doNotCollideWithTheMorningSummary() {
        // Read on the main actor (MorningSummaryNotifier is @MainActor) so the assert autoclosures stay
        // non-isolated and clean under Swift 6.
        let morning = (MorningSummaryNotifier.requestIdentifier, MorningSummaryNotifier.categoryIdentifier,
                       MorningSummaryNotifier.enabledKey)
        XCTAssertNotEqual(EveningCheckInScheduler.requestIdentifier, morning.0)
        XCTAssertNotEqual(EveningCheckInScheduler.categoryIdentifier, morning.1)
        XCTAssertNotEqual(EveningCheckInScheduler.enabledKey, morning.2)
    }

    func testPendingTab_valueTheRootConsumes() {
        XCTAssertEqual(BaselineNotificationDelegate.pendingTabKey, "baseline.pendingTab")
        XCTAssertEqual(BaselineNotificationDelegate.pendingTabJournal, "journal")
    }
}
