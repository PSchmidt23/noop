import Foundation

/// The live backend: the person's own Supabase project (Baseline/Backend/supabase/schema.sql), reached only through
/// `SupabaseREST`. Every write is an RPC (clients have no table write grants); reads are the two invoker RPCs
/// `friends_overview` / `my_competitions`, the definer `competition_standings`, and one `profiles` select for the
/// caller's own row. Friends' data is decoded into memory and never written to disk.
final class SupabaseFriendsBackend: FriendsBackend, @unchecked Sendable {
    let kind: FriendsBackendKind = .live
    let rest: SupabaseREST

    init(rest: SupabaseREST) { self.rest = rest }

    convenience init(config: FriendsConfig, keychain: FriendsKeychain = FriendsKeychain()) {
        self.init(rest: SupabaseREST(config: config, keychain: keychain))
    }

    // MARK: - Session

    func currentUserID() async -> UUID? { await rest.userID }

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await rest.signInWithIdToken(idToken: idToken, nonce: nonce)
    }

    func signInDemo() async throws { throw FriendsError.unconfigured }

    func signOut() async { await rest.logout() }

    /// The Edge Function revokes the Apple token (when a fresh authorization code is given) and ALWAYS deletes the
    /// auth user, which cascades every row. If the function is unreachable or not deployed, the `delete_account`
    /// RPC deletes the user instead (no Apple revoke). The local session is cleared either way.
    func deleteAccount(appleAuthorizationCode: String?) async throws -> Bool {
        var payload: [String: Any] = [:]
        if let appleAuthorizationCode { payload["authorizationCode"] = appleAuthorizationCode }
        let body = try JSONSerialization.data(withJSONObject: payload)
        var revoked = false
        var deleted = false
        if let r = try? await rest.function("delete-account", body: body), (200..<300).contains(r.status) {
            let obj = (try? JSONSerialization.jsonObject(with: r.data)) as? [String: Any]
            deleted = (obj?["deleted"] as? Bool) ?? true
            revoked = (obj?["revoked"] as? Bool) ?? false
        }
        if !deleted {
            _ = try await rest.rpc("delete_account")
        }
        await rest.clearSession()
        return revoked
    }

    // MARK: - Profile & consent

    func myProfile() async throws -> FriendsProfile? {
        guard let id = await rest.userID else { throw FriendsError.notSignedIn }
        let data = try await rest.select("profiles", query: [
            URLQueryItem(name: "select", value: "id,display_name,step_goal,intensity_goal"),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
        ])
        return try FriendsJSON.decode([FriendsProfile].self, data).first
    }

    func completeProfile(displayName: String, ageConfirmed: Bool) async throws -> FriendsProfile {
        let data = try await rest.rpc("complete_profile", body: FriendsJSON.body([
            "p_display_name": displayName, "p_age_confirmed": ageConfirmed,
        ]))
        return try FriendsJSON.decode(FriendsProfile.self, data)
    }

    func updateProfile(displayName: String?, stepGoal: Int?, intensityGoal: Int?) async throws {
        _ = try await rest.rpc("update_profile", body: FriendsJSON.body([
            "p_display_name": displayName, "p_step_goal": stepGoal, "p_intensity_goal": intensityGoal,
        ]))
    }

    func setShare(_ metric: FriendsMetric, audience: ShareAudience?, consentVersion: Int) async throws {
        _ = try await rest.rpc("set_share", body: FriendsJSON.body([
            "p_metric": metric.rawValue, "p_audience": audience?.rawValue, "p_consent_version": consentVersion,
        ]))
    }

    func upload(days: [DailyShare], trends: [TrendShare], retract: [DailyRetraction]) async throws
        -> (accepted: Int, dropped: Int) {
        let body = try JSONEncoder().encode(FriendsJSON.UploadParams(p_days: days, p_trends: trends, retract: retract))
        let data = try await rest.rpc("upload", body: body)
        let r = try FriendsJSON.decode(FriendsJSON.UploadResult.self, data)
        return (r.accepted, r.dropped)
    }

    func myServerData() async throws -> Data {
        try await rest.rpc("my_data")
    }

    // MARK: - Graph

    func createInvite() async throws -> (code: String, expiresAt: Date) {
        let r = try FriendsJSON.decode(FriendsJSON.Invite.self, try await rest.rpc("create_invite"))
        return (r.code, try FriendsJSON.date(r.expires_at))
    }

    /// A refused code comes back as `{"error": key}` (not an HTTP error) so the server's rate limit counts it.
    func peekInvite(_ code: String) async throws -> (name: String, expiresAt: Date) {
        let data = try await rest.rpc("peek_invite", body: FriendsJSON.body(["p_code": code]))
        try FriendsJSON.throwIfError(data)
        let r = try FriendsJSON.decode(FriendsJSON.Peek.self, data)
        return (r.display_name, try FriendsJSON.date(r.expires_at))
    }

    func redeemInvite(_ code: String) async throws -> (friendID: UUID, name: String) {
        let data = try await rest.rpc("redeem_invite", body: FriendsJSON.body(["p_code": code]))
        try FriendsJSON.throwIfError(data)
        let r = try FriendsJSON.decode(FriendsJSON.Redeem.self, data)
        return (r.friend_id, r.display_name)
    }

    func respondFriend(_ id: UUID, accept: Bool) async throws {
        _ = try await rest.rpc("respond_friend", body: FriendsJSON.body(["p_other": id.uuidString.lowercased(), "p_accept": accept]))
    }

    func setHidden(_ id: UUID, hidden: Bool) async throws {
        _ = try await rest.rpc("set_hidden", body: FriendsJSON.body(["p_other": id.uuidString.lowercased(), "p_hidden": hidden]))
    }

    func removeFriend(_ id: UUID) async throws {
        _ = try await rest.rpc("remove_friend", body: FriendsJSON.body(["p_other": id.uuidString.lowercased()]))
    }

    func block(_ id: UUID) async throws {
        _ = try await rest.rpc("block_user", body: FriendsJSON.body(["p_other": id.uuidString.lowercased()]))
    }

    func unblock(_ id: UUID) async throws {
        _ = try await rest.rpc("unblock_user", body: FriendsJSON.body(["p_other": id.uuidString.lowercased()]))
    }

    func report(_ id: UUID, reason: ReportReason, competition: UUID?) async throws {
        _ = try await rest.rpc("report_user", body: FriendsJSON.body([
            "p_other": id.uuidString.lowercased(), "p_reason": reason.rawValue,
            "p_competition": competition?.uuidString.lowercased(),
        ]))
    }

    // MARK: - Reads

    func overview(from: String, to: String) async throws -> FriendsOverview {
        let data = try await rest.rpc("friends_overview", body: FriendsJSON.body(["p_from": from, "p_to": to]))
        return try FriendsJSON.overview(data)
    }

    // MARK: - Competitions

    func competitions() async throws -> [CompetitionSummary] {
        let data = try await rest.rpc("my_competitions")
        return try FriendsJSON.decode([FriendsJSON.Competition].self, data).map { try $0.summary() }
    }

    func createCompetition(_ draft: CompetitionDraft) async throws -> UUID {
        let data = try await rest.rpc("create_competition", body: FriendsJSON.body([
            "p_metric": draft.metric.rawValue, "p_mode": draft.mode.rawValue, "p_start": draft.start, "p_end": draft.end,
            "p_invitees": draft.invitees.map { $0.uuidString.lowercased() },
        ]))
        return try FriendsJSON.uuidScalar(data)
    }

    func respondCompetition(_ id: UUID, accept: Bool) async throws {
        _ = try await rest.rpc("respond_competition", body: FriendsJSON.body(["p_id": id.uuidString.lowercased(), "p_accept": accept]))
    }

    func leaveCompetition(_ id: UUID) async throws {
        _ = try await rest.rpc("leave_competition", body: FriendsJSON.body(["p_id": id.uuidString.lowercased()]))
    }

    func removeParticipant(_ id: UUID, user: UUID) async throws {
        _ = try await rest.rpc("remove_participant", body: FriendsJSON.body([
            "p_id": id.uuidString.lowercased(), "p_user": user.uuidString.lowercased(),
        ]))
    }

    func standings(_ id: UUID) async throws -> CompetitionStandings {
        let data = try await rest.rpc("competition_standings", body: FriendsJSON.body(["p_id": id.uuidString.lowercased()]))
        return try FriendsJSON.standings(data)
    }
}

/// The server's JSON shapes (snake_case, exactly as schema.sql builds them) and their mapping onto the contract.
enum FriendsJSON {

    /// An RPC body from named parameters; nil values become JSON null (PostgREST then uses the SQL default).
    static func body(_ params: [String: Any?]) -> Data {
        var obj: [String: Any] = [:]
        for (k, v) in params { obj[k] = v ?? NSNull() }
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// A bare JSON string scalar holding a uuid (`"…"`), as PostgREST returns a `uuid` function result.
    static func uuidScalar(_ data: Data) throws -> UUID {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
        guard let id = UUID(uuidString: text) else { throw FriendsError.server }
        return id
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw FriendsError.server }
    }

    /// An RPC that answers a refusal as `{"error": "invite_invalid"}` instead of raising (peek_invite, redeem_invite:
    /// a raise would roll back their rate-limit bump). Throws that key as a `FriendsError`, `.server` when unknown.
    static func throwIfError(_ data: Data) throws {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let key = obj["error"] as? String else { return }
        throw FriendsError(rawValue: key) ?? .server
    }

    /// Postgres timestamptz as jsonb renders it ("2026-10-15T12:00:00+00:00", fractional seconds optional).
    static func date(_ s: String) throws -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
        // "2026-10-15 12:00:00+00" (text cast) as a last resort.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ssX"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        throw FriendsError.server
    }

    /// The `upload` body. Retractions travel in `p_days` as `{day, metric, value: null}` after the rows.
    struct UploadParams: Encodable {
        let p_days: [UploadDay]
        let p_trends: [TrendShare]

        init(p_days: [DailyShare], p_trends: [TrendShare], retract: [DailyRetraction] = []) {
            self.p_days = p_days.map(UploadDay.row) + retract.map(UploadDay.retract)
            self.p_trends = p_trends
        }
    }

    /// One element of `p_days`: a value, or a retraction of that day.
    enum UploadDay: Encodable {
        case row(DailyShare)
        case retract(DailyRetraction)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .row(let r): try r.encode(to: encoder)
            case .retract(let r): try r.encode(to: encoder)
            }
        }
    }

    struct UploadResult: Decodable { let accepted: Int; let dropped: Int }
    struct Invite: Decodable { let code: String; let expires_at: String }
    struct Peek: Decodable { let display_name: String; let expires_at: String }
    struct Redeem: Decodable { let friend_id: UUID; let display_name: String }

    struct Share: Decodable { let metric: FriendsMetric; let audience: ShareAudience }

    struct Person: Decodable {
        let id: UUID
        let display_name: String
        let step_goal: Int
        let intensity_goal: Int
        let status: String
        let requested_by_me: Bool

        var profile: FriendsProfile {
            FriendsProfile(id: id, displayName: display_name, stepGoal: step_goal, intensityGoal: intensity_goal)
        }
        var friendStatus: FriendStatus {
            if status == "accepted" { return .accepted }
            return requested_by_me ? .pendingOutgoing : .pendingIncoming
        }
    }

    struct Day: Decodable {
        let user_id: UUID
        let day: String
        let metric: FriendsMetric
        let value: Int
        let source: String?
        let capped: Bool
        var share: DailyShare { DailyShare(day: day, metric: metric, value: value, source: source, capped: capped) }
    }

    struct Trend: Decodable {
        let user_id: UUID
        let metric: FriendsMetric
        let week_start: String
        let status: TrendStatus
        let delta: Int?
        let band: TrendBand?
        let clipped: Bool
        var share: TrendShare {
            TrendShare(metric: metric, weekStart: week_start, status: status, delta: delta, band: band, clipped: clipped)
        }
    }

    struct Overview: Decodable {
        let me: FriendsProfile
        let my_shares: [Share]
        let hides: [UUID]
        let friends: [Person]
        let days: [Day]
        let trends: [Trend]
    }

    static func overview(_ data: Data) throws -> FriendsOverview {
        let o = try decode(Overview.self, data)
        let hides = Set(o.hides)
        var shares: [FriendsMetric: ShareAudience] = [:]
        for s in o.my_shares { shares[s.metric] = s.audience }
        let daysBy = Dictionary(grouping: o.days, by: \.user_id)
        let trendsBy = Dictionary(grouping: o.trends, by: \.user_id)
        let friends = o.friends.map { p in
            Friend(profile: p.profile, status: p.friendStatus, iHide: hides.contains(p.id),
                   days: (daysBy[p.id] ?? []).map(\.share).sorted { $0.day < $1.day },
                   trends: (trendsBy[p.id] ?? []).map(\.share).sorted { $0.weekStart < $1.weekStart })
        }
        return FriendsOverview(me: o.me, myShares: shares,
                               myDays: (daysBy[o.me.id] ?? []).map(\.share).sorted { $0.day < $1.day },
                               myTrends: (trendsBy[o.me.id] ?? []).map(\.share).sorted { $0.weekStart < $1.weekStart },
                               friends: friends)
    }

    struct Member: Decodable {
        let user_id: UUID
        let display_name: String
        let state: MemberState
    }

    struct Competition: Decodable {
        let id: UUID
        let metric: FriendsMetric
        let mode: CompetitionMode
        let start_day: String
        let end_day: String
        let created_by: UUID
        let freeze_at: String
        let finalized: Bool
        let my_state: MemberState?
        let members: [Member]

        func summary(now: Date = Date()) throws -> CompetitionSummary {
            let freeze = try FriendsJSON.date(freeze_at)
            return CompetitionSummary(id: id, metric: metric, mode: mode, start: start_day, end: end_day,
                                      createdBy: created_by, myState: my_state ?? .invited,
                                      members: members.map { CompetitionMember(userID: $0.user_id, name: $0.display_name, state: $0.state) },
                                      freezeAt: freeze, isFinal: finalized || now >= freeze)
        }
    }

    struct StandingRow: Decodable {
        let user_id: UUID
        let display_name: String
        let state: MemberState
        let score: Int?
        let place: Int?
        let days_counted: Int
        let capped_days: Int
        let sharing: Bool
        let source_mix: String?
    }

    struct MyDay: Decodable { let day: String; let value: Int; let points: Int; let capped: Bool }

    struct Standings: Decodable {
        let competition: Competition
        let final: Bool
        let rows: [StandingRow]
        let my_days: [MyDay]
    }

    static func standings(_ data: Data) throws -> CompetitionStandings {
        let s = try decode(Standings.self, data)
        var summary = try s.competition.summary()
        summary.isFinal = summary.isFinal || s.final
        let rows = s.rows.map {
            Standing(userID: $0.user_id, name: $0.display_name, state: $0.state, score: $0.score, place: $0.place,
                     daysCounted: $0.days_counted, cappedDays: $0.capped_days, sharing: $0.sharing, sourceMix: $0.source_mix)
        }
        return CompetitionStandings(summary: summary, rows: FriendsScoring.sortStandings(rows),
                                    myDays: s.my_days.map { DayPoints(day: $0.day, value: $0.value, points: $0.points, capped: $0.capped) },
                                    isFinal: s.final)
    }
}
