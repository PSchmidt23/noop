import Foundation

/// The Friends tab's leaderboard, friend cards and trend copy, pure. The server never ranks friends
/// (`friends_overview` returns only the rows RLS lets the viewer see); this ranks them on the phone. Screens never
/// compute scores themselves.
///
/// Physiology is never ranked, never sorted by value and never compared between people: `trendPill` and
/// `trendSentence` describe one person against their own baseline, and friend cards are alphabetical.
enum FriendsBoard {

    /// "This week | 4 weeks".
    enum Window: String, CaseIterable, Sendable {
        case week, fourWeeks

        var title: String { self == .week ? "This week" : "4 weeks" }

        /// The day keys the window covers up to `today` (Monday of this week, or of 3 weeks earlier).
        func days(today: String) -> [String] {
            let monday = FriendsDates.monday(of: today)
            let start = self == .week ? monday : FriendsDates.adding(-21, to: monday)
            return FriendsDates.days(from: start, to: today)
        }
    }

    /// "% of own goal | Total" (steps only; every other metric scores as a total). Same words as
    /// `CompetitionMode.goalPercent.title`.
    enum Scoring: String, CaseIterable, Sendable {
        case goalPercent, total
        var title: String { self == .goalPercent ? "% of own goal" : "Total" }
    }

    struct Row: Identifiable, Equatable, Sendable {
        var id: UUID
        var name: String
        var initials: String
        var isMe: Bool
        /// nil with Competitive view off.
        var place: Int?
        var tied: Bool
        /// The ranking number (points for % of own goal, else the total).
        var score: Int
        var total: Int
        /// 0…1 for the bar, relative to the top score on the board.
        var fraction: Double
        /// "84 % of own goal · 9,010 a day", "52,310 steps", "112 min", "5 of 7 nights".
        var valueText: String
        /// The whole row read as one VoiceOver element.
        var accessibilityText: String

        var placeText: String? { place.map { FriendsScoring.placeText($0, tied: tied) } }
    }

    struct Board: Equatable, Sendable {
        var metric: FriendsMetric
        var scoring: Scoring
        var window: Window
        var rows: [Row]
        /// "You're 2nd of 5 · 6 % behind Alex"; nil with Competitive view off or when I'm not on the board.
        var headline: String?
        /// Accepted friends who don't share this metric with me at the Friends level.
        var nonSharers: Int
        /// False when I don't share this metric at the Friends level (the "Share Steps with friends" prompt).
        var meIncluded: Bool

        /// "2 friends don't share steps"; nil when everyone does.
        var nonSharersText: String? {
            guard nonSharers > 0 else { return nil }
            let who = nonSharers == 1 ? "1 friend doesn't" : "\(nonSharers) friends don't"
            return "\(who) share \(metric.title.lowercased())"
        }

        static let rankingCaption = "Ranked on what you do. HRV, resting HR and readiness are never ranked."
    }

    /// The behaviour metrics a chip row offers: shared at the Friends level by me and at least one accepted friend.
    static func boardMetrics(overview: FriendsOverview) -> [FriendsMetric] {
        FriendsMetric.behaviour.filter { m in
            overview.myShares[m] == .friends && overview.accepted.contains { $0.sharedBehaviour.contains(m) }
        }
    }

    /// Ranks me and my accepted friends on one behaviour metric over a window.
    /// - `today`: the viewer's local day key (the window ends here).
    /// - `competitive`: off → alphabetical, no places, no headline.
    /// - `muted`: muted friends still count but are left off the board (they collapse on the cards too).
    static func board(metric: FriendsMetric, scoring requested: Scoring, window: Window, today: String,
                      overview: FriendsOverview, competitive: Bool, muted: Set<UUID> = []) -> Board {
        let scoring: Scoring = metric == .steps ? requested : .total
        let days = window.days(today: today)
        let accepted = overview.accepted.filter { !muted.contains($0.id) }
        let sharers = accepted.filter { $0.sharedBehaviour.contains(metric) }
        let nonSharers = accepted.count - sharers.count
        let meIncluded = overview.myShares[metric] == .friends

        struct Entry { var id: UUID; var name: String; var isMe: Bool; var goal: Int?; var values: [String: Int] }
        var entries: [Entry] = sharers.map {
            Entry(id: $0.id, name: $0.name, isMe: false, goal: $0.profile.goal(for: metric),
                  values: values(of: $0.days, metric: metric))
        }
        if meIncluded {
            entries.append(Entry(id: overview.me.id, name: overview.me.displayName, isMe: true,
                                 goal: overview.me.goal(for: metric), values: values(of: overview.myDays, metric: metric)))
        }

        let scored: [(entry: Entry, score: Int, total: Int)] = entries.map { e in
            let total = days.reduce(0) { $0 + (e.values[$1] ?? 0) }
            let score: Int
            switch scoring {
            case .goalPercent:
                score = FriendsScoring.score(metric: .steps, mode: .goalPercent,
                                             goal: FriendsScoring.storedStepGoal(e.goal ?? 8_000),
                                             window: days, values: e.values)
            case .total:
                score = total
            }
            return (e, score, total)
        }
        let top = max(1, scored.map(\.score).max() ?? 1)
        let placeMap = competitive ? FriendsScoring.places(scored.map { (id: $0.entry.id, score: Optional($0.score)) }) : [:]

        var rows: [Row] = scored.map { s in
            let place = placeMap[s.entry.id]
            let tied = place != nil && FriendsScoring.isTied(s.entry.id, places: placeMap)
            let valueText = self.valueText(metric: metric, scoring: scoring, score: s.score, total: s.total,
                                           dayCount: days.count)
            let displayName = s.entry.isMe ? "You" : s.entry.name
            var spoken = displayName
            if let place { spoken += ", " + FriendsScoring.placeSpoken(place, tied: tied) }
            spoken += ", " + valueText
            return Row(id: s.entry.id, name: displayName, initials: DisplayName.initials(s.entry.name), isMe: s.entry.isMe,
                       place: place, tied: tied, score: s.score, total: s.total,
                       fraction: min(1, Double(s.score) / Double(top)), valueText: valueText,
                       accessibilityText: spoken)
        }
        if competitive {
            rows.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.total != b.total { return a.total > b.total }   // "% of own goal, with total second"
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        } else {
            rows.sort { a, b in
                if a.isMe != b.isMe { return a.isMe }   // You first, then alphabetical
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        let headline = competitive && meIncluded
            ? self.headline(rows: rows, metric: metric, scoring: scoring, dayCount: days.count) : nil
        return Board(metric: metric, scoring: scoring, window: window, rows: rows, headline: headline,
                     nonSharers: nonSharers, meIncluded: meIncluded)
    }

    /// "You're 2nd of 5 · 6 % behind Alex" (names only the person directly above), "Tied 1st of 5",
    /// "You're 1st of 5". nil when I'm not on the board or I'm alone. The gap is in the unit the rows print.
    static func headline(rows: [Row], metric: FriendsMetric, scoring: Scoring, dayCount: Int) -> String? {
        guard rows.count > 1, let me = rows.first(where: \.isMe), let place = me.place else { return nil }
        let of = "of \(rows.count)"
        if me.tied {
            let lead = "Tied \(FriendsScoring.ordinal(place)) \(of)"
            guard place > 1, let above = rows.filter({ ($0.place ?? 0) < place }).last else { return lead }
            return "\(lead) · \(gapText(above: above, me: me, metric: metric, scoring: scoring, dayCount: dayCount)) behind \(above.name)"
        }
        let lead = "You're \(FriendsScoring.ordinal(place)) \(of)"
        guard place > 1, let above = rows.filter({ ($0.place ?? 0) < place }).last else { return lead }
        return "\(lead) · \(gapText(above: above, me: me, metric: metric, scoring: scoring, dayCount: dayCount)) behind \(above.name)"
    }

    /// The gap to the person above, in the unit the rows print. % of own goal: the difference between the two rows'
    /// daily percents ("6 %"), or "less than 1 %" when both round to the same figure; the summed points behind the
    /// ranking appear nowhere on the board, so they are never printed. Totals: "1,240 steps", "35 min", "2 nights".
    static func gapText(above: Row, me: Row, metric: FriendsMetric, scoring: Scoring, dayCount: Int) -> String {
        if scoring == .goalPercent {
            let gap = dailyPercent(above.score, dayCount: dayCount) - dailyPercent(me.score, dayCount: dayCount)
            return gap >= 1 ? "\(gap) %" : "less than 1 %"
        }
        let gap = above.score - me.score
        return "\(number(gap)) \(metric.unitText(gap))"
    }

    /// The "% of own goal" a row prints: the summed daily points over the window, per day, rounded half up.
    static func dailyPercent(_ score: Int, dayCount: Int) -> Int {
        FriendsScoring.roundedRatio(score, max(dayCount, 1))
    }

    static func valueText(metric: FriendsMetric, scoring: Scoring, score: Int, total: Int, dayCount: Int) -> String {
        let n = max(dayCount, 1)
        switch (metric, scoring) {
        case (.steps, .goalPercent):
            let pct = dailyPercent(score, dayCount: n)
            let perDay = FriendsScoring.roundedRatio(total, n)
            return "\(pct) % of own goal · \(number(perDay)) a day"
        case (.steps, .total):
            return "\(number(total)) steps"
        case (.intensity, _):
            return "\(number(total)) min"
        case (.active, _):
            return "\(total) of \(dayCount) days"
        case (.sleepGoal, _), (.bedtime, _):
            return "\(total) of \(dayCount) nights"
        default:
            return number(total)
        }
    }

    /// day → value for one metric.
    static func values(of days: [DailyShare], metric: FriendsMetric) -> [String: Int] {
        var out: [String: Int] = [:]
        for d in days where d.metric == metric { out[d.day] = d.value }
        return out
    }

    /// Grouped in the device's locale, the same as `FriendsUI.number` and the Steps card, so a leaderboard row and
    /// a friend card on one screen never print one number two ways ("9,010" in en_US, "9.010" in de_DE).
    static func number(_ n: Int, locale: Locale = .autoupdatingCurrent) -> String {
        n.formatted(.number.locale(locale))
    }

    // MARK: - Friend cards

    /// Accepted friends, ALPHABETICAL, muted ones split off ("Muted (n)"). Never sorted by any value.
    static func friendCards(_ overview: FriendsOverview, muted: Set<UUID>) -> (visible: [Friend], muted: [Friend]) {
        let sorted = overview.accepted.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (sorted.filter { !muted.contains($0.id) }, sorted.filter { muted.contains($0.id) })
    }

    enum GoalDot: String, Equatable, Sendable {
        /// Filled: at own goal that day.
        case met
        /// Hollow: data, goal missed.
        case missed
        /// Faint: a future day or no data.
        case none
    }

    /// Mon–Sun dots for a person's first shared behaviour metric this week. A day is "met" when its value reaches
    /// their own goal: daily step goal for steps, weekly goal ÷ 7 for intensity, 1 for the day-count metrics.
    static func goalDots(days: [DailyShare], metric: FriendsMetric, profile: FriendsProfile, today: String) -> [GoalDot] {
        let byDay = values(of: days, metric: metric)
        return FriendsDates.week(containing: today).map { day in
            guard day <= today, let v = byDay[day] else { return .none }
            return v >= dailyGoal(metric: metric, profile: profile) ? .met : .missed
        }
    }

    /// The per-day goal a bar's tick and a dot compare against.
    static func dailyGoal(metric: FriendsMetric, profile: FriendsProfile) -> Int {
        switch metric {
        case .steps: return FriendsScoring.storedStepGoal(profile.stepGoal)
        case .intensity: return max(1, Int((Double(FriendsScoring.storedIntensityGoal(profile.intensityGoal)) / 7).rounded()))
        default: return 1
        }
    }

    /// "4 of 7 goal days" (the dots' one VoiceOver summary; only days so far count).
    static func dotsSummary(_ dots: [GoalDot]) -> String {
        let met = dots.filter { $0 == .met }.count
        return "\(met) of 7 goal days"
    }

    /// Seven values (Mon–Sun) for the thin bars; nil for a future day or no data.
    static func weekBars(days: [DailyShare], metric: FriendsMetric, today: String) -> [(day: String, value: Int?)] {
        let byDay = values(of: days, metric: metric)
        return FriendsDates.week(containing: today).map { ($0, $0 <= today ? byDay[$0] : nil) }
    }

    // MARK: - Physiology pills (never ranked)

    /// The newest row per physiology metric.
    static func latestTrends(_ trends: [TrendShare]) -> [FriendsMetric: TrendShare] {
        var out: [FriendsMetric: TrendShare] = [:]
        for t in trends {
            if let cur = out[t.metric], cur.weekStart >= t.weekStart { continue }
            out[t.metric] = t
        }
        return out
    }

    /// Pills in a FIXED order (HRV, Resting HR, Readiness), never by value.
    static func pills(_ trends: [TrendShare]) -> [String] {
        let latest = latestTrends(trends)
        return FriendsMetric.physiology.compactMap { latest[$0].map(trendPill) }
    }

    /// "HRV +8 % vs own baseline", "Resting HR −2 bpm vs own baseline", "Readiness +4 vs own month",
    /// "HRV · calibrating"; when clipped, "HRV ≥ +30 % vs own baseline" above and "HRV ≤ −30 % vs own baseline"
    /// below (the true change is at least that far out, in the direction of its sign).
    static func trendPill(_ t: TrendShare) -> String {
        let name = t.metric.shortTitle
        guard t.status == .ready, let delta = t.delta else { return "\(name) · calibrating" }
        let magnitude = signed(delta)
        let shown = t.clipped ? "\(delta < 0 ? "≤" : "≥") \(magnitude)" : magnitude
        switch t.metric {
        case .hrv: return "\(name) \(shown) % vs own baseline"
        case .rhr: return "\(name) \(shown) bpm vs own baseline"
        default: return "\(name) \(shown) vs own month"
        }
    }

    /// "HRV is 8 % above Alex's own baseline, within their usual range."
    static func trendSentence(_ t: TrendShare, name: String) -> String {
        let possessive = name.hasSuffix("s") ? "\(name)'" : "\(name)'s"
        guard t.status == .ready, let delta = t.delta else {
            return "\(t.metric.shortTitle) is still calibrating against \(possessive) own baseline."
        }
        let band = t.band.map { ", \($0.phrase)" } ?? ""
        let more = t.clipped ? "at least " : ""
        switch t.metric {
        case .hrv:
            if delta == 0 { return "HRV is at \(possessive) own baseline\(band)." }
            return "HRV is \(more)\(abs(delta)) % \(delta > 0 ? "above" : "below") \(possessive) own baseline\(band)."
        case .rhr:
            if delta == 0 { return "Resting HR is at \(possessive) own baseline\(band)." }
            return "Resting HR is \(more)\(abs(delta)) bpm \(delta > 0 ? "above" : "below") \(possessive) own baseline\(band)."
        default:
            if delta == 0 { return "Readiness this week matches \(possessive) own month\(band)." }
            return "Readiness this week is \(more)\(abs(delta)) \(abs(delta) == 1 ? "point" : "points") \(delta > 0 ? "above" : "below") \(possessive) own month\(band)."
        }
    }

    static let trendFootnote = "Each person against their own baseline. Not comparable between people."

    /// "+8", "−2" (true minus sign), "0".
    static func signed(_ n: Int) -> String {
        if n > 0 { return "+\(n)" }
        if n < 0 { return "−\(abs(n))" }
        return "0"
    }
}
