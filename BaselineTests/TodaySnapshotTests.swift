import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `TodaySnapshot.build`: band classification against the personal baseline, the calibrating and
/// stale states, the readiness line and the sleep card's 30-night delta. Day keys are literals and
/// the carry rule is UTC key math, so nothing here depends on the machine's zone or clock.
final class TodaySnapshotTests: BaselineEngineTestCase {

    private let today = "2026-02-18"

    /// `n` nights of the same value ending the day before `today`, oldest first.
    private func priorNights(_ n: Int, hrv: Double, rhr: Int? = nil) -> [DailyMetric] {
        (1...n).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: hrv, rhr: rhr) }
    }

    // MARK: Band classification

    func testTodayInsideBand_readsAgainstBaselineOfPriorNights() throws {
        // Ten identical nights fold to exactly that value with the spread held at the floor (5 ms), so
        // the band is 60 ± 1.253·5 and 61 ms sits inside it.
        let days = priorNights(10, hrv: 60) + [Fixtures.metric(today, hrv: 61)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let hrv = try XCTUnwrap(snap.hrv)

        XCTAssertEqual(hrv.day, today)
        XCTAssertEqual(hrv.value, 61)
        XCTAssertFalse(hrv.isStale)
        XCTAssertEqual(hrv.band, .inside)
        XCTAssertEqual(try XCTUnwrap(hrv.baseline), 60, accuracy: 1e-9, "today must not sit inside its own baseline")
        XCTAssertEqual(try XCTUnwrap(hrv.deviation).delta, 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(hrv.bandLow), 60 - Baselines.sigma(hrv.state), accuracy: 1e-9)
        XCTAssertEqual(hrv.recent.count, 11, "sparkline carries every valued night, capped at 14")
        XCTAssertEqual(hrv.recent.last?.day, today)
    }

    func testAboveAndBelowBand() throws {
        let above = TodaySnapshot.build(days: priorNights(10, hrv: 60) + [Fixtures.metric(today, hrv: 90)],
                                        nights: [], todayKey: today)
        XCTAssertEqual(try XCTUnwrap(above.hrv).band, .above)

        let below = TodaySnapshot.build(days: priorNights(10, hrv: 60) + [Fixtures.metric(today, hrv: 45)],
                                        nights: [], todayKey: today)
        XCTAssertEqual(try XCTUnwrap(below.hrv).band, .below)
    }

    func testRestingHrUsesItsOwnConfig() throws {
        // Resting HR floor spread is 2 bpm (σ ≈ 2.5): +2 bpm is inside, +6 bpm is above.
        let inside = TodaySnapshot.build(days: priorNights(10, hrv: 60, rhr: 50) + [Fixtures.metric(today, rhr: 52)],
                                         nights: [], todayKey: today)
        let rhr = try XCTUnwrap(inside.restingHr)
        XCTAssertEqual(rhr.value, 52)
        XCTAssertEqual(rhr.band, .inside)

        let high = TodaySnapshot.build(days: priorNights(10, hrv: 60, rhr: 50) + [Fixtures.metric(today, rhr: 56)],
                                       nights: [], todayKey: today)
        XCTAssertEqual(try XCTUnwrap(high.restingHr).band, .above)
    }

    // MARK: Calibrating and stale

    func testFewerThanSeedNights_isCalibrating() throws {
        // Two prior nights < Baselines.minNightsSeed (4): no band, no delta, an honest night count.
        let days = priorNights(2, hrv: 60) + [Fixtures.metric(today, hrv: 61)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let hrv = try XCTUnwrap(snap.hrv)

        XCTAssertEqual(hrv.band, .calibrating)
        XCTAssertNil(hrv.deviation)
        XCTAssertNil(hrv.baseline)
        XCTAssertEqual(hrv.value, 61, "the value itself still shows while calibrating")
        guard case .calibrating(let nights) = snap.readiness else {
            return XCTFail("expected .calibrating, got \(snap.readiness)")
        }
        XCTAssertEqual(nights, 3)
    }

    func testNewestNightOlderThanCarryWindow_isStale() throws {
        // Newest HRV night is 10 days old, past Baselines.vitalCarryDays (7): the tile blanks the value
        // and names the day; readiness must not present a tier from it.
        let lastDay = Fixtures.key(today, minus: 10)
        let days = (10...19).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 60) }
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let hrv = try XCTUnwrap(snap.hrv)

        XCTAssertTrue(hrv.isStale)
        XCTAssertNil(hrv.value)
        XCTAssertEqual(hrv.day, lastDay)
        XCTAssertNil(hrv.deviation)
        XCTAssertTrue(hrv.recent.isEmpty, "a stale sparkline would read as the last 14 nights")
        guard case .stale(let day) = snap.readiness else {
            return XCTFail("expected .stale, got \(snap.readiness)")
        }
        XCTAssertEqual(day, lastDay)
    }

    func testNoHrvAtAll_hasNoReading() {
        let snap = TodaySnapshot.build(days: [Fixtures.metric(today, rhr: 50)], nights: [], todayKey: today)
        XCTAssertNil(snap.hrv)
        XCTAssertNotNil(snap.restingHr)
    }

    // MARK: Readiness tier

    func testReadinessTier_fromFourteenValidNights() {
        let flat = TodaySnapshot.build(days: priorNights(14, hrv: 60) + [Fixtures.metric(today, hrv: 60)],
                                       nights: [], todayKey: today)
        guard case .tier(let tier) = flat.readiness else {
            return XCTFail("expected .tier, got \(flat.readiness)")
        }
        XCTAssertEqual(tier, .normal)

        // Fourteen nights at 60 ms then seven at 40 ms: the 7-night baseline sits below the long-window
        // band, and the EWMA baseline (going into today) still sits well above 40 ms.
        let high = (7...20).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 60) }
        let low = (1...6).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 40) }
        let dip = TodaySnapshot.build(days: high + low + [Fixtures.metric(today, hrv: 40)],
                                      nights: [], todayKey: today)
        guard case .tier(let dipTier) = dip.readiness else {
            return XCTFail("expected .tier, got \(dip.readiness)")
        }
        XCTAssertEqual(dipTier, .suppressed)
        XCTAssertEqual(dip.hrv?.band, .below)
    }

    // MARK: Sleep card

    func testSleepCard_deltaAgainstThirtyNightAverage() throws {
        let n0 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(today, sleepMin: 480, efficiency: 0.89)))
        let n1 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 1), sleepMin: 420)))
        let n2 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 2), sleepMin: 450)))
        let future = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: -1), sleepMin: 300)))

        let snap = TodaySnapshot.build(days: [], nights: [future, n0, n1, n2], todayKey: today)
        let sleep = try XCTUnwrap(snap.sleep)

        XCTAssertEqual(sleep.day, today, "a night dated after today is never last night")
        XCTAssertEqual(sleep.totalMin, 480)
        XCTAssertEqual(try XCTUnwrap(sleep.efficiencyPct), 89, accuracy: 1e-9)
        XCTAssertFalse(sleep.hasStages)
        XCTAssertEqual(try XCTUnwrap(sleep.avg30Min), 450, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.signedDurationText(minutes: sleep.totalMin - sleep.avg30Min!), "+30 min")

        // Below BaselineReadouts.sleepAverageMinNights the delta has nothing to compare against.
        let thin = TodaySnapshot.build(days: [], nights: [n0, n1], todayKey: today)
        XCTAssertNil(try XCTUnwrap(thin.sleep).avg30Min)
    }

    func testEffortIsTodaysStrainOnly() {
        let withToday = TodaySnapshot.build(days: priorNights(3, hrv: 60) + [Fixtures.metric(today, strain: 42)],
                                            nights: [], todayKey: today)
        XCTAssertEqual(withToday.effort, 42)
        let yesterdayOnly = TodaySnapshot.build(days: [Fixtures.metric(Fixtures.key(today, minus: 1), strain: 42)],
                                                nights: [], todayKey: today)
        XCTAssertNil(yesterdayOnly.effort)
    }

    // MARK: Formatting

    func testFormatters() {
        XCTAssertEqual(TodayFormat.signed(-2.4, unit: "bpm"), "\u{2212}2 bpm")
        XCTAssertNil(TodayFormat.wokeStamp(day: today, todayKey: today))
        XCTAssertEqual(TodayFormat.wokeStamp(day: Fixtures.key(today, minus: 1), todayKey: today)?.hasPrefix("Woke "), true)
    }

    /// One spelling for every span of minutes the app prints. The Today hero and stage legend, the Sleep
    /// hero, rows and stage cells, Trends' average, Progress's cells and sentence, the morning summary and
    /// the Workouts list all call these three, so no screen can spell a duration its own way.
    func testDurationText_isOneSpellingForEveryTab() {
        XCTAssertEqual(BaselineReadouts.durationText(minutes: 462), "7h 42m")
        XCTAssertEqual(BaselineReadouts.durationText(minutes: 480), "8h 00m")
        XCTAssertEqual(BaselineReadouts.durationText(minutes: 59.4), "59 min")
        XCTAssertEqual(BaselineReadouts.durationText(minutes: 59.5), "1h 00m")
        XCTAssertEqual(BaselineReadouts.durationText(minutes: 0), "0 min")
        XCTAssertEqual(BaselineReadouts.durationText(minutes: -3), "0 min", "a negative span never prints a sign")

        XCTAssertEqual(BaselineReadouts.durationText(seconds: 2_700), "45 min")
        XCTAssertEqual(BaselineReadouts.durationText(seconds: 3_900), "1h 05m")
        XCTAssertEqual(BaselineReadouts.durationText(seconds: 0), "–", "a session with no recorded length")
        XCTAssertEqual(BaselineReadouts.durationText(seconds: nil), "–")

        XCTAssertEqual(BaselineReadouts.durationSteadyMin, 5)
        XCTAssertNil(BaselineReadouts.signedDurationText(minutes: 3), "inside ±5 min reads as on average")
        XCTAssertNil(BaselineReadouts.signedDurationText(minutes: -4.4))
        XCTAssertEqual(BaselineReadouts.signedDurationText(minutes: 4.5), "+5 min")
        XCTAssertEqual(BaselineReadouts.signedDurationText(minutes: 22), "+22 min")
        XCTAssertEqual(BaselineReadouts.signedDurationText(minutes: -65), "\u{2212}1h 05m")
    }
}
