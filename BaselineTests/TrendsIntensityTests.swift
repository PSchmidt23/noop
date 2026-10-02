import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `TrendsIntensity.build` (the Trends tab's Intensity-minutes weeks) and `TrendsRange.detailRange`:
/// weeks are ISO weeks keyed by their Monday, the first drawn whole from the Monday the range starts
/// in, the last in progress until its Sunday; finished weeks are judged against the goal, the one in
/// progress is not; the card is gated on any recorded day; `.needsAge` asks instead of drawing zeros.
/// Day keys are literals (`Baselines.cutoffKey` is pure UTC key math), so nothing depends on the
/// machine's zone; `Week.date` is checked through the same local-midnight parser the chart uses.
final class TrendsIntensityTests: XCTestCase {

    private let forbidden = ["strain", "recovery", "coach", "active zone", "exercise ring"]

    /// 2026-02-18 is a Wednesday; the 30-day window behind it starts on Tuesday 2026-01-20, whose
    /// Monday is 2026-01-19.
    private let today = "2026-02-18"
    private let hrr = IntensityMinutes.Basis.hrr(restingHr: 52, hrMax: 182)

    private func day(_ key: String, credited: Int, scored: Int = 600,
                     basis: IntensityMinutes.Basis? = nil) -> TrendsIntensity.Day {
        TrendsIntensity.Day(day: key, credited: credited, scoredMinutes: scored, basis: basis ?? hrr)
    }

    private func startKey(_ range: TrendsRange) -> String {
        Baselines.cutoffKey(todayKey: today, carryDays: range.days - 1)
    }

    // MARK: Weeks

    func testWeeks_areMondayKeyedFromTheRangesFirstWeekToToday() throws {
        let t = TrendsIntensity.build(days: [], startKey: startKey(.month), todayKey: today, goal: 150)
        XCTAssertEqual(TrendsIntensity.lookbackKey(startKey: "2026-01-20"), "2026-01-19")
        XCTAssertEqual(t.weeks.map(\.id), ["2026-01-19", "2026-01-26", "2026-02-02", "2026-02-09", "2026-02-16"])
        XCTAssertEqual(t.weeks.map(\.inProgress), [false, false, false, false, true])
        XCTAssertEqual(t.weeks.map(\.credited), [0, 0, 0, 0, 0])
        XCTAssertEqual(try XCTUnwrap(t.thisWeek).id, "2026-02-16")
        XCTAssertEqual(t.completedWeeks, 4)
        XCTAssertEqual(t.weeksWithData, 0, "no recorded day: every week is missing, not a zero")
        XCTAssertEqual(t.weeksAtGoal, 0)
        XCTAssertFalse(t.hasAny, "nothing recorded: the screen leaves the card out")
        XCTAssertNil(t.basis)
        XCTAssertEqual(try XCTUnwrap(t.weeks.first).date, BaselineReadouts.localMidnight(of: "2026-01-19"))
    }

    func testWeekSums_countTheWholeFirstWeekAndStopAtToday() {
        // Monday 2026-01-19 lies BEFORE the 30-day window (which starts Tuesday 2026-01-20) and still
        // counts: a bar is a week against a weekly goal, never a tail of one.
        let days = [
            day("2026-01-19", credited: 40),
            day("2026-01-20", credited: 30),
            day("2026-01-25", credited: 90),          // Sunday closes the first week at 160
            day("2026-02-09", credited: 50),
            day("2026-02-15", credited: 60),          // 110 in the week before this one
            day("2026-02-16", credited: 70),
            day("2026-02-18", credited: 42),          // today
            day("2026-02-19", credited: 999),         // tomorrow: never counted
            day("2026-01-11", credited: 999),         // before the first Monday: never counted
        ]
        let t = TrendsIntensity.build(days: days, startKey: startKey(.month), todayKey: today, goal: 150)
        XCTAssertEqual(t.weeks.map(\.credited), [160, 0, 0, 110, 112])
        XCTAssertEqual(t.weeks.map(\.recordedDays), [3, 0, 0, 2, 2])
        XCTAssertEqual(t.thisWeek?.credited, 112)
        XCTAssertEqual(t.thisWeekText, "112 / 150")
        XCTAssertEqual(t.completedWeeks, 4)
        XCTAssertEqual(t.weeksWithData, 3, "two empty weeks in the middle are missing")
        XCTAssertEqual(t.weeksAtGoal, 1, "only the first week reached 150")
        XCTAssertTrue(t.hasAny)
        XCTAssertEqual(t.basis, hrr, "the newest recorded day's basis")
    }

    func testWeekInProgress_countsOnceItReachesTheGoal_likeTheDetail() {
        let days = [day("2026-02-16", credited: 100), day("2026-02-17", credited: 60)]
        let t = TrendsIntensity.build(days: days, startKey: startKey(.week), todayKey: today, goal: 150)
        // 7D from Thursday 2026-02-12: last week (Feb 9) whole, this week (Feb 16) in progress.
        XCTAssertEqual(t.weeks.map(\.id), ["2026-02-09", "2026-02-16"])
        XCTAssertEqual(t.thisWeek?.credited, 160)
        XCTAssertEqual(t.completedWeeks, 1)
        XCTAssertEqual(t.weeksWithData, 1, "last week recorded nothing")
        XCTAssertEqual(t.weeksAtGoal, 1, "160 this week already met the goal: a met goal stays met")
    }

    func testSunday_closesTheWeekSoNothingIsInProgress() {
        let sunday = "2026-02-22"
        let t = TrendsIntensity.build(days: [day(sunday, credited: 150)],
                                      startKey: Baselines.cutoffKey(todayKey: sunday, carryDays: 6), todayKey: sunday, goal: 150)
        XCTAssertEqual(t.weeks.map(\.id), ["2026-02-16"])
        XCTAssertEqual(t.weeks.map(\.inProgress), [false])
        XCTAssertEqual(t.completedWeeks, 1)
        XCTAssertEqual(t.weeksWithData, 1)
        XCTAssertEqual(t.weeksAtGoal, 1)
    }

    func testQuarter_drawsFourteenWeeks() {
        let t = TrendsIntensity.build(days: [], startKey: startKey(.quarter), todayKey: today, goal: 150)
        // 90 days back from Wed 2026-02-18 is Fri 2025-11-21, whose Monday is 2025-11-17.
        XCTAssertEqual(t.weeks.first?.id, "2025-11-17")
        XCTAssertEqual(t.weeks.last?.id, "2026-02-16")
        XCTAssertEqual(t.weeks.count, 14)
    }

    // MARK: Gates

    func testNeedsAge_asksInsteadOfDrawingZeroBars() {
        // The strap recorded heart rate (scored minutes) but no max heart rate exists to judge it.
        let days = [day("2026-02-17", credited: 0, scored: 480, basis: .needsAge)]
        let t = TrendsIntensity.build(days: days, startKey: startKey(.week), todayKey: today, goal: 150)
        XCTAssertTrue(t.hasAny, "recorded heart rate keeps the card, with the ask")
        XCTAssertTrue(t.needsAge)
        XCTAssertEqual(t.basis?.caption, "Add your age or max heart rate in Settings › Profile")
    }

    func testWorkoutsOnlyDay_countsAsRecorded() {
        let days = [day("2026-02-17", credited: 35, scored: 0, basis: .workoutsOnly)]
        let t = TrendsIntensity.build(days: days, startKey: startKey(.week), todayKey: today, goal: 150)
        XCTAssertTrue(t.hasAny)
        XCTAssertFalse(t.needsAge)
        XCTAssertEqual(t.thisWeek?.credited, 35)
        XCTAssertEqual(t.thisWeek?.recordedDays, 1)
    }

    func testDayLiftedFromRecord_dropsUnscoredCredit() {
        // A `.needsAge` record keeps the day's scored minutes but its Intensity figures are not a reading.
        let scored = IntradayDayStore.compute(day: "2026-02-17", buckets: [], thresholds: nil, fingerprint: (0, 0))
        let d = TrendsIntensity.Day(scored)
        XCTAssertEqual(d.credited, 0)
        XCTAssertEqual(d.basis, .needsAge)
        XCTAssertFalse(d.recorded, "no buckets, no workouts: nothing recorded")
    }

    // MARK: Sentences and the detail range

    func testChartSummary_saysTheWeeksTheGoalAndThisWeekOnce() {
        let days = [day("2026-01-19", credited: 160), day("2026-02-18", credited: 112)]
        let t = TrendsIntensity.build(days: days, startKey: startKey(.month), todayKey: today, goal: 150)
        let s = t.chartSummary(range: .month)
        XCTAssertEqual(s, "Intensity minutes, last 30 days: 5 weeks, 1 of 2 weeks at the 150-minute goal; this week 112 of 150.")
        for word in forbidden { XCTAssertFalse(s.lowercased().contains(word), word) }

        let sunday = "2026-02-22"
        let closed = TrendsIntensity.build(days: [day(sunday, credited: 20)],
                                           startKey: Baselines.cutoffKey(todayKey: sunday, carryDays: 6), todayKey: sunday, goal: 150)
        XCTAssertEqual(closed.chartSummary(range: .week), "Intensity minutes, last 7 days: 1 week, 0 of 1 week at the 150-minute goal.")
    }

    func testDetailRange_isTheDetailWindowNearestThePicker() {
        XCTAssertEqual(TrendsRange.week.detailRange, .week)
        XCTAssertEqual(TrendsRange.month.detailRange, .fourWeeks, "30 days opens on the 28-day detail, not the year")
        XCTAssertEqual(TrendsRange.quarter.detailRange, .year, "the detail has no quarter; the year keeps the weekly points")
    }

    /// Trends' card titles open Home's route table (`TodayDetail.spec`), so a metric's 1D view is one
    /// page from either tab: the night's stages for Sleep, the day's workouts for Effort, the week's bars
    /// for Intensity minutes, never the bare number of the standard spec. The hint names the screen
    /// pushed, not the card: "Effort & Readiness" opens Effort.
    @MainActor
    func testCardTitles_openHomesSpec_andHintTheScreenPushed() {
        for key in [MetricKey.hrv, .rhr, .effort, .sleepDuration, .steps, .intensityMinutes] {
            let trends = TrendsCardTitle.spec(key)
            let home = TodayDetail.spec(key)
            XCTAssertEqual(trends.key, home.key)
            XCTAssertEqual(trends.title, home.title, "\(key)")
            XCTAssertEqual(trends.dayView != nil, home.dayView != nil, "\(key)")
        }
        XCTAssertNotNil(TrendsCardTitle.spec(.sleepDuration).dayView, "Sleep's 1D view is the night")
        XCTAssertNotNil(TrendsCardTitle.spec(.effort).dayView, "Effort's 1D view lists the day's workouts")
        XCTAssertNotNil(TrendsCardTitle.spec(.intensityMinutes).dayView, "Intensity's 1D view is the week")

        XCTAssertEqual(TrendsCardTitle.hint(.effort), "Shows Effort over a day, a week, four weeks or a year")
        XCTAssertFalse(TrendsCardTitle.hint(.effort).contains("Readiness"), "the pushed screen has no readiness line")
        XCTAssertEqual(TrendsCardTitle.hint(.intensityMinutes), "Shows Intensity minutes over a day, a week, four weeks or a year")
        for key in MetricKey.allCases {
            let hint = TrendsCardTitle.hint(key).lowercased()
            for word in forbidden { XCTAssertFalse(hint.contains(word), hint) }
        }
    }
}
