#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Pure derivations for the Progress screen: is the personal baseline itself moving over months?
// Everything here is a value type built from `repo.baselineDays` (through `BaselineReadouts.nightlyStates`,
// the one fold walk Trends draws its band from), the Sleep tab's `SleepNight` list (through
// `BaselineReadouts.sleepTiming`, the readout the Sleep tab prints) and NOOP's weekly fitness read
// (through `BaselineReadouts.fitness`). Nothing touches the store or SwiftUI.
//
// Not drawn, on purpose: a "Readiness baseline" card. The Readiness score (`DailyMetric.recovery`) is
// NOOP's weighted z-score of each night AGAINST the person's moving HRV / resting HR baselines, mapped so
// z = 0 reads 58. Its long-run level is therefore pinned near 58 by construction: a baseline that climbs
// for three months shows up in the HRV card and vanishes from Readiness, which only ever says how last
// night compared with the weeks before it. A trajectory of it over a horizon would read as "no progress"
// for everyone, and a mixed history changes formula at the import boundary (imported days carry the
// vendor's own score verbatim; strap days NOOP's). The literature table rates composite scores Low
// (no outcome validation). So Progress keeps Readiness where it is honest: one morning at a time, on Home.
//
// Also not drawn, on purpose: a "Heart rate" baseline card (the daily minimum heart rate over months).
// The honest version of that number already exists on this screen: the Resting HR card, NOOP's
// overnight resting HR folded through the same winsorized EWMA, with a trust gate and a noise floor.
// A daily minimum off the intraday stream (`IntradayDayRecord.bpmMin`, the lowest SAMPLE in the lowest
// 60-second bucket of the day) is the most artefact-prone statistic the strap yields: one low-confidence
// PPG second, a strap loosened on the charger or a bucket straddling the night's end reads lower than
// any night, and an EWMA of minima would track those artefacts, not the heart. It would also restate
// the resting HR trajectory (the two agree whenever the day's low is overnight, which is nearly every
// day), so the screen would say one fact twice, and it exists only for strap days that a screen has
// already asked `IntradayDayStore` to classify (imports carry no intraday heart rate), so a 180-day
// horizon would mean classifying 180 days of samples on first open to draw a line the Resting HR card
// already draws. The day's low, mean and high stay where they are honest: the Heart rate detail
// (`MetricDetailSpec.standard(.heartRate)`), per day and over 7D / 4W / 1Y, with its Medium badge.

// MARK: - Horizon

/// How far back Progress compares the baseline with itself. Raw value = days (what AppStorage persists);
/// `.all` is 0.
enum ProgressHorizon: Int, CaseIterable, Identifiable, BaselineRangeOption {
    case quarter = 90
    case half = 180
    case year = 365
    case all = 0

    var id: Int { rawValue }
    /// nil for `.all`.
    var days: Int? { self == .all ? nil : rawValue }

    var label: String {
        switch self {
        case .quarter: return "90D"
        case .half: return "180D"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    var subtitle: String {
        switch self {
        case .quarter: return "Last 90 days"
        case .half: return "Last 180 days"
        case .year: return "Last year"
        case .all: return "All time"
        }
    }

    /// How the far end reads in a sentence; nil for `.all` (which names the day the baseline settled).
    var agoPhrase: String? {
        switch self {
        case .quarter: return "90 days ago"
        case .half: return "180 days ago"
        case .year: return "a year ago"
        case .all: return nil
        }
    }

    static func resolve(_ raw: Int) -> ProgressHorizon { ProgressHorizon(rawValue: raw) ?? .quarter }

    /// The day key `days` before `todayKey` (pure UTC key math), nil for `.all`.
    func cutoff(todayKey: String) -> String? {
        days.map { Baselines.cutoffKey(todayKey: todayKey, carryDays: $0) }
    }
}

// MARK: - Trajectory

/// The baseline GOING INTO valid night `id`: the state after folding every night before it, the same
/// number the Trends band carries at that night.
struct ProgressPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let baseline: Double
    let sigma: Double
    let nValid: Int
    let trusted: Bool

    var day: String { id }
}

enum ProgressTrajectory {
    /// Usable points only (provisional + trusted): at valid night D the state going into D. Missing
    /// nights emit nothing; the engine's skip-and-hold makes the straight segment across a gap literally
    /// correct. The last point equals `BaselineReadouts.latestNight(...).state` whenever that is usable.
    static func build(walk: [BaselineReadouts.NightState]) -> [ProgressPoint] {
        var out: [ProgressPoint] = []
        out.reserveCapacity(walk.count)
        for n in walk {
            guard n.validValue != nil, let s = n.stateGoingIn, s.usable, let date = TrendsDayKey.date(n.day) else { continue }
            out.append(ProgressPoint(id: n.day, date: date, baseline: s.baseline, sigma: Baselines.sigma(s),
                                     nValid: s.nValid, trusted: s.trusted))
        }
        return out
    }
}

// MARK: - Noise floor

/// How far two baselines can sit apart by chance alone. An EWMA of iid nights with smoothing λ has
/// variance λ/(2−λ)·σ²; two baselines 90 or more nights apart are ~independent (0.5^(90/14) ≈ 1%), so
/// their difference has variance 2λ/(2−λ)·σ², and two of those standard deviations is the floor. At the
/// floor spread this is 2.79 ms for HRV and 1.12 bpm for resting HR; larger for a noisier person.
enum ProgressNoise {
    /// 2·sqrt(2λ/(2−λ)), λ = 1 − 0.5^(1/halfLifeB). 0.4450 for a 14-night half-life.
    static func factor(cfg: MetricCfg) -> Double {
        let lambda = 1.0 - pow(0.5, 1.0 / cfg.halfLifeB)
        return 2.0 * sqrt(2.0 * lambda / (2.0 - lambda))
    }

    static func floor(cfg: MetricCfg, sigmaThen: Double, sigmaNow: Double) -> Double {
        factor(cfg: cfg) * max(sigmaThen, sigmaNow)
    }
}

// MARK: - Comparison

/// Two trusted points on the trajectory and the noise floor that decides "steady".
struct ProgressComparison: Equatable {
    let then: ProgressPoint
    let now: ProgressPoint
    let noise: Double
    /// The anchor is more than 14 days older than the cutoff (strap off around it), so the sentence names
    /// the date instead of "90 days ago". Always true for `.all`.
    let namesDate: Bool

    var delta: Double { now.baseline - then.baseline }

    /// |delta| < noise, or |delta| rounds to 0.
    var steady: Bool { abs(delta) < noise || Int(abs(delta).rounded()) == 0 }

    /// `trusted` = trajectory points with `trusted == true`. nil when there is no anchor at the horizon's
    /// far end (or no trusted point at all).
    static func resolve(trusted: [ProgressPoint], todayKey: String, horizon: ProgressHorizon,
                        cfg: MetricCfg) -> ProgressComparison? {
        guard let now = trusted.last else { return nil }
        let then: ProgressPoint
        let namesDate: Bool
        if let cutoff = horizon.cutoff(todayKey: todayKey) {
            guard let anchor = trusted.last(where: { $0.day <= cutoff }) else { return nil }
            then = anchor
            namesDate = anchor.day < Baselines.cutoffKey(todayKey: cutoff, carryDays: Baselines.staleDays)
        } else {
            guard let first = trusted.first, first.id != now.id else { return nil }
            then = first
            namesDate = true
        }
        let noise = ProgressNoise.floor(cfg: cfg, sigmaThen: then.sigma, sigmaNow: now.sigma)
        return ProgressComparison(then: then, now: now, noise: noise, namesDate: namesDate)
    }
}

// MARK: - Metric status

enum ProgressMetricStatus: Equatable {
    case empty
    /// `nights` is the engine's own count, `nValid` of the state folded over every night so far (14 on
    /// the morning the baseline settles; the first trusted point lands the night after).
    case calibrating(nights: Int)
    /// Trusted, but no anchor at the horizon's far end yet. `compareFromDay` is the day the comparison
    /// arrives (nil for `.all`).
    case settling(firstTrustedDay: String, compareFromDay: String?, points: [ProgressPoint])
    /// The newest valid night is more than `Baselines.staleDays` old.
    case paused(lastDay: String, points: [ProgressPoint])
    /// `asOfDay` names the "now" point when it is older than `Baselines.vitalCarryDays` (Today's carry
    /// rule), e.g. the last trusted night before a gap the engine marked stale.
    case ready(comparison: ProgressComparison, points: [ProgressPoint], asOfDay: String?)

    /// Trusted points, for the chart. Empty while calibrating or empty.
    var points: [ProgressPoint] {
        switch self {
        case .empty, .calibrating: return []
        case .settling(_, _, let p), .paused(_, let p), .ready(_, let p, _): return p
        }
    }

    var comparison: ProgressComparison? {
        if case .ready(let c, _, _) = self { return c }
        return nil
    }
}

enum ProgressMetric {
    /// The status ladder, in order: empty → paused → calibrating → settling → ready. `points` handed to
    /// the chart are trusted only: provisional points are never drawn or compared, since the early-adapt
    /// 3-night half-life would read as "progress".
    static func build(upToToday: [DailyMetric], cfg: MetricCfg, todayKey: String, horizon: ProgressHorizon,
                      value: (DailyMetric) -> Double?) -> ProgressMetricStatus {
        let walk = BaselineReadouts.nightlyStates(upToToday: upToToday, cfg: cfg, value: value)
        guard let newestValidDay = walk.last(where: { $0.validValue != nil })?.day else { return .empty }
        let trusted = ProgressTrajectory.build(walk: walk).filter(\.trusted)

        // Key arithmetic, not row counting: `repo.days` has no rows for off-strap days.
        if newestValidDay < Baselines.cutoffKey(todayKey: todayKey, carryDays: Baselines.staleDays) {
            return .paused(lastDay: newestValidDay, points: trusted)
        }
        guard let first = trusted.first else {
            // The state folded over every night so far: the last night's going-in state stepped once
            // more by that night, exactly the engine's walk (`validValue` is nil for the nights the
            // engine skips, and an in-range night it rejects as an outlier leaves nValid unchanged).
            // Its nValid is the count the Today hero and the Trends "Baseline" cell print.
            let folded = walk.last.map { Baselines.update($0.stateGoingIn, value: $0.validValue, cfg: cfg) }
            return .calibrating(nights: folded?.nValid ?? 0)
        }
        guard let comparison = ProgressComparison.resolve(trusted: trusted, todayKey: todayKey,
                                                          horizon: horizon, cfg: cfg) else {
            // Negative carryDays adds days: the day the first trusted night is `horizon` days old.
            let compareFrom = horizon.days.map { Baselines.cutoffKey(todayKey: first.day, carryDays: -$0) }
            return .settling(firstTrustedDay: first.day, compareFromDay: compareFrom, points: trusted)
        }
        let now = comparison.now
        let asOf = now.day < Baselines.cutoffKey(todayKey: todayKey, carryDays: Baselines.vitalCarryDays) ? now.day : nil
        return .ready(comparison: comparison, points: trusted, asOfDay: asOf)
    }

    /// The points the chart draws: from the horizon's cutoff (or the anchor, whichever is earlier) to now;
    /// every trusted point when that leaves fewer than two, and always for `.all`.
    static func window(_ status: ProgressMetricStatus, todayKey: String, horizon: ProgressHorizon) -> [ProgressPoint] {
        let points = status.points
        guard let cutoff = horizon.cutoff(todayKey: todayKey) else { return points }
        let start = min(cutoff, status.comparison?.then.day ?? cutoff)
        let windowed = points.filter { $0.day >= start }
        return windowed.count >= 2 ? windowed : points
    }

    /// Y-axis span over the window's baseline ± sigma, padded and snapped by the Trends rule.
    static func yDomain(window: [ProgressPoint], step: Double) -> ClosedRange<Double> {
        let band = window.map {
            BandPoint(id: $0.id, date: $0.date, value: $0.baseline, baseline: nil,
                      low: $0.baseline - $0.sigma, high: $0.baseline + $0.sigma)
        }
        return TrendsSeries.yDomain(points: band, step: step)
    }

    /// True when the window spans more than a year, so x labels carry the year.
    static func spansOverAYear(_ window: [ProgressPoint]) -> Bool {
        guard let first = window.first, let last = window.last else { return false }
        return last.date.timeIntervalSince(first.date) > 365 * 86_400
    }
}

// MARK: - Sleep

/// How much and how regularly, over the latest 30 nights against the same window at the horizon's far
/// end. The "now" average is `BaselineReadouts.sleepAverage30` by construction (same 30 nights, same
/// ≥ 3 gate), so Today, Sleep and Progress print one number.
enum ProgressSleep {
    static let windowNights = 30
    /// A settled window: both sides need this many nights before the averages are compared.
    static let comparisonMinNights = Baselines.minNightsTrust
    /// `.all` compares the first 30 nights with the latest 30, so it needs this many in total.
    static let allTimeMinNights = 60
    /// Minutes below which a duration change is never called a change.
    static let durationFloorMin = 5.0
    /// Timed nights the averages need (the readout's own floor), and the change in the regularity index,
    /// in points, below which timing is "about as regular" (a 14-night index moves about that much when
    /// a single night lands an hour off).
    static let timingMinNights = BaselineReadouts.sleepAverageMinNights
    static let timingSteadyPoints = 5

    struct Window: Equatable {
        let avgMin: Double
        /// Population standard deviation of the nightly minutes.
        let sdMin: Double
        let nights: Int
        let newestDay: String
        let oldestDay: String
    }

    enum Duration: Equatable {
        case none
        /// Fewer than `BaselineReadouts.sleepAverageMinNights`.
        case building(nights: Int)
        /// `nights` is every night on or before today; the average covers the newest 30 of them.
        case nowOnly(nowAvgMin: Double, nights: Int, compareFromDay: String?)
        case ready(now: Window, then: Window, deltaMin: Double, noiseMin: Double)
    }

    /// One window's average bedtime and wake (circular means, minutes after local midnight) and its
    /// regularity index, lifted off `BaselineReadouts.sleepTiming(for:nights:)`: the same readout the
    /// Sleep tab's timing card prints, so Progress and Sleep never disagree on an average bedtime.
    struct Timing: Equatable {
        let bedMeanMin: Double
        let wakeMeanMin: Double
        /// 0–100 over the window's newest 14 nights; nil under 5 consecutive-night pairs.
        let regularity: Int?
        /// Timed nights the averages cover (at most 30) and the days they span.
        let nights: Int
        let newestDay: String
        let oldestDay: String
    }

    enum Regularity: Equatable {
        /// Every night is `.dailyMetric` (imported totals only).
        case noTimedNights
        /// Fewer than `timingMinNights` timed nights.
        case building(timed: Int)
        case nowOnly(now: Timing, compareFromDay: String?)
        /// `delta` = now.regularity − then.regularity (positive = more regular); nil when either window
        /// is short of the index, in which case the sentence states the bedtimes alone.
        case ready(now: Timing, then: Timing, delta: Int?)
    }

    struct Reading: Equatable {
        let duration: Duration
        let regularity: Regularity
    }

    /// `nights` is `SleepNightBuilder.nights(…)`, newest first. `calendar` places bed and wake on the
    /// clock (the device's; tests pass their own).
    static func reading(nights: [SleepNight], todayKey: String, horizon: ProgressHorizon,
                        calendar: Calendar = .current) -> Reading {
        let scoped = nights.filter { $0.dayKey <= todayKey }
        let cutoff = horizon.cutoff(todayKey: todayKey)
        return Reading(duration: duration(scoped, cutoff: cutoff, horizon: horizon),
                       regularity: regularity(scoped, todayKey: todayKey, cutoff: cutoff, horizon: horizon,
                                              calendar: calendar))
    }

    // MARK: Duration

    private static func duration(_ scoped: [SleepNight], cutoff: String?, horizon: ProgressHorizon) -> Duration {
        guard !scoped.isEmpty else { return .none }
        guard let now = window(scoped.prefix(windowNights)) else { return .building(nights: scoped.count) }
        let then: Window?
        if let cutoff {
            then = window(scoped.filter { $0.dayKey <= cutoff }.prefix(windowNights))
        } else {
            then = window(scoped.suffix(windowNights))
        }
        if let then, now.nights >= comparisonMinNights, then.nights >= comparisonMinNights,
           then.newestDay < now.oldestDay {
            let delta = now.avgMin - then.avgMin
            let se = 2 * sqrt(then.sdMin * then.sdMin / Double(then.nights) + now.sdMin * now.sdMin / Double(now.nights))
            return .ready(now: now, then: then, deltaMin: delta, noiseMin: max(durationFloorMin, se))
        }
        var compareFrom: String? = nil
        if let days = horizon.days, scoped.count >= comparisonMinNights {
            compareFrom = Baselines.cutoffKey(todayKey: scoped[comparisonMinNights - 1].dayKey, carryDays: -days)
        }
        return .nowOnly(nowAvgMin: now.avgMin, nights: scoped.count, compareFromDay: compareFrom)
    }

    /// Mean and population SD of minutes asleep; nil below `BaselineReadouts.sleepAverageMinNights`.
    static func window(_ nights: ArraySlice<SleepNight>) -> Window? {
        guard nights.count >= BaselineReadouts.sleepAverageMinNights,
              let newest = nights.first, let oldest = nights.last else { return nil }
        let n = Double(nights.count)
        let mean = nights.reduce(0) { $0 + $1.asleepMin } / n
        let variance = nights.reduce(0) { $0 + ($1.asleepMin - mean) * ($1.asleepMin - mean) } / n
        return Window(avgMin: mean, sdMin: sqrt(variance), nights: nights.count,
                      newestDay: newest.dayKey, oldestDay: oldest.dayKey)
    }

    // MARK: Timing

    /// A night the readout can place on the clock: strap-recorded, with a bed and a later wake.
    private static func timed(_ night: SleepNight) -> Bool {
        guard night.source == .session, let onset = night.onsetTs, let wake = night.wakeTs else { return false }
        return wake > onset
    }

    private static func regularity(_ scoped: [SleepNight], todayKey: String, cutoff: String?,
                                   horizon: ProgressHorizon, calendar: Calendar) -> Regularity {
        let timedAll = scoped.filter(timed)
        guard !timedAll.isEmpty else { return .noTimedNights }
        guard let now = timing(timedAll, for: todayKey, calendar: calendar) else {
            return .building(timed: timedAll.count)
        }
        // The far end: the newest 30 timed nights on or before the cutoff; for `.all`, the first 30.
        let thenDay = cutoff ?? timedAll.suffix(windowNights).first?.dayKey
        if let thenDay, let then = timing(timedAll, for: thenDay, calendar: calendar), then.newestDay < now.oldestDay {
            var delta: Int? = nil
            if let a = now.regularity, let b = then.regularity { delta = a - b }
            return .ready(now: now, then: then, delta: delta)
        }
        var compareFrom: String? = nil
        if let days = horizon.days, timedAll.count >= timingMinNights {
            compareFrom = Baselines.cutoffKey(todayKey: timedAll[timingMinNights - 1].dayKey, carryDays: -days)
        }
        return .nowOnly(now: now, compareFromDay: compareFrom)
    }

    /// The readout's window ending on `day` (its newest 30 timed nights on or before it), nil below
    /// `timingMinNights`. The target window plays no part here, so the default one is passed and the
    /// call stays pure (no UserDefaults).
    static func timing(_ nights: [SleepNight], for day: String, calendar: Calendar = .current) -> Timing? {
        let t = BaselineReadouts.sleepTiming(for: day, nights: nights, window: .default, calendar: calendar)
        guard let bed = t.averageBedMinutes, let wake = t.averageWakeMinutes,
              let newest = t.nights.first, let oldest = t.nights.last else { return nil }
        return Timing(bedMeanMin: bed, wakeMeanMin: wake, regularity: t.regularity,
                      nights: t.nights.count, newestDay: newest.day, oldestDay: oldest.day)
    }
}

// MARK: - Fitness (estimated VO2 max, fitness age)

/// The profile fields the fitness estimate needs, lifted off `ProfileStore` by the screen so the model
/// stays pure. `.none` is the no-profile case (tests, previews).
struct ProgressProfile: Equatable {
    var age: Int? = nil
    var sex: String? = nil
    var waistCm: Double? = nil
    var hasHeightWeight = false

    static let none = ProgressProfile()

    /// The one resolver from the fields `ProfileStore` carries to what the model takes, used by both
    /// fitness consumers (`ProgressSection` and `BaselineReadouts.fitness(_:profile:for:)`). `entered`
    /// is `BaselineReadouts.ProfileSet`, the flag Settings › Profile writes: NOOP's store seeds age 30
    /// and "male" when nothing was ever set, so until the person has entered them the pair is nil and
    /// `ProgressFitness.build` lands on `.needsProfile` rather than scoring a 30-year-old man. A waist
    /// of 0 is "none"; height and weight only shade the estimate's confidence, never a number, so their
    /// engine defaults pass through.
    static func lifted(age: Int, sex: String, waistCm: Double, heightCm: Double, weightKg: Double,
                       entered: Bool) -> ProgressProfile {
        ProgressProfile(age: entered ? age : nil, sex: entered ? sex : nil,
                        waistCm: waistCm > 0 ? waistCm : nil,
                        hasHeightWeight: heightCm > 0 && weightKg > 0)
    }

    /// `lifted(age:sex:waistCm:heightCm:weightKg:entered:)` over the live store.
    @MainActor
    static func lifted(from store: ProfileStore, entered: Bool) -> ProgressProfile {
        lifted(age: store.age, sex: store.sex, waistCm: store.waistCm, heightCm: store.heightCm,
               weightKg: store.weightKg, entered: entered)
    }
}

/// Is the estimated VO2 max moving over months? NOOP's weekly fitness read (`FitnessAgeEngine`, Nes
/// 2011, via `BaselineReadouts.fitness(for:days:…)`) for every week ending on today's weekday, back to
/// the first row, then the same ladder as the HRV card: an anchor at the horizon's far end and a
/// "steady" floor. Low accuracy (`MetricAccuracy` "vo2": resting-based estimates overestimate, typical
/// error 4–5 mL/kg/min), so the card draws a band and names a direction, never a target.
enum ProgressFitness {
    /// The drawn band (± around each point) and the y-axis snap: about the model's standard error.
    static let bandVO2 = 5.0
    static let yStep = 5.0
    /// Changes under this many mL/kg/min are "about where it was": roughly two standard errors of a
    /// seven-night resting HR median carried through the model (about 1 mL/kg/min per bpm at typical
    /// values), well inside the model's own error.
    static let steadyVO2 = 3.0

    /// One week's estimate, stamped on the week's last day.
    struct Point: Identifiable, Equatable {
        let id: String
        let date: Date
        let vo2max: Double
        let fitnessAge: Double
        let chronoAge: Double
        /// Nights of resting HR in the week (4…7).
        let rhrNights: Int
        /// True when VO2 max came from the waist-free fallback (resting HR and age alone).
        let fallback: Bool

        var weekEnding: String { id }

        /// The point as the trajectory chart draws it: the estimate with its ± band.
        var trajectory: ProgressPoint {
            ProgressPoint(id: id, date: date, baseline: vo2max, sigma: ProgressFitness.bandVO2,
                          nValid: rhrNights, trusted: true)
        }
    }

    struct Comparison: Equatable {
        let then: Point
        let now: Point
        /// The anchor is more than 14 days older than the cutoff, so the sentence names its date.
        let namesDate: Bool

        var delta: Double { now.vo2max - then.vo2max }
        var steady: Bool { abs(delta) < ProgressFitness.steadyVO2 || Int(abs(delta).rounded()) == 0 }
    }

    enum Status: Equatable {
        /// No night with a resting HR anywhere: the card is not drawn.
        case empty
        /// Resting HR exists but no age or sex: the person has not entered them in Settings › Profile
        /// yet (`BaselineReadouts.ProfileSet` is false, so `ProgressProfile.lifted` passed nil for the
        /// store's seeded 30 / "male"). The card's sentence asks for them.
        case needsProfile
        /// No week with `FitnessAgeEngine.minCoverageDays` nights of resting HR yet; `rhrNights` is
        /// this week's count.
        case calibrating(rhrNights: Int)
        /// The newest estimate is more than `Baselines.staleDays` old.
        case paused(lastWeek: String, points: [Point])
        /// Estimates exist, but none at the horizon's far end yet.
        case settling(firstWeek: String, compareFromDay: String?, points: [Point])
        case ready(comparison: Comparison, points: [Point])

        var points: [Point] {
            switch self {
            case .empty, .needsProfile, .calibrating: return []
            case .paused(_, let p), .settling(_, _, let p), .ready(_, let p): return p
            }
        }

        /// The newest estimate (the "now" cell and the fitness-age caption).
        var now: Point? { points.last }

        var comparison: Comparison? {
            if case .ready(let c, _) = self { return c }
            return nil
        }
    }

    /// `days` is `repo.baselineDays` (oldest → newest).
    static func build(days: [DailyMetric], todayKey: String, horizon: ProgressHorizon, profile: ProgressProfile) -> Status {
        let upToToday = days.filter { $0.day <= todayKey }
        guard upToToday.contains(where: { $0.restingHr != nil }) else { return .empty }
        guard (profile.age ?? 0) > 0, !(profile.sex ?? "").isEmpty else { return .needsProfile }
        let byDay = index(upToToday)
        let pts = points(byDay: byDay, todayKey: todayKey, profile: profile)
        guard let newest = pts.last else {
            return .calibrating(rhrNights: week(ending: todayKey, byDay: byDay).compactMap(\.restingHr).count)
        }
        if newest.weekEnding < Baselines.cutoffKey(todayKey: todayKey, carryDays: Baselines.staleDays) {
            return .paused(lastWeek: newest.weekEnding, points: pts)
        }
        var then: Point? = nil
        var namesDate = false
        if let cutoff = horizon.cutoff(todayKey: todayKey) {
            then = pts.last(where: { $0.weekEnding <= cutoff })
            if let anchor = then {
                namesDate = anchor.weekEnding < Baselines.cutoffKey(todayKey: cutoff, carryDays: Baselines.staleDays)
            }
        } else if let first = pts.first, first.id != newest.id {
            then = first
            namesDate = true
        }
        guard let then else {
            // Negative carryDays adds days: the day the first estimate is `horizon` days old.
            let compareFrom = horizon.days.map { Baselines.cutoffKey(todayKey: pts[0].weekEnding, carryDays: -$0) }
            return .settling(firstWeek: pts[0].weekEnding, compareFromDay: compareFrom, points: pts)
        }
        return .ready(comparison: Comparison(then: then, now: newest, namesDate: namesDate), points: pts)
    }

    /// Weekly estimates, oldest → newest, for the weeks ending on `todayKey` and every seven days before
    /// it, down to the first row. A week without an estimate (under four nights of resting HR) emits
    /// nothing, so a gap is a straight segment, as on the HRV card.
    static func points(days: [DailyMetric], todayKey: String, profile: ProgressProfile) -> [Point] {
        points(byDay: index(days.filter { $0.day <= todayKey }), todayKey: todayKey, profile: profile)
    }

    private static func points(byDay: [String: DailyMetric], todayKey: String, profile: ProgressProfile) -> [Point] {
        guard let earliest = byDay.keys.min(), let age = profile.age, let sex = profile.sex else { return [] }
        var out: [Point] = []
        var weekEnd = todayKey
        while weekEnd >= earliest {
            let rows = week(ending: weekEnd, byDay: byDay)
            if let r = BaselineReadouts.fitness(for: weekEnd, days: rows, age: age, sex: sex, waistCm: profile.waistCm,
                                                hasHeightWeight: profile.hasHeightWeight),
               let vo2 = r.vo2max, let date = TrendsDayKey.date(weekEnd) {
                out.append(Point(id: weekEnd, date: date, vo2max: vo2, fitnessAge: r.result.fitnessAge,
                                 chronoAge: r.result.chronoAge, rhrNights: r.rhrNights, fallback: r.vo2IsFallback))
            }
            weekEnd = Baselines.cutoffKey(todayKey: weekEnd, carryDays: 7)
        }
        return out.reversed()
    }

    private static func index(_ days: [DailyMetric]) -> [String: DailyMetric] {
        Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// The seven calendar days ending on `weekEnd`, oldest → newest (rows that exist).
    private static func week(ending weekEnd: String, byDay: [String: DailyMetric]) -> [DailyMetric] {
        (0..<7).compactMap { byDay[Baselines.cutoffKey(todayKey: weekEnd, carryDays: $0)] }.sorted { $0.day < $1.day }
    }

    /// The points the chart draws: from the horizon's cutoff (or the anchor, whichever is earlier) to
    /// now; every point when that leaves fewer than two, and always for `.all`.
    static func window(_ status: Status, todayKey: String, horizon: ProgressHorizon) -> [Point] {
        let points = status.points
        guard let cutoff = horizon.cutoff(todayKey: todayKey) else { return points }
        let start = min(cutoff, status.comparison?.then.weekEnding ?? cutoff)
        let windowed = points.filter { $0.weekEnding >= start }
        return windowed.count >= 2 ? windowed : points
    }
}

// MARK: - Snapshot

struct ProgressSnapshot {
    let horizon: ProgressHorizon
    let todayKey: String
    let hrv: ProgressMetricStatus
    let restingHr: ProgressMetricStatus
    let sleep: ProgressSleep.Reading
    let fitness: ProgressFitness.Status
    /// Nights anywhere with HRV, resting HR or sleep (Trends' gate); 0 → empty-store state.
    let totalNights: Int
    /// The recalibration day when it dropped at least one night, for the closing caption.
    let recalibratedOn: String?

    /// Whether the horizon changes anything on screen: a metric that has settled (settling, paused or
    /// ready) or a sleep reading that compares, or will compare, two windows. While every card is still
    /// calibrating or building, the picker would switch between four identical screens, so it is hidden
    /// and the HRV card leads.
    var hasHorizonContent: Bool {
        for status in [hrv, restingHr] {
            switch status {
            case .settling, .paused, .ready: return true
            case .empty, .calibrating: break
            }
        }
        switch sleep.duration {
        case .nowOnly, .ready: return true
        case .none, .building: break
        }
        switch sleep.regularity {
        case .nowOnly, .ready: return true
        case .noTimedNights, .building: break
        }
        switch fitness {
        case .settling, .paused, .ready: return true
        case .empty, .needsProfile, .calibrating: return false
        }
    }

    /// `days` is `repo.baselineDays` (oldest → newest); `nights` is `SleepNightBuilder.nights(…)` (newest
    /// first); `profile` is the age, sex and body fields off `ProfileStore` (`.none` without one).
    static func build(days: [DailyMetric], nights: [SleepNight], horizon: ProgressHorizon, todayKey: String,
                      profile: ProgressProfile = .none) -> ProgressSnapshot {
        let upToToday = days.filter { $0.day <= todayKey }
        let totalNights = upToToday.reduce(into: 0) { acc, d in
            if d.avgHrv != nil || d.restingHr != nil || d.totalSleepMin != nil { acc += 1 }
        }
        let diagnostic = Baselines.epochDropDiagnostic(dayKeys: upToToday.map(\.day))
        return ProgressSnapshot(
            horizon: horizon,
            todayKey: todayKey,
            hrv: ProgressMetric.build(upToToday: upToToday, cfg: Baselines.hrvCfg, todayKey: todayKey,
                                      horizon: horizon) { $0.avgHrv },
            restingHr: ProgressMetric.build(upToToday: upToToday, cfg: Baselines.restingHRCfg, todayKey: todayKey,
                                            horizon: horizon) { $0.restingHr.map(Double.init) },
            sleep: ProgressSleep.reading(nights: nights, todayKey: todayKey, horizon: horizon),
            fitness: ProgressFitness.build(days: upToToday, todayKey: todayKey, horizon: horizon, profile: profile),
            totalNights: totalNights,
            recalibratedOn: diagnostic.dropped > 0 ? diagnostic.epochDay : nil)
    }

    /// The HRV sentence for the Today row: the identical string the Progress HRV card prints (same
    /// resolver, same persisted horizon). nil for `.empty` and `.calibrating`, so Today never grows a
    /// permanent calibrating line (the HRV tile and readiness pill already carry their counts).
    static func hrvHeadline(days: [DailyMetric], horizon: ProgressHorizon, todayKey: String) -> String? {
        let upToToday = days.filter { $0.day <= todayKey }
        let status = ProgressMetric.build(upToToday: upToToday, cfg: Baselines.hrvCfg, todayKey: todayKey,
                                          horizon: horizon) { $0.avgHrv }
        switch status {
        case .empty, .calibrating: return nil
        case .settling, .paused, .ready:
            return ProgressCopy.sentence(noun: "HRV", unit: "ms", status: status, horizon: horizon)
        }
    }
}

// MARK: - Copy

/// Every sentence Progress prints. Deltas are spoken as higher / lower, more / less; no signed values,
/// so no typographic minus appears in a sentence.
enum ProgressCopy {
    enum Tone { case improving, worsening, steady, none }

    /// "Mar 3" for a day key (the key itself if it does not parse).
    static func date(_ key: String) -> String {
        guard let d = TrendsDayKey.date(key) else { return key }
        return TrendsFormat.shortDate(d)
    }

    /// "90 days ago" / "on Mar 3" / "when it settled on Mar 3".
    private static func ago(_ c: ProgressComparison, horizon: ProgressHorizon) -> String {
        ago(thenDay: c.then.day, namesDate: c.namesDate, horizon: horizon)
    }

    private static func ago(thenDay: String, namesDate: Bool, horizon: ProgressHorizon) -> String {
        if let phrase = horizon.agoPhrase, !namesDate { return phrase }
        if horizon == .all { return "when it settled on \(date(thenDay))" }
        return "on \(date(thenDay))"
    }

    // MARK: Metric

    static func sentence(noun: String, unit: String, status: ProgressMetricStatus, horizon: ProgressHorizon) -> String {
        switch status {
        case .empty:
            return "No nights with \(noun) yet."
        case .calibrating(let n):
            return "Your \(noun) baseline settles after \(Baselines.minNightsTrust) nights; Progress starts the night after · \(n) so far."
        case .settling(let firstDay, let compareFrom, _):
            if let compareFrom, let phrase = horizon.agoPhrase {
                return "Your \(noun) baseline settled on \(date(firstDay)). Compare it with \(phrase) from \(date(compareFrom))."
            }
            return "Your \(noun) baseline settled on \(date(firstDay)). Keep wearing the strap and this line grows."
        case .paused(let lastDay, _):
            return "No \(noun) since \(date(lastDay)). Progress resumes with the next synced night."
        case .ready(let c, _, _):
            if c.steady {
                return "Your \(noun) baseline is about where it was \(ago(c, horizon: horizon))."
            }
            let n = Int(abs(c.delta).rounded())
            let direction = c.delta > 0 ? "higher" : "lower"
            return "Your \(noun) baseline is \(n) \(unit) \(direction) than \(ago(c, horizon: horizon))."
        }
    }

    /// The dot beside the sentence: `TodayRingTile.tone`'s rule with `higherIsBetter` (HRV up / resting
    /// HR down = improving). The sentence text itself is never coloured.
    static func tone(status: ProgressMetricStatus, higherIsBetter: Bool) -> Tone {
        guard case .ready(let c, _, _) = status else { return .none }
        if c.steady { return .steady }
        let up = c.delta > 0
        return up == higherIsBetter ? .improving : .worsening
    }

    static func footnote(unit: String, status: ProgressMetricStatus) -> String? {
        switch status {
        case .ready(let c, _, _):
            // What the line IS is said once, in the screen's closing caption.
            let n = Int(c.noise.rounded(.up))
            return "Changes under about \(n) \(unit) are within the baseline's own noise."
        case .settling, .paused:
            return "Only the settled part of your baseline is drawn (\(Baselines.minNightsTrust) nights or more)."
        case .calibrating, .empty:
            return nil
        }
    }

    static func thenLabel(_ c: ProgressComparison) -> String { "Then · \(date(c.then.day))" }

    static func nowLabel(_ c: ProgressComparison, asOfDay: String?) -> String {
        if let asOfDay { return "Now · as of \(date(asOfDay))" }
        return "Now · \(date(c.now.day))"
    }

    /// For `.settling` / `.paused`: the last trusted point.
    static func nowLabel(day: String) -> String { "Now · \(date(day))" }

    // MARK: Sleep duration

    /// "90 days ago" / "your first month".
    private static func sleepAgo(_ horizon: ProgressHorizon) -> String { horizon.agoPhrase ?? "your first month" }

    static func sleepSentence(_ d: ProgressSleep.Duration, horizon: ProgressHorizon) -> String {
        switch d {
        case .none:
            return "No nights of sleep yet."
        case .building(let n):
            return "Your sleep average appears after \(BaselineReadouts.sleepAverageMinNights) nights · \(n) so far."
        case .nowOnly(let avg, let nights, let compareFrom):
            let shown = min(nights, ProgressSleep.windowNights)
            let lead = "You're averaging \(BaselineReadouts.durationText(minutes: avg)) asleep over the last \(shown) nights."
            if let compareFrom, let phrase = horizon.agoPhrase {
                return "\(lead) Compare it with \(phrase) from \(date(compareFrom))."
            }
            if horizon == .all {
                return "\(lead) Comparisons with your first month start after \(ProgressSleep.allTimeMinNights) nights · \(nights) so far."
            }
            return "\(lead) Comparisons start after \(ProgressSleep.comparisonMinNights) nights."
        case .ready(let now, _, let delta, let noise):
            let lead = "You're averaging \(BaselineReadouts.durationText(minutes: now.avgMin)) asleep,"
            if abs(delta) < noise {
                return "\(lead) about the same as \(sleepAgo(horizon))."
            }
            return "\(lead) \(BaselineReadouts.durationText(minutes: abs(delta))) \(delta > 0 ? "more" : "less") than \(sleepAgo(horizon))."
        }
    }

    static func sleepTone(_ d: ProgressSleep.Duration) -> Tone {
        guard case .ready(_, _, let delta, let noise) = d else { return .none }
        if abs(delta) < noise { return .steady }
        return delta > 0 ? .improving : .worsening
    }

    /// "Then · 30 nights to Jul 2" / "Now · last 30 nights".
    static func sleepThenLabel(_ w: ProgressSleep.Window) -> String { "Then · \(w.nights) nights to \(date(w.newestDay))" }
    static func sleepNowLabel(nights: Int) -> String { "Now · last \(min(nights, ProgressSleep.windowNights)) nights" }

    static func sleepFootnote(_ d: ProgressSleep.Duration) -> String? {
        guard case .ready(_, _, _, let noise) = d else { return nil }
        return "30-night averages, the same one Today and Sleep show. Changes under about \(Int(noise.rounded(.up))) min are within the average's own noise."
    }

    // MARK: Sleep timing

    /// "11:24 PM" for minutes after local midnight: the readout's own clock text, so the Sleep tab and
    /// Progress print one bedtime the same way.
    static func clock(minutes: Double) -> String { BaselineReadouts.clockText(minutes: minutes) }

    /// "Your bedtime averages 11:24 PM and your timing scores 83 of 100 for regularity." The index is
    /// named only when the window has it.
    private static func timingLead(_ t: ProgressSleep.Timing) -> String {
        if let r = t.regularity {
            return "Your bedtime averages \(clock(minutes: t.bedMeanMin)) and your timing scores \(r) of 100 for regularity."
        }
        return "Your bedtime averages \(clock(minutes: t.bedMeanMin)); regularity scores after \(BaselineReadouts.regularityMinPairs + 1) strap nights in a row."
    }

    static func timingSentence(_ r: ProgressSleep.Regularity, horizon: ProgressHorizon) -> String {
        switch r {
        case .noTimedNights:
            return "Bed and wake times come from nights the strap recorded. Imported nights carry totals only."
        case .building(let n):
            return "Bed and wake times settle after \(ProgressSleep.timingMinNights) strap nights · \(n) so far."
        case .nowOnly(let now, let compareFrom):
            let lead = timingLead(now)
            if let compareFrom, let phrase = horizon.agoPhrase {
                return "\(lead) Compare it with \(phrase) from \(date(compareFrom))."
            }
            if horizon == .all {
                return "\(lead) Keep wearing the strap and the comparison arrives."
            }
            return "\(lead) Comparisons start after \(ProgressSleep.timingMinNights) more strap nights."
        case .ready(let now, let then, let delta):
            guard let delta, let score = now.regularity else {
                return "Your bedtime averages \(clock(minutes: now.bedMeanMin)); it was \(clock(minutes: then.bedMeanMin)) \(sleepAgo(horizon))."
            }
            if delta >= ProgressSleep.timingSteadyPoints {
                return "Your sleep timing is more regular than \(sleepAgo(horizon)): \(score) of 100, up from \(score - delta)."
            }
            if delta <= -ProgressSleep.timingSteadyPoints {
                return "Your sleep timing is less regular than \(sleepAgo(horizon)): \(score) of 100, down from \(score - delta)."
            }
            return "Your sleep timing is about as regular as \(sleepAgo(horizon)): \(score) of 100."
        }
    }

    static func timingTone(_ r: ProgressSleep.Regularity) -> Tone {
        guard case .ready(_, _, let delta) = r, let delta else { return .none }
        if delta >= ProgressSleep.timingSteadyPoints { return .improving }
        if delta <= -ProgressSleep.timingSteadyPoints { return .worsening }
        return .steady
    }

    /// One row of the timing grid: the label, the clock or index now, the earlier window's figure under
    /// it when there is a comparison, and the spoken form.
    struct TimingRow: Identifiable, Equatable {
        let label: String
        let value: String
        let was: String?
        var id: String { label }

        /// "Bedtime usually 11:24 PM; was 11:51 PM." / "Regularity 83 of 100; was 71."
        var spoken: String {
            let verb = label == "Regularity" ? "" : " usually"
            if let was { return "\(label)\(verb) \(value); \(was)." }
            return "\(label)\(verb) \(value)."
        }
    }

    /// Bedtime and wake, each with the earlier window's clock when there is one, then the regularity
    /// index once the window has it. Empty while timing is building or untimed.
    static func timingRows(_ r: ProgressSleep.Regularity) -> [TimingRow] {
        let now: ProgressSleep.Timing
        let then: ProgressSleep.Timing?
        switch r {
        case .ready(let n, let t, _): now = n; then = t
        case .nowOnly(let n, _): now = n; then = nil
        case .building, .noTimedNights: return []
        }
        var rows = [
            TimingRow(label: "Bedtime", value: clock(minutes: now.bedMeanMin),
                      was: then.map { "was \(clock(minutes: $0.bedMeanMin))" }),
            TimingRow(label: "Wake", value: clock(minutes: now.wakeMeanMin),
                      was: then.map { "was \(clock(minutes: $0.wakeMeanMin))" }),
        ]
        if let score = now.regularity {
            rows.append(TimingRow(label: "Regularity", value: "\(score) of 100",
                                  was: then?.regularity.map { "was \($0)" }))
        }
        return rows
    }

    // MARK: Fitness

    static let vo2Unit = "mL/kg/min"

    /// nil for `.empty` (no card).
    static func fitnessSentence(_ s: ProgressFitness.Status, horizon: ProgressHorizon) -> String? {
        switch s {
        case .empty:
            return nil
        case .needsProfile:
            return "Add your date of birth and sex in Settings › Profile for an estimated VO2 max and fitness age."
        case .calibrating(let n):
            return "Your fitness estimate needs \(FitnessAgeEngine.minCoverageDays) nights of resting HR in a week · \(n) this week."
        case .settling(let firstWeek, let compareFrom, _):
            if let compareFrom, let phrase = horizon.agoPhrase {
                return "Your first fitness estimate landed the week to \(date(firstWeek)). Compare it with \(phrase) from \(date(compareFrom))."
            }
            return "Your first fitness estimate landed the week to \(date(firstWeek)). Keep wearing the strap and this line grows."
        case .paused(let lastWeek, _):
            return "No fitness estimate since the week to \(date(lastWeek)). It resumes with \(FitnessAgeEngine.minCoverageDays) nights of resting HR in a week."
        case .ready(let c, _):
            let when = ago(thenDay: c.then.weekEnding, namesDate: c.namesDate, horizon: horizon)
            if c.steady {
                return "Your estimated VO2 max is about where it was \(when)."
            }
            let n = Int(abs(c.delta).rounded())
            return "Your estimated VO2 max is about \(n) \(vo2Unit) \(c.delta > 0 ? "higher" : "lower") than \(when)."
        }
    }

    static func fitnessTone(_ s: ProgressFitness.Status) -> Tone {
        guard case .ready(let c, _) = s else { return .none }
        if c.steady { return .steady }
        return c.delta > 0 ? .improving : .worsening
    }

    /// The card's one context line, under the cells: the fitness age with its band against the calendar
    /// age, and what the estimate was made from. "Fitness age 34 (±5 years) at 38. VO2 max from resting
    /// HR and age alone; a waist in Settings › Profile sharpens it."
    static func fitnessAgeCaption(_ p: ProgressFitness.Point) -> String {
        let lead = "Fitness age \(Int(p.fitnessAge.rounded())) (±\(Int(FitnessAgeEngine.displayBandYears)) years) at \(Int(p.chronoAge))."
        if p.fallback {
            return "\(lead) VO2 max from resting HR and age alone; a waist in Settings › Profile sharpens it."
        }
        return "\(lead) VO2 max from resting HR, weekly effort and waist, with the age and sex in Settings › Profile."
    }

    static func fitnessThenLabel(_ c: ProgressFitness.Comparison) -> String { "Then · week to \(date(c.then.weekEnding))" }
    static func fitnessNowLabel(_ p: ProgressFitness.Point) -> String { "Now · week to \(date(p.weekEnding))" }

    // MARK: Screen

    /// Said once for the whole screen: what the drawn line is (the HRV and resting HR card footnotes
    /// only state their noise figure).
    static func closingCaption(recalibratedOn: String?) -> String {
        let body = "The HRV and resting HR lines are your baseline going into each night, the same dashed line Trends draws under your nights: a recency-weighted average (half-life \(Int(Baselines.hrvCfg.halfLifeB)) nights) that Today and Trends judge each night against. Noise figures assume nights vary independently; they are a model statement, not a measurement. Estimates from published methods, not medical advice."
        if let recalibratedOn { return "Counting from your recalibration on \(date(recalibratedOn)). " + body }
        return body
    }

    static let emptyTitle = "Progress starts with your first night"
    static let emptyMessage = "Progress shows whether your personal baseline itself is moving over months. After \(Baselines.minNightsTrust) synced nights your HRV and resting HR baselines settle, and from then on each horizon compares them with where they were."
}
#endif
