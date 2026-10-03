import XCTest
@testable import Baseline

/// Friends copy that must say one thing the same way everywhere: "Your days" in each competition rule's own
/// unit (bars, line, caption and VoiceOver agree), step sources as words, and the standings place column
/// (ordinals, ties counted across the full standings even when the card draws only the top three).
@MainActor
final class FriendsCopyTests: XCTestCase {

    private let profile = FriendsProfile(id: UUID(), displayName: "Pat", stepGoal: 8_000, intensityGoal: 140)

    private func day(_ key: String, value: Int, points: Int, capped: Bool = false) -> DayPoints {
        DayPoints(day: key, value: value, points: points, capped: capped)
    }

    // MARK: Your days

    func testYourDays_stepsPercentOfOwnGoal_isPointsWithTheLineAt100() {
        let y = YourDays([day("2026-10-05", value: 9_000, points: 113)], metric: .steps, mode: .goalPercent, profile: profile)
        XCTAssertEqual(y.bars, [113])
        XCTAssertEqual(y.goal, 100)
        XCTAssertEqual(y.spoken, "Mon 5 Oct, 113 points")
        XCTAssertTrue(y.caption.contains("100 points"), y.caption)
    }

    func testYourDays_intensityPercentOfOwnGoal_isMinutesAgainstASeventhOfTheWeeklyGoal() {
        // 140 a week → a 20-minute line; the server's points for this rule are window-wide, so a day is minutes.
        let y = YourDays([day("2026-10-05", value: 40, points: 40)], metric: .intensity, mode: .goalPercent, profile: profile)
        XCTAssertEqual(y.bars, [40])
        XCTAssertEqual(y.goal, 20)
        XCTAssertEqual(y.spoken, "Mon 5 Oct, 40 min")
        XCTAssertFalse(y.caption.contains("points"), y.caption)
        XCTAssertTrue(y.caption.contains("20 min"), y.caption)
    }

    func testYourDays_stepsTotal_saysStepsNotPoints() {
        let days = [day("2026-10-05", value: 12_400, points: 12_400), day("2026-10-06", value: 60_000, points: 60_000, capped: true)]
        let y = YourDays(days, metric: .steps, mode: .total, profile: profile)
        XCTAssertNil(y.goal)
        XCTAssertEqual(y.spoken, "Mon 5 Oct, 12,400 steps; Tue 6 Oct, 60,000 steps, capped")
        XCTAssertEqual(y.caption, "Best day 60,000 steps. Bars with an orange cap hit the daily cap.")
    }

    func testYourDays_daysAtGoal_saysAtGoalOrMissed() {
        let days = [day("2026-10-05", value: 9_010, points: 1), day("2026-10-06", value: 4_000, points: 0)]
        let y = YourDays(days, metric: .steps, mode: .daysAtGoal, profile: profile)
        XCTAssertEqual(y.bars, [1, 0])
        XCTAssertNil(y.goal)
        XCTAssertEqual(y.spoken, "Mon 5 Oct, At goal, 9,010 steps; Tue 6 Oct, Missed, 4,000 steps")
        XCTAssertFalse(y.caption.contains("points"), y.caption)
    }

    func testYourDays_nightsTotal_neverSaysPoints() {
        let y = YourDays([day("2026-10-05", value: 1, points: 1)], metric: .sleepGoal, mode: .total, profile: profile)
        XCTAssertEqual(y.spoken, "Mon 5 Oct, At sleep goal")
        XCTAssertEqual(y.caption, "Full bars are nights at your own sleep goal.")
    }

    // MARK: Step sources

    func testSourceText_isWords() {
        XCTAssertEqual(CompetitionDetailScreen.sourceText("phone+strap"), "strap and iPhone")
        XCTAssertEqual(CompetitionDetailScreen.sourceText("strap"), "strap")
        XCTAssertEqual(CompetitionDetailScreen.sourceText("phone"), "iPhone")
    }

    // MARK: Roster without scores

    /// competition_standings sends no rows to someone invited (or who left while it runs), so the detail names who
    /// is in it and says why there are no scores, instead of an empty Standings card.
    func testRosterWithoutScores_namesWhoIsIn_andSaysWhy() {
        let me = UUID()
        let members = [CompetitionMember(userID: UUID(), name: "Alex", state: .joined),
                       CompetitionMember(userID: me, name: "Pat", state: .invited),
                       CompetitionMember(userID: UUID(), name: "Priya", state: .invited),
                       CompetitionMember(userID: UUID(), name: "Sam", state: .joined)]
        XCTAssertEqual(CompetitionDetailScreen.rosterText(members, me: me), "Alex and Sam have joined. Priya is invited.")
        XCTAssertEqual(CompetitionDetailScreen.rosterText([members[1]], me: me), "Nobody else has joined yet.")
        XCTAssertEqual(CompetitionDetailScreen.nameList(["Alex", "Sam", "Priya"]), "Alex, Sam and Priya")

        func summary(_ state: MemberState, final: Bool) -> CompetitionSummary {
            CompetitionSummary(id: UUID(), metric: .steps, mode: .total, start: "2026-10-05", end: "2026-10-11",
                               createdBy: members[0].userID, myState: state, members: members,
                               freezeAt: FriendsScoring.freezeAt(endDay: "2026-10-11"), isFinal: final)
        }
        XCTAssertEqual(CompetitionDetailScreen.noScoresText(summary(.invited, final: false)), "Scores show once you join.")
        XCTAssertEqual(CompetitionDetailScreen.noScoresText(summary(.invited, final: true)),
                       "Scores went only to the people who joined.")
        XCTAssertEqual(CompetitionDetailScreen.noScoresText(summary(.left, final: false)),
                       "You left, so scores show once the results are final.")
    }

    // MARK: Standings place column

    func testPlaceColumn_usesOrdinals_andSeesATieBeyondTheTopThree() {
        func row(_ name: String, _ score: Int, _ place: Int) -> Standing {
            Standing(userID: UUID(), name: name, state: .joined, score: score, place: place,
                     daysCounted: 7, cappedDays: 0, sharing: true, sourceMix: nil)
        }
        let rows = [row("Alex", 900, 1), row("Ben", 800, 2), row("Cat", 700, 3), row("Dee", 700, 3)]
        XCTAssertEqual(CompetitionTopBars.placeText(rows[0], in: rows), "1st")
        XCTAssertEqual(CompetitionTopBars.placeText(rows[1], in: rows), "2nd")
        // The card draws only the top three, but the tie with Dee (4th row) still shows.
        XCTAssertEqual(CompetitionTopBars.placeText(rows[2], in: rows), "=3rd")
        XCTAssertEqual(CompetitionTopBars.placeSpoken(rows[2], in: rows), "tied 3rd")
    }
}
