import XCTest
@testable import Baseline

/// `SleepTimingAim`: tonight's bedtime is the midpoint (median round the clock) of the last seven
/// bedtimes, the target while fewer than three nights are timed, and the regularity index reads as one
/// word. Times are local wall-clock instants in February 2026 (no DST edge).
final class SleepTimingCardTests: XCTestCase {

    private typealias Night = BaselineReadouts.SleepTiming.Night
    private typealias Window = BaselineReadouts.SleepWindow

    /// A night going to bed on `day` February 2026 at `hour:minute` (hours past 24 roll into the next
    /// morning), up eight hours later. `day` is the night's key, the morning it ends on.
    private func night(_ day: Int, hour: Int, minute: Int = 0) -> Night {
        let bed = Fixtures.local(2026, 2, day, hour: hour, minute: minute)
        let wake = bed.addingTimeInterval(8 * 3_600)
        return Night(day: Fixtures.dayKey(wake), bed: bed, wake: wake)
    }

    /// Newest first, as `SleepTiming.nights` is ordered.
    private func newestFirst(_ nights: [Night]) -> [Night] { nights.sorted { $0.day > $1.day } }

    func testTonight_isTheMedianOfTheLastSevenBedtimes() {
        // Seven bedtimes: 22:40, 22:55, 23:05, 23:10, 23:20, 23:45 and one late 01:30 outlier.
        let nights = newestFirst([
            night(1, hour: 22, minute: 40), night(2, hour: 22, minute: 55), night(3, hour: 23, minute: 5),
            night(4, hour: 23, minute: 10), night(5, hour: 23, minute: 20), night(6, hour: 23, minute: 45),
            night(8, hour: 1, minute: 30),
        ])
        let aim = SleepTimingAim.tonight(nights: nights, target: .default)
        XCTAssertEqual(aim.minutes, 23 * 60 + 10, accuracy: 1e-9, "the median, so the 01:30 outlier does not pull it")
        XCTAssertEqual(aim.source, .recentNights(count: 7))
        XCTAssertEqual(aim.contextText, "The middle of your last 7 bedtimes")
    }

    func testTonight_readsOnlyTheNewestSevenNights() {
        // Ten nights: three old 21:00 bedtimes that must not count, then seven at 23:30.
        var nights = (1...3).map { night($0, hour: 21) }
        nights += (4...10).map { night($0, hour: 23, minute: 30) }
        let aim = SleepTimingAim.tonight(nights: newestFirst(nights), target: .default)
        XCTAssertEqual(aim.minutes, 23 * 60 + 30, accuracy: 1e-9)
        XCTAssertEqual(aim.source, .recentNights(count: 7))
    }

    func testTonight_midpointWrapsMidnight() {
        // 23:50, 23:55, 00:05 (next morning), 00:10, 00:20: measured from noon they sit together, so the
        // median is 00:05, not a daytime hour.
        let nights = newestFirst([
            night(1, hour: 23, minute: 50), night(2, hour: 23, minute: 55),
            night(4, hour: 0, minute: 5), night(5, hour: 0, minute: 10), night(6, hour: 0, minute: 20),
        ])
        let aim = SleepTimingAim.tonight(nights: nights, target: .default)
        XCTAssertEqual(aim.minutes, 5, accuracy: 1e-9)
        XCTAssertEqual(aim.source, .recentNights(count: 5))
    }

    func testTonight_fallsBackToTheTargetUnderThreeNights() {
        let target = Window(bedMinutes: 22 * 60 + 15, wakeMinutes: 6 * 60 + 15)
        let two = newestFirst([night(1, hour: 23), night(2, hour: 23, minute: 30)])
        let aim = SleepTimingAim.tonight(nights: two, target: target)
        XCTAssertEqual(aim.minutes, 22 * 60 + 15, accuracy: 1e-9)
        XCTAssertEqual(aim.source, .target)
        XCTAssertEqual(aim.contextText, "Your target bedtime, until 3 nights are recorded")

        let none = SleepTimingAim.tonight(nights: [], target: target)
        XCTAssertEqual(none.source, .target)

        let three = newestFirst([night(1, hour: 23), night(2, hour: 23, minute: 30), night(3, hour: 23, minute: 10)])
        XCTAssertEqual(SleepTimingAim.tonight(nights: three, target: target).source, .recentNights(count: 3),
                       "three nights is enough, the same floor as the 30-night averages")
    }

    func testTonight_roundsToTheMinute() {
        // An even count: the median is the mean of the middle two, 23:00 and 23:01 → 23:00.5 → 23:00
        // (banker's-free `rounded()`: .5 rounds away from zero, so 23:01).
        let nights = newestFirst([
            night(1, hour: 22, minute: 30), night(2, hour: 23, minute: 0),
            night(3, hour: 23, minute: 1), night(4, hour: 23, minute: 40),
        ])
        let aim = SleepTimingAim.tonight(nights: nights, target: .default)
        XCTAssertEqual(aim.minutes, aim.minutes.rounded(), "whole minutes only")
        XCTAssertEqual(aim.minutes, 23 * 60 + 1, accuracy: 1e-9)
    }

    func testRegularityLabel_oneWordPerBand() {
        XCTAssertEqual(SleepTimingAim.regularityLabel(100), "Steady")
        XCTAssertEqual(SleepTimingAim.regularityLabel(80), "Steady")
        XCTAssertEqual(SleepTimingAim.regularityLabel(79), "Varied")
        XCTAssertEqual(SleepTimingAim.regularityLabel(60), "Varied")
        XCTAssertEqual(SleepTimingAim.regularityLabel(59), "Scattered")
        XCTAssertEqual(SleepTimingAim.regularityLabel(0), "Scattered")
        for i in stride(from: 0, through: 100, by: 1) {
            XCTAssertFalse(SleepTimingAim.regularityLabel(i).contains(" "), "one word")
        }
    }

    func testConstants_matchTheReadouts() {
        XCTAssertEqual(SleepTimingAim.nights, 7)
        XCTAssertEqual(SleepTimingAim.minNights, BaselineReadouts.sleepAverageMinNights)
    }
}
