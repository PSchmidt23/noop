import XCTest
@testable import Baseline

/// `FriendsStore` against a recording fake backend: the phase machine, when an upload may run at all, the 35-day
/// first window then the incremental one, the 10-minute throttle, the sign-out wipe and the pending join code.
@MainActor
final class FriendsStoreTests: XCTestCase {

    private let suite = "baseline.tests.friendsStore"
    private var defaults: UserDefaults!
    private var clock = TestClock()
    private let utc = TimeZone(identifier: "UTC")!
    private let anonJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.c2ln"

    final class TestClock { var now = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")! }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        clock = TestClock()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeStore(_ fake: RecordingFriendsBackend, arguments: [String] = [], sample: Bool = false,
                           inputs: FriendsUploadInputs? = nil) -> FriendsStore {
        let env = FriendsStore.Environment(arguments: arguments, isDebug: true,
                                           config: FriendsConfig.make(url: "https://stub.supabase.co", key: anonJWT),
                                           sampleDataActive: { sample })
        let clock = self.clock
        let loaded = inputs ?? stepInputs()
        return FriendsStore(environment: env, defaults: defaults, makeBackend: { _ in fake },
                            inputsLoader: { _ in loaded }, now: { clock.now }, timeZone: utc)
    }

    /// Strap steps on every day of the 35-day window.
    private func stepInputs(value: Int = 9_000) -> FriendsUploadInputs {
        var i = FriendsUploadInputs(today: "2026-10-07")
        for day in FriendsUploadBuilder.fullWindow(today: "2026-10-07") { i.stepDays[day] = .init(value: value, source: "strap") }
        return i
    }

    /// Signed in with a profile, consent shown, sharing `shares`: the ready tab.
    private func readyStore(_ fake: RecordingFriendsBackend, shares: [FriendsMetric: ShareAudience] = [.steps: .friends],
                            arguments: [String] = [], sample: Bool = false) async -> FriendsStore {
        fake.signedIn = true
        fake.profile = FriendsProfile(id: fake.me, displayName: "Pat", stepGoal: 8_000, intensityGoal: 150)
        fake.shares = shares
        defaults.set(true, forKey: FriendsStore.consentShownKey)
        let store = makeStore(fake, arguments: arguments, sample: sample)
        await store.start()
        return store
    }

    // MARK: Phases

    func testPhaseMachine_signedOut_profile_consent_ready() async {
        let fake = RecordingFriendsBackend()
        let store = makeStore(fake)
        await store.start()
        XCTAssertEqual(store.phase, .signedOut)

        await store.signInWithApple(idToken: "t", nonce: "n")
        XCTAssertEqual(store.phase, .needsProfile)

        let badName = await store.completeProfile(displayName: "x@y", ageConfirmed: true)
        XCTAssertFalse(badName)
        XCTAssertEqual(store.lastError, .invalidName)
        let under16 = await store.completeProfile(displayName: "Pat", ageConfirmed: false)
        XCTAssertFalse(under16)
        XCTAssertEqual(store.lastError, .ageRequired)
        let made = await store.completeProfile(displayName: "Pat", ageConfirmed: true)
        XCTAssertTrue(made)
        XCTAssertEqual(store.phase, .needsConsent)

        await store.finishConsent([.steps: .friends, .hrv: .competitions])
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(fake.shareCalls.map(\.metric), [.steps], "an audience a metric can't have is never sent")
        XCTAssertEqual(fake.shareCalls.first?.version, FriendsConsent.version)
        XCTAssertTrue(defaults.bool(forKey: FriendsStore.consentShownKey))
    }

    func testShareNothingForNow_isReadyWithNoShares() async {
        let fake = RecordingFriendsBackend()
        fake.signedIn = true
        fake.profile = FriendsProfile(id: fake.me, displayName: "Pat", stepGoal: 8_000, intensityGoal: 150)
        let store = makeStore(fake)
        await store.start()
        XCTAssertEqual(store.phase, .needsConsent)
        await store.skipConsent()
        XCTAssertEqual(store.phase, .ready)
        XCTAssertTrue(fake.uploads.isEmpty)
    }

    func testReturningPersonWithShares_skipsConsent() async {
        let fake = RecordingFriendsBackend()
        fake.signedIn = true
        fake.profile = FriendsProfile(id: fake.me, displayName: "Pat", stepGoal: 8_000, intensityGoal: 150)
        fake.shares = [.steps: .friends]
        let store = makeStore(fake)
        await store.start()
        XCTAssertEqual(store.phase, .ready)
    }

    // MARK: When uploads may run

    func testNoUpload_whenNothingIsShared() async {
        let fake = RecordingFriendsBackend()
        let store = await readyStore(fake, shares: [:])
        await store.scheduleUpload(force: true)
        XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertEqual(store.uploadBlocker, "nothing shared")
    }

    func testNoUpload_onSampleData_underUITesting_orOnDemo() async {
        let sample = RecordingFriendsBackend()
        let s1 = await readyStore(sample, sample: true)
        await s1.scheduleUpload(force: true)
        XCTAssertTrue(sample.uploads.isEmpty)
        XCTAssertEqual(s1.uploadBlocker, "sample data")

        let ui = RecordingFriendsBackend()
        let s2 = await readyStore(ui, arguments: ["--ui-testing"])
        await s2.scheduleUpload(force: true)
        XCTAssertTrue(ui.uploads.isEmpty)

        let demo = RecordingFriendsBackend(kind: .demo)
        let s3 = await readyStore(demo)
        await s3.scheduleUpload(force: true)
        XCTAssertTrue(demo.uploads.isEmpty)
        XCTAssertEqual(s3.uploadBlocker, "demo")
    }

    func testFirstUploadSends35Days_thenTheIncrementalWindow() async {
        let fake = RecordingFriendsBackend()
        let store = await readyStore(fake)   // becoming ready uploads once (forced, full window)
        XCTAssertEqual(fake.uploads.count, 1)
        XCTAssertEqual(fake.uploads.first?.days.count, 35)
        XCTAssertEqual(Set(fake.uploads.first?.days.map(\.metric) ?? []), [.steps])

        clock.now.addTimeInterval(11 * 60)
        await store.scheduleUpload()
        XCTAssertEqual(fake.uploads.count, 2)
        XCTAssertEqual(fake.uploads.last?.days.map(\.day), ["2026-10-05", "2026-10-06", "2026-10-07"],
                       "unchanged history: today and the 2 days before")
    }

    func testThrottle_tenMinutes_forceBypasses() async {
        let fake = RecordingFriendsBackend()
        let store = await readyStore(fake)
        XCTAssertEqual(fake.uploads.count, 1)
        clock.now.addTimeInterval(5 * 60)
        await store.scheduleUpload()
        XCTAssertEqual(fake.uploads.count, 1, "throttled")
        await store.scheduleUpload(force: true)
        XCTAssertEqual(fake.uploads.count, 2, "force bypasses the throttle")
    }

    /// A day accepted before that no longer has a shareable value (its phone steps were deleted from Apple Health,
    /// so it resolves to a strap estimate, which is never uploaded) is retracted, and leaves the digest.
    func testADayThatLostItsValue_isRetracted() async {
        let fake = RecordingFriendsBackend()
        let store = await readyStore(fake)
        XCTAssertEqual(fake.uploads.first?.days.count, 35)
        XCTAssertEqual(fake.retractions.first, [], "nothing to retract on the first upload")

        var inputs = stepInputs()
        inputs.stepDays["2026-09-20"] = .init(value: 4_000, source: "estimate")
        inputs.stepDays["2026-10-06"] = nil
        let later = makeStore(fake, inputs: inputs)
        await later.start()   // same defaults, so the same digest
        XCTAssertEqual(fake.retractions.last, [DailyRetraction(day: "2026-09-20", metric: .steps),
                                               DailyRetraction(day: "2026-10-06", metric: .steps)])
        XCTAssertFalse(fake.uploads.last?.days.contains { $0.day == "2026-09-20" || $0.day == "2026-10-06" } ?? true)
        let digest = defaults.dictionary(forKey: FriendsStore.digestKey) as? [String: Int] ?? [:]
        XCTAssertNil(digest["steps|2026-09-20"], "a retracted day leaves the digest")
        XCTAssertNotNil(digest["steps|2026-09-21"])

        clock.now.addTimeInterval(11 * 60)
        await later.scheduleUpload()
        XCTAssertEqual(fake.retractions.last, [], "a retraction is sent once")
        _ = store
    }

    func testTurningAMetricOn_sendsTheFullWindowAgain() async {
        let fake = RecordingFriendsBackend()
        let store = await readyStore(fake)
        XCTAssertEqual(fake.uploads.count, 1)
        let turnedOn = await store.setShare(.intensity, audience: .friends)
        XCTAssertTrue(turnedOn)
        XCTAssertEqual(fake.uploads.count, 2)
        XCTAssertEqual(fake.uploads.last?.days.count, 35, "a newly shared metric resends 35 days")
    }

    // MARK: Sign-out, delete, join links

    func testSignOut_wipesLocalState() async {
        let fake = RecordingFriendsBackend()
        let store = await readyStore(fake)
        store.setMuted(UUID(), true)
        XCTAssertNotNil(defaults.object(forKey: FriendsStore.digestKey))
        XCTAssertNotNil(defaults.object(forKey: FriendsStore.mutedKey))
        await store.signOut()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.overview)
        XCTAssertTrue(store.muted.isEmpty)
        XCTAssertNil(defaults.object(forKey: FriendsStore.digestKey))
        XCTAssertNil(defaults.object(forKey: FriendsStore.mutedKey))
        XCTAssertNil(defaults.object(forKey: FriendsStore.consentShownKey))
        XCTAssertTrue(fake.signedOutCalled)
    }

    func testDelete_reportsTheRevoke_andWipes() async {
        let fake = RecordingFriendsBackend()
        fake.revokeResult = true
        let store = await readyStore(fake)
        let deleted = await store.deleteAccount(appleAuthorizationCode: "code")
        XCTAssertTrue(deleted)
        XCTAssertEqual(fake.deleteCodes, ["code"])
        XCTAssertEqual(store.lastDeleteRevoked, true)
        XCTAssertEqual(store.phase, .signedOut)
    }

    func testPendingJoinCode_survivesSignIn_thenPeeks() async {
        let fake = RecordingFriendsBackend()
        fake.profile = FriendsProfile(id: fake.me, displayName: "Pat", stepGoal: 8_000, intensityGoal: 150)
        fake.shares = [.steps: .friends]
        let store = makeStore(fake)
        await store.start()
        XCTAssertEqual(store.phase, .signedOut)
        await store.handleJoinLink(code: "abcd-2345")
        XCTAssertEqual(store.pendingJoinCode, "ABCD2345", "kept while signed out")
        XCTAssertTrue(fake.peeks.isEmpty)
        await store.signInWithApple(idToken: "t", nonce: "n")
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(fake.peeks, ["ABCD2345"])
        XCTAssertEqual(store.joinPrompt?.name, "Sam")
        XCTAssertNil(store.pendingJoinCode)
    }

    func testBadge_countsIncomingRequestsAndInvitations() async {
        let fake = RecordingFriendsBackend()
        fake.incoming = [FriendsProfile(id: UUID(), displayName: "Chris", stepGoal: 8_000, intensityGoal: 150)]
        fake.invitations = 1
        let store = await readyStore(fake)
        XCTAssertEqual(store.badgeCount, 2)
    }

    func testRematchDraft_nextMonday_stillFriendsOnly() {
        let me = UUID(), alex = UUID(), gone = UUID()
        let s = CompetitionSummary(id: UUID(), metric: .steps, mode: .daysAtGoal, start: "2026-09-21", end: "2026-09-27",
                                   createdBy: me, myState: .joined,
                                   members: [.init(userID: me, name: "Pat", state: .joined),
                                             .init(userID: alex, name: "Alex", state: .joined),
                                             .init(userID: gone, name: "Gone", state: .joined)],
                                   freezeAt: FriendsScoring.freezeAt(endDay: "2026-09-27"), isFinal: true)
        let draft = FriendsStore.rematchDraft(s, me: me, friends: [alex], today: "2026-10-07")
        XCTAssertEqual(draft, CompetitionDraft(metric: .steps, mode: .daysAtGoal, start: "2026-10-12", end: "2026-10-18",
                                               invitees: [alex]))
    }
}

/// Records what the store asks for; answers like a small, obedient server.
final class RecordingFriendsBackend: FriendsBackend, @unchecked Sendable {
    let kind: FriendsBackendKind
    let me = UUID()
    var signedIn = false
    var profile: FriendsProfile?
    var shares: [FriendsMetric: ShareAudience] = [:]
    var incoming: [FriendsProfile] = []
    var invitations = 0
    var revokeResult = false

    var uploads: [(days: [DailyShare], trends: [TrendShare])] = []
    /// The retractions sent with each upload call (same order as `uploads`).
    var retractions: [[DailyRetraction]] = []
    var shareCalls: [(metric: FriendsMetric, audience: ShareAudience?, version: Int)] = []
    var peeks: [String] = []
    var deleteCodes: [String?] = []
    var signedOutCalled = false

    init(kind: FriendsBackendKind = .live) { self.kind = kind }

    func currentUserID() async -> UUID? { signedIn ? me : nil }
    func signInWithApple(idToken: String, nonce: String) async throws { signedIn = true }
    func signInDemo() async throws { signedIn = true }
    func signOut() async { signedIn = false; signedOutCalled = true }
    func deleteAccount(appleAuthorizationCode: String?) async throws -> Bool {
        deleteCodes.append(appleAuthorizationCode); signedIn = false; profile = nil; return revokeResult
    }
    func myProfile() async throws -> FriendsProfile? {
        guard signedIn else { throw FriendsError.notSignedIn }
        return profile
    }
    func completeProfile(displayName: String, ageConfirmed: Bool) async throws -> FriendsProfile {
        let p = FriendsProfile(id: me, displayName: displayName, stepGoal: 8_000, intensityGoal: 150)
        profile = p
        return p
    }
    func updateProfile(displayName: String?, stepGoal: Int?, intensityGoal: Int?) async throws {}
    func setShare(_ metric: FriendsMetric, audience: ShareAudience?, consentVersion: Int) async throws {
        shareCalls.append((metric, audience, consentVersion))
        shares[metric] = audience
    }
    func upload(days: [DailyShare], trends: [TrendShare], retract: [DailyRetraction]) async throws
        -> (accepted: Int, dropped: Int) {
        uploads.append((days, trends))
        retractions.append(retract)
        return (days.count + trends.count + retract.count, 0)
    }
    func myServerData() async throws -> Data { Data("{}".utf8) }
    func createInvite() async throws -> (code: String, expiresAt: Date) { ("MYCQDE22", Date()) }
    func peekInvite(_ code: String) async throws -> (name: String, expiresAt: Date) { peeks.append(code); return ("Sam", Date()) }
    func redeemInvite(_ code: String) async throws -> (friendID: UUID, name: String) { (UUID(), "Sam") }
    func respondFriend(_ id: UUID, accept: Bool) async throws {}
    func setHidden(_ id: UUID, hidden: Bool) async throws {}
    func removeFriend(_ id: UUID) async throws {}
    func block(_ id: UUID) async throws {}
    func unblock(_ id: UUID) async throws {}
    func report(_ id: UUID, reason: ReportReason, competition: UUID?) async throws {}
    func overview(from: String, to: String) async throws -> FriendsOverview {
        guard let profile else { throw FriendsError.profileRequired }
        return FriendsOverview(me: profile, myShares: shares, myDays: [],
                               friends: incoming.map { Friend(profile: $0, status: .pendingIncoming) })
    }
    func competitions() async throws -> [CompetitionSummary] {
        (0..<invitations).map { _ in
            CompetitionSummary(id: UUID(), metric: .steps, mode: .total, start: "2026-10-12", end: "2026-10-18",
                               createdBy: UUID(), myState: .invited, members: [],
                               freezeAt: FriendsScoring.freezeAt(endDay: "2026-10-18"), isFinal: false)
        }
    }
    func createCompetition(_ draft: CompetitionDraft) async throws -> UUID { UUID() }
    func respondCompetition(_ id: UUID, accept: Bool) async throws {}
    func leaveCompetition(_ id: UUID) async throws {}
    func removeParticipant(_ id: UUID, user: UUID) async throws {}
    func standings(_ id: UUID) async throws -> CompetitionStandings { throw FriendsError.notMember }
}
