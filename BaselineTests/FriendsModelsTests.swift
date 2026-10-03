import XCTest
@testable import Baseline

/// The Friends contract: display names, invite codes, modes, error keys and day-key arithmetic.
final class FriendsModelsTests: XCTestCase {

    func testDisplayName_validAndInvalid() {
        XCTAssertEqual(try DisplayName.validate("Ana-María").get(), "Ana-María")
        XCTAssertEqual(try DisplayName.validate("J.R.").get(), "J.R.")
        XCTAssertEqual(try DisplayName.validate("  Sam   Lee ").get(), "Sam Lee", "trimmed, whitespace collapsed")
        XCTAssertEqual(try DisplayName.validate("Ｓａｍ").get(), "Sam", "NFKC folds full-width letters")
        for bad in ["a", String(repeating: "y", count: 25), "x@y", "www.site", "http://a", "a/b", "<b>", "Tom: hi",
                    "Admin", "the moderator", "Line\u{0007}bell"] {
            XCTAssertEqual(DisplayName.validate(bad), .failure(.invalidName), bad)
        }
        XCTAssertEqual(try DisplayName.validate(String(repeating: "y", count: 24)).get().count, 24)
    }

    /// Short blocked words match only as whole words, so real names that contain one are accepted (the same cases
    /// as private.valid_name in tests/rpc.sql); long, unambiguous ones still match anywhere.
    func testDisplayName_realNamesContainingAShortBlockedWord() {
        for name in ["Nazir", "Hancock", "Alfred Hitchcock", "Yoshitaka", "Toshihiro", "Isis", "Heilmann",
                     "Hubertus Heil", "Pricket", "Slutsky", "Thorny", "Joe Bastardi", "Pornchai", "Kyson", "Pedone"] {
            XCTAssertEqual(try? DisplayName.validate(name).get(), name, name)
        }
        for bad in ["Mr Shit", "shit", "Big-Cock", "cock.99", "NAZI", "the_nazi", "Porn Star", "FuckFace", "xFUCKx",
                    "BaselineAdmin", "Hitlerfan", "Ｓｈｉｔ"] {
            XCTAssertEqual(DisplayName.validate(bad), .failure(.invalidName), bad)
        }
        XCTAssertEqual(DisplayName.words("ana-ma\u{ED}a   2nd!"), " ana ma a 2nd ", "only a–z and 0–9 make words")
        XCTAssertEqual(Set(DisplayName.blockedSubstrings).intersection(DisplayName.blockedWholeWords), [])
    }

    func testDisplayName_initials() {
        XCTAssertEqual(DisplayName.initials("Ana-María López"), "AL")
        XCTAssertEqual(DisplayName.initials("sam"), "S")
    }

    func testInviteCode_normalisation() {
        XCTAssertEqual(FriendInviteCode.normalize(" abcd-2345 "), "ABCD2345")
        XCTAssertEqual(FriendInviteCode.normalize("abcd 2345"), "ABCD2345")
        for bad in ["ABCD234O", "ABCD2340", "ABCD2341", "ABCDI345", "ABC2345", "ABCD23456", ""] {
            XCTAssertNil(FriendInviteCode.normalize(bad), bad)
        }
        XCTAssertEqual(FriendInviteCode.grouped("ABCD2345"), "ABCD 2345")
    }

    func testInviteCode_linkRoundTrip() {
        let link = FriendInviteCode.link("ABCD2345")
        XCTAssertEqual(link.absoluteString, "baseline://friends/join/ABCD2345")
        XCTAssertEqual(BaselineDeepLink.destination(for: link), .join("ABCD2345"))
        XCTAssertEqual(BaselineDeepLink.destination(for: URL(string: "baseline://friends/join/abcd-2345")!), .join("ABCD2345"))
        XCTAssertEqual(BaselineDeepLink.destination(for: URL(string: "baseline://friends/join/OOPS0000")!), .friends)
        XCTAssertEqual(Set(BaselineDeepLink.inviteCharset), Set(FriendInviteCode.charset),
                       "the widget-safe copy of the alphabet matches")
        XCTAssertTrue(FriendInviteCode.shareText("ABCD2345").contains("baseline://friends/join/ABCD2345"))
    }

    func testCompetitionModeAllowed() {
        XCTAssertEqual(CompetitionMode.allowed(for: .steps), [.goalPercent, .total, .daysAtGoal])
        XCTAssertEqual(CompetitionMode.allowed(for: .intensity), [.goalPercent, .total])
        for m in [FriendsMetric.active, .sleepGoal, .bedtime] { XCTAssertEqual(CompetitionMode.allowed(for: m), [.total]) }
        for m in FriendsMetric.physiology { XCTAssertTrue(CompetitionMode.allowed(for: m).isEmpty, "never a physiology competition") }
    }

    func testMetrics_rawValuesAndAudiences() {
        XCTAssertEqual(FriendsMetric.allCases.map(\.rawValue),
                       ["steps", "intensity", "active", "sleep_goal", "bedtime", "hrv", "rhr", "readiness"])
        for m in FriendsMetric.physiology { XCTAssertEqual(m.allowedAudiences, [.friends]) }
        for m in FriendsMetric.behaviour { XCTAssertEqual(m.allowedAudiences, [.competitions, .friends]) }
        XCTAssertEqual(FriendsMetric.steps.dailyCap, 60_000)
        XCTAssertEqual(FriendsMetric.intensity.dailyCap, 300)
    }

    func testErrorKeys_matchTheSQLKeyList() {
        let sql = ["not_signed_in", "profile_required", "invalid_name", "age_required", "invalid_audience",
                   "invite_invalid", "invite_expired", "invite_used", "invite_self", "invite_limit", "already_friends",
                   "friend_limit", "blocked", "rate_limited", "not_found", "not_friends", "not_member", "not_creator",
                   "joining_closed", "metric_not_shared", "invalid_window", "invalid_mode", "too_many_participants"]
        XCTAssertEqual(FriendsError.serverKeys.map(\.rawValue), sql)
        for key in sql { XCTAssertNotNil(FriendsError(rawValue: key), key) }
        XCTAssertEqual(FriendsError.inviteExpired.message, "That code has expired. Ask for a new one.")
    }

    func testCopyNeverUsesBannedWords() {
        let banned = ["strain", "recovery", "coach", "circles", "rings", "workweek hustle", "weekend warrior",
                      "goal day", "daily showdown", "active zone minutes", "body battery"]
        var copy: [String] = FriendsMetric.allCases.flatMap { [$0.title, $0.shortTitle, $0.sharedForm] }
        copy += FriendsError.allCases.map(\.message)
        copy += CompetitionMode.allCases.flatMap { mode in FriendsMetric.behaviour.map { mode.explanation(for: $0) } }
        copy += [FriendsConsent.paragraph, FriendsBoard.Board.rankingCaption, FriendsBoard.trendFootnote]
        for text in copy {
            for word in banned { XCTAssertFalse(text.lowercased().contains(word), "\"\(word)\" in: \(text)") }
        }
    }

    func testDayKeys() {
        XCTAssertEqual(FriendsDates.monday(of: "2026-10-07"), "2026-10-05")
        XCTAssertEqual(FriendsDates.monday(of: "2026-10-11"), "2026-10-05", "Sunday belongs to the week before")
        XCTAssertEqual(FriendsDates.monday(of: "2026-10-05"), "2026-10-05")
        XCTAssertEqual(FriendsDates.days(from: "2026-10-30", to: "2026-11-02"),
                       ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"])
        XCTAssertEqual(FriendsDates.distance(from: "2026-10-05", to: "2026-10-12"), 7)
        XCTAssertEqual(FriendsDates.rangeText(start: "2026-10-06", end: "2026-10-12"), "Tue 6 – Mon 12 Oct")
        XCTAssertEqual(FriendsDates.rangeText(start: "2026-09-28", end: "2026-10-04"), "Mon 28 Sep – Sun 4 Oct")
    }

    func testCompetitionSummary_titleAndDays() {
        let s = CompetitionSummary(id: UUID(), metric: .steps, mode: .goalPercent, start: "2026-10-05", end: "2026-10-11",
                                   createdBy: UUID(), myState: .joined, members: [],
                                   freezeAt: FriendsScoring.freezeAt(endDay: "2026-10-11"), isFinal: false)
        XCTAssertEqual(s.title, "Steps · Mon 5 – Sun 11 Oct")
        XCTAssertEqual(s.daysLeft(today: "2026-10-08"), 4)
        XCTAssertEqual(s.dayText(today: "2026-10-08"), "Day 4 of 7")
        XCTAssertEqual(s.daysLeft(today: "2026-10-12"), 0)
    }
}
