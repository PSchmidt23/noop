import Foundation
import StrandAnalytics

/// The person's own data as the Friends upload sees it: plain values keyed by LOCAL day, already read from the
/// funnel Home reads (the Data-source picker) by `FriendsUploadInputs.load` (or built by hand in tests). Nothing here is shared as is:
/// `FriendsUploadBuilder.build` turns it into capped daily integers, 0/1 nights and clipped weekly deltas.
struct FriendsUploadInputs: Sendable {
    struct StepDay: Equatable, Sendable {
        var value: Int
        /// "strap", "phone", "estimate" or "import". Only strap and phone counts are ever uploaded.
        var source: String
    }

    struct Night: Equatable, Sendable {
        /// Asleep minutes (light + deep + REM).
        var asleepMinutes: Int
        /// Bed time as minutes after local midnight; nil when the night has no clock times (an imported total).
        var bedMinuteOfDay: Double?
    }

    /// A day's 0/1 answers already decided by the app's readout (`BaselineReadouts.friendsDailyAggregates`, the
    /// same rules as below). When present they win over the raw fields, so the upload can never disagree with
    /// what the app itself computed for that day. nil fields fall back to the raw rule.
    struct DayFlags: Equatable, Sendable {
        var active: Int?
        var sleepGoal: Int?
        var bedtime: Int?
    }

    /// The upload day (the person's local today).
    var today: String
    var stepDays: [String: StepDay] = [:]
    /// Credited intensity minutes for days the per-day store RECORDED (scored minutes or credit); nothing else.
    var intensityDays: [String: Int] = [:]
    /// The longest workout that local day, in minutes.
    var workoutMinutesByDay: [String: Int] = [:]
    /// Keyed by the WAKE day (Baseline's night key).
    var nights: [String: Night] = [:]
    /// Precomputed 0/1 answers per day (see `DayFlags`).
    var dayFlags: [String: DayFlags] = [:]
    /// `baseline.sleepGoalMinutes`, default 450.
    var sleepGoalMinutes: Int = FriendsUploadInputs.defaultSleepGoalMinutes
    /// `SleepWindow.stored().bedMinutes`.
    var targetBedMinutes: Int = 23 * 60
    /// Valid nightly HRV (RMSSD ms) and resting HR (bpm), keyed by night; at least the last ~120 nights so each
    /// week's baseline can be folded from the nights before it.
    var hrvNights: [String: Double] = [:]
    var rhrNights: [String: Double] = [:]
    /// NOOP's HRV recalibration epoch (`Baselines.hrvBaselineEpoch()`); 0 = none.
    var hrvEpoch: Double = 0
    /// The stored Readiness score (0–100) per morning.
    var readinessByDay: [String: Double] = [:]

    static let defaultSleepGoalMinutes = 450
}

/// Pure: local readouts → the rows the server accepts (FRIENDS_SPEC.md §5.2). Only metrics with a share entry are
/// built; the server drops anything else anyway.
enum FriendsUploadBuilder {

    /// Activity counts as an active day from 20 intensity minutes or a 20-minute workout.
    static let activeMinutes = 20
    /// Bedtime counts as on time within ±30 minutes of the target.
    static let bedtimeToleranceMinutes = 30.0
    /// Physiology waits for 14 valid nights in the last 30 before any delta is shared.
    static let trendGateNights = 14
    static let trendGateWindow = 30
    /// A week's mean needs at least this many values in its 7 days.
    static let weekMinValues = 3
    /// Current week plus 4 previous.
    static let trendWeeks = 5

    /// `days`: the day keys to build daily rows for (the scheduler passes 35 days or the incremental window).
    static func build(_ inputs: FriendsUploadInputs, shares: [FriendsMetric: ShareAudience],
                      days: [String]) -> ([DailyShare], [TrendShare]) {
        guard !shares.isEmpty else { return ([], []) }
        var out: [DailyShare] = []
        for day in days.sorted() {
            for metric in FriendsMetric.behaviour where shares[metric] != nil {
                if let row = dailyRow(metric: metric, day: day, inputs: inputs) { out.append(row) }
            }
        }
        var trends: [TrendShare] = []
        for metric in FriendsMetric.physiology where shares[metric] != nil {
            trends += trendRows(metric: metric, inputs: inputs)
        }
        return (out, trends)
    }

    static func dailyRow(metric: FriendsMetric, day: String, inputs: FriendsUploadInputs) -> DailyShare? {
        switch metric {
        case .steps:
            guard let s = inputs.stepDays[day], s.source == "strap" || s.source == "phone" else { return nil }
            let c = FriendsScoring.capped(.steps, s.value)
            return DailyShare(day: day, metric: .steps, value: c.value, source: s.source, capped: c.capped)
        case .intensity:
            guard let m = inputs.intensityDays[day] else { return nil }
            let c = FriendsScoring.capped(.intensity, m)
            return DailyShare(day: day, metric: .intensity, value: c.value, capped: c.capped)
        case .active:
            if let flag = inputs.dayFlags[day]?.active { return DailyShare(day: day, metric: .active, value: flag > 0 ? 1 : 0) }
            let m = inputs.intensityDays[day]
            let w = inputs.workoutMinutesByDay[day]
            guard m != nil || w != nil else { return nil }
            let active = (m ?? 0) >= activeMinutes || (w ?? 0) >= activeMinutes
            return DailyShare(day: day, metric: .active, value: active ? 1 : 0)
        case .sleepGoal:
            if let flag = inputs.dayFlags[day]?.sleepGoal { return DailyShare(day: day, metric: .sleepGoal, value: flag > 0 ? 1 : 0) }
            guard let n = inputs.nights[day] else { return nil }
            return DailyShare(day: day, metric: .sleepGoal, value: n.asleepMinutes >= inputs.sleepGoalMinutes ? 1 : 0)
        case .bedtime:
            if let flag = inputs.dayFlags[day]?.bedtime { return DailyShare(day: day, metric: .bedtime, value: flag > 0 ? 1 : 0) }
            guard let n = inputs.nights[day], let bed = n.bedMinuteOfDay else { return nil }
            let onTime = clockDistance(bed, Double(inputs.targetBedMinutes)) <= bedtimeToleranceMinutes
            return DailyShare(day: day, metric: .bedtime, value: onTime ? 1 : 0)
        case .hrv, .rhr, .readiness:
            return nil
        }
    }

    /// Minutes between two clock times the short way round (23:50 vs 00:10 = 20). Same rule as
    /// `BaselineReadouts.clockDistance`, repeated here so the builder stays free of the app's readout layer.
    static func clockDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1440)
        return min(d, 1440 - d)
    }

    // MARK: - Trends

    /// The weeks to send: the current week (ending today) and up to 4 previous (each ending on its Sunday), keyed
    /// by Monday, oldest first.
    static func weeks(today: String) -> [(monday: String, end: String)] {
        let thisMonday = FriendsDates.monday(of: today)
        return (0..<trendWeeks).reversed().map { back in
            let monday = FriendsDates.adding(-7 * back, to: thisMonday)
            let end = back == 0 ? today : FriendsDates.adding(6, to: monday)
            return (monday, end)
        }
    }

    static func trendRows(metric: FriendsMetric, inputs: FriendsUploadInputs) -> [TrendShare] {
        weeks(today: inputs.today).compactMap { week in
            trendRow(metric: metric, weekStart: week.monday, end: week.end, inputs: inputs)
        }
    }

    /// One week's row, or nil when the week has too few values to say anything (no row is better than a guess).
    static func trendRow(metric: FriendsMetric, weekStart: String, end: String, inputs: FriendsUploadInputs) -> TrendShare? {
        let series: [String: Double]
        switch metric {
        case .hrv: series = inputs.hrvNights
        case .rhr: series = inputs.rhrNights
        case .readiness: series = inputs.readinessByDay
        default: return nil
        }
        let last30 = window(series, endingOn: end, days: trendGateWindow)
        let last7 = window(series, endingOn: end, days: 7)
        guard last30.count >= trendGateNights else {
            // Calibrating is said once, for the current week; older weeks simply have no row.
            return end == inputs.today ? TrendShare(metric: metric, weekStart: weekStart, status: .calibrating) : nil
        }
        guard last7.count >= weekMinValues else { return nil }
        let mean7 = last7.reduce(0, +) / Double(last7.count)
        let clip = metric.trendClip ?? 0
        let raw: Int
        let band: TrendBand
        switch metric {
        case .readiness:
            let mean30 = last30.reduce(0, +) / Double(last30.count)
            raw = FriendsScoring.pgRound(mean7 - mean30)
            band = abs(raw) < 5 ? .within : (raw > 0 ? .above : .below)
        default:
            // The baseline is folded from the nights BEFORE the week's 7-day window: a night never sits inside
            // its own baseline (the rule every Baseline baseline follows).
            let windowStart = FriendsDates.adding(-6, to: end)
            let history = series.filter { $0.key < windowStart }.sorted { $0.key < $1.key }
            let cfg = metric == .hrv ? Baselines.hrvCfg : Baselines.restingHRCfg
            let state = Baselines.foldHistory(history.map { Optional($0.value) }, dayKeys: history.map(\.key), cfg: cfg,
                                              baselineEpoch: metric == .hrv ? inputs.hrvEpoch : 0)
            guard state.usable, state.baseline > 0 else {
                return end == inputs.today ? TrendShare(metric: metric, weekStart: weekStart, status: .calibrating) : nil
            }
            raw = metric == .hrv
                ? FriendsScoring.pgRound((mean7 / state.baseline - 1) * 100)
                : FriendsScoring.pgRound(mean7 - state.baseline)
            let z = Baselines.deviation(mean7, state: state).z
            band = abs(z) < 1 ? .within : (z > 0 ? .above : .below)
        }
        let clipped = abs(raw) > clip
        let delta = clipped ? (raw > 0 ? clip : -clip) : raw
        return TrendShare(metric: metric, weekStart: weekStart, status: .ready, delta: delta, band: band, clipped: clipped)
    }

    /// The values in the `days` days ending on `end` (inclusive).
    static func window(_ series: [String: Double], endingOn end: String, days: Int) -> [Double] {
        let start = FriendsDates.adding(-(days - 1), to: end)
        return series.filter { $0.key >= start && $0.key <= end && $0.value.isFinite }.map(\.value)
    }

    // MARK: - Incremental window

    /// A stable 64-bit FNV-1a hash (Swift's `Hasher` is seeded per process, so it cannot be persisted).
    static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h)
    }

    /// The digest key and value for one row (`metric|day` → hash of value, source, capped; never the value itself).
    static func digestEntry(_ row: DailyShare) -> (key: String, hash: Int) {
        ("\(row.metric.rawValue)|\(row.day)", stableHash("\(row.value)|\(row.source ?? "")|\(row.capped)"))
    }

    /// The rows to send on an incremental upload: today and the 2 days before it, plus any row whose digest changed.
    /// `full` sends everything.
    static func select(_ rows: [DailyShare], today: String, digest: [String: Int], full: Bool) -> [DailyShare] {
        if full { return rows }
        let recent = Set((0...2).map { FriendsDates.adding(-$0, to: today) })
        return rows.filter { row in
            if recent.contains(row.day) { return true }
            let e = digestEntry(row)
            return digest[e.key] != e.hash
        }
    }

    /// Days the digest says were accepted before that now have no row, for metrics still shared, inside `window`:
    /// each becomes a retraction so the server deletes the old value instead of counting it until retention. Only
    /// this phone's own accepted keys are retracted (a new phone's empty digest retracts nothing), and a metric
    /// turned Off needs none (`set_share` Off already deleted its rows). Sorted by day, then metric.
    static func retractions(rows: [DailyShare], digest: [String: Int], shares: [FriendsMetric: ShareAudience],
                            window: [String]) -> [DailyRetraction] {
        let current = Set(rows.map { digestEntry($0).key })
        let days = Set(window)
        var out: [DailyRetraction] = []
        for key in digest.keys where !current.contains(key) {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let metric = FriendsMetric(rawValue: parts[0]), metric.isBehaviour,
                  shares[metric] != nil, days.contains(parts[1]) else { continue }
            out.append(DailyRetraction(day: parts[1], metric: metric))
        }
        return out.sorted { ($0.day, $0.metric.rawValue) < ($1.day, $1.metric.rawValue) }
    }

    /// The digest after `rows` were accepted and `retracted` deleted, pruned to the last 40 days.
    static func updatedDigest(_ digest: [String: Int], with rows: [DailyShare], retracted: [DailyRetraction] = [],
                              today: String) -> [String: Int] {
        var out = digest
        for r in retracted { out["\(r.metric.rawValue)|\(r.day)"] = nil }
        for r in rows { let e = digestEntry(r); out[e.key] = e.hash }
        let oldest = FriendsDates.adding(-40, to: today)
        return out.filter { entry in
            guard let day = entry.key.split(separator: "|").last.map(String.init) else { return false }
            return day >= oldest
        }
    }

    /// The day keys of the 35-day upload window ending today.
    static func fullWindow(today: String) -> [String] {
        FriendsDates.days(from: FriendsDates.adding(-34, to: today), to: today)
    }
}
