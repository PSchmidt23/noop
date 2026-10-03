import Foundation

/// The in-memory Friends backend (FRIENDS_SPEC.md §5.5): seeded demo friends and competitions, no network, no
/// Keychain, nothing persisted. Used in DEBUG demo modes, under sample data, under UI tests, and behind the intro's
/// "Preview with demo friends" button, so the tab is fully usable in the simulator before any server exists.
///
/// It enforces the same rules as schema.sql where they matter to a person trying the tab: turning a metric Off
/// deletes its rows, joining needs the metric shared (`metric_not_shared`) and closes a day after the start,
/// physiology can't be shared "only in competitions", blocking removes the friendship, hiding hides, only the
/// creator removes participants, and scores come from `FriendsScoring` (the SQL's mirror).
actor LocalDemoFriendsBackend: FriendsBackend {

    enum StartState: Sendable, Equatable {
        /// The intro with "Continue with demo account".
        case signedOut
        /// Signed in, no profile yet: the setup sheet (name, 16+, consent).
        case setup
        /// Signed in with a profile and the demo shares: the populated tab.
        case ready
    }

    nonisolated let kind: FriendsBackendKind = .demo

    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    private struct Link { var accepted: Bool; var requestedByMe: Bool }

    private struct Comp {
        var id: UUID
        var createdBy: UUID
        var metric: FriendsMetric
        var mode: CompetitionMode
        var start: String
        var end: String
        var freezeAt: Date
        /// Member order is kept for a stable display.
        var order: [UUID]
        var states: [UUID: MemberState]
        var goals: [UUID: Int]
    }

    private var signedIn = false
    private var me: FriendsProfile?
    private var myShares: [FriendsMetric: ShareAudience] = [:]
    /// Uploaded values ("metric|day"), on top of the seeded ones.
    private var myUploads: [String: DailyShare] = [:]
    private var myUploadedTrends: [TrendShare] = []
    private var people: [UUID: LocalDemoFriendsSeed.Person] = [:]
    private var links: [UUID: Link] = [:]
    private var hides: Set<UUID> = []
    private var blocks: Set<UUID> = []
    private var ownCodes: [String: Date] = [:]
    private var codeCounter = 0
    private var comps: [UUID: Comp] = [:]
    private(set) var reports: [(user: UUID, reason: ReportReason, competition: UUID?)] = []

    init(start: StartState = .ready, now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.now = now
        self.timeZone = timeZone
        let seeded = LocalDemoFriendsBackend.seed(start: start, today: FriendsDates.localKey(now(), timeZone: timeZone))
        signedIn = seeded.signedIn
        me = seeded.me
        myShares = seeded.shares
        people = seeded.people
        links = seeded.links
        comps = seeded.comps
    }

    // MARK: - Seed

    private static func seed(start: StartState, today: String)
        -> (signedIn: Bool, me: FriendsProfile?, shares: [FriendsMetric: ShareAudience],
            people: [UUID: LocalDemoFriendsSeed.Person], links: [UUID: Link], comps: [UUID: Comp]) {
        let S = LocalDemoFriendsSeed.self
        var people: [UUID: LocalDemoFriendsSeed.Person] = [:]
        for p in S.acceptedFriends + [S.chris, S.casey] { people[p.id] = p }
        var links: [UUID: Link] = [:]
        for p in S.acceptedFriends { links[p.id] = Link(accepted: true, requestedByMe: false) }
        links[S.chrisID] = Link(accepted: false, requestedByMe: false)

        let me = start == .ready
            ? FriendsProfile(id: S.meID, displayName: S.me.name, stepGoal: S.me.stepGoal, intensityGoal: S.me.intensityGoal)
            : nil
        let shares = start == .ready ? S.me.shares : [:]

        let thisMonday = FriendsDates.monday(of: today)
        let nextMonday = FriendsDates.adding(7, to: thisMonday)
        let finishedMonday = FriendsDates.adding(-14, to: thisMonday)
        func comp(_ id: UUID, by: UUID, _ metric: FriendsMetric, _ mode: CompetitionMode, start: String,
                  members: [(UUID, MemberState)]) -> Comp {
            let end = FriendsDates.adding(6, to: start)
            var states: [UUID: MemberState] = [:], goals: [UUID: Int] = [:]
            for (uid, state) in members {
                states[uid] = state
                if state == .joined, let p = uid == S.meID ? S.me : people[uid] {
                    let profile = FriendsProfile(id: uid, displayName: p.name, stepGoal: p.stepGoal, intensityGoal: p.intensityGoal)
                    if let g = FriendsScoring.lockedGoal(metric: metric, profile: profile) { goals[uid] = g }
                }
            }
            return Comp(id: id, createdBy: by, metric: metric, mode: mode, start: start, end: end,
                        freezeAt: FriendsScoring.freezeAt(endDay: end), order: members.map(\.0), states: states, goals: goals)
        }
        let active = comp(S.activeCompetitionID, by: S.meID, .steps, .goalPercent, start: thisMonday,
                          members: [(S.meID, .joined), (S.alexID, .joined), (S.jordanID, .joined), (S.priyaID, .joined)])
        let invitation = comp(S.invitationCompetitionID, by: S.alexID, .intensity, .total, start: nextMonday,
                              members: [(S.alexID, .joined), (S.samID, .joined), (S.meID, .invited)])
        let finished = comp(S.finishedCompetitionID, by: S.priyaID, .bedtime, .total, start: finishedMonday,
                            members: [(S.priyaID, .joined), (S.meID, .joined), (S.alexID, .joined)])
        let comps = [active.id: active, invitation.id: invitation, finished.id: finished]
        return (start != .signedOut, me, shares, people, links, comps)
    }

    private var today: String { FriendsDates.localKey(now(), timeZone: timeZone) }

    /// The bedtime competition's week (its fixed nights make the "Tied 1st").
    private var finishedWeek: [String] {
        guard let c = comps[LocalDemoFriendsSeed.finishedCompetitionID] else { return [] }
        return FriendsDates.days(from: c.start, to: c.end)
    }

    // MARK: - Values

    /// A person's value for one metric and day, or nil when they don't share it (at any level) or the day is ahead.
    private func value(of id: UUID, _ metric: FriendsMetric, day: String) -> DailyShare? {
        guard day <= today else { return nil }
        if id == LocalDemoFriendsSeed.meID {
            guard myShares[metric] != nil else { return nil }
            if let up = myUploads["\(metric.rawValue)|\(day)"] { return up }
            return seeded(LocalDemoFriendsSeed.me, metric, day: day)
        }
        guard let p = people[id], p.shares[metric] != nil else { return nil }
        return seeded(p, metric, day: day)
    }

    private func seeded(_ p: LocalDemoFriendsSeed.Person, _ metric: FriendsMetric, day: String) -> DailyShare? {
        var shareable = p
        shareable.shares = [metric: .friends]
        return LocalDemoFriendsSeed.days(shareable, days: [day], finishedWeek: finishedWeek).first
    }

    // MARK: - Session

    func currentUserID() async -> UUID? { signedIn ? LocalDemoFriendsSeed.meID : nil }

    func signInWithApple(idToken: String, nonce: String) async throws { throw FriendsError.unconfigured }

    func signInDemo() async throws { signedIn = true }

    func signOut() async { signedIn = false }

    func deleteAccount(appleAuthorizationCode: String?) async throws -> Bool {
        let fresh = Self.seed(start: .signedOut, today: today)
        signedIn = false
        me = nil
        myShares = [:]
        myUploads = [:]
        myUploadedTrends = []
        people = fresh.people
        links = fresh.links
        comps = fresh.comps
        hides = []
        blocks = []
        ownCodes = [:]
        reports = []
        return false
    }

    private func requireSignedIn() throws {
        guard signedIn else { throw FriendsError.notSignedIn }
    }

    private func requireProfile() throws -> FriendsProfile {
        try requireSignedIn()
        guard let me else { throw FriendsError.profileRequired }
        return me
    }

    // MARK: - Profile & consent

    func myProfile() async throws -> FriendsProfile? {
        try requireSignedIn()
        return me
    }

    func completeProfile(displayName: String, ageConfirmed: Bool) async throws -> FriendsProfile {
        try requireSignedIn()
        guard ageConfirmed else { throw FriendsError.ageRequired }
        let name = try DisplayName.validate(displayName).get()
        let profile = FriendsProfile(id: LocalDemoFriendsSeed.meID, displayName: name,
                                     stepGoal: me?.stepGoal ?? LocalDemoFriendsSeed.me.stepGoal,
                                     intensityGoal: me?.intensityGoal ?? LocalDemoFriendsSeed.me.intensityGoal)
        me = profile
        return profile
    }

    func updateProfile(displayName: String?, stepGoal: Int?, intensityGoal: Int?) async throws {
        var p = try requireProfile()
        if let displayName { p.displayName = try DisplayName.validate(displayName).get() }
        if let stepGoal { p.stepGoal = FriendsScoring.storedStepGoal(stepGoal) }
        if let intensityGoal { p.intensityGoal = FriendsScoring.storedIntensityGoal(intensityGoal) }
        me = p
    }

    func setShare(_ metric: FriendsMetric, audience: ShareAudience?, consentVersion: Int) async throws {
        _ = try requireProfile()
        guard consentVersion >= 1 else { throw FriendsError.invalidAudience }
        guard let audience else {
            myShares[metric] = nil
            myUploads = myUploads.filter { $0.value.metric != metric }
            myUploadedTrends.removeAll { $0.metric == metric }
            return
        }
        guard metric.allowedAudiences.contains(audience) else { throw FriendsError.invalidAudience }
        myShares[metric] = audience
    }

    func upload(days: [DailyShare], trends: [TrendShare], retract: [DailyRetraction]) async throws
        -> (accepted: Int, dropped: Int) {
        _ = try requireProfile()
        guard days.count + retract.count <= 175, trends.count <= 15 else { throw FriendsError.invalidWindow }
        let lo = FriendsDates.adding(-36, to: today), hi = FriendsDates.adding(1, to: today)
        var accepted = 0, dropped = 0
        for d in days {
            guard d.metric.isBehaviour, myShares[d.metric] != nil, d.day >= lo, d.day <= hi, d.value >= 0,
                  d.metric != .steps || d.source == "strap" || d.source == "phone" else { dropped += 1; continue }
            let c = FriendsScoring.capped(d.metric, d.value)
            myUploads["\(d.metric.rawValue)|\(d.day)"] = DailyShare(day: d.day, metric: d.metric, value: c.value,
                                                                     source: d.metric == .steps ? d.source : nil,
                                                                     capped: c.capped || d.capped)
            accepted += 1
        }
        for r in retract {
            // Like the server: the caller's own uploaded row goes (seeded demo values are not uploads).
            guard r.metric.isBehaviour, r.day >= lo, r.day <= hi else { dropped += 1; continue }
            myUploads["\(r.metric.rawValue)|\(r.day)"] = nil
            accepted += 1
        }
        for t in trends {
            guard !t.metric.isBehaviour, myShares[t.metric] != nil, FriendsDates.isMonday(t.weekStart) else { dropped += 1; continue }
            myUploadedTrends.removeAll { $0.metric == t.metric && $0.weekStart == t.weekStart }
            myUploadedTrends.append(t)
            accepted += 1
        }
        return (accepted, dropped)
    }

    func myServerData() async throws -> Data {
        let p = try requireProfile()
        let days = myVisibleDays(from: FriendsDates.adding(-34, to: today), to: today)
        let obj: [String: Any] = [
            "profile": ["id": p.id.uuidString.lowercased(), "display_name": p.displayName,
                        "step_goal": p.stepGoal, "intensity_goal": p.intensityGoal],
            "shares": myShares.map { ["metric": $0.key.rawValue, "audience": $0.value.rawValue] },
            "daily_values": days.map { d -> [String: Any] in
                var row: [String: Any] = ["day": d.day, "metric": d.metric.rawValue, "value": d.value, "capped": d.capped]
                if let s = d.source { row["source"] = s }
                return row
            },
            "demo": true,
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    private func myVisibleDays(from: String, to: String) -> [DailyShare] {
        var out: [DailyShare] = []
        for day in FriendsDates.days(from: from, to: min(to, today)) {
            for m in FriendsMetric.behaviour {
                if let v = value(of: LocalDemoFriendsSeed.meID, m, day: day) { out.append(v) }
            }
        }
        return out
    }

    // MARK: - Graph

    func createInvite() async throws -> (code: String, expiresAt: Date) {
        _ = try requireProfile()
        let open = ownCodes.filter { $0.value > now() }
        guard open.count < 5 else { throw FriendsError.inviteLimit }
        let code: String
        if codeCounter == 0 {
            code = LocalDemoFriendsSeed.firstOwnCode
        } else {
            let chars = Array(FriendInviteCode.charset)
            var n = codeCounter * 7919 + 104_729
            code = String((0..<8).map { _ -> Character in
                let c = chars[n % chars.count]; n /= chars.count; n += 31; return c
            })
        }
        codeCounter += 1
        let expires = now().addingTimeInterval(7 * 86_400)
        ownCodes[code] = expires
        return (code, expires)
    }

    /// The person a code points at, or the error the server would raise.
    private func resolve(_ raw: String) throws -> LocalDemoFriendsSeed.Person {
        guard let code = FriendInviteCode.normalize(raw) else { throw FriendsError.inviteInvalid }
        switch code {
        case LocalDemoFriendsSeed.expiredCode: throw FriendsError.inviteExpired
        case LocalDemoFriendsSeed.usedCode: throw FriendsError.inviteUsed
        case _ where ownCodes[code] != nil: throw FriendsError.inviteSelf
        case LocalDemoFriendsSeed.caseyCode:
            let casey = LocalDemoFriendsSeed.casey
            if blocks.contains(casey.id) { throw FriendsError.blocked }
            if links[casey.id] != nil { throw FriendsError.alreadyFriends }
            return casey
        default:
            throw FriendsError.inviteInvalid
        }
    }

    func peekInvite(_ code: String) async throws -> (name: String, expiresAt: Date) {
        _ = try requireProfile()
        let p = try resolve(code)
        return (p.name, now().addingTimeInterval(5 * 86_400))
    }

    func redeemInvite(_ code: String) async throws -> (friendID: UUID, name: String) {
        _ = try requireProfile()
        let p = try resolve(code)
        guard links.count < 50 else { throw FriendsError.friendLimit }
        links[p.id] = Link(accepted: false, requestedByMe: true)
        people[p.id] = p
        return (p.id, p.name)
    }

    func respondFriend(_ id: UUID, accept: Bool) async throws {
        _ = try requireProfile()
        guard let link = links[id], !link.accepted, !link.requestedByMe else { throw FriendsError.notFound }
        if accept { links[id] = Link(accepted: true, requestedByMe: false) } else { links[id] = nil }
    }

    func setHidden(_ id: UUID, hidden: Bool) async throws {
        _ = try requireProfile()
        guard links[id] != nil else { throw FriendsError.notFriends }
        if hidden { hides.insert(id) } else { hides.remove(id) }
    }

    func removeFriend(_ id: UUID) async throws {
        _ = try requireProfile()
        links[id] = nil
        hides.remove(id)
    }

    func block(_ id: UUID) async throws {
        _ = try requireProfile()
        guard id != LocalDemoFriendsSeed.meID else { throw FriendsError.notFound }
        blocks.insert(id)
        links[id] = nil
        hides.remove(id)
        for (cid, c) in comps where c.createdBy == LocalDemoFriendsSeed.meID && c.end >= today && c.states[id] != nil {
            comps[cid]?.states[id] = .removed
        }
    }

    func unblock(_ id: UUID) async throws {
        _ = try requireProfile()
        blocks.remove(id)
    }

    func report(_ id: UUID, reason: ReportReason, competition: UUID?) async throws {
        _ = try requireProfile()
        guard people[id] != nil || blocks.contains(id) else { throw FriendsError.notFound }
        reports.append((id, reason, competition))
    }

    // MARK: - Reads

    func overview(from: String, to: String) async throws -> FriendsOverview {
        let p = try requireProfile()
        let span = FriendsDates.distance(from: from, to: to)
        guard span >= 0, span <= 34 else { throw FriendsError.invalidWindow }
        let window = FriendsDates.days(from: from, to: min(to, today))
        var friends: [Friend] = []
        for (id, link) in links where !blocks.contains(id) {
            guard let person = people[id] else { continue }
            let profile = FriendsProfile(id: id, displayName: person.name, stepGoal: person.stepGoal,
                                         intensityGoal: person.intensityGoal)
            guard link.accepted else {
                friends.append(Friend(profile: profile, status: link.requestedByMe ? .pendingOutgoing : .pendingIncoming,
                                      iHide: hides.contains(id)))
                continue
            }
            var days: [DailyShare] = []
            for day in window {
                for m in FriendsMetric.behaviour where person.shares[m] == .friends {
                    if let v = value(of: id, m, day: day) { days.append(v) }
                }
            }
            let trends = LocalDemoFriendsSeed.trends(person, today: today).filter { person.shares[$0.metric] == .friends }
            friends.append(Friend(profile: profile, status: .accepted, iHide: hides.contains(id), days: days, trends: trends))
        }
        friends.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var myTrends = myUploadedTrends.filter { myShares[$0.metric] != nil }
        if myTrends.isEmpty {
            myTrends = LocalDemoFriendsSeed.trends(LocalDemoFriendsSeed.me, today: today).filter { myShares[$0.metric] != nil }
        }
        return FriendsOverview(me: p, myShares: myShares, myDays: myVisibleDays(from: from, to: to),
                               myTrends: myTrends.sorted { $0.weekStart < $1.weekStart }, friends: friends)
    }

    // MARK: - Competitions

    private func name(of id: UUID) -> String {
        if id == LocalDemoFriendsSeed.meID { return me?.displayName ?? "You" }
        return people[id]?.name ?? "Friend"
    }

    private func summary(_ c: Comp) -> CompetitionSummary {
        let members = c.order.compactMap { uid -> CompetitionMember? in
            guard let state = c.states[uid], [.invited, .joined, .left].contains(state), !blocks.contains(uid) else { return nil }
            return CompetitionMember(userID: uid, name: name(of: uid), state: state)
        }
        return CompetitionSummary(id: c.id, metric: c.metric, mode: c.mode, start: c.start, end: c.end, createdBy: c.createdBy,
                                  myState: c.states[LocalDemoFriendsSeed.meID] ?? .invited, members: members,
                                  freezeAt: c.freezeAt, isFinal: now() >= c.freezeAt)
    }

    func competitions() async throws -> [CompetitionSummary] {
        _ = try requireProfile()
        let oldest = FriendsDates.adding(-90, to: today)
        return comps.values
            .filter { c in
                guard let s = c.states[LocalDemoFriendsSeed.meID] else { return false }
                return [.invited, .joined, .left].contains(s) && c.end >= oldest
            }
            .map { summary($0) }
            .sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start > $1.start }
    }

    func createCompetition(_ draft: CompetitionDraft) async throws -> UUID {
        let p = try requireProfile()
        let invitees = Array(Set(draft.invitees)).filter { $0 != p.id }
        guard (1...9).contains(invitees.count) else { throw FriendsError.tooManyParticipants }
        guard invitees.allSatisfy({ links[$0]?.accepted == true && !blocks.contains($0) }) else { throw FriendsError.notFriends }
        guard CompetitionMode.allowed(for: draft.metric).contains(draft.mode) else { throw FriendsError.invalidMode }
        let length = FriendsDates.distance(from: draft.start, to: draft.end)
        let lead = FriendsDates.distance(from: today, to: draft.start)
        guard length >= 0, length <= 30, lead >= -1, lead <= 30 else { throw FriendsError.invalidWindow }
        guard myShares[draft.metric] != nil else { throw FriendsError.metricNotShared }
        let id = UUID()
        var states: [UUID: MemberState] = [p.id: .joined]
        var goals: [UUID: Int] = [:]
        if let g = FriendsScoring.lockedGoal(metric: draft.metric, profile: p) { goals[p.id] = g }
        for uid in invitees {
            // Demo friends who share the metric accept straight away, so a new competition has a field.
            if let person = people[uid], person.shares[draft.metric] != nil {
                states[uid] = .joined
                let profile = FriendsProfile(id: uid, displayName: person.name, stepGoal: person.stepGoal,
                                             intensityGoal: person.intensityGoal)
                if let g = FriendsScoring.lockedGoal(metric: draft.metric, profile: profile) { goals[uid] = g }
            } else {
                states[uid] = .invited
            }
        }
        comps[id] = Comp(id: id, createdBy: p.id, metric: draft.metric, mode: draft.mode, start: draft.start, end: draft.end,
                         freezeAt: FriendsScoring.freezeAt(endDay: draft.end), order: [p.id] + invitees,
                         states: states, goals: goals)
        return id
    }

    func respondCompetition(_ id: UUID, accept: Bool) async throws {
        let p = try requireProfile()
        guard var c = comps[id], c.states[p.id] == .invited else { throw FriendsError.notFound }
        if accept {
            guard today <= FriendsDates.adding(1, to: c.start) else { throw FriendsError.joiningClosed }
            guard myShares[c.metric] != nil else { throw FriendsError.metricNotShared }
            c.states[p.id] = .joined
            if let g = FriendsScoring.lockedGoal(metric: c.metric, profile: p) { c.goals[p.id] = g }
        } else {
            c.states[p.id] = .declined
        }
        comps[id] = c
    }

    func leaveCompetition(_ id: UUID) async throws {
        let p = try requireProfile()
        guard let c = comps[id], c.states[p.id] == .joined else { throw FriendsError.notMember }
        comps[id]?.states[p.id] = .left
    }

    func removeParticipant(_ id: UUID, user: UUID) async throws {
        let p = try requireProfile()
        guard let c = comps[id] else { throw FriendsError.notFound }
        guard c.createdBy == p.id else { throw FriendsError.notCreator }
        guard user != p.id, c.states[user] != nil else { throw FriendsError.notFound }
        comps[id]?.states[user] = .removed
    }

    func standings(_ id: UUID) async throws -> CompetitionStandings {
        let p = try requireProfile()
        guard let c = comps[id], let mine = c.states[p.id], [.invited, .joined, .left].contains(mine) else {
            throw FriendsError.notMember
        }
        let window = FriendsDates.days(from: c.start, to: c.end)
        let members: [FriendsScoring.MemberInput] = c.order.compactMap { uid in
            guard let state = c.states[uid], !blocks.contains(uid) else { return nil }
            let sharing = uid == p.id ? myShares[c.metric] != nil : people[uid]?.shares[c.metric] != nil
            var values: [String: Int] = [:], capped: Set<String> = [], sources: [String: String] = [:]
            for day in window {
                guard let v = value(of: uid, c.metric, day: day) else { continue }
                values[day] = v.value
                if v.capped { capped.insert(day) }
                if let s = v.source { sources[day] = s }
            }
            return FriendsScoring.MemberInput(userID: uid, name: name(of: uid), state: state, goal: c.goals[uid],
                                              sharing: sharing, values: values, cappedDays: capped, sources: sources)
        }
        let s = summary(c)
        // Like competition_standings: scores only for people taking part (joined, or joined then left once final);
        // an invited person sees the roster in the summary, and their own days once they have a locked goal.
        let seesScores = mine == .joined || (s.isFinal && mine == .left)
        let rows = seesScores
            ? FriendsScoring.standings(metric: c.metric, mode: c.mode, window: window, members: members) : []
        let me = members.first { $0.userID == p.id }
        let myDays = mine == .invited ? [] :
            FriendsScoring.myDays(metric: c.metric, mode: c.mode, goal: c.goals[p.id], window: window,
                                  values: me?.values ?? [:], cappedDays: me?.cappedDays ?? [], through: today)
        return CompetitionStandings(summary: s, rows: rows, myDays: myDays, isFinal: s.isFinal)
    }
}
