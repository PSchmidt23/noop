import XCTest
import SwiftUI
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// The second half of `BaselineReadouts` (`BaselineReadoutsMetrics.swift`): the Readiness score read
/// from the funnel with NOOP's bands and a drivers sentence in Baseline's vocabulary, the windowed
/// averages behind Steps and Calories, the Stress day readout over a `DaytimeStress.Result`, sleep
/// timing (circular averages, the regularity index, the target window), the fitness readout and the
/// `MetricAccuracy` table. Day keys are literals; the windows are UTC key math.
final class BaselineReadoutsMetricsTests: BaselineEngineTestCase {

    private let today = "2026-02-18"
    private let forbidden = ["strain", "recovery", "coach"]

    private func key(_ back: Int) -> String { Fixtures.key(today, minus: back) }

    /// A full strap night: HRV, resting HR, a scored night and the sleep block the Rest composite needs.
    private func night(_ day: String, hrv: Double, rhr: Int, recovery: Double?, resp: Double? = 15,
                       sleep: Double? = 430, strain: Double? = nil, kcal: Double? = nil, steps: Int? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: sleep == nil ? nil : 0.9,
                    deepMin: sleep == nil ? nil : 90, remMin: sleep == nil ? nil : 100, lightMin: sleep == nil ? nil : 240,
                    disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: recovery, strain: strain,
                    exerciseCount: nil, respRateBpm: resp, steps: steps, activeKcalEst: kcal)
    }

    // MARK: Readiness

    func testReadinessTone_cutsAtNoopsBands_andTheWordMatchesTheColour() {
        // The cuts are the engine's own constants, never literals of ours, so a change upstream moves the
        // tone and everything drawn from it together.
        let red = RecoveryScorer.bandRedMax, yellow = RecoveryScorer.bandYellowMax
        XCTAssertEqual(BaselineReadouts.readinessTone(red - 0.1), .low)
        XCTAssertEqual(BaselineReadouts.readinessTone(red), .watch)
        XCTAssertEqual(BaselineReadouts.readinessTone(yellow - 0.1), .watch)
        XCTAssertEqual(BaselineReadouts.readinessTone(yellow), .good)
        XCTAssertEqual(BaselineReadouts.readinessTone(100), .good)
        // One signal per tone: the watch tone is drawn in the watch colour, so its word is "Fair", never
        // a reassurance like "Steady".
        XCTAssertEqual(ReadinessTone.good.label, "Good")
        XCTAssertEqual(ReadinessTone.watch.label, "Fair")
        XCTAssertEqual(ReadinessTone.low.label, "Low")
        for tone in [ReadinessTone.good, .watch, .low] {
            for word in forbidden { XCTAssertFalse(tone.label.lowercased().contains(word), tone.label) }
        }
    }

    func testReadinessScore_nilWithoutAStoredScore_thenReadsItWithDriversAndConfidence() throws {
        // Ten calm nights, then a morning with HRV up and resting HR up against them. No sleep block, so
        // the only terms are HRV (+), resting HR (−) and respiration (at baseline, 0 points).
        var days = (1...10).reversed().map { night(key($0), hrv: 60, rhr: 50, recovery: 60, sleep: nil) }
        XCTAssertNil(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0), "no row for today yet")
        days.append(night(today, hrv: 72, rhr: 55, recovery: nil, sleep: nil))
        XCTAssertNil(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0), "no score on the row")
        XCTAssertNil(BaselineReadouts.readinessCalibrationNights(for: today, days: days, epoch: 0),
                     "past the seed gate: a missing score is some other gap, never 'calibrating'")

        days[days.count - 1] = night(today, hrv: 72, rhr: 55, recovery: 71, sleep: nil)
        let r = try XCTUnwrap(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0))
        XCTAssertEqual(r.day, today)
        XCTAssertEqual(r.score, 71)
        XCTAssertEqual(r.scoreText, "71")
        XCTAssertEqual(r.tone, .good)
        XCTAssertEqual(r.confidence, .building, "ten prior nights: usable, not yet trusted (14)")
        XCTAssertFalse(r.drivers.isEmpty)
        let sentence = try XCTUnwrap(r.driversSentence)
        XCTAssertTrue(sentence.hasPrefix("Lifted by heart rate variability (+"), sentence)
        XCTAssertTrue(sentence.contains("held back by resting heart rate (\u{2212}"), sentence)
        XCTAssertTrue(sentence.hasSuffix(")."), sentence)
        for word in forbidden { XCTAssertFalse(sentence.lowercased().contains(word), sentence) }
        // The engine's verdict text is never copied through.
        XCTAssertFalse(sentence.contains("baseline"), sentence)
    }

    func testReadinessScore_importedDayWithoutUsableBaselineKeepsTheNumberAndDropsTheDrivers() throws {
        // Two prior nights only: the HRV baseline is not usable, so there is nothing to break down, but
        // the export's own score still prints.
        let days = [night(key(2), hrv: 60, rhr: 50, recovery: 55), night(key(1), hrv: 61, rhr: 51, recovery: 58),
                    night(today, hrv: 40, rhr: 58, recovery: 22)]
        let r = try XCTUnwrap(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0))
        XCTAssertEqual(r.tone, .low)
        XCTAssertTrue(r.drivers.isEmpty)
        XCTAssertNil(r.driversSentence)
        XCTAssertEqual(r.confidence, .calibrating)
    }

    func testReadinessScore_anImportedScoreKeepsItsNumberAndGetsNoDrivers() throws {
        // Ten strap-scored nights, then a morning the export scored (90) and the strap did not.
        var days = (1...10).reversed().map { night(key($0), hrv: 60, rhr: 50, recovery: 60, sleep: nil) }
        days.append(night(today, hrv: 72, rhr: 55, recovery: 90, sleep: nil))
        let rows = days.map { SourcedDailyMetric(metric: $0, source: $0.day == today ? .whoopImport : .noopComputed) }
        let strap = try XCTUnwrap(BaselineReadouts.strapScores(rows))
        XCTAssertEqual(strap.count, 10)
        XCTAssertNil(strap[today], "the strap scored nothing for this morning")

        let imported = try XCTUnwrap(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0, strapScores: strap))
        XCTAssertEqual(imported.score, 90, "the export's number is the number shown")
        XCTAssertTrue(imported.drivers.isEmpty, "NOOP's driver points explain nothing about an export's score")
        XCTAssertNil(imported.driversSentence)
        XCTAssertEqual(imported.confidence, .building, "the caption's baseline is still the strap's ten nights")

        // The strap's own score (the same number under strap-first) keeps its drivers; a strap that scored
        // the morning differently from the number shown (an export winning under merged) does not.
        let own = try XCTUnwrap(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0, strapScores: [today: 90]))
        XCTAssertFalse(own.drivers.isEmpty)
        let shadowed = try XCTUnwrap(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0, strapScores: [today: 61]))
        XCTAssertTrue(shadowed.drivers.isEmpty)
        // No per-source rows (a preview, or `days` assigned directly): every score is taken as the strap's.
        XCTAssertNil(BaselineReadouts.strapScores([]))
        XCTAssertFalse(try XCTUnwrap(BaselineReadouts.readinessScore(for: today, days: days, epoch: 0)).drivers.isEmpty)
    }

    func testReadinessCalibrationNights_countsValidHrvNightsUnderTheSeed() {
        let days = [night(key(2), hrv: 60, rhr: 50, recovery: nil), night(key(1), hrv: 61, rhr: 51, recovery: nil),
                    night(today, hrv: 59, rhr: 50, recovery: nil)]
        XCTAssertEqual(BaselineReadouts.readinessCalibrationNights(for: today, days: days, epoch: 0), 3)
        XCTAssertEqual(BaselineReadouts.readinessSeedNights, Baselines.minNightsSeed)
        XCTAssertEqual(BaselineReadouts.readinessCalibrationNights(for: today, days: [], epoch: 0), 0,
                       "a brand-new history reads 0 of 4, not nothing")
    }

    func testDriversSentence_singleMoverAndNoMovers() {
        let up = ChargeDriver(label: "Sleep quality", deltaPoints: 4, valueText: "", baselineText: "", verdict: "x")
        let flat = ChargeDriver(label: "Respiratory rate", deltaPoints: 0, valueText: "", baselineText: "", verdict: "x")
        XCTAssertEqual(BaselineReadouts.driversSentence([flat, up]), "Lifted by sleep quality (+4).")
        XCTAssertEqual(BaselineReadouts.driversSentence([ChargeDriver(label: "Skin temperature", deltaPoints: -2,
                                                                      valueText: "", baselineText: "", verdict: "x")]),
                       "Held back by skin temperature (\u{2212}2).")
        XCTAssertNil(BaselineReadouts.driversSentence([flat]))
        XCTAssertNil(BaselineReadouts.driversSentence([]))
    }

    // MARK: Windowed averages

    func testWindowAverage_excludesTheDayItselfAndDaysOutsideTheWindow_andNeedsThreeObserved() {
        let readings: [(day: String, value: Double)] = [
            (key(8), 1_000),    // outside a 7-day window
            (key(7), 7_000), (key(5), 8_000), (key(1), 9_000),
            (today, 50_000),    // the day itself never sits inside its own average
        ]
        let a7 = BaselineReadouts.windowAverage(before: today, window: 7, readings: readings)
        XCTAssertEqual(a7.observed, 3)
        XCTAssertEqual(try XCTUnwrap(a7.mean), 8_000, accuracy: 1e-9)
        let a30 = BaselineReadouts.windowAverage(before: today, window: 30, readings: readings)
        XCTAssertEqual(a30.observed, 4)
        XCTAssertEqual(try XCTUnwrap(a30.mean), 6_250, accuracy: 1e-9)

        let thin = BaselineReadouts.windowAverage(before: today, window: 7, readings: Array(readings.prefix(3)))
        XCTAssertNil(thin.mean, "two recorded days: no average yet")
        XCTAssertEqual(thin.observed, 2)
        XCTAssertEqual(BaselineReadouts.averageMinDays, 3)
    }

    // MARK: Steps

    func testSteps_readoutAndSparkline() throws {
        var readings: [(day: String, value: Double)] = (1...30).map { (day: key($0), value: 6_000) }
        readings.append((day: today, value: 8_412))
        readings.removeAll { $0.day == key(3) }   // a day the strap was off
        let s = BaselineReadouts.steps(for: today, readings: readings)
        XCTAssertEqual(s.steps, 8_412)
        XCTAssertEqual(try XCTUnwrap(s.average7), 6_000, accuracy: 1e-9)
        XCTAssertEqual(s.observed7, 6)
        XCTAssertEqual(s.observed30, 29)
        XCTAssertEqual(s.recent.count, 7)
        XCTAssertEqual(s.recent.map(\.day), (0...6).reversed().map { key($0) }, "oldest → newest, ending today")
        XCTAssertNil(s.recent[3].value, "the missing day is an empty bar, not a zero")
        XCTAssertEqual(s.recent.last?.value, 8_412)
        XCTAssertEqual(try XCTUnwrap(s.delta(against: s.average7)), 2_412, accuracy: 1e-9)

        XCTAssertEqual(BaselineReadouts.stepsText(8_412), "8,412")
        XCTAssertEqual(BaselineReadouts.stepsText(nil), "–")
        XCTAssertEqual(BaselineReadouts.stepsDeltaText(steps: 8_412, average: 6_000, windowLabel: "7-day"),
                       "+2,412 vs your 7-day average")
        XCTAssertEqual(BaselineReadouts.stepsDeltaText(steps: 5_000, average: 6_000, windowLabel: "30-day"),
                       "\u{2212}1,000 vs your 30-day average")
        XCTAssertEqual(BaselineReadouts.stepsDeltaText(steps: 6_200, average: 6_000, windowLabel: "7-day"),
                       "On your 7-day average", "inside 5% either way")
        XCTAssertNil(BaselineReadouts.stepsDeltaText(steps: nil, average: 6_000, windowLabel: "7-day"))
        XCTAssertNil(BaselineReadouts.stepsDeltaText(steps: 6_000, average: nil, windowLabel: "7-day"))

        let empty = BaselineReadouts.steps(for: today, readings: [])
        XCTAssertNil(empty.steps)
        XCTAssertNil(empty.average7)
        XCTAssertEqual(empty.recent.count, 7)
    }

    func testStepReadings_importsOnlyDropsTheStrapsComputedPoints() {
        // NOOP's Apple-preferred resolver appends the strap's computed steps ("<deviceId>-noop") after the
        // phone's sources; "Imports only" promises the strap's rows are gone, so those points are dropped.
        let point = { (day: String, value: Double, source: String) in
            ResolvedMetricPoint(day: day, value: value, source: source, sourceKey: "steps")
        }
        let resolved = [point(key(3), 4_000, Repository.appleHealthSource),
                        point(key(2), 9_000, "whoop-abc-noop"),
                        point(key(1), 5_000, Repository.healthConnectSource),
                        point(today, 7_000, "whoop-abc-noop")]
        let funnel: [(day: String, value: Double)] = [(key(5), 3_000), (today, 1_000), (key(40), 2_000)]
        let imports = BaselineReadouts.stepReadings(mode: .importOnly, resolved: resolved, funnel: funnel,
                                                    from: key(30), to: today)
        XCTAssertEqual(imports.map(\.day), [key(5), key(3), key(1), today])
        XCTAssertEqual(imports.map(\.value), [3_000, 4_000, 5_000, 1_000],
                       "the strap's counts are gone; the funnel's import-only column fills today and the day the resolver lacks")
        XCTAssertFalse(imports.contains { $0.day == key(2) })
        XCTAssertFalse(imports.contains { $0.day == key(40) }, "outside the window")

        // Strap-first keeps every resolved point verbatim (the resolver already ranked the sources).
        let strapFirst = BaselineReadouts.stepReadings(mode: .strapFirst, resolved: resolved, funnel: funnel,
                                                       from: key(30), to: today)
        XCTAssertEqual(strapFirst.map(\.value), [3_000, 4_000, 9_000, 5_000, 7_000])
        XCTAssertEqual(BaselineReadouts.importedStepSources, [Repository.appleHealthSource, Repository.healthConnectSource])
    }

    func testStepsTile_todayWithholdsTheJudgement_andVoiceOverHearsTheAverage() {
        // A completed day is judged against the average; today is a running count and is not.
        XCTAssertEqual(StepsTile.title(isToday: false), "Steps")
        XCTAssertEqual(StepsTile.title(isToday: true), "Steps so far")
        XCTAssertEqual(StepsTile.context(steps: 1_800, average: 7_000, averageLabel: "7-day", daysUntilAverage: nil, isToday: false),
                       "\u{2212}5,200 vs your 7-day average")
        XCTAssertEqual(StepsTile.context(steps: 1_800, average: 7_000, averageLabel: "7-day", daysUntilAverage: nil, isToday: true),
                       "Builds through the day")
        XCTAssertEqual(StepsTile.context(steps: 1_800, average: nil, averageLabel: "7-day", daysUntilAverage: 2, isToday: true),
                       "Builds through the day · 7-day average after 2 more days")
        XCTAssertEqual(StepsTile.context(steps: 1_800, average: nil, averageLabel: "7-day", daysUntilAverage: 1, isToday: false),
                       "7-day average after 1 more day")
        XCTAssertEqual(StepsTile.context(steps: nil, average: 7_000, averageLabel: "7-day", daysUntilAverage: nil, isToday: true),
                       "No steps recorded yet")
        XCTAssertEqual(StepsTile.context(steps: nil, average: 7_000, averageLabel: "7-day", daysUntilAverage: nil, isToday: false),
                       "No steps recorded")

        XCTAssertEqual(StepsTile.tone(steps: 1_800, average: 7_000, isToday: false), BaselineTheme.watch, "a quarter under, on a completed day")
        XCTAssertEqual(StepsTile.tone(steps: 1_800, average: 7_000, isToday: true), BaselineTheme.steps, "a partial count earns no judgement")
        XCTAssertEqual(StepsTile.tone(steps: 8_000, average: 7_000, isToday: false), BaselineTheme.good)
        XCTAssertEqual(StepsTile.tone(steps: 8_000, average: 7_000, isToday: true), BaselineTheme.steps)
        XCTAssertEqual(StepsTile.tone(steps: 6_900, average: 7_000, isToday: false), BaselineTheme.steps)
        XCTAssertEqual(StepsTile.tone(steps: nil, average: 7_000, isToday: false), BaselineTheme.textTertiary)

        // VoiceOver hears the "avg" caption, not only the delta.
        XCTAssertEqual(StepsTile.accessibilityLabel(numeral: "8,412", average: 6_000, averageLabel: "7-day",
                                                    context: "+2,412 vs your 7-day average"),
                       "8,412 steps, 7-day average 6,000, +2,412 vs your 7-day average")
        XCTAssertEqual(StepsTile.accessibilityLabel(numeral: "1,800", average: nil, averageLabel: "7-day",
                                                    context: "Builds through the day"),
                       "1,800 steps, Builds through the day")
    }

    // MARK: Calories

    func testCalories_readoutAndRoundedText() throws {
        var days = (1...30).reversed().map { night(key($0), hrv: 60, rhr: 50, recovery: 60, kcal: 2_000) }
        days.append(night(today, hrv: 60, rhr: 50, recovery: 60, kcal: 2_143))
        let c = BaselineReadouts.calories(for: today, days: days)
        XCTAssertEqual(c.kcal, 2_143)
        XCTAssertEqual(try XCTUnwrap(c.average30), 2_000, accuracy: 1e-9)
        XCTAssertEqual(c.observed30, 30)
        XCTAssertEqual(try XCTUnwrap(c.delta), 143, accuracy: 1e-9)

        XCTAssertEqual(BaselineReadouts.caloriesText(2_143), "2,140", "never to the kcal")
        XCTAssertEqual(BaselineReadouts.caloriesText(2_145), "2,150")
        XCTAssertEqual(BaselineReadouts.caloriesText(nil), "–")
        XCTAssertEqual(BaselineReadouts.caloriesDeltaText(kcal: 2_143, average: 2_000), "+140 vs your 30\u{2011}day average")
        XCTAssertEqual(BaselineReadouts.caloriesDeltaText(kcal: 1_700, average: 2_000), "\u{2212}300 vs your 30\u{2011}day average")
        XCTAssertEqual(BaselineReadouts.caloriesDeltaText(kcal: 2_050, average: 2_000), "On your 30\u{2011}day average")

        let none = BaselineReadouts.calories(for: today, days: [night(today, hrv: 60, rhr: 50, recovery: 60)])
        XCTAssertNil(none.kcal)
        XCTAssertNil(none.average30)
    }

    func testCalories_beforeTheRolloverReadTheSameRowAsEffort() throws {
        // 01:30 on `today`: NOOP's logical day is still yesterday. Yesterday's row carries the figure of the
        // day being lived; today's row has no banked night yet, so Calories follows the Effort cell to
        // yesterday's row and the 30-day average is taken before yesterday.
        var days = (2...31).reversed().map { night(key($0), hrv: 60, rhr: 50, recovery: 60, kcal: 2_000) }
        days.append(night(key(1), hrv: 60, rhr: 50, recovery: 60, kcal: 2_300))
        days.append(night(today, hrv: 60, rhr: 50, recovery: nil, sleep: nil))
        let early = BaselineReadouts.calories(for: today, days: days, logicalKey: key(1))
        XCTAssertEqual(early.kcal, 2_300)
        XCTAssertEqual(try XCTUnwrap(early.average30), 2_000, accuracy: 1e-9, "the 30 days before yesterday")
        XCTAssertEqual(early.observed30, 30)
        let effortRow = Repository.resolveToday(days: days, logicalKey: key(1), localKey: today)
        XCTAssertEqual(effortRow?.day, key(1), "the Effort cell's row")
        XCTAssertEqual(effortRow?.activeKcalEst, early.kcal)

        // Once today's night is banked the local row wins for both cells.
        days[days.count - 1] = night(today, hrv: 60, rhr: 50, recovery: 60, kcal: 150)
        XCTAssertEqual(BaselineReadouts.calories(for: today, days: days, logicalKey: key(1)).kcal, 150)
        XCTAssertEqual(Repository.resolveToday(days: days, logicalKey: key(1), localKey: today)?.day, today)
        // Daytime (logical == local) and an earlier day read their own row, as before.
        XCTAssertEqual(BaselineReadouts.calories(for: today, days: days).kcal, 150)
        XCTAssertEqual(BaselineReadouts.calories(for: key(1), days: days, logicalKey: key(1)).kcal, 2_300)
    }

    // MARK: Stress

    private func hour(_ h: Int, level: Double?, moving: Bool = false) -> DaytimeStress.HourPoint {
        DaytimeStress.HourPoint(hour: h, startTs: 1_700_000_000 + h * 3_600, level: level, meanHR: 70, rmssd: nil,
                                maskedForActivity: moving)
    }

    func testStressDay_emptyIsNil_scoredDayMapsEveryField() throws {
        XCTAssertNil(BaselineReadouts.stressDay(.empty, day: today))
        let unscored = DaytimeStress.Result(hours: [hour(9, level: nil), hour(10, level: nil, moving: true)],
                                            sustainedHigh: false, sustainedRun: 0, dayMean: nil, peak: nil,
                                            activityMaskedHours: 1)
        XCTAssertNil(BaselineReadouts.stressDay(unscored, day: today), "nothing scored: nothing to draw")

        let hours = [hour(8, level: 0.8), hour(9, level: nil, moving: true), hour(10, level: 2.3), hour(11, level: 1.1)]
        let result = DaytimeStress.Result(hours: hours, sustainedHigh: false, sustainedRun: 0, dayMean: 1.4,
                                          peak: hours[2], activityMaskedHours: 1, highStressMinutes: 60,
                                          timeline: hours + [hour(12, level: 1.0)])
        let r = try XCTUnwrap(BaselineReadouts.stressDay(result, day: today))
        XCTAssertEqual(r.day, today)
        XCTAssertEqual(r.points.count, 5, "the display timeline, gaps included")
        XCTAssertEqual(r.points[1].level, nil)
        XCTAssertTrue(r.points[1].moving)
        XCTAssertEqual(r.points[2].id, hours[2].startTs)
        XCTAssertEqual(r.dayMean, 1.4)
        XCTAssertEqual(try XCTUnwrap(r.peak).level, 2.3)
        XCTAssertEqual(r.highMinutes, 60)
        XCTAssertEqual(r.movingHours, 1)
        XCTAssertEqual(r.scoredHours, 3)
        XCTAssertFalse(r.sustainedHigh)

        let summary = BaselineReadouts.stressSummary(r)
        XCTAssertTrue(summary.hasPrefix("Stress averaged 1.4 of 3 (Medium), peak 2.3 at "), summary)
        XCTAssertTrue(summary.hasSuffix("; 1 hour left out while you were moving."), summary)
        XCTAssertEqual(BaselineReadouts.stressLevelText(0.9), "Low")
        XCTAssertEqual(BaselineReadouts.stressLevelText(1), "Medium")
        XCTAssertEqual(BaselineReadouts.stressLevelText(2), "High")
        XCTAssertEqual(BaselineReadouts.stressDomain, 0...3)
        // The chart's y axis names each band at its middle with the Average cell's own words.
        XCTAssertEqual(StressCurveChart.bandMidpoints.map(BaselineReadouts.stressLevelText), ["Low", "Medium", "High"])
        XCTAssertEqual(StressCurveChart.bandEdges, [0, 1, 2, 3])
    }

    // MARK: Sleep timing

    /// A `.session` night ending on the local day of `wake`.
    private func sleepNight(bed: Date, wake: Date) -> SleepNight {
        SleepNight(dayKey: Fixtures.dayKey(wake), source: .session, onsetTs: Int(bed.timeIntervalSince1970),
                   wakeTs: Int(wake.timeIntervalSince1970), asleepMin: wake.timeIntervalSince(bed) / 60 * 0.9,
                   deepMin: 0, remMin: 0, lightMin: 0, awakeMin: 0, hasStageTotals: false, efficiency: 0.9,
                   restingHr: nil, avgHrv: nil, respRateBpm: nil, skinTempDevC: nil, stagingSparse: false, segments: [])
    }

    /// `count` nights in February 2026 (no DST edge), bed at `bedHour:bedMinute` on day `1 + i`, `hours` long,
    /// each shifted later by `driftMinutes × i`. Newest first, as `SleepNightBuilder.nights` returns them.
    private func februaryNights(_ count: Int, bedHour: Int = 23, bedMinute: Int = 0, hours: Double = 8,
                                driftMinutes: Int = 0) -> [SleepNight] {
        let cal = Calendar.current
        return (0..<count).map { i -> SleepNight in
            let base = Fixtures.local(2026, 2, 1 + i, hour: bedHour, minute: bedMinute)
            let bed = cal.date(byAdding: .minute, value: driftMinutes * i, to: base)!
            return sleepNight(bed: bed, wake: bed.addingTimeInterval(hours * 3_600))
        }.reversed()
    }

    func testMinutesOfDayAndCircularMean_wrapMidnight() throws {
        XCTAssertEqual(BaselineReadouts.minutesOfDay(Fixtures.local(2026, 2, 1, hour: 23, minute: 30)), 1_410, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.minutesOfDay(Fixtures.local(2026, 2, 2, hour: 0, minute: 30)), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.circularMeanMinutes([1_410, 30])), 0, accuracy: 1e-6,
                       "23:30 and 00:30 average to midnight, not noon")
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.circularMeanMinutes([1_380, 1_380])), 1_380, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(BaselineReadouts.circularMeanMinutes([400, 440])), 420, accuracy: 1e-6)
        XCTAssertNil(BaselineReadouts.circularMeanMinutes([]))
        XCTAssertNil(BaselineReadouts.circularMeanMinutes([0, 720]), "opposite times have no mean")
        XCTAssertEqual(BaselineReadouts.clockDistance(1_430, 10), 20)
        XCTAssertEqual(BaselineReadouts.clockDistance(100, 160), 60)
        XCTAssertFalse(BaselineReadouts.clockText(minutes: 1_380).isEmpty)
    }

    func testHourText_followsTheLocaleLikeClockText_andTheStripsAxisUsesIt() {
        let us = Locale(identifier: "en_US"), gb = Locale(identifier: "en_GB")
        // Foundation sets the day period off with a narrow no-break space (U+202F) on iOS 17+; the
        // label reads "6 PM" either way, so compare on plain spaces.
        func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }
        XCTAssertEqual(plain(BaselineReadouts.hourText(minutes: 18 * 60, locale: us)), "6 PM")
        XCTAssertEqual(plain(BaselineReadouts.hourText(minutes: 0, locale: us)), "12 AM")
        XCTAssertEqual(plain(BaselineReadouts.hourText(minutes: 12 * 60, locale: us)), "12 PM")
        XCTAssertEqual(BaselineReadouts.hourText(minutes: 18 * 60, locale: gb), "18", "a 24-hour locale, like clockText's 18:00")
        XCTAssertTrue(BaselineReadouts.clockText(minutes: 18 * 60).contains(BaselineReadouts.hourText(minutes: 18 * 60).prefix(1)))
        // The strip's four ticks: 6 PM, midnight, 6 AM and the trailing noon; two survive at accessibility sizes.
        XCTAssertEqual(TimingStripChart.axisTicks.map(\.minutesOfDay), [18 * 60, 0, 6 * 60, 12 * 60])
        XCTAssertEqual(TimingStripChart.axisTicks.map(\.fraction), [0.25, 0.5, 0.75, 1])
        XCTAssertEqual(TimingStripChart.ticks(accessibilitySize: false).count, 4)
        XCTAssertEqual(TimingStripChart.ticks(accessibilitySize: true).map(\.fraction), [0.5, 1])
    }

    func testNoonInterval_framesANightOnTheNoonToNoonDay() {
        let bed = Fixtures.local(2026, 2, 1, hour: 23)
        let r = BaselineReadouts.noonInterval(bed: bed, wake: bed.addingTimeInterval(8 * 3_600))
        XCTAssertEqual(r.lowerBound, 660, accuracy: 1e-9, "23:00 is 11 hours after noon")
        XCTAssertEqual(r.upperBound, 1_140, accuracy: 1e-9)
        let late = Fixtures.local(2026, 2, 2, hour: 1)
        let r2 = BaselineReadouts.noonInterval(bed: late, wake: late.addingTimeInterval(14 * 3_600))
        XCTAssertEqual(r2.lowerBound, 780, accuracy: 1e-9)
        XCTAssertEqual(r2.upperBound, 1_440, accuracy: 1e-9, "clamped to the frame")
    }

    func testSleepRegularity_identicalNightsScore100_anHourOfDriftAbout83_tooFewPairsNil() throws {
        let timing = { (nights: [SleepNight]) -> [BaselineReadouts.SleepTiming.Night] in
            nights.compactMap { n in n.onset.flatMap { b in n.wake.map { BaselineReadouts.SleepTiming.Night(day: n.dayKey, bed: b, wake: $0) } } }
        }
        XCTAssertEqual(BaselineReadouts.sleepRegularity(nights: timing(februaryNights(14))), 100)
        // Six 8-hour nights, bedtime an hour later every night (23:00 → 04:00, none past noon): every pair
        // disagrees for 120 of 1440 minutes.
        let drifting = try XCTUnwrap(BaselineReadouts.sleepRegularity(nights: timing(februaryNights(6, driftMinutes: 60))))
        XCTAssertEqual(drifting, 83)
        XCTAssertNil(BaselineReadouts.sleepRegularity(nights: timing(februaryNights(5))), "five nights are four pairs")
        XCTAssertNotNil(BaselineReadouts.sleepRegularity(nights: timing(februaryNights(6))))
        XCTAssertEqual(BaselineReadouts.regularityMinPairs, 5)
        XCTAssertEqual(BaselineReadouts.regularityNights, 14)
        // A gap breaks the chain: nights 1–3 and 5–14 give 2 + 9 pairs, still enough.
        let gapped = februaryNights(14).filter { $0.dayKey != Fixtures.dayKey(Fixtures.local(2026, 2, 5, hour: 7)) }
        XCTAssertEqual(BaselineReadouts.sleepRegularity(nights: timing(gapped)), 100)
    }

    func testSleepWindow_storedDefaultsAndRoundTrip() throws {
        let suite = "BaselineReadoutsMetricsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(BaselineReadouts.SleepWindow.stored(defaults), .default)
        XCTAssertEqual(BaselineReadouts.SleepWindow.default, .init(bedMinutes: 23 * 60, wakeMinutes: 7 * 60))
        XCTAssertEqual(BaselineReadouts.SleepWindow.bedKey, "baseline.sleepWindow.bedMinutes")
        XCTAssertEqual(BaselineReadouts.SleepWindow.wakeKey, "baseline.sleepWindow.wakeMinutes")
        XCTAssertEqual(BaselineReadouts.SleepWindow.default.spanMinutes, 480)

        BaselineReadouts.SleepWindow(bedMinutes: 22 * 60 + 30, wakeMinutes: 6 * 60 + 15).save(defaults)
        XCTAssertEqual(BaselineReadouts.SleepWindow.stored(defaults), .init(bedMinutes: 1_350, wakeMinutes: 375))
        defaults.set(5_000, forKey: BaselineReadouts.SleepWindow.bedKey)
        XCTAssertEqual(BaselineReadouts.SleepWindow.stored(defaults).bedMinutes, 23 * 60, "out of range falls back")
        XCTAssertEqual(BaselineReadouts.SleepWindow.toleranceMin, 30)
    }

    func testSleepTiming_averagesRegularityAndWindowCount() throws {
        // Fourteen nights, bed 23:10, wake 07:10; the newest two bed at 00:40 (outside the window).
        var nights = Array(februaryNights(14, bedHour: 23, bedMinute: 10).dropFirst(2))
        let lateA = Fixtures.local(2026, 2, 14, hour: 0, minute: 40)
        let lateB = Fixtures.local(2026, 2, 15, hour: 0, minute: 40)
        nights.insert(sleepNight(bed: lateA, wake: lateA.addingTimeInterval(6.5 * 3_600)), at: 0)
        nights.insert(sleepNight(bed: lateB, wake: lateB.addingTimeInterval(6.5 * 3_600)), at: 0)
        // A daily-row night (an import without sessions) carries no times and is skipped.
        let rowOnly = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric("2026-02-16", sleepMin: 400)))
        nights.insert(rowOnly, at: 0)
        let day = "2026-02-16"
        let window = BaselineReadouts.SleepWindow.default

        let t = BaselineReadouts.sleepTiming(for: day, nights: nights, window: window)
        XCTAssertEqual(t.day, day)
        XCTAssertEqual(t.nights.count, 14)
        XCTAssertEqual(t.nights.first?.day, "2026-02-15", "newest first; the row-only night is out")
        XCTAssertEqual(t.target, window)
        XCTAssertEqual(t.nightsCounted, 14)
        XCTAssertEqual(t.nightsInWindow, 12, "two 00:40 nights miss the 23:00 ± 30 bed target")
        let bedAvg = try XCTUnwrap(t.averageBedMinutes)
        XCTAssertGreaterThan(bedAvg, 23 * 60 + 10, "two late nights pull the circular mean past 23:10")
        XCTAssertLessThan(bedAvg, 23 * 60 + 40)
        let wakeAvg = try XCTUnwrap(t.averageWakeMinutes)
        XCTAssertEqual(wakeAvg, 7 * 60 + 10, accuracy: 1, "the late nights still woke at 07:10")
        XCTAssertNotNil(t.regularity)
        XCTAssertLessThan(try XCTUnwrap(t.regularity), 100)

        // Scoped to the day: only nights on or before it count.
        let earlier = BaselineReadouts.sleepTiming(for: "2026-02-03", nights: nights, window: window)
        XCTAssertEqual(earlier.nights.count, 2)
        XCTAssertNil(earlier.averageBedMinutes, "two nights: under the three-night floor")
        XCTAssertNil(earlier.regularity)
        XCTAssertEqual(earlier.nightsInWindow, 2)
    }

    // MARK: Fitness

    func testFitness_needsAgeSexAndFourNights_thenEstimatesWithAFallbackVO2() throws {
        let days = (0...6).reversed().map { night(key($0), hrv: 60, rhr: 52, recovery: 60, strain: $0 % 2 == 0 ? 45 : 10) }
        XCTAssertNil(BaselineReadouts.fitness(for: today, days: days, age: nil, sex: "male"))
        XCTAssertNil(BaselineReadouts.fitness(for: today, days: days, age: 40, sex: nil))
        XCTAssertNil(BaselineReadouts.fitness(for: today, days: Array(days.suffix(3)), age: 40, sex: "male"),
                     "three nights of resting HR are under the four-night gate")
        let inputs = BaselineReadouts.fitnessInputs(for: today, days: days, age: nil, sex: "male", waistCm: nil, hasHeightWeight: false)
        XCTAssertFalse(inputs.canCompute)
        XCTAssertEqual(inputs.items.first(where: { $0.key == "rhr" })?.detail, "7 of last 7 nights")

        let f = try XCTUnwrap(BaselineReadouts.fitness(for: today, days: days, age: 40, sex: "male"))
        XCTAssertEqual(f.weekEnding, today)
        XCTAssertEqual(f.restingHr, 52)
        XCTAssertEqual(f.rhrNights, 7)
        XCTAssertEqual(f.activeDays, 4, "days with Effort ≥ 30")
        XCTAssertEqual(f.result.chronoAge, 40)
        XCTAssertEqual(f.result.bandYears, 5)
        XCTAssertNil(f.result.vo2max, "Nes needs a waist")
        XCTAssertTrue(f.vo2IsFallback)
        let vo2 = try XCTUnwrap(f.vo2max)
        XCTAssertEqual(vo2, 15.3 * StrainScorer.estimateHRmax([], age: 40).0 / 52, accuracy: 1e-6, "Uth 2004")
        XCTAssertEqual(try XCTUnwrap(f.vo2BandText), String(format: "%.0f–%.0f", vo2 - 5, vo2 + 5))
        XCTAssertEqual(f.inputs.confidence, .ready, "seven nights of resting HR and seven days with an Effort")
        XCTAssertFalse(f.result.lowerConfidence)

        let withWaist = try XCTUnwrap(BaselineReadouts.fitness(for: today, days: days, age: 40, sex: "male", waistCm: 90))
        XCTAssertNotNil(withWaist.result.vo2max)
        XCTAssertFalse(withWaist.vo2IsFallback)
        XCTAssertEqual(withWaist.vo2max, withWaist.result.vo2max)
        XCTAssertEqual(BaselineReadouts.median([3, 1, 2]), 2)
        XCTAssertEqual(BaselineReadouts.median([4, 1, 2, 3]), 2.5)
    }

    func testFitnessWeek_isACalendarWeek_notNoopsLastSevenRows() throws {
        // Four nights, five days off, two nights (yesterday and today). NOOP's own gate takes the last seven
        // ROWS, so it sees all six resting-HR nights and scores the week; Baseline's week is the seven
        // CALENDAR days ending today, which hold two, so it waits rather than scoring a week with nights
        // from the week before. A deliberate difference, documented on `fitnessWeek`.
        let worn = [10, 9, 8, 7, 1, 0]
        let days = worn.reversed().map { night(key($0), hrv: 60, rhr: 52, recovery: 60, strain: 40) }
        XCTAssertEqual(Array(days.suffix(7)).compactMap(\.restingHr).count, 6, "NOOP's last-seven-rows gate would compute")
        XCTAssertNil(BaselineReadouts.fitness(for: today, days: days, age: 40, sex: "male"))
        let inputs = BaselineReadouts.fitnessInputs(for: today, days: days, age: 40, sex: "male", waistCm: nil, hasHeightWeight: false)
        XCTAssertFalse(inputs.canCompute)
        XCTAssertEqual(inputs.items.first(where: { $0.key == "rhr" })?.detail, "2 of last 7 nights")
        // The week ending on the fourth worn night holds those four and computes.
        let earlier = try XCTUnwrap(BaselineReadouts.fitness(for: key(7), days: days, age: 40, sex: "male"))
        XCTAssertEqual(earlier.rhrNights, 4)
        XCTAssertEqual(earlier.weekEnding, key(7))
    }

    /// Settings › Profile's "entered" flag, read from a suite of its own so the app's defaults stay
    /// untouched: absent → false (the store's seeded age and sex are not used), "YES" the way the
    /// screenshot harness passes it through the argument domain → true.
    func testProfileSet_isFalseUntilWritten() throws {
        let suite = "baseline.tests.profileSet"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(BaselineReadouts.ProfileSet.key, "baseline.profileSet")
        XCTAssertFalse(BaselineReadouts.ProfileSet.current(defaults))
        defaults.set(true, forKey: BaselineReadouts.ProfileSet.key)
        XCTAssertTrue(BaselineReadouts.ProfileSet.current(defaults))
        defaults.set("YES", forKey: BaselineReadouts.ProfileSet.key)
        XCTAssertTrue(BaselineReadouts.ProfileSet.current(defaults), "the harness' `-baseline.profileSet YES`")
    }

    // MARK: Accuracy table

    func testMetricAccuracy_coversTheLiteratureTable_inBaselinesVocabulary() throws {
        let expected: [(String, MetricAccuracy.Tier)] = [
            ("hrv", .high), ("restingHr", .high), ("sleepDuration", .medium), ("sleepTiming", .medium),
            ("sleepRegularity", .high), ("sleepStages", .low), ("steps", .medium), ("calories", .low),
            ("vo2", .low), ("spo2", .low), ("skinTemp", .medium), ("stress", .low), ("readiness", .low),
            ("effort", .medium),
        ]
        XCTAssertEqual(MetricAccuracy.all.map(\.key), expected.map(\.0), "the table's order")
        for (key, tier) in expected {
            let row = try XCTUnwrap(MetricAccuracy.lookup(key), key)
            XCTAssertEqual(row.tier, tier, key)
            XCTAssertFalse(row.caveat.isEmpty)
            XCTAssertTrue(row.caveat.hasSuffix("."), row.caveat)
            for word in forbidden + ["whoop"] {
                XCTAssertFalse(row.name.lowercased().contains(word), row.name)
                XCTAssertFalse(row.caveat.lowercased().contains(word), row.caveat)
            }
        }
        XCTAssertNil(MetricAccuracy.lookup("no-such-metric"))
        XCTAssertEqual(MetricAccuracy["hrv"]?.name, "HRV")
        XCTAssertEqual(MetricAccuracy.Tier.high.label, "High accuracy")
        XCTAssertEqual(MetricAccuracy.Tier.medium.label, "Medium accuracy")
        XCTAssertEqual(MetricAccuracy.Tier.low.label, "Low accuracy")
        XCTAssertEqual(MetricAccuracy.Tier.allCases.map(\.shortLabel), ["High", "Medium", "Low"],
                       "the badge's text at accessibility sizes is the tier word alone")
    }

    // MARK: Day keys

    func testLocalMidnight_parsesAKey() throws {
        let d = try XCTUnwrap(BaselineReadouts.localMidnight(of: "2026-02-18"))
        XCTAssertEqual(Repository.localDayKey(d), "2026-02-18")
        XCTAssertEqual(Calendar.current.component(.hour, from: d), 0)
        XCTAssertNil(BaselineReadouts.localMidnight(of: "not a key"))
    }
}
