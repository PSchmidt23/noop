#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Ranges over the funnel: one metric key, one range (1D / 7D / 4W / 1Y), one pure builder. Every metric
// detail screen reads its points and its four hero numbers from `BaselineReadouts.metricSeries`, so a
// weekly average, a window's low and the "vs the period before" sentence are computed in ONE place over
// ONE table (`repo.baselineDays`, strap first). Daily-column metrics are a few linear passes over rows
// already in memory; the intraday-derived ones (Stress, Intensity minutes, heart rate) arrive as
// per-day facts from `IntradayDayStore`, never from raw samples over weeks.

// MARK: - Range

/// The detail screens' window. `label` is the pill text ("1D / 7D / 4W / 1Y"), `subtitle` the spoken
/// form. 7D and 4W are daily points; 1Y is weekly averages over ISO weeks (Monday-first, local calendar).
enum MetricRange: String, CaseIterable, Identifiable, BaselineRangeOption {
    case day, week, fourWeeks, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "1D"
        case .week: return "7D"
        case .fourWeeks: return "4W"
        case .year: return "1Y"
        }
    }

    var subtitle: String {
        switch self {
        case .day: return "One day"
        case .week: return "Last 7 days"
        case .fourWeeks: return "Last 4 weeks"
        case .year: return "Last year"
        }
    }

    /// The pill text at accessibility sizes: the label itself. Four two-character segments fit at AX3
    /// (as "4W" / "1Y" always did), and dropping the "D" from "1D" / "7D" alone left a bare "1" beside
    /// "4W": four tokens in two spellings. VoiceOver reads `subtitle` either way.
    var shortLabel: String { label }

    /// Calendar days the window spans, ending on the selected day inclusive.
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .fourWeeks: return 28
        case .year: return 365
        }
    }

    /// How the window's days are grouped into points.
    var bucket: RangeBucket { self == .year ? .week : .day }

    /// The window as a phrase for a sentence: "today" / "the last 7 days" / "the last 4 weeks" / "the last year".
    var phrase: String {
        switch self {
        case .day: return "this day"
        case .week: return "the last 7 days"
        case .fourWeeks: return "the last 4 weeks"
        case .year: return "the last year"
        }
    }

    static func resolve(_ raw: String?) -> MetricRange { raw.flatMap(MetricRange.init(rawValue:)) ?? .week }
}

/// How `BaselineRangeSeries.buckets` groups days: one point per day, per ISO week (Monday → Sunday,
/// local) or per calendar month.
enum RangeBucket: Equatable {
    case day, week, month
}

// MARK: - Keys

/// The metrics a detail screen can be opened on. `seriesKey` is NOOP's daily column
/// (`Repository.dailyColumn`) where one exists; the rest are built from nights (bedtime, wake) or from
/// the per-day intraday facts (Stress, Intensity minutes, heart rate).
enum MetricKey: String, CaseIterable, Identifiable {
    case hrv, rhr, readiness, sleepDuration, sleepEfficiency, bedtime, wake, steps, effort, calories,
         stressAvg, intensityMinutes, heartRate

    var id: String { rawValue }

    /// Baseline's vocabulary, as a card title.
    var name: String {
        switch self {
        case .hrv: return "HRV"
        case .rhr: return "Resting HR"
        case .readiness: return "Readiness"
        case .sleepDuration: return "Sleep"
        case .sleepEfficiency: return "Sleep efficiency"
        case .bedtime: return "Bedtime"
        case .wake: return "Wake time"
        case .steps: return "Steps"
        case .effort: return "Effort"
        case .calories: return "Calories"
        case .stressAvg: return "Stress"
        case .intensityMinutes: return "Intensity minutes"
        case .heartRate: return "Heart rate"
        }
    }

    /// The daily column behind the key, nil for the derived ones.
    var seriesKey: String? {
        switch self {
        case .hrv: return "hrv"
        case .rhr: return "rhr"
        case .readiness: return "recovery"
        case .sleepDuration: return "sleep_total_min"
        case .sleepEfficiency: return "sleep_efficiency"
        case .steps: return "steps"
        case .effort: return "strain"
        case .calories: return "active_kcal"
        case .bedtime, .wake, .stressAvg, .intensityMinutes, .heartRate: return nil
        }
    }

    /// Drawn as bars (a count or a load that adds up) rather than a line (a level).
    var isCountLike: Bool {
        switch self {
        case .steps, .effort, .calories, .intensityMinutes, .sleepDuration: return true
        default: return false
        }
    }

    /// A clock time: bedtime is kept as minutes after the previous NOON (23:30 → 690, 00:30 → 750) and
    /// wake as minutes after midnight, so averages, lows and highs are plain arithmetic with no wrap.
    var isClockTime: Bool { self == .bedtime || self == .wake }

    /// Which way is good, for the chart's accessibility hint; nil where neither is.
    var higherIsBetter: Bool? {
        switch self {
        case .hrv, .readiness, .sleepDuration, .sleepEfficiency, .steps, .intensityMinutes: return true
        case .rhr, .stressAvg: return false
        case .bedtime, .wake, .effort, .calories, .heartRate: return nil
        }
    }

    /// Needs per-day facts from the intraday stream (`IntradayDayStore`) rather than a daily column.
    var isIntradayDerived: Bool {
        switch self {
        case .stressAvg, .intensityMinutes, .heartRate: return true
        default: return false
        }
    }
}

// MARK: - Points and stats

/// A personal band for one point: the baseline going into that day with its ± sigma edges
/// (`BaselineReadouts.nightlyStates`), or nil before the band is usable.
struct MetricBand: Equatable {
    let baseline: Double
    let low: Double
    let high: Double
}

/// One point on a metric chart: a day, or a week / month bucket of days. `min` / `max` are the lowest
/// and highest DAILY values inside the bucket (for heart rate, the day's own low and high), nil on a
/// single-day point without its own extremes. `n` counts the days with a value; a bucket with none is
/// absent, never a zero.
struct RangePoint: Identifiable, Equatable {
    /// The day key, or the bucket's first day key (its Monday for a week).
    let id: String
    /// Local midnight of `id`; for an intraday point the sample's own instant.
    let date: Date
    let value: Double
    let min: Double?
    let max: Double?
    let n: Int
    var band: MetricBand? = nil
}

/// The four hero numbers of a range plus the comparison with the period before it.
struct MetricStats: Equatable {
    /// The newest day in the window with a value, and the value.
    let latest: Double?
    let latestDay: String?
    /// Mean, low and high of the DAILY values in the window (never of bucket means).
    let average: Double?
    let min: Double?
    let max: Double?
    /// Days with a value.
    let count: Int
    /// Mean over the same-length window immediately before this one (nil under `MetricStats.minDays`).
    let previousAverage: Double?
    let previousCount: Int

    /// `average − previousAverage`; nil when either side is missing.
    var change: Double? {
        guard let average, let previousAverage else { return nil }
        return average - previousAverage
    }

    /// Fewest days before a window's average is compared with the one before it.
    static let minDays = 3

    static let empty = MetricStats(latest: nil, latestDay: nil, average: nil, min: nil, max: nil, count: 0,
                                   previousAverage: nil, previousCount: 0)
}

/// Everything a metric detail draws for one key and one range.
struct MetricSeries {
    let key: MetricKey
    let range: MetricRange
    /// First and last day keys of the window (inclusive).
    let startKey: String
    let endKey: String
    let points: [RangePoint]
    let stats: MetricStats
    /// The newest bucket does not yet hold its full span of days (a week still in progress).
    let lastBucketPartial: Bool

    var isEmpty: Bool { points.isEmpty }
}

/// A day's value with optional extremes (heart rate carries its low and high beside the mean).
struct MetricDayValue: Equatable {
    let day: String
    let value: Double
    var min: Double? = nil
    var max: Double? = nil
}

// MARK: - Bucketing (pure)

/// The one bucketing function every range goes through: days in, points out. Missing days are
/// excluded (`n` says how many were seen); an empty bucket is absent; weeks are ISO weeks on the local
/// calendar (Monday first, `isoCalendar`), keyed by the Monday's day key; months by their first day.
enum BaselineRangeSeries {

    /// The local calendar with ISO weeks: Monday first, whatever the device locale starts its week on,
    /// so an Intensity-minutes week and a 1Y bucket are the same seven days (Garmin's convention, ISO 8601).
    static func isoCalendar(_ base: Calendar = .current) -> Calendar {
        var c = base
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// The first day key of the bucket `dayKey` falls in: the key itself for `.day`, its Monday for
    /// `.week`, the 1st for `.month`. nil for an unparseable key.
    static func bucketStart(of dayKey: String, bucket: RangeBucket, calendar: Calendar = .current) -> String? {
        guard let date = BaselineReadouts.localMidnight(of: dayKey) else { return nil }
        switch bucket {
        case .day:
            return dayKey
        case .week:
            guard let interval = isoCalendar(calendar).dateInterval(of: .weekOfYear, for: date) else { return nil }
            return Repository.localDayKey(interval.start)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
            return Repository.localDayKey(interval.start)
        }
    }

    /// The last day key of the bucket starting on `startKey` (its Sunday, its month end).
    static func bucketEnd(of startKey: String, bucket: RangeBucket, calendar: Calendar = .current) -> String? {
        guard let date = BaselineReadouts.localMidnight(of: startKey) else { return nil }
        switch bucket {
        case .day:
            return startKey
        case .week:
            guard let end = isoCalendar(calendar).date(byAdding: .day, value: 6, to: date) else { return nil }
            return Repository.localDayKey(end)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: date),
                  let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
            return Repository.localDayKey(last)
        }
    }

    /// Points over `from`…`to` (inclusive day keys), oldest first. A bucket's `value` is the mean of its
    /// days' values, `min` / `max` the lowest low and highest high of its days (a day's own `min` / `max`
    /// when it carries them, else its value), `n` its day count. Values that are not finite are skipped.
    static func buckets(_ values: [MetricDayValue], from: String, to: String, bucket: RangeBucket,
                        calendar: Calendar = .current) -> [RangePoint] {
        var byStart: [String: (sum: Double, lo: Double, hi: Double, n: Int)] = [:]
        for v in values where v.day >= from && v.day <= to && v.value.isFinite {
            guard let start = bucketStart(of: v.day, bucket: bucket, calendar: calendar) else { continue }
            let lo = v.min ?? v.value, hi = v.max ?? v.value
            if var acc = byStart[start] {
                acc.sum += v.value; acc.lo = Swift.min(acc.lo, lo); acc.hi = Swift.max(acc.hi, hi); acc.n += 1
                byStart[start] = acc
            } else {
                byStart[start] = (v.value, lo, hi, 1)
            }
        }
        return byStart.keys.sorted().compactMap { start in
            guard let acc = byStart[start], let date = BaselineReadouts.localMidnight(of: start) else { return nil }
            let mean = acc.sum / Double(acc.n)
            // A single day without its own extremes has none to show.
            let hasExtremes = bucket != .day || acc.lo != mean || acc.hi != mean
            return RangePoint(id: start, date: date, value: mean,
                               min: hasExtremes ? acc.lo : nil, max: hasExtremes ? acc.hi : nil, n: acc.n)
        }
    }

    /// Stats over the DAILY values inside `from`…`to`, with the same-length window before `from` as the
    /// comparison (`previousAverage`, nil under `MetricStats.minDays` days on either side).
    static func stats(_ values: [MetricDayValue], from: String, to: String) -> MetricStats {
        var inWindow: [MetricDayValue] = []
        var before: [MetricDayValue] = []
        let span = dayCount(from: from, to: to)
        let previousFrom = Baselines.cutoffKey(todayKey: from, carryDays: span)
        for v in values where v.value.isFinite {
            if v.day >= from && v.day <= to { inWindow.append(v) }
            else if v.day >= previousFrom && v.day < from { before.append(v) }
        }
        inWindow.sort { $0.day < $1.day }
        let vals = inWindow.map(\.value)
        let avg = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        let prevVals = before.map(\.value)
        // A one-day window compares with the day before it alone.
        let minDays = span == 1 ? 1 : MetricStats.minDays
        let enough = vals.count >= minDays && prevVals.count >= minDays
        let prevAvg = enough ? prevVals.reduce(0, +) / Double(prevVals.count) : nil
        return MetricStats(latest: inWindow.last?.value, latestDay: inWindow.last?.day,
                           average: avg, min: vals.min(), max: vals.max(), count: vals.count,
                           previousAverage: prevAvg, previousCount: prevVals.count)
    }

    /// Calendar days from `from` to `to` inclusive (UTC key math; 1 for equal keys, 0 when reversed).
    static func dayCount(from: String, to: String) -> Int {
        guard let a = TrendsDayKey.utc.date(from: from), let b = TrendsDayKey.utc.date(from: to), b >= a else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded()) + 1
    }
}

// MARK: - Readings per key (pure)

extension BaselineReadouts {

    /// Per-day facts the intraday stream yields (`IntradayDayStore`), keyed by day: Stress day mean (0–3),
    /// credited Intensity minutes, and the day's heart-rate low / mean / high. Any map may be empty.
    struct IntradayDayValues {
        var stressMean: [String: Double] = [:]
        var intensityMinutes: [String: Double] = [:]
        var heartRate: [String: (min: Double, avg: Double, max: Double)] = [:]

        static let none = IntradayDayValues()
    }

    /// The `(day, value)` readings behind a key, oldest → newest, from the funnel's `days`, the Sleep
    /// tab's `nights` (bedtime / wake; `.dailyMetric` nights carry no times) and the intraday facts.
    /// `stepReadings` (`BaselineReadouts.stepReadings`, the strap → phone → estimate resolution) replaces
    /// the funnel's `steps` column when given. Efficiency is a percent (0–100); bedtime and wake are
    /// clock minutes (`MetricKey.isClockTime`).
    static func metricReadings(key: MetricKey, days: [DailyMetric], nights: [SleepNight] = [],
                               stepReadings: [(day: String, value: Double)]? = nil,
                               intraday: IntradayDayValues = .none, calendar: Calendar = .current) -> [MetricDayValue] {
        switch key {
        case .hrv, .rhr, .readiness, .sleepDuration, .effort, .calories:
            return BaselineDays.series(key: key.seriesKey ?? "", days: days).map { MetricDayValue(day: $0.day, value: $0.value) }
        case .sleepEfficiency:
            return days.compactMap { d in
                guard let e = d.efficiency, e > 0 else { return nil }
                return MetricDayValue(day: d.day, value: e > 1.5 ? e : e * 100)
            }
        case .steps:
            let readings = stepReadings ?? BaselineDays.series(key: "steps", days: days)
            return readings.filter { $0.value >= 0 }.sorted { $0.day < $1.day }.map { MetricDayValue(day: $0.day, value: $0.value) }
        case .bedtime, .wake:
            return nights.compactMap { n -> MetricDayValue? in
                guard let bed = n.onset, let wake = n.wake, wake > bed else { return nil }
                let m = key == .bedtime
                    ? (minutesOfDay(bed, calendar: calendar) + 720).truncatingRemainder(dividingBy: 1440)
                    : minutesOfDay(wake, calendar: calendar)
                return MetricDayValue(day: n.dayKey, value: m)
            }.sorted { $0.day < $1.day }
        case .stressAvg:
            return intraday.stressMean.map { MetricDayValue(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
        case .intensityMinutes:
            return intraday.intensityMinutes.map { MetricDayValue(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
        case .heartRate:
            return intraday.heartRate.map { MetricDayValue(day: $0.key, value: $0.value.avg, min: $0.value.min, max: $0.value.max) }
                .sorted { $0.day < $1.day }
        }
    }

    /// Bedtime / wake as a clock time back from the series' minutes: bedtime values are noon-anchored
    /// (`MetricKey.isClockTime`), wake values midnight-anchored.
    static func clockValueText(_ value: Double, key: MetricKey, calendar: Calendar = .current) -> String {
        let minutes = key == .bedtime ? (value + 720).truncatingRemainder(dividingBy: 1440) : value
        return clockText(minutes: minutes, calendar: calendar)
    }

    /// The window `range` covers ending on `endKey` (both keys inclusive).
    static func metricWindow(range: MetricRange, endKey: String) -> (startKey: String, endKey: String) {
        (Baselines.cutoffKey(todayKey: endKey, carryDays: range.days - 1), endKey)
    }

    /// The series for `key` over `range` ending on `endKey`, from readings already resolved
    /// (`metricReadings`). `bands` (day key → band, `metricBands`) is attached to day points by key and to
    /// week points as the mean band of their days. `intraday` supplies the 1D heart-rate trace: its
    /// points become the series (one per sample) and its low / mean / high the stats.
    static func metricSeries(key: MetricKey, range: MetricRange, endKey: String, readings: [MetricDayValue],
                             bands: [String: MetricBand] = [:], intraday: IntradayHeartRate? = nil,
                             calendar: Calendar = .current) -> MetricSeries {
        let (startKey, _) = metricWindow(range: range, endKey: endKey)
        if key == .heartRate, range == .day {
            let points = (intraday?.points ?? []).map { p in
                RangePoint(id: "\(p.id)", date: p.date, value: p.bpm, min: p.minBpm, max: p.maxBpm, n: 1)
            }
            let stats = intraday.map { t in
                MetricStats(latest: t.points.last?.bpm, latestDay: endKey, average: t.avgBpm, min: t.minBpm, max: t.maxBpm,
                            count: t.points.count, previousAverage: nil, previousCount: 0)
            } ?? .empty
            return MetricSeries(key: key, range: range, startKey: startKey, endKey: endKey, points: points,
                                stats: stats, lastBucketPartial: intraday?.partial ?? false)
        }
        var points = BaselineRangeSeries.buckets(readings, from: startKey, to: endKey, bucket: range.bucket, calendar: calendar)
        if !bands.isEmpty {
            points = attachBands(points, bands: bands, bucket: range.bucket, calendar: calendar)
        }
        let stats = BaselineRangeSeries.stats(readings, from: startKey, to: endKey)
        let partial: Bool = {
            guard range.bucket != .day, let last = points.last,
                  let end = BaselineRangeSeries.bucketEnd(of: last.id, bucket: range.bucket, calendar: calendar) else { return false }
            return end > endKey
        }()
        return MetricSeries(key: key, range: range, startKey: startKey, endKey: endKey, points: points,
                            stats: stats, lastBucketPartial: partial)
    }

    /// The personal band per day for HRV (`Baselines.hrvCfg`) or resting HR (`restingHRCfg`): the fold
    /// of every night BEFORE each one (`nightlyStates`), the same band Trends and Progress draw. Empty for
    /// every other key.
    static func metricBands(key: MetricKey, days: [DailyMetric], endKey: String) -> [String: MetricBand] {
        let cfg: MetricCfg
        let value: (DailyMetric) -> Double?
        switch key {
        case .hrv: cfg = Baselines.hrvCfg; value = { $0.avgHrv }
        case .rhr: cfg = Baselines.restingHRCfg; value = { $0.restingHr.map(Double.init) }
        default: return [:]
        }
        var out: [String: MetricBand] = [:]
        for n in nightlyStates(upToToday: days.filter { $0.day <= endKey }, cfg: cfg, value: value) {
            guard let s = n.stateGoingIn, s.usable else { continue }
            let sigma = Baselines.sigma(s)
            out[n.day] = MetricBand(baseline: s.baseline, low: s.baseline - sigma, high: s.baseline + sigma)
        }
        return out
    }

    /// Day points take the band of their day; week / month points the mean band over the days of the
    /// bucket that have one. Points without a band keep nil.
    static func attachBands(_ points: [RangePoint], bands: [String: MetricBand], bucket: RangeBucket,
                            calendar: Calendar = .current) -> [RangePoint] {
        if bucket == .day {
            return points.map { p in
                var q = p; q.band = bands[p.id]; return q
            }
        }
        var grouped: [String: [MetricBand]] = [:]
        for (day, band) in bands {
            guard let start = BaselineRangeSeries.bucketStart(of: day, bucket: bucket, calendar: calendar) else { continue }
            grouped[start, default: []].append(band)
        }
        return points.map { p in
            var q = p
            if let list = grouped[p.id], !list.isEmpty {
                let n = Double(list.count)
                q.band = MetricBand(baseline: list.map(\.baseline).reduce(0, +) / n,
                                    low: list.map(\.low).reduce(0, +) / n,
                                    high: list.map(\.high).reduce(0, +) / n)
            }
            return q
        }
    }

    // MARK: Sentences

    /// The one context sentence under a range chart: the window's average, then the change against the
    /// period before, said once. "Averaged 64 ms over the last 7 days, 3 ms above the 7 days before." /
    /// "Averaged 64 ms over the last 7 days." / "No nights with HRV in the last 7 days." `format` prints
    /// a value in the metric's own spelling; `delta` prints a difference (defaults to `format` of the
    /// magnitude). Inside `steadyFraction` of the average the change reads "about the same as".
    ///
    /// On 1D the hero's "This day" and "Day before" cells already print both values, so the sentence
    /// carries only what they do not: the difference ("+1,240 vs the day before." / "About the same as
    /// the day before." / "No day before to compare."), never the day's number a second time.
    static func metricContext(series: MetricSeries, noun: String, unit: String,
                              format: (Double) -> String, delta: ((Double) -> String)? = nil) -> String {
        let s = series.stats
        let rangeWords = series.range.phrase
        guard let avg = s.average else {
            return series.range == .day ? "No \(noun) recorded for \(rangeWords)." : "No days with \(noun) in \(rangeWords)."
        }
        let unitSuffix = unit.isEmpty ? "" : " \(unit)"
        if series.range == .day {
            guard let change = s.change, let prev = s.previousAverage else { return "No day before to compare." }
            if abs(change) <= abs(prev) * metricSteadyFraction || abs(change) < metricSteadyFloor(unit: unit) {
                return "About the same as the day before."
            }
            let magnitude = delta?(abs(change)) ?? format(abs(change))
            let sign = change < 0 ? "\u{2212}" : "+"
            return "\(sign)\(magnitude)\(unitSuffix) vs the day before."
        }
        var out = "Averaged \(format(avg))\(unitSuffix) over \(rangeWords)"
        if let change = s.change, let prev = s.previousAverage {
            let before = series.range == .week ? "the 7 days before" : series.range == .fourWeeks ? "the 4 weeks before" : "the year before"
            let steady = abs(change) <= abs(prev) * metricSteadyFraction || abs(change) < metricSteadyFloor(unit: unit)
            if steady {
                out += ", about the same as \(before)"
            } else {
                let magnitude = delta?(abs(change)) ?? format(abs(change))
                out += ", \(magnitude)\(unitSuffix) \(change > 0 ? "above" : "below") \(before)"
            }
        }
        return out + "."
    }

    /// Inside this fraction of the previous average either way a change is "about the same".
    static let metricSteadyFraction = 0.02

    /// A change smaller than one printed unit is never called a change.
    private static func metricSteadyFloor(unit: String) -> Double { unit == "%" || unit == "ms" || unit == "bpm" ? 0.5 : 0 }

    /// "+4 ms" / "−3 bpm" for a change; "–" when there is none.
    static func metricChangeText(_ change: Double?, format: (Double) -> String, unit: String) -> String {
        guard let change else { return "–" }
        let sign = change < 0 ? "\u{2212}" : "+"
        return sign + format(abs(change)) + (unit.isEmpty ? "" : " \(unit)")
    }

    /// The whole-chart VoiceOver sentence: "HRV, last 7 days: 6 days from 58 to 71 ms; average 64 ms."
    /// For weekly points it also names the bucket: "52 weeks". Nothing shown on the chart is lost to the
    /// touch-only scrub.
    static func metricChartSummary(series: MetricSeries, name: String, unit: String, format: (Double) -> String) -> String {
        let s = series.stats
        let unitSuffix = unit.isEmpty ? "" : " \(unit)"
        var out = "\(name), \(series.range.subtitle.lowercased()): "
        if series.key == .heartRate, series.range == .day {
            guard let lo = s.min, let hi = s.max, let avg = s.average else { return out + "no heart-rate trace" }
            return out + "\(format(lo)) to \(format(hi))\(unitSuffix), average \(format(avg))\(unitSuffix)"
        }
        guard s.count > 0, let lo = s.min, let hi = s.max, let avg = s.average else { return out + "no days recorded" }
        let unitsWord = series.range.bucket == .week ? "\(series.points.count) weeks over \(s.count) days" : "\(s.count) days"
        out += "\(unitsWord) from \(format(lo)) to \(format(hi))\(unitSuffix); average \(format(avg))\(unitSuffix)"
        if let change = s.change {
            out += "; " + metricChangeText(change, format: format, unit: unit) + " vs the period before"
        }
        return out
    }
}

// MARK: - Repository accessor (@MainActor)

extension BaselineReadouts {

    /// The series for `key` over `range` ending on `endDay`, read through the funnel: daily columns from
    /// `repo.baselineDays`, steps through `stepReadings` (strap → phone → estimate), bedtime / wake from
    /// the Sleep tab's nights (`nights`, built here when not passed), the intraday-derived keys from
    /// `IntradayDayStore` (per-day facts, computed once per day and persisted; the year never re-reads
    /// 365 days of samples). `profile` supplies the max heart rate the Intensity classifier needs
    /// (`ProfileStore.effortHRmax`) behind the profile gate (`entered`, `ProfileSet`, or a max-HR
    /// override; `IntensityMinutes.mayScore`); without one the Intensity series is empty, as Home's card
    /// and the 1D week view say. `bandProvider` replaces `metricBands` (day key → band over the funnel's
    /// rows ending on `endDay`) when a screen has its own.
    @MainActor
    static func metricSeries(_ repo: Repository, profile: ProfileStore?, key: MetricKey, range: MetricRange,
                             endDay: String, nights: [SleepNight]? = nil, mode: BaselineDataSource = .current(),
                             entered: Bool = ProfileSet.current(),
                             bandProvider: (([DailyMetric], String) -> [String: MetricBand])? = nil,
                             calendar: Calendar = .current, now: Date = Date()) async -> MetricSeries {
        let days = days(repo, mode: mode)
        let (startKey, _) = metricWindow(range: range, endKey: endDay)
        // Readings reach back one more window so the "vs the period before" comparison has its days.
        let readFrom = Baselines.cutoffKey(todayKey: startKey, carryDays: range.days)

        if key == .heartRate, range == .day {
            let trace = await intradayHeartRate(repo, for: endDay, nights: nights, mode: mode, calendar: calendar, now: now)
            return metricSeries(key: key, range: range, endKey: endDay, readings: [], intraday: trace, calendar: calendar)
        }

        var stepReadings: [(day: String, value: Double)]? = nil
        var nightList: [SleepNight] = []
        var intraday = IntradayDayValues.none
        switch key {
        case .steps:
            stepReadings = await self.stepReadings(repo, from: readFrom, to: endDay, mode: mode)
        case .bedtime, .wake:
            if let nights {
                nightList = nights
            } else {
                let habitual = await repo.habitualMidsleepSec()
                let sessions = await self.nights(repo, mode: mode, now: now)
                nightList = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
            }
        case .stressAvg, .intensityMinutes, .heartRate:
            let keys = dayKeys(from: readFrom, to: endDay)
            let wantStress = key == .stressAvg && range != .year
            let records = await IntradayDayStore.shared.records(repo, profile: profile, days: keys, mode: mode,
                                                                entered: entered, computeStress: wantStress,
                                                                calendar: calendar, now: now)
            intraday = intradayValues(records)
        default:
            break
        }
        let readings = metricReadings(key: key, days: days, nights: nightList, stepReadings: stepReadings,
                                      intraday: intraday, calendar: calendar)
        let bands = bandProvider?(days, endDay) ?? metricBands(key: key, days: days, endKey: endDay)
        return metricSeries(key: key, range: range, endKey: endDay, readings: readings, bands: bands, calendar: calendar)
    }

    /// The intraday facts the range readings take from per-day records (pure): the Stress mean, the
    /// credited Intensity minutes of a day that is a reading (`IntradayDayRecord.recordedIntensity`:
    /// scored on a basis, never a `.needsAge` day's zeros, and recorded, never a day the strap was off
    /// or not yet paired; the predicate Trends' weeks count with) and the day's heart-rate low / mean /
    /// high.
    static func intradayValues(_ records: [String: IntradayDayRecord]) -> IntradayDayValues {
        var out = IntradayDayValues.none
        for (day, r) in records {
            if let s = r.stressMean { out.stressMean[day] = s }
            if r.recordedIntensity { out.intensityMinutes[day] = Double(r.credited) }
            if let lo = r.hrMin, let avg = r.hrAvg, let hi = r.hrMax { out.heartRate[day] = (lo, avg, hi) }
        }
        return out
    }

    /// Every day key from `from` to `to` inclusive (UTC key math), oldest first.
    static func dayKeys(from: String, to: String) -> [String] {
        let n = BaselineRangeSeries.dayCount(from: from, to: to)
        guard n > 0 else { return [] }
        return (0..<n).reversed().map { Baselines.cutoffKey(todayKey: to, carryDays: $0) }
    }
}
#endif
