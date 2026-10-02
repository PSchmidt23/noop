import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// Intensity minutes as a WEEKLY TOTAL against the goal (`MetricKey.sumsPerBucket`), never a mean of the
/// days that happened to record: the one week builder (`BaselineRangeSeries.weekTotals`), a sum series'
/// weeks and days (`MetricSums`), the detail's hero per range (`metricSumHero`), the chart's caption and
/// VoiceOver sentence, and Home's card, Trends' card and the detail's hero agreeing on one week.
/// 2026-02-18 is a Wednesday; its week starts on Monday 2026-02-16. Day keys are literals or pure key
/// math, so nothing depends on the machine's zone.
@MainActor
final class IntensityWeeklyTests: XCTestCase {

    private let today = "2026-02-18"
    private let monday = "2026-02-16"
    private let goal = MetricGoal(value: 150, period: .week)
    private let hrr = IntensityMinutes.Basis.hrr(restingHr: 52, hrMax: 182)
    private let forbidden = ["strain", "recovery", "coach", "active zone", "exercise ring"]
    private let whole: (Double) -> String = { "\(Int($0.rounded()))" }

    private func key(_ back: Int) -> String { Fixtures.key(today, minus: back) }

    /// Day facts as the day store hands them to the range layer (`intradayValues`): one entry per
    /// recorded day, credited = moderate + 2 · vigorous, with the split and the basis.
    private func facts(_ days: [(String, Int, Int)]) -> BaselineReadouts.IntradayDayValues {
        var v = BaselineReadouts.IntradayDayValues()
        for (day, moderate, vigorous) in days {
            v.intensityMinutes[day] = Double(moderate + 2 * vigorous)
            v.intensityParts[day] = (moderate, vigorous)
            v.intensityBasis[day] = hrr
        }
        return v
    }

    /// The series `MetricDetailScreen` draws, through the same readings the repository accessor builds.
    private func series(_ range: MetricRange, _ values: BaselineReadouts.IntradayDayValues, end: String? = nil) -> MetricSeries {
        let readings = BaselineReadouts.metricReadings(key: .intensityMinutes, days: [], intraday: values)
        return BaselineReadouts.metricSeries(key: .intensityMinutes, range: range, endKey: end ?? today,
                                             readings: readings, dayFacts: values)
    }

    private func hero(_ s: MetricSeries, isToday: Bool = true) -> BaselineReadouts.MetricSumHero {
        BaselineReadouts.metricSumHero(series: s, goal: goal, noun: "intensity minutes", unit: "min",
                                       format: whole, isToday: isToday)
    }

    /// A persisted day as `IntradayDayStore` keeps it, scored on heart-rate reserve.
    private func record(_ day: String, moderate: Int, vigorous: Int, scored: Int = 600) -> IntradayDayRecord {
        IntradayDayRecord(day: day, version: IntradayDayStore.version, fingerprintCount: scored, fingerprintMaxTs: 0,
                          fingerprintSum: 0, thresholdSignature: "hrr:52:182|b3g1", storeIdentity: "",
                          basisTag: "hrr", restingHr: 52, hrMaxBpm: 182, moderateMin: moderate, vigorousMin: vigorous,
                          scoredMinutes: scored, bpmMin: 50, bpmAvg: 80, bpmMax: 150, stressMean: nil,
                          stressComputed: false, computedAt: 0)
    }

    // MARK: Keys, windows, goal

    func testSumsPerBucket_isIntensityOnly_andItsLongRangesAreWholeWeeks() {
        XCTAssertEqual(MetricKey.allCases.filter(\.sumsPerBucket), [.intensityMinutes])
        XCTAssertFalse(MetricKey.steps.sumsPerBucket, "steps stay a per-day mean: their norm is a day")
        XCTAssertEqual(MetricRange.allCases.map { $0.bucket(for: .intensityMinutes) }, [.day, .day, .week, .week])
        XCTAssertEqual(MetricRange.allCases.map { $0.bucket(for: .steps) }, [.day, .day, .day, .week])
        XCTAssertEqual(BaselineReadouts.metricWindow(key: .intensityMinutes, range: .week, endKey: today).startKey, key(6))
        XCTAssertEqual(BaselineReadouts.metricWindow(key: .intensityMinutes, range: .fourWeeks, endKey: today).startKey,
                       "2026-01-26", "four Monday weeks, the last the one today falls in")
        XCTAssertEqual(BaselineReadouts.metricWindow(key: .intensityMinutes, range: .year, endKey: today).startKey,
                       "2025-02-24", "fifty-two Monday weeks")
        XCTAssertEqual(BaselineReadouts.metricWindow(key: .steps, range: .fourWeeks, endKey: today).startKey, key(27))
        XCTAssertEqual(goal.perDay, 150.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(MetricGoal(value: 10_000, period: .day).perWeek, 70_000)
    }

    func testSpecGoal_isTheLiveWeeklyIntensityGoal_andNoOtherKeyHasOne() throws {
        let g = try XCTUnwrap(TodayDetail.spec(.intensityMinutes).goal?())
        XCTAssertEqual(g.period, .week)
        XCTAssertEqual(g.value, Double(IntensityMinutes.goal()))
        for key in MetricKey.allCases where key != .intensityMinutes {
            XCTAssertNil(MetricDetailSpec.standard(key).goal, "\(key)")
        }
    }

    // MARK: The week builder

    func testWeekTotals_aScoredZeroIsZero_aMissingDayIsNil_andDaysAfterTheEndAreEmpty() throws {
        let values = [MetricDayValue(day: monday, value: 40),
                      MetricDayValue(day: key(1), value: 0),               // worn, nothing credited
                      MetricDayValue(day: "2026-02-19", value: 99),       // tomorrow: never counted
                      MetricDayValue(day: "2026-02-15", value: 25)]       // last Sunday
        let weeks = BaselineRangeSeries.weekTotals(values, from: today, to: today)
        XCTAssertEqual(weeks.count, 1)
        let w = try XCTUnwrap(weeks.first)
        XCTAssertEqual(w.id, monday)
        XCTAssertEqual(w.date, BaselineReadouts.localMidnight(of: monday))
        XCTAssertEqual(w.days, [40, 0, nil, nil, nil, nil, nil], "Tuesday is a recorded 0; Wednesday has no reading yet")
        XCTAssertEqual(w.total, 40)
        XCTAssertEqual(w.recordedDays, 2)
        XCTAssertEqual(w.activeDays, 1)
        XCTAssertTrue(w.inProgress)
        XCTAssertTrue(w.hasData)

        let two = BaselineRangeSeries.weekTotals(values, from: "2026-02-15", to: today)
        XCTAssertEqual(two.map(\.id), ["2026-02-09", monday])
        XCTAssertEqual(two.map(\.total), [25, 40])
        XCTAssertEqual(two.map(\.inProgress), [false, true])
        XCTAssertTrue(BaselineRangeSeries.weekTotals(values, from: today, to: "2026-02-13").isEmpty, "reversed: no weeks")
    }

    func testRecords_aWornQuietDayIsAZeroReading_aStrapOffDayIsMissing() throws {
        let t = try XCTUnwrap(IntensityMinutes.Thresholds.karvonen(restingHr: 52, hrMax: 182))
        let t0 = Int(try XCTUnwrap(BaselineReadouts.localMidnight(of: key(1))).timeIntervalSince1970) + 9 * 3_600
        let desk = (0..<300).map { HRBucket(ts: t0 + $0 * 60, bpm: 70, minBpm: 66, maxBpm: 74) }
        let records = [key(1): IntradayDayStore.compute(day: key(1), buckets: desk, thresholds: t),
                       monday: IntradayDayStore.compute(day: monday, buckets: [], thresholds: t)]
        let s = series(.week, BaselineReadouts.intradayValues(records))
        XCTAssertEqual(s.sums?.thisWeek?.days, [nil, 0, nil, nil, nil, nil, nil],
                       "Monday (strap off) is missing, Tuesday (worn, under the moderate line) is 0")
        XCTAssertEqual(hero(s).cellsText, "This week 0 of 150 min · Days active 0 of 7")
        XCTAssertEqual(hero(s).sentence, "No moderate or vigorous minutes this week.")
    }

    func testMondayRollover_startsTheWeekFromZero_whateverTheLocale() {
        let sunday = "2026-02-22", nextMonday = "2026-02-23"
        let values = [MetricDayValue(day: monday, value: 100), MetricDayValue(day: sunday, value: 60),
                      MetricDayValue(day: nextMonday, value: 15)]
        let closed = BaselineRangeSeries.weekTotals(values, from: sunday, to: sunday)
        XCTAssertEqual(closed.map(\.total), [160])
        XCTAssertEqual(closed.map(\.inProgress), [false], "Sunday closes the week")
        let rolled = BaselineRangeSeries.weekTotals(values, from: nextMonday, to: nextMonday)
        XCTAssertEqual(rolled.map(\.id), [nextMonday])
        XCTAssertEqual(rolled.map(\.total), [15])
        XCTAssertEqual(rolled.map(\.inProgress), [true])
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.firstWeekday = 1
        XCTAssertEqual(BaselineRangeSeries.weekTotals(values, from: sunday, to: sunday, calendar: sundayFirst).map(\.id),
                       [monday], "a locale that starts its week on Sunday changes nothing")

        // The detail's "This week" and Home's track roll over on the same Monday.
        let v = facts([(monday, 100, 0), (sunday, 60, 0), (nextMonday, 15, 0)])
        XCTAssertEqual(hero(series(.week, v, end: sunday)).cells.first?.value, "160")
        XCTAssertEqual(hero(series(.week, v, end: nextMonday)).cells.first,
                       .init(label: "This week", value: "15", unit: "of 150 min"))
        let home = BaselineReadouts.intensity(for: nextMonday, dayRecords: [nextMonday: record(nextMonday, moderate: 15, vigorous: 0),
                                                                         sunday: record(sunday, moderate: 60, vigorous: 0)],
                                              goal: 150, fallbackBasis: .needsAge)
        XCTAssertEqual(home.weekDays, [15])
        XCTAssertEqual(home.weekText, "15 / 150 this week")
    }

    // MARK: The detail's hero per range

    func testSevenDays_thisWeekAgainstTheGoal_daysActive_andThisWeeksSplit() throws {
        // Thu 12 … Sun 15 belong to last week (Sat 14: strap off); Monday → today make "This week".
        let v = facts([("2026-02-12", 15, 0), ("2026-02-13", 0, 0), ("2026-02-15", 5, 10),
                       (monday, 20, 10), (key(1), 0, 0), (today, 18, 27)])
        let s = series(.week, v)
        XCTAssertEqual(s.bucket, .day)
        XCTAssertEqual(s.points.map(\.id), ["2026-02-12", "2026-02-13", "2026-02-15", monday, key(1), today],
                       "one bar per recorded day, a recorded zero included; the strap-off Saturday has none")
        XCTAssertEqual(s.points.map(\.value), [15, 0, 25, 40, 0, 72])
        let h = hero(s)
        XCTAssertEqual(h.cells, [.init(label: "This week", value: "112", unit: "of 150 min"),
                                 .init(label: "Days active", value: "4", unit: "of 7")])
        XCTAssertEqual(h.cellsText, "This week 112 of 150 min · Days active 4 of 7")
        XCTAssertEqual(h.sentence, "38 moderate · 37 vigorous, counted double", "this week's split: 38 + 2 × 37 = 112")
        XCTAssertEqual(h.footnote, "40 % / 60 % of your heart-rate reserve (resting 52, max 182)")
        XCTAssertFalse(h.cellsText.contains("Average"), "no mean of the recorded days")
        XCTAssertEqual(MetricDetailScreen.chartCaption(s), "Lighter bars are last week; this week starts on Monday.")
        XCTAssertEqual(BaselineReadouts.metricSumChartSummary(series: s, goal: goal, name: "Intensity minutes", unit: "min", format: whole),
                       "Intensity minutes, last 7 days: 6 days recorded, 4 active, highest 72 min; this week 112 of 150 min; daily pace 21 min.")

        // On a Sunday the seven bars are the week itself: nothing lighter, nothing to caption.
        let sunday = series(.week, facts([(monday, 20, 10), ("2026-02-22", 30, 0)]), end: "2026-02-22")
        XCTAssertNil(MetricDetailScreen.chartCaption(sunday))
        XCTAssertEqual(hero(sunday, isToday: false).cellsText, "This week 70 of 150 min · Days active 2 of 7")
    }

    func testFourWeeks_weeksAtGoalAndTheAverageFinishedWeek() throws {
        // Jan 26: 160 · Feb 2: 83 · Feb 9: exactly 150 (a scored zero on Wednesday) · Feb 16, in progress: 112.
        let v = facts([("2026-01-26", 40, 30), ("2026-01-30", 40, 10),
                       ("2026-02-03", 33, 25),
                       ("2026-02-09", 50, 0), ("2026-02-11", 0, 0), ("2026-02-15", 50, 25),
                       (monday, 20, 10), (key(1), 0, 0), (today, 18, 27)])
        let s = series(.fourWeeks, v)
        XCTAssertEqual(s.startKey, "2026-01-26")
        XCTAssertEqual(s.bucket, .week)
        XCTAssertEqual(s.points.map(\.id), ["2026-01-26", "2026-02-02", "2026-02-09", monday])
        XCTAssertEqual(s.points.map(\.value), [160, 83, 150, 112], "each bar is the week's TOTAL")
        XCTAssertEqual(s.points.map(\.n), [2, 1, 3, 3])
        XCTAssertTrue(s.lastBucketPartial)
        let sums = try XCTUnwrap(s.sums)
        XCTAssertEqual(sums.weeksAtGoal(goal), 2, "160 and exactly 150; 112 so far has not reached it")
        XCTAssertEqual(try XCTUnwrap(sums.averageWeek), 131, accuracy: 1e-9, "(160 + 83 + 150) / 3: the half-built week is left out")
        let h = hero(s)
        XCTAssertEqual(h.cellsText, "Weeks at goal 2 of 4 · Average week 131 min")
        XCTAssertEqual(h.sentence, "Over 4 weeks: 251 moderate · 127 vigorous, counted double")
        XCTAssertEqual(h.footnote, hrr.caption)
        XCTAssertEqual(MetricDetailScreen.chartCaption(s), "The lighter bar is this week, still in progress.")
        XCTAssertEqual(BaselineReadouts.metricSumChartSummary(series: s, goal: goal, name: "Intensity minutes", unit: "min", format: whole),
                       "Intensity minutes, last 4 weeks: 4 weeks recorded, 2 at the goal of 150 min; average week 131 min; this week 112 min so far.")

        // The week in progress counts once it has reached the goal: a met goal stays met.
        var met = v
        met.intensityMinutes[today] = 120
        met.intensityParts[today] = (0, 60)
        XCTAssertEqual(hero(series(.fourWeeks, met)).cells.first, .init(label: "Weeks at goal", value: "3", unit: "of 4"))

        // A week with no reading at all is missing: no bar, not a zero week, not a week judged.
        var gap = v
        gap.intensityMinutes["2026-02-03"] = nil
        gap.intensityParts["2026-02-03"] = nil
        gap.intensityBasis["2026-02-03"] = nil
        let g = series(.fourWeeks, gap)
        XCTAssertEqual(g.points.map(\.id), ["2026-01-26", "2026-02-09", monday])
        XCTAssertEqual(hero(g).cellsText, "Weeks at goal 2 of 3 · Average week 155 min")
        XCTAssertEqual(hero(g).sentence, "Over 3 weeks: 218 moderate · 102 vigorous, counted double",
                       "the split speaks for the weeks with data, the denominator above")

        // On the Sunday the fourth week is finished and judged like the others.
        let sunday = series(.fourWeeks, v, end: "2026-02-22")
        XCTAssertFalse(sunday.lastBucketPartial)
        XCTAssertNil(MetricDetailScreen.chartCaption(sunday))
        XCTAssertEqual(hero(sunday, isToday: false).cellsText, "Weeks at goal 2 of 4 · Average week 126 min")
    }

    func testYear_fiftyTwoWeeklyTotals() throws {
        // One day a week, on its Monday: every third finished week 180, the rest 90; this week 112 so far.
        var days: [(String, Int, Int)] = []
        for i in 0..<51 {
            days.append((Baselines.cutoffKey(todayKey: "2025-02-24", carryDays: -7 * i), i % 3 == 0 ? 180 : 90, 0))
        }
        days.append((monday, 112, 0))
        let s = series(.year, facts(days))
        XCTAssertEqual(s.startKey, "2025-02-24")
        XCTAssertEqual(s.bucket, .week)
        XCTAssertEqual(s.points.count, 52)
        XCTAssertEqual(s.points.last?.id, monday)
        XCTAssertEqual(s.points.last?.value, 112)
        XCTAssertTrue(s.lastBucketPartial)
        let h = hero(s)
        XCTAssertEqual(h.cellsText, "Weeks at goal 17 of 52 · Average week 120 min")
        XCTAssertEqual(h.sentence, "Over 52 weeks: 6232 moderate · 0 vigorous, counted double")
        for word in forbidden {
            XCTAssertFalse(h.cellsText.lowercased().contains(word))
            XCTAssertFalse(h.sentence.lowercased().contains(word))
        }
    }

    func testEmptyWindow_isOneSentence_noCellsOfDashes() {
        let s = series(.fourWeeks, facts([]))
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(hero(s).cells, [])
        XCTAssertEqual(hero(s).sentence, "No days with intensity minutes in the last 4 weeks.")
        XCTAssertNil(hero(s).footnote)
    }

    func testOneDay_aScoredZeroIsZero_andOnlyAFinishedDayWithNoHeartRateIsADash() {
        let yesterday = key(1)
        // Today scored with nothing credited: the 0 Home's card prints ("0 min today").
        let zero = series(.day, facts([(yesterday, 20, 10), (today, 0, 0)]))
        XCTAssertEqual(hero(zero).cellsText, "This day 0 min · Day before 40 min")
        XCTAssertEqual(hero(zero).sentence, "No moderate or vigorous minutes today.")
        XCTAssertNil(hero(zero).footnote, "the 1D week card under the hero prints the basis")
        XCTAssertEqual(hero(zero, isToday: false).sentence, "No moderate or vigorous minutes on this day.")
        // Today before its first minute is banked counts from 0, as Home's card does.
        let notYet = series(.day, facts([(yesterday, 20, 10)]))
        XCTAssertEqual(hero(notYet).cellsText, "This day 0 min · Day before 40 min")
        XCTAssertEqual(hero(notYet).sentence, "No moderate or vigorous minutes today.")
        // A finished day without heart rate (or workout credit) is the only dash, and it stands alone.
        XCTAssertEqual(hero(notYet, isToday: false).cellsText, "This day – · Day before 40 min")
        XCTAssertEqual(hero(notYet, isToday: false).sentence, "No heart rate recorded on this day.")
        // A credited day: the change against the day before, never the day's number again.
        let credited = series(.day, facts([(yesterday, 20, 10), (today, 13, 5)]))
        XCTAssertEqual(hero(credited).cellsText, "This day 23 min · Day before 40 min")
        XCTAssertEqual(hero(credited).sentence, "\u{2212}17 min vs the day before.")
    }

    // MARK: One week, three readouts

    /// Home's Intensity card (its track), Trends' Intensity card ("This week") and the detail's 7D hero
    /// read one fixture week through their production adapters and print the same total: all three sum
    /// through `BaselineRangeSeries.weekTotals`. Home's hero ("72 min today") is the detail's 1D "This day".
    func testHomeTrendsAndTheDetail_printTheSameWeek() throws {
        let records: [String: IntradayDayRecord] = [
            "2026-02-13": record("2026-02-13", moderate: 30, vigorous: 30),   // last Friday: not this week
            "2026-02-15": record("2026-02-15", moderate: 10, vigorous: 0),
            monday: record(monday, moderate: 20, vigorous: 10),
            key(1): record(key(1), moderate: 0, vigorous: 0),                 // worn, nothing credited
            today: record(today, moderate: 18, vigorous: 27),
        ]
        // Home: `BaselineReadouts.intensity(_ repo:…)` over the same records.
        let home = BaselineReadouts.intensity(for: today, dayRecords: records, goal: 150, fallbackBasis: .needsAge)
        // Trends: the 7-day card, as `TrendsScreen` builds it.
        let trendsStart = Baselines.cutoffKey(todayKey: today, carryDays: TrendsRange.week.days - 1)
        let trends = TrendsIntensity.build(days: records.values.map { TrendsIntensity.Day($0) },
                                           startKey: trendsStart, todayKey: today, goal: 150)
        // The detail: 7D and 1D, as `MetricDetailScreen` loads them.
        let values = BaselineReadouts.intradayValues(records)
        let week = hero(series(.week, values))
        let day = hero(series(.day, values))

        XCTAssertEqual(home.weekCredited, 112)
        XCTAssertEqual(home.weekText, "112 / 150 this week")
        XCTAssertEqual(IntensityTrack.spokenLabel(home), "112 of 150 minutes this week")
        let card = TrendIntensityCard.thisWeekCell(trends)
        XCTAssertEqual(card.value, "112")
        XCTAssertEqual(card.unit, "of 150 min")
        let detail = try XCTUnwrap(week.cells.first)
        XCTAssertEqual(detail, .init(label: "This week", value: "112", unit: "of 150 min"))
        XCTAssertEqual(detail.value, card.value)
        XCTAssertEqual(detail.unit, card.unit)
        XCTAssertEqual(detail.value, "\(home.weekCredited)")
        XCTAssertEqual(day.cells.first?.value, "\(home.creditedToday)", "Home's \(home.creditedToday) min today")
        XCTAssertEqual(week.sentence, "38 moderate · 37 vigorous, counted double")
        XCTAssertEqual(home.splitText, "18 moderate · 27 vigorous, counted double", "the same spelling for the day")
        for text in [home.weekText, week.cellsText, week.sentence, day.cellsText, day.sentence] {
            for word in forbidden { XCTAssertFalse(text.lowercased().contains(word), text) }
        }
    }
}
