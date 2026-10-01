#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Pure derivations for the Progress screen: is the personal baseline itself moving over months?
// Everything here is a value type built from `repo.days` (through `BaselineReadouts.nightlyStates`,
// the one fold walk Trends draws its band from) and the Sleep tab's `SleepNight` list. Nothing touches
// the store or SwiftUI.

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
        let validCount = walk.reduce(into: 0) { if $1.validValue != nil { $0 += 1 } }
        guard let newestValidDay = walk.last(where: { $0.validValue != nil })?.day else { return .empty }
        let trusted = ProgressTrajectory.build(walk: walk).filter(\.trusted)

        // Key arithmetic, not row counting: `repo.days` has no rows for off-strap days.
        if newestValidDay < Baselines.cutoffKey(todayKey: todayKey, carryDays: Baselines.staleDays) {
            return .paused(lastDay: newestValidDay, points: trusted)
        }
        guard let first = trusted.first else {
            return .calibrating(nights: min(validCount, Baselines.minNightsTrust))
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
    static let timingMinNights = 7
    /// Minutes of bedtime-spread change below which timing is "about as regular".
    static let timingSteadyMin = 5.0

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

    /// Circular mean (seconds of local day) and spread (minutes) of bed and wake times.
    struct Timing: Equatable {
        let bedMeanSec: Int
        let bedSpreadMin: Double
        let wakeMeanSec: Int
        let wakeSpreadMin: Double
        let nights: Int
    }

    enum Regularity: Equatable {
        /// Every night is `.dailyMetric` (imported totals only).
        case noTimedNights
        /// 1…6 timed nights.
        case building(timed: Int)
        case nowOnly(now: Timing, compareFromDay: String?)
        /// `bedDeltaMin` = now.bedSpreadMin − then.bedSpreadMin (negative = steadier).
        case ready(now: Timing, then: Timing, bedDeltaMin: Double)
    }

    struct Reading: Equatable {
        let duration: Duration
        let regularity: Regularity
    }

    /// `nights` is `SleepNightBuilder.nights(…)`, newest first.
    static func reading(nights: [SleepNight], todayKey: String, horizon: ProgressHorizon) -> Reading {
        let scoped = nights.filter { $0.dayKey <= todayKey }
        let cutoff = horizon.cutoff(todayKey: todayKey)
        return Reading(duration: duration(scoped, cutoff: cutoff, horizon: horizon),
                       regularity: regularity(scoped, cutoff: cutoff, horizon: horizon))
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

    private static func timed(_ night: SleepNight) -> Bool {
        night.source == .session && night.onsetTs != nil && night.wakeTs != nil
    }

    private static func regularity(_ scoped: [SleepNight], cutoff: String?, horizon: ProgressHorizon) -> Regularity {
        let timedAll = scoped.filter(timed)
        guard !timedAll.isEmpty else { return .noTimedNights }
        let nowNights = Array(timedAll.prefix(windowNights))
        guard let now = timing(nowNights) else { return .building(timed: timedAll.count) }

        let thenNights: [SleepNight]
        if let cutoff {
            thenNights = Array(timedAll.filter { $0.dayKey <= cutoff }.prefix(windowNights))
        } else {
            thenNights = Array(timedAll.suffix(windowNights))
        }
        if let then = timing(thenNights), let thenNewest = thenNights.first?.dayKey,
           let nowOldest = nowNights.last?.dayKey, thenNewest < nowOldest {
            return .ready(now: now, then: then, bedDeltaMin: now.bedSpreadMin - then.bedSpreadMin)
        }
        var compareFrom: String? = nil
        if let days = horizon.days, timedAll.count >= timingMinNights {
            compareFrom = Baselines.cutoffKey(todayKey: timedAll[timingMinNights - 1].dayKey, carryDays: -days)
        }
        return .nowOnly(now: now, compareFromDay: compareFrom)
    }

    /// Over the strap-recorded nights in `nights` (first 30 of them); nil below `timingMinNights`.
    /// Mean is circular (so 23:30 and 00:30 average to midnight, not noon); spread is the RMS of the
    /// wrapped distance to the mean, in minutes.
    static func timing(_ nights: [SleepNight], calendar: Calendar = .current) -> Timing? {
        let used = nights.filter(timed).prefix(windowNights)
        guard used.count >= timingMinNights else { return nil }
        var bed: [Double] = []
        var wake: [Double] = []
        for n in used {
            guard let onset = n.onset, let wakeDate = n.wake else { continue }
            bed.append(secondsOfDay(onset, calendar: calendar))
            wake.append(secondsOfDay(wakeDate, calendar: calendar))
        }
        guard let bedMean = circularMeanSec(bed), let wakeMean = circularMeanSec(wake) else { return nil }
        // `% 86_400`: a mean a hair below midnight rounds to 86400, which is 00:00 again.
        return Timing(bedMeanSec: Int(bedMean.rounded()) % 86_400, bedSpreadMin: spreadMin(bed, mean: bedMean),
                      wakeMeanSec: Int(wakeMean.rounded()) % 86_400, wakeSpreadMin: spreadMin(wake, mean: wakeMean),
                      nights: used.count)
    }

    private static func secondsOfDay(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
    }

    /// Mean direction of the seconds-of-day on the 24 h circle, in 0..<86400; nil when the resultant is
    /// (near) zero, i.e. the times are spread evenly round the clock.
    static func circularMeanSec(_ secs: [Double]) -> Double? {
        guard !secs.isEmpty else { return nil }
        let twoPi = 2 * Double.pi
        var s = 0.0, c = 0.0
        for v in secs {
            let theta = twoPi * v / 86_400
            s += sin(theta)
            c += cos(theta)
        }
        let resultant = sqrt(s * s + c * c) / Double(secs.count)
        guard resultant >= 1e-6 else { return nil }
        var mean = atan2(s, c) / twoPi * 86_400
        if mean < 0 { mean += 86_400 }
        if mean >= 86_400 { mean -= 86_400 }
        return mean
    }

    /// sqrt(mean(d²)) / 60 with d the wrapped distance to `mean` (so 23:30 and 00:30 are an hour apart).
    static func spreadMin(_ secs: [Double], mean: Double) -> Double {
        guard !secs.isEmpty else { return 0 }
        let sum = secs.reduce(0.0) { acc, v in
            var d = (v - mean + 43_200).truncatingRemainder(dividingBy: 86_400)
            if d < 0 { d += 86_400 }
            d -= 43_200
            return acc + d * d
        }
        return sqrt(sum / Double(secs.count)) / 60
    }
}

// MARK: - Snapshot

struct ProgressSnapshot {
    let horizon: ProgressHorizon
    let todayKey: String
    let hrv: ProgressMetricStatus
    let restingHr: ProgressMetricStatus
    let sleep: ProgressSleep.Reading
    /// Nights anywhere with HRV, resting HR or sleep (Trends' gate); 0 → empty-store state.
    let totalNights: Int
    /// The recalibration day when it dropped at least one night, for the closing caption.
    let recalibratedOn: String?

    /// `days` is `repo.days` (oldest → newest); `nights` is `SleepNightBuilder.nights(…)` (newest first).
    static func build(days: [DailyMetric], nights: [SleepNight], horizon: ProgressHorizon, todayKey: String) -> ProgressSnapshot {
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
        if let phrase = horizon.agoPhrase, !c.namesDate { return phrase }
        if horizon == .all { return "when it settled on \(date(c.then.day))" }
        return "on \(date(c.then.day))"
    }

    // MARK: Metric

    static func sentence(noun: String, unit: String, status: ProgressMetricStatus, horizon: ProgressHorizon) -> String {
        switch status {
        case .empty:
            return "No nights with \(noun) yet."
        case .calibrating(let n):
            return "Your \(noun) baseline settles after \(Baselines.minNightsTrust) nights · \(n) so far. Progress compares it with itself from then on."
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

    /// The dot beside the sentence: `MetricHero.bandDot`'s rule with `higherIsBetter` (HRV up / resting
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
            let n = Int(c.noise.rounded(.up))
            return "The line is your baseline going into each night, the same dashed line Trends draws under your nights. Changes under about \(n) \(unit) are within the baseline's own noise."
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

    /// "11:24 PM" for seconds of local day, on today's date (the device zone).
    static func clock(sec: Int, calendar: Calendar = .current) -> String {
        SleepFormat.clock(calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(sec)))
    }

    static func timingSentence(_ r: ProgressSleep.Regularity, horizon: ProgressHorizon) -> String {
        switch r {
        case .noTimedNights:
            return "Bed and wake times come from nights the strap recorded. Imported nights carry totals only."
        case .building(let n):
            return "Bed and wake times settle after \(ProgressSleep.timingMinNights) strap nights · \(n) so far."
        case .nowOnly(let now, let compareFrom):
            let lead = "Your bedtime lands within about \(Int(now.bedSpreadMin.rounded())) min of \(clock(sec: now.bedMeanSec))."
            if let compareFrom, let phrase = horizon.agoPhrase {
                return "\(lead) Compare it with \(phrase) from \(date(compareFrom))."
            }
            if horizon == .all {
                return "\(lead) Keep wearing the strap and the comparison arrives."
            }
            return "\(lead) Comparisons start after \(ProgressSleep.timingMinNights) more strap nights."
        case .ready(_, _, let delta):
            let n = Int(abs(delta).rounded())
            if delta <= -ProgressSleep.timingSteadyMin {
                return "Your bedtime is \(n) min steadier than \(sleepAgo(horizon))."
            }
            if delta >= ProgressSleep.timingSteadyMin {
                return "Your bedtime is \(n) min less steady than \(sleepAgo(horizon))."
            }
            return "Your bedtime is about as regular as \(sleepAgo(horizon))."
        }
    }

    static func timingTone(_ r: ProgressSleep.Regularity) -> Tone {
        guard case .ready(_, _, let delta) = r else { return .none }
        if delta <= -ProgressSleep.timingSteadyMin { return .improving }
        if delta >= ProgressSleep.timingSteadyMin { return .worsening }
        return .steady
    }

    /// "11:24 PM · ±25 min"
    static func timingValue(meanSec: Int, spreadMin: Double) -> String {
        "\(clock(sec: meanSec)) · ±\(Int(spreadMin.rounded())) min"
    }

    /// "was 11:51 PM · ±43 min"
    static func timingWas(meanSec: Int, spreadMin: Double) -> String {
        "was \(timingValue(meanSec: meanSec, spreadMin: spreadMin))"
    }

    /// "Bedtime usually 11:24 PM, varying about 25 minutes; was 11:51 PM varying 43 minutes."
    static func timingSpoken(label: String, meanSec: Int, spreadMin: Double, wasMeanSec: Int?, wasSpreadMin: Double?) -> String {
        var s = "\(label) usually \(clock(sec: meanSec)), varying about \(Int(spreadMin.rounded())) minutes"
        if let wasMeanSec, let wasSpreadMin {
            s += "; was \(clock(sec: wasMeanSec)) varying \(Int(wasSpreadMin.rounded())) minutes"
        }
        return s + "."
    }

    // MARK: Screen

    static func closingCaption(recalibratedOn: String?) -> String {
        let body = "Baselines are the recency-weighted averages Today and Trends judge each night against (half-life \(Int(Baselines.hrvCfg.halfLifeB)) nights). Noise figures assume nights vary independently; they are a model statement, not a measurement. Estimates from published methods, not medical advice."
        if let recalibratedOn { return "Counting from your recalibration on \(date(recalibratedOn)). " + body }
        return body
    }

    static let emptyTitle = "Progress starts with your first night"
    static let emptyMessage = "Progress shows whether your personal baseline itself is moving over months. After \(Baselines.minNightsTrust) synced nights your HRV and resting HR baselines settle, and from then on each horizon compares them with where they were."
}
#endif
