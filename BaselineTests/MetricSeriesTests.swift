import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// The range layer (`Baseline/Components/BaselineReadoutsRanges.swift`): `MetricRange`, the one
/// bucketing function (days, ISO weeks, months; missing days excluded, partial newest bucket), the
/// stats with the period-before comparison, the readings per key (efficiency as a percent, bedtime
/// noon-anchored), the band attachment, the sentences, and the intraday heart-rate readout
/// (`BaselineReadoutsIntraday.swift`: downsampling, sleep and workout spans).
final class MetricSeriesTests: BaselineEngineTestCase {

    /// A Wednesday; 2026-02-16 is the Monday of its week.
    private let today = "2026-02-18"
    private let forbidden = ["strain", "recovery", "coach"]

    private func key(_ back: Int) -> String { Fixtures.key(today, minus: back) }

    private func values(_ pairs: [(Int, Double)]) -> [MetricDayValue] {
        pairs.map { MetricDayValue(day: key($0.0), value: $0.1) }
    }

    // MARK: Range

    func testMetricRange_labelsDaysAndBuckets() {
        XCTAssertEqual(MetricRange.allCases.map(\.label), ["1D", "7D", "4W", "1Y"])
        XCTAssertEqual(MetricRange.allCases.map(\.shortLabel), ["1D", "7D", "4W", "1Y"], "one spelling at every type size")
        XCTAssertEqual(MetricRange.allCases.map(\.days), [1, 7, 28, 365])
        XCTAssertEqual(MetricRange.allCases.map(\.bucket), [.day, .day, .day, .week])
        XCTAssertEqual(MetricRange.week.subtitle, "Last 7 days")
        XCTAssertEqual(MetricRange.resolve("fourWeeks"), .fourWeeks)
        XCTAssertEqual(MetricRange.resolve(nil), .week)
        XCTAssertEqual(BaselineReadouts.metricWindow(range: .week, endKey: today).startKey, key(6))
        XCTAssertEqual(BaselineReadouts.metricWindow(range: .year, endKey: today).startKey, key(364))
        XCTAssertEqual(BaselineReadouts.dayKeys(from: key(2), to: today), [key(2), key(1), today])
        XCTAssertTrue(BaselineReadouts.dayKeys(from: today, to: key(1)).isEmpty)
    }

    // MARK: Bucketing

    func testBuckets_byDay_excludeMissingDays_andCarryNoExtremesForASingleValue() {
        let v = values([(6, 60), (4, 62), (0, 70)]) + [MetricDayValue(day: key(2), value: 65, min: 50, max: 90)]
        let points = BaselineRangeSeries.buckets(v, from: key(6), to: today, bucket: .day)
        XCTAssertEqual(points.map(\.id), [key(6), key(4), key(2), today])
        XCTAssertEqual(points.map(\.value), [60, 62, 65, 70])
        XCTAssertEqual(points.map(\.n), [1, 1, 1, 1])
        XCTAssertNil(points[0].min, "a day without its own extremes has none")
        XCTAssertEqual(points[2].min, 50, "a heart-rate day keeps its low and high")
        XCTAssertEqual(points[2].max, 90)
        XCTAssertEqual(points[3].date, BaselineReadouts.localMidnight(of: today))
        // Outside the window and non-finite values are dropped.
        let noisy = v + [MetricDayValue(day: key(7), value: 1), MetricDayValue(day: today, value: .nan)]
        XCTAssertEqual(BaselineRangeSeries.buckets(noisy, from: key(6), to: today, bucket: .day).map(\.value), [60, 62, 65, 70])
    }

    func testBuckets_byISOWeek_keyedByMonday_withMeanLowHighAndCount() {
        // Mon 2026-02-09 … Sun 02-15 (three days), Mon 02-16 … Wed 02-18 (two days).
        let v = [MetricDayValue(day: "2026-02-09", value: 60), MetricDayValue(day: "2026-02-11", value: 70), MetricDayValue(day: "2026-02-15", value: 50),
                 MetricDayValue(day: "2026-02-16", value: 80), MetricDayValue(day: "2026-02-18", value: 90, min: 40, max: 100)]
        let points = BaselineRangeSeries.buckets(v, from: "2026-02-01", to: "2026-02-18", bucket: .week)
        XCTAssertEqual(points.map(\.id), ["2026-02-09", "2026-02-16"])
        XCTAssertEqual(points[0].value, 60, accuracy: 1e-9)
        XCTAssertEqual(points[0].min, 50)
        XCTAssertEqual(points[0].max, 70)
        XCTAssertEqual(points[0].n, 3)
        XCTAssertEqual(points[1].value, 85, accuracy: 1e-9)
        XCTAssertEqual(points[1].min, 40, "a day's own low counts")
        XCTAssertEqual(points[1].max, 100)
        XCTAssertEqual(points[1].n, 2)
        XCTAssertEqual(BaselineRangeSeries.bucketStart(of: "2026-02-22", bucket: .week), "2026-02-16", "Sunday belongs to the Monday's week")
        XCTAssertEqual(BaselineRangeSeries.bucketEnd(of: "2026-02-16", bucket: .week), "2026-02-22")
        XCTAssertEqual(BaselineRangeSeries.bucketStart(of: "2026-02-18", bucket: .month), "2026-02-01")
        XCTAssertEqual(BaselineRangeSeries.bucketEnd(of: "2026-02-01", bucket: .month), "2026-02-28")
        XCTAssertNil(BaselineRangeSeries.bucketStart(of: "not a day", bucket: .week))
        var sunday = Calendar(identifier: .gregorian)
        sunday.firstWeekday = 1
        XCTAssertEqual(BaselineRangeSeries.bucketStart(of: "2026-02-22", bucket: .week, calendar: sunday), "2026-02-16",
                       "ISO weeks whatever the locale")
        XCTAssertEqual(BaselineRangeSeries.dayCount(from: "2026-02-16", to: "2026-02-22"), 7)
        XCTAssertEqual(BaselineRangeSeries.dayCount(from: today, to: today), 1)
    }

    func testStats_overDailyValues_withThePeriodBefore() {
        // This week: 60, 62, 70 (three days); the seven days before: 50, 52, 54 (three days).
        let v = values([(6, 60), (4, 62), (0, 70), (8, 50), (10, 52), (13, 54), (14, 99)])
        let s = BaselineRangeSeries.stats(v, from: key(6), to: today)
        XCTAssertEqual(s.latest, 70)
        XCTAssertEqual(s.latestDay, today)
        XCTAssertEqual(s.average!, 64, accuracy: 1e-9)
        XCTAssertEqual(s.min, 60)
        XCTAssertEqual(s.max, 70)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.previousCount, 3, "the day 14 back is outside the period before")
        XCTAssertEqual(s.previousAverage!, 52, accuracy: 1e-9)
        XCTAssertEqual(s.change!, 12, accuracy: 1e-9)
        // Under three days on either side there is no comparison.
        let thin = BaselineRangeSeries.stats(values([(0, 70), (1, 60), (2, 65), (8, 50)]), from: key(6), to: today)
        XCTAssertNil(thin.previousAverage)
        XCTAssertNil(thin.change)
        XCTAssertEqual(thin.count, 3)
        XCTAssertEqual(BaselineRangeSeries.stats([], from: key(6), to: today), .empty)
    }

    // MARK: Series

    func testMetricSeries_year_isWeekly_andFlagsThePartialNewestWeek() {
        var readings: [MetricDayValue] = []
        for back in 0..<60 { readings.append(MetricDayValue(day: key(back), value: Double(60 + back % 5))) }
        let s = BaselineReadouts.metricSeries(key: .hrv, range: .year, endKey: today, readings: readings)
        XCTAssertEqual(s.range, .year)
        XCTAssertEqual(s.startKey, key(364))
        XCTAssertEqual(s.points.last?.id, "2026-02-16", "the week of the Wednesday")
        XCTAssertEqual(s.points.last?.n, 3)
        XCTAssertTrue(s.lastBucketPartial, "Wednesday: the week runs to Sunday")
        XCTAssertEqual(s.stats.count, 60)
        XCTAssertFalse(s.isEmpty)
        let sunday = BaselineReadouts.metricSeries(key: .hrv, range: .year, endKey: "2026-02-22", readings: readings)
        XCTAssertFalse(sunday.lastBucketPartial)
        let week = BaselineReadouts.metricSeries(key: .hrv, range: .week, endKey: today, readings: readings)
        XCTAssertEqual(week.points.count, 7)
        XCTAssertFalse(week.lastBucketPartial)
    }

    func testMetricSeries_attachesBands_perDay_andAsWeeklyMeans() {
        let readings = values([(0, 70), (1, 60), (2, 65), (3, 62), (8, 50)])
        let bands = [key(0): MetricBand(baseline: 64, low: 58, high: 70), key(1): MetricBand(baseline: 62, low: 56, high: 68)]
        let week = BaselineReadouts.metricSeries(key: .hrv, range: .week, endKey: today, readings: readings, bands: bands)
        XCTAssertEqual(week.points.last?.band, bands[key(0)])
        XCTAssertNil(week.points.first?.band, "no band before it was usable")
        let year = BaselineReadouts.metricSeries(key: .hrv, range: .year, endKey: today, readings: readings, bands: bands)
        let last = try! XCTUnwrap(year.points.last?.band)
        XCTAssertEqual(last.baseline, 63, accuracy: 1e-9, "the mean band of the week's banded days")
        XCTAssertEqual(last.low, 57, accuracy: 1e-9)
        XCTAssertEqual(last.high, 69, accuracy: 1e-9)
    }

    func testMetricBands_comeFromTheNightlyWalk_forHRVAndRestingHROnly() {
        var days: [DailyMetric] = []
        for back in (1...20).reversed() { days.append(Fixtures.metric(key(back), hrv: 60 + Double(back % 3), rhr: 50)) }
        days.append(Fixtures.metric(today, hrv: 64, rhr: 51))
        let hrv = BaselineReadouts.metricBands(key: .hrv, days: days, endKey: today)
        XCTAssertNotNil(hrv[today], "twenty nights before today: the band is usable")
        XCTAssertNil(hrv[key(20)], "the first night has nothing before it")
        let expected = BaselineReadouts.latestNight(upToToday: days, cfg: Baselines.hrvCfg) { $0.avgHrv }.state
        XCTAssertEqual(hrv[today]?.baseline, expected.baseline, "the same fold the Today hero reads")
        XCTAssertFalse(BaselineReadouts.metricBands(key: .rhr, days: days, endKey: today).isEmpty)
        XCTAssertTrue(BaselineReadouts.metricBands(key: .steps, days: days, endKey: today).isEmpty)
    }

    // MARK: Readings per key

    func testReadings_efficiencyAsPercent_bedtimeNoonAnchored_wakeFromMidnight() throws {
        let days = [DailyMetric(day: key(1), totalSleepMin: 420, efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil,
                                disturbances: nil, restingHr: 50, avgHrv: 60, recovery: 70, strain: 12, exerciseCount: nil,
                                steps: 8_000, activeKcalEst: 2_100),
                    DailyMetric(day: today, totalSleepMin: 400, efficiency: 88, deepMin: nil, remMin: nil, lightMin: nil,
                                disturbances: nil, restingHr: 52, avgHrv: 64, recovery: 72, strain: 8, exerciseCount: nil)]
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .sleepEfficiency, days: days).map(\.value), [90, 88])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .hrv, days: days).map(\.value), [60, 64])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .rhr, days: days).map(\.value), [50, 52])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .readiness, days: days).map(\.value), [70, 72])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .sleepDuration, days: days).map(\.value), [420, 400])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .effort, days: days).map(\.value), [12, 8])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .calories, days: days).map(\.value), [2_100])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .steps, days: days).map(\.value), [8_000])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .steps, days: days, stepReadings: [(day: today, value: 9_000)]).map(\.value), [9_000],
                       "the resolver's readings replace the column")

        // A night 23:30 → 07:15 ending on today; a daily-row night carries no times.
        let bed = Fixtures.local(2026, 2, 17, hour: 23, minute: 30), wake = Fixtures.local(2026, 2, 18, hour: 7, minute: 15)
        let night = SleepNight(dayKey: today, source: .session, onsetTs: Int(bed.timeIntervalSince1970), wakeTs: Int(wake.timeIntervalSince1970),
                               asleepMin: 440, deepMin: 90, remMin: 100, lightMin: 250, awakeMin: 25, hasStageTotals: true,
                               efficiency: 0.95, restingHr: 52, avgHrv: 64, respRateBpm: nil, skinTempDevC: nil, stagingSparse: false, segments: [])
        let rowOnly = try XCTUnwrap(SleepNightBuilder.build(fromDaily: days[0]))
        let bedtime = BaselineReadouts.metricReadings(key: .bedtime, days: days, nights: [rowOnly, night])
        XCTAssertEqual(bedtime.count, 1)
        XCTAssertEqual(bedtime[0].value, 11 * 60 + 30, accuracy: 1e-6, "23:30 is 690 minutes after noon")
        XCTAssertEqual(BaselineReadouts.clockValueText(bedtime[0].value, key: .bedtime),
                       BaselineReadouts.clockText(minutes: 23 * 60 + 30))
        let wakes = BaselineReadouts.metricReadings(key: .wake, days: days, nights: [night])
        XCTAssertEqual(wakes[0].value, 7 * 60 + 15, accuracy: 1e-6)
        XCTAssertEqual(BaselineReadouts.clockValueText(wakes[0].value, key: .wake), BaselineReadouts.clockText(minutes: 7 * 60 + 15))
        // A bedtime after midnight sits later than one before it, so averages do not wrap.
        let late = Fixtures.local(2026, 2, 18, hour: 0, minute: 30)
        let lateNight = SleepNight(dayKey: today, source: .session, onsetTs: Int(late.timeIntervalSince1970), wakeTs: Int(wake.timeIntervalSince1970),
                                   asleepMin: 380, deepMin: 0, remMin: 0, lightMin: 0, awakeMin: 0, hasStageTotals: false,
                                   efficiency: nil, restingHr: nil, avgHrv: nil, respRateBpm: nil, skinTempDevC: nil, stagingSparse: false, segments: [])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .bedtime, days: days, nights: [lateNight])[0].value, 12 * 60 + 30, accuracy: 1e-6)

        // Intraday facts come in as maps.
        var facts = BaselineReadouts.IntradayDayValues()
        facts.stressMean[today] = 1.4
        facts.intensityMinutes[today] = 23
        facts.heartRate[today] = (48, 71, 162)
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .stressAvg, days: days, intraday: facts).map(\.value), [1.4])
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .intensityMinutes, days: days, intraday: facts).map(\.value), [23])
        let hr = BaselineReadouts.metricReadings(key: .heartRate, days: days, intraday: facts)
        XCTAssertEqual(hr[0].value, 71)
        XCTAssertEqual(hr[0].min, 48)
        XCTAssertEqual(hr[0].max, 162)
    }

    func testMetricKey_vocabularyAndShapes() {
        for k in MetricKey.allCases {
            for word in forbidden { XCTAssertFalse(k.name.lowercased().contains(word), k.name) }
        }
        XCTAssertEqual(MetricKey.rhr.name, "Resting HR")
        XCTAssertEqual(MetricKey.intensityMinutes.name, "Intensity minutes")
        XCTAssertTrue(MetricKey.steps.isCountLike)
        XCTAssertFalse(MetricKey.hrv.isCountLike)
        XCTAssertTrue(MetricKey.bedtime.isClockTime)
        XCTAssertEqual(MetricKey.rhr.higherIsBetter, false)
        XCTAssertNil(MetricKey.heartRate.higherIsBetter)
        XCTAssertEqual(MetricKey.readiness.seriesKey, "recovery", "NOOP's column name stays a code name")
        XCTAssertTrue(MetricKey.heartRate.isIntradayDerived)
    }

    // MARK: Sentences

    func testContextSentence_saysTheAverageOnce_thenTheChange() {
        let whole: (Double) -> String = { "\(Int($0.rounded()))" }
        let up = BaselineReadouts.metricSeries(key: .hrv, range: .week, endKey: today,
                                               readings: values([(6, 60), (4, 62), (0, 70), (8, 50), (10, 52), (13, 54)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: up, noun: "HRV", unit: "ms", format: whole),
                       "Averaged 64 ms over the last 7 days, 12 ms above the 7 days before.")
        let steady = BaselineReadouts.metricSeries(key: .rhr, range: .fourWeeks, endKey: today,
                                                   readings: values([(0, 50), (1, 50), (2, 50), (30, 50), (31, 50), (32, 50)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: steady, noun: "resting HR", unit: "bpm", format: whole),
                       "Averaged 50 bpm over the last 4 weeks, about the same as the 4 weeks before.")
        let alone = BaselineReadouts.metricSeries(key: .hrv, range: .week, endKey: today, readings: values([(0, 70), (1, 60)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: alone, noun: "HRV", unit: "ms", format: whole),
                       "Averaged 65 ms over the last 7 days.")
        let none = BaselineReadouts.metricSeries(key: .hrv, range: .week, endKey: today, readings: [])
        XCTAssertEqual(BaselineReadouts.metricContext(series: none, noun: "HRV", unit: "ms", format: whole),
                       "No days with HRV in the last 7 days.")
        // 1D: the cells print both days, so the sentence is the difference alone, never 8,412 again.
        let stepsText: (Double) -> String = { BaselineReadouts.stepsText(Int($0.rounded())) }
        let day = BaselineReadouts.metricSeries(key: .steps, range: .day, endKey: today, readings: values([(0, 8_412), (1, 6_000)]))
        let daySentence = BaselineReadouts.metricContext(series: day, noun: "steps", unit: "", format: stepsText)
        XCTAssertEqual(daySentence, "+2,412 vs the day before.")
        XCTAssertFalse(daySentence.contains("8,412"), "the day's value is the cell's, said once")
        let fewer = BaselineReadouts.metricSeries(key: .rhr, range: .day, endKey: today, readings: values([(0, 50), (1, 53)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: fewer, noun: "resting HR", unit: "bpm", format: whole),
                       "\u{2212}3 bpm vs the day before.")
        let same = BaselineReadouts.metricSeries(key: .rhr, range: .day, endKey: today, readings: values([(0, 50), (1, 50)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: same, noun: "resting HR", unit: "bpm", format: whole),
                       "About the same as the day before.")
        let alone1D = BaselineReadouts.metricSeries(key: .steps, range: .day, endKey: today, readings: values([(0, 8_412)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: alone1D, noun: "steps", unit: "", format: stepsText),
                       "No day before to compare.")
        let empty1D = BaselineReadouts.metricSeries(key: .steps, range: .day, endKey: today, readings: values([(1, 6_000)]))
        XCTAssertEqual(BaselineReadouts.metricContext(series: empty1D, noun: "steps", unit: "", format: stepsText),
                       "No steps recorded for this day.")
        XCTAssertEqual(BaselineReadouts.metricChangeText(-3.2, format: whole, unit: "bpm"), "\u{2212}3 bpm")
        XCTAssertEqual(BaselineReadouts.metricChangeText(nil, format: whole, unit: "bpm"), "–")
        let summary = BaselineReadouts.metricChartSummary(series: up, name: "HRV", unit: "ms", format: whole)
        XCTAssertEqual(summary, "HRV, last 7 days: 3 days from 60 to 70 ms; average 64 ms; +12 ms vs the period before")
        let yearly = BaselineReadouts.metricSeries(key: .hrv, range: .year, endKey: today, readings: values([(0, 70), (1, 60), (9, 65)]))
        XCTAssertTrue(BaselineReadouts.metricChartSummary(series: yearly, name: "HRV", unit: "ms", format: whole).contains("2 weeks over 3 days"))
    }

    // MARK: Intraday heart rate

    func testIntradayHeartRate_downsamplesClipsSpansAndSummarises() throws {
        let midnight = BaselineReadouts.localMidnight(of: today)!
        let t0 = Int(midnight.timeIntervalSince1970)
        // 1,440 minutes at 60 bpm, a 162 peak at 18:00, a 48 low at 03:00, PPG-derived (conf 0.6) at 12:00.
        let buckets = (0..<1_440).map { i -> HRBucket in
            let bpm: Double = i == 18 * 60 ? 162 : i == 3 * 60 ? 48 : 60
            return HRBucket(ts: t0 + i * 60, bpm: bpm, minBpm: bpm - 2, maxBpm: bpm + 2, conf: i == 12 * 60 ? 0.6 : 1)
        }
        let bed = Fixtures.local(2026, 2, 17, hour: 23, minute: 0), wake = Fixtures.local(2026, 2, 18, hour: 7, minute: 0)
        let night = SleepNight(dayKey: today, source: .session, onsetTs: Int(bed.timeIntervalSince1970), wakeTs: Int(wake.timeIntervalSince1970),
                               asleepMin: 440, deepMin: 90, remMin: 100, lightMin: 250, awakeMin: 25, hasStageTotals: true,
                               efficiency: 0.95, restingHr: 52, avgHrv: 64, respRateBpm: nil, skinTempDevC: nil, stagingSparse: false, segments: [])
        let run = WorkoutRow(startTs: t0 + 18 * 3_600, endTs: t0 + 19 * 3_600, sport: "Running", source: "my-whoop", durationS: 3_600,
                             energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
        let yesterday = WorkoutRow(startTs: t0 - 7_200, endTs: t0 - 3_600, sport: "Cycling", source: "my-whoop", durationS: 3_600,
                                   energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)

        let t = try XCTUnwrap(BaselineReadouts.intradayHeartRate(day: today, buckets: buckets, nights: [night], workouts: [run, yesterday]))
        XCTAssertEqual(t.points.count, 1_440)
        XCTAssertEqual(t.minBpm, 46)
        XCTAssertEqual(t.maxBpm, 164)
        XCTAssertEqual(t.coveredMinutes, 1_440)
        XCTAssertFalse(t.partial)
        XCTAssertEqual(t.dayStart, midnight)
        XCTAssertEqual(t.sleep.count, 1)
        XCTAssertEqual(t.sleep[0].start, midnight, "the night is clipped to the day")
        XCTAssertEqual(t.sleep[0].end, wake)
        XCTAssertEqual(t.workouts.map(\.label), ["Running"], "yesterday's ride is outside the day")
        XCTAssertEqual(t.workouts[0].kind, .workout)
        XCTAssertEqual(t.points[12 * 60].conf, 0.6)
        let summary = BaselineReadouts.intradaySummary(t)
        XCTAssertTrue(summary.hasPrefix("Heart rate: 46 to 164 bpm, average 60"), summary)
        XCTAssertTrue(summary.contains("asleep"), summary)
        XCTAssertTrue(summary.contains("one workout, Running"), summary)
        // The 1D hero's visible sentence: coverage and spans only; the low / mean / high are the cells'.
        let context = BaselineReadouts.intradayContext(t)
        XCTAssertTrue(context.hasPrefix("24h 00m of heart rate · asleep until "), context)
        XCTAssertEqual(context.components(separatedBy: "asleep").count, 2, "one asleep clause: \(context)")
        XCTAssertTrue(context.hasSuffix(" · one workout, Running."), context)
        for number in ["46", "164", "60"] { XCTAssertFalse(context.contains(number), "\(number) is a cell: \(context)") }
        XCTAssertFalse(context.lowercased().contains("average"), context)

        // Downsampling keeps the extremes and the weakest confidence.
        let small = try XCTUnwrap(BaselineReadouts.intradayHeartRate(day: today, buckets: buckets, maxPoints: 144))
        XCTAssertLessThanOrEqual(small.points.count, 144)
        XCTAssertEqual(small.points.map(\.maxBpm).max(), 164)
        XCTAssertEqual(small.points.map(\.minBpm).min(), 46)
        XCTAssertEqual(small.points.map(\.conf).min(), 0.6)
        XCTAssertEqual(small.minBpm, 46, "the day's numbers come from every bucket, not the drawn ones")
        XCTAssertEqual(BaselineReadouts.downsample(buckets, to: 2_000).count, 1_440, "already fits")

        // A partial day and the empty case.
        let morningOnly = try XCTUnwrap(BaselineReadouts.intradayHeartRate(day: today, buckets: Array(buckets.prefix(120))))
        XCTAssertTrue(morningOnly.partial)
        XCTAssertTrue(BaselineReadouts.intradaySummary(morningOnly).contains("2h 00m of the day"))
        XCTAssertEqual(BaselineReadouts.intradayContext(morningOnly), "Partial day: 2h 00m of heart rate.",
                       "coverage said once, in the hero; the trace caption no longer repeats it")
        XCTAssertNil(BaselineReadouts.intradayHeartRate(day: today, buckets: []))
        XCTAssertNil(BaselineReadouts.intradayHeartRate(day: "nope", buckets: buckets))

        // The series form of the day: one point per sample, the day's low / mean / high as the stats.
        let s = BaselineReadouts.metricSeries(key: .heartRate, range: .day, endKey: today, readings: [], intraday: t)
        XCTAssertEqual(s.points.count, 1_440)
        XCTAssertEqual(s.stats.min, 46)
        XCTAssertEqual(s.stats.max, 164)
        XCTAssertEqual(s.stats.count, 1_440)
        let none = BaselineReadouts.metricSeries(key: .heartRate, range: .day, endKey: today, readings: [], intraday: nil)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.stats, .empty)
    }

    // MARK: Intensity behind the profile gate

    /// The Intensity series goes through the one profile gate (`IntensityMinutes.mayScore`, which
    /// `IntradayDayStore.records` scores every day behind): NOOP's `ProfileStore` seeds a 30-year-old
    /// whose Tanaka max (187 bpm) is never nil, but until a date of birth is entered (`ProfileSet`) or a
    /// max heart rate is set by hand the day is `.needsAge`, so the series Trends and the detail's
    /// 7D / 4W / 1Y draw is empty, as Home's card and the 1D week view say. The same minutes are
    /// credited once either is entered.
    @MainActor
    func testIntensitySeries_seededProfileScoresNothingUntilAnAgeOrMaxHRIsEntered() throws {
        let seededHRmax = StrainScorer.tanakaHRmax(age: 30)
        let zones = HRZones.zones(maxHR: seededHRmax.rounded())
        let nights = (1...5).map { Fixtures.metric(key($0), rhr: 52) }
        let t0 = Int(try XCTUnwrap(BaselineReadouts.localMidnight(of: today)).timeIntervalSince1970) + 10 * 3_600
        // 25 minutes at 120 bpm: moderate (not vigorous) on resting 52 against 187 or 190.
        let buckets = (0..<25).map { i in HRBucket(ts: t0 + i * 60, bpm: 120, minBpm: 116, maxBpm: 124) }

        func series(entered: Bool, hrMaxOverride: Int) -> MetricSeries {
            let hrMax = hrMaxOverride > 0 ? Double(hrMaxOverride) : seededHRmax
            let thresholds = IntensityMinutes.thresholds(for: today, days: nights, effortHRmax: hrMax, zoneSet: zones,
                                                         entered: entered, hrMaxOverride: hrMaxOverride)
            let record = IntradayDayStore.compute(day: today, buckets: buckets, thresholds: thresholds,
                                                  fingerprint: (count: 1_500, maxTs: t0 + 24 * 60))
            let readings = BaselineReadouts.metricReadings(key: .intensityMinutes, days: nights,
                                                           intraday: BaselineReadouts.intradayValues([today: record]))
            return BaselineReadouts.metricSeries(key: .intensityMinutes, range: .week, endKey: today, readings: readings)
        }

        XCTAssertFalse(IntensityMinutes.mayScore(entered: false, hrMaxOverride: 0))
        XCTAssertNil(IntensityMinutes.thresholds(for: today, days: nights, effortHRmax: seededHRmax, zoneSet: zones,
                                                 entered: false, hrMaxOverride: 0), "the seeded age is not a max heart rate")
        let seeded = series(entered: false, hrMaxOverride: 0)
        XCTAssertTrue(seeded.points.isEmpty, "nothing credited against a stranger's max heart rate")
        XCTAssertTrue(seeded.isEmpty)

        let entered = series(entered: true, hrMaxOverride: 0)
        XCTAssertEqual(entered.points.count, 1)
        XCTAssertEqual(entered.stats.latest, 25)

        let manual = series(entered: false, hrMaxOverride: 190)
        XCTAssertTrue(IntensityMinutes.mayScore(entered: false, hrMaxOverride: 190), "an override scores without a date of birth")
        XCTAssertEqual(manual.stats.latest, 25)
    }

    /// A day the strap recorded nothing on (off, on the charger, or before it was paired) has a record
    /// scored on a basis with zero minutes, but it is not a reading: the range's count, average, low and
    /// the period before ignore it, while a worn quiet day stays a genuine zero. Trends' weeks count the
    /// same days through the same predicate (`IntradayDayRecord.isRecorded`).
    func testIntensitySeries_skipsDaysTheStrapRecordedNothing() throws {
        let t = try XCTUnwrap(IntensityMinutes.Thresholds.karvonen(restingHr: 52, hrMax: 182))   // moderate ≥ 104
        let t0 = Int(try XCTUnwrap(BaselineReadouts.localMidnight(of: today)).timeIntervalSince1970) + 9 * 3_600
        let walk = (0..<40).map { HRBucket(ts: t0 + $0 * 60, bpm: 120, minBpm: 118, maxBpm: 122) }
        let desk = (0..<300).map { HRBucket(ts: t0 - 86_400 + $0 * 60, bpm: 70, minBpm: 66, maxBpm: 74) }
        var records = [today: IntradayDayStore.compute(day: today, buckets: walk, thresholds: t),
                       key(1): IntradayDayStore.compute(day: key(1), buckets: desk, thresholds: t)]
        // Five strap-off days in the window and seven in the week before it.
        for back in Array(2...6) + Array(7...13) {
            records[key(back)] = IntradayDayStore.compute(day: key(back), buckets: [], thresholds: t)
        }
        let off = try XCTUnwrap(records[key(2)])
        XCTAssertTrue(off.basisIsScored, "precondition: the empty day has a basis")
        XCTAssertFalse(off.recordedIntensity)
        XCTAssertTrue(try XCTUnwrap(records[key(1)]).recordedIntensity, "a worn quiet day is a reading")

        let values = BaselineReadouts.intradayValues(records)
        XCTAssertEqual(Set(values.intensityMinutes.keys), [today, key(1)])
        let readings = BaselineReadouts.metricReadings(key: .intensityMinutes, days: [], intraday: values)
        let s = BaselineReadouts.metricSeries(key: .intensityMinutes, range: .week, endKey: today, readings: readings)
        XCTAssertEqual(s.stats.count, 2)
        XCTAssertEqual(s.stats.average, 20, "(40 + 0) / 2, not diluted by five empty days")
        XCTAssertEqual(s.stats.min, 0, "the quiet day is a real zero")
        XCTAssertNil(s.stats.previousAverage, "a week the strap recorded nothing is no period to compare with")
        XCTAssertEqual(records.values.map { TrendsIntensity.Day($0) }.filter(\.recorded).count, 2,
                       "Trends counts the same two days")
    }

    // MARK: Spec

    @MainActor
    func testStandardSpecs_coverEveryKey_inBaselinesVocabulary() {
        for key in MetricKey.allCases {
            let spec = MetricDetailSpec.standard(key)
            XCTAssertEqual(spec.key, key)
            XCTAssertFalse(spec.title.isEmpty)
            XCTAssertNotNil(spec.badge, "\(key): every detail states its accuracy")
            XCTAssertNotNil(spec.aboutText, "\(key)")
            for word in forbidden {
                XCTAssertFalse(spec.title.lowercased().contains(word), spec.title)
                XCTAssertFalse((spec.aboutText ?? "").lowercased().contains(word), key.rawValue)
            }
        }
        XCTAssertEqual(MetricDetailSpec.standard(.sleepDuration).format(444), "7h 24m")
        XCTAssertEqual(MetricDetailSpec.standard(.steps).format(8_412), "8,412")
        XCTAssertEqual(MetricDetailSpec.standard(.calories).format(2_143), "2,140")
        XCTAssertEqual(MetricDetailSpec.standard(.stressAvg).format(1.44), "1.4")
        XCTAssertNotNil(MetricDetailSpec.standard(.hrv).bandProvider)
        XCTAssertNil(MetricDetailSpec.standard(.steps).bandProvider)
        XCTAssertEqual(MetricDetailSpec.standard(.intensityMinutes).aboutText, BaselineReadouts.IntensityReadout.caveat)
    }
}
