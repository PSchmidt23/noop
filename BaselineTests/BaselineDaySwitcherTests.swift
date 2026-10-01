import XCTest
@testable import Baseline

/// `BaselineDaySwitcher.title(for:now:)`: "Today" and "Yesterday" for the two newest days, the weekday,
/// day and month for any other, resolved on calendar days (a time of day never changes the answer).
final class BaselineDaySwitcherTests: XCTestCase {

    private var cal: Calendar { Calendar.current }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testTodayAndYesterday() {
        let now = date(2026, 10, 1, hour: 23)
        XCTAssertEqual(BaselineDaySwitcher.title(for: date(2026, 10, 1, hour: 2), now: now), "Today")
        XCTAssertEqual(BaselineDaySwitcher.title(for: date(2026, 9, 30, hour: 18), now: now), "Yesterday")
    }

    func testOlderDaysSpellWeekdayDayAndMonth() {
        let now = date(2026, 10, 1)
        let title = BaselineDaySwitcher.title(for: date(2026, 9, 28), now: now)
        XCTAssertEqual(title, date(2026, 9, 28).formatted(.dateTime.weekday(.wide).day().month(.wide)))
        XCTAssertTrue(title.contains("28"), title)
        XCTAssertNotEqual(title, "Today")
        XCTAssertNotEqual(title, "Yesterday")
    }
}
