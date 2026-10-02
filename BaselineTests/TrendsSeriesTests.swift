import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `TrendsSeries.build`, `yDomain` and `trend`: the band appears only once the fold is usable, the
/// y-axis pads and snaps outward without dipping below zero, and the trend pill compares the two ends
/// of the range. `now` is a fixed local noon so every day key is unambiguous on any machine.
final class TrendsSeriesTests: BaselineEngineTestCase {

    private let now = Fixtures.local(2026, 2, 18, hour: 12)
    private func key(_ daysAgo: Int) -> String { Fixtures.dayKey(now, minus: daysAgo) }

    // MARK: Band gating

    func testBandDrawnOnlyOnceBaselineIsUsable_weekRange() throws {
        // Three nights of history (< minNightsSeed) then seven in range. The first in-range point has
        // no band; after it is folded the fourth valid night makes the state provisional, so the
        // second point carries baseline ± σ.
        let history = (7...9).reversed().map { Fixtures.metric(key($0), hrv: 60) }
        let inRange = (0...6).reversed().map { Fixtures.metric(key($0), hrv: 60) }
        let s = TrendsSeries.build(days: history + inRange, range: .week, now: now)

        XCTAssertEqual(s.hrv.points.map(\.id), (0...6).reversed().map { key($0) })
        XCTAssertNil(s.hrv.points[0].baseline, "3 folded nights: band not yet usable")
        XCTAssertNil(s.hrv.points[0].low)
        let second = s.hrv.points[1]
        XCTAssertEqual(try XCTUnwrap(second.baseline), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(second.low), 60 - 1.253 * Baselines.hrvCfg.floorSpread, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(second.high), 60 + 1.253 * Baselines.hrvCfg.floorSpread, accuracy: 1e-9)

        // "Current" is the fold of every night before the newest, the same state Today reads.
        XCTAssertEqual(s.hrv.current.nValid, 9)
        XCTAssertTrue(s.hrv.current.usable)
        XCTAssertEqual(try XCTUnwrap(s.hrv.average), 60, accuracy: 1e-9)
        XCTAssertEqual(s.totalNights, 10)
        XCTAssertTrue(s.restingHr.points.isEmpty, "no resting HR banked")
        XCTAssertNil(s.readiness, "fewer than 14 HRV nights: no readiness strip")
    }

    func testBandGateIsTheSameWithoutHistory_monthRange() {
        // Same ten nights inside a 30-day window: the band first appears on the fifth point.
        let days = (0...9).reversed().map { Fixtures.metric(key($0), hrv: 60) }
        let s = TrendsSeries.build(days: days, range: .month, now: now)
        XCTAssertEqual(s.hrv.points.count, 10)
        XCTAssertNil(s.hrv.points[3].baseline)
        XCTAssertNotNil(s.hrv.points[4].baseline)
    }

    func testOutOfRangeAndInvalidNightsAreNotPoints() {
        let days = [Fixtures.metric(key(7), hrv: 60),            // before the 7-day window
                    Fixtures.metric(key(3), hrv: 300),           // above Baselines.hrvCfg.maxVal
                    Fixtures.metric(key(2), hrv: nil, rhr: 50),  // no HRV
                    Fixtures.metric(key(1), hrv: 58)]
        let s = TrendsSeries.build(days: days, range: .week, now: now)
        XCTAssertEqual(s.hrv.points.map(\.id), [key(1)])
        XCTAssertEqual(s.restingHr.points.map(\.id), [key(2)])
    }

    // MARK: Trend direction

    func testTrendComparesFirstAndLastWindow() throws {
        // Week range compares 3 nights at each end: 50,50,50 → 70,70,70 reads +20 ms.
        let values: [Double] = [50, 50, 50, 70, 70, 70, 70]
        let days = zip((0...6).reversed(), values).map { Fixtures.metric(key($0), hrv: $1) }
        let s = TrendsSeries.build(days: days, range: .week, now: now)
        XCTAssertEqual(try XCTUnwrap(s.hrv.trend), 20, accuracy: 1e-9)

        XCTAssertEqual(try XCTUnwrap(TrendsSeries.trend([1, 2, 3, 4], window: 3)), 2, accuracy: 1e-9,
                       "window shrinks to half the nights (2) and still reads")
        XCTAssertNil(TrendsSeries.trend([50, 50, 50], window: 3), "one night per end is not a trend")
        XCTAssertNil(TrendsSeries.trend([], window: 7))
    }

    // MARK: Y domain

    func testYDomainPadsAndSnapsOutward() {
        let date = now
        let points = [BandPoint(id: "a", date: date, value: 55, baseline: 55, low: 48, high: 62),
                      BandPoint(id: "b", date: date, value: 57, baseline: 55, low: 48, high: 62)]
        // 48…62 padded by 12% of 14 (1.68) → 46.32…63.68, snapped to 5 ms steps.
        XCTAssertEqual(TrendsSeries.yDomain(points: points, step: 5), 45...65)

        // Band edges extend the domain even when every value sits inside them.
        let bpm = [BandPoint(id: "a", date: date, value: 51, baseline: 50, low: 47.5, high: 52.5)]
        XCTAssertEqual(TrendsSeries.yDomain(points: bpm, step: 2), 46...54)
    }

    func testYDomainNeverBelowZeroAndHandlesEmpty() {
        XCTAssertEqual(TrendsSeries.yDomain(points: [], step: 5), 0...5)
        let low = [BandPoint(id: "a", date: now, value: 2, baseline: nil, low: nil, high: nil)]
        XCTAssertEqual(TrendsSeries.yDomain(points: low, step: 5), 0...5)
    }

    // MARK: Sleep and effort bars

    func testSleepAndEffortBars() throws {
        let days = [Fixtures.metric(key(3), sleepMin: 0, strain: 30),      // zero sleep: no bar
                    Fixtures.metric(key(2), sleepMin: 420),
                    Fixtures.metric(key(1), sleepMin: 390, strain: 80),
                    Fixtures.metric(key(0), hrv: 60)]
        let s = TrendsSeries.build(days: days, range: .week, now: now)

        XCTAssertEqual(s.sleep.bars.map(\.id), [key(2), key(1)])
        XCTAssertEqual(s.sleep.bars.map(\.value), [7.0, 6.5])
        XCTAssertEqual(s.sleepNights, 2)
        XCTAssertEqual(s.sleepNights7h, 1)
        XCTAssertEqual(try XCTUnwrap(s.sleep.average), 6.75, accuracy: 1e-9)

        XCTAssertEqual(s.effort.bars.map(\.value), [30, 80])
        XCTAssertEqual(try XCTUnwrap(s.effort.average), 55, accuracy: 1e-9)
        XCTAssertEqual(s.effortPeak?.id, key(1))
    }

    func testRangeResolveAndLabels() {
        XCTAssertEqual(TrendsRange.resolve(7), .week)
        XCTAssertEqual(TrendsRange.resolve(12), .month, "an unknown persisted value falls back to 30 days")
        XCTAssertEqual(TrendsRange.week.trendWindow, 3)
        XCTAssertEqual(TrendsRange.quarter.trendWindow, 7)
        XCTAssertEqual(TrendsFormat.signed(-3.4, unit: "bpm"), "\u{2212}3 bpm")
    }

    // MARK: Effort and Readiness

    /// A row carrying a step count (the funnel's `steps` column); `Fixtures.metric` has no such argument.
    private func stepsRow(_ day: String, steps: Int) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil,
                    exerciseCount: nil, steps: steps)
    }

    func testEffortReadinessPointsAveragesAndOutranCount() throws {
        let days = [Fixtures.metric(key(3), strain: 30, recovery: 60),   // paired, readiness ahead
                    Fixtures.metric(key(2), strain: 80, recovery: 50),   // paired, effort outran
                    Fixtures.metric(key(1), recovery: 70),               // readiness only
                    Fixtures.metric(key(0), hrv: 60, strain: 40)]        // effort only
        let s = TrendsSeries.build(days: days, range: .week, now: now)
        let m = s.effortReadiness

        XCTAssertEqual(m.points.map(\.id), [key(3), key(2), key(1), key(0)])
        XCTAssertEqual(m.points.map(\.effort), [30, 80, nil, 40])
        XCTAssertEqual(m.points.map(\.readiness), [60, 50, 70, nil])
        XCTAssertEqual(try XCTUnwrap(m.effortAverage), 50, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.readinessAverage), 60, accuracy: 1e-9)
        XCTAssertEqual(m.effortDays, 3)
        XCTAssertEqual(m.readinessDays, 3)
        XCTAssertEqual(m.pairedDays, 2)
        XCTAssertEqual(m.outranDays, 1)
        // The merged card prints one average effort: the same number the effort bars carry.
        XCTAssertEqual(m.effortAverage, s.effort.average)
    }

    func testEffortReadinessIgnoresDaysOutsideTheRangeAndEqualValues() {
        let days = [Fixtures.metric(key(10), strain: 90, recovery: 20),   // before the 7-day window
                    Fixtures.metric(key(1), strain: 55, recovery: 55),    // equal: not outran
                    Fixtures.metric(key(0), hrv: 60)]                     // neither column
        let s = TrendsSeries.build(days: days, range: .week, now: now)
        XCTAssertEqual(s.effortReadiness.points.map(\.id), [key(1)])
        XCTAssertEqual(s.effortReadiness.pairedDays, 1)
        XCTAssertEqual(s.effortReadiness.outranDays, 0)

        let none = TrendsSeries.build(days: [Fixtures.metric(key(10), strain: 90, recovery: 20)], range: .week, now: now)
        XCTAssertTrue(none.effortReadiness.points.isEmpty)
        XCTAssertNil(none.effortReadiness.effortAverage)
        XCTAssertNil(none.effortReadiness.readinessAverage)
    }

    // MARK: Steps

    func testStepsFromResolvedReadings() throws {
        let tomorrow = Baselines.cutoffKey(todayKey: key(0), carryDays: -1)
        let readings: [(day: String, value: Double)] = [
            (key(40), 5_000),      // outside the week, inside the quarter: keeps the card
            (key(2), 8_000),
            (key(1), 10_000),
            (key(0), 0),           // a counted zero is a bar
            (tomorrow, 9_000),     // never a bar
            (key(3), -1)           // not a count
        ]
        let s = TrendsSeries.build(days: [Fixtures.metric(key(0), hrv: 60)], range: .week,
                                   stepReadings: readings, now: now)
        XCTAssertEqual(s.steps.bars.map(\.id), [key(2), key(1), key(0)])
        XCTAssertEqual(s.steps.bars.map(\.value), [8_000, 10_000, 0])
        XCTAssertEqual(try XCTUnwrap(s.steps.average), 6_000, accuracy: 1e-9)
        XCTAssertEqual(s.stepsDays, 3)
        XCTAssertEqual(s.stepsAboveAverage, 2, "8,000 and 10,000 beat a 6,000 mean")
        XCTAssertTrue(s.hasSteps)
    }

    func testStepsFallBackToTheFunnelColumnAndGateOnTheQuarter() throws {
        // No readings passed: the rows' own `steps` column draws the bars.
        let days = [stepsRow(key(1), steps: 7_000), stepsRow(key(0), steps: 9_000)]
        let s = TrendsSeries.build(days: days, range: .week, now: now)
        XCTAssertEqual(s.steps.bars.map(\.value), [7_000, 9_000])
        XCTAssertEqual(try XCTUnwrap(s.steps.average), 8_000, accuracy: 1e-9)
        XCTAssertEqual(s.stepsAboveAverage, 1)
        XCTAssertTrue(s.hasSteps)

        // Readings given but empty: nothing in the quarter, so the card is left out.
        let empty = TrendsSeries.build(days: days, range: .week, stepReadings: [], now: now)
        XCTAssertTrue(empty.steps.bars.isEmpty)
        XCTAssertFalse(empty.hasSteps)

        // A count 89 days back is inside the lookback (card stays, empty text); 90 back is not.
        let edge = TrendsSeries.build(days: [], range: .week, stepReadings: [(day: key(89), value: 4_000)], now: now)
        XCTAssertTrue(edge.hasSteps)
        XCTAssertTrue(edge.steps.bars.isEmpty)
        let past = TrendsSeries.build(days: [], range: .week, stepReadings: [(day: key(90), value: 4_000)], now: now)
        XCTAssertFalse(past.hasSteps)
    }

    func testWindowKeysAndStepsLookback() {
        let w = TrendsSeries.window(range: .week, now: now)
        XCTAssertEqual(w.startKey, key(6))
        XCTAssertEqual(w.todayKey, key(0))
        XCTAssertEqual(TrendsSeries.window(range: .quarter, now: now).startKey, key(89))
        XCTAssertEqual(TrendsSeries.stepsLookbackDays, 90)
    }
}
