import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// The Progress model: `BaselineReadouts.nightlyStates` (the one fold walk shared with Trends), the
/// trajectory, the EWMA noise floor, the comparison anchor, the status ladder, the sleep windows (timing
/// through `BaselineReadouts.sleepTiming`, the Sleep tab's readout), the weekly fitness ladder and every
/// sentence. Day keys are literals and the horizon math is UTC key arithmetic, so nothing here
/// depends on the machine's zone or clock except the timing test, which builds local instants.
final class ProgressModelTests: BaselineEngineTestCase {

    private let today = "2026-02-18"
    private func key(_ daysAgo: Int) -> String { Fixtures.key(today, minus: daysAgo) }

    /// `n` nights of the same value ending the day before `today`, oldest first.
    private func priorNights(_ n: Int, hrv: Double, rhr: Int? = nil) -> [DailyMetric] {
        (1...n).reversed().map { Fixtures.metric(key($0), hrv: hrv, rhr: rhr) }
    }

    private func hrvWalk(_ days: [DailyMetric]) -> [BaselineReadouts.NightState] {
        BaselineReadouts.nightlyStates(upToToday: days.filter { $0.day <= today }, cfg: Baselines.hrvCfg) { $0.avgHrv }
    }

    private func hrvStatus(_ days: [DailyMetric], _ horizon: ProgressHorizon) -> ProgressMetricStatus {
        ProgressMetric.build(upToToday: days.filter { $0.day <= today }, cfg: Baselines.hrvCfg,
                             todayKey: today, horizon: horizon) { $0.avgHrv }
    }

    /// `Baselines.sigma` at each metric's floor spread (1.253 × 5 ms, 1.253 × 2 bpm).
    private let hrvSigmaFloor = 1.253 * 5.0
    private let rhrSigmaFloor = 1.253 * 2.0

    /// A trusted trajectory point.
    private func point(_ day: String, baseline: Double, sigma: Double = 1.253 * 5.0, nValid: Int = 20) -> ProgressPoint {
        ProgressPoint(id: day, date: TrendsDayKey.date(day)!, baseline: baseline, sigma: sigma, nValid: nValid, trusted: true)
    }

    // MARK: - nightlyStates / trajectory

    func testNightlyStatesEndpointEqualsLatestNight() throws {
        // 20 nights at 60 then 20 rising towards 70, resting HR flat at 50.
        let flat = (21...40).reversed().map { Fixtures.metric(key($0), hrv: 60, rhr: 50) }
        let rising = (1...20).reversed().map { Fixtures.metric(key($0), hrv: 60 + Double(21 - $0) * 0.5, rhr: 50) }
        let days = flat + rising

        let walk = hrvWalk(days)
        let latest = BaselineReadouts.latestNight(upToToday: days, cfg: Baselines.hrvCfg) { $0.avgHrv }
        XCTAssertEqual(try XCTUnwrap(walk.last?.stateGoingIn), latest.state)
        let lastPoint = try XCTUnwrap(ProgressTrajectory.build(walk: walk).last)
        XCTAssertEqual(lastPoint.baseline, latest.state.baseline, accuracy: 1e-9)
        XCTAssertEqual(lastPoint.nValid, latest.state.nValid)

        let rhrWalk = BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) }
        let rhrLatest = BaselineReadouts.latestNight(upToToday: days, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) }
        XCTAssertEqual(try XCTUnwrap(rhrWalk.last?.stateGoingIn), rhrLatest.state)
        XCTAssertEqual(try XCTUnwrap(ProgressTrajectory.build(walk: rhrWalk).last).baseline, rhrLatest.state.baseline, accuracy: 1e-9)
    }

    func testTrajectoryMatchesTrendsBandLine() throws {
        // Trends keys nights through the local zone, so this fixture does too.
        let now = Fixtures.local(2026, 2, 18, hour: 12)
        let days = (0..<120).reversed().map { ago in
            Fixtures.metric(Fixtures.dayKey(now, minus: ago), hrv: ago >= 60 ? 55 : 68)
        }
        let series = TrendsSeries.build(days: days, range: .quarter, now: now)
        let trajectory = ProgressTrajectory.build(walk: BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.hrvCfg) { $0.avgHrv })
        let byId = Dictionary(uniqueKeysWithValues: trajectory.map { ($0.id, $0) })

        var compared = 0
        for p in series.hrv.points {
            guard let b = p.baseline else { continue }
            let t = try XCTUnwrap(byId[p.id], "Trends has a band at \(p.id); Progress must have the point")
            XCTAssertEqual(t.baseline, b, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(p.low), t.baseline - t.sigma, accuracy: 1e-9)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 80)
    }

    func testPointIsStateGoingIn() throws {
        let days = priorNights(20, hrv: 60) + [Fixtures.metric(today, hrv: 90)]
        let last = try XCTUnwrap(ProgressTrajectory.build(walk: hrvWalk(days)).last)
        XCTAssertEqual(last.id, today)
        XCTAssertEqual(last.baseline, 60, accuracy: 1e-9, "a night never sits inside its own baseline")
    }

    func testGating() throws {
        // Nights 1…20 at 60 ms, except night 8 (300 ms, out of range) and night 9 (no HRV).
        let days: [DailyMetric] = (1...20).map { i in
            let day = key(21 - i)
            switch i {
            case 8: return Fixtures.metric(day, hrv: 300)
            case 9: return Fixtures.metric(day, hrv: nil, rhr: 50)
            default: return Fixtures.metric(day, hrv: 60)
            }
        }
        let walk = hrvWalk(days)
        let points = ProgressTrajectory.build(walk: walk)
        let byId = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        let first = try XCTUnwrap(points.first)
        XCTAssertEqual(first.id, key(21 - 5), "first point on the 5th valid night")
        XCTAssertEqual(first.nValid, 4)
        XCTAssertFalse(first.trusted)

        XCTAssertNil(byId[key(21 - 8)], "an out-of-range night emits no point")
        XCTAssertNil(byId[key(21 - 9)], "a nil night emits no point")
        let before = try XCTUnwrap(byId[key(21 - 7)])
        let after = try XCTUnwrap(byId[key(21 - 10)])
        XCTAssertEqual(after.nValid, before.nValid + 1, "the gap did not advance nValid")
        XCTAssertEqual(after.baseline, before.baseline, accuracy: 1e-9, "skip-and-hold across the gap")

        // 14 valid nights are banked going into the 15th valid night (night 17): trusted flips there.
        XCTAssertFalse(try XCTUnwrap(byId[key(21 - 16)]).trusted)
        let fifteenth = try XCTUnwrap(byId[key(21 - 17)])
        XCTAssertTrue(fifteenth.trusted)
        XCTAssertEqual(fifteenth.nValid, Baselines.minNightsTrust)
    }

    func testEpochDropsEarlierNights() throws {
        // 30 flat nights; recalibrate at the UTC start of the 10th night (key(21)).
        let days = priorNights(30, hrv: 60, rhr: 50)
        let epochDay = key(21)
        let epoch = try XCTUnwrap(TrendsDayKey.utc.date(from: epochDay)).timeIntervalSince1970
        // NOOP's "Recalibrate" writes both keys: HRV re-anchors on the HRV epoch, resting HR on the
        // recovery epoch (`BaselineReadouts.baselineEpoch(for:)`).
        Baselines.recalibrateRecoveryBaselines(now: epoch)
        defer {
            UserDefaults.standard.removeObject(forKey: Baselines.hrvBaselineEpochKey)
            UserDefaults.standard.removeObject(forKey: Baselines.recoveryBaselineEpochKey)
        }

        XCTAssertTrue(TrendsDayKey.isBeforeEpoch(key(22), epoch: epoch))
        XCTAssertFalse(TrendsDayKey.isBeforeEpoch(epochDay, epoch: epoch))
        XCTAssertFalse(TrendsDayKey.isBeforeEpoch(key(22), epoch: 0), "no recalibration drops nothing")

        let walk = hrvWalk(days)
        XCTAssertEqual(walk.first?.day, epochDay)
        XCTAssertEqual(walk.count, 21)
        let points = ProgressTrajectory.build(walk: walk)
        XCTAssertEqual(try XCTUnwrap(points.first).nValid, 4)
        XCTAssertEqual(points.first?.id, key(17))

        // Resting HR re-anchors on the recovery epoch, which "Recalibrate" set to the same instant.
        let rhrWalk = BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) }
        XCTAssertEqual(rhrWalk.map(\.day), walk.map(\.day))
        XCTAssertEqual(ProgressTrajectory.build(walk: rhrWalk).first?.id, key(17))

        // The two epochs are separate keys: clearing the recovery epoch alone keeps every resting HR
        // night while HRV still drops the nine before its own epoch.
        UserDefaults.standard.removeObject(forKey: Baselines.recoveryBaselineEpochKey)
        XCTAssertEqual(BaselineReadouts.baselineEpoch(for: Baselines.restingHRCfg), 0, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.baselineEpoch(for: Baselines.hrvCfg), epoch, accuracy: 1e-9)
        let rhrAll = BaselineReadouts.nightlyStates(upToToday: days, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) }
        XCTAssertEqual(rhrAll.count, 30)
        XCTAssertEqual(hrvWalk(days).count, 21)
    }

    // MARK: - Noise and comparison

    func testNoiseFloor() {
        XCTAssertEqual(ProgressNoise.factor(cfg: Baselines.hrvCfg), 0.4450, accuracy: 0.001)
        XCTAssertEqual(ProgressNoise.floor(cfg: Baselines.hrvCfg, sigmaThen: 6.265, sigmaNow: 6.265), 2.79, accuracy: 0.01)
        XCTAssertEqual(ProgressNoise.floor(cfg: Baselines.restingHRCfg, sigmaThen: 2.506, sigmaNow: 2.506), 1.12, accuracy: 0.01)
        let single = ProgressNoise.floor(cfg: Baselines.hrvCfg, sigmaThen: 6.265, sigmaNow: 6.265)
        XCTAssertEqual(ProgressNoise.floor(cfg: Baselines.hrvCfg, sigmaThen: 6.265, sigmaNow: 12.53), 2 * single, accuracy: 1e-9)
    }

    func testResolveAnchorAtCutoff() throws {
        // 140 nights so the 31 nights before a 20-night gap ending at the cutoff are themselves trusted.
        let full = priorNights(140, hrv: 60)
        let trusted = ProgressTrajectory.build(walk: hrvWalk(full)).filter(\.trusted)
        let cutoff = Baselines.cutoffKey(todayKey: today, carryDays: 90)

        let c = try XCTUnwrap(ProgressComparison.resolve(trusted: trusted, todayKey: today, horizon: .quarter, cfg: Baselines.hrvCfg))
        XCTAssertEqual(c.then.day, cutoff)
        XCTAssertEqual(c.now.day, key(1))
        XCTAssertFalse(c.namesDate)

        // Strap off for the 20 nights ending at the cutoff: the anchor slides to the last point before
        // the gap and the sentence names its date.
        let gap20 = Set((90...109).map { key($0) })
        let withGap = full.filter { !gap20.contains($0.day) }
        let t20 = ProgressTrajectory.build(walk: hrvWalk(withGap)).filter(\.trusted)
        let g = try XCTUnwrap(ProgressComparison.resolve(trusted: t20, todayKey: today, horizon: .quarter, cfg: Baselines.hrvCfg))
        XCTAssertEqual(g.then.day, key(110))
        XCTAssertTrue(g.namesDate)

        // A 10-night gap is within the 14-day tolerance.
        let gap10 = Set((90...99).map { key($0) })
        let t10 = ProgressTrajectory.build(walk: hrvWalk(full.filter { !gap10.contains($0.day) })).filter(\.trusted)
        let s = try XCTUnwrap(ProgressComparison.resolve(trusted: t10, todayKey: today, horizon: .quarter, cfg: Baselines.hrvCfg))
        XCTAssertEqual(s.then.day, key(100))
        XCTAssertFalse(s.namesDate)
    }

    func testResolveAllTime() throws {
        let trusted = ProgressTrajectory.build(walk: hrvWalk(priorNights(40, hrv: 60))).filter(\.trusted)
        let c = try XCTUnwrap(ProgressComparison.resolve(trusted: trusted, todayKey: today, horizon: .all, cfg: Baselines.hrvCfg))
        XCTAssertEqual(c.then.id, trusted.first?.id)
        XCTAssertEqual(c.then.nValid, Baselines.minNightsTrust)
        XCTAssertTrue(c.namesDate)

        let one = ProgressTrajectory.build(walk: hrvWalk(priorNights(15, hrv: 60))).filter(\.trusted)
        XCTAssertEqual(one.count, 1)
        XCTAssertNil(ProgressComparison.resolve(trusted: one, todayKey: today, horizon: .all, cfg: Baselines.hrvCfg))
    }

    func testSteadyUsesNoise() {
        func hrv(_ a: Double, _ b: Double) -> ProgressComparison {
            let then = point("2025-11-20", baseline: a, sigma: hrvSigmaFloor)
            let now = point("2026-02-17", baseline: b, sigma: hrvSigmaFloor)
            return ProgressComparison(then: then, now: now,
                                      noise: ProgressNoise.floor(cfg: Baselines.hrvCfg, sigmaThen: then.sigma, sigmaNow: now.sigma),
                                      namesDate: false)
        }
        func rhr(_ a: Double, _ b: Double) -> ProgressComparison {
            let then = point("2025-11-20", baseline: a, sigma: rhrSigmaFloor)
            let now = point("2026-02-17", baseline: b, sigma: rhrSigmaFloor)
            return ProgressComparison(then: then, now: now,
                                      noise: ProgressNoise.floor(cfg: Baselines.restingHRCfg, sigmaThen: then.sigma, sigmaNow: now.sigma),
                                      namesDate: false)
        }
        func status(_ c: ProgressComparison) -> ProgressMetricStatus { .ready(comparison: c, points: [c.then, c.now], asOfDay: nil) }

        XCTAssertTrue(hrv(58, 60).steady, "2.0 ms < 2.79 ms floor")
        XCTAssertFalse(hrv(58, 61).steady)
        XCTAssertEqual(ProgressCopy.tone(status: status(hrv(58, 61)), higherIsBetter: true), .improving)
        XCTAssertEqual(ProgressCopy.tone(status: status(hrv(58, 60)), higherIsBetter: true), .steady)

        XCTAssertTrue(rhr(50, 50.9).steady, "0.9 bpm < 1.12 bpm floor")
        XCTAssertFalse(rhr(50, 51.5).steady)
        XCTAssertEqual(ProgressCopy.tone(status: status(rhr(50, 51.5)), higherIsBetter: false), .worsening)
        XCTAssertEqual(ProgressCopy.tone(status: status(rhr(50, 48)), higherIsBetter: false), .improving)

        XCTAssertTrue(hrv(60, 60.4).steady, "rounds to 0")
        XCTAssertEqual(hrv(58, 64).delta, 6, accuracy: 1e-9)
        XCTAssertEqual(ProgressCopy.tone(status: .calibrating(nights: 3), higherIsBetter: true), .none)
    }

    // MARK: - Status ladder

    func testLadderPrecedence() throws {
        XCTAssertEqual(hrvStatus([Fixtures.metric(key(1), hrv: 300)], .quarter), .empty)
        XCTAssertEqual(hrvStatus([], .quarter), .empty)
        XCTAssertEqual(hrvStatus(priorNights(9, hrv: 60), .quarter), .calibrating(nights: 9))

        let outliers = (14...18).reversed().map { Fixtures.metric(key($0), hrv: 300) }
        XCTAssertEqual(hrvStatus(outliers + priorNights(13, hrv: 60), .quarter), .calibrating(nights: 13))

        // 20 nights: the 15th valid night (key(6)) is the first trusted point; six trusted points in all.
        guard case .settling(let firstDay, let compareFrom, let points) = hrvStatus(priorNights(20, hrv: 60), .quarter) else {
            return XCTFail("expected .settling")
        }
        XCTAssertEqual(firstDay, key(6))
        XCTAssertEqual(compareFrom, Baselines.cutoffKey(todayKey: key(6), carryDays: -90))
        XCTAssertEqual(points.count, 6)
        XCTAssertTrue(points.allSatisfy(\.trusted), "only trusted points are handed to the chart")

        // 15 nights: exactly one trusted point, so `.all` has no second point to compare against.
        guard case .settling(_, let allCompareFrom, _) = hrvStatus(priorNights(15, hrv: 60), .all) else {
            return XCTFail("expected .settling for .all with a single trusted point")
        }
        XCTAssertNil(allCompareFrom)

        guard case .ready(let c, let readyPoints, let asOf) = hrvStatus(priorNights(120, hrv: 60), .quarter) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(c.then.day, key(90))
        XCTAssertEqual(readyPoints.count, 120 - 14)
        XCTAssertNil(asOf)
    }

    func testCompareFromDayArithmetic() {
        XCTAssertEqual(Baselines.cutoffKey(todayKey: "2025-12-01", carryDays: -90), "2026-03-01")
        XCTAssertEqual(Baselines.cutoffKey(todayKey: "2025-06-15", carryDays: -365), "2026-06-15")
        XCTAssertEqual(ProgressHorizon.quarter.cutoff(todayKey: "2026-03-01"), "2025-12-01")
        XCTAssertNil(ProgressHorizon.all.cutoff(todayKey: today))
    }

    func testPausedAndAsOf() throws {
        func nights(newestAgo: Int, count: Int) -> [DailyMetric] {
            (newestAgo..<(newestAgo + count)).reversed().map { Fixtures.metric(key($0), hrv: 60) }
        }
        guard case .paused(let lastDay, let points) = hrvStatus(nights(newestAgo: 15, count: 100), .quarter) else {
            return XCTFail("expected .paused")
        }
        XCTAssertEqual(lastDay, key(15))
        XCTAssertEqual(points.count, 86)

        guard case .ready = hrvStatus(nights(newestAgo: 14, count: 100), .quarter) else {
            return XCTFail("14 days old is still within staleDays")
        }
        guard case .ready(_, _, let asOf8) = hrvStatus(nights(newestAgo: 8, count: 100), .quarter) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(asOf8, key(8))
        guard case .ready(_, _, let asOf7) = hrvStatus(nights(newestAgo: 7, count: 100), .quarter) else {
            return XCTFail("expected .ready")
        }
        XCTAssertNil(asOf7)
    }

    func testStaleGapResumes() throws {
        // 30 nights, then 16 rows without HRV (the engine marks the state stale), then one night back.
        let before = (18...47).reversed().map { Fixtures.metric(key($0), hrv: 60) }
        let gap = (2...17).reversed().map { Fixtures.metric(key($0), hrv: nil, rhr: 50) }
        let back = [Fixtures.metric(key(1), hrv: 60)]

        guard case .ready(let c, _, let asOf) = hrvStatus(before + gap + back, .all) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(asOf, key(18), "now is the last trusted point before the gap")
        XCTAssertEqual(c.now.day, key(18))
        XCTAssertEqual(c.now.baseline, 60, accuracy: 1e-9)

        guard case .ready(let c2, _, let asOf2) = hrvStatus(before + gap + back + [Fixtures.metric(today, hrv: 60)], .all) else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(c2.now.day, today, "the second night back is judged against a refreshed, trusted state")
        XCTAssertNil(asOf2)
    }

    // MARK: - Copy

    func testMetricSentences() throws {
        func ready(_ a: Double, _ b: Double, cfg: MetricCfg, sigma: Double, thenDay: String = "2025-11-20",
                   namesDate: Bool = false) -> ProgressMetricStatus {
            let then = point(thenDay, baseline: a, sigma: sigma)
            let now = point("2026-02-17", baseline: b, sigma: sigma)
            let c = ProgressComparison(then: then, now: now,
                                       noise: ProgressNoise.floor(cfg: cfg, sigmaThen: sigma, sigmaNow: sigma),
                                       namesDate: namesDate)
            return .ready(comparison: c, points: [then, now], asOfDay: nil)
        }
        let mar3 = ProgressCopy.date("2026-03-03")
        var sentences: [String] = []
        func check(_ s: String, _ expected: String, line: UInt = #line) {
            XCTAssertEqual(s, expected, line: line)
            sentences.append(s)
        }

        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: ready(58, 64, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor), horizon: .quarter),
              "Your HRV baseline is 6 ms higher than 90 days ago.")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: ready(62, 58, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor), horizon: .quarter),
              "Your HRV baseline is 4 ms lower than 90 days ago.")
        check(ProgressCopy.sentence(noun: "resting HR", unit: "bpm", status: ready(53, 50, cfg: Baselines.restingHRCfg, sigma: rhrSigmaFloor), horizon: .half),
              "Your resting HR baseline is 3 bpm lower than 180 days ago.")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: ready(58, 60, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor), horizon: .quarter),
              "Your HRV baseline is about where it was 90 days ago.")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: ready(58, 64, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor, thenDay: "2026-03-03", namesDate: true), horizon: .year),
              "Your HRV baseline is 6 ms higher than on \(mar3).")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: ready(58, 60, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor, thenDay: "2026-03-03", namesDate: true), horizon: .year),
              "Your HRV baseline is about where it was on \(mar3).")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: ready(58, 64, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor, thenDay: "2026-03-03", namesDate: true), horizon: .all),
              "Your HRV baseline is 6 ms higher than when it settled on \(mar3).")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: .calibrating(nights: 9), horizon: .quarter),
              "Your HRV baseline settles after 14 nights; Progress starts the night after · 9 so far.")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: .calibrating(nights: 14), horizon: .quarter),
              "Your HRV baseline settles after 14 nights; Progress starts the night after · 14 so far.")
        let settled = "2025-09-18"
        let compareFrom = Baselines.cutoffKey(todayKey: settled, carryDays: -90)
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: .settling(firstTrustedDay: settled, compareFromDay: compareFrom, points: []), horizon: .quarter),
              "Your HRV baseline settled on \(ProgressCopy.date(settled)). Compare it with 90 days ago from \(ProgressCopy.date(compareFrom)).")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: .settling(firstTrustedDay: settled, compareFromDay: nil, points: []), horizon: .all),
              "Your HRV baseline settled on \(ProgressCopy.date(settled)). Keep wearing the strap and this line grows.")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: .paused(lastDay: "2025-09-12", points: []), horizon: .quarter),
              "No HRV since \(ProgressCopy.date("2025-09-12")). Progress resumes with the next synced night.")
        check(ProgressCopy.sentence(noun: "resting HR", unit: "bpm", status: .paused(lastDay: "2025-09-12", points: []), horizon: .quarter),
              "No resting HR since \(ProgressCopy.date("2025-09-12")). Progress resumes with the next synced night.")
        check(ProgressCopy.sentence(noun: "HRV", unit: "ms", status: .empty, horizon: .quarter), "No nights with HRV yet.")
        check(ProgressCopy.sentence(noun: "resting HR", unit: "bpm", status: .empty, horizon: .quarter), "No nights with resting HR yet.")

        let hrvFoot = try XCTUnwrap(ProgressCopy.footnote(unit: "ms", status: ready(58, 64, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor)))
        XCTAssertEqual(hrvFoot, "Changes under about 3 ms are within the baseline's own noise.")
        let rhrFoot = try XCTUnwrap(ProgressCopy.footnote(unit: "bpm", status: ready(53, 50, cfg: Baselines.restingHRCfg, sigma: rhrSigmaFloor)))
        XCTAssertEqual(rhrFoot, "Changes under about 2 bpm are within the baseline's own noise.")
        XCTAssertFalse(hrvFoot.contains("Trends"), "what the line is belongs to the closing caption, said once")
        XCTAssertNotNil(ProgressCopy.footnote(unit: "ms", status: .paused(lastDay: "2025-09-12", points: [])))
        XCTAssertNil(ProgressCopy.footnote(unit: "ms", status: .calibrating(nights: 2)))
        XCTAssertNil(ProgressCopy.footnote(unit: "ms", status: .empty))

        for s in sentences + [hrvFoot, rhrFoot] {
            XCTAssertFalse(s.contains("\u{2212}"), "no typographic minus in a sentence: \(s)")
        }

        // Cells.
        guard case .ready(let c, _, _) = ready(58, 64, cfg: Baselines.hrvCfg, sigma: hrvSigmaFloor) else { return XCTFail() }
        XCTAssertEqual(ProgressCopy.thenLabel(c), "Then · \(ProgressCopy.date("2025-11-20"))")
        XCTAssertEqual(ProgressCopy.nowLabel(c, asOfDay: nil), "Now · \(ProgressCopy.date("2026-02-17"))")
        XCTAssertEqual(ProgressCopy.nowLabel(c, asOfDay: "2026-02-10"), "Now · as of \(ProgressCopy.date("2026-02-10"))")
        XCTAssertTrue(ProgressCopy.closingCaption(recalibratedOn: "2025-06-02").hasPrefix("Counting from your recalibration on \(ProgressCopy.date("2025-06-02")). "))
        let closing = ProgressCopy.closingCaption(recalibratedOn: nil)
        XCTAssertTrue(closing.hasPrefix("The HRV and resting HR lines are your baseline going into each night, the same dashed line Trends draws"), closing)
        XCTAssertEqual(closing.components(separatedBy: "dashed line").count, 2, "the baseline explanation appears exactly once")
    }

    func testCalibratingReportsTheEnginesCount() throws {
        // Exactly 14 valid prior nights: the fold is trusted (nValid 14) but no night has been judged
        // against it yet, so there is no trusted point. The copy must say 14, the engine's own count,
        // and not claim the baseline is still short of 14.
        let fourteen = priorNights(14, hrv: 60)
        XCTAssertEqual(hrvStatus(fourteen, .quarter), .calibrating(nights: 14))
        let latest = BaselineReadouts.latestNight(upToToday: fourteen, cfg: Baselines.hrvCfg) { $0.avgHrv }
        XCTAssertEqual(latest.state.nValid, 13, "the Today hero counts the fold BEFORE the newest night")
        let folded = Baselines.foldHistory(fourteen.map(\.avgHrv), dayKeys: fourteen.map(\.day), cfg: Baselines.hrvCfg)
        XCTAssertEqual(folded.nValid, 14, "the engine's fold over every night so far")
        XCTAssertTrue(folded.trusted)

        // Out-of-range and missing nights are skipped by the engine and so by the count.
        let withGaps = priorNights(10, hrv: 60) + [Fixtures.metric(key(0), hrv: 300)]
        XCTAssertEqual(hrvStatus(withGaps, .quarter), .calibrating(nights: 10))
        XCTAssertEqual(hrvStatus(priorNights(3, hrv: 60), .quarter), .calibrating(nights: 3))

        // The 15th valid night is the first trusted point: settling, not calibrating.
        guard case .settling(let firstDay, _, let points) = hrvStatus(priorNights(15, hrv: 60), .quarter) else {
            return XCTFail("expected .settling")
        }
        XCTAssertEqual(firstDay, key(1))
        XCTAssertEqual(points.count, 1)
    }

    func testClockIsTheReadouts() {
        // Progress prints bedtimes exactly as the Sleep tab's readout does.
        XCTAssertEqual(ProgressCopy.clock(minutes: 23 * 60 + 24), BaselineReadouts.clockText(minutes: 23 * 60 + 24))
        XCTAssertEqual(ProgressCopy.clock(minutes: 0), BaselineReadouts.clockText(minutes: 0))
        XCTAssertFalse(ProgressCopy.clock(minutes: 12 * 60).isEmpty)
    }

    func testHorizonPickerGate() {
        // Calibrating metrics and a building sleep average: nothing on screen depends on the horizon.
        let early = ProgressSnapshot.build(days: priorNights(5, hrv: 60, rhr: 50), nights: [], horizon: .quarter, todayKey: today)
        XCTAssertEqual(early.hrv, .calibrating(nights: 5))
        XCTAssertFalse(early.hasHorizonContent)

        // One settled metric is enough.
        XCTAssertTrue(ProgressSnapshot.build(days: priorNights(20, hrv: 60), nights: [], horizon: .quarter, todayKey: today).hasHorizonContent)
        XCTAssertTrue(ProgressSnapshot.build(days: priorNights(120, hrv: 60), nights: [], horizon: .all, todayKey: today).hasHorizonContent)
        let paused = (15..<115).reversed().map { Fixtures.metric(key($0), hrv: 60) }
        XCTAssertTrue(ProgressSnapshot.build(days: paused, nights: [], horizon: .quarter, todayKey: today).hasHorizonContent)

        // So is a sleep average that names the day its comparison arrives.
        let sleepOnly = dailyNights(20) { _ in 420 }
        let sleepSnap = ProgressSnapshot.build(days: [], nights: sleepOnly, horizon: .quarter, todayKey: today)
        XCTAssertEqual(sleepSnap.hrv, .empty)
        guard case .nowOnly = sleepSnap.sleep.duration else { return XCTFail("expected .nowOnly") }
        XCTAssertTrue(sleepSnap.hasHorizonContent)

        // Two nights of sleep and no metrics: the average is still building.
        XCTAssertFalse(ProgressSnapshot.build(days: [], nights: dailyNights(2) { _ in 420 }, horizon: .quarter, todayKey: today).hasHorizonContent)
        XCTAssertFalse(ProgressSnapshot.build(days: [], nights: [], horizon: .quarter, todayKey: today).hasHorizonContent)

        // A first fitness estimate (four nights of resting HR and a profile) also names a comparison day.
        let fourNights = priorNights(4, hrv: 60, rhr: 50)
        XCTAssertFalse(ProgressSnapshot.build(days: fourNights, nights: [], horizon: .quarter, todayKey: today).hasHorizonContent,
                       "no profile: no estimate")
        let withProfile = ProgressSnapshot.build(days: fourNights, nights: [], horizon: .quarter, todayKey: today, profile: profile)
        guard case .settling = withProfile.fitness else { return XCTFail("expected .settling") }
        XCTAssertTrue(withProfile.hasHorizonContent)
    }

    func testTodayRowEqualsProgressCard() {
        let days = priorNights(120, hrv: 60) + [Fixtures.metric(today, hrv: 66)]
        for horizon in ProgressHorizon.allCases {
            let snap = ProgressSnapshot.build(days: days, nights: [], horizon: horizon, todayKey: today)
            XCTAssertEqual(ProgressSnapshot.hrvHeadline(days: days, horizon: horizon, todayKey: today),
                           ProgressCopy.sentence(noun: "HRV", unit: "ms", status: snap.hrv, horizon: horizon))
        }
        XCTAssertNotNil(ProgressSnapshot.hrvHeadline(days: priorNights(20, hrv: 60), horizon: .quarter, todayKey: today), "settling shows")
        XCTAssertNil(ProgressSnapshot.hrvHeadline(days: priorNights(9, hrv: 60), horizon: .quarter, todayKey: today), "calibrating hides the row")
        XCTAssertNil(ProgressSnapshot.hrvHeadline(days: [Fixtures.metric(key(1), rhr: 50)], horizon: .quarter, todayKey: today), "no HRV hides the row")
    }

    // MARK: - Sleep

    /// Daily-row nights (newest first) for `count` nights ending yesterday; `minutes(i)` with i = 0 the newest.
    private func dailyNights(_ count: Int, minutes: (Int) -> Double) -> [SleepNight] {
        let days = (0..<count).reversed().map { Fixtures.metric(key($0 + 1), sleepMin: minutes($0)) }
        return SleepNightBuilder.nights(sessions: [], days: days, habitualMidsleepSec: nil)
    }

    func testSleepAverageIdentity() throws {
        let nights = dailyNights(45) { 400 + Double($0 % 7) * 10 }
        guard case .nowOnly(let avg, let count, _) = ProgressSleep.reading(nights: nights, todayKey: today, horizon: .quarter).duration else {
            return XCTFail("45 nights within 90 days have no then-window")
        }
        XCTAssertEqual(avg, try XCTUnwrap(BaselineReadouts.sleepAverage30(nights)), accuracy: 1e-9)
        XCTAssertEqual(count, 45)

        // Then-window: the newest 30 nights on or before the cutoff.
        let long = dailyNights(150) { 380 + Double($0 % 11) * 8 }
        guard case .ready(let now, let then, let delta, _) = ProgressSleep.reading(nights: long, todayKey: today, horizon: .quarter).duration else {
            return XCTFail("expected .ready")
        }
        let cutoff = Baselines.cutoffKey(todayKey: today, carryDays: 90)
        let expectedThen = Array(long.filter { $0.dayKey <= cutoff }.prefix(30))
        XCTAssertEqual(then.newestDay, cutoff)
        XCTAssertEqual(then.nights, 30)
        XCTAssertEqual(then.avgMin, expectedThen.reduce(0) { $0 + $1.asleepMin } / 30, accuracy: 1e-9)
        XCTAssertEqual(now.avgMin, try XCTUnwrap(BaselineReadouts.sleepAverage30(long)), accuracy: 1e-9)
        XCTAssertEqual(delta, now.avgMin - then.avgMin, accuracy: 1e-9)
    }

    func testSleepComparisonGates() throws {
        // 30 recent nights and 10 nights 90–99 days ago: fewer than 14 before the cutoff.
        let recent = (0..<30).map { Fixtures.metric(key($0 + 1), sleepMin: 420) }
        let old = (90..<100).map { Fixtures.metric(key($0), sleepMin: 400) }
        let split = SleepNightBuilder.nights(sessions: [], days: old + recent, habitualMidsleepSec: nil)
        guard case .nowOnly(_, let n, let compareFrom) = ProgressSleep.reading(nights: split, todayKey: today, horizon: .quarter).duration else {
            return XCTFail("expected .nowOnly")
        }
        XCTAssertEqual(n, 40)
        XCTAssertEqual(compareFrom, Baselines.cutoffKey(todayKey: split[13].dayKey, carryDays: -90))

        // Fewer than 14 nights: no compare-from date.
        guard case .nowOnly(_, _, let none) = ProgressSleep.reading(nights: dailyNights(9) { _ in 420 }, todayKey: today, horizon: .quarter).duration else {
            return XCTFail("expected .nowOnly")
        }
        XCTAssertNil(none)

        // All time: the first 30 nights overlap the latest 30 until 60 exist.
        guard case .nowOnly(_, let n50, let cf50) = ProgressSleep.reading(nights: dailyNights(50) { _ in 420 }, todayKey: today, horizon: .all).duration else {
            return XCTFail("expected .nowOnly")
        }
        XCTAssertEqual(n50, 50)
        XCTAssertNil(cf50)

        let seventy = dailyNights(70) { $0 % 2 == 0 ? 400 : 440 }   // population SD 20 in every even-length window
        guard case .ready(let now, let then, let delta, let noise) = ProgressSleep.reading(nights: seventy, todayKey: today, horizon: .all).duration else {
            return XCTFail("expected .ready")
        }
        XCTAssertLessThan(then.newestDay, now.oldestDay)
        XCTAssertEqual(now.nights, 30)
        XCTAssertEqual(then.nights, 30)
        XCTAssertEqual(now.sdMin, 20, accuracy: 1e-9)
        XCTAssertEqual(delta, 0, accuracy: 1e-9)
        XCTAssertEqual(noise, max(5, 2 * sqrt(400.0 / 30 + 400.0 / 30)), accuracy: 1e-9)

        XCTAssertEqual(ProgressSleep.reading(nights: [], todayKey: today, horizon: .all).duration, .none)
        XCTAssertEqual(ProgressSleep.reading(nights: dailyNights(2) { _ in 420 }, todayKey: today, horizon: .all).duration, .building(nights: 2))
    }

    func testSleepSentences() {
        let now = ProgressSleep.Window(avgMin: 432, sdMin: 30, nights: 30, newestDay: key(1), oldestDay: key(30))
        let then = ProgressSleep.Window(avgMin: 414, sdMin: 30, nights: 30, newestDay: key(90), oldestDay: key(119))
        XCTAssertEqual(ProgressCopy.sleepSentence(.ready(now: now, then: then, deltaMin: 18, noiseMin: 10), horizon: .quarter),
                       "You're averaging 7h 12m asleep, 18 min more than 90 days ago.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.ready(now: now, then: then, deltaMin: -22, noiseMin: 10), horizon: .quarter),
                       "You're averaging 7h 12m asleep, 22 min less than 90 days ago.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.ready(now: now, then: then, deltaMin: 3, noiseMin: 5), horizon: .quarter),
                       "You're averaging 7h 12m asleep, about the same as 90 days ago.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.ready(now: now, then: then, deltaMin: 65, noiseMin: 5), horizon: .all),
                       "You're averaging 7h 12m asleep, 1h 05m more than your first month.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.ready(now: now, then: then, deltaMin: 2, noiseMin: 5), horizon: .all),
                       "You're averaging 7h 12m asleep, about the same as your first month.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.nowOnly(nowAvgMin: 432, nights: 40, compareFromDay: "2025-12-17"), horizon: .quarter),
                       "You're averaging 7h 12m asleep over the last 30 nights. Compare it with 90 days ago from \(ProgressCopy.date("2025-12-17")).")
        XCTAssertEqual(ProgressCopy.sleepSentence(.nowOnly(nowAvgMin: 432, nights: 9, compareFromDay: nil), horizon: .quarter),
                       "You're averaging 7h 12m asleep over the last 9 nights. Comparisons start after 14 nights.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.nowOnly(nowAvgMin: 432, nights: 41, compareFromDay: nil), horizon: .all),
                       "You're averaging 7h 12m asleep over the last 30 nights. Comparisons with your first month start after 60 nights · 41 so far.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.building(nights: 2), horizon: .quarter),
                       "Your sleep average appears after 3 nights · 2 so far.")
        XCTAssertEqual(ProgressCopy.sleepSentence(.none, horizon: .quarter), "No nights of sleep yet.")

        // The 70-night all-time reading from the gate test reads against the first month.
        let seventy = dailyNights(70) { $0 % 2 == 0 ? 400 : 440 }
        let s = ProgressCopy.sleepSentence(ProgressSleep.reading(nights: seventy, todayKey: today, horizon: .all).duration, horizon: .all)
        XCTAssertTrue(s.hasSuffix("as your first month."), s)

        XCTAssertEqual(ProgressCopy.sleepThenLabel(then), "Then · 30 nights to \(ProgressCopy.date(key(90)))")
        XCTAssertEqual(ProgressCopy.sleepNowLabel(nights: 45), "Now · last 30 nights")
        XCTAssertEqual(ProgressCopy.sleepNowLabel(nights: 14), "Now · last 14 nights")
        XCTAssertEqual(ProgressCopy.sleepFootnote(.ready(now: now, then: then, deltaMin: 18, noiseMin: 30.2)),
                       "30-night averages, the same one Today and Sleep show. Changes under about 31 min are within the average's own noise.")
        XCTAssertEqual(ProgressCopy.sleepTone(.ready(now: now, then: then, deltaMin: 18, noiseMin: 10)), .improving)
        XCTAssertEqual(ProgressCopy.sleepTone(.ready(now: now, then: then, deltaMin: 3, noiseMin: 10)), .steady)
    }

    /// `count` strap nights waking 07:00 on Feb 18, 17, 16 …; onsets alternate 23:30 the evening before
    /// and 00:30 the same morning.
    /// `count` strap nights waking on the mornings before `today` (the newest wakes on `today` − 1), newest
    /// first: bed at 23:00 + `bedOffsetMin(i)` the evening before (i = 0 the newest; an offset past 60 lands
    /// after midnight), wake at 07:00. Built from local components, so they round-trip to their day keys
    /// wherever the test runs.
    private func timedNights(_ count: Int, bedOffsetMin: (Int) -> Int = { _ in 0 }) -> [SleepNight] {
        func local(_ dayKey: String, minutes: Int) -> Date {
            let parts = dayKey.split(separator: "-").compactMap { Int($0) }
            return Fixtures.local(parts[0], parts[1], parts[2], hour: minutes / 60, minute: minutes % 60)
        }
        let sessions = (0..<count).map { i -> CachedSleepSession in
            let wakeKey = key(i + 1)
            let bedMinutes = 23 * 60 + bedOffsetMin(i)
            let bed = bedMinutes >= 1440 ? local(wakeKey, minutes: bedMinutes - 1440) : local(key(i + 2), minutes: bedMinutes)
            let wake = local(wakeKey, minutes: 7 * 60)
            return CachedSleepSession(startTs: Int(bed.timeIntervalSince1970), endTs: Int(wake.timeIntervalSince1970),
                                      efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
        }
        return SleepNightBuilder.nights(sessions: sessions, days: [], habitualMidsleepSec: nil)
    }

    func testTimingUsesTheReadout() throws {
        // Ten nights alternating 23:30 / 00:30 beds and 07:00 wakes: the circular mean is midnight, not
        // noon, and consecutive nights an hour apart score 1 − 60/1440 → 92 on the regularity index.
        let ten = timedNights(10) { $0 % 2 == 0 ? 30 : 90 }
        XCTAssertEqual(ten.count, 10)
        XCTAssertTrue(ten.allSatisfy { $0.source == .session && $0.onsetTs != nil && $0.wakeTs != nil })
        let t = try XCTUnwrap(ProgressSleep.timing(ten, for: today))
        XCTAssertLessThanOrEqual(min(t.bedMeanMin, 1440 - t.bedMeanMin), 1, "23:30 and 00:30 average to midnight")
        XCTAssertEqual(t.wakeMeanMin, 7 * 60, accuracy: 1e-6)
        XCTAssertEqual(t.regularity, 92)
        XCTAssertEqual(t.nights, 10)
        XCTAssertEqual(t.newestDay, key(1))
        XCTAssertEqual(t.oldestDay, key(10))

        // The identical numbers the Sleep tab's readout prints.
        let readout = BaselineReadouts.sleepTiming(for: today, nights: ten, window: .default)
        XCTAssertEqual(t.bedMeanMin, readout.averageBedMinutes)
        XCTAssertEqual(t.wakeMeanMin, readout.averageWakeMinutes)
        XCTAssertEqual(t.regularity, readout.regularity)

        // Daily-only nights are skipped; under three timed nights there is no window; three nights have
        // averages but only two consecutive pairs, so no index yet.
        let daily = dailyNights(5) { _ in 420 }
        XCTAssertEqual(try XCTUnwrap(ProgressSleep.timing(ten + daily, for: today)).nights, 10)
        XCTAssertNil(ProgressSleep.timing(timedNights(2), for: today))
        let three = try XCTUnwrap(ProgressSleep.timing(timedNights(3), for: today))
        XCTAssertEqual(three.nights, 3)
        XCTAssertNil(three.regularity)

        XCTAssertEqual(ProgressSleep.reading(nights: daily, todayKey: today, horizon: .quarter).regularity, .noTimedNights)
        XCTAssertEqual(ProgressSleep.reading(nights: timedNights(2), todayKey: today, horizon: .quarter).regularity, .building(timed: 2))
        guard case .nowOnly(let now, let compareFrom) = ProgressSleep.reading(nights: ten, todayKey: today, horizon: .quarter).regularity else {
            return XCTFail("expected .nowOnly")
        }
        XCTAssertEqual(now, t)
        XCTAssertEqual(compareFrom, Baselines.cutoffKey(todayKey: ten[2].dayKey, carryDays: -90))
    }

    func testTimingComparison() throws {
        // 100 nights: the newest 30 at 23:00 sharp, the rest alternating ±45 min. Over 90 days the far
        // window (the nights on or before the cutoff) scores 1 − 90/1440 → 88; now scores 100.
        let nights = timedNights(100) { $0 < 30 ? 0 : ($0 % 2 == 0 ? 45 : -45) }
        let reading = ProgressSleep.reading(nights: nights, todayKey: today, horizon: .quarter).regularity
        guard case .ready(let now, let then, let delta) = reading else { return XCTFail("expected .ready") }
        XCTAssertEqual(now.regularity, 100)
        XCTAssertEqual(then.regularity, 88)
        XCTAssertEqual(delta, 12)
        XCTAssertEqual(now.oldestDay, key(30))
        XCTAssertEqual(then.newestDay, key(90), "the newest night on or before the cutoff")
        XCTAssertLessThan(then.newestDay, now.oldestDay)
        XCTAssertEqual(ProgressCopy.timingSentence(reading, horizon: .quarter),
                       "Your sleep timing is more regular than 90 days ago: 100 of 100, up from 88.")
        XCTAssertEqual(ProgressCopy.timingTone(reading), .improving)

        // All time: the first 30 nights against the latest 30, so 60 are needed before they compare.
        guard case .ready(_, let first, _) = ProgressSleep.reading(nights: nights, todayKey: today, horizon: .all).regularity else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(first.oldestDay, key(100))
        XCTAssertEqual(first.newestDay, key(71))
        guard case .nowOnly = ProgressSleep.reading(nights: timedNights(59), todayKey: today, horizon: .all).regularity else {
            return XCTFail("59 nights: the windows overlap")
        }
        guard case .ready = ProgressSleep.reading(nights: timedNights(60), todayKey: today, horizon: .all).regularity else {
            return XCTFail("60 nights: two windows")
        }
    }

    func testTimingSentences() {
        let now = ProgressSleep.Timing(bedMeanMin: 23 * 60 + 24, wakeMeanMin: 7 * 60 + 5, regularity: 83,
                                       nights: 30, newestDay: "2026-02-17", oldestDay: "2026-01-19")
        let then = ProgressSleep.Timing(bedMeanMin: 23 * 60 + 51, wakeMeanMin: 7 * 60 + 20, regularity: 71,
                                        nights: 30, newestDay: "2025-11-20", oldestDay: "2025-10-22")
        let noIndex = ProgressSleep.Timing(bedMeanMin: now.bedMeanMin, wakeMeanMin: now.wakeMeanMin, regularity: nil,
                                           nights: 4, newestDay: "2026-02-17", oldestDay: "2026-02-13")
        let clock = BaselineReadouts.clockText(minutes: now.bedMeanMin)
        let thenClock = BaselineReadouts.clockText(minutes: then.bedMeanMin)

        XCTAssertEqual(ProgressCopy.timingSentence(.ready(now: now, then: then, delta: 12), horizon: .quarter),
                       "Your sleep timing is more regular than 90 days ago: 83 of 100, up from 71.")
        XCTAssertEqual(ProgressCopy.timingSentence(.ready(now: now, then: then, delta: -12), horizon: .all),
                       "Your sleep timing is less regular than your first month: 83 of 100, down from 95.")
        XCTAssertEqual(ProgressCopy.timingSentence(.ready(now: now, then: then, delta: 3), horizon: .quarter),
                       "Your sleep timing is about as regular as 90 days ago: 83 of 100.")
        XCTAssertEqual(ProgressCopy.timingSentence(.ready(now: now, then: then, delta: nil), horizon: .quarter),
                       "Your bedtime averages \(clock); it was \(thenClock) 90 days ago.")
        XCTAssertEqual(ProgressCopy.timingSentence(.building(timed: 2), horizon: .quarter),
                       "Bed and wake times settle after 3 strap nights · 2 so far.")
        XCTAssertEqual(ProgressCopy.timingSentence(.noTimedNights, horizon: .quarter),
                       "Bed and wake times come from nights the strap recorded. Imported nights carry totals only.")
        XCTAssertEqual(ProgressCopy.timingSentence(.nowOnly(now: now, compareFromDay: "2025-12-17"), horizon: .quarter),
                       "Your bedtime averages \(clock) and your timing scores 83 of 100 for regularity. Compare it with 90 days ago from \(ProgressCopy.date("2025-12-17")).")
        XCTAssertEqual(ProgressCopy.timingSentence(.nowOnly(now: noIndex, compareFromDay: nil), horizon: .all),
                       "Your bedtime averages \(clock); regularity scores after 6 strap nights in a row. Keep wearing the strap and the comparison arrives.")

        XCTAssertEqual(ProgressCopy.timingTone(.ready(now: now, then: then, delta: 12)), .improving)
        XCTAssertEqual(ProgressCopy.timingTone(.ready(now: now, then: then, delta: -5)), .worsening)
        XCTAssertEqual(ProgressCopy.timingTone(.ready(now: now, then: then, delta: 4)), .steady)
        XCTAssertEqual(ProgressCopy.timingTone(.ready(now: now, then: then, delta: nil)), .none)
        XCTAssertEqual(ProgressCopy.timingTone(.nowOnly(now: now, compareFromDay: nil)), .none)

        // The grid: bedtime and wake with the earlier window's clock, then the index once it exists.
        let rows = ProgressCopy.timingRows(.ready(now: now, then: then, delta: 12))
        XCTAssertEqual(rows.map(\.label), ["Bedtime", "Wake", "Regularity"])
        XCTAssertEqual(rows[0].value, clock)
        XCTAssertEqual(rows[0].was, "was \(thenClock)")
        XCTAssertEqual(rows[0].spoken, "Bedtime usually \(clock); was \(thenClock).")
        XCTAssertEqual(rows[2].value, "83 of 100")
        XCTAssertEqual(rows[2].was, "was 71")
        XCTAssertEqual(rows[2].spoken, "Regularity 83 of 100; was 71.")
        let alone = ProgressCopy.timingRows(.nowOnly(now: noIndex, compareFromDay: nil))
        XCTAssertEqual(alone.map(\.label), ["Bedtime", "Wake"])
        XCTAssertNil(alone[0].was)
        XCTAssertEqual(alone[1].spoken, "Wake usually \(BaselineReadouts.clockText(minutes: now.wakeMeanMin)).")
        XCTAssertTrue(ProgressCopy.timingRows(.building(timed: 2)).isEmpty)
        XCTAssertTrue(ProgressCopy.timingRows(.noTimedNights).isEmpty)
    }

    // MARK: - Fitness

    private let profile = ProgressProfile(age: 38, sex: "male")

    /// Nights `range` days ago with resting HR `rhr` and an Effort of 40, oldest first.
    private func rhrNights(_ range: ClosedRange<Int>, rhr: Int) -> [DailyMetric] {
        range.reversed().map { Fixtures.metric(key($0), rhr: rhr, strain: 40) }
    }

    func testFitnessGates() {
        XCTAssertEqual(ProgressFitness.build(days: [], todayKey: today, horizon: .quarter, profile: profile), .empty)
        XCTAssertEqual(ProgressFitness.build(days: [Fixtures.metric(key(1), hrv: 60)], todayKey: today, horizon: .quarter, profile: profile),
                       .empty, "HRV alone is not resting HR")
        let two = rhrNights(1...2, rhr: 50)
        XCTAssertEqual(ProgressFitness.build(days: two, todayKey: today, horizon: .quarter, profile: .none), .needsProfile)
        XCTAssertEqual(ProgressFitness.build(days: two, todayKey: today, horizon: .quarter, profile: ProgressProfile(age: 38, sex: "")),
                       .needsProfile)
        XCTAssertEqual(ProgressFitness.build(days: two, todayKey: today, horizon: .quarter, profile: profile), .calibrating(rhrNights: 2))

        // Four nights in the week ending today: the first estimate, and the day its comparison arrives.
        let four = rhrNights(1...4, rhr: 50)
        guard case .settling(let firstWeek, let compareFrom, let points) =
                ProgressFitness.build(days: four, todayKey: today, horizon: .quarter, profile: profile) else {
            return XCTFail("expected .settling")
        }
        XCTAssertEqual(firstWeek, today)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].rhrNights, 4)
        XCTAssertTrue(points[0].fallback, "no waist: VO2 max from the HR ratio")
        XCTAssertEqual(compareFrom, Baselines.cutoffKey(todayKey: today, carryDays: -90))

        // A row after today is ignored; a waist switches to the Nes estimate.
        let tomorrow = Fixtures.metric(Fixtures.key(today, minus: -1), rhr: 50)
        XCTAssertEqual(ProgressFitness.points(days: four + [tomorrow], todayKey: today, profile: profile).count, 1)
        let waist = ProgressProfile(age: 38, sex: "male", waistCm: 85)
        XCTAssertEqual(ProgressFitness.points(days: four, todayKey: today, profile: waist).first?.fallback, false)
    }

    /// The app-level wiring: `ProfileStore` seeds age 30 / "male" (and 178 cm / 75 kg) when nothing was
    /// ever entered, so `ProgressProfile.lifted` must pass nil age and sex until Settings › Profile's
    /// `baseline.profileSet` flag is true, and the Fitness card must land on `.needsProfile` with those
    /// seeded values, however many nights of resting HR exist. Once entered, the same fields score.
    func testProfileLiftedNeedsTheEnteredFlag() {
        let seeded = ProgressProfile.lifted(age: 30, sex: "male", waistCm: 0, heightCm: 178, weightKg: 75, entered: false)
        XCTAssertEqual(seeded, ProgressProfile(age: nil, sex: nil, waistCm: nil, hasHeightWeight: true),
                       "the store's defaults are not a profile until the flag says so; body fields pass through")
        let week = rhrNights(1...7, rhr: 50)
        XCTAssertEqual(ProgressFitness.build(days: week, todayKey: today, horizon: .quarter, profile: seeded), .needsProfile)
        XCTAssertTrue(ProgressFitness.points(days: week, todayKey: today, profile: seeded).isEmpty)

        let entered = ProgressProfile.lifted(age: 30, sex: "male", waistCm: 85, heightCm: 178, weightKg: 75, entered: true)
        XCTAssertEqual(entered, ProgressProfile(age: 30, sex: "male", waistCm: 85, hasHeightWeight: true))
        let status = ProgressFitness.build(days: week, todayKey: today, horizon: .quarter, profile: entered)
        XCTAssertNotEqual(status, .needsProfile)
        XCTAssertEqual(status.now?.chronoAge, 30)
        XCTAssertEqual(status.now?.fallback, false, "a waist switches to the Nes estimate")
        XCTAssertNil(ProgressProfile.lifted(age: 30, sex: "male", waistCm: 0, heightCm: 0, weightKg: 75, entered: true).waistCm)
        XCTAssertFalse(ProgressProfile.lifted(age: 30, sex: "male", waistCm: 0, heightCm: 0, weightKg: 75, entered: true).hasHeightWeight)
    }

    func testFitnessPointsWeekly() throws {
        // 120 nights: weeks ending today, today − 7, … while a week still has four nights of resting HR.
        let days = rhrNights(1...120, rhr: 50)
        let points = ProgressFitness.points(days: days, todayKey: today, profile: profile)
        XCTAssertEqual(points.count, 17, "today − 0 … today − 112 carry 6–7 nights; today − 119 carries two")
        XCTAssertEqual(points.last?.weekEnding, today)
        XCTAssertEqual(points.first?.weekEnding, key(112))
        XCTAssertEqual(points.map(\.weekEnding), points.map(\.weekEnding).sorted(), "oldest → newest")
        XCTAssertEqual(points.last?.rhrNights, 6)
        XCTAssertEqual(points[points.count - 2].rhrNights, 7)

        // Each point is NOOP's own weekly read of those rows.
        let readout = try XCTUnwrap(BaselineReadouts.fitness(for: today, days: Array(days.suffix(6)), age: 38, sex: "male"))
        XCTAssertEqual(points.last?.vo2max, readout.vo2max)
        XCTAssertEqual(points.last?.fitnessAge, readout.result.fitnessAge)
        XCTAssertEqual(points.last?.chronoAge, 38)
        for p in points { XCTAssertEqual(p.vo2max, try XCTUnwrap(readout.vo2max), accuracy: 1e-9, "same inputs, same number") }
        XCTAssertEqual(points[0].trajectory.sigma, ProgressFitness.bandVO2)
        XCTAssertEqual(points[0].trajectory.baseline, points[0].vo2max)
    }

    func testFitnessLadder() throws {
        // Older nights at 60 bpm, the latest 60 at 50: the estimate rises. Over a quarter the anchor is
        // the newest week on or before the cutoff.
        let days = rhrNights(61...120, rhr: 60) + rhrNights(1...60, rhr: 50)
        let s = ProgressFitness.build(days: days, todayKey: today, horizon: .quarter, profile: profile)
        guard case .ready(let c, let points) = s else { return XCTFail("expected .ready") }
        XCTAssertEqual(points.count, 17)
        XCTAssertEqual(c.now.weekEnding, today)
        XCTAssertEqual(c.then.weekEnding, key(91))
        XCTAssertFalse(c.namesDate)
        XCTAssertGreaterThan(c.delta, ProgressFitness.steadyVO2)
        XCTAssertFalse(c.steady)
        let sentence = try XCTUnwrap(ProgressCopy.fitnessSentence(s, horizon: .quarter))
        XCTAssertTrue(sentence.hasPrefix("Your estimated VO2 max is about "), sentence)
        XCTAssertTrue(sentence.hasSuffix(" mL/kg/min higher than 90 days ago."), sentence)
        XCTAssertEqual(ProgressCopy.fitnessTone(s), .improving)
        XCTAssertEqual(s.now, c.now)

        // The chart window runs from the anchor to now.
        let window = ProgressFitness.window(s, todayKey: today, horizon: .quarter)
        XCTAssertEqual(window.first?.weekEnding, key(91))
        XCTAssertEqual(window.count, 14)
        XCTAssertEqual(ProgressFitness.window(s, todayKey: today, horizon: .all).count, 17)

        // Steady: the same resting HR throughout.
        let flat = ProgressFitness.build(days: rhrNights(1...120, rhr: 50), todayKey: today, horizon: .quarter, profile: profile)
        XCTAssertEqual(ProgressCopy.fitnessSentence(flat, horizon: .quarter), "Your estimated VO2 max is about where it was 90 days ago.")
        XCTAssertEqual(ProgressCopy.fitnessTone(flat), .steady)

        // All time: the first week against the latest; the sentence names the week it landed.
        let all = ProgressFitness.build(days: days, todayKey: today, horizon: .all, profile: profile)
        guard case .ready(let ca, _) = all else { return XCTFail("expected .ready") }
        XCTAssertEqual(ca.then.weekEnding, key(112))
        XCTAssertTrue(ca.namesDate)
        XCTAssertEqual(ProgressCopy.fitnessSentence(all, horizon: .all)?.hasSuffix("higher than when it settled on \(ProgressCopy.date(key(112)))."), true)

        // A year: no anchor yet, so settling, naming the day the comparison arrives.
        guard case .settling(let first, let compareFrom, _) = ProgressFitness.build(days: days, todayKey: today, horizon: .year, profile: profile) else {
            return XCTFail("expected .settling")
        }
        XCTAssertEqual(first, key(112))
        XCTAssertEqual(compareFrom, Baselines.cutoffKey(todayKey: key(112), carryDays: -365))

        // Paused: the newest estimate is older than the stale window.
        let gap = ProgressFitness.build(days: rhrNights(21...120, rhr: 50), todayKey: today, horizon: .quarter, profile: profile)
        guard case .paused(let lastWeek, _) = gap else { return XCTFail("expected .paused") }
        XCTAssertEqual(lastWeek, key(21))
        XCTAssertEqual(ProgressCopy.fitnessSentence(gap, horizon: .quarter),
                       "No fitness estimate since the week to \(ProgressCopy.date(key(21))). It resumes with 4 nights of resting HR in a week.")
        XCTAssertEqual(ProgressCopy.fitnessTone(gap), .none)
        XCTAssertEqual(gap.now?.weekEnding, key(21))
    }

    func testFitnessCopy() throws {
        let now = ProgressFitness.Point(id: "2026-02-18", date: try XCTUnwrap(TrendsDayKey.date("2026-02-18")), vo2max: 42.4,
                                        fitnessAge: 33.6, chronoAge: 38, rhrNights: 6, fallback: true)
        let then = ProgressFitness.Point(id: "2025-11-19", date: try XCTUnwrap(TrendsDayKey.date("2025-11-19")), vo2max: 40.1,
                                         fitnessAge: 35.2, chronoAge: 38, rhrNights: 7, fallback: false)
        XCTAssertEqual(ProgressCopy.fitnessAgeCaption(now),
                       "Fitness age 34 (±5 years) at 38. VO2 max from resting HR and age alone; a waist in Settings › Profile sharpens it.")
        XCTAssertEqual(ProgressCopy.fitnessAgeCaption(then),
                       "Fitness age 35 (±5 years) at 38. VO2 max from resting HR, weekly effort and waist, with the age and sex in Settings › Profile.")
        XCTAssertEqual(ProgressCopy.fitnessNowLabel(now), "Now · week to \(ProgressCopy.date("2026-02-18"))")
        let c = ProgressFitness.Comparison(then: then, now: now, namesDate: false)
        XCTAssertEqual(ProgressCopy.fitnessThenLabel(c), "Then · week to \(ProgressCopy.date("2025-11-19"))")
        XCTAssertTrue(c.steady, "2.3 is under the 3 mL/kg/min floor")
        XCTAssertEqual(ProgressCopy.fitnessSentence(.ready(comparison: c, points: [then, now]), horizon: .quarter),
                       "Your estimated VO2 max is about where it was 90 days ago.")
        let lower = ProgressFitness.Comparison(then: now, now: then, namesDate: true)
        XCTAssertFalse(ProgressFitness.Comparison(then: then, now: ProgressFitness.Point(id: now.id, date: now.date, vo2max: 44, fitnessAge: 33,
                                                                                         chronoAge: 38, rhrNights: 6, fallback: true),
                                                  namesDate: false).steady)
        XCTAssertEqual(ProgressCopy.fitnessSentence(.ready(comparison: lower, points: []), horizon: .quarter),
                       "Your estimated VO2 max is about where it was on \(ProgressCopy.date("2026-02-18")).")
        XCTAssertEqual(ProgressCopy.fitnessSentence(.calibrating(rhrNights: 2), horizon: .quarter),
                       "Your fitness estimate needs 4 nights of resting HR in a week · 2 this week.")
        XCTAssertEqual(ProgressCopy.fitnessSentence(.needsProfile, horizon: .quarter),
                       "Add your date of birth and sex in Settings › Profile for an estimated VO2 max and fitness age.")
        XCTAssertEqual(ProgressCopy.fitnessSentence(.settling(firstWeek: "2026-02-04", compareFromDay: "2026-05-05", points: []), horizon: .quarter),
                       "Your first fitness estimate landed the week to \(ProgressCopy.date("2026-02-04")). Compare it with 90 days ago from \(ProgressCopy.date("2026-05-05")).")
        XCTAssertEqual(ProgressCopy.fitnessSentence(.settling(firstWeek: "2026-02-04", compareFromDay: nil, points: []), horizon: .all),
                       "Your first fitness estimate landed the week to \(ProgressCopy.date("2026-02-04")). Keep wearing the strap and this line grows.")
        XCTAssertNil(ProgressCopy.fitnessSentence(.empty, horizon: .quarter))
        XCTAssertEqual(ProgressCopy.fitnessTone(.calibrating(rhrNights: 2)), .none)
    }

    // MARK: - Misc

    func testHorizonAndPicker() {
        XCTAssertEqual(ProgressHorizon.resolve(12), .quarter)
        XCTAssertEqual(ProgressHorizon.resolve(0), .all)
        XCTAssertEqual(ProgressHorizon.resolve(365), .year)
        XCTAssertEqual(ProgressHorizon.allCases.map(\.label), ["90D", "180D", "1Y", "All"])
        XCTAssertEqual(ProgressHorizon.allCases.map(\.subtitle), ["Last 90 days", "Last 180 days", "Last year", "All time"])
        XCTAssertEqual(ProgressHorizon.allCases.map(\.agoPhrase), ["90 days ago", "180 days ago", "a year ago", nil])
        XCTAssertEqual(ProgressHorizon.allCases.map(\.days), [90, 180, 365, nil])

        // TrendsRange is a BaselineRangeOption, so the Trends picker is the shared `BaselineRangePicker`.
        func label<O: BaselineRangeOption>(_ o: O) -> String { o.label }
        XCTAssertEqual(label(TrendsRange.week), "7D")
        XCTAssertEqual(label(ProgressHorizon.half), "180D")
    }

    func testYDomainWrapping() {
        // Baselines 55…62 ms with sigma 6.265: band 48.7…68.3, padded 12% of 19.5 → 46.4…70.6, snapped
        // outward to 5 ms steps.
        let window = (0...7).map { i in point(key(8 - i), baseline: 55 + Double(i), sigma: 6.265) }
        let domain = ProgressMetric.yDomain(window: window, step: 5)
        XCTAssertEqual(domain, 45...75)
        let band = window.map { BandPoint(id: $0.id, date: $0.date, value: $0.baseline, baseline: nil,
                                          low: $0.baseline - $0.sigma, high: $0.baseline + $0.sigma) }
        XCTAssertEqual(domain, TrendsSeries.yDomain(points: band, step: 5), "reuses the tested Trends rule")
        XCTAssertEqual(ProgressMetric.yDomain(window: [], step: 5), 0...5)
    }

    func testChartWindow() throws {
        let status = hrvStatus(priorNights(200, hrv: 60), .quarter)
        let window = ProgressMetric.window(status, todayKey: today, horizon: .quarter)
        XCTAssertEqual(window.first?.day, key(90), "the window starts at the anchor")
        XCTAssertEqual(window.last?.day, key(1))
        XCTAssertEqual(ProgressMetric.window(status, todayKey: today, horizon: .all).count, 200 - 14)
        XCTAssertFalse(ProgressMetric.spansOverAYear(window))

        // Settling: every trusted point is newer than the cutoff, so all six are in the window.
        let settling = hrvStatus(priorNights(20, hrv: 60), .quarter)
        XCTAssertEqual(ProgressMetric.window(settling, todayKey: today, horizon: .quarter).count, 6)

        // A single point newer than the cutoff is fewer than two: every trusted point is drawn instead.
        let lone = ProgressMetricStatus.settling(firstTrustedDay: key(1), compareFromDay: nil,
                                                 points: [point(key(200), baseline: 60), point(key(150), baseline: 61), point(key(1), baseline: 62)])
        XCTAssertEqual(ProgressMetric.window(lone, todayKey: today, horizon: .quarter).count, 3)
    }

    func testEmptyStore() {
        let snap = ProgressSnapshot.build(days: [], nights: [], horizon: .quarter, todayKey: today)
        XCTAssertEqual(snap.totalNights, 0)
        XCTAssertEqual(snap.hrv, .empty)
        XCTAssertEqual(snap.restingHr, .empty)
        XCTAssertEqual(snap.sleep.duration, .none)
        XCTAssertEqual(snap.sleep.regularity, .noTimedNights)
        XCTAssertEqual(snap.fitness, .empty)
        XCTAssertNil(snap.recalibratedOn)

        let one = ProgressSnapshot.build(days: [Fixtures.metric(key(1), sleepMin: 420)], nights: [], horizon: .quarter, todayKey: today)
        XCTAssertEqual(one.totalNights, 1)
        XCTAssertEqual(one.hrv, .empty)
    }
}
