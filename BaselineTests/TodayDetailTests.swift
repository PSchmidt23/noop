import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// Home's detail layer, pure: the VoiceOver hint and opening range per metric, the Heart rate and
/// Intensity cards' one-line captions, the Heart rate card's timed "Latest" label, the Intensity card's
/// visibility rule and its track's spoken label, the sparkline's thinned trace, the intensity week's
/// split line, and the cache's intraday update.
@MainActor
final class TodayDetailTests: XCTestCase {

    private let today = "2026-02-18"
    private let forbidden = ["strain", "recovery", "coach", "active zone", "exercise ring"]

    // MARK: Routes

    /// An unsynced morning: today's HRV tile carries yesterday's night ("Woke …"), so its detail must end
    /// on yesterday, or the 1D page would say "No HRV recorded" under the number Home just showed. Keys
    /// without a carried night, and a day with its own value, keep the selected day.
    func testDetailDay_followsTheNightTheCardShows() {
        let yesterday = Fixtures.key(today, minus: 1)
        let days = (2...11).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 60, rhr: 50) }
            + [Fixtures.metric(yesterday, hrv: 70, rhr: 52)]
        let carried = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        XCTAssertEqual(TodayDetail.detailDay(.hrv, selected: today, snapshot: carried, readiness: .missing), yesterday)
        XCTAssertEqual(TodayDetail.detailDay(.rhr, selected: today, snapshot: carried, readiness: .missing), yesterday)
        XCTAssertEqual(TodayDetail.detailDay(.steps, selected: today, snapshot: carried, readiness: .missing), today)
        XCTAssertEqual(TodayDetail.detailDay(.heartRate, selected: today, snapshot: carried, readiness: .missing), today)
        XCTAssertEqual(TodayDetail.detailDay(.readiness, selected: today, snapshot: carried, readiness: .missing), today)

        let own = TodaySnapshot.build(days: days + [Fixtures.metric(today, hrv: 65, rhr: 51)], nights: [], todayKey: today)
        XCTAssertEqual(TodayDetail.detailDay(.hrv, selected: today, snapshot: own, readiness: .missing), today)
        XCTAssertEqual(TodayDetail.detailDay(.hrv, selected: today, snapshot: nil, readiness: .missing), today)
    }

    func testHint_namesTheMetricInBaselinesVocabulary() {
        XCTAssertEqual(TodayDetail.hint(.hrv), "Opens HRV details")
        XCTAssertEqual(TodayDetail.hint(.rhr), "Opens Resting HR details")
        XCTAssertEqual(TodayDetail.hint(.readiness), "Opens Readiness details")
        XCTAssertEqual(TodayDetail.hint(.sleepDuration), "Opens Sleep details")
        XCTAssertEqual(TodayDetail.hint(.intensityMinutes), "Opens Intensity minutes details")
        XCTAssertEqual(TodayDetail.hint(.heartRate), "Opens Heart rate details")
        for key in MetricKey.allCases {
            let hint = TodayDetail.hint(key).lowercased()
            for word in forbidden { XCTAssertFalse(hint.contains(word), hint) }
        }
    }

    func testInitialRange_intradayKeysOpenOnTheDay_dailyColumnsOnTheWeek() {
        XCTAssertEqual(TodayDetail.initialRange(.heartRate), .day)
        XCTAssertEqual(TodayDetail.initialRange(.intensityMinutes), .day)
        XCTAssertEqual(TodayDetail.initialRange(.stressAvg), .day)
        XCTAssertEqual(TodayDetail.initialRange(.sleepDuration), .day)
        XCTAssertEqual(TodayDetail.initialRange(.effort), .day)
        XCTAssertEqual(TodayDetail.initialRange(.hrv), .week)
        XCTAssertEqual(TodayDetail.initialRange(.steps), .week)
        XCTAssertEqual(TodayDetail.initialRange(.calories), .week)
    }

    func testSpec_keepsTheStandardSpecAndAddsTheDayViewsHomeOwns() {
        for key in MetricKey.allCases {
            let spec = TodayDetail.spec(key)
            let standard = MetricDetailSpec.standard(key)
            XCTAssertEqual(spec.title, standard.title)
            XCTAssertEqual(spec.unit, standard.unit)
            let custom: Bool = [.sleepDuration, .effort, .stressAvg, .intensityMinutes, .steps, .calories].contains(key)
            XCTAssertEqual(spec.dayView != nil, custom, "\(key)")
            // Stress and Calories: the day view IS the 1D page (no hero repeating, or contradicting, it).
            XCTAssertEqual(spec.dayViewReplacesHero, [.stressAvg, .calories].contains(key), "\(key)")
        }
    }

    // MARK: Heart rate card

    private func trace(points: Int, bpm: Double = 70, lo: Double = 48, hi: Double = 162, covered: Int = 600) -> BaselineReadouts.IntradayHeartRate {
        let start = BaselineReadouts.localMidnight(of: today)!
        let list = (0..<points).map { i in
            BaselineReadouts.IntradayHeartRate.Point(id: i, date: start.addingTimeInterval(Double(i) * 60),
                                                     bpm: bpm + Double(i % 5), minBpm: bpm - 2, maxBpm: bpm + 6, conf: 1)
        }
        return BaselineReadouts.IntradayHeartRate(day: today, dayStart: start, dayEnd: start.addingTimeInterval(86_400),
                                                  points: list, sleep: [], workouts: [], minBpm: lo, maxBpm: hi,
                                                  avgBpm: bpm, coveredMinutes: covered)
    }

    func testHeartRateCaption_saysTheAverageOnceAndTheCoverageOnlyForAPartialDay() {
        XCTAssertEqual(HeartRateCard.caption(trace(points: 10, bpm: 71, covered: 600), isToday: true), "Average 71 bpm through the day")
        XCTAssertEqual(HeartRateCard.caption(trace(points: 10, bpm: 71, covered: 190), isToday: true),
                       "Average 71 bpm over 3h 10m of heart rate so far")
        XCTAssertEqual(HeartRateCard.caption(trace(points: 10, bpm: 71, covered: 190), isToday: false),
                       "Average 71 bpm over 3h 10m of heart rate")
    }

    func testLatestLabel_todayWearsTheNewestBucketsClockTime_aPastDaySaysLast() {
        let t = trace(points: 10)
        let time = t.points.last!.date.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(HeartRateCard.latestLabel(t, isToday: true), "Latest · \(time)",
                       "a strap off the wrist since the afternoon is never read as current")
        XCTAssertEqual(HeartRateCard.latestLabel(t, isToday: false), "Last")
        XCTAssertEqual(HeartRateCard.latestLabel(trace(points: 0), isToday: true), "Latest")
    }

    func testCompactTrace_thinsThePointsAndDropsTheSpans_keepingTheDaysExtremes() {
        let full = trace(points: 1_440)
        let compact = HeartRateCard.compact(full, maxPoints: 360)
        XCTAssertLessThanOrEqual(compact.points.count, 360)
        XCTAssertEqual(compact.points.first?.id, 0)
        XCTAssertEqual(compact.minBpm, 48)
        XCTAssertEqual(compact.maxBpm, 162)
        XCTAssertEqual(compact.coveredMinutes, full.coveredMinutes)
        XCTAssertTrue(compact.sleep.isEmpty && compact.workouts.isEmpty)
        let small = trace(points: 100)
        XCTAssertEqual(HeartRateCard.compact(small).points.count, 100, "a trace that fits is kept as is")
    }

    // MARK: Intensity card

    private func readout(moderate: Int, vigorous: Int, scored: Int, basis: IntensityMinutes.Basis = .hrr(restingHr: 52, hrMax: 182),
                         week: [Int]? = nil, goal: Int = 150) -> BaselineReadouts.IntensityReadout {
        BaselineReadouts.IntensityReadout(day: today, moderateMin: moderate, vigorousMin: vigorous,
                                          weekStart: Fixtures.key(today, minus: 2),
                                          weekDays: week ?? [40, 49, moderate + 2 * vigorous], weekGoal: goal,
                                          basis: basis, scoredMinutes: scored)
    }

    func testIntensityCaption_splitForACreditedDay_andTheReasonForNone() {
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 15, vigorous: 8, scored: 900), isToday: true),
                       "15 moderate · 8 vigorous, counted double")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 15, vigorous: 8, scored: 100), isToday: true),
                       "15 moderate · 8 vigorous, counted double", "today is never called a partial day")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 15, vigorous: 8, scored: 100), isToday: false),
                       "15 moderate · 8 vigorous, counted double · partial day")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 20, vigorous: 0, scored: 0, basis: .workoutsOnly), isToday: false),
                       "20 moderate · 0 vigorous, counted double · from workouts only")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 0, vigorous: 0, scored: 30), isToday: true),
                       "Builds through the day as the strap records moderate and vigorous minutes.")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 0, vigorous: 0, scored: 0), isToday: false),
                       "No heart rate recorded on this day.")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 0, vigorous: 0, scored: 100), isToday: false),
                       "No minutes at moderate intensity or above · partial day")
        XCTAssertEqual(IntensityCard.caption(readout(moderate: 0, vigorous: 0, scored: 900), isToday: false),
                       "No minutes at moderate intensity or above.")
    }

    func testIntensityCardVisibility_onlyWithAReading_orTodaysAgeAsk_neverZerosOnAMorning() {
        let scored = readout(moderate: 0, vigorous: 0, scored: 300)
        let empty = readout(moderate: 0, vigorous: 0, scored: 0)
        let needsAge = readout(moderate: 0, vigorous: 0, scored: 300, basis: .needsAge)
        let imported = readout(moderate: 20, vigorous: 0, scored: 0, basis: .workoutsOnly)
        let credited = readout(moderate: 15, vigorous: 0, scored: 90, week: [15])
        // Monday morning: overnight heart rate scored, nothing credited all week.
        let mondayMorning = readout(moderate: 0, vigorous: 0, scored: 420, week: [0])
        // Later in the week, today still at zero: the week's track is a reading.
        let weekSoFar = readout(moderate: 0, vigorous: 0, scored: 420, week: [40, 49, 0])

        XCTAssertFalse(TodayScreen.showsIntensity(mondayMorning, isToday: true, isPaired: true),
                       "a paired morning with nothing credited all week has no '0 min today · 0 / 150' card")
        XCTAssertTrue(TodayScreen.showsIntensity(weekSoFar, isToday: true, isPaired: true), "the week's track is a reading")
        XCTAssertTrue(TodayScreen.showsIntensity(weekSoFar, isToday: true, isPaired: false))
        XCTAssertTrue(TodayScreen.showsIntensity(credited, isToday: true, isPaired: true))
        XCTAssertTrue(TodayScreen.showsIntensity(credited, isToday: true, isPaired: false))
        XCTAssertTrue(TodayScreen.showsIntensity(needsAge, isToday: true, isPaired: true), "today asks for the age")
        XCTAssertFalse(TodayScreen.showsIntensity(needsAge, isToday: true, isPaired: false))
        XCTAssertTrue(TodayScreen.showsIntensity(scored, isToday: false, isPaired: true), "a past day's zero is a reading")
        XCTAssertFalse(TodayScreen.showsIntensity(mondayMorning, isToday: true, isPaired: false))
        XCTAssertFalse(TodayScreen.showsIntensity(readout(moderate: 0, vigorous: 0, scored: 0, week: [0]), isToday: false, isPaired: true))
        XCTAssertFalse(TodayScreen.showsIntensity(needsAge, isToday: false, isPaired: true))
        XCTAssertTrue(TodayScreen.showsIntensity(imported, isToday: false, isPaired: false))
        XCTAssertTrue(TodayScreen.showsIntensity(empty, isToday: true, isPaired: true), "the helper's week [40, 49, 0] has minutes")
    }

    func testIntensityTrack_readsTheWeekInWords_neverTheSlash() {
        let r = readout(moderate: 15, vigorous: 4, scored: 900, week: [40, 49, 23])
        XCTAssertEqual(r.weekText, "112 / 150 this week")
        XCTAssertEqual(IntensityTrack.spokenLabel(r), "112 of 150 minutes this week")
        XCTAssertFalse(IntensityTrack.spokenLabel(r).contains("/"))
    }

    func testIntensityWeekSplitLine_namesTheDayOnce() {
        let r = readout(moderate: 38, vigorous: 37, scored: 900)
        XCTAssertEqual(TodayIntensityWeekView.splitLine(r), "\(TodayFormat.dayLabel(today)): 38 moderate · 37 vigorous, counted double")
        let none = readout(moderate: 0, vigorous: 0, scored: 900)
        XCTAssertNil(TodayIntensityWeekView.splitLine(none), "a day with nothing credited is the hero's sentence, said once")
    }

    // MARK: Cache

    func testCacheEntry_updateIntradayReplacesOnlyTheTraceAndTheMinutes() {
        let days = (1...10).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 60, rhr: 50) }
            + [Fixtures.metric(today, hrv: 61, rhr: 51)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let cache = HomeDayCache()
        let k = HomeDayCache.Key(dayKey: today, logicalKey: today, refreshSeq: 1, dataSource: "", horizon: 90,
                                 intensityGoal: 150, intensityHRmax: 182)
        cache.store(HomeDayCache.Entry(snapshot: snap, signals: nil, signalsJournalSeq: 0, workouts: [],
                                       progressHeadline: "steady"), for: k)
        XCTAssertNil(cache.entry(for: k)?.heartRate)
        XCTAssertNil(cache.entry(for: k)?.intensity)

        cache.updateIntraday(heartRate: trace(points: 3), intensity: readout(moderate: 10, vigorous: 5, scored: 400), for: k)

        let hit = cache.entry(for: k)
        XCTAssertEqual(hit?.heartRate?.points.count, 3)
        XCTAssertEqual(hit?.intensity?.creditedToday, 20)
        XCTAssertEqual(hit?.progressHeadline, "steady", "the rest of the entry is untouched")
        XCTAssertNil(cache.entry(for: HomeDayCache.Key(dayKey: today, logicalKey: today, refreshSeq: 1, dataSource: "",
                                                       horizon: 90, intensityGoal: 200, intensityHRmax: 182)),
                     "a new weekly goal is a new key")
        XCTAssertNil(cache.entry(for: HomeDayCache.Key(dayKey: today, logicalKey: today, refreshSeq: 1, dataSource: "",
                                                       horizon: 90, intensityGoal: 150, intensityHRmax: 0)),
                     "a profile that stopped being usable is a new key")
        cache.updateIntraday(heartRate: nil, intensity: nil, for: HomeDayCache.Key(dayKey: "2000-01-01", logicalKey: "2000-01-01",
                                                                                   refreshSeq: 1, dataSource: "", horizon: 90))
        XCTAssertEqual(cache.count, 1, "an unknown key is a no-op")
    }
}
