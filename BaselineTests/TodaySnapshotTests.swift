import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `TodaySnapshot.build`: band classification against the personal baseline, the per-metric recalibration
/// epochs, the calibrating and stale states, the readiness line, the sleep card's delta against the 30
/// nights before it and the logical-day effort row. Day keys are literals and the carry rule is UTC key
/// math, so nothing here depends on the machine's zone or clock.
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

    // MARK: Recalibration epochs

    /// NOOP folds HRV against `noop.hrvBaselineEpoch` and resting HR against `noop.recoveryBaselineEpoch`
    /// (`IntelligenceEngine`); the shared fold must make the same split or Today's tile and the engine's
    /// score could disagree after a "Recalibrate". An epoch set mid-history drops the earlier nights of
    /// ITS metric only.
    func testRestingHrFoldsAgainstTheRecoveryEpoch_hrvAgainstTheHrvEpoch() throws {
        let days = priorNights(10, hrv: 60, rhr: 50) + [Fixtures.metric(today, hrv: 61, rhr: 52)]
        // Day-start (UTC, the engine's parse) of the night 5 days ago: nights 10…6 ago predate it.
        let cutoffKey = Fixtures.key(today, minus: 5)
        let cutoff = try XCTUnwrap(TrendsDayKey.utc.date(from: cutoffKey)).timeIntervalSince1970

        XCTAssertEqual(BaselineReadouts.baselineEpoch(for: Baselines.hrvCfg), 0)
        XCTAssertEqual(BaselineReadouts.baselineEpoch(for: Baselines.restingHRCfg), 0)

        UserDefaults.standard.set(cutoff, forKey: Baselines.recoveryBaselineEpochKey)
        XCTAssertEqual(BaselineReadouts.baselineEpoch(for: Baselines.restingHRCfg), cutoff)
        XCTAssertEqual(BaselineReadouts.baselineEpoch(for: Baselines.hrvCfg), 0, "the HRV fold ignores the recovery epoch")
        let recoveryReset = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        XCTAssertEqual(try XCTUnwrap(recoveryReset.restingHr).state.nValid, 5, "nights 5…1 ago remain for resting HR")
        XCTAssertEqual(try XCTUnwrap(recoveryReset.hrv).state.nValid, 10, "HRV keeps every prior night")

        UserDefaults.standard.removeObject(forKey: Baselines.recoveryBaselineEpochKey)
        UserDefaults.standard.set(cutoff, forKey: Baselines.hrvBaselineEpochKey)
        let hrvReset = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        XCTAssertEqual(try XCTUnwrap(hrvReset.hrv).state.nValid, 5)
        XCTAssertEqual(try XCTUnwrap(hrvReset.restingHr).state.nValid, 10, "the resting-HR fold ignores the HRV epoch")

        // The nightly walk (Trends' band, Progress' trajectory) makes the same split as the single fold.
        let rhrWalk = BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) }
        XCTAssertEqual(rhrWalk.count, 11, "no recovery epoch: every night walked")
        let hrvWalk = BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.hrvCfg) { $0.avgHrv }
        XCTAssertEqual(hrvWalk.count, 6, "HRV epoch: nights before it are dropped, not held")
        XCTAssertEqual(hrvWalk.first?.day, cutoffKey)

        // An explicit epoch overrides the per-metric default (the injectable seam).
        let explicit = BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.restingHRCfg, epoch: cutoff) { $0.restingHr.map(Double.init) }
        XCTAssertEqual(explicit.count, 6)
    }

    // MARK: Sleep card

    func testSleepCard_deltaAgainstThirtyNightsBeforeIt() throws {
        let n0 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(today, sleepMin: 480, efficiency: 0.89)))
        let n1 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 1), sleepMin: 420)))
        let n2 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 2), sleepMin: 450)))
        let n3 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 3), sleepMin: 390)))
        let future = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: -1), sleepMin: 300)))

        let snap = TodaySnapshot.build(days: [], nights: [future, n0, n1, n2, n3], todayKey: today)
        let sleep = try XCTUnwrap(snap.sleep)

        XCTAssertEqual(sleep.day, today, "a night dated after today is never last night")
        XCTAssertEqual(sleep.totalMin, 480)
        XCTAssertEqual(try XCTUnwrap(sleep.efficiencyPct), 89, accuracy: 1e-9)
        XCTAssertFalse(sleep.hasStages)
        // The three nights BEFORE last night (420 / 450 / 390), never last night itself.
        XCTAssertEqual(try XCTUnwrap(sleep.avg30Min), 420, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.signedDurationText(minutes: sleep.totalMin - sleep.avg30Min!), "+1h 00m")

        // Below BaselineReadouts.sleepAverageMinNights earlier nights the delta has nothing to compare against.
        let thin = TodaySnapshot.build(days: [], nights: [n0, n1, n2], todayKey: today)
        XCTAssertNil(try XCTUnwrap(thin.sleep).avg30Min)
    }

    /// ONE comparison average for every "vs your 30-night average" (Today's card, the Sleep hero and bar
    /// rule, a night's detail, the morning summary): the 30 nights strictly before the night in question.
    func testSleepAverage30Before_isTheThirtyEarlierNights() throws {
        // 40 nights ending today, newest first; night i (0 = today) slept 400 + i minutes.
        let nights = try (0..<40).map { i in
            try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: i), sleepMin: 400 + Double(i))))
        }
        // Before today: nights 1…30 → mean of 401…430 = 415.5.
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.sleepAverage30(before: today, in: nights)), 415.5, accuracy: 1e-9)
        // Before the night 5 days ago: nights 6…35 → mean of 406…435 = 420.5; order of `nights` is newest first.
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.sleepAverage30(before: Fixtures.key(today, minus: 5), in: nights)), 420.5, accuracy: 1e-9)
        // The oldest nights have too few before them.
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.sleepAverage30(before: Fixtures.key(today, minus: 36), in: nights)), 438, accuracy: 1e-9,
                       "three earlier nights (437 / 438 / 439) just clear the gate")
        XCTAssertNil(BaselineReadouts.sleepAverage30(before: Fixtures.key(today, minus: 37), in: nights))
        XCTAssertNil(BaselineReadouts.sleepAverage30(before: Fixtures.key(today, minus: 39), in: nights))
        // The inclusive figure (Progress' "you're averaging …") counts the newest night too.
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.sleepAverage30(nights)), 414.5, accuracy: 1e-9)
    }

    // MARK: Effort

    func testEffortIsTodaysStrainOnly() {
        let withToday = TodaySnapshot.build(days: priorNights(3, hrv: 60) + [Fixtures.metric(today, strain: 42)],
                                            nights: [], todayKey: today)
        XCTAssertEqual(withToday.effort, 42)
        let yesterdayOnly = TodaySnapshot.build(days: [Fixtures.metric(Fixtures.key(today, minus: 1), strain: 42)],
                                                nights: [], todayKey: today)
        XCTAssertNil(yesterdayOnly.effort)
    }

    /// Effort is read from NOOP's logical day (`Repository.resolveToday`): in the small hours the row still
    /// being lived is yesterday's, unless the new local day already has a banked night (#304), in which
    /// case that row is today. The journal and the night readings keep the local key.
    func testEffortFollowsTheLogicalDayRow() {
        let yesterday = Fixtures.key(today, minus: 1)
        let days = [Fixtures.metric(yesterday, strain: 42), Fixtures.metric(today, strain: 7)]
        let smallHours = TodaySnapshot.build(days: days, nights: [], todayKey: today, logicalKey: yesterday)
        XCTAssertEqual(smallHours.effort, 42, "before the 04:00 rollover today's effort is yesterday's row")
        XCTAssertEqual(smallHours.todayKey, today, "the local key stays the journal's and the nights' day")

        let banked = [Fixtures.metric(yesterday, strain: 42), Fixtures.metric(today, sleepMin: 400, strain: 7)]
        let earlyWake = TodaySnapshot.build(days: banked, nights: [], todayKey: today, logicalKey: yesterday)
        XCTAssertEqual(earlyWake.effort, 7, "a night banked under the new local day makes that row today")

        let daytime = TodaySnapshot.build(days: days, nights: [], todayKey: today, logicalKey: today)
        XCTAssertEqual(daytime.effort, 7)
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
