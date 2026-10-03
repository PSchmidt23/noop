import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// The words Home's activity cards print (`TodayActivity.swift`, pure): the Steps card's one line, goal
/// status, spoken hero and goal days; the Calories card's title, split and active-only context; the
/// Stress card's hours, headline and the one sentence against the person's own typical day; the
/// Settings › Activity goals strings; and Trends' goal-day count and calorie bars. None of them may
/// print a vendor's feature name or Baseline's banned words.
final class TodayActivityTests: BaselineEngineTestCase {

    private let forbidden = ["strain", "recovery", "coach", "active zone minutes", "body battery", "stress monitor",
                             "circles", "activity rings"]

    // MARK: Steps

    func testStepsGoalStatus_todayCountsDown_metIsMet_pastDayUnderGoalIsNotScolded() {
        XCTAssertEqual(StepsCardText.goalStatus(steps: 6_240, goal: 8_000, isToday: true), "1,760 to go")
        XCTAssertEqual(StepsCardText.goalStatus(steps: 8_000, goal: 8_000, isToday: true), "Goal met")
        XCTAssertEqual(StepsCardText.goalStatus(steps: 9_100, goal: 8_000, isToday: false), "Goal met")
        XCTAssertNil(StepsCardText.goalStatus(steps: 6_240, goal: 8_000, isToday: false))
        XCTAssertNil(StepsCardText.goalStatus(steps: nil, goal: 8_000, isToday: true))
    }

    func testStepsLine_oneLine_goalThenSevenDayContext_todayNeverJudged() {
        XCTAssertEqual(StepsCardText.line(steps: 6_240, goal: 8_000, average7: 7_480, observed7: 7, isToday: true),
                       "1,760 to go · 7\u{2011}day average 7,480")
        XCTAssertEqual(StepsCardText.line(steps: 9_240, goal: 8_000, average7: 8_000, observed7: 7, isToday: false),
                       "Goal met · +1,240 vs your 7\u{2011}day average")
        XCTAssertEqual(StepsCardText.line(steps: 6_000, goal: 8_000, average7: 6_100, observed7: 7, isToday: false),
                       "On your 7\u{2011}day average")
        XCTAssertEqual(StepsCardText.line(steps: 4_000, goal: 8_000, average7: nil, observed7: 1, isToday: false),
                       "7\u{2011}day average after 2 more days")
        XCTAssertEqual(StepsCardText.line(steps: nil, goal: 8_000, average7: 7_480, observed7: 7, isToday: true),
                       "No steps yet today · 7\u{2011}day average 7,480")
        XCTAssertEqual(StepsCardText.line(steps: nil, goal: 8_000, average7: nil, observed7: 2, isToday: false),
                       "No steps recorded · 7\u{2011}day average after 1 more day")
    }

    func testStepsSpokenAndGoalDays() {
        XCTAssertEqual(StepsCardText.spoken(steps: 6_240, goal: 8_000), "6,240 of 8,000 steps")
        let week: [Double?] = [9_000, nil, 7_999, 8_000, 12_000, 0, 3_000]
        XCTAssertEqual(StepsCardText.goalDays(week, goal: 8_000), 3, "an empty day is not counted against the goal")
        XCTAssertEqual(StepsCardText.weekSummary(week, goal: 8_000), "Goal met on 3 of the last 7 days")
    }

    // MARK: Calories

    func testCaloriesTitle_namesActiveWhenNoRestingEstimate() {
        XCTAssertEqual(CaloriesCardText.title(hasResting: true, isToday: true), "Calories so far")
        XCTAssertEqual(CaloriesCardText.title(hasResting: true, isToday: false), "Calories")
        XCTAssertEqual(CaloriesCardText.title(hasResting: false, isToday: false), "Active calories")
    }

    func testCaloriesSplit_roundedToTen_andNamesAppleHealthOnlyWhenItIsTheSource() {
        XCTAssertEqual(CaloriesCardText.split(resting: 1_717.5, active: 523, activeFromAppleHealth: false, isToday: false),
                       "1,720 resting · 520 active")
        XCTAssertEqual(CaloriesCardText.split(resting: 1_620, active: 520, activeFromAppleHealth: true, isToday: false),
                       "1,620 resting · 520 active · active from Apple Health")
        XCTAssertEqual(CaloriesCardText.split(resting: 858.75, active: nil, activeFromAppleHealth: false, isToday: true),
                       "860 resting · active adds up as the strap records heart rate")
        XCTAssertNil(CaloriesCardText.split(resting: nil, active: 520, activeFromAppleHealth: false, isToday: false),
                     "active alone is the hero; the title already says 'Active calories'")
        XCTAssertNil(CaloriesCardText.split(resting: nil, active: nil, activeFromAppleHealth: false, isToday: false))
    }

    func testCaloriesContext_activeOnly_finishedDaysOnly() {
        XCTAssertEqual(CaloriesCardText.activeContext(active: 700, average30: 520, isToday: false),
                       "Active +180 vs your 30\u{2011}day average")
        XCTAssertEqual(CaloriesCardText.activeContext(active: 525, average30: 520, isToday: false),
                       "Active on your 30\u{2011}day average")
        XCTAssertNil(CaloriesCardText.activeContext(active: 700, average30: 520, isToday: true), "today is partial")
        XCTAssertNil(CaloriesCardText.activeContext(active: 700, average30: nil, isToday: false))
    }

    func testCaloriesBodyLineAndShare() {
        XCTAssertEqual(CaloriesCardText.bodyLine(heightCm: 178, weightKg: 75), "Using 178 cm · 75 kg. Edit in Profile")
        XCTAssertEqual(CaloriesCardText.activeShare(resting: 1_500, active: 500), 0.25, accuracy: 1e-9)
        XCTAssertEqual(CaloriesCardText.activeShare(resting: nil, active: 500), 1)
        XCTAssertEqual(CaloriesCardText.activeShare(resting: 1_500, active: nil), 0)
    }

    // MARK: Stress

    func testStressHours_wholeOrHalf_neverMinutes() {
        XCTAssertEqual(StressCardText.hoursText(2), "2 h")
        XCTAssertEqual(StressCardText.hoursText(2.5), "2.5 h")
        XCTAssertEqual(StressCardText.hoursText(2.4), "2.5 h", "a median is printed to the half hour")
        XCTAssertEqual(StressCardText.headline(elevated: 2, calm: 7, restored: 2, moving: 0),
                       "2 h elevated · 7 h calm · 2 h restored")
        XCTAssertEqual(StressCardText.headline(elevated: 2, calm: 7, restored: 2, moving: 1),
                       "2 h elevated · 7 h calm · 2 h restored · 1 h moving")
    }

    func testStressTotals_needThePersonalLensAndThreeStillHours() {
        XCTAssertTrue(StressCardText.showsTotals(learning: false, scoredHours: 3))
        XCTAssertFalse(StressCardText.showsTotals(learning: false, scoredHours: 2))
        XCTAssertFalse(StressCardText.showsTotals(learning: true, scoredHours: 11), "a day measured against itself is not totalled")
    }

    func testStressSentence_learning_short_today_noTypical_thenAgainstTheTypical() {
        func line(_ elevated: Int, scored: Int = 11, typical: Double? = 2, learning: Int? = nil,
                  today: Bool = false, hour: Int = 20) -> String {
            StressCardText.sentence(elevated: elevated, scoredHours: scored, typical: typical, learningDays: learning,
                                    isToday: today, hour: hour)
        }
        XCTAssertEqual(line(2, learning: 2), "Learning your daytime baseline · 2 of \(Baselines.minNightsSeed) days")
        XCTAssertEqual(line(1, scored: 2), "Only 2 h of still, daytime wear, too little to total")
        XCTAssertEqual(line(4, today: true, hour: 14), "So far today · elevated means 15 bpm or more over your calm heart rate")
        XCTAssertEqual(line(3, typical: nil), "Your typical appears after 5 days of daytime wear")
        XCTAssertEqual(line(3), "About your typical 2 h elevated", "within ±1 h")
        XCTAssertEqual(line(1, typical: 3), "Less elevated time than your typical 3 h")
        XCTAssertEqual(line(5, typical: 3), "More elevated time than your typical 3 h")
        XCTAssertEqual(line(5, typical: 3, today: true, hour: 18), "More elevated time than your typical 3 h",
                       "today is compared from 18:00")
        XCTAssertEqual(StressCardText.floorLine(63.6), "Against your daytime heart-rate floor: 64 bpm (30 days)")
    }

    func testStressCopy_neverAScoreOrABannedWord() {
        let lines = [StressCardText.caveat, StressCardText.headline(elevated: 1, calm: 2, restored: 3, moving: 1),
                     StressCardText.sentence(elevated: 1, scoredHours: 6, typical: 1, learningDays: nil, isToday: false, hour: 20)]
        for l in lines {
            XCTAssertFalse(l.contains("of 3"), l)
            for w in forbidden { XCTAssertFalse(l.lowercased().contains(w), l) }
        }
    }

    // MARK: Settings

    func testActivityGoalsCopy() {
        XCTAssertEqual(SettingsActivityGoalsCard.stepText(8_000), "8,000 steps")
        XCTAssertEqual(SettingsActivityGoalsCard.intensitySubtitle(150), "150 min a week")
        for l in [SettingsActivityGoalsCard.stepLine, CaloriesCardText.caveat, CaloriesCardText.profileAsk,
                  StepsCardText.noSourceToday] {
            for w in forbidden { XCTAssertFalse(l.lowercased().contains(w), l) }
        }
    }

    // MARK: Trends

    private let now = Fixtures.local(2026, 2, 18, hour: 12)
    private func key(_ daysAgo: Int) -> String { Fixtures.dayKey(now, minus: daysAgo) }

    func testTrendsStepsGoalDays_countBarsAtOrOverTheGoal() {
        let readings: [(day: String, value: Double)] = [(key(3), 8_000), (key(2), 7_999), (key(1), 12_000), (key(0), 0)]
        let s = TrendsSeries.build(days: [Fixtures.metric(key(0), hrv: 60)], range: .week, stepReadings: readings,
                                   stepGoal: 8_000, now: now)
        XCTAssertEqual(s.stepsAtGoal, 2)
        XCTAssertEqual(s.stepGoal, 8_000)
        let none = TrendsSeries.build(days: [Fixtures.metric(key(0), hrv: 60)], range: .week, stepReadings: readings, now: now)
        XCTAssertEqual(none.stepsAtGoal, 0, "no goal given, nothing counted")
        XCTAssertNil(none.stepGoal)
    }

    func testTrendsCalories_inRangePositiveDaysOnly() throws {
        let tomorrow = Baselines.cutoffKey(todayKey: key(0), carryDays: -1)
        let readings: [(day: String, value: Double)] = [(key(10), 2_000), (key(2), 2_100), (key(1), 0), (key(0), 2_300),
                                                        (tomorrow, 2_500)]
        let m = TrendsSeries.caloriesMetric(readings: readings, startKey: key(6), todayKey: key(0))
        XCTAssertEqual(m.bars.map(\.id), [key(2), key(0)], "out of range, zero and future days are absent")
        XCTAssertEqual(try XCTUnwrap(m.average), 2_200, accuracy: 1e-9)
        XCTAssertNil(m.inProgressID)
    }

    func testTrendsCalories_todaySoFarIsDrawnButKeptOutOfTheAverage() throws {
        let readings: [(day: String, value: Double)] = [(key(2), 2_300), (key(1), 2_200), (key(0), 600)]
        let m = TrendsSeries.caloriesMetric(readings: readings, startKey: key(6), todayKey: key(0), todayInProgress: true)
        XCTAssertEqual(m.bars.map(\.id), [key(2), key(1), key(0)], "today's bar is still drawn")
        XCTAssertEqual(m.inProgressID, key(0))
        XCTAssertEqual(try XCTUnwrap(m.average), 2_250, accuracy: 1e-9, "a morning's 600 kcal never pulls the average down")

        let onlyToday = TrendsSeries.caloriesMetric(readings: [(key(0), 600)], startKey: key(6), todayKey: key(0),
                                                    todayInProgress: true)
        XCTAssertEqual(onlyToday.bars.count, 1)
        XCTAssertNil(onlyToday.average, "no whole day yet, no average")

        let noToday = TrendsSeries.caloriesMetric(readings: [(key(1), 2_200)], startKey: key(6), todayKey: key(0),
                                                  todayInProgress: true)
        XCTAssertNil(noToday.inProgressID, "no bar for today, nothing in progress")
        XCTAssertEqual(try XCTUnwrap(noToday.average), 2_200, accuracy: 1e-9)
    }
}
