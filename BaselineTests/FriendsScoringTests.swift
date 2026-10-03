import XCTest
@testable import Baseline

/// `FriendsScoring`: the Swift mirror of `private.competition_scores` in Baseline/Backend/supabase/schema.sql. The same
/// fixture is asserted in tests/scoring.sql and the schema's SELFTEST block, so SQL and Swift cannot drift silently.
final class FriendsScoringTests: XCTestCase {

    private let week = FriendsDates.days(from: "2026-10-05", to: "2026-10-11")

    func testStepsGoalPercent_dayPoints() {
        XCTAssertEqual(FriendsScoring.dayPoints(metric: .steps, mode: .goalPercent, value: 12_000, goal: 8_000), 150)
        XCTAssertEqual(FriendsScoring.dayPoints(metric: .steps, mode: .goalPercent, value: 20_000, goal: 8_000), 200,
                       "a day is capped at 2× the goal")
        XCTAssertEqual(FriendsScoring.dayPoints(metric: .steps, mode: .goalPercent, value: 0, goal: 8_000), 0)
    }

    func testStepsGoalPercent_sevenDaysAtTheCap() {
        let values = Dictionary(uniqueKeysWithValues: week.map { ($0, 20_000) })
        XCTAssertEqual(FriendsScoring.score(metric: .steps, mode: .goalPercent, goal: 8_000, window: week, values: values), 1_400)
    }

    func testStepsGoalPercent_missingDaysCountZero_lateJoiner() {
        let values = ["2026-10-09": 8_000, "2026-10-10": 8_000, "2026-10-11": 8_000]
        XCTAssertEqual(FriendsScoring.score(metric: .steps, mode: .goalPercent, goal: 8_000, window: week, values: values), 300)
    }

    func testGoalFloor() {
        XCTAssertEqual(FriendsScoring.storedStepGoal(2_000), 3_000, "a 2,000 goal is stored as 3,000")
        XCTAssertEqual(FriendsScoring.storedStepGoal(40_000), 30_000)
        let p = FriendsProfile(id: UUID(), displayName: "Ana", stepGoal: 2_000, intensityGoal: 20)
        XCTAssertEqual(FriendsScoring.lockedGoal(metric: .steps, profile: p), 3_000)
        XCTAssertEqual(FriendsScoring.lockedGoal(metric: .intensity, profile: p), 60)
        XCTAssertNil(FriendsScoring.lockedGoal(metric: .bedtime, profile: p))
    }

    func testIntensityGoalPercent_threeDayWindow() {
        let window = FriendsDates.days(from: "2026-10-05", to: "2026-10-07")
        XCTAssertEqual(FriendsScoring.intensityTarget(weeklyGoal: 150, days: 3), 64.29, accuracy: 0.005)
        let values = ["2026-10-05": 30, "2026-10-07": 40]
        XCTAssertEqual(FriendsScoring.score(metric: .intensity, mode: .goalPercent, goal: 150, window: window, values: values), 109)
    }

    /// Exact half points round UP, as Postgres `round(numeric)` does (the same cases are in tests/scoring.sql and the
    /// SELFTEST). In Double, 435 ÷ 3,000 × 100 is 14.4999… and 201 ÷ 200 × 100 is 100.4999…, a point low each.
    func testHalfPoints_roundUpLikeNumeric() {
        XCTAssertEqual(FriendsScoring.dayPoints(metric: .steps, mode: .goalPercent, value: 435, goal: 3_000), 15)
        XCTAssertEqual(FriendsScoring.score(metric: .steps, mode: .goalPercent, goal: 3_000, window: ["2026-08-03"],
                                            values: ["2026-08-03": 435]), 15)
        let week = FriendsDates.days(from: "2026-08-10", to: "2026-08-16")
        XCTAssertEqual(FriendsScoring.score(metric: .intensity, mode: .goalPercent, goal: 200, window: week,
                                            values: ["2026-08-10": 201]), 101)
        let fourDays = FriendsDates.days(from: "2026-08-10", to: "2026-08-13")
        XCTAssertEqual(FriendsScoring.score(metric: .intensity, mode: .goalPercent, goal: 200, window: fourDays,
                                            values: ["2026-08-11": 44]), 39, "44 of 114.29 = 38.5")
        XCTAssertEqual(FriendsScoring.roundedRatio(29, 2), 15)
        XCTAssertEqual(FriendsScoring.roundedRatio(28, 3), 9)
        XCTAssertEqual(FriendsScoring.roundedRatio(0, 0), 0, "a zero divisor counts as 1")
    }

    /// The integer formula against exact rational rounding over the whole steps input space a competition can hold
    /// (goals 3,000–30,000, values 0–60,000): round(min(v/g, 2) × 100) with ties up, computed as 2·100v vs (2k+1)·g.
    func testStepsDayPoints_matchExactRationalRounding() {
        var wrong: [String] = []
        for g in stride(from: 3_000, through: 30_000, by: 500) {
            for v in 0...60_000 {
                let k = FriendsScoring.dayPoints(metric: .steps, mode: .goalPercent, value: v, goal: g)
                // k is right when k − ½ ≤ 100v/g < k + ½, i.e. (2k − 1)·g ≤ 200v < (2k + 1)·g; at the cap, 200v ≥ 399g.
                let ok = k == 200 ? 200 * v >= 399 * g : ((2 * k - 1) * g <= 200 * v && 200 * v < (2 * k + 1) * g)
                if !ok { wrong.append("goal \(g), \(v) steps → \(k)") }
            }
        }
        XCTAssertEqual(wrong, [], "\(wrong.prefix(5))")
    }

    func testTotal_capsAt60000_andCountsCappedDays() {
        let c = FriendsScoring.capped(.steps, 70_000)
        XCTAssertEqual(c.value, 60_000)
        XCTAssertTrue(c.capped)
        let member = FriendsScoring.MemberInput(userID: UUID(), name: "Ben", state: .joined, goal: 8_000, sharing: true,
                                                values: ["2026-10-12": c.value], cappedDays: ["2026-10-12"])
        let rows = FriendsScoring.standings(metric: .steps, mode: .total, window: ["2026-10-12"], members: [member])
        XCTAssertEqual(rows.first?.score, 60_000)
        XCTAssertEqual(rows.first?.cappedDays, 1)
    }

    func testDaysAtGoal() {
        let window = FriendsDates.days(from: "2026-09-01", to: "2026-09-04")
        let values = ["2026-09-01": 9_000, "2026-09-02": 7_999, "2026-09-03": 8_000, "2026-09-04": 0]
        XCTAssertEqual(FriendsScoring.score(metric: .steps, mode: .daysAtGoal, goal: 8_000, window: window, values: values), 2)
    }

    func testTies_sharePlaces_andPrintTied() {
        let a = UUID(), b = UUID(), c = UUID()
        let places = FriendsScoring.places([(id: a, score: 300), (id: b, score: 300), (id: c, score: 200)])
        XCTAssertEqual(places[a], 1)
        XCTAssertEqual(places[b], 1)
        XCTAssertEqual(places[c], 3, "rank(): the place after a tie is skipped")
        XCTAssertTrue(FriendsScoring.isTied(a, places: places))
        XCTAssertFalse(FriendsScoring.isTied(c, places: places))
        XCTAssertEqual(FriendsScoring.placeText(1, tied: true), "=1st")
        XCTAssertEqual(FriendsScoring.placeText(3, tied: false), "3rd")
        XCTAssertEqual(FriendsScoring.placeSpoken(1, tied: true), "tied 1st")
        XCTAssertEqual(FriendsScoring.placeSpoken(3, tied: false), "3rd")
    }

    func testOrdinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(FriendsScoring.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st"])
    }

    func testNonSharerHasNoScoreOrPlace_andLeftIsUnranked() {
        let a = UUID(), b = UUID(), c = UUID()
        let values = ["2026-10-05": 8_000]
        let rows = FriendsScoring.standings(metric: .steps, mode: .total, window: week, members: [
            .init(userID: a, name: "Ana", state: .joined, goal: 8_000, sharing: true, values: values),
            .init(userID: b, name: "Ben", state: .joined, goal: 8_000, sharing: false, values: values),
            .init(userID: c, name: "Cleo", state: .left, goal: 8_000, sharing: true, values: ["2026-10-05": 20_000]),
        ])
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.userID, $0) })
        XCTAssertEqual(byID[a]?.place, 1)
        XCTAssertNil(byID[b]?.score, "not sharing → null score")
        XCTAssertNil(byID[b]?.place)
        XCTAssertEqual(byID[c]?.score, 20_000, "a person who left keeps their score…")
        XCTAssertNil(byID[c]?.place, "…but is not ranked")
        XCTAssertEqual(rows.map(\.userID), [a, c, b], "ranked first, then left, then not sharing")
    }

    func testScoresDependOnDayKeysOnly_notTheTimeZone() {
        let values = ["2026-10-05": 12_000, "2026-10-06": 20_000]
        let reference = FriendsScoring.score(metric: .steps, mode: .goalPercent, goal: 8_000, window: week, values: values)
        for id in ["Pacific/Kiritimati", "America/Los_Angeles", "Asia/Kolkata", "UTC"] {
            let zone = TimeZone(identifier: id)!
            // The window is rebuilt from keys the way a phone in that zone would; keys are calendar dates.
            let instant = FriendsDates.date("2026-10-08")!.addingTimeInterval(12 * 3600)
            let local = FriendsDates.localKey(instant, timeZone: zone)
            let w = FriendsDates.week(containing: local)
            XCTAssertEqual(w, week, id)
            XCTAssertEqual(FriendsScoring.score(metric: .steps, mode: .goalPercent, goal: 8_000, window: w, values: values),
                           reference, id)
        }
    }

    func testFreezeAt_isEndPlusThreeDaysNoonUTC() {
        let expected = ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z")!
        XCTAssertEqual(FriendsScoring.freezeAt(endDay: "2026-10-12"), expected)
    }

    func testMyDays_pointsAndCappedMark() {
        let days = FriendsScoring.myDays(metric: .steps, mode: .goalPercent, goal: 8_000, window: week,
                                         values: ["2026-10-05": 12_000, "2026-10-06": 60_000], cappedDays: ["2026-10-06"],
                                         through: "2026-10-07")
        XCTAssertEqual(days.map(\.day), ["2026-10-05", "2026-10-06", "2026-10-07"], "only days so far")
        XCTAssertEqual(days.map(\.points), [150, 200, 0])
        XCTAssertEqual(days.map(\.capped), [false, true, false])
    }
}
