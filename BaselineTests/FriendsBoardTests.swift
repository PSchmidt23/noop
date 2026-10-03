import XCTest
@testable import Baseline

/// `FriendsBoard`: the leaderboard, its headline, the friend cards and the physiology copy. Behaviour is ranked; HRV,
/// resting HR and readiness never are, and never sort anything.
final class FriendsBoardTests: XCTestCase {

    private let today = "2026-10-07"   // a Wednesday: the week so far is Mon 5 – Wed 7
    private let meID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    private func profile(_ name: String, goal: Int = 8_000, id: UUID = UUID()) -> FriendsProfile {
        FriendsProfile(id: id, displayName: name, stepGoal: goal, intensityGoal: 150)
    }

    private func steps(_ values: [Int], from start: String = "2026-10-05") -> [DailyShare] {
        values.enumerated().map { i, v in
            DailyShare(day: FriendsDates.adding(i, to: start), metric: .steps, value: v, source: "strap")
        }
    }

    private func overview(me myDays: [DailyShare], share: Bool = true, friends: [Friend]) -> FriendsOverview {
        FriendsOverview(me: profile("Pat", id: meID), myShares: share ? [.steps: .friends] : [:], myDays: myDays,
                        friends: friends)
    }

    func testGoalPercent_ordersByPoints_withTotalSecond() {
        // Alex (goal 6,000) walks fewer steps than Priya (goal 10,000) but more of their own goal.
        let alex = Friend(profile: profile("Alex", goal: 6_000), status: .accepted, days: steps([6_000, 6_000, 6_000]))
        let priya = Friend(profile: profile("Priya", goal: 10_000), status: .accepted, days: steps([8_000, 8_000, 8_000]))
        let board = FriendsBoard.board(metric: .steps, scoring: .goalPercent, window: .week, today: today,
                                       overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [priya, alex]),
                                       competitive: true)
        // Alex and You tie on points (300 each); You walked more steps, so the total orders the tie for display.
        XCTAssertEqual(board.rows.map(\.name), ["You", "Alex", "Priya"])
        XCTAssertEqual(board.rows.map(\.score), [300, 300, 240])
        XCTAssertEqual(board.rows.map(\.place), [1, 1, 3])
        XCTAssertEqual(board.rows.map(\.tied), [true, true, false])
        XCTAssertEqual(board.rows.first?.valueText, "100 % of own goal · \(FriendsBoard.number(8_000)) a day")
        XCTAssertEqual(board.rows[2].valueText, "80 % of own goal · \(FriendsBoard.number(8_000)) a day")
    }

    func testTotalScoring_ranksRawSteps() {
        let alex = Friend(profile: profile("Alex", goal: 6_000), status: .accepted, days: steps([6_000, 6_000, 6_000]))
        let board = FriendsBoard.board(metric: .steps, scoring: .total, window: .week, today: today,
                                       overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [alex]),
                                       competitive: true)
        XCTAssertEqual(board.rows.map(\.name), ["You", "Alex"])
        XCTAssertEqual(board.rows.first?.valueText, "\(FriendsBoard.number(24_000)) steps")
        XCTAssertEqual(board.headline, "You're 1st of 2")
    }

    func testHeadline_namesOnlyThePersonDirectlyAbove() {
        let a = Friend(profile: profile("Alex"), status: .accepted, days: steps([10_000, 10_000, 10_000]))   // 375
        let b = Friend(profile: profile("Blair"), status: .accepted, days: steps([8_000, 8_000, 8_480]))     // 306
        let c = Friend(profile: profile("Cleo"), status: .accepted, days: steps([1_000, 1_000, 1_000]))      // 39
        let board = FriendsBoard.board(metric: .steps, scoring: .goalPercent, window: .week, today: today,
                                       overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [a, b, c]),
                                       competitive: true)
        // The gap is in the rows' unit: Blair's row reads 102 % of own goal and yours 100 %, so 2 % (not the 6
        // summed points behind the ranking, which no row prints).
        XCTAssertEqual(board.rows.first { $0.name == "Blair" }?.valueText.hasPrefix("102 % of own goal"), true)
        XCTAssertEqual(board.rows.first(where: \.isMe)?.valueText.hasPrefix("100 % of own goal"), true)
        XCTAssertEqual(board.headline, "You're 3rd of 4 · 2 % behind Blair")
    }

    func testHeadline_goalPercentGapUnderOnePercent() {
        // 301 summed points against 300 over 3 days: both rows read 100 % of own goal.
        let a = Friend(profile: profile("Alex"), status: .accepted, days: steps([8_000, 8_000, 8_040]))   // 100.5 → 101
        let board = FriendsBoard.board(metric: .steps, scoring: .goalPercent, window: .week, today: today,
                                       overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [a]),
                                       competitive: true)
        XCTAssertEqual(board.rows.map(\.score), [301, 300])
        XCTAssertEqual(board.headline, "You're 2nd of 2 · less than 1 % behind Alex")
    }

    func testHeadline_totalGapUsesTheRowsUnit() {
        let a = Friend(profile: profile("Alex"), status: .accepted, days: steps([9_000, 9_000, 9_240]))
        let board = FriendsBoard.board(metric: .steps, scoring: .total, window: .week, today: today,
                                       overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [a]),
                                       competitive: true)
        XCTAssertEqual(board.headline, "You're 2nd of 2 · \(FriendsBoard.number(3_240)) steps behind Alex")
    }

    func testNumbers_followTheDeviceLocale() {
        XCTAssertEqual(FriendsBoard.number(9_010, locale: Locale(identifier: "en_US")), "9,010")
        XCTAssertEqual(FriendsBoard.number(48_200, locale: Locale(identifier: "de_DE")), "48.200")
        XCTAssertEqual(FriendsBoard.number(48_200), 48_200.formatted(.number), "the same formatter as the friend cards")
    }

    func testHeadline_tiedAndFirst() {
        let a = Friend(profile: profile("Alex"), status: .accepted, days: steps([8_000, 8_000, 8_000]))
        let tied = FriendsBoard.board(metric: .steps, scoring: .goalPercent, window: .week, today: today,
                                      overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [a]), competitive: true)
        XCTAssertEqual(tied.headline, "Tied 1st of 2")
        let first = FriendsBoard.board(metric: .steps, scoring: .goalPercent, window: .week, today: today,
                                       overview: overview(me: steps([9_000, 9_000, 9_000]), friends: [a]), competitive: true)
        XCTAssertEqual(first.headline, "You're 1st of 2")
    }

    func testCompetitiveViewOff_isAlphabetical_withoutPlacesOrHeadline() {
        let z = Friend(profile: profile("Zoe"), status: .accepted, days: steps([20_000, 20_000, 20_000]))
        let a = Friend(profile: profile("Alex"), status: .accepted, days: steps([1_000, 1_000, 1_000]))
        let board = FriendsBoard.board(metric: .steps, scoring: .goalPercent, window: .week, today: today,
                                       overview: overview(me: steps([8_000, 8_000, 8_000]), friends: [z, a]),
                                       competitive: false)
        XCTAssertEqual(board.rows.map(\.name), ["You", "Alex", "Zoe"])
        XCTAssertTrue(board.rows.allSatisfy { $0.place == nil })
        XCTAssertNil(board.headline)
    }

    func testNonSharersCounted_andMeExcludedWhenIDontShare() {
        let sharer = Friend(profile: profile("Alex"), status: .accepted, days: steps([8_000]))
        let quiet1 = Friend(profile: profile("Jordan"), status: .accepted)
        let quiet2 = Friend(profile: profile("Sam"), status: .accepted,
                            days: [DailyShare(day: "2026-10-05", metric: .bedtime, value: 1)])
        let pending = Friend(profile: profile("Chris"), status: .pendingIncoming)
        let board = FriendsBoard.board(metric: .steps, scoring: .total, window: .week, today: today,
                                       overview: overview(me: steps([8_000]), share: false,
                                                          friends: [sharer, quiet1, quiet2, pending]),
                                       competitive: true)
        XCTAssertEqual(board.nonSharers, 2)
        XCTAssertEqual(board.nonSharersText, "2 friends don't share steps")
        XCTAssertFalse(board.meIncluded)
        XCTAssertFalse(board.rows.contains { $0.isMe })
        XCTAssertNil(board.headline)
        XCTAssertEqual(FriendsBoard.Board.rankingCaption,
                       "Ranked on what you do. HRV, resting HR and readiness are never ranked.")
    }

    func testFriendCards_areAlphabetical_mutedSplitOff() {
        let names = ["sam", "Alex", "Priya", "jordan"]
        let friends = names.map { Friend(profile: profile($0), status: .accepted) }
        let muted: Set<UUID> = [friends[2].id]
        let cards = FriendsBoard.friendCards(overview(me: [], friends: friends), muted: muted)
        XCTAssertEqual(cards.visible.map(\.name), ["Alex", "jordan", "sam"])
        XCTAssertEqual(cards.muted.map(\.name), ["Priya"])
    }

    func testPhysiologyIsNeverSortedByValue() {
        // Pills come in the fixed HRV, Resting HR, Readiness order, whatever the values.
        let trends = [
            TrendShare(metric: .readiness, weekStart: "2026-10-05", status: .ready, delta: 15, band: .above),
            TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: -20, band: .below),
            TrendShare(metric: .rhr, weekStart: "2026-10-05", status: .ready, delta: 3, band: .within),
        ]
        XCTAssertEqual(FriendsBoard.pills(trends), [
            "HRV −20 % vs own baseline", "Resting HR +3 bpm vs own baseline", "Readiness +15 vs own month",
        ])
        // Friend cards with very different HRV changes stay alphabetical.
        let big = Friend(profile: profile("Zed"), status: .accepted,
                         trends: [TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: 30, band: .above, clipped: true)])
        let small = Friend(profile: profile("Amy"), status: .accepted,
                           trends: [TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: -5, band: .within)])
        XCTAssertEqual(FriendsBoard.friendCards(overview(me: [], friends: [big, small]), muted: []).visible.map(\.name),
                       ["Amy", "Zed"])
    }

    func testTrendPillsAndSentences() {
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: 8, band: .within)),
                       "HRV +8 % vs own baseline")
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .rhr, weekStart: "2026-10-05", status: .ready, delta: -2, band: .within)),
                       "Resting HR −2 bpm vs own baseline")
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .readiness, weekStart: "2026-10-05", status: .ready, delta: 4, band: .within)),
                       "Readiness +4 vs own month")
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .calibrating)),
                       "HRV · calibrating")
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: 30, band: .above, clipped: true)),
                       "HRV ≥ +30 % vs own baseline")
        // A clipped DROP is at least that far below: "≤ −30", never "≥ −30" (which would mean −30 or higher).
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: -30, band: .below, clipped: true)),
                       "HRV ≤ −30 % vs own baseline")
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .rhr, weekStart: "2026-10-05", status: .ready, delta: -10, band: .below, clipped: true)),
                       "Resting HR ≤ −10 bpm vs own baseline")
        XCTAssertEqual(FriendsBoard.trendPill(TrendShare(metric: .readiness, weekStart: "2026-10-05", status: .ready, delta: 15, band: .above, clipped: true)),
                       "Readiness ≥ +15 vs own month")
        XCTAssertEqual(FriendsBoard.trendSentence(TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: -30, band: .below, clipped: true), name: "Alex"),
                       "HRV is at least 30 % below Alex's own baseline, below their usual range.")
        XCTAssertEqual(FriendsBoard.trendSentence(TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: 8, band: .within), name: "Alex"),
                       "HRV is 8 % above Alex's own baseline, within their usual range.")
        for text in [FriendsBoard.trendFootnote] + FriendsBoard.pills([
            TrendShare(metric: .hrv, weekStart: "2026-10-05", status: .ready, delta: 8, band: .within)]) {
            XCTAssertFalse(text.contains(" ms"), "never a raw HRV unit")
        }
    }

    func testGoalDots_andSummary() {
        let p = profile("Alex", goal: 8_000)
        let days = steps([9_000, 7_000, 8_000])
        let dots = FriendsBoard.goalDots(days: days, metric: .steps, profile: p, today: today)
        XCTAssertEqual(dots, [.met, .missed, .met, .none, .none, .none, .none])
        XCTAssertEqual(FriendsBoard.dotsSummary(dots), "2 of 7 goal days")
        let intensity = [DailyShare(day: "2026-10-05", metric: .intensity, value: 22)]
        XCTAssertEqual(FriendsBoard.goalDots(days: intensity, metric: .intensity, profile: p, today: today).first, .met,
                       "intensity dots compare against the weekly goal ÷ 7 (150 → 21)")
    }

    func testUpdatedText() {
        XCTAssertEqual(FriendsDates.updatedText(lastDay: "2026-10-07", today: today), "Updated today")
        XCTAssertEqual(FriendsDates.updatedText(lastDay: "2026-10-06", today: today), "Updated yesterday")
        XCTAssertEqual(FriendsDates.updatedText(lastDay: "2026-10-04", today: today), "Updated 3 days ago")
        XCTAssertNil(FriendsDates.updatedText(lastDay: nil, today: today))
    }

    func testBoardMetrics_needBothSides() {
        let alex = Friend(profile: profile("Alex"), status: .accepted,
                          days: steps([8_000]) + [DailyShare(day: "2026-10-05", metric: .bedtime, value: 1)])
        var o = overview(me: [], friends: [alex])
        o.myShares = [.steps: .friends, .intensity: .friends, .bedtime: .competitions]
        XCTAssertEqual(FriendsBoard.boardMetrics(overview: o), [.steps],
                       "bedtime is shared by me only for competitions; intensity by no friend")
    }
}
