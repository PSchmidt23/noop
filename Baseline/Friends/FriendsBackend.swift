import Foundation

// The one seam between the Friends screens/store and a server (FRIENDS_SPEC.md §5.1). Two implementations:
// `SupabaseFriendsBackend` (Live/, the person's Supabase project over HTTPS) and `LocalDemoFriendsBackend` (Demo/,
// in memory, seeded demo friends; used under sample data, --demo-seed, --ui-testing, --friends-demo*, and the
// "Preview with demo friends" button). `FriendsBackendFactory.choose(...)` picks one.

enum FriendsBackendKind: Sendable { case live, demo }

protocol FriendsBackend: AnyObject, Sendable {
    var kind: FriendsBackendKind { get }

    // session
    func currentUserID() async -> UUID?
    func signInWithApple(idToken: String, nonce: String) async throws
    /// Demo only; the live backend throws `.unconfigured`.
    func signInDemo() async throws
    func signOut() async
    /// Deletes the account and every shared row. Returns true when the Apple token was revoked too.
    func deleteAccount(appleAuthorizationCode: String?) async throws -> Bool

    // profile & consent
    /// nil = signed in but no profile yet (the setup sheet).
    func myProfile() async throws -> FriendsProfile?
    func completeProfile(displayName: String, ageConfirmed: Bool) async throws -> FriendsProfile
    func updateProfile(displayName: String?, stepGoal: Int?, intensityGoal: Int?) async throws
    /// `audience` nil = Off: the server deletes the share row and every row of that metric in the same transaction.
    func setShare(_ metric: FriendsMetric, audience: ShareAudience?, consentVersion: Int) async throws
    /// Upserts `days` and `trends`, and deletes the caller's row for each of `retract` (a day that no longer has a
    /// shareable value). At most 175 days plus retractions per call.
    func upload(days: [DailyShare], trends: [TrendShare], retract: [DailyRetraction]) async throws
        -> (accepted: Int, dropped: Int)
    /// The `my_data` JSON (Art. 15/20 export).
    func myServerData() async throws -> Data

    // graph
    func createInvite() async throws -> (code: String, expiresAt: Date)
    func peekInvite(_ code: String) async throws -> (name: String, expiresAt: Date)
    func redeemInvite(_ code: String) async throws -> (friendID: UUID, name: String)
    func respondFriend(_ id: UUID, accept: Bool) async throws
    func setHidden(_ id: UUID, hidden: Bool) async throws
    func removeFriend(_ id: UUID) async throws
    func block(_ id: UUID) async throws
    func unblock(_ id: UUID) async throws
    func report(_ id: UUID, reason: ReportReason, competition: UUID?) async throws

    // reads
    /// `from` / `to` are day keys, at most 34 days apart.
    func overview(from: String, to: String) async throws -> FriendsOverview

    // competitions
    func competitions() async throws -> [CompetitionSummary]
    func createCompetition(_ draft: CompetitionDraft) async throws -> UUID
    func respondCompetition(_ id: UUID, accept: Bool) async throws
    func leaveCompetition(_ id: UUID) async throws
    func removeParticipant(_ id: UUID, user: UUID) async throws
    func standings(_ id: UUID) async throws -> CompetitionStandings
}

extension FriendsBackend {
    /// An upload that retracts nothing.
    func upload(days: [DailyShare], trends: [TrendShare]) async throws -> (accepted: Int, dropped: Int) {
        try await upload(days: days, trends: trends, retract: [])
    }
}
