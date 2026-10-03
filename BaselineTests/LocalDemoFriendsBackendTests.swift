import XCTest
@testable import Baseline

/// `LocalDemoFriendsBackend`: the in-memory backend the simulator, sample data and UI tests use. It must follow the
/// server's rules where a person trying the tab would notice.
final class LocalDemoFriendsBackendTests: XCTestCase {

    /// Wednesday 7 Oct 2026, 12:00 UTC.
    private let noon = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!
    private let utc = TimeZone(identifier: "UTC")!

    private func backend(_ start: LocalDemoFriendsBackend.StartState = .ready) -> LocalDemoFriendsBackend {
        let now = noon
        return LocalDemoFriendsBackend(start: start, now: { now }, timeZone: utc)
    }

    func testFullFlow_signIn_profile_share_invite_redeem_accept_compete() async throws {
        let b = backend(.signedOut)
        let signedOutID = await b.currentUserID()
        XCTAssertNil(signedOutID)
        try await b.signInDemo()
        let missing = try await b.myProfile()
        XCTAssertNil(missing, "signed in without a profile: the setup sheet")
        do {
            _ = try await b.completeProfile(displayName: "Pat", ageConfirmed: false)
            XCTFail("16+ is required")
        } catch { XCTAssertEqual(error as? FriendsError, .ageRequired) }
        let me = try await b.completeProfile(displayName: "  Pat ", ageConfirmed: true)
        XCTAssertEqual(me.displayName, "Pat")
        try await b.setShare(.steps, audience: .friends, consentVersion: 1)

        // Invite: own code → invite_self; Casey's code → pending outgoing, then already_friends.
        let invite = try await b.createInvite()
        XCTAssertNotNil(FriendInviteCode.normalize(invite.code))
        await assertThrows(.inviteSelf) { _ = try await b.peekInvite(invite.code) }
        let peek = try await b.peekInvite(LocalDemoFriendsSeed.caseyCode.lowercased())
        XCTAssertEqual(peek.name, "Casey")
        let redeemed = try await b.redeemInvite(LocalDemoFriendsSeed.caseyCode)
        XCTAssertEqual(redeemed.name, "Casey")
        await assertThrows(.alreadyFriends) { _ = try await b.redeemInvite(LocalDemoFriendsSeed.caseyCode) }
        var o = try await b.overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertEqual(o.outgoing.map(\.name), ["Casey"])
        XCTAssertEqual(o.incoming.map(\.name), ["Chris"])

        // Accept Chris's request.
        try await b.respondFriend(LocalDemoFriendsSeed.chrisID, accept: true)
        o = try await b.overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertTrue(o.accepted.contains { $0.name == "Chris" })

        // Create a steps competition with Alex and read the standings.
        let id = try await b.createCompetition(CompetitionDraft(metric: .steps, mode: .goalPercent, start: "2026-10-06",
                                                                end: "2026-10-12", invitees: [LocalDemoFriendsSeed.alexID]))
        let standings = try await b.standings(id)
        XCTAssertEqual(Set(standings.rows.map(\.name)), ["Pat", "Alex"])
        XCTAssertEqual(standings.myDays.map(\.day), ["2026-10-06", "2026-10-07"], "days so far only")
        XCTAssertFalse(standings.isFinal)
    }

    func testDemoCodes_errors() async throws {
        let b = backend()
        await assertThrows(.inviteExpired) { _ = try await b.peekInvite(LocalDemoFriendsSeed.expiredCode) }
        await assertThrows(.inviteUsed) { _ = try await b.redeemInvite(LocalDemoFriendsSeed.usedCode) }
        await assertThrows(.inviteInvalid) { _ = try await b.peekInvite("ABCD2345") }
        await assertThrows(.inviteInvalid) { _ = try await b.peekInvite("DEM0") }
        let own = try await b.createInvite()
        XCTAssertEqual(own.code, LocalDemoFriendsSeed.firstOwnCode)
        await assertThrows(.inviteSelf) { _ = try await b.redeemInvite(own.code) }
        for code in [LocalDemoFriendsSeed.caseyCode, LocalDemoFriendsSeed.expiredCode, LocalDemoFriendsSeed.usedCode,
                     LocalDemoFriendsSeed.firstOwnCode] {
            XCTAssertEqual(FriendInviteCode.normalize(code), code, "\(code) must be typeable")
        }
    }

    func testOff_deletesMyRows() async throws {
        let b = backend()
        var o = try await b.overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertFalse(o.myDays.filter { $0.metric == .steps }.isEmpty)
        try await b.setShare(.steps, audience: nil, consentVersion: 1)
        o = try await b.overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertTrue(o.myDays.filter { $0.metric == .steps }.isEmpty)
        XCTAssertNil(o.myShares[.steps])
    }

    func testPhysiology_neverCompetitionsOnly() async {
        let b = backend()
        await assertThrows(.invalidAudience) { try await b.setShare(.hrv, audience: .competitions, consentVersion: 1) }
    }

    /// Like competition_standings: an invited person sees who is in it, not their scores, until they join.
    func testInvitedViewer_seesTheRosterButNoScores_untilJoining() async throws {
        let b = backend()
        let invited = try await b.standings(LocalDemoFriendsSeed.invitationCompetitionID)
        XCTAssertEqual(invited.summary.myState, .invited)
        XCTAssertTrue(invited.rows.isEmpty, "no scores while only invited")
        XCTAssertTrue(invited.myDays.isEmpty)
        XCTAssertFalse(invited.summary.members.isEmpty, "the roster is still there")
        try await b.respondCompetition(LocalDemoFriendsSeed.invitationCompetitionID, accept: true)
        let joined = try await b.standings(LocalDemoFriendsSeed.invitationCompetitionID)
        XCTAssertFalse(joined.rows.isEmpty, "joining shows the standings")
    }

    func testJoin_needsTheMetricShared() async throws {
        let b = backend()
        try await b.setShare(.intensity, audience: nil, consentVersion: 1)
        await assertThrows(.metricNotShared) {
            try await b.respondCompetition(LocalDemoFriendsSeed.invitationCompetitionID, accept: true)
        }
        try await b.setShare(.intensity, audience: .competitions, consentVersion: 1)
        try await b.respondCompetition(LocalDemoFriendsSeed.invitationCompetitionID, accept: true)
        let list = try await b.competitions()
        XCTAssertEqual(list.first { $0.id == LocalDemoFriendsSeed.invitationCompetitionID }?.myState, .joined)
    }

    func testBlock_removesTheFriendship_andHideHides() async throws {
        let b = backend()
        try await b.setHidden(LocalDemoFriendsSeed.alexID, hidden: true)
        var o = try await b.overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertEqual(o.friends.first { $0.id == LocalDemoFriendsSeed.alexID }?.iHide, true)
        XCTAssertEqual(o.hiddenFromCount, 1)
        try await b.block(LocalDemoFriendsSeed.alexID)
        o = try await b.overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertFalse(o.friends.contains { $0.id == LocalDemoFriendsSeed.alexID })
        let standings = try await b.standings(LocalDemoFriendsSeed.activeCompetitionID)
        XCTAssertFalse(standings.rows.contains { $0.userID == LocalDemoFriendsSeed.alexID }, "blocked people drop out")
    }

    func testOnlyTheCreatorRemovesParticipants() async throws {
        let b = backend()
        await assertThrows(.notCreator) {
            try await b.removeParticipant(LocalDemoFriendsSeed.invitationCompetitionID, user: LocalDemoFriendsSeed.samID)
        }
        try await b.removeParticipant(LocalDemoFriendsSeed.activeCompetitionID, user: LocalDemoFriendsSeed.priyaID)
    }

    func testSeed_isDeterministic_andShapedLikeTheSpec() async throws {
        let a = try await backend().overview(from: "2026-09-07", to: "2026-10-08")
        let b = try await backend().overview(from: "2026-09-07", to: "2026-10-08")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.accepted.map(\.name), ["Alex", "Jordan", "Priya", "Sam"])
        let jordan = a.accepted.first { $0.name == "Jordan" }!
        XCTAssertFalse(jordan.sharedBehaviour.contains(.steps), "Jordan shares steps only in competitions")
        XCTAssertTrue(a.accepted.first { $0.name == "Priya" }!.trends.isEmpty, "Priya shares no physiology")
        XCTAssertTrue(a.accepted.first { $0.name == "Sam" }!.trends.allSatisfy { $0.status == .calibrating })
        XCTAssertEqual(Set(a.accepted.map(\.profile.stepGoal)), [6_000, 8_000, 10_000, 7_500])

        let comps = try await backend().competitions()
        XCTAssertEqual(comps.count, 3)
        let finished = try await backend().standings(LocalDemoFriendsSeed.finishedCompetitionID)
        XCTAssertTrue(finished.isFinal)
        let top = finished.rows.filter { $0.place == 1 }
        XCTAssertEqual(top.count, 2, "the finished bedtime competition is a tie: Tied 1st")
        let active = try await backend().standings(LocalDemoFriendsSeed.activeCompetitionID)
        XCTAssertTrue(active.rows.contains { $0.name == "Jordan" && $0.sharing },
                      "competition-level sharing counts in standings")
    }

    func testCreateCompetition_validates() async {
        let b = backend()
        await assertThrows(.tooManyParticipants) {
            _ = try await b.createCompetition(CompetitionDraft(metric: .steps, mode: .total, start: "2026-10-12",
                                                               end: "2026-10-18", invitees: []))
        }
        await assertThrows(.invalidMode) {
            _ = try await b.createCompetition(CompetitionDraft(metric: .bedtime, mode: .goalPercent, start: "2026-10-12",
                                                               end: "2026-10-18", invitees: [LocalDemoFriendsSeed.alexID]))
        }
        await assertThrows(.invalidWindow) {
            _ = try await b.createCompetition(CompetitionDraft(metric: .steps, mode: .total, start: "2026-10-12",
                                                               end: "2026-11-30", invitees: [LocalDemoFriendsSeed.alexID]))
        }
        await assertThrows(.notFriends) {
            _ = try await b.createCompetition(CompetitionDraft(metric: .steps, mode: .total, start: "2026-10-12",
                                                               end: "2026-10-18", invitees: [LocalDemoFriendsSeed.chrisID]))
        }
    }

    func testUpload_dropsUnsharedAndCaps() async throws {
        let b = backend()
        let r = try await b.upload(days: [
            DailyShare(day: "2026-10-07", metric: .steps, value: 70_000, source: "strap"),
            DailyShare(day: "2026-10-07", metric: .steps, value: 5_000, source: "estimate"),
            DailyShare(day: "2026-08-01", metric: .intensity, value: 30),
        ], trends: [])
        XCTAssertEqual(r.accepted, 1)
        XCTAssertEqual(r.dropped, 2)
        let o = try await b.overview(from: "2026-10-07", to: "2026-10-07")
        XCTAssertEqual(o.myDays.first { $0.metric == .steps }?.value, 60_000)
        XCTAssertEqual(o.myDays.first { $0.metric == .steps }?.capped, true)
    }

    private func assertThrows(_ expected: FriendsError, _ work: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await work()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? FriendsError, expected, file: file, line: line)
        }
    }
}
