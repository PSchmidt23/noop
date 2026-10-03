import Foundation

/// Competition scoring, pure. The SQL in Baseline/Backend/supabase/schema.sql (`private.competition_scores`) is
/// authoritative; this is its mirror, used by the demo backend, the "Your days" bars and the tests. One fixture is
/// asserted in three places (FriendsScoringTests, tests/scoring.sql and the schema's SELFTEST block), so the two
/// cannot drift silently.
///
/// For each joined member, with n = the number of window days and a missing day counting 0:
/// - steps · goal_percent: Σ_d round(min(v_d / goal, 2) × 100)  (at most 200 a day)
/// - intensity · goal_percent: round(min(Σv × 7 / (weeklyGoal × n), 2) × 100)
/// - any · total: Σv
/// - steps · days_at_goal: count(v_d ≥ goal)
/// Rounding is half away from zero, like Postgres `round(numeric)`, and the points are computed in exact integer
/// arithmetic, as `numeric` does: in Double, 435 ÷ 3,000 × 100 is 14.4999… and would round a point below the server.
enum FriendsScoring {

    /// The lowest daily step goal a competition scores against (a 2,000 goal is stored as 3,000).
    static let stepGoalFloor = 3_000
    static let stepGoalCeiling = 30_000
    static let intensityGoalRange = 60...600
    /// Points for one day (steps) or one window (intensity) never exceed 200, i.e. 2 × the goal.
    static let maxGoalPoints = 200

    /// The goal as the server stores it.
    static func storedStepGoal(_ goal: Int) -> Int { min(stepGoalCeiling, max(stepGoalFloor, goal)) }
    static func storedIntensityGoal(_ goal: Int) -> Int {
        min(intensityGoalRange.upperBound, max(intensityGoalRange.lowerBound, goal))
    }

    /// The goal locked when someone joins: the profile's daily step goal for steps, weekly minutes for intensity,
    /// nil for the day-count metrics.
    static func lockedGoal(metric: FriendsMetric, profile: FriendsProfile) -> Int? {
        switch metric {
        case .steps: return storedStepGoal(profile.stepGoal)
        case .intensity: return storedIntensityGoal(profile.intensityGoal)
        default: return nil
        }
    }

    /// A raw daily value clamped to the metric's server cap; `capped` is true when it was clamped.
    static func capped(_ metric: FriendsMetric, _ value: Int) -> (value: Int, capped: Bool) {
        let v = max(0, value)
        guard let cap = metric.dailyCap else { return (v, false) }
        if metric.isDayCount { return (min(v, 1), false) }
        return v > cap ? (cap, true) : (v, false)
    }

    /// Postgres `round(numeric)`: half away from zero. For values that only exist as doubles (physiology deltas);
    /// scores use `roundedRatio`, which is exact.
    static func pgRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrAwayFromZero)) }

    /// `num ÷ den` rounded half away from zero in exact integer arithmetic (num ≥ 0, den ≥ 1): the same result as
    /// Postgres `round(num::numeric / den)`. (2·num + den) ÷ (2·den), floored, is ⌊num/den + ½⌋.
    static func roundedRatio(_ num: Int, _ den: Int) -> Int {
        let n = max(num, 0), d = max(den, 1)
        return (2 * n + d) / (2 * d)
    }

    /// One day's points as the "Your days" bars show them.
    static func dayPoints(metric: FriendsMetric, mode: CompetitionMode, value: Int, goal: Int?) -> Int {
        switch (mode, metric) {
        case (.goalPercent, .steps):
            // round(min(v / goal, 2) × 100) = min(200, round(100·v / goal)), exactly.
            return min(maxGoalPoints, roundedRatio(100 * max(value, 0), max(goal ?? stepGoalFloor, 1)))
        case (.daysAtGoal, _):
            return value >= (goal ?? Int.max) ? 1 : 0
        default:
            return value
        }
    }

    /// The intensity target over a window of `days` days for a weekly goal (3 days at 150 → 64.29).
    static func intensityTarget(weeklyGoal: Int, days: Int) -> Double {
        Double(weeklyGoal) * Double(days) / 7.0
    }

    /// A member's score over `window` (every day key in the competition) from their `values` (day → value; a day
    /// missing from `values` counts 0). Values must already be capped.
    static func score(metric: FriendsMetric, mode: CompetitionMode, goal: Int?, window: [String],
                      values: [String: Int]) -> Int {
        let vs = window.map { values[$0] ?? 0 }
        switch (mode, metric) {
        case (.goalPercent, .steps):
            return vs.reduce(0) { $0 + dayPoints(metric: .steps, mode: .goalPercent, value: $1, goal: goal) }
        case (.goalPercent, _):
            // round(min(Σv × 7 / (weeklyGoal × n), 2) × 100) = min(200, round(700·Σv / (weeklyGoal × n))), exactly.
            let goalDays = max(goal ?? intensityGoalRange.lowerBound, 1) * window.count
            guard goalDays > 0 else { return 0 }
            return min(maxGoalPoints, roundedRatio(700 * vs.reduce(0, +), goalDays))
        case (.daysAtGoal, _):
            let g = goal ?? Int.max
            return vs.filter { $0 >= g }.count
        case (.total, _):
            return vs.reduce(0, +)
        }
    }

    /// `rank() over (order by score desc)`: ties share a place, the next place skips (1, 1, 3). Members with a nil
    /// score get no place.
    static func places<ID: Hashable>(_ scores: [(id: ID, score: Int?)]) -> [ID: Int] {
        let ranked = scores.compactMap { s in s.score.map { (s.id, $0) } }
        var out: [ID: Int] = [:]
        for (id, score) in ranked {
            out[id] = 1 + ranked.filter { $0.1 > score }.count
        }
        return out
    }

    /// True when someone else holds the same place.
    static func isTied<ID: Hashable>(_ id: ID, places: [ID: Int]) -> Bool {
        guard let p = places[id] else { return false }
        return places.filter { $0.value == p }.count > 1
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st".
    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10, ones = n % 10
        let suffix: String
        if tens == 1 { suffix = "th" } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    /// The place column: "1st", "=2nd" (tied). Always an ordinal, so the column keeps one shape.
    static func placeText(_ place: Int, tied: Bool) -> String {
        tied ? "=\(ordinal(place))" : ordinal(place)
    }

    /// The same place as VoiceOver reads it: "2nd", "tied 2nd" (never "equals").
    static func placeSpoken(_ place: Int, tied: Bool) -> String {
        tied ? "tied \(ordinal(place))" : ordinal(place)
    }

    /// When results become final: (end_day + 3) at 12:00 UTC, i.e. 48 h after the last day ends anywhere on Earth.
    static func freezeAt(endDay: String) -> Date {
        let base = FriendsDates.date(FriendsDates.adding(3, to: endDay)) ?? Date.distantFuture
        return base.addingTimeInterval(12 * 3600)
    }

    /// Builds a standings table from members' values (the demo backend's server). `members` carries each person's
    /// state, locked goal, values and whether they still share the metric.
    struct MemberInput: Sendable {
        var userID: UUID
        var name: String
        var state: MemberState
        var goal: Int?
        var sharing: Bool
        var values: [String: Int]
        var cappedDays: Set<String>
        var sources: [String: String]

        init(userID: UUID, name: String, state: MemberState, goal: Int?, sharing: Bool, values: [String: Int],
             cappedDays: Set<String> = [], sources: [String: String] = [:]) {
            self.userID = userID; self.name = name; self.state = state; self.goal = goal
            self.sharing = sharing; self.values = values; self.cappedDays = cappedDays; self.sources = sources
        }
    }

    static func standings(metric: FriendsMetric, mode: CompetitionMode, window: [String],
                          members: [MemberInput]) -> [Standing] {
        let scored = members.filter { $0.state == .joined || $0.state == .left }
        let scores: [(id: UUID, score: Int?)] = scored.map { m in
            (m.userID, m.sharing ? score(metric: metric, mode: mode, goal: m.goal, window: window, values: m.values) : nil)
        }
        let rankable = zip(scored, scores).filter { $0.0.state == .joined }.map { $0.1 }
        let placeMap = places(rankable)
        let windowSet = Set(window)
        let rows: [Standing] = zip(scored, scores).map { m, s in
            let counted = m.values.keys.filter(windowSet.contains).count
            let capped = m.cappedDays.filter(windowSet.contains).count
            let mix = Set(m.sources.filter { windowSet.contains($0.key) }.values).sorted().joined(separator: "+")
            return Standing(userID: m.userID, name: m.name, state: m.state, score: m.sharing ? s.score : nil,
                            place: m.state == .joined ? placeMap[m.userID] : nil,
                            daysCounted: m.sharing ? counted : 0, cappedDays: m.sharing ? capped : 0,
                            sharing: m.sharing, sourceMix: mix.isEmpty ? nil : mix)
        }
        return sortStandings(rows)
    }

    /// Ranked rows first (by place, then name), then people who left, then non-sharers.
    static func sortStandings(_ rows: [Standing]) -> [Standing] {
        rows.sorted { a, b in
            func bucket(_ s: Standing) -> Int { s.place != nil ? 0 : (s.state == .left && s.sharing ? 1 : 2) }
            if bucket(a) != bucket(b) { return bucket(a) < bucket(b) }
            if let pa = a.place, let pb = b.place, pa != pb { return pa < pb }
            if (a.score ?? -1) != (b.score ?? -1) { return (a.score ?? -1) > (b.score ?? -1) }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// The caller's own day bars.
    static func myDays(metric: FriendsMetric, mode: CompetitionMode, goal: Int?, window: [String],
                       values: [String: Int], cappedDays: Set<String>, through today: String) -> [DayPoints] {
        window.filter { $0 <= today }.map { day in
            let v = values[day] ?? 0
            return DayPoints(day: day, value: v, points: dayPoints(metric: metric, mode: mode, value: v, goal: goal),
                             capped: cappedDays.contains(day))
        }
    }

    /// The rule line on the competition detail. A sleep competition names the person's own goal
    /// (`BaselineReadouts.SleepGoal`, Settings › Profile): each person's nights count against their own.
    static func ruleText(metric: FriendsMetric, mode: CompetitionMode,
                         sleepGoalMinutes: Int = BaselineReadouts.SleepGoal.minutes()) -> String {
        switch (mode, metric) {
        case (.goalPercent, .steps):
            return "Points = your steps ÷ your own goal × 100 each day, at most 200"
        case (.goalPercent, _):
            return "Points = your minutes ÷ your own goal for these days × 100, at most 200"
        case (.daysAtGoal, _):
            return "One point for each day you reach your own goal"
        case (.total, .steps):
            return "Total steps, up to 60,000 a day"
        case (.total, .intensity):
            return "Total intensity minutes, up to 300 a day"
        case (.total, .active):
            return "One point for each active day"
        case (.total, .sleepGoal):
            return "One point for each night asleep for at least your own sleep goal (yours is \(BaselineReadouts.SleepGoal.text(sleepGoalMinutes)), set in Settings › Profile)"
        case (.total, .bedtime):
            return "One point for each bedtime within 30 minutes of your own target"
        case (.total, _):
            return "Total"
        }
    }
}
