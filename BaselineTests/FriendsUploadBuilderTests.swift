import XCTest
@testable import Baseline

/// `FriendsUploadBuilder`: what leaves the phone. Only shared metrics, only derived forms (capped daily integers,
/// 0/1 nights, clipped weekly deltas), only whitelisted JSON keys.
final class FriendsUploadBuilderTests: XCTestCase {

    private let today = "2026-10-07"   // Wednesday

    private func inputs() -> FriendsUploadInputs { FriendsUploadInputs(today: today) }

    func testNoShares_buildsNothing() {
        var i = inputs()
        i.stepDays[today] = .init(value: 9_000, source: "strap")
        let (days, trends) = FriendsUploadBuilder.build(i, shares: [:], days: [today])
        XCTAssertTrue(days.isEmpty)
        XCTAssertTrue(trends.isEmpty)
    }

    func testOnlySharedMetricsAppear() {
        var i = inputs()
        i.stepDays[today] = .init(value: 9_000, source: "strap")
        i.intensityDays[today] = 25
        i.nights[today] = .init(asleepMinutes: 480, bedMinuteOfDay: 23 * 60)
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.intensity: .competitions], days: [today])
        XCTAssertEqual(days, [DailyShare(day: today, metric: .intensity, value: 25)])
    }

    func testSteps_estimateAndImportExcluded_strapAndPhoneKeptWithSource() {
        var i = inputs()
        i.stepDays["2026-10-04"] = .init(value: 4_000, source: "estimate")
        i.stepDays["2026-10-05"] = .init(value: 5_000, source: "import")
        i.stepDays["2026-10-06"] = .init(value: 6_000, source: "phone")
        i.stepDays["2026-10-07"] = .init(value: 7_000, source: "strap")
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.steps: .friends],
                                                   days: FriendsDates.days(from: "2026-10-04", to: today))
        XCTAssertEqual(days, [
            DailyShare(day: "2026-10-06", metric: .steps, value: 6_000, source: "phone"),
            DailyShare(day: "2026-10-07", metric: .steps, value: 7_000, source: "strap"),
        ])
    }

    func testSteps_over60000_isCappedAndFlagged() {
        var i = inputs()
        i.stepDays[today] = .init(value: 70_000, source: "strap")
        i.intensityDays[today] = 400
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.steps: .friends, .intensity: .friends], days: [today])
        XCTAssertEqual(days.first { $0.metric == .steps }, DailyShare(day: today, metric: .steps, value: 60_000, source: "strap", capped: true))
        XCTAssertEqual(days.first { $0.metric == .intensity }, DailyShare(day: today, metric: .intensity, value: 300, capped: true))
    }

    func testSleepGoal_449is0_450is1() {
        var i = inputs()
        i.sleepGoalMinutes = 450
        i.nights["2026-10-06"] = .init(asleepMinutes: 449, bedMinuteOfDay: nil)
        i.nights["2026-10-07"] = .init(asleepMinutes: 450, bedMinuteOfDay: nil)
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.sleepGoal: .friends], days: ["2026-10-06", "2026-10-07"])
        XCTAssertEqual(days.map(\.value), [0, 1])
    }

    func testBedtime_acrossMidnight() {
        var i = inputs()
        i.targetBedMinutes = 10                     // 00:10
        i.nights[today] = .init(asleepMinutes: 420, bedMinuteOfDay: 23 * 60 + 50)   // 23:50 → 20 min away
        i.nights["2026-10-06"] = .init(asleepMinutes: 420, bedMinuteOfDay: 1 * 60)  // 01:00 → 50 min away
        i.nights["2026-10-05"] = .init(asleepMinutes: 420, bedMinuteOfDay: nil)     // no clock time → no row
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.bedtime: .friends],
                                                   days: ["2026-10-05", "2026-10-06", today])
        XCTAssertEqual(days, [DailyShare(day: "2026-10-06", metric: .bedtime, value: 0),
                              DailyShare(day: today, metric: .bedtime, value: 1)])
    }

    func testActiveDays_from20IntensityMinutesOrA20MinuteWorkout() {
        var i = inputs()
        i.intensityDays["2026-10-05"] = 20
        i.intensityDays["2026-10-06"] = 19
        i.workoutMinutesByDay["2026-10-07"] = 20
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.active: .friends],
                                                   days: ["2026-10-04", "2026-10-05", "2026-10-06", today])
        XCTAssertEqual(days.map(\.day), ["2026-10-05", "2026-10-06", today], "no row for a day with neither")
        XCTAssertEqual(days.map(\.value), [1, 0, 1])
    }

    // MARK: Trends

    /// `n` valid nights at `value` ending on `today`, then the last 7 nights replaced by `recent`.
    private func nights(_ n: Int, base: Double, recent: Double?) -> [String: Double] {
        var out: [String: Double] = [:]
        for back in 0..<n { out[FriendsDates.adding(-back, to: today)] = back < 7 ? (recent ?? base) : base }
        return out
    }

    func testTrendGate_13Calibrating_14Ready() {
        var i = inputs()
        i.hrvNights = nights(13, base: 50, recent: 54)
        var (_, trends) = FriendsUploadBuilder.build(i, shares: [.hrv: .friends], days: [])
        XCTAssertEqual(trends.last, TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .calibrating))
        XCTAssertEqual(trends.count, 1, "calibrating is said once, for the current week")
        i.hrvNights = nights(14, base: 50, recent: 54)
        (_, trends) = FriendsUploadBuilder.build(i, shares: [.hrv: .friends], days: [])
        XCTAssertEqual(trends.last?.status, .ready)
        XCTAssertEqual(trends.last?.delta, 8)
    }

    func testClips_hrvPlus42To30_rhrMinus14ToMinus10() {
        var i = inputs()
        i.hrvNights = nights(30, base: 50, recent: 71)     // +42 %
        i.rhrNights = nights(30, base: 60, recent: 46)     // −14 bpm
        let (_, trends) = FriendsUploadBuilder.build(i, shares: [.hrv: .friends, .rhr: .friends], days: [])
        let hrv = trends.last { $0.metric == .hrv }
        let rhr = trends.last { $0.metric == .rhr }
        XCTAssertEqual(hrv?.delta, 30)
        XCTAssertEqual(hrv?.clipped, true)
        XCTAssertEqual(hrv?.band, .above)
        XCTAssertEqual(rhr?.delta, -10)
        XCTAssertEqual(rhr?.clipped, true)
        XCTAssertEqual(rhr?.band, .below)
    }

    func testReadiness_sevenDayMeanMinusThirtyDayMean_bandWord() {
        var i = inputs()
        i.readinessByDay = nights(30, base: 60, recent: 70)   // 7-day 70, 30-day (23×60 + 7×70)/30 = 62.33 → +8
        let (_, trends) = FriendsUploadBuilder.build(i, shares: [.readiness: .friends], days: [])
        XCTAssertEqual(trends.last?.delta, 8)
        XCTAssertEqual(trends.last?.band, .above)
        var calm = inputs()
        calm.readinessByDay = nights(30, base: 60, recent: 62)
        XCTAssertEqual(FriendsUploadBuilder.build(calm, shares: [.readiness: .friends], days: []).1.last?.band, .within,
                       "a readiness change under 5 points is within")
    }

    func testWeeklyRows_areKeyedToMonday_currentPlusFourPrevious() {
        var i = inputs()
        var hrv: [String: Double] = [:]
        for back in 0..<90 { hrv[FriendsDates.adding(-back, to: today)] = 50 }
        i.hrvNights = hrv
        let (_, trends) = FriendsUploadBuilder.build(i, shares: [.hrv: .friends], days: [])
        XCTAssertEqual(trends.map(\.weekStart), ["2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"])
        XCTAssertTrue(trends.allSatisfy { FriendsDates.isMonday($0.weekStart) })
        XCTAssertTrue(trends.allSatisfy { $0.delta == 0 && $0.band == .within })
    }

    // MARK: JSON

    func testGoldenJSON_onlyWhitelistedKeys() throws {
        var i = inputs()
        i.stepDays[today] = .init(value: 70_000, source: "strap")
        i.intensityDays[today] = 30
        i.nights[today] = .init(asleepMinutes: 480, bedMinuteOfDay: 23 * 60)
        i.hrvNights = nights(30, base: 50, recent: 54)
        let all = Dictionary(uniqueKeysWithValues: FriendsMetric.allCases.map { ($0, $0.allowedAudiences.last!) })
        let (days, trends) = FriendsUploadBuilder.build(i, shares: all, days: [today])
        let data = try JSONEncoder().encode(FriendsJSON.UploadParams(p_days: days, p_trends: trends))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["p_days", "p_trends"])
        let dayKeys = Set((obj["p_days"] as? [[String: Any]] ?? []).flatMap(\.keys))
        let trendKeys = Set((obj["p_trends"] as? [[String: Any]] ?? []).flatMap(\.keys))
        XCTAssertTrue(dayKeys.isSubset(of: ["day", "metric", "value", "source", "capped"]), "\(dayKeys)")
        XCTAssertTrue(trendKeys.isSubset(of: ["metric", "week_start", "status", "delta", "band", "clipped"]), "\(trendKeys)")
        XCTAssertFalse(dayKeys.isEmpty)
        XCTAssertFalse(trendKeys.isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("54"), "never a raw HRV value")
        XCTAssertFalse(text.contains("480"), "never sleep minutes")
        XCTAssertFalse(text.contains("1380"), "never a clock time")
    }

    // MARK: Incremental window

    func testSelect_fullOrRecentPlusChanged() {
        let rows = (0..<10).map { DailyShare(day: FriendsDates.adding(-$0, to: today), metric: .steps, value: 5_000, source: "strap") }
        XCTAssertEqual(FriendsUploadBuilder.select(rows, today: today, digest: [:], full: true).count, 10)
        let digest = FriendsUploadBuilder.updatedDigest([:], with: rows, today: today)
        XCTAssertEqual(FriendsUploadBuilder.select(rows, today: today, digest: digest, full: false).map(\.day),
                       ["2026-10-07", "2026-10-06", "2026-10-05"], "unchanged: only today and the 2 days before")
        var changed = rows
        changed[8].value = 6_000
        XCTAssertEqual(FriendsUploadBuilder.select(changed, today: today, digest: digest, full: false).map(\.day),
                       ["2026-10-07", "2026-10-06", "2026-10-05", "2026-09-29"], "plus the day whose value changed")
        XCTAssertFalse(digest.values.contains(5_000), "the digest stores hashes, never values")
    }

    /// A day this phone shared before that now has no row is retracted (value null), only inside the window and only
    /// for metrics still shared; the digest forgets it once the server accepted the retraction.
    func testRetractions_forAcceptedDaysThatLostTheirValue() throws {
        let window = FriendsUploadBuilder.fullWindow(today: today)
        let before = [
            DailyShare(day: "2026-10-06", metric: .steps, value: 9_000, source: "phone"),
            DailyShare(day: "2026-10-05", metric: .steps, value: 8_000, source: "phone"),
            DailyShare(day: "2026-10-05", metric: .sleepGoal, value: 1),
            DailyShare(day: "2026-10-05", metric: .bedtime, value: 1),
        ]
        var digest = FriendsUploadBuilder.updatedDigest([:], with: before, today: today)
        digest["steps|2026-08-01"] = 1   // outside the 35-day window: retention deletes it anyway
        // Now: 6 Oct steps resolve to an estimate (never uploaded), 5 Oct's night was edited away; bedtime is Off.
        let now = [DailyShare(day: "2026-10-05", metric: .steps, value: 8_000, source: "phone")]
        let r = FriendsUploadBuilder.retractions(rows: now, digest: digest,
                                                 shares: [.steps: .friends, .sleepGoal: .competitions], window: window)
        XCTAssertEqual(r, [DailyRetraction(day: "2026-10-05", metric: .sleepGoal),
                           DailyRetraction(day: "2026-10-06", metric: .steps)])
        let after = FriendsUploadBuilder.updatedDigest(digest, with: now, retracted: r, today: today)
        XCTAssertNil(after["steps|2026-10-06"])
        XCTAssertNil(after["sleep_goal|2026-10-05"])
        XCTAssertNotNil(after["steps|2026-10-05"])
        XCTAssertEqual(FriendsUploadBuilder.retractions(rows: now, digest: after, shares: [.steps: .friends], window: window),
                       [], "sent once")

        // On the wire: a retraction is {day, metric, value: null} in p_days, after the rows.
        let data = try JSONEncoder().encode(FriendsJSON.UploadParams(p_days: now, p_trends: [], retract: r))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let days = try XCTUnwrap(obj["p_days"] as? [[String: Any]])
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(Set(days[1].keys), ["day", "metric", "value"])
        XCTAssertTrue(days[1]["value"] is NSNull, "null value = retract that day")
        XCTAssertEqual(days[1]["metric"] as? String, "sleep_goal")
        XCTAssertEqual(days[0]["value"] as? Int, 8_000)
    }

    func testStableHash_isStableAcrossRuns() {
        XCTAssertEqual(FriendsUploadBuilder.stableHash(""), Int(truncatingIfNeeded: UInt64(0xcbf29ce484222325)))
        XCTAssertEqual(FriendsUploadBuilder.stableHash("a"), Int(truncatingIfNeeded: UInt64(0xaf63dc4c8601ec8c)))
    }

    func testDayFlags_fromTheAppReadout_winOverRawRules() {
        var i = inputs()
        // Raw fields say "not active / short night / late", the app's readout says otherwise: the readout wins.
        i.intensityDays[today] = 5
        i.nights[today] = .init(asleepMinutes: 300, bedMinuteOfDay: 2 * 60)
        i.dayFlags[today] = .init(active: 1, sleepGoal: 1, bedtime: 1)
        i.dayFlags["2026-10-06"] = .init(active: nil, sleepGoal: 0, bedtime: nil)
        let (days, _) = FriendsUploadBuilder.build(i, shares: [.active: .friends, .sleepGoal: .friends, .bedtime: .friends],
                                                   days: ["2026-10-06", today])
        XCTAssertEqual(days, [
            DailyShare(day: "2026-10-06", metric: .sleepGoal, value: 0),
            DailyShare(day: today, metric: .active, value: 1),
            DailyShare(day: today, metric: .sleepGoal, value: 1),
            DailyShare(day: today, metric: .bedtime, value: 1),
        ])
    }
}
