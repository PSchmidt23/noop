import Foundation

// The Friends contract (Baseline/Research/FRIENDS_SPEC.md §5.1). Foundation only: the screens, the store, both
// backends and the tests all speak these types. Raw values are the SQL keys in Baseline/Backend/supabase/schema.sql
// exactly, so a value never needs translating on its way to or from the server.
//
// The rule every type here follows: behaviour (steps, intensity minutes, active days, nights at the person's own
// sleep goal, on-time bedtimes) can be compared head-to-head; physiology (HRV, resting HR, readiness) only ever
// travels as each person's change against their OWN baseline, rounded and clipped, and is never ranked.

// MARK: - Metrics and sharing

enum FriendsMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps, intensity, active, sleepGoal = "sleep_goal", bedtime, hrv, rhr, readiness

    var id: String { rawValue }

    /// The five metrics friends can compete on.
    static let behaviour: [FriendsMetric] = [.steps, .intensity, .active, .sleepGoal, .bedtime]
    /// The three that are shown only as a change against the person's own baseline, never ranked.
    static let physiology: [FriendsMetric] = [.hrv, .rhr, .readiness]

    var isBehaviour: Bool { Self.behaviour.contains(self) }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .intensity: return "Intensity minutes"
        case .active: return "Active days"
        case .sleepGoal: return "Nights at sleep goal"
        case .bedtime: return "On-time bedtimes"
        case .hrv: return "HRV trend"
        case .rhr: return "Resting HR trend"
        case .readiness: return "Readiness trend"
        }
    }

    /// The short name a pill or a generated competition title uses ("HRV", "Steps").
    var shortTitle: String {
        switch self {
        case .steps: return "Steps"
        case .intensity: return "Intensity minutes"
        case .active: return "Active days"
        case .sleepGoal: return "Sleep goal"
        case .bedtime: return "Bedtimes"
        case .hrv: return "HRV"
        case .rhr: return "Resting HR"
        case .readiness: return "Readiness"
        }
    }

    /// The exact consent sentence for this metric (§7.2, consent version 1), with the person's own sleep
    /// goal as Settings › Profile holds it now (`BaselineReadouts.SleepGoal`).
    var sharedForm: String { sharedFormText(sleepGoalMinutes: BaselineReadouts.SleepGoal.minutes()) }

    /// `sharedForm` for a given sleep goal: the sleep-goal row names the line a night is judged against
    /// ("your own sleep goal (7h 30m asleep)"), so the threshold is never one the person cannot see.
    func sharedFormText(sleepGoalMinutes: Int) -> String {
        switch self {
        case .steps: return "your daily step count and whether the strap or iPhone counted it"
        case .intensity: return "your daily minutes, counted against your own heart rate"
        case .active: return "whether a day had 20+ intensity minutes or a 20-minute workout"
        case .sleepGoal:
            return "whether a night reached your own sleep goal (\(BaselineReadouts.SleepGoal.text(sleepGoalMinutes)) asleep, set in Settings › Profile); never hours or times"
        case .bedtime: return "whether bedtime was within 30 min of your target; never the time"
        case .hrv: return "weekly HRV change vs your own baseline, e.g. +8 %; never your HRV"
        case .rhr: return "weekly change vs your own baseline, e.g. −2 bpm; never your heart rate"
        case .readiness: return "this week vs your month, e.g. +4; never your score"
        }
    }

    /// Physiology can be shared with friends or not at all; never "only in competitions" (there are none).
    var allowedAudiences: [ShareAudience] { isBehaviour ? [.competitions, .friends] : [.friends] }

    /// The server-side cap for a daily value (values above it upload as the cap with `capped = true`).
    var dailyCap: Int? {
        switch self {
        case .steps: return 60_000
        case .intensity: return 300
        case .active, .sleepGoal, .bedtime: return 1
        case .hrv, .rhr, .readiness: return nil
        }
    }

    /// The clip for a weekly physiology delta: HRV ±30 %, resting HR ±10 bpm, readiness ±15 points.
    var trendClip: Int? {
        switch self {
        case .hrv: return 30
        case .rhr: return 10
        case .readiness: return 15
        default: return nil
        }
    }

    /// True for the three 0/1-per-day metrics (a count of days or nights when summed).
    var isDayCount: Bool { self == .active || self == .sleepGoal || self == .bedtime }

    /// The noun a count of this metric reads in ("steps", "min", "days", "nights").
    func unitText(_ value: Int) -> String {
        switch self {
        case .steps: return value == 1 ? "step" : "steps"
        case .intensity: return "min"
        case .active: return value == 1 ? "day" : "days"
        case .sleepGoal, .bedtime: return value == 1 ? "night" : "nights"
        case .hrv: return "%"
        case .rhr: return "bpm"
        case .readiness: return value == 1 ? "point" : "points"
        }
    }
}

/// Who sees a shared metric. `nil` (no row on the server) is Off, the default for every metric.
enum ShareAudience: String, Codable, Sendable, CaseIterable {
    case competitions, friends

    var title: String {
        switch self {
        case .competitions: return "Only in competitions"
        case .friends: return "Friends"
        }
    }
}

/// The consent text version every `set_share` call records (§7.2).
enum FriendsConsent {
    static let version = 1
    static let paragraph = "Health data. By tapping I agree, you explicitly consent to Baseline storing the items you turned on above on Baseline's server (Supabase, Frankfurt, EU) and showing them only to friends you accept, or only inside competitions you join. You can withdraw any time in Settings › Friends & sharing; withdrawing deletes them from the server. Daily values are kept 35 days."
}

/// One uploaded (or visible) daily value. `day` is the owner's LOCAL calendar day ("yyyy-MM-dd").
/// Encoded keys are exactly `day, metric, value, source, capped` (the upload whitelist; a golden test holds it).
struct DailyShare: Codable, Equatable, Sendable {
    var day: String
    var metric: FriendsMetric
    var value: Int
    /// "strap" or "phone" for steps; nil for every other metric.
    var source: String?
    var capped: Bool

    init(day: String, metric: FriendsMetric, value: Int, source: String? = nil, capped: Bool = false) {
        self.day = day; self.metric = metric; self.value = value; self.source = source; self.capped = capped
    }
}

/// A day this phone shared before and no longer has a shareable value for (the day's phone steps were deleted from
/// Apple Health, a night was edited away). It uploads in `p_days` as `{day, metric, value: null}`, and the server
/// deletes that row, so friends and competitions stop counting a number Home no longer shows.
struct DailyRetraction: Encodable, Equatable, Hashable, Sendable {
    var day: String
    var metric: FriendsMetric

    private enum CodingKeys: String, CodingKey { case day, metric, value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(day, forKey: .day)
        try c.encode(metric, forKey: .metric)
        try c.encodeNil(forKey: .value)
    }
}

enum TrendStatus: String, Codable, Sendable { case calibrating, ready }

/// Where the week sits against the person's own usual range (|z| < 1 is within).
enum TrendBand: String, Codable, Sendable {
    case below, within, above

    var phrase: String {
        switch self {
        case .below: return "below their usual range"
        case .within: return "within their usual range"
        case .above: return "above their usual range"
        }
    }
}

/// One weekly physiology row: the person's own change against their own baseline, clipped and rounded.
/// Encoded keys are exactly `metric, week_start, status, delta, band, clipped`.
struct TrendShare: Codable, Equatable, Sendable {
    var metric: FriendsMetric
    /// The owner's local Monday ("yyyy-MM-dd").
    var weekStart: String
    var status: TrendStatus
    /// hrv: % vs own baseline; rhr: bpm vs own baseline; readiness: 7-day mean minus 30-day mean. nil while calibrating.
    var delta: Int?
    var band: TrendBand?
    var clipped: Bool

    enum CodingKeys: String, CodingKey {
        case metric, weekStart = "week_start", status, delta, band, clipped
    }

    init(metric: FriendsMetric, weekStart: String, status: TrendStatus, delta: Int? = nil, band: TrendBand? = nil,
         clipped: Bool = false) {
        self.metric = metric; self.weekStart = weekStart; self.status = status
        self.delta = delta; self.band = band; self.clipped = clipped
    }
}

// MARK: - People

struct FriendsProfile: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var displayName: String
    /// Daily step goal (3,000–30,000 on the server).
    var stepGoal: Int
    /// WEEKLY intensity-minutes goal (60–600).
    var intensityGoal: Int

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", stepGoal = "step_goal", intensityGoal = "intensity_goal"
    }

    /// The goal a metric is scored against: steps → daily steps, intensity → weekly minutes, else nil.
    func goal(for metric: FriendsMetric) -> Int? {
        switch metric {
        case .steps: return stepGoal
        case .intensity: return intensityGoal
        default: return nil
        }
    }
}

enum FriendStatus: String, Codable, Sendable { case accepted, pendingIncoming, pendingOutgoing }

struct Friend: Identifiable, Equatable, Sendable {
    var profile: FriendsProfile
    var status: FriendStatus
    /// True when I have hidden my data from this friend (only I can see this).
    var iHide: Bool
    /// The friend's daily rows visible to me (Friends level only; competition-only shares never appear here).
    var days: [DailyShare]
    /// The friend's weekly physiology rows visible to me.
    var trends: [TrendShare]
    /// The newest day this friend's data covers ("Updated today / yesterday / n days ago"); nil when none.
    var lastDay: String?

    var id: UUID { profile.id }
    var name: String { profile.displayName }

    init(profile: FriendsProfile, status: FriendStatus, iHide: Bool = false, days: [DailyShare] = [],
         trends: [TrendShare] = [], lastDay: String? = nil) {
        self.profile = profile; self.status = status; self.iHide = iHide
        self.days = days; self.trends = trends
        self.lastDay = lastDay ?? days.map(\.day).max()
    }

    /// The behaviour metrics this friend shares with me (any visible row in the overview window).
    var sharedBehaviour: [FriendsMetric] {
        let present = Set(days.map(\.metric))
        return FriendsMetric.behaviour.filter(present.contains)
    }

    /// The physiology metrics this friend shares with me.
    var sharedPhysiology: [FriendsMetric] {
        let present = Set(trends.map(\.metric))
        return FriendsMetric.physiology.filter(present.contains)
    }
}

struct FriendsOverview: Equatable, Sendable {
    var me: FriendsProfile
    var myShares: [FriendsMetric: ShareAudience]
    /// My own uploaded rows (what the server holds for me in the window).
    var myDays: [DailyShare]
    var myTrends: [TrendShare]
    var friends: [Friend]

    init(me: FriendsProfile, myShares: [FriendsMetric: ShareAudience], myDays: [DailyShare],
         myTrends: [TrendShare] = [], friends: [Friend]) {
        self.me = me; self.myShares = myShares; self.myDays = myDays; self.myTrends = myTrends; self.friends = friends
    }

    var accepted: [Friend] { friends.filter { $0.status == .accepted } }
    var incoming: [Friend] { friends.filter { $0.status == .pendingIncoming } }
    var outgoing: [Friend] { friends.filter { $0.status == .pendingOutgoing } }
    /// "Hidden from n".
    var hiddenFromCount: Int { friends.filter(\.iHide).count }
}

// MARK: - Competitions

enum CompetitionMode: String, Codable, Sendable, CaseIterable {
    case goalPercent = "goal_percent", total, daysAtGoal = "days_at_goal"

    /// What the server's check constraint allows: steps → all three; intensity → % of goal and total; the
    /// three day-count metrics → total (a count of days); physiology → none, ever.
    static func allowed(for metric: FriendsMetric) -> [CompetitionMode] {
        switch metric {
        case .steps: return [.goalPercent, .total, .daysAtGoal]
        case .intensity: return [.goalPercent, .total]
        case .active, .sleepGoal, .bedtime: return [.total]
        case .hrv, .rhr, .readiness: return []
        }
    }

    var title: String {
        switch self {
        case .goalPercent: return "% of own goal"
        case .total: return "Total"
        case .daysAtGoal: return "Days at goal"
        }
    }

    /// The one-line explanation under the mode chip (§6.7).
    func explanation(for metric: FriendsMetric) -> String {
        switch (self, metric) {
        case (.goalPercent, .intensity):
            return "Your minutes as a share of your own weekly goal, up to 200. Fair across different goals."
        case (.goalPercent, _):
            return "Each day's steps as a share of your own goal, up to 200 a day. Fair across different goals."
        case (.total, .steps):
            return "Raw steps, capped at 60,000 a day; each person's source is shown."
        case (.total, .intensity):
            return "Total intensity minutes, capped at 300 a day."
        case (.total, _):
            return "A count of \(metric == .active ? "days" : "nights"); each one counts once."
        case (.daysAtGoal, _):
            return "Days you reach your own goal. Everyone can win."
        }
    }
}

enum MemberState: String, Codable, Sendable { case invited, joined, declined, left, removed }

struct CompetitionDraft: Equatable, Sendable {
    var metric: FriendsMetric
    var mode: CompetitionMode
    /// Local day keys, inclusive; at most 31 days.
    var start: String
    var end: String
    var invitees: [UUID]
}

struct CompetitionMember: Equatable, Sendable, Identifiable {
    var userID: UUID
    var name: String
    var state: MemberState
    var id: UUID { userID }
}

struct CompetitionSummary: Identifiable, Equatable, Sendable {
    var id: UUID
    var metric: FriendsMetric
    var mode: CompetitionMode
    var start: String
    var end: String
    var createdBy: UUID
    var myState: MemberState
    var members: [CompetitionMember]
    var freezeAt: Date
    var isFinal: Bool

    /// Generated, never stored: "Steps · Mon 6 – Sun 12 Oct".
    var title: String { "\(metric.shortTitle) · \(FriendsDates.rangeText(start: start, end: end))" }

    /// The one-line rule ("% of own goal", "Total", "Days at goal").
    var modeTitle: String { mode.title }

    /// Joined members (the people being scored).
    var joined: [CompetitionMember] { members.filter { $0.state == .joined } }

    /// Days left including today, 0 once the last day is over. `today` is a local day key.
    func daysLeft(today: String) -> Int {
        guard today <= end else { return 0 }
        let from = max(today, start)
        return FriendsDates.days(from: from, to: end).count
    }

    /// "Day 4 of 7" while running (nil before the start or after the end).
    func dayText(today: String) -> String? {
        guard today >= start, today <= end else { return nil }
        let n = FriendsDates.days(from: start, to: end).count
        let i = FriendsDates.days(from: start, to: today).count
        return "Day \(i) of \(n)"
    }

    func isActive(today: String) -> Bool { !isFinal && today <= end }
    func isUpcoming(today: String) -> Bool { today < start }
}

struct Standing: Identifiable, Equatable, Sendable {
    var userID: UUID
    var name: String
    var state: MemberState
    /// nil = not sharing the metric any more ("Not sharing").
    var score: Int?
    /// nil for non-sharers and people who left; ties share a place (1, 1, 3).
    var place: Int?
    var daysCounted: Int
    var cappedDays: Int
    var sharing: Bool
    /// "strap", "phone" or "strap+phone" (shown in steps · total only).
    var sourceMix: String?
    var id: UUID { userID }
}

struct DayPoints: Equatable, Sendable {
    var day: String
    var value: Int
    var points: Int
    var capped: Bool
}

struct CompetitionStandings: Equatable, Sendable {
    var summary: CompetitionSummary
    var rows: [Standing]
    /// Only the caller's own days.
    var myDays: [DayPoints]
    var isFinal: Bool
}

enum ReportReason: String, Codable, CaseIterable, Sendable {
    case name, cheating, harassment, other

    var title: String {
        switch self {
        case .name: return "Inappropriate name"
        case .cheating: return "Cheating"
        case .harassment: return "Harassment"
        case .other: return "Other"
        }
    }
}

// MARK: - Errors

/// Raw values are the server's stable message keys (§4), so `FriendsError(rawValue: message)` maps a PostgREST
/// error straight across. `network`, `unconfigured` and `server` are client-side.
enum FriendsError: String, Error, Equatable, Sendable, CaseIterable {
    case notSignedIn = "not_signed_in", profileRequired = "profile_required", invalidName = "invalid_name",
         ageRequired = "age_required", invalidAudience = "invalid_audience", inviteInvalid = "invite_invalid",
         inviteExpired = "invite_expired", inviteUsed = "invite_used", inviteSelf = "invite_self",
         inviteLimit = "invite_limit", alreadyFriends = "already_friends", friendLimit = "friend_limit",
         blocked, rateLimited = "rate_limited", notFound = "not_found", notFriends = "not_friends",
         notMember = "not_member", notCreator = "not_creator", joiningClosed = "joining_closed",
         metricNotShared = "metric_not_shared", invalidWindow = "invalid_window", invalidMode = "invalid_mode",
         tooManyParticipants = "too_many_participants", network, unconfigured, server

    /// The keys the server raises (everything except the three client-side cases).
    static let serverKeys: [FriendsError] = allCases.filter { ![.network, .unconfigured, .server].contains($0) }

    /// Calm, one-sentence copy for the screen.
    var message: String {
        switch self {
        case .notSignedIn: return "You're signed out. Sign in again to use Friends."
        case .profileRequired: return "Finish setting up your name first."
        case .invalidName: return "Use 2–24 letters or numbers, without links or symbols like @ or /."
        case .ageRequired: return "Friends is for people 16 and over."
        case .invalidAudience: return "That metric can't be shared that way."
        case .inviteInvalid: return "That code doesn't match an invite. Check the letters and try again."
        case .inviteExpired: return "That code has expired. Ask for a new one."
        case .inviteUsed: return "That code has already been used. Ask for a new one."
        case .inviteSelf: return "That's your own code. Send it to a friend instead."
        case .inviteLimit: return "You have 5 open invites. Wait for one to be used or to expire."
        case .alreadyFriends: return "You're already connected."
        case .friendLimit: return "Friends is limited to 50 people."
        case .blocked: return "You can't connect with this person."
        case .rateLimited: return "That's a lot of requests. Try again in a little while."
        case .notFound: return "That's no longer available."
        case .notFriends: return "You can only do that with an accepted friend."
        case .notMember: return "You're not part of this competition."
        case .notCreator: return "Only the person who started the competition can do that."
        case .joiningClosed: return "Joining closed a day after the competition started."
        case .metricNotShared: return "Share this metric first, at least for competitions."
        case .invalidWindow: return "Pick dates up to 31 days long, starting no more than 30 days ahead."
        case .invalidMode: return "That scoring mode isn't available for this metric."
        case .tooManyParticipants: return "Pick between 1 and 9 friends."
        case .network: return "Can't reach the server. Check your connection and try again."
        case .unconfigured: return "Friends isn't set up in this build yet."
        case .server: return "Something went wrong on the server. Try again."
        }
    }
}

// MARK: - Display name (D19, mirrors `valid_name` in schema.sql)

enum DisplayName {
    static let minLength = 2
    static let maxLength = 24

    /// Lower-case entries that make a name invalid ANYWHERE in it, even inside a longer word ("xFUCKx"): long or
    /// unambiguous ones no ordinary name contains. Kept identical, order included, to the `blocked_words` seed rows
    /// with `whole_word = false` in schema.sql (a test reads both).
    static let blockedSubstrings: [String] = [
        "admin", "administrator", "moderator", "official", "baseline team", "baselineteam", "support team",
        "anthropic", "apple support", "whoop support", "customer service",
        "fuck", "fucker", "fucking", "motherfucker", "bullshit", "asshole", "bitch", "cunt", "dickhead", "wanker",
        "bollocks", "whore", "pornhub", "onlyfans", "xxx", "blowjob", "handjob", "dildo", "pussy", "vagina", "boobs",
        "nipple", "orgasm", "hitler", "kkk", "pedophile", "retard", "faggot", "nigger", "nigga", "killyourself",
    ]

    /// Lower-case entries that make a name invalid only as a WHOLE word (see `words(_:)`): short ones that real names
    /// contain, so "Nazir", "Hancock", "Hitchcock", "Yoshitaka", "Toshihiro", "Pricket", "Slutsky", "Thorny" and
    /// "Bastardi" are names while "Mr Shit" is not. The `blocked_words` seed rows with `whole_word = true`.
    /// ("isis" and "heil" are not listed at all: Isis is a given name and Heil a surname.)
    static let blockedWholeWords: [String] = [
        "shit", "bastard", "twat", "prick", "slut", "porn", "porno", "cock", "penis", "tits", "horny", "nazi", "rapist",
        "pedo", "paedo", "kys",
    ]

    /// The name as whole words for `blockedWholeWords`: lower-cased, every run of characters other than a–z and 0–9
    /// read as one space, padded with a space each side (" mr shit "). The same rule as `private.valid_name`.
    static func words(_ lower: String) -> String {
        var out = ""
        var pendingSpace = false
        for scalar in lower.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return " \(out) "
    }

    /// True when a blocked entry matches: a substring entry anywhere, a whole-word entry as a word.
    static func containsBlockedWord(_ name: String) -> Bool {
        let lower = name.lowercased()
        if blockedSubstrings.contains(where: lower.contains) { return true }
        let padded = words(lower)
        return blockedWholeWords.contains { padded.contains(" \($0) ") }
    }

    /// Normalises (NFKC, whitespace collapsed, trimmed) and checks the shape and the blocked list.
    static func validate(_ raw: String) -> Result<String, FriendsError> {
        let normalized = normalize(raw)
        let count = normalized.count
        guard count >= minLength, count <= maxLength else { return .failure(.invalidName) }
        let forbidden: Set<Character> = ["<", ">", "@", "/", "\\", ":"]
        if normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return .failure(.invalidName)
        }
        if normalized.contains(where: forbidden.contains) { return .failure(.invalidName) }
        let lower = normalized.lowercased()
        if lower.contains("http") || lower.contains("www.") { return .failure(.invalidName) }
        if containsBlockedWord(normalized) { return .failure(.invalidName) }
        return .success(normalized)
    }

    /// NFKC, then every run of whitespace becomes one space, then trimmed.
    static func normalize(_ raw: String) -> String {
        let nfkc = raw.precomposedStringWithCompatibilityMapping
        let parts = nfkc.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    /// Initials for the avatar circle ("Ana-María López" → "AL", "Sam" → "S").
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        let letters = words.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

// MARK: - Invite codes

enum FriendInviteCode {
    /// No 0 / O / 1 / I (and no lower-case l once upper-cased: it reads as L).
    static let charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    static let length = 8

    /// Trim, uppercase, strip spaces and dashes; exactly 8 characters from `charset`, else nil.
    static func normalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        let allowed = Set(charset)
        guard cleaned.count == length, cleaned.allSatisfy(allowed.contains) else { return nil }
        return cleaned
    }

    /// "ABCD 2345".
    static func grouped(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }

    /// baseline://friends/join/ABCD2345
    static func link(_ code: String) -> URL {
        URL(string: "baseline://friends/join/\(code)")!
    }

    static func shareText(_ code: String) -> String {
        "Connect with me on Baseline: enter \(code) in Friends, or open \(link(code).absoluteString)"
    }
}

// MARK: - Local day keys

/// Day-key arithmetic on "yyyy-MM-dd" strings. Every computation runs on a fixed UTC Gregorian calendar, so a key
/// means the same calendar date in any time zone (the server never converts zones either).
enum FriendsDates {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // ISO weeks: Monday
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// UTC midnight of the key's calendar date.
    static func date(_ key: String) -> Date? { parser.date(from: key) }
    static func key(_ date: Date) -> String { parser.string(from: date) }

    /// The local day key for an instant in `timeZone` (the person's "today").
    static func localKey(_ instant: Date, timeZone: TimeZone = .current) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let c = local.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func adding(_ days: Int, to key: String) -> String {
        guard let d = date(key), let r = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return self.key(r)
    }

    /// Inclusive list of keys from `from` to `to` (empty when `to < from`).
    static func days(from: String, to: String) -> [String] {
        guard let a = date(from), let b = date(to), a <= b else { return [] }
        var out: [String] = []
        var cur = a
        while cur <= b {
            out.append(key(cur))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }
        return out
    }

    /// Whole days from `a` to `b` (positive when `b` is later).
    static func distance(from a: String, to b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }

    /// The Monday of the ISO week containing `key`.
    static func monday(of key: String) -> String {
        guard let d = date(key) else { return key }
        let weekday = calendar.component(.weekday, from: d)   // 1 = Sunday … 7 = Saturday
        let back = (weekday + 5) % 7                           // Monday → 0, Sunday → 6
        return adding(-back, to: key)
    }

    /// Monday … Sunday of the week containing `key`.
    static func week(containing key: String) -> [String] {
        let mon = monday(of: key)
        return (0..<7).map { adding($0, to: mon) }
    }

    /// True when the key is a Monday.
    static func isMonday(_ key: String) -> Bool { monday(of: key) == key }

    /// "Mon 6 – Sun 12 Oct", or "Mon 29 Sep – Sun 5 Oct" across months.
    static func rangeText(start: String, end: String) -> String {
        guard let a = date(start), let b = date(end) else { return "\(start) – \(end)" }
        let sameMonth = calendar.component(.month, from: a) == calendar.component(.month, from: b)
            && calendar.component(.year, from: a) == calendar.component(.year, from: b)
        if start == end { return longFormatter.string(from: a) }
        let left = sameMonth ? shortFormatter.string(from: a) : longFormatter.string(from: a)
        return "\(left) – \(longFormatter.string(from: b))"
    }

    /// "Thu 9 Oct" for an instant, in the device's zone.
    static func shortDate(_ instant: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "EEE d MMM"
        return f.string(from: instant)
    }

    /// "Updated today" / "Updated yesterday" / "Updated 3 days ago"; nil when there is no day.
    static func updatedText(lastDay: String?, today: String) -> String? {
        guard let lastDay else { return nil }
        let n = distance(from: lastDay, to: today)
        switch n {
        case ..<1: return "Updated today"
        case 1: return "Updated yesterday"
        default: return "Updated \(n) days ago"
        }
    }
}
