import XCTest
import WhoopStore
import WhoopProtocol
import StrandAnalytics
@testable import Baseline

/// The activity readouts (`Research/ACTIVITY_METRICS.md`, "Implementable spec"), pure: where a day's steps
/// came from and the step goal, the Mifflin–St Jeor resting figure and the Calories split (strap and
/// Apple Health never summed), the Stress hour states on NOOP's own scorer and the 14-day typical, and
/// the behaviour aggregate Friends uploads.
@MainActor
final class ActivityReadoutsTests: XCTestCase {

    private let today = "2026-02-18"
    private func key(_ back: Int) -> String { Fixtures.key(today, minus: back) }

    // MARK: Steps: source

    func testStepSource_fromTheResolverPoint() {
        XCTAssertEqual(StepSource.of(source: "my-whoop-noop", key: "steps"), .strap, "the counter's daily steps")
        XCTAssertEqual(StepSource.of(source: "baseline-sample-noop", key: "steps"), .strap, "any computed sibling")
        XCTAssertEqual(StepSource.of(source: Repository.appleHealthSource, key: "steps"), .phone)
        XCTAssertEqual(StepSource.of(source: "my-whoop", key: "steps_est"), .estimate)
        XCTAssertEqual(StepSource.of(source: "my-whoop", key: "steps"), .imported, "a WHOOP export's column")
        XCTAssertTrue(StepSource.strap.isCounted)
        XCTAssertTrue(StepSource.phone.isCounted)
        XCTAssertFalse(StepSource.estimate.isCounted)
        XCTAssertFalse(StepSource.imported.isCounted)
    }

    /// One source per day, the first resolver point wins, never summed; a day only the funnel filled is an
    /// import; imports-only keeps the phone's points alone.
    func testStepSourcedReadings_oneSourcePerDay_neverSummed() {
        let resolved = [
            ResolvedMetricPoint(day: key(2), value: 6_000, source: "my-whoop-noop", sourceKey: "steps"),
            ResolvedMetricPoint(day: key(2), value: 9_000, source: Repository.appleHealthSource, sourceKey: "steps"),
            ResolvedMetricPoint(day: key(1), value: 7_100, source: Repository.appleHealthSource, sourceKey: "steps"),
            ResolvedMetricPoint(day: today, value: 4_000, source: "my-whoop", sourceKey: "steps_est"),
        ]
        let funnel = [(day: key(3), value: 5_000.0), (day: key(2), value: 1.0)]
        let r = BaselineReadouts.stepSourcedReadings(mode: .strapFirst, resolved: resolved, funnel: funnel,
                                                     from: key(5), to: today)
        XCTAssertEqual(r.map(\.day), [key(3), key(2), key(1), today])
        XCTAssertEqual(r.map(\.value), [5_000, 6_000, 7_100, 4_000], "the strap's count, never strap + phone")
        XCTAssertEqual(r.map(\.source), [.imported, .strap, .phone, .estimate])

        let phoneOnly = BaselineReadouts.stepSourcedReadings(mode: .importOnly, resolved: resolved, funnel: [],
                                                             from: key(5), to: today)
        XCTAssertEqual(phoneOnly.map(\.source), [.phone, .phone])
        XCTAssertEqual(phoneOnly.map(\.value), [9_000, 7_100])
    }

    func testStepsReadout_carriesTheDaysSource_andItsState() {
        let readings = [(day: key(1), value: 7_000.0), (day: today, value: 0.0)]
        let sources: [String: StepSource] = [key(1): .phone, today: .strap]
        let r = BaselineReadouts.steps(for: today, readings: readings, sources: sources)
        XCTAssertEqual(r.source, .strap)
        XCTAssertEqual(r.state, .zero, "a zero the strap recorded is a reading")
        XCTAssertEqual(r.sources[key(1)], .phone)

        let past = BaselineReadouts.steps(for: key(1), readings: readings, sources: sources)
        XCTAssertEqual(past.state, .counted)
        XCTAssertEqual(past.source, .phone)

        let none = BaselineReadouts.steps(for: key(4), readings: readings, sources: sources)
        XCTAssertEqual(none.state, .noSource)
        XCTAssertNil(none.source, "no count, no source")
        XCTAssertEqual(none.steps, nil)
    }

    // MARK: Steps: goal

    func testStepGoal_defaultClampAndSnap() throws {
        let suite = "ActivityReadoutsTests.stepGoal"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(StepGoal.key, "baseline.stepGoal")
        XCTAssertEqual(StepGoal.goal(defaults), 8_000, "the evidence-based default")
        XCTAssertEqual(StepGoal.range, 3_000...30_000)
        XCTAssertEqual(StepGoal.range.lowerBound, FriendsScoring.stepGoalFloor,
                       "the floor Friends scores against, so Home's 'Goal met' is Friends' goal day")
        XCTAssertEqual(StepGoal.range.upperBound, FriendsScoring.stepGoalCeiling)
        XCTAssertEqual(StepGoal.step, 500)
        StepGoal.save(10_000, defaults)
        XCTAssertEqual(StepGoal.goal(defaults), 10_000)
        StepGoal.save(1_000, defaults)
        XCTAssertEqual(StepGoal.goal(defaults), 3_000)
        defaults.set(2_500, forKey: StepGoal.key)
        XCTAssertEqual(StepGoal.goal(defaults), 3_000, "an older build's 2,500 reads as Friends' 3,000")
        XCTAssertEqual(FriendsScoring.storedStepGoal(StepGoal.goal(defaults)), StepGoal.goal(defaults))
        XCTAssertEqual(ActivityGoals.stepGoal(stored: 2_500), 3_000,
                       "Home and the Steps detail bind the raw key; they draw Friends' floor, not 2,500")
        XCTAssertEqual(ActivityGoals.stepGoal(stored: 2_500), FriendsScoring.storedStepGoal(2_500))
        XCTAssertEqual(ActivityGoals.stepGoal(stored: 8_000), 8_000)
        StepGoal.save(45_000, defaults)
        XCTAssertEqual(StepGoal.goal(defaults), 30_000)
        defaults.set(8_260, forKey: StepGoal.key)
        XCTAssertEqual(StepGoal.goal(defaults), 8_500, "a hand-edited value snaps to the stepper's grid")
    }

    func testStepsGoalTrack_fractionMetAndGoalDays() {
        let readings = (0..<7).map { (day: key($0), value: Double([9_000, 4_000, 8_000, 12_000, 7_999, 8_500, 6_240][$0])) }
        let r = BaselineReadouts.steps(for: today, readings: readings)
        XCTAssertEqual(r.goalFraction(goal: 8_000), 1)
        XCTAssertTrue(r.goalMet(goal: 8_000))
        XCTAssertEqual(r.goalDays(goal: 8_000), 4, "9,000, 8,000, 12,000 and 8,500")
        let partial = BaselineReadouts.steps(for: key(6), readings: readings)
        XCTAssertEqual(partial.goalFraction(goal: 8_000), 6_240.0 / 8_000, accuracy: 1e-9)
        XCTAssertFalse(partial.goalMet(goal: 8_000))
    }

    // MARK: Calories: resting

    func testMifflinStJeor_byTheSpecsFixtures() {
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "male", weightKg: 75, heightCm: 178, age: 30), 1_717.5, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "female", weightKg: 60, heightCm: 165, age: 40), 1_270.25, accuracy: 1e-9)
        let male = BaselineReadouts.bmrMifflin(sex: "male", weightKg: 70, heightCm: 170, age: 35)
        let female = BaselineReadouts.bmrMifflin(sex: "female", weightKg: 70, heightCm: 170, age: 35)
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "nonbinary", weightKg: 70, heightCm: 170, age: 35), (male + female) / 2,
                       accuracy: 1e-9, "the male/female midpoint")
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "", weightKg: 70, heightCm: 170, age: 35), (male + female) / 2, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "MALE", weightKg: 75, heightCm: 178, age: 30), 1_717.5, accuracy: 1e-9)
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "female", weightKg: 30, heightCm: 100, age: 90), 800, "clamped low")
        XCTAssertEqual(BaselineReadouts.bmrMifflin(sex: "male", weightKg: 300, heightCm: 230, age: 18), 4_000, "clamped high")
    }

    func testCalorieInputs_ageAndSexOnlyOnceEntered_appleWeightPreferred() {
        let seeded = BaselineReadouts.calorieInputs(weightKg: 75, heightCm: 178, age: 30, sex: "male", hrMax: 190,
                                                    entered: false, bodySet: false, appleWeightKg: nil)
        XCTAssertNil(seeded.age, "NOOP's seeded 30-year-old is never trusted")
        XCTAssertNil(seeded.sex)
        XCTAssertNil(seeded.bmr, "no resting figure without an entered age and sex")
        XCTAssertTrue(seeded.bodyAssumed)
        XCTAssertEqual(seeded.energyProfile.sex, "nonbinary", "the active model runs on the neutral midpoint")

        let entered = BaselineReadouts.calorieInputs(weightKg: 75, heightCm: 178, age: 30, sex: "male", hrMax: 190,
                                                     entered: true, bodySet: true, appleWeightKg: 80)
        XCTAssertEqual(entered.weightKg, 80, "the latest Apple Health weight wins")
        XCTAssertTrue(entered.weightFromAppleHealth)
        XCTAssertFalse(entered.bodyAssumed)
        XCTAssertEqual(try XCTUnwrap(entered.bmr), BaselineReadouts.bmrMifflin(sex: "male", weightKg: 80, heightCm: 178, age: 30),
                       accuracy: 1e-9)
        XCTAssertNotEqual(entered.energySignature, seeded.energySignature)
    }

    // MARK: Calories: the day

    private var inputs: CalorieInputs {
        BaselineReadouts.calorieInputs(weightKg: 75, heightCm: 178, age: 30, sex: "male", hrMax: 190,
                                       entered: true, bodySet: true, appleWeightKg: nil)
    }

    func testCaloriesDay_strapAndAppleAreNeverSummed() {
        let both = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: [today: 520],
                                                appleActive: [today: 610], mode: .strapFirst)
        XCTAssertEqual(both.activeKcal, 520, "the strap's estimate, not 520 + 610")
        XCTAssertEqual(both.activeSource, .strap)
        XCTAssertEqual(both.restingKcal, 1_717.5)
        XCTAssertEqual(try XCTUnwrap(both.totalKcal), 2_237.5, accuracy: 1e-9)
        XCTAssertFalse(both.isPartialDay)

        let appleOnly = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: [:],
                                                     appleActive: [today: 610], mode: .strapFirst)
        XCTAssertEqual(appleOnly.activeKcal, 610)
        XCTAssertEqual(appleOnly.activeSource, .appleHealth)

        let importsOnly = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: [today: 520],
                                                       appleActive: [today: 610], mode: .importOnly)
        XCTAssertEqual(importsOnly.activeKcal, 610)
        XCTAssertEqual(importsOnly.activeSource, .appleHealth)

        // A strap day without exercise-level heart rate scores 0 active (NOOP's 50 % HRR gate); the phone's
        // walking energy stands in for that 0, alone, never added. Without a phone figure the 0 stays.
        let restDay = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: [today: 0],
                                                   appleActive: [today: 340], mode: .strapFirst)
        XCTAssertEqual(restDay.activeKcal, 340)
        XCTAssertEqual(restDay.activeSource, .appleHealth)
        let restDayNoPhone = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: [today: 0],
                                                          appleActive: [:], mode: .strapFirst)
        XCTAssertEqual(restDayNoPhone.activeKcal, 0)
        XCTAssertEqual(restDayNoPhone.activeSource, .strap)
    }

    func testCaloriesDay_todayAtNoonIsHalfTheBMR() {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let fraction = BaselineReadouts.dayFraction(noon)
        XCTAssertEqual(fraction, 0.5, accuracy: 0.05, "noon is half the day (an hour either way on a DST day)")
        let r = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: [today: 100], appleActive: [:],
                                             mode: .strapFirst, dayFraction: 0.5)
        XCTAssertEqual(r.restingKcal, 1_717.5 / 2)
        XCTAssertTrue(r.isPartialDay)
    }

    func testCaloriesDay_withoutAProfile_activeOnly_andNothingWithNeither() {
        let r = BaselineReadouts.caloriesDay(for: today, inputs: nil, strapActive: [today: 300], appleActive: [:],
                                             mode: .strapFirst)
        XCTAssertNil(r.restingKcal)
        XCTAssertNil(r.totalKcal, "no total without the resting part")
        XCTAssertEqual(r.activeKcal, 300)
        XCTAssertTrue(r.hasFigure)

        let seeded = BaselineReadouts.calorieInputs(weightKg: 75, heightCm: 178, age: 30, sex: "male", hrMax: 190,
                                                    entered: false, bodySet: false, appleWeightKg: nil)
        let none = BaselineReadouts.caloriesDay(for: today, inputs: seeded, strapActive: [:], appleActive: [:],
                                                mode: .strapFirst)
        XCTAssertFalse(none.hasFigure, "no active source and no profile: the card is left out")
        XCTAssertTrue(none.bodyAssumed)
    }

    func testCaloriesDay_activeAverageNeedsSevenEarlierDays() {
        var strap: [String: Double] = [today: 700]
        for back in 1...6 { strap[key(back)] = 400 }
        let six = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: strap, appleActive: [:], mode: .strapFirst)
        XCTAssertNil(six.activeAverage30)
        XCTAssertEqual(six.activeObserved30, 6)
        strap[key(9)] = 500
        let seven = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: strap, appleActive: [:], mode: .strapFirst)
        XCTAssertEqual(try XCTUnwrap(seven.activeAverage30), (6 * 400 + 500) / 7.0, accuracy: 1e-9)
        strap[key(31)] = 9_000
        let outside = BaselineReadouts.caloriesDay(for: today, inputs: inputs, strapActive: strap, appleActive: [:], mode: .strapFirst)
        XCTAssertEqual(outside.activeObserved30, 7, "day 31 is outside the window")
    }

    /// One Calories figure per day everywhere: the detail's readings are `caloriesDay`'s total (Home's
    /// card), Trends' bars carry the same values, and the funnel's `active_kcal` column never stands in
    /// for them once the readings are given. Without an age and sex the figure is the active part.
    func testCalorieReadings_areTheCardsFigure_inTheDetailAndOnTrends() throws {
        let strap: [String: Double] = [key(3): 520, key(1): 480]
        let apple: [String: Double] = [key(2): 610, key(1): 900]
        let readings = BaselineReadouts.calorieReadings(from: key(4), to: today, inputs: inputs, strapActive: strap,
                                                        appleActive: apple, mode: .strapFirst)
        XCTAssertEqual(readings.map(\.day), [key(3), key(2), key(1)], "a day with no active estimate is absent")
        for r in readings {
            let card = BaselineReadouts.caloriesDay(for: r.day, inputs: inputs, strapActive: strap, appleActive: apple,
                                                    mode: .strapFirst)
            XCTAssertEqual(r.value, try XCTUnwrap(card.totalKcal), accuracy: 1e-9, "Home's figure for \(r.day)")
        }
        XCTAssertEqual(try XCTUnwrap(readings.last).value, 1_717.5 + 480, accuracy: 1e-9, "the strap's active, never + Apple's")

        let funnel = [DailyMetric(day: key(1), totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                                  disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil,
                                  exerciseCount: nil, activeKcalEst: 2_900)]
        XCTAssertEqual(BaselineReadouts.metricReadings(key: .calories, days: funnel).map(\.value), [2_900],
                       "precondition: the pure form without readings still reads the funnel column")
        let detail = BaselineReadouts.metricReadings(key: .calories, days: funnel, calorieReadings: readings)
        XCTAssertEqual(detail.map(\.value), readings.map(\.value), "the detail reads the card's figure, not active_kcal")

        let trends = TrendsSeries.caloriesMetric(startKey: key(4), todayKey: today, inputs: inputs, strapActive: strap,
                                                 appleActive: apple, mode: .strapFirst, todayFraction: 1)
        XCTAssertEqual(trends.bars.map(\.value), readings.map(\.value), "Trends' bars are the same numbers")

        let seeded = BaselineReadouts.calorieInputs(weightKg: 75, heightCm: 178, age: 30, sex: "male", hrMax: 190,
                                                    entered: false, bodySet: false, appleWeightKg: nil)
        let activeOnly = BaselineReadouts.calorieReadings(from: key(4), to: today, inputs: seeded, strapActive: strap,
                                                          appleActive: apple, mode: .strapFirst)
        XCTAssertEqual(activeOnly.map(\.value), [520, 610, 480], "no age and sex: the active part alone")
    }

    /// The day store's active figure: NOOP's estimator over the day's heart rate, active part only, and
    /// stamped with what it ran on; a caller without inputs carries a figure forward.
    func testIntradayCompute_estimatesActiveEnergyOnlyAboveTheGate() {
        let start = 1_771_372_800   // a UTC midnight; the estimator is clock-free
        func buckets(_ bpm: Double, minutes: Int, from offset: Int = 0) -> [HRBucket] {
            (0..<minutes).map { HRBucket(ts: start + offset + $0 * 60, bpm: bpm, minBpm: bpm - 2, maxBpm: bpm + 2) }
        }
        let calm = IntradayDayStore.compute(day: today, buckets: buckets(70, minutes: 600), thresholds: nil,
                                            energy: (inputs: inputs, restingHr: 55))
        XCTAssertEqual(try XCTUnwrap(calm.activeKcal), 0, accuracy: 1e-9, "70 bpm is below 50 % of the reserve")
        XCTAssertNotNil(calm.energySignature)

        let trained = IntradayDayStore.compute(day: today, buckets: buckets(70, minutes: 600) + buckets(150, minutes: 45, from: 36_000),
                                               thresholds: nil, energy: (inputs: inputs, restingHr: 55))
        XCTAssertGreaterThan(try XCTUnwrap(trained.activeKcal), 200, "45 minutes at 150 bpm")
        XCTAssertLessThan(try XCTUnwrap(trained.activeKcal), 900)

        let carried = IntradayDayStore.compute(day: today, buckets: buckets(70, minutes: 10), thresholds: nil,
                                               carriedEnergy: (kcal: 123, signature: "x"))
        XCTAssertEqual(carried.activeKcal, 123)
        XCTAssertEqual(carried.energySignature, "x")
        let empty = IntradayDayStore.compute(day: today, buckets: [], thresholds: nil, energy: (inputs: inputs, restingHr: nil))
        XCTAssertNil(empty.activeKcal, "no heart rate, no strap figure (Apple Health's may stand in)")
    }

    // MARK: Stress

    func testStressState_levelsAndTheMovingGap() {
        XCTAssertEqual(StressState.of(level: 2.0, moving: false), .elevated)
        XCTAssertEqual(StressState.of(level: 1.99, moving: false), .calm)
        XCTAssertEqual(StressState.of(level: 1.6, moving: false), .calm)
        XCTAssertEqual(StressState.of(level: 1.59, moving: false), .restored)
        XCTAssertEqual(StressState.of(level: nil, moving: true), .moving)
        XCTAssertEqual(StressState.of(level: nil, moving: false), .noReading)
        XCTAssertEqual(StressState.elevatedFloor, DaytimeStress.highBandFloor)
    }

    /// The bpm ↔ state table through NOOP's own scorer on the personal lens: a floor of 64 bpm makes
    /// 64 and 66 restored, 67 calm (past the 3 bpm spread), 78 still calm and 80 elevated (past floor + 15,
    /// the band edge itself, which floating point may land either side of).
    func testStressStates_onNoopsScorer_followTheFloorInBpm() throws {
        let floor = BaselineState(baseline: 64, spread: 3, nValid: 20, nightsSinceUpdate: 0, status: .trusted)
        let day = 1_771_372_800   // UTC midnight, scored at tz offset 0
        let means: [Int: Int] = [9: 64, 10: 66, 11: 67, 12: 78, 13: 80, 14: 90]
        var hr: [HRSample] = []
        for (hour, bpm) in means {
            for s in 0..<360 { hr.append(HRSample(ts: day + hour * 3_600 + s * 10, bpm: bpm)) }
        }
        let result = DaytimeStress.analyze(hr: hr, rr: [], mode: .baselineRelative(hr: floor, rmssd: nil))
        let states = Dictionary(uniqueKeysWithValues: result.hours.map { ($0.hour, StressState.of($0)) })
        XCTAssertEqual(states[9], .restored)
        XCTAssertEqual(states[10], .restored)
        XCTAssertEqual(states[11], .calm)
        XCTAssertEqual(states[12], .calm)
        XCTAssertEqual(states[13], .elevated)
        XCTAssertEqual(states[14], .elevated)

        let r = try XCTUnwrap(BaselineReadouts.stressDay(result, day: today, lens: .personal(floorBPM: 64)))
        XCTAssertEqual(r.restoredHours, 2)
        XCTAssertEqual(r.calmHours, 2)
        XCTAssertEqual(r.elevatedHours, 2)
        XCTAssertEqual(r.restoredHours + r.calmHours + r.elevatedHours, r.scoredHours)
        XCTAssertEqual(r.elevatedHours * 60, result.highStressMinutes, "the same threshold as NOOP's high-stress minutes")
        XCTAssertEqual(try XCTUnwrap(r.peakHour?.overFloorBPM), 26, accuracy: 0.5, "90 bpm is 26 over the floor")
    }

    func testStressLens_personalOnceUsable_learningCountsTheDays() {
        let usable = BaselineState(baseline: 66.4, spread: 3, nValid: 9, nightsSinceUpdate: 0, status: .provisional)
        XCTAssertEqual(BaselineReadouts.StressLens.of(.baselineRelative(hr: usable, rmssd: nil), daysOfHistory: 9),
                       .personal(floorBPM: 66.4))
        XCTAssertEqual(BaselineReadouts.StressLens.of(.dayRelative, daysOfHistory: 2), .learning(daysOfHistory: 2))
        XCTAssertEqual(BaselineReadouts.StressLens.of(.dayRelative, daysOfHistory: 9), .learning(daysOfHistory: 3),
                       "day-relative means the fold is not usable yet, whatever the count")

        // NOOP's own fold over aggregates (`StressDayStore.lens(aggregates:)`): personal from the 4th day.
        let three = StressDayStore.lens(aggregates: [nil, 64, 65, nil, 63])
        XCTAssertEqual(three.lens, .learning(daysOfHistory: 3))
        let four = StressDayStore.lens(aggregates: [64, 65, nil, 63, 64])
        XCTAssertTrue(four.lens.isPersonal)
        XCTAssertEqual(try XCTUnwrap(four.lens.floorBPM), 64, accuracy: 1.5)
    }

    func testStressTypical_medianOfQualifyingDays_needsFive() {
        func day(_ elevated: Int, scored: Int = 8, personal: Bool = true) -> StressDayFacts {
            StressDayFacts(restored: 2, calm: max(0, scored - elevated - 2), elevated: elevated, moving: 1, scored: scored,
                           personal: personal)
        }
        XCTAssertNil(StressDayStore.typical([day(1), day(2), day(3), day(4)]), "four days are not enough")
        XCTAssertEqual(StressDayStore.typical([day(1), day(2), day(3), day(4), day(6)]), 3)
        XCTAssertEqual(StressDayStore.typical([day(1), day(2), day(3), day(4), day(6), day(9, scored: 2),
                                               day(9, personal: false), nil]), 3,
                       "under three scored hours, a learning day and a day without data are left out")
        XCTAssertEqual(StressDayStore.typical([day(1), day(2), day(3), day(4), day(6), day(8)]), 3.5)
        XCTAssertEqual(StressDayStore.lensKey(.personal(floorBPM: 64.04)), "p:640")
    }

    /// The Stress detail's readings are elevated hours of the days the card may total: a learning day and
    /// a day under three scored hours are absent, a totalled day with no elevated hour is a 0.
    func testStressElevatedHours_onlyDaysThatMayBeTotalled() {
        func day(_ elevated: Int, scored: Int = 8, personal: Bool = true) -> StressDayFacts {
            StressDayFacts(restored: 2, calm: max(0, scored - elevated - 2), elevated: elevated, moving: 1, scored: scored,
                           personal: personal)
        }
        let hours = StressDayStore.elevatedHours([key(1): day(2), key(2): day(0), key(3): day(4, personal: false),
                                                  key(4): day(1, scored: 2)])
        XCTAssertEqual(hours, [key(1): 2, key(2): 0])
    }

    /// A past day's lens is the lens NOOP's resolver gave the same day: 15 worn days at the start of the
    /// 30-day window (one of them too sparse for the 300-sample gate), then 15 days with the strap off.
    /// NOOP leaves the empty days out of its fold and the floor stays usable; the store must leave them
    /// out too, or 15 trailing skip-and-hold nights age its fold past `staleDays` into "learning".
    @MainActor
    func testStressDayStoreLens_matchesNOOPsResolver_acrossATrailingGap() async throws {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        for back in 16...30 {
            let raw = try XCTUnwrap(calendar.date(byAdding: .day, value: -back, to: startOfToday))
            let t0 = Int(calendar.startOfDay(for: raw).timeIntervalSince1970)
            // Two waking hours: 600 samples each, or 100 on the sparse day (heart rate, but no hour clears the gate).
            let every = back == 20 ? 36 : 6
            let hr: [HRSample] = [9, 14].flatMap { (hour: Int) -> [HRSample] in
                stride(from: 0, to: 3_600, by: every).map { HRSample(ts: t0 + hour * 3_600 + $0, bpm: 63 + back % 2) }
            }
            try await store.insert(Streams(hr: hr), deviceId: "my-whoop")
        }

        StressLensCache.shared.clear()
        defer { StressLensCache.shared.clear() }
        let noop = await DaytimeStressMode.selected(repo: repo, startOfToday: startOfToday, calendar: calendar,
                                                    personalBaseline: true)
        guard case .baselineRelative = noop else {
            return XCTFail("precondition: NOOP's floor is usable after 14 worn days, whatever followed")
        }
        let ours = await StressDayStore(fileURL: nil).lens(repo, dayStart: startOfToday, calendar: calendar)
        XCTAssertEqual(ours.mode, noop, "the same fold as NOOP's resolver")
        XCTAssertTrue(ours.lens.isPersonal, "a strap-off gap is not 15 stale nights")
        XCTAssertEqual(ours.daysOfHistory, 14, "the sparse day enters the fold as a skip, the empty days not at all")
    }

    // MARK: Friends

    func testFriendsDailyAggregate_behaviourOnly_byTheSpecsRules() {
        let bed = Fixtures.local(2026, 2, 17, hour: 23, minute: 50)
        func record(_ moderate: Int, _ vigorous: Int, scored: Int = 600) -> IntradayDayRecord {
            IntradayDayRecord(day: today, version: IntradayDayStore.version, fingerprintCount: scored, fingerprintMaxTs: 0,
                              fingerprintSum: 0, thresholdSignature: "", storeIdentity: "", basisTag: "hrr",
                              restingHr: 52, hrMaxBpm: 182, moderateMin: moderate, vigorousMin: vigorous,
                              scoredMinutes: scored, bpmMin: nil, bpmAvg: nil, bpmMax: nil, stressMean: nil,
                              stressComputed: false, computedAt: 0)
        }
        let a = BaselineReadouts.friendsDailyAggregate(
            for: today, steps: (value: 9_120, source: .phone), intensityRecord: record(10, 6), workouts: [],
            night: (asleepMinutes: 450, bed: bed), sleepGoalMinutes: 450, targetBedMinutes: 10)
        XCTAssertEqual(a.steps, 9_120)
        XCTAssertEqual(a.stepsSource, .phone)
        XCTAssertEqual(a.intensity, 22)
        XCTAssertEqual(a.active, 1, "22 credited minutes")
        XCTAssertEqual(a.sleepGoal, 1, "450 asleep against a 450 goal")
        XCTAssertEqual(a.bedtime, 1, "23:50 against a 00:10 target is 20 minutes")

        let b = BaselineReadouts.friendsDailyAggregate(
            for: today, steps: (value: 9_120, source: .estimate), intensityRecord: record(5, 2), workouts: [],
            night: (asleepMinutes: 449, bed: Fixtures.local(2026, 2, 18, hour: 0, minute: 45)),
            sleepGoalMinutes: 450, targetBedMinutes: 23 * 60 + 50)
        XCTAssertNil(b.steps, "an estimate is never shared")
        XCTAssertNil(b.stepsSource)
        XCTAssertEqual(b.active, 0)
        XCTAssertEqual(b.sleepGoal, 0, "449 is under the goal")
        XCTAssertEqual(b.bedtime, 0, "55 minutes late")

        let workout = WorkoutRow(startTs: 1_771_400_000, endTs: 1_771_400_000 + 25 * 60, sport: "Running", source: "x",
                                 durationS: 25 * 60, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                                 distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
        let c = BaselineReadouts.friendsDailyAggregate(
            for: today, steps: nil, intensityRecord: nil, workouts: [workout], night: nil,
            sleepGoalMinutes: 450, targetBedMinutes: 0)
        XCTAssertEqual(c.active, 1, "a 25-minute workout")
        XCTAssertNil(c.intensity)
        XCTAssertNil(c.sleepGoal)
        XCTAssertNil(c.bedtime)

        let d = BaselineReadouts.friendsDailyAggregate(
            for: today, steps: nil, intensityRecord: record(0, 0, scored: 0), workouts: [],
            night: (asleepMinutes: 480, bed: nil), sleepGoalMinutes: 450, targetBedMinutes: 0)
        XCTAssertNil(d.intensity, "a day the strap never scored is not a zero-minute reading")
        XCTAssertNil(d.active)
        XCTAssertEqual(d.sleepGoal, 1)
        XCTAssertNil(d.bedtime, "no bedtime without a timed night")
    }

    func testSleepGoal_defaultAndClamp() throws {
        let suite = "ActivityReadoutsTests.sleepGoal"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(BaselineReadouts.SleepGoal.key, "baseline.sleepGoalMinutes")
        XCTAssertEqual(BaselineReadouts.SleepGoal.minutes(defaults), 450)
        defaults.set(100, forKey: BaselineReadouts.SleepGoal.key)
        XCTAssertEqual(BaselineReadouts.SleepGoal.minutes(defaults), 300)
        defaults.set(482, forKey: BaselineReadouts.SleepGoal.key)
        XCTAssertEqual(BaselineReadouts.SleepGoal.minutes(defaults), 480, "snapped to the stepper's 15-minute grid")
        XCTAssertEqual(BaselineReadouts.SleepGoal.text(450), "7h 30m")
        XCTAssertEqual(BaselineReadouts.SleepGoal.text(480), "8h")
        XCTAssertEqual(SettingsSleepWindowCard.sleepGoalSpoken(450), "7 hours 30 minutes")
    }

    /// The goal a night is judged against is printed where the person agrees to share it and where a
    /// competition scores it, never an unseen 450.
    func testSleepGoal_isStatedInTheConsentRowAndTheCompetitionRule() {
        XCTAssertTrue(FriendsMetric.sleepGoal.sharedFormText(sleepGoalMinutes: 480).contains("8h asleep"),
                      FriendsMetric.sleepGoal.sharedFormText(sleepGoalMinutes: 480))
        XCTAssertTrue(FriendsMetric.sleepGoal.sharedFormText(sleepGoalMinutes: 450).contains("7h 30m"))
        XCTAssertEqual(FriendsMetric.steps.sharedFormText(sleepGoalMinutes: 480), FriendsMetric.steps.sharedForm)
        XCTAssertTrue(FriendsScoring.ruleText(metric: .sleepGoal, mode: .total, sleepGoalMinutes: 420).contains("7h"))
    }
}
