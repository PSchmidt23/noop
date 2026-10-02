import XCTest
import WhoopProtocol
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// The Intensity-minutes engine (`Baseline/Components/IntensityMinutes.swift`): Karvonen thresholds and
/// the %HRmax fallback, minute classification over synthetic 1 Hz traces, the bout rule (Baseline's
/// 3-minute floor with 1-minute gaps, and the stricter ten-minute convention), the resting-HR
/// reference, the Monday → Sunday week, the goal, the per-day record and its persistence.
final class IntensityMinutesTests: XCTestCase {

    private let forbidden = ["strain", "recovery", "coach", "active zone", "exercise ring"]

    /// Karvonen on resting 52 / max 182: moderate from 104 bpm, vigorous from 130 bpm.
    private var thresholds: IntensityMinutes.Thresholds {
        IntensityMinutes.Thresholds.karvonen(restingHr: 52, hrMax: 182)!
    }

    /// `pct` of heart-rate reserve as bpm on the thresholds above.
    private func bpm(pctHRR pct: Double) -> Double { 52 + pct / 100 * 130 }

    /// A 1 Hz trace: `minutes` whole minutes at `bpm` from `start` (local wall clock, whole minute).
    private func trace(from start: Date, minutes: Int, bpm: Double, hz: Int = 1) -> [IntensityMinutes.Sample] {
        let t0 = Int(start.timeIntervalSince1970)
        return (0..<(minutes * 60 * hz)).map { i in IntensityMinutes.Sample(ts: t0 + i / hz, bpm: bpm) }
    }

    private func minutes(_ samples: [IntensityMinutes.Sample]) -> [IntensityMinutes.Minute] {
        IntensityMinutes.minutes(samples: samples)
    }

    private let morning = Fixtures.local(2026, 2, 18, hour: 8)

    // MARK: Thresholds

    func testKarvonenThresholds_areACSMCutoffsOnTheReserve() throws {
        let t = thresholds
        XCTAssertEqual(t.moderateBpm, 104, accuracy: 0.001)
        XCTAssertEqual(t.vigorousBpm, 130, accuracy: 0.001)
        XCTAssertEqual(t.basis, .hrr(restingHr: 52, hrMax: 182))
        XCTAssertEqual(try XCTUnwrap(t.pctHRR(117)), 50, accuracy: 0.001)
        XCTAssertNil(IntensityMinutes.Thresholds.karvonen(restingHr: 190, hrMax: 182), "a reserve of zero or less refuses")
        XCTAssertNil(IntensityMinutes.Thresholds.karvonen(restingHr: 0, hrMax: 182))
        XCTAssertEqual(t.basis.caption, "40 % / 60 % of your heart-rate reserve (resting 52, max 182)")
        for word in forbidden { XCTAssertFalse(t.basis.caption.lowercased().contains(word)) }
    }

    func testHrMaxFallback_isZone3AndZone4OfNoopsZones() throws {
        let zones = HRZones.zones(maxHR: 180)
        let t = try XCTUnwrap(IntensityMinutes.Thresholds.hrMax(zoneSet: zones))
        XCTAssertEqual(t.moderateBpm, 126, accuracy: 0.001, "Zone 3 starts at 70 % of max")
        XCTAssertEqual(t.vigorousBpm, 144, accuracy: 0.001, "Zone 4 starts at 80 %")
        XCTAssertEqual(t.basis, .hrMax(hrMax: 180))
        XCTAssertNil(t.pctHRR(150), "no reserve under the fallback")
        // The resolver: a resting reference → Karvonen; none → the zones; no max HR → nil (needs age).
        let day = "2026-02-18"
        let nights = (1...5).map { Fixtures.metric(Fixtures.key(day, minus: $0), rhr: 50 + $0 % 2) }
        XCTAssertEqual(IntensityMinutes.thresholds(for: day, days: nights, effortHRmax: 182, zoneSet: zones)?.basis,
                       .hrr(restingHr: 51, hrMax: 182))
        XCTAssertEqual(IntensityMinutes.thresholds(for: day, days: [], effortHRmax: 180, zoneSet: zones)?.basis, .hrMax(hrMax: 180))
        XCTAssertNil(IntensityMinutes.thresholds(for: day, days: nights, effortHRmax: nil, zoneSet: zones))
    }

    func testRestingReference_isTheMedianOfTheLastSevenNights_elseTheDaysOwn() {
        let day = "2026-02-18"
        var days = [Fixtures.metric(Fixtures.key(day, minus: 1), rhr: 60), Fixtures.metric(Fixtures.key(day, minus: 2), rhr: 50)]
        XCTAssertNil(IntensityMinutes.restingReference(for: day, days: days), "two nights are not enough, and the day has none")
        days.append(Fixtures.metric(day, rhr: 55))
        XCTAssertEqual(IntensityMinutes.restingReference(for: day, days: days), 55, "the day's own resting HR")
        days.append(Fixtures.metric(Fixtures.key(day, minus: 3), rhr: 54))
        XCTAssertEqual(IntensityMinutes.restingReference(for: day, days: days), 54, "median of 60, 50, 54")
        // A night eight days back is outside the seven-night window.
        days.append(Fixtures.metric(Fixtures.key(day, minus: 8), rhr: 90))
        XCTAssertEqual(IntensityMinutes.restingReference(for: day, days: days), 54)
    }

    /// The day store's index (`RestingReferences`, the funnel walked once for a 730-day range) gives the
    /// one-day form's answer for every day: inside and outside the history, across gaps, nights without a
    /// resting HR and the "too few nights, the day's own" fallback.
    func testRestingReferences_matchTheOneDayFormForEveryDay() {
        let anchor = "2026-02-18"
        var days: [DailyMetric] = []
        for back in stride(from: 60, through: 0, by: -1) where back % 5 != 3 {
            days.append(Fixtures.metric(Fixtures.key(anchor, minus: back), rhr: back % 7 == 0 ? nil : 48 + back % 9))
        }
        let index = IntensityMinutes.RestingReferences(days)
        for back in -3...70 {
            let day = Fixtures.key(anchor, minus: back)
            XCTAssertEqual(index.reference(for: day), IntensityMinutes.restingReference(for: day, days: days), day)
        }
        XCTAssertNil(IntensityMinutes.RestingReferences([]).reference(for: anchor))
        // The gated thresholds over the index are the one-day form's too.
        let zones = HRZones.zones(maxHR: 182)
        for back in [0, 3, 30, 65] {
            let day = Fixtures.key(anchor, minus: back)
            XCTAssertEqual(IntensityMinutes.thresholds(for: day, references: index, effortHRmax: 182, zoneSet: zones,
                                                       entered: true, hrMaxOverride: 0),
                           IntensityMinutes.thresholds(for: day, days: days, effortHRmax: 182, zoneSet: zones,
                                                       entered: true, hrMaxOverride: 0), day)
        }
        XCTAssertNil(IntensityMinutes.thresholds(for: anchor, references: index, effortHRmax: 182, zoneSet: zones,
                                                 entered: false, hrMaxOverride: 0), "the profile gate holds on the index too")
    }

    // MARK: Minutes

    func testMinutes_needTwentySamples_andTakeTheMedian() {
        let t0 = Int(morning.timeIntervalSince1970)
        var samples: [IntensityMinutes.Sample] = []
        // Minute 0: 30 samples at 110 with one artefact at 200 → median 110.
        for i in 0..<30 { samples.append(.init(ts: t0 + i, bpm: i == 7 ? 200 : 110)) }
        // Minute 1: 19 samples → unscored.
        for i in 0..<19 { samples.append(.init(ts: t0 + 60 + i, bpm: 140)) }
        let m = minutes(samples)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].start, t0)
        XCTAssertEqual(m[0].bpm, 110)
        // Buckets: one minute per 60-second bucket at its mean.
        let b = IntensityMinutes.minutes(buckets: [HRBucket(ts: t0 + 60, bpm: 120, minBpm: 110, maxBpm: 130),
                                                   HRBucket(ts: t0, bpm: 100, minBpm: 90, maxBpm: 110)])
        XCTAssertEqual(b.map(\.start), [t0, t0 + 60])
        XCTAssertEqual(b.map(\.bpm), [100, 120])
    }

    // MARK: Bouts and credit (the research's cases)

    func testWalk25MinutesAt45PercentHRR_credits25() {
        let r = IntensityMinutes.credit(day: "2026-02-18", minutes: minutes(trace(from: morning, minutes: 25, bpm: bpm(pctHRR: 45))),
                                        thresholds: thresholds)
        XCTAssertEqual(r.moderateMin, 25)
        XCTAssertEqual(r.vigorousMin, 0)
        XCTAssertEqual(r.credited, 25)
        XCTAssertEqual(r.bouts.count, 1)
        XCTAssertEqual(r.scoredMinutes, 25)
    }

    func testRun20MinutesAt70PercentHRR_credits40_vigorousCountsDouble() {
        let r = IntensityMinutes.credit(day: "2026-02-18", minutes: minutes(trace(from: morning, minutes: 20, bpm: bpm(pctHRR: 70))),
                                        thresholds: thresholds)
        XCTAssertEqual(r.moderateMin, 0)
        XCTAssertEqual(r.vigorousMin, 20)
        XCTAssertEqual(r.credited, 40)
        XCTAssertEqual(r.bouts.first?.credited, 40)
    }

    func testTwoTwoMinuteSpikes_creditNothing() {
        let later = morning.addingTimeInterval(10 * 60)
        let samples = trace(from: morning, minutes: 2, bpm: bpm(pctHRR: 80)) + trace(from: later, minutes: 2, bpm: bpm(pctHRR: 80))
        let r = IntensityMinutes.credit(day: "2026-02-18", minutes: minutes(samples), thresholds: thresholds)
        XCTAssertEqual(r.credited, 0, "under the three-minute floor")
        XCTAssertTrue(r.bouts.isEmpty)
        XCTAssertEqual(r.scoredMinutes, 4, "the minutes were scored, just not credited")
    }

    func testTwelveMinuteBoutWithAOneMinuteDip_credits11() {
        // Minutes 0–5 moderate, minute 6 below, minutes 7–11 moderate: one bout, the dip earns nothing.
        var samples = trace(from: morning, minutes: 6, bpm: bpm(pctHRR: 50))
        samples += trace(from: morning.addingTimeInterval(6 * 60), minutes: 1, bpm: bpm(pctHRR: 20))
        samples += trace(from: morning.addingTimeInterval(7 * 60), minutes: 5, bpm: bpm(pctHRR: 50))
        let r = IntensityMinutes.credit(day: "2026-02-18", minutes: minutes(samples), thresholds: thresholds)
        XCTAssertEqual(r.moderateMin, 11)
        XCTAssertEqual(r.bouts.count, 1)
        XCTAssertEqual(r.bouts[0].start, Int(morning.timeIntervalSince1970))
        XCTAssertEqual(r.bouts[0].end, Int(morning.timeIntervalSince1970) + 11 * 60)
        // The stricter convention reaches the same answer here: eleven qualifying minutes pass ten.
        XCTAssertEqual(IntensityMinutes.credit(day: "d", minutes: minutes(samples), thresholds: thresholds, rule: .tenMinute).credited, 11)
    }

    func testTwoMinuteGap_endsABout_andAnUnscoredGapCountsAsAGap() {
        // 5 moderate, 2 below, 5 moderate → two bouts of five under the default rule, none under ten.
        var samples = trace(from: morning, minutes: 5, bpm: bpm(pctHRR: 50))
        samples += trace(from: morning.addingTimeInterval(5 * 60), minutes: 2, bpm: bpm(pctHRR: 10))
        samples += trace(from: morning.addingTimeInterval(7 * 60), minutes: 5, bpm: bpm(pctHRR: 50))
        let r = IntensityMinutes.credit(day: "d", minutes: minutes(samples), thresholds: thresholds)
        XCTAssertEqual(r.bouts.count, 2)
        XCTAssertEqual(r.credited, 10)
        XCTAssertEqual(IntensityMinutes.credit(day: "d", minutes: minutes(samples), thresholds: thresholds, rule: .tenMinute).credited, 0)

        // The same shape with the two minutes simply missing from the stream.
        let gapped = trace(from: morning, minutes: 5, bpm: bpm(pctHRR: 50))
            + trace(from: morning.addingTimeInterval(7 * 60), minutes: 5, bpm: bpm(pctHRR: 50))
        XCTAssertEqual(IntensityMinutes.bouts(minutes(gapped), thresholds: thresholds).count, 2)
        // One missing minute bridges.
        let bridged = trace(from: morning, minutes: 5, bpm: bpm(pctHRR: 50))
            + trace(from: morning.addingTimeInterval(6 * 60), minutes: 5, bpm: bpm(pctHRR: 50))
        XCTAssertEqual(IntensityMinutes.bouts(minutes(bridged), thresholds: thresholds).count, 1)
    }

    func testTwelveMinuteBoutCounts12_nineMinuteBoutCountsZeroUnderTheTenMinuteRule() {
        let twelve = minutes(trace(from: morning, minutes: 12, bpm: bpm(pctHRR: 50)))
        let nine = minutes(trace(from: morning, minutes: 9, bpm: bpm(pctHRR: 50)))
        XCTAssertEqual(IntensityMinutes.credit(day: "d", minutes: twelve, thresholds: thresholds, rule: .tenMinute).credited, 12)
        XCTAssertEqual(IntensityMinutes.credit(day: "d", minutes: nine, thresholds: thresholds, rule: .tenMinute).credited, 0)
        // Baseline's own rule (WHO 2020: any duration counts; three minutes is the noise floor).
        XCTAssertEqual(IntensityMinutes.credit(day: "d", minutes: twelve, thresholds: thresholds).credited, 12)
        XCTAssertEqual(IntensityMinutes.credit(day: "d", minutes: nine, thresholds: thresholds).credited, 9)
        XCTAssertEqual(IntensityMinutes.BoutRule.default, IntensityMinutes.BoutRule(minMinutes: 3, gapToleranceMinutes: 1))
    }

    func testMixedDay_walkThenRun_sumsModerateAndVigorousSeparately() {
        var samples = trace(from: morning, minutes: 30, bpm: bpm(pctHRR: 45))                       // walk
        samples += trace(from: morning.addingTimeInterval(4 * 3_600), minutes: 20, bpm: bpm(pctHRR: 75)) // run
        samples += trace(from: morning.addingTimeInterval(8 * 3_600), minutes: 60, bpm: bpm(pctHRR: 10)) // desk
        let r = IntensityMinutes.credit(day: "d", minutes: minutes(samples), thresholds: thresholds)
        XCTAssertEqual(r.moderateMin, 30)
        XCTAssertEqual(r.vigorousMin, 20)
        XCTAssertEqual(r.credited, 70)
        XCTAssertEqual(r.bouts.count, 2)
        XCTAssertEqual(r.scoredMinutes, 110)
        // A run that warms up through moderate into vigorous is one bout with both kinds.
        let ramp = trace(from: morning, minutes: 5, bpm: bpm(pctHRR: 45)) + trace(from: morning.addingTimeInterval(300), minutes: 10, bpm: bpm(pctHRR: 65))
        let b = IntensityMinutes.bouts(minutes(ramp), thresholds: thresholds)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].moderateMin, 5)
        XCTAssertEqual(b[0].vigorousMin, 10)
        XCTAssertEqual(b[0].credited, 25)
    }

    func testWorkoutsOnlyFallback_usesImportedZonePercentages() throws {
        let row = WorkoutRow(startTs: 1_000, endTs: 1_000 + 3_600, sport: "Running", source: "my-whoop", durationS: 3_600,
                             energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                             zonesJSON: #"{"z1":10,"z2":20,"z3":30,"z4":30,"z5":10}"#, notes: nil, steps: nil)
        let r = try XCTUnwrap(IntensityMinutes.creditFromWorkouts(day: "d", rows: [row]))
        XCTAssertEqual(r.moderateMin, 18, "Zone 3: 30 % of 60 min")
        XCTAssertEqual(r.vigorousMin, 24, "Zones 4 + 5: 40 % of 60 min")
        XCTAssertEqual(r.basis, .workoutsOnly)
        XCTAssertNil(IntensityMinutes.creditFromWorkouts(day: "d", rows: []))
    }

    // MARK: Week and goal

    func testWeek_isMondayToSunday_whateverTheLocaleStartsOn() {
        // 2026-02-16 is a Monday.
        XCTAssertEqual(IntensityMinutes.weekStart(of: "2026-02-18"), "2026-02-16")
        XCTAssertEqual(IntensityMinutes.weekStart(of: "2026-02-16"), "2026-02-16", "Monday is its own week start")
        XCTAssertEqual(IntensityMinutes.weekStart(of: "2026-02-22"), "2026-02-16", "Sunday closes the week")
        XCTAssertEqual(IntensityMinutes.weekStart(of: "2026-02-23"), "2026-02-23", "the next Monday rolls over")
        XCTAssertEqual(IntensityMinutes.weekDays(ending: "2026-02-18"), ["2026-02-16", "2026-02-17", "2026-02-18"])
        XCTAssertEqual(IntensityMinutes.weekDays(ending: "2026-02-16"), ["2026-02-16"])
        XCTAssertEqual(IntensityMinutes.weekDays(ending: "2026-02-22").count, 7)
        // A locale that starts its week on Sunday makes no difference.
        var sunday = Calendar(identifier: .gregorian)
        sunday.firstWeekday = 1
        XCTAssertEqual(IntensityMinutes.weekStart(of: "2026-02-22", calendar: sunday), "2026-02-16")
        // The week with the European DST Sunday (2026-03-29) still holds seven calendar days.
        XCTAssertEqual(IntensityMinutes.weekDays(ending: "2026-03-29"),
                       ["2026-03-23", "2026-03-24", "2026-03-25", "2026-03-26", "2026-03-27", "2026-03-28", "2026-03-29"])
    }

    func testWeekReadout_sumsCreditedDaysMondayToTheDay() {
        func day(_ k: String, mod: Int, vig: Int) -> IntensityMinutes.DayResult {
            IntensityMinutes.DayResult(day: k, moderateMin: mod, vigorousMin: vig, bouts: [], scoredMinutes: 600,
                                       basis: .hrr(restingHr: 52, hrMax: 182))
        }
        let records = ["2026-02-16": day("2026-02-16", mod: 20, vig: 10),
                       "2026-02-17": day("2026-02-17", mod: 0, vig: 15),
                       "2026-02-18": day("2026-02-18", mod: 23, vig: 0),
                       "2026-02-15": day("2026-02-15", mod: 99, vig: 99)]   // last Sunday: not this week
        let r = BaselineReadouts.intensity(for: "2026-02-18", records: records, goal: 150, fallbackBasis: .needsAge)
        XCTAssertEqual(r.weekStart, "2026-02-16")
        XCTAssertEqual(r.weekDays, [40, 30, 23])
        XCTAssertEqual(r.weekCredited, 93)
        XCTAssertEqual(r.creditedToday, 23)
        XCTAssertEqual(r.weekText, "93 / 150 this week")
        XCTAssertEqual(r.splitText, "23 moderate · 0 vigorous (×2)")
        XCTAssertEqual(r.basis, .hrr(restingHr: 52, hrMax: 182))
        XCTAssertFalse(r.partialDay)
        XCTAssertEqual(r.weekFraction, 93.0 / 150.0, accuracy: 1e-9)
        // Monday rollover: the next Monday starts from zero with the day's own basis fallback.
        let monday = BaselineReadouts.intensity(for: "2026-02-23", records: records, goal: 150, fallbackBasis: .hrMax(hrMax: 182))
        XCTAssertEqual(monday.weekDays, [0])
        XCTAssertEqual(monday.basis, .hrMax(hrMax: 182))
        XCTAssertTrue(monday.partialDay, "nothing scored yet")
        for word in forbidden {
            XCTAssertFalse(r.weekText.lowercased().contains(word))
            XCTAssertFalse(BaselineReadouts.IntensityReadout.caveat.lowercased().contains(word))
        }
    }

    func testGoal_defaults150_andClamps() {
        let defaults = UserDefaults(suiteName: "IntensityMinutesTests.goal")!
        defaults.removePersistentDomain(forName: "IntensityMinutesTests.goal")
        XCTAssertEqual(IntensityMinutes.goalKey, "baseline.intensityGoalMinutes")
        XCTAssertEqual(IntensityMinutes.goal(defaults), 150)
        IntensityMinutes.saveGoal(200, defaults)
        XCTAssertEqual(IntensityMinutes.goal(defaults), 200)
        IntensityMinutes.saveGoal(5, defaults)
        XCTAssertEqual(IntensityMinutes.goal(defaults), 60)
        defaults.set(9_999, forKey: IntensityMinutes.goalKey)
        XCTAssertEqual(IntensityMinutes.goal(defaults), 600)
        defaults.removePersistentDomain(forName: "IntensityMinutesTests.goal")
    }

    // MARK: Per-day record and the store

    @MainActor
    func testRecord_carriesTheDaysHeartRate_andIsNotAReadingWithoutAge() {
        let t0 = Int(morning.timeIntervalSince1970)
        let buckets = (0..<30).map { i in
            HRBucket(ts: t0 + i * 60, bpm: i < 25 ? bpm(pctHRR: 50) : 60, minBpm: i < 25 ? 100 : 55, maxBpm: i < 25 ? 125 : 65)
        }
        let scored = IntradayDayStore.compute(day: "2026-02-18", buckets: buckets, thresholds: thresholds,
                                              fingerprint: (count: 1_800, maxTs: t0 + 1_799))
        XCTAssertEqual(scored.moderateMin, 25)
        XCTAssertEqual(scored.credited, 25)
        XCTAssertEqual(scored.scoredMinutes, 30)
        XCTAssertEqual(scored.bpmMin, 55)
        XCTAssertEqual(scored.bpmMax, 125)
        XCTAssertEqual(scored.basis, .hrr(restingHr: 52, hrMax: 182))
        XCTAssertTrue(scored.basisIsScored)
        XCTAssertEqual(scored.thresholdSignature, "hrr:52:182|b3g1")
        XCTAssertEqual(scored.dayResult.credited, 25)

        let ageless = IntradayDayStore.compute(day: "2026-02-18", buckets: buckets, thresholds: nil,
                                               fingerprint: (count: 1_800, maxTs: t0 + 1_799))
        XCTAssertEqual(ageless.credited, 0)
        XCTAssertFalse(ageless.basisIsScored)
        XCTAssertEqual(ageless.basis, .needsAge)
        XCTAssertEqual(ageless.bpmMax, 125, "the heart-rate facts stand without an age")
        XCTAssertEqual(ageless.thresholdSignature, "needsAge|b3g1")

        let empty = IntradayDayStore.compute(day: "2026-02-18", buckets: [], thresholds: thresholds, fingerprint: (count: 0, maxTs: 0))
        XCTAssertNil(empty.bpmAvg)
        XCTAssertEqual(empty.scoredMinutes, 0)
    }

    @MainActor
    func testStore_persistsRecordsAsJSON_andReloadsThem() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntensityMinutesTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(IntradayDayStore.fileName)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = IntradayDayStore(fileURL: url)
        XCTAssertTrue(store.storedRecords.isEmpty)
        let record = IntradayDayStore.compute(day: "2026-02-18", buckets: [], thresholds: thresholds, fingerprint: (count: 0, maxTs: 0))
        store.store(record)
        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reopened = IntradayDayStore(fileURL: url)
        XCTAssertEqual(reopened.storedRecords["2026-02-18"], record)
        XCTAssertEqual(reopened.storedRecords.count, 1)

        reopened.reset()
        XCTAssertTrue(IntradayDayStore(fileURL: url).storedRecords.isEmpty)
        XCTAssertEqual(IntradayDayStore.defaultFileURL?.lastPathComponent, IntradayDayStore.fileName)
        XCTAssertEqual(IntradayDayStore.defaultFileURL?.deletingLastPathComponent().lastPathComponent, "Baseline")
    }

    /// With the day's raw samples the record follows §5's floor: two samples a minute (the ~30-second
    /// live heart rate of a WHOOP 5.0 / MG) score no minute, earn nothing and do not count toward the
    /// partial-day line, though every minute has a 60-second bucket. The bucket-only path (an older day
    /// computed for the first time) has no count to apply the floor with and credits them.
    func testRecord_fromSamples_appliesTheTwentySampleFloor() {
        let t0 = Int(morning.timeIntervalSince1970)
        let sparse = (0..<60).map { IntensityMinutes.Sample(ts: t0 + $0 * 30, bpm: 150) }   // 30 min, 2 a minute
        let buckets = (0..<30).map { HRBucket(ts: t0 + $0 * 60, bpm: 150, minBpm: 150, maxBpm: 150) }
        let fromSamples = IntradayDayStore.compute(day: "2026-02-18", buckets: buckets, samples: sparse, thresholds: thresholds)
        XCTAssertEqual(fromSamples.scoredMinutes, 0)
        XCTAssertEqual(fromSamples.credited, 0)
        XCTAssertFalse(fromSamples.recordedIntensity, "nothing scored: not an Intensity reading")
        XCTAssertEqual(fromSamples.bpmMax, 150, "the heart-rate facts still come from the buckets")
        XCTAssertEqual(fromSamples.witness, IntradayWitness(buckets: buckets))

        let dense = trace(from: morning, minutes: 30, bpm: 150)
        let full = IntradayDayStore.compute(day: "2026-02-18", buckets: buckets, samples: dense, thresholds: thresholds)
        XCTAssertEqual(full.scoredMinutes, 30)
        XCTAssertEqual(full.vigorousMin, 30)

        let bucketsOnly = IntradayDayStore.compute(day: "2026-02-18", buckets: buckets, thresholds: thresholds)
        XCTAssertEqual(bucketsOnly.vigorousMin, 30, "no count on a bucket: the older-day path has no floor")
    }

    /// The witness moves when a late PPG estimate lands inside a minute that already had a bucket (the
    /// weakest confidence in the bucket drops), which a count and a last start alone would miss.
    func testWitness_movesWhenPPGRowsFillAnExistingMinute() {
        let t0 = Int(morning.timeIntervalSince1970)
        let measured = (0..<30).map { HRBucket(ts: t0 + $0 * 60, bpm: 150, minBpm: 150, maxBpm: 150) }
        let filled = (0..<30).map { HRBucket(ts: t0 + $0 * 60, bpm: 150, minBpm: 150, maxBpm: 150, conf: 0.8) }
        XCTAssertEqual(IntradayWitness(buckets: measured).count, IntradayWitness(buckets: filled).count)
        XCTAssertEqual(IntradayWitness(buckets: measured).maxTs, IntradayWitness(buckets: filled).maxTs)
        XCTAssertNotEqual(IntradayWitness(buckets: measured), IntradayWitness(buckets: filled))
        XCTAssertEqual(IntradayWitness(buckets: []), IntradayWitness(count: 0, maxTs: 0, sum: 0))
    }

    /// A workout crossing midnight is credited once, to the day it started on, never to both days.
    func testWorkoutsOnly_creditTheDayTheSessionStarted() throws {
        let start = Fixtures.local(2026, 2, 17, hour: 23, minute: 30)
        let run = WorkoutRow(startTs: Int(start.timeIntervalSince1970), endTs: Int(start.timeIntervalSince1970) + 3_600,
                             sport: "Running", source: "my-whoop", durationS: 3_600, energyKcal: nil, avgHr: nil, maxHr: nil,
                             strain: nil, distanceM: nil, zonesJSON: #"{"z1":10,"z2":10,"z3":20,"z4":40,"z5":20}"#,
                             notes: nil, steps: nil)
        let startDay = Fixtures.dayKey(start), morningAfter = Fixtures.dayKey(start.addingTimeInterval(3_600))
        XCTAssertNotEqual(startDay, morningAfter, "precondition: the run crosses midnight")
        XCTAssertEqual(IntradayDayStore.workouts(startedOn: startDay, rows: [run]).count, 1)
        XCTAssertTrue(IntradayDayStore.workouts(startedOn: morningAfter, rows: [run]).isEmpty)

        let first = IntradayDayStore.compute(day: startDay, buckets: [], thresholds: thresholds,
                                             workouts: IntradayDayStore.workouts(startedOn: startDay, rows: [run]))
        let second = IntradayDayStore.compute(day: morningAfter, buckets: [], thresholds: thresholds,
                                              workouts: IntradayDayStore.workouts(startedOn: morningAfter, rows: [run]))
        XCTAssertEqual(first.basis, .workoutsOnly)
        XCTAssertEqual(first.vigorousMin, 36, "Zones 4 + 5: 60 % of 60 min")
        XCTAssertEqual(second.credited, 0, "the hour after midnight is not counted again")
        XCTAssertEqual(first.credited + second.credited, 84, "one hour of running, credited once in the week")
    }

    // MARK: The day store over a repository (an in-memory WhoopStore, a file of its own)

    /// The anchor "now" of the repository tests: day keys come from it, never from the machine's clock.
    private let evening = Fixtures.local(2026, 2, 18, hour: 20)
    /// Moderate from Zone 3 (126 bpm), vigorous from Zone 4 (144 bpm): no resting reference is seeded.
    private let zones = HRZones.zones(maxHR: 180)

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("IntensityMinutesTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(IntradayDayStore.fileName)
    }

    /// Measured heart rate from `hour` on `day`: `minutes` at `bpm`, one sample every `every` seconds.
    private func measured(_ day: String, hour: Int, minutes: Int, bpm: Int, every: Int = 1) -> [HRSample] {
        let t0 = Int(BaselineReadouts.localMidnight(of: day)!.timeIntervalSince1970) + hour * 3_600
        return stride(from: 0, to: minutes * 60, by: every).map { HRSample(ts: t0 + $0, bpm: bpm) }
    }

    /// PPG-derived heart rate (`ppgHrSample`, what a WHOOP 5.0 / MG and a 4.0 on v25 bank) at 1 Hz.
    private func ppg(_ day: String, hour: Int, minutes: Int, bpm: Int, conf: Double = 0.8) -> [PpgHrSample] {
        let t0 = Int(BaselineReadouts.localMidnight(of: day)!.timeIntervalSince1970) + hour * 3_600
        return (0..<(minutes * 60)).map { PpgHrSample(ts: t0 + $0, bpm: bpm, conf: conf) }
    }

    @MainActor
    private func repository(_ store: WhoopStore) -> Repository {
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        return repo
    }

    @MainActor
    private func read(_ dayStore: IntradayDayStore, _ repo: Repository, _ days: [String]) async -> [String: IntradayDayRecord] {
        await dayStore.records(repo, effortHRmax: 180, zoneSet: zones, days: days, mode: .strapFirst,
                               entered: true, now: evening)
    }

    /// A day whose heart rate is all PPG-derived has a measured fingerprint of (0, 0), yet it is read and
    /// scored, inside the verify window (from its samples) and outside it (from its buckets), and kept.
    @MainActor
    func testStore_scoresAPPGOnlyDay_whoseMeasuredFingerprintIsZero() async throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let recent = Fixtures.dayKey(evening, minus: 3), old = Fixtures.dayKey(evening, minus: 30)
        let store = try await WhoopStore.inMemory()
        for day in [recent, old] {
            try await store.insert(Streams(ppgHr: ppg(day, hour: 9, minutes: 30, bpm: 150)), deviceId: "my-whoop")
        }
        let repo = repository(store)
        for day in [recent, old] {
            let start = Int(BaselineReadouts.localMidnight(of: day)!.timeIntervalSince1970)
            let fp = await repo.hrFingerprint(from: start, to: start + 86_399)
            XCTAssertEqual(fp?.count, 0, "precondition: nothing in the measured table")
        }

        let records = await read(IntradayDayStore(fileURL: url), repo, [old, recent])
        for day in [recent, old] {
            let r = try XCTUnwrap(records[day], day)
            XCTAssertEqual(r.vigorousMin, 30, day)
            XCTAssertEqual(r.scoredMinutes, 30, day)
            XCTAssertEqual(r.bpmMax, 150, day)
            XCTAssertTrue(r.recordedIntensity, day)
        }
        XCTAssertEqual(IntradayDayStore(fileURL: url).storedRecords[old]?.credited, 60, "persisted, scored")
    }

    /// Sparse live heart rate first (two samples a minute: no minute passes the floor), then the strap's
    /// PPG estimates for the same half hour land. The measured fingerprint does not move; the record does.
    @MainActor
    func testStore_recomputesADayWhenPPGRowsLandAfterSparseLiveHR() async throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = Fixtures.dayKey(evening, minus: 2)
        let store = try await WhoopStore.inMemory()
        try await store.insert(Streams(hr: measured(day, hour: 9, minutes: 30, bpm: 150, every: 30)), deviceId: "my-whoop")
        let repo = repository(store)
        let start = Int(BaselineReadouts.localMidnight(of: day)!.timeIntervalSince1970)
        let before = await repo.hrFingerprint(from: start, to: start + 86_399)

        let firstRead = await read(IntradayDayStore(fileURL: url), repo, [day])
        let first = try XCTUnwrap(firstRead[day])
        XCTAssertEqual(first.scoredMinutes, 0, "two samples a minute score nothing")
        XCTAssertEqual(first.credited, 0)

        try await store.insert(Streams(ppgHr: ppg(day, hour: 9, minutes: 30, bpm: 150)), deviceId: "my-whoop")
        let after = await repo.hrFingerprint(from: start, to: start + 86_399)
        XCTAssertEqual(before?.count, after?.count, "precondition: the measured fingerprint did not move")
        XCTAssertEqual(before?.maxTs, after?.maxTs)

        // A new launch (no memo, the persisted record): the buckets moved, so the day is read again.
        let secondRead = await read(IntradayDayStore(fileURL: url), repo, [day])
        let second = try XCTUnwrap(secondRead[day])
        XCTAssertEqual(second.scoredMinutes, 30)
        XCTAssertEqual(second.vigorousMin, 30)
    }

    /// Live heart rate lands with no `refreshSeq` bump: today is never served from the memo, so a walk
    /// banked after the first read shows on the next one. A past day stands until the next refresh.
    @MainActor
    func testStore_rereadsTodayAtTheSameRefreshSeq() async throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let today = Fixtures.dayKey(evening), yesterday = Fixtures.dayKey(evening, minus: 1)
        let store = try await WhoopStore.inMemory()
        try await store.insert(Streams(hr: measured(today, hour: 8, minutes: 10, bpm: 150)
                                           + measured(yesterday, hour: 8, minutes: 10, bpm: 150)), deviceId: "my-whoop")
        let repo = repository(store)
        let dayStore = IntradayDayStore(fileURL: url)

        let first = await read(dayStore, repo, [yesterday, today])
        XCTAssertEqual(first[today]?.vigorousMin, 10)
        XCTAssertEqual(first[yesterday]?.vigorousMin, 10)

        try await store.insert(Streams(hr: measured(today, hour: 12, minutes: 20, bpm: 150)
                                           + measured(yesterday, hour: 12, minutes: 20, bpm: 150)), deviceId: "my-whoop")
        let seq = repo.refreshSeq
        let second = await read(dayStore, repo, [yesterday, today])
        XCTAssertEqual(repo.refreshSeq, seq, "precondition: no refresh in between")
        XCTAssertEqual(second[today]?.vigorousMin, 30, "today's noon walk is counted at once")
        XCTAssertEqual(second[yesterday]?.vigorousMin, 10, "a past day waits for the next refreshSeq")
    }

    /// An older day's record is trusted without a read while the store under it is the same one; when
    /// the store's identity moves (a backup restored brings older nights) the day is read again once.
    @MainActor
    func testStore_rereadsAnOlderDayWhenTheStoreIdentityMoves() async throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = Fixtures.dayKey(evening, minus: 40)
        let store = try await WhoopStore.inMemory()
        _ = try await store.upsertDailyMetrics([Fixtures.metric(Fixtures.dayKey(evening, minus: 45), sleepMin: 420)],
                                               deviceId: "my-whoop-noop")
        try await store.insert(Streams(hr: measured(old, hour: 9, minutes: 20, bpm: 150)), deviceId: "my-whoop")
        let repo = repository(store)
        await repo.refresh()
        XCTAssertTrue(repo.loaded, "precondition: the identity needs the first refresh")
        let firstIdentity = IntradayDayStore.storeIdentity(repo)
        let identity = try XCTUnwrap(firstIdentity)
        XCTAssertEqual(identity, "my-whoop|" + Fixtures.dayKey(evening, minus: 45))

        let firstRead = await read(IntradayDayStore(fileURL: url), repo, [old])
        let first = try XCTUnwrap(firstRead[old])
        XCTAssertEqual(first.vigorousMin, 20)
        XCTAssertEqual(first.storeIdentity, identity)

        // Rows land on the old day behind the record (a restore). Same store identity: trusted, no read.
        try await store.insert(Streams(hr: measured(old, hour: 14, minutes: 10, bpm: 150)), deviceId: "my-whoop")
        let trustedRead = await read(IntradayDayStore(fileURL: url), repo, [old])
        let trusted = try XCTUnwrap(trustedRead[old])
        XCTAssertEqual(trusted.vigorousMin, 20, "an older day is not re-read while the store is the same one")

        // The restore also brought older nights: the identity moves and the day is read again.
        _ = try await store.upsertDailyMetrics([Fixtures.metric(Fixtures.dayKey(evening, minus: 90), sleepMin: 400)],
                                               deviceId: "my-whoop-noop")
        await repo.refresh()
        let movedIdentity = IntradayDayStore.storeIdentity(repo)
        let moved = try XCTUnwrap(movedIdentity)
        XCTAssertNotEqual(moved, identity)
        let rereadRead = await read(IntradayDayStore(fileURL: url), repo, [old])
        let reread = try XCTUnwrap(rereadRead[old])
        XCTAssertEqual(reread.vigorousMin, 30)
        XCTAssertEqual(reread.storeIdentity, moved)
    }
}
