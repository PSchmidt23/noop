#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Pure derivations for the Compare screen: night by night, how do the Baseline strap's numbers sit
// against an imported source (the official WHOOP export, or an Apple Health import)? Everything here is
// a value type built from `repo.vitalRows`, the per-source daily rows the engine publishes on every
// refresh (`.noopComputed` = the strap's own nights, `.whoopImport` = the WHOOP CSV import,
// `.appleHealth` = Apple Health). Nothing touches the store or SwiftUI.
//
// Day convention: both sides key a night by the morning it ends on (`DailyMetric.day`), so a pair is
// the same night as seen by two recorders. A difference is always Baseline − other: a fact, not a verdict.

// MARK: - Metric

/// The four figures both recorders produce on a comparable scale. Effort is left out: the import carries
/// WHOOP's day scale rescaled to 0–100, which pairs, but five segments do not fit the narrowest width.
/// Readiness is a tier here and a 0–100 score there, so it has no sensible pairing.
enum CompareMetric: String, CaseIterable, Identifiable {
    case hrv, restingHr, sleep, efficiency

    var id: String { rawValue }

    static func resolve(_ raw: String) -> CompareMetric { CompareMetric(rawValue: raw) ?? .hrv }

    /// Pill text.
    var label: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHr: return "Resting HR"
        case .sleep: return "Sleep"
        case .efficiency: return "Efficiency"
        }
    }

    /// How the metric reads mid-sentence.
    var noun: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHr: return "resting HR"
        case .sleep: return "sleep"
        case .efficiency: return "sleep efficiency"
        }
    }

    /// The unit printed beside a value; empty for sleep, whose values are spelled as durations.
    var unit: String {
        switch self {
        case .hrv: return "ms"
        case .restingHr: return "bpm"
        case .sleep: return ""
        case .efficiency: return "%"
        }
    }

    /// The night's value in display units when it is valid on this metric, else nil. HRV and resting HR
    /// honour the engine's plausible ranges (the same gate `BaselineReadouts.latestNight` applies); sleep
    /// is minutes asleep; efficiency is the stored 0–1 fraction as a percentage.
    func value(_ d: DailyMetric) -> Double? {
        switch self {
        case .hrv:
            guard let v = d.avgHrv, v.isFinite, Baselines.hrvCfg.minVal <= v, v <= Baselines.hrvCfg.maxVal else { return nil }
            return v
        case .restingHr:
            guard let r = d.restingHr else { return nil }
            let v = Double(r)
            guard Baselines.restingHRCfg.minVal <= v, v <= Baselines.restingHRCfg.maxVal else { return nil }
            return v
        case .sleep:
            guard let m = d.totalSleepMin, m.isFinite, m > 0 else { return nil }
            return m
        case .efficiency:
            guard let e = d.efficiency, e.isFinite, e > 0, e <= 1 else { return nil }
            return e * 100
        }
    }

    /// A value as the list and the stat cells print it: "62", "7h 12m", "91".
    func valueText(_ v: Double) -> String {
        switch self {
        case .sleep: return BaselineReadouts.durationText(minutes: v)
        case .hrv, .restingHr, .efficiency: return String(Int(v.rounded()))
        }
    }

    /// A signed difference with a typographic minus: "+4 ms", "−3 bpm", "+22 min", "−1h 05m", "+2 pts".
    /// Zero prints unsigned ("0 ms").
    func differenceText(_ d: Double) -> String {
        let m = Int(d.rounded())
        let sign = m < 0 ? "\u{2212}" : (m > 0 ? "+" : "")
        switch self {
        case .sleep: return sign + BaselineReadouts.durationText(minutes: Double(abs(m)))
        case .efficiency: return "\(sign)\(abs(m)) pts"
        case .hrv, .restingHr: return "\(sign)\(abs(m)) \(unit)"
        }
    }

    /// The size of a gap as a sentence spells it ("4 ms", "22 min", "2 points"); nil when it rounds to
    /// nothing, so the sentence can say "matched" instead.
    func magnitudeText(_ d: Double) -> String? {
        let m = Int(abs(d).rounded())
        guard m > 0 else { return nil }
        switch self {
        case .sleep: return BaselineReadouts.durationText(minutes: Double(m))
        case .efficiency: return m == 1 ? "1 point" : "\(m) points"
        case .hrv, .restingHr: return "\(m) \(unit)"
        }
    }

    /// "above" / "below" for a level; "longer than" / "shorter than" for a duration.
    func directionWords(baselineHigher: Bool) -> String {
        switch self {
        case .sleep: return baselineHigher ? "longer than" : "shorter than"
        case .hrv, .restingHr, .efficiency: return baselineHigher ? "above" : "below"
        }
    }

    /// Display value → chart value: sleep is drawn in hours, everything else as is.
    func chartValue(_ v: Double) -> Double {
        self == .sleep ? v / 60 : v
    }

    /// The y-axis snap step in chart units (5 ms, 2 bpm, 1 h, 5 %).
    var chartStep: Double {
        switch self {
        case .hrv: return 5
        case .restingHr: return 2
        case .sleep: return 1
        case .efficiency: return 5
        }
    }

    /// The axis unit for the chart ("h" for sleep).
    var chartUnit: String { self == .sleep ? "h" : unit }
}

// MARK: - Source

/// What the strap's nights are compared with. `rows(for:)` reads the matching provenance out of
/// `repo.vitalRows`.
enum CompareSource: String, CaseIterable, Identifiable, Hashable {
    case whoopExport, appleHealth

    var id: String { rawValue }

    static func resolve(_ raw: String) -> CompareSource { CompareSource(rawValue: raw) ?? .whoopExport }

    /// Pill and legend text.
    var label: String {
        switch self {
        case .whoopExport: return "WHOOP export"
        case .appleHealth: return "Apple Health"
        }
    }

    /// The short name a column header or a sentence uses.
    var shortName: String {
        switch self {
        case .whoopExport: return "WHOOP"
        case .appleHealth: return "Apple Health"
        }
    }

    var possessive: String { shortName + "\u{2019}s" }

    var dailySource: DailyMetricSource {
        switch self {
        case .whoopExport: return .whoopImport
        case .appleHealth: return .appleHealth
        }
    }

    /// A caveat the summary shows under the sentence when the two recorders do not measure the same
    /// statistic; nil when they do.
    func caveat(for metric: CompareMetric) -> String? {
        guard self == .appleHealth, metric == .hrv else { return nil }
        return "Apple Health\u{2019}s HRV is SDNN from Apple Watch, not the RMSSD Baseline measures, so the two differ by design."
    }
}

// MARK: - Range

/// The chart window. Raw value = days (what AppStorage persists); `.all` is 0.
enum BaselineCompareRange: Int, CaseIterable, Identifiable, BaselineRangeOption {
    case month = 30
    case quarter = 90
    case all = 0

    var id: Int { rawValue }
    /// nil for `.all`.
    var days: Int? { self == .all ? nil : rawValue }

    var label: String {
        switch self {
        case .month: return "30D"
        case .quarter: return "90D"
        case .all: return "All"
        }
    }

    var subtitle: String {
        switch self {
        case .month: return "Last 30 days"
        case .quarter: return "Last 90 days"
        case .all: return "All nights"
        }
    }

    static func resolve(_ raw: Int) -> BaselineCompareRange { BaselineCompareRange(rawValue: raw) ?? .month }

    /// The first day key inside the window (today and the `days − 1` before it, pure UTC key math, the
    /// same count Trends uses); nil for `.all`.
    func startKey(todayKey: String) -> String? {
        days.map { Baselines.cutoffKey(todayKey: todayKey, carryDays: $0 - 1) }
    }
}

// MARK: - Pairs and stats

/// One night both recorders have on the chosen metric, in display units.
struct ComparePair: Identifiable, Equatable {
    /// Day key.
    let id: String
    let date: Date
    let baseline: Double
    let other: Double

    var day: String { id }
    /// Baseline − other.
    var difference: Double { baseline - other }
}

struct CompareStats: Equatable {
    let nights: Int
    /// Mean of (Baseline − other).
    let meanDifference: Double
    /// Mean of |Baseline − other|.
    let meanAbsoluteDifference: Double
    /// Pearson r across the pairs (`CorrelationEngine.pearson`); nil under 3 nights or when either side
    /// never varies.
    let r: Double?
}

/// `repo.vitalRows` split by provenance.
struct CompareRows: Equatable {
    /// The strap's own nights (`.noopComputed`).
    let baseline: [DailyMetric]
    let bySource: [CompareSource: [DailyMetric]]

    func rows(for source: CompareSource) -> [DailyMetric] { bySource[source] ?? [] }
}

enum CompareModel {

    static func split(_ rows: [SourcedDailyMetric]) -> CompareRows {
        var baseline: [DailyMetric] = []
        var bySource: [CompareSource: [DailyMetric]] = [:]
        for row in rows {
            switch row.source {
            case .noopComputed: baseline.append(row.metric)
            case .whoopImport: bySource[.whoopExport, default: []].append(row.metric)
            case .appleHealth: bySource[.appleHealth, default: []].append(row.metric)
            case .localCache: break
            }
        }
        return CompareRows(baseline: baseline, bySource: bySource)
    }

    /// Inner join on the day key, oldest → newest, keeping only nights valid on `metric` for BOTH sides.
    /// A day listed twice on one side keeps its last row. An unparseable key is dropped.
    static func pairs(baseline: [DailyMetric], other: [DailyMetric], metric: CompareMetric) -> [ComparePair] {
        var otherByDay: [String: Double] = [:]
        for d in other {
            if let v = metric.value(d) { otherByDay[d.day] = v }
        }
        var baselineByDay: [String: Double] = [:]
        for d in baseline {
            if let v = metric.value(d) { baselineByDay[d.day] = v }
        }
        return baselineByDay.keys.sorted().compactMap { day in
            guard let b = baselineByDay[day], let o = otherByDay[day], let date = TrendsDayKey.date(day) else { return nil }
            return ComparePair(id: day, date: date, baseline: b, other: o)
        }
    }

    /// Sources with at least one night overlapping the strap's on any metric, in picker order.
    static func availableSources(_ rows: CompareRows) -> [CompareSource] {
        CompareSource.allCases.filter { source in
            let other = rows.rows(for: source)
            guard !other.isEmpty, !rows.baseline.isEmpty else { return false }
            return CompareMetric.allCases.contains { !pairs(baseline: rows.baseline, other: other, metric: $0).isEmpty }
        }
    }

    /// nil when there are no pairs.
    static func stats(_ pairs: [ComparePair]) -> CompareStats? {
        guard !pairs.isEmpty else { return nil }
        let n = Double(pairs.count)
        let diffs = pairs.map(\.difference)
        let mean = diffs.reduce(0, +) / n
        let meanAbs = diffs.reduce(0) { $0 + abs($1) } / n
        let r = CorrelationEngine.pearson(pairs.map { ($0.baseline, $0.other) })?.r
        return CompareStats(nights: pairs.count, meanDifference: mean, meanAbsoluteDifference: meanAbs, r: r)
    }

    /// The pairs inside `range` ending at `todayKey`.
    static func window(_ pairs: [ComparePair], range: BaselineCompareRange, todayKey: String) -> [ComparePair] {
        guard let start = range.startKey(todayKey: todayKey) else { return pairs }
        return pairs.filter { $0.day >= start }
    }

    /// One plain sentence: "On 41 nights Baseline's HRV ran 4 ms above WHOOP's and moved with it (r = 0.86)."
    /// A gap that rounds to nothing reads "matched WHOOP's on average"; without an r the tracking clause
    /// is left off.
    static func sentence(metric: CompareMetric, stats: CompareStats, source: CompareSource) -> String {
        let nights = "\(stats.nights) night\(stats.nights == 1 ? "" : "s")"
        let gap: String
        if let magnitude = metric.magnitudeText(stats.meanDifference) {
            let direction = metric.directionWords(baselineHigher: stats.meanDifference > 0)
            gap = "ran \(magnitude) \(direction) \(source.possessive)"
        } else {
            gap = "matched \(source.possessive) on average"
        }
        let tracking: String
        if let r = stats.r {
            let rText = "r = " + (r < 0 ? "\u{2212}" : "") + String(format: "%.2f", abs(r))
            if r >= 0.7 {
                tracking = " and moved with it (\(rText))"
            } else if r >= 0.4 {
                tracking = " and loosely followed it (\(rText))"
            } else {
                tracking = " but did not track it (\(rText))"
            }
        } else {
            tracking = ""
        }
        return "On \(nights) Baseline\u{2019}s \(metric.noun) \(gap)\(tracking)."
    }

    /// "0.86" / "−0.12"; "—" when undefined.
    static func rText(_ r: Double?) -> String {
        guard let r else { return "\u{2014}" }
        return (r < 0 ? "\u{2212}" : "") + String(format: "%.2f", abs(r))
    }

    /// min … max of `values` padded ~12% and snapped outward to `step`, never below zero: the rule
    /// `TrendsSeries.yDomain` applies, over both lines.
    static func yDomain(_ values: [Double], step: Double) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...step }
        let pad = max(hi - lo, step) * 0.12
        let floorLo = max(0, (lo - pad) / step).rounded(.down) * step
        let ceilHi = ((hi + pad) / step).rounded(.up) * step
        return floorLo...max(ceilHi, floorLo + step)
    }
}

// MARK: - Snapshot

/// Everything the Compare screen draws for one (source, metric, range), built once per load.
struct CompareSnapshot {
    /// The source actually compared: the requested one when it has overlapping nights, else the first
    /// that does (the picker follows this).
    let source: CompareSource
    let metric: CompareMetric
    let range: BaselineCompareRange
    let availableSources: [CompareSource]
    /// Every overlapping night on `metric` up to today, oldest → newest.
    let pairs: [ComparePair]
    /// Over `pairs`; nil when the metric has no overlapping night.
    let stats: CompareStats?
    let sentence: String?
    /// `pairs` inside `range`.
    let windowed: [ComparePair]
    let yDomain: ClosedRange<Double>

    /// The last 30 overlapping nights, newest first.
    var recentNights: [ComparePair] { Array(pairs.suffix(30).reversed()) }

    static func build(rows: [SourcedDailyMetric], source requested: CompareSource, metric: CompareMetric,
                      range: BaselineCompareRange, todayKey: String) -> CompareSnapshot {
        let split = CompareModel.split(rows)
        let available = CompareModel.availableSources(split)
        let source = available.contains(requested) ? requested : (available.first ?? requested)
        let pairs = CompareModel.pairs(baseline: split.baseline, other: split.rows(for: source), metric: metric)
            .filter { $0.day <= todayKey }
        let stats = CompareModel.stats(pairs)
        let windowed = CompareModel.window(pairs, range: range, todayKey: todayKey)
        let yDomain = CompareModel.yDomain(
            windowed.flatMap { [metric.chartValue($0.baseline), metric.chartValue($0.other)] },
            step: metric.chartStep)
        return CompareSnapshot(source: source, metric: metric, range: range, availableSources: available,
                               pairs: pairs, stats: stats,
                               sentence: stats.map { CompareModel.sentence(metric: metric, stats: $0, source: source) },
                               windowed: windowed, yDomain: yDomain)
    }
}
#endif
