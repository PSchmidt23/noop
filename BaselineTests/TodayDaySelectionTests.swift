import XCTest
@testable import Baseline

/// `TodayDaySelection`: Home's day-by-day model. Never a future day, never a day before the first stored
/// night (today only while the store is empty), a selection that was today follows the midnight roll,
/// and the keys handed to the funnels are the selected day's. Dates are built in the machine's own
/// calendar at noon, so nothing here straddles a DST edge.
final class TodayDaySelectionTests: XCTestCase {

    private let cal = Calendar.current

    private func noon(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func start(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.startOfDay(for: noon(y, m, d)) }

    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!

    // MARK: Start

    func testStartsOnTodayWithNoBoundsWhileTheStoreIsEmpty() {
        let s = TodayDaySelection(now: now)
        XCTAssertEqual(s.day, start(2026, 10, 1))
        XCTAssertTrue(s.isToday)
        XCTAssertEqual(s.offset, 0)
        XCTAssertFalse(s.canGoForward)
        XCTAssertFalse(s.canGoBack, "nothing stored: nothing to see on an earlier day")
        XCTAssertEqual(s.title, "Today")
        XCTAssertEqual(s.key, Repository.localDayKey(start(2026, 10, 1)))
    }

    func testEmptyStoreKeepsTodayEvenWhenStepped() {
        var s = TodayDaySelection(now: now)
        s.step(-1)
        XCTAssertTrue(s.isToday)
        s.select(noon(2026, 9, 20))
        XCTAssertTrue(s.isToday)
    }

    // MARK: Stepping within the stored range

    func testStepsBackAndForwardInsideTheBounds() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 28))
        XCTAssertTrue(s.canGoBack)
        s.step(-1)
        XCTAssertEqual(s.day, start(2026, 9, 30))
        XCTAssertEqual(s.offset, 1)
        XCTAssertEqual(s.title, "Yesterday")
        XCTAssertTrue(s.canGoForward)
        XCTAssertEqual(s.key, Repository.localDayKey(start(2026, 9, 30)))
        s.step(1)
        XCTAssertTrue(s.isToday)
        XCTAssertFalse(s.canGoForward)
    }

    func testNeverAFutureDay() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        s.step(1)
        XCTAssertTrue(s.isToday)
        s.select(noon(2026, 10, 5))
        XCTAssertTrue(s.isToday)
        s.step(-2)
        s.step(5)
        XCTAssertTrue(s.isToday)
    }

    func testNeverBeforeTheFirstStoredNight() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 28))
        s.step(-10)
        XCTAssertEqual(s.day, start(2026, 9, 28))
        XCTAssertFalse(s.canGoBack)
        XCTAssertEqual(s.offset, 3)
        s.select(noon(2026, 1, 1))
        XCTAssertEqual(s.day, start(2026, 9, 28))
        s.step(-1)
        XCTAssertEqual(s.day, start(2026, 9, 28), "a disabled chevron's step is a no-op")
    }

    func testSelectNormalisesToTheStartOfTheDay() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        s.select(noon(2026, 9, 29, hour: 23))
        XCTAssertEqual(s.day, start(2026, 9, 29))
        XCTAssertEqual(s.offset, 2)
    }

    // MARK: Bounds arriving later

    func testEarliestArrivingAfterASelectionClampsIt() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        s.select(noon(2026, 9, 10))
        s.setEarliest(noon(2026, 9, 20))
        XCTAssertEqual(s.day, start(2026, 9, 20))
        s.setEarliest(nil)
        XCTAssertTrue(s.isToday, "no stored night any more: back to today")
    }

    func testEarliestInTheFutureIsCappedAtToday() {
        var s = TodayDaySelection(now: now)
        s.setEarliest(noon(2026, 10, 9))
        XCTAssertEqual(s.earliest, start(2026, 10, 1))
        XCTAssertTrue(s.isToday)
        XCTAssertFalse(s.canGoBack)
    }

    // MARK: Midnight

    func testRollFollowsTheNewDayWhenTodayWasSelected() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        s.roll(now: noon(2026, 10, 2, hour: 0))
        XCTAssertEqual(s.today, start(2026, 10, 2))
        XCTAssertEqual(s.day, start(2026, 10, 2))
        XCTAssertTrue(s.isToday)
    }

    func testRollKeepsAnOlderDay() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        s.step(-1)
        s.roll(now: noon(2026, 10, 2, hour: 0))
        XCTAssertEqual(s.day, start(2026, 9, 30))
        XCTAssertEqual(s.offset, 2)
        XCTAssertFalse(s.isToday)
        XCTAssertNotEqual(s.title, "Yesterday")
    }

    // MARK: Keys for the funnels

    func testLogicalKeyIsTheClockResolvedDayOnlyForToday() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        let smallHours = Repository.localDayKey(start(2026, 9, 30))
        XCTAssertEqual(s.logicalKey(todayLogicalKey: smallHours), smallHours,
                       "before 04:00 today still reads the day being lived")
        s.step(-2)
        XCTAssertEqual(s.logicalKey(todayLogicalKey: smallHours), s.key, "a past day is its own day")
    }

    func testWorkoutWindowCoversTheSelectedDay() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        XCTAssertEqual(s.workoutWindowDays, 2)
        s.step(-5)
        XCTAssertEqual(s.workoutWindowDays, 7)
    }

    func testShortDateNamesTheDay() {
        var s = TodayDaySelection(now: now, earliest: noon(2026, 9, 1))
        s.step(-3)
        XCTAssertTrue(s.shortDate.contains("28"), s.shortDate)
        XCTAssertEqual(s.shortDate, start(2026, 9, 28).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
    }
}
