import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `SleepNightBuilder.nights`: a session-backed night keeps its stage totals, timeline and vitals
/// fallbacks; a day with sleep only in `DailyMetric` becomes a fallback night; efficiency arrives as
/// either a percent or a fraction; the list is newest first. Times are local wall-clock instants, the
/// zone the builder keys nights in, so the expected keys hold on any machine.
final class SleepNightBuilderTests: XCTestCase {

    private let dayKey = "2026-02-18"
    private var onset: Int { Int(Fixtures.local(2026, 2, 17, hour: 23).timeIntervalSince1970) }
    private var wake: Int { Int(Fixtures.local(2026, 2, 18, hour: 7).timeIntervalSince1970) }

    /// 23:00 → 07:00: light 120, deep 90, rem 90, wake 10, light 170 (asleep 470, in bed 480).
    private var nightStages: [StageSegment] {
        let t = onset
        return [StageSegment(start: t, end: t + 120 * 60, stage: "light"),
                StageSegment(start: t + 120 * 60, end: t + 210 * 60, stage: "deep"),
                StageSegment(start: t + 210 * 60, end: t + 300 * 60, stage: "rem"),
                StageSegment(start: t + 300 * 60, end: t + 310 * 60, stage: "wake"),
                StageSegment(start: t + 310 * 60, end: t + 480 * 60, stage: "light")]
    }

    private func session(_ start: Int, _ end: Int, stages: [StageSegment]?, efficiency: Double? = nil,
                         restingHr: Int? = nil, avgHrv: Double? = nil) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: efficiency, restingHr: restingHr,
                           avgHrv: avgHrv, stagesJSON: stages.map(Fixtures.stagesJSON))
    }

    // MARK: Session-backed night

    func testSessionNight_stagesTimelineAndVitalFallbacks() throws {
        // The night, a one-hour afternoon nap ending the same day, and a daily row for that day whose
        // sleep total disagrees with the stages (stages win) and which supplies the missing resting HR.
        let night = session(onset, wake, stages: nightStages, avgHrv: 55)
        let napStart = Int(Fixtures.local(2026, 2, 18, hour: 14).timeIntervalSince1970)
        let nap = session(napStart, napStart + 3_600,
                          stages: [StageSegment(start: napStart, end: napStart + 3_600, stage: "light")])
        let daily = Fixtures.metric(dayKey, rhr: 50, sleepMin: 400)

        let nights = SleepNightBuilder.nights(sessions: [nap, night], days: [daily], habitualMidsleepSec: nil)
        XCTAssertEqual(nights.count, 1, "the nap joins the day, it does not make a second night")
        let n = try XCTUnwrap(nights.first)

        XCTAssertEqual(n.dayKey, dayKey)
        XCTAssertEqual(n.source, .session)
        XCTAssertEqual(n.onsetTs, onset)
        XCTAssertEqual(n.wakeTs, wake)
        XCTAssertTrue(n.hasStageTotals)
        XCTAssertEqual(n.asleepMin, 470, accuracy: 1e-9)
        XCTAssertEqual(n.deepMin, 90, accuracy: 1e-9)
        XCTAssertEqual(n.remMin, 90, accuracy: 1e-9)
        XCTAssertEqual(n.lightMin, 290, accuracy: 1e-9)
        XCTAssertEqual(n.awakeMin, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(n.efficiency), 470.0 / 480.0, accuracy: 1e-9, "asleep ÷ in bed when wake is staged")
        XCTAssertEqual(n.segments.count, 5)
        XCTAssertTrue(n.hasTimeline)
        XCTAssertEqual(n.avgHrv, 55)
        XCTAssertEqual(n.restingHr, 50, "session carries no resting HR: the daily row's value is used")
        XCTAssertFalse(n.stagingSparse)
    }

    func testSessionWithoutStagePayload_usesDailyStageColumnsAndStoredEfficiency() throws {
        let block = session(onset, wake, stages: nil, efficiency: 0.9)
        let daily = Fixtures.metric(dayKey, deep: 90, rem: 100, light: 230)
        let n = try XCTUnwrap(SleepNightBuilder.nights(sessions: [block], days: [daily], habitualMidsleepSec: nil).first)

        XCTAssertEqual(n.source, .session)
        XCTAssertTrue(n.hasStageTotals)
        XCTAssertEqual(n.asleepMin, 420, accuracy: 1e-9)
        XCTAssertEqual(n.deepMin, 90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(n.efficiency), 0.9, accuracy: 1e-9, "no staged wake: the stored efficiency stands")
        XCTAssertTrue(n.segments.isEmpty)
        XCTAssertFalse(n.hasTimeline)
    }

    // MARK: Daily-row fallback

    func testDailyMetricFallback_normalisesEfficiencyAndDerivesAwake() throws {
        let percent = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(dayKey, sleepMin: 420, efficiency: 89.0)))
        XCTAssertEqual(percent.source, .dailyMetric)
        XCTAssertEqual(try XCTUnwrap(percent.efficiency), 0.89, accuracy: 1e-9, "a percent from import/seed paths becomes a fraction")
        XCTAssertEqual(percent.asleepMin, 420)
        XCTAssertEqual(percent.awakeMin, 420 / 0.89 - 420, accuracy: 1e-9, "in bed − asleep from the efficiency")
        XCTAssertFalse(percent.hasStageTotals)
        XCTAssertNil(percent.onsetTs)
        XCTAssertNil(percent.wakeTs)
        XCTAssertFalse(percent.hasTimeline)

        let fraction = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(dayKey, sleepMin: 420, efficiency: 0.89)))
        XCTAssertEqual(try XCTUnwrap(fraction.efficiency), 0.89, accuracy: 1e-9, "a fraction is left alone")

        let none = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(dayKey, sleepMin: 420)))
        XCTAssertNil(none.efficiency)
        XCTAssertEqual(none.awakeMin, 0)
    }

    func testDailyMetricFallback_stageColumnsWithoutTotal() throws {
        let n = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(dayKey, deep: 90, rem: 100, light: 230)))
        XCTAssertEqual(n.asleepMin, 420, accuracy: 1e-9)
        XCTAssertTrue(n.hasStageTotals)
        XCTAssertNil(SleepNightBuilder.build(fromDaily: Fixtures.metric(dayKey, rhr: 50)), "a row without sleep is not a night")
    }

    // MARK: Merge and ordering

    func testSessionDaysWinOverDailyRows_andNightsAreNewestFirst() throws {
        let night = session(onset, wake, stages: nightStages)
        let days = [Fixtures.metric("2026-02-15", rhr: 50),                         // no sleep: skipped
                    Fixtures.metric("2026-02-16", sleepMin: 450, efficiency: 0.91),
                    Fixtures.metric("2026-02-17", sleepMin: 420, efficiency: 89.0),
                    Fixtures.metric(dayKey, sleepMin: 400)]                         // covered by the session
        let nights = SleepNightBuilder.nights(sessions: [night], days: days, habitualMidsleepSec: nil)

        XCTAssertEqual(nights.map(\.dayKey), [dayKey, "2026-02-17", "2026-02-16"])
        XCTAssertEqual(nights.map(\.source), [.session, .dailyMetric, .dailyMetric])
        XCTAssertEqual(nights[0].asleepMin, 470, accuracy: 1e-9, "the session's stages, not the daily total")
        XCTAssertEqual(nights[1].asleepMin, 420)
        XCTAssertEqual(try XCTUnwrap(nights[2].efficiency), 0.91, accuracy: 1e-9)
    }

    // MARK: Formatting

    func testDeltaText() {
        XCTAssertEqual(SleepFormat.deltaText(asleepMin: 452, average: 420), "+32 min vs average")
        XCTAssertEqual(SleepFormat.deltaText(asleepMin: 402, average: 420), "\u{2212}18 min vs average")
        XCTAssertEqual(SleepFormat.deltaText(asleepMin: 423, average: 420), "On your average")
        XCTAssertEqual(SleepFormat.deltaText(asleepMin: 500, average: 420), "+1h 20m vs average",
                       "an hour or more is spelled as every other duration, not as 80 min")
        XCTAssertEqual(SleepFormat.percent(0.894), "89%")
    }
}
