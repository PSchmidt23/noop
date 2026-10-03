#if os(iOS)
import Combine
import Foundation

/// The Friends tab's state (FRIENDS_SPEC.md §5.3). One instance, created in `BaselineApp` and injected as an
/// environment object. Screens read `phase`, `overview`, `competitions` and call the async actions; nothing here
/// draws.
///
/// Privacy rules this type enforces:
/// - Friends' data lives in memory only. Nothing about another person is written to disk.
/// - Muted friends, the Competitive-view switch, the consent-shown flag and the upload digest are the only local
///   keys (`baseline.friends.*`), and sign-out / delete clear them. (`FriendsKeychain.installMarkerKey` marks the
///   install, not the person: it stays, so a reinstall can be told from a sign-out.)
/// - Uploads run only against the LIVE backend, signed in, with at least one share, never under sample data or UI
///   tests. The demo backend never receives anything.
@MainActor
final class FriendsStore: ObservableObject {

    enum Phase: Equatable {
        /// No live backend and no demo chosen: the intro with "Preview with demo friends".
        case unavailable
        /// A backend but no session: the intro with Sign in with Apple (live) or "Continue with demo account".
        case signedOut
        /// Signed in, no profile: the setup sheet (name, 16+).
        case needsProfile
        /// Profile made, consent screen not yet shown on this device.
        case needsConsent
        case ready
    }

    /// What the store reads from the app around it. `current()` is the real thing; tests build their own.
    struct Environment {
        var arguments: [String]
        var isDebug: Bool
        var config: FriendsConfig?
        var sampleDataActive: () -> Bool

        static func current(bundle: Bundle = .main) -> Environment {
            #if DEBUG
            let debug = true
            #else
            let debug = false
            #endif
            return Environment(arguments: CommandLine.arguments, isDebug: debug, config: FriendsConfig.load(bundle: bundle),
                               sampleDataActive: { BaselineSampleData.isActive })
        }

        var isUITesting: Bool { isDebug && arguments.contains("--ui-testing") }
    }

    /// "Connect with Sam?" after an invite link or code was peeked.
    struct JoinPrompt: Equatable, Identifiable {
        var code: String
        var name: String
        var expiresAt: Date
        var id: String { code }
    }

    typealias BackendMaker = @MainActor (FriendsBackendFactory.Choice) -> FriendsBackend?
    /// Loads the local inputs for the given day keys (nil when there is no data source attached).
    typealias InputsLoader = @MainActor (_ days: [String]) async -> FriendsUploadInputs?

    // MARK: Published state

    @Published private(set) var phase: Phase = .unavailable
    @Published private(set) var profile: FriendsProfile?
    @Published private(set) var overview: FriendsOverview?
    @Published private(set) var competitions: [CompetitionSummary] = []
    @Published var lastError: FriendsError?
    /// Set by a `baseline://friends/join/CODE` link (or a typed code) and kept until the person is ready.
    @Published var pendingJoinCode: String?
    @Published var joinPrompt: JoinPrompt?
    @Published private(set) var isDemo = false
    @Published private(set) var isBusy = false
    @Published private(set) var muted: Set<UUID> = []
    @Published var competitiveView: Bool {
        didSet { defaults.set(competitiveView, forKey: Self.competitiveViewKey) }
    }
    /// After a delete: true when Apple sign-in for Baseline was revoked too, false when the manual line applies.
    @Published private(set) var lastDeleteRevoked: Bool?
    @Published private(set) var lastUploadAt: Date?

    // MARK: Keys

    static let mutedKey = "baseline.friends.muted"
    static let digestKey = "baseline.friends.uploadDigest"
    static let competitiveViewKey = "baseline.friends.competitiveView"
    static let consentShownKey = "baseline.friends.consentShown"

    static let uploadThrottle: TimeInterval = 10 * 60
    static let refreshDebounce: TimeInterval = 30
    /// The overview window: 33 days back to tomorrow (a friend east of here may already be on tomorrow).
    static let overviewBack = 33

    // MARK: Collaborators

    private(set) var choice: FriendsBackendFactory.Choice = .unavailable
    private(set) var backend: FriendsBackend?
    private let environment: Environment
    private let defaults: UserDefaults
    private let makeBackend: BackendMaker
    private var inputsLoader: InputsLoader?
    private let now: () -> Date
    private let timeZone: TimeZone

    private var previewRequested = false
    /// Demo sessions keep the consent flag in memory; live ones in `baseline.friends.consentShown`.
    private var demoConsentShown = false
    /// The next upload sends the whole 35-day window (after sign-in, or when a metric turns on).
    private(set) var needsFullUpload = true
    private var debounceTask: Task<Void, Never>?
    private var started = false
    /// One upload at a time (an activation and the tab's own start can both ask).
    private var uploadInFlight = false

    init(environment: Environment = .current(), defaults: UserDefaults = .standard,
         makeBackend: BackendMaker? = nil, inputsLoader: InputsLoader? = nil,
         now: @escaping () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.environment = environment
        self.defaults = defaults
        self.makeBackend = makeBackend ?? { FriendsBackendFactory.makeBackend($0) }
        self.inputsLoader = inputsLoader
        self.now = now
        self.timeZone = timeZone
        self.competitiveView = defaults.object(forKey: Self.competitiveViewKey) as? Bool ?? true
    }

    /// Wires the local data source for uploads. Call once from the app with its repository and profile store.
    func attach(repo: Repository, profile: ProfileStore?) {
        inputsLoader = { [weak repo, weak profile] days in
            guard let repo else { return nil }
            return await FriendsUploadInputs.load(repo, profile: profile, days: days, now: Date())
        }
    }

    // MARK: Derived

    var today: String { FriendsDates.localKey(now(), timeZone: timeZone) }
    var isLive: Bool { backend?.kind == .live }
    var myShares: [FriendsMetric: ShareAudience] { overview?.myShares ?? [:] }
    var me: FriendsProfile? { overview?.me ?? profile }

    /// Incoming friend requests plus competition invitations (the tab badge). 0 unless ready.
    var badgeCount: Int {
        guard phase == .ready else { return 0 }
        let requests = overview?.incoming.count ?? 0
        let invites = competitions.filter { $0.myState == .invited && !$0.isFinal && $0.end >= today }.count
        return requests + invites
    }

    /// Whether "Sign in with Apple" is offered (live only).
    var offersAppleSignIn: Bool { phase == .signedOut && isLive }
    /// Whether "Preview with demo friends" is offered (no live backend in this build).
    var offersPreview: Bool { phase == .unavailable }

    private var consentShown: Bool {
        get { isDemo ? demoConsentShown : defaults.bool(forKey: Self.consentShownKey) }
        set {
            if isDemo { demoConsentShown = newValue } else { defaults.set(newValue, forKey: Self.consentShownKey) }
        }
    }

    // MARK: - Lifecycle

    /// Chooses the backend (again, if the inputs changed) and restores the session. Safe to call on every activation
    /// and whenever sample data is turned on or off: a changed choice resets everything held in memory.
    func start() async {
        let next = FriendsBackendFactory.choose(config: environment.config, sampleDataActive: environment.sampleDataActive(),
                                                arguments: environment.arguments, isDebug: environment.isDebug,
                                                previewRequested: previewRequested)
        if !started || next != choice {
            install(next)
            started = true
        }
        await reloadSession()
    }

    /// The intro's "Preview with demo friends": a session-only demo (Release builds without a config included).
    func requestPreview() async {
        previewRequested = true
        await start()
    }

    private func install(_ next: FriendsBackendFactory.Choice) {
        debounceTask?.cancel()
        choice = next
        backend = makeBackend(next)
        isDemo = backend?.kind == .demo
        overview = nil
        competitions = []
        profile = nil
        joinPrompt = nil
        lastError = nil
        needsFullUpload = true
        demoConsentShown = next.demoStart == .ready
        muted = isDemo ? [] : Self.loadMuted(defaults)
    }

    /// Works out the phase from the backend's session and profile, then loads the tab when ready.
    func reloadSession() async {
        guard let backend else { phase = .unavailable; return }
        guard await backend.currentUserID() != nil else { phase = .signedOut; return }
        do {
            profile = try await backend.myProfile()
        } catch {
            handle(error)
            // Offline with a session: keep showing what was there rather than pretending to be signed out.
            if (error as? FriendsError) == .network, phase == .ready { return }
            if phase != .needsProfile { phase = .signedOut }
            return
        }
        guard profile != nil else { phase = .needsProfile; return }
        if !consentShown {
            // A returning person on a new phone already chose their shares: don't ask again.
            await loadOverview()
            if !(overview?.myShares.isEmpty ?? true) { consentShown = true }
        }
        guard consentShown else { phase = .needsConsent; return }
        await becomeReady()
    }

    /// `forceUpload` after sign-in, profile creation and consent; an ordinary activation respects the throttle (the
    /// first upload of a process always runs, since nothing has been sent yet).
    private func becomeReady(forceUpload: Bool = false) async {
        phase = .ready
        await refresh()
        await peekPendingJoin()
        await scheduleUpload(force: forceUpload)
    }

    // MARK: - Sign-in, profile, consent

    func signInWithApple(idToken: String, nonce: String) async {
        guard let backend else { return }
        await run { try await backend.signInWithApple(idToken: idToken, nonce: nonce) }
        needsFullUpload = true
        await reloadSession()
    }

    /// The demo's "Continue with demo account".
    func signInDemo() async {
        guard let backend else { return }
        await run { try await backend.signInDemo() }
        await reloadSession()
    }

    /// Step (a)+(b) of setup. Validates the name locally first (the same rule as the server).
    @discardableResult
    func completeProfile(displayName: String, ageConfirmed: Bool) async -> Bool {
        guard let backend else { return false }
        guard ageConfirmed else { lastError = .ageRequired; return false }
        switch DisplayName.validate(displayName) {
        case .failure(let e): lastError = e; return false
        case .success(let name):
            guard let p = await run({ try await backend.completeProfile(displayName: name, ageConfirmed: true) }) else { return false }
            profile = p
            needsFullUpload = true
            await syncGoals()
            if consentShown { await becomeReady(forceUpload: true) } else { phase = .needsConsent }
            return true
        }
    }

    /// "I agree" with the picks from the consent screen (step c). Every metric starts Off; only the ones turned on
    /// are sent, each with the consent version.
    func finishConsent(_ picks: [FriendsMetric: ShareAudience]) async {
        guard let backend else { return }
        for (metric, audience) in picks.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where metric.allowedAudiences.contains(audience) {
            await run { try await backend.setShare(metric, audience: audience, consentVersion: FriendsConsent.version) }
        }
        consentShown = true
        needsFullUpload = true
        await becomeReady(forceUpload: true)
    }

    /// "Share nothing for now".
    func skipConsent() async {
        consentShown = true
        await becomeReady()
    }

    /// One metric's level (Settings › Friends & sharing, the join sheet). nil = Off: the server deletes its rows now.
    @discardableResult
    func setShare(_ metric: FriendsMetric, audience: ShareAudience?) async -> Bool {
        guard let backend else { return false }
        let wasOff = myShares[metric] == nil
        guard await run({ try await backend.setShare(metric, audience: audience, consentVersion: FriendsConsent.version) }) != nil
        else { return false }
        if audience != nil && wasOff { needsFullUpload = true }
        if audience == nil { forgetDigest(metric: metric) }
        await refresh()
        await scheduleUpload(force: true)
        return true
    }

    @discardableResult
    func rename(_ displayName: String) async -> Bool {
        guard let backend else { return false }
        switch DisplayName.validate(displayName) {
        case .failure(let e): lastError = e; return false
        case .success(let name):
            guard await run({ try await backend.updateProfile(displayName: name, stepGoal: nil, intensityGoal: nil) }) != nil
            else { return false }
            await refresh()
            return true
        }
    }

    /// Pushes the local step and intensity goals to the profile when they differ (locked into competitions on join).
    func syncGoals() async {
        guard let backend, let p = me ?? profile else { return }
        let step = FriendsScoring.storedStepGoal(StepGoal.goal(defaults))
        let intensity = FriendsScoring.storedIntensityGoal(IntensityMinutes.goal(defaults))
        guard step != p.stepGoal || intensity != p.intensityGoal else { return }
        await run { try await backend.updateProfile(displayName: nil, stepGoal: step, intensityGoal: intensity) }
        if var updated = profile {
            updated.stepGoal = step
            updated.intensityGoal = intensity
            profile = updated
        }
        overview?.me.stepGoal = step
        overview?.me.intensityGoal = intensity
    }

    // MARK: - Reads

    /// Reloads the overview and the competitions.
    func refresh() async {
        await loadOverview()
        await loadCompetitions()
    }

    private func loadOverview() async {
        guard let backend else { return }
        let from = FriendsDates.adding(-Self.overviewBack, to: today)
        let to = FriendsDates.adding(1, to: today)
        if let o = await run({ try await backend.overview(from: from, to: to) }) { overview = o }
    }

    private func loadCompetitions() async {
        guard let backend else { return }
        if let c = await run({ try await backend.competitions() }) { competitions = c }
    }

    func standings(_ id: UUID) async -> CompetitionStandings? {
        guard let backend else { return nil }
        return await run { try await backend.standings(id) }
    }

    func myServerData() async -> Data? {
        guard let backend else { return nil }
        return await run { try await backend.myServerData() }
    }

    // MARK: - Friend graph

    func createInvite() async -> (code: String, expiresAt: Date)? {
        guard let backend else { return nil }
        return await run { try await backend.createInvite() }
    }

    /// "Connect with Sam?" for a typed code. nil (with `lastError`) when the code is bad.
    func peek(code raw: String) async -> JoinPrompt? {
        guard let backend else { return nil }
        guard let code = FriendInviteCode.normalize(raw) else { lastError = .inviteInvalid; return nil }
        guard let r = await run({ try await backend.peekInvite(code) }) else { return nil }
        return JoinPrompt(code: code, name: r.name, expiresAt: r.expiresAt)
    }

    /// Sends the request ("Request sent to Sam."). Returns the friend's name.
    @discardableResult
    func redeem(code raw: String) async -> String? {
        guard let backend else { return nil }
        guard let code = FriendInviteCode.normalize(raw) else { lastError = .inviteInvalid; return nil }
        guard let r = await run({ try await backend.redeemInvite(code) }) else { return nil }
        joinPrompt = nil
        await loadOverview()
        return r.name
    }

    /// A `baseline://friends/join/CODE` link: kept until the person is signed in and set up, then peeked.
    func handleJoinLink(code: String) async {
        pendingJoinCode = FriendInviteCode.normalize(code)
        await peekPendingJoin()
    }

    private func peekPendingJoin() async {
        guard phase == .ready, let code = pendingJoinCode else { return }
        pendingJoinCode = nil
        joinPrompt = await peek(code: code)
    }

    func confirmJoin() async -> String? {
        guard let prompt = joinPrompt else { return nil }
        return await redeem(code: prompt.code)
    }

    func dismissJoin() { joinPrompt = nil }

    func respondFriend(_ id: UUID, accept: Bool) async {
        guard let backend else { return }
        await run { try await backend.respondFriend(id, accept: accept) }
        await loadOverview()
    }

    func setHidden(_ id: UUID, hidden: Bool) async {
        guard let backend else { return }
        await run { try await backend.setHidden(id, hidden: hidden) }
        await loadOverview()
    }

    func removeFriend(_ id: UUID) async {
        guard let backend else { return }
        await run { try await backend.removeFriend(id) }
        setMuted(id, false)
        await refresh()
    }

    func block(_ id: UUID) async {
        guard let backend else { return }
        await run { try await backend.block(id) }
        setMuted(id, false)
        await refresh()
    }

    func unblock(_ id: UUID) async {
        guard let backend else { return }
        await run { try await backend.unblock(id) }
    }

    @discardableResult
    func report(_ id: UUID, reason: ReportReason, competition: UUID? = nil) async -> Bool {
        guard let backend else { return false }
        return await run { try await backend.report(id, reason: reason, competition: competition) } != nil
    }

    /// Mute is local only: the friend's card collapses into "Muted (n)".
    func setMuted(_ id: UUID, _ isMuted: Bool) {
        if isMuted { muted.insert(id) } else { muted.remove(id) }
        if !isDemo { defaults.set(muted.map(\.uuidString).sorted(), forKey: Self.mutedKey) }
    }

    static func loadMuted(_ defaults: UserDefaults) -> Set<UUID> {
        Set((defaults.stringArray(forKey: mutedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    // MARK: - Competitions

    func createCompetition(_ draft: CompetitionDraft) async -> UUID? {
        guard let backend else { return nil }
        await syncGoals()
        let id = await run { try await backend.createCompetition(draft) }
        await loadCompetitions()
        return id
    }

    func respondCompetition(_ id: UUID, accept: Bool) async -> Bool {
        guard let backend else { return false }
        if accept { await syncGoals() }
        let ok = await run { try await backend.respondCompetition(id, accept: accept) } != nil
        await loadCompetitions()
        return ok
    }

    func leaveCompetition(_ id: UUID) async {
        guard let backend else { return }
        await run { try await backend.leaveCompetition(id) }
        await loadCompetitions()
    }

    func removeParticipant(_ id: UUID, user: UUID) async {
        guard let backend else { return }
        await run { try await backend.removeParticipant(id, user: user) }
        await loadCompetitions()
    }

    /// "Rematch": the same metric, mode and length with the members who are still friends, from next Monday.
    func rematch(_ summary: CompetitionSummary) async -> UUID? {
        guard let draft = Self.rematchDraft(summary, me: me?.id, friends: Set(overview?.accepted.map(\.id) ?? []), today: today)
        else { lastError = .tooManyParticipants; return nil }
        return await createCompetition(draft)
    }

    static func rematchDraft(_ s: CompetitionSummary, me: UUID?, friends: Set<UUID>, today: String) -> CompetitionDraft? {
        let length = FriendsDates.distance(from: s.start, to: s.end)
        let start = FriendsDates.adding(7, to: FriendsDates.monday(of: today))
        let invitees = s.members.filter { $0.userID != me && $0.state == .joined && friends.contains($0.userID) }.map(\.userID)
        guard !invitees.isEmpty else { return nil }
        return CompetitionDraft(metric: s.metric, mode: s.mode, start: start, end: FriendsDates.adding(length, to: start),
                                invitees: Array(invitees.prefix(9)))
    }

    // MARK: - Sign out & delete

    func signOut() async {
        await backend?.signOut()
        wipeLocal()
        phase = backend == nil ? .unavailable : .signedOut
    }

    /// Deletes the account and all shared data. `appleAuthorizationCode` comes from
    /// `AppleSignIn.reauthorizeForDeletion()` (nil if the person cancelled: data is still deleted).
    @discardableResult
    func deleteAccount(appleAuthorizationCode: String?) async -> Bool {
        guard let backend else { return false }
        guard let revoked = await run({ try await backend.deleteAccount(appleAuthorizationCode: appleAuthorizationCode) })
        else { return false }
        lastDeleteRevoked = revoked
        wipeLocal()
        phase = .signedOut
        return true
    }

    private func wipeLocal() {
        debounceTask?.cancel()
        overview = nil
        competitions = []
        profile = nil
        joinPrompt = nil
        pendingJoinCode = nil
        muted = []
        lastUploadAt = nil
        needsFullUpload = true
        demoConsentShown = false
        defaults.removeObject(forKey: Self.digestKey)
        defaults.removeObject(forKey: Self.mutedKey)
        defaults.removeObject(forKey: Self.consentShownKey)
    }

    // MARK: - Upload

    /// Why an upload would not run right now; nil when it may.
    var uploadBlocker: String? {
        guard let backend else { return "no backend" }
        if backend.kind != .live { return "demo" }
        if environment.isUITesting { return "ui testing" }
        if environment.sampleDataActive() { return "sample data" }
        if phase != .ready { return "not ready" }
        if myShares.isEmpty { return "nothing shared" }
        return nil
    }

    /// Called on `repo.refreshSeq` while the app is active: uploads 30 s after the last change.
    func noteDataRefreshed() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.refreshDebounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.scheduleUpload()
        }
    }

    /// Builds and sends the person's own derived rows. At most once every 10 minutes unless `force`. The first upload
    /// after sign-in (or after a metric turns on) sends 35 days; later ones send today, the 2 days before, and any
    /// day whose value changed since the last accepted upload. A day accepted before that no longer has a shareable
    /// value is retracted, so the server deletes it rather than counting it on friends' boards until retention.
    func scheduleUpload(force: Bool = false) async {
        guard uploadBlocker == nil, !uploadInFlight, let backend, let loader = inputsLoader else { return }
        if !force, let last = lastUploadAt, now().timeIntervalSince(last) < Self.uploadThrottle { return }
        uploadInFlight = true
        defer { uploadInFlight = false }
        await syncGoals()
        let today = self.today
        let window = FriendsUploadBuilder.fullWindow(today: today)
        guard let inputs = await loader(window) else { return }
        let (rows, trends) = FriendsUploadBuilder.build(inputs, shares: myShares, days: window)
        let digest = loadDigest()
        let send = FriendsUploadBuilder.select(rows, today: today, digest: digest, full: needsFullUpload)
        let retract = FriendsUploadBuilder.retractions(rows: rows, digest: digest, shares: myShares, window: window)
        // At most 175 p_days elements per call (the server's limit): the rows, then the retractions.
        var calls: [(days: [DailyShare], retract: [DailyRetraction])] = []
        for i in stride(from: 0, to: send.count, by: 175) { calls.append((Array(send[i..<min(i + 175, send.count)]), [])) }
        for i in stride(from: 0, to: retract.count, by: 175) {
            calls.append(([], Array(retract[i..<min(i + 175, retract.count)])))
        }
        if calls.isEmpty { calls = [([], [])] }
        var accepted: [DailyShare] = []
        var retracted: [DailyRetraction] = []
        var first = true
        for call in calls {
            let r = await run { try await backend.upload(days: call.days, trends: first ? trends : [], retract: call.retract) }
            guard r != nil else { return }
            accepted += call.days
            retracted += call.retract
            first = false
        }
        saveDigest(FriendsUploadBuilder.updatedDigest(digest, with: accepted, retracted: retracted, today: today))
        lastUploadAt = now()
        needsFullUpload = false
    }

    private func loadDigest() -> [String: Int] {
        (defaults.dictionary(forKey: Self.digestKey) as? [String: Int]) ?? [:]
    }

    private func saveDigest(_ digest: [String: Int]) {
        defaults.set(digest, forKey: Self.digestKey)
    }

    private func forgetDigest(metric: FriendsMetric) {
        let kept = loadDigest().filter { !$0.key.hasPrefix("\(metric.rawValue)|") }
        saveDigest(kept)
    }

    // MARK: - Errors

    /// Runs one backend call, recording a failure in `lastError` (and dropping to signed-out when the session is gone).
    @discardableResult
    private func run<T>(_ work: () async throws -> T) async -> T? {
        isBusy = true
        defer { isBusy = false }
        do {
            return try await work()
        } catch {
            handle(error)
            return nil
        }
    }

    private func handle(_ error: Error) {
        let e = (error as? FriendsError) ?? .server
        lastError = e
        if e == .notSignedIn {
            overview = nil
            competitions = []
            profile = nil
            phase = backend == nil ? .unavailable : .signedOut
        } else if e == .profileRequired {
            phase = .needsProfile
        }
    }
}
#endif
