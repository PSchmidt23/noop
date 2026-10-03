#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Ranges over the funnel: one metric key, one range (1D / 7D / 4W / 1Y), one pure builder. Every metric
// detail screen reads its points and its four hero numbers from `BaselineReadouts.metricSeries`, so a
// weekly average, a window's low and the "vs the period before" sentence are computed in ONE place over
// ONE table (`repo.baselineDays`, strap first). Daily-column metrics are a few linear passes over rows
// already in memory; the intraday-derived ones arrive as per-day facts, never from raw samples over
// weeks: Intensity minutes and heart rate from `IntradayDayStore`, Stress elevated hours from
// `StressDayStore`.

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

    /// How the window's days are grouped for `key`: a sum metric's (`MetricKey.sumsPerBucket`) 4W and 1Y
    /// are weekly TOTALS, one bar per Monday-to-Sunday week; every other key keeps `bucket`.
    func bucket(for key: MetricKey) -> RangeBucket {
        key.sumsPerBucket && sumWeeks != nil ? .week : bucket
    }

    /// The whole weeks a sum metric's window spans: 4W four Monday weeks, 1Y fifty-two, the last the week
    /// the selected day falls in. nil for 1D and 7D, which stay day windows.
    var sumWeeks: Int? {
        switch self {
        case .fourWeeks: return 4
        case .year: return 52
        case .day, .week: return nil
        }
    }

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

    /// Drawn as bars (a count or a load that adds up) rather than a line (a level). Stress is elevated
    /// HOURS a day, so bars too, never a line that reads like a score.
    var isCountLike: Bool {
        switch self {
        case .steps, .effort, .calories, .intensityMinutes, .sleepDuration, .stressAvg: return true
        default: return false
        }
    }

    /// Adds up over a week against a weekly goal instead of being averaged over the days that happened
    /// to record: the 7D / 4W / 1Y detail reads it as Monday-to-Sunday week TOTALS (`MetricSums`, judged
    /// against `MetricDetailSpec.goal`), a day the strap scored with nothing credited is a 0 and only a
    /// day with no data at all is missing. Intensity minutes only. Steps stay a per-day mean: their norm
    /// is per day (Home's tile judges a day against the 7-day average), so the mean of the recorded days
    /// is the number the person asks for, and a 1Y bar reads "average 8,412 over 6 days".
    var sumsPerBucket: Bool { self == .intensityMinutes }

    /// A clock time: bedtime is kept as minutes after the previous NOON (23:30 → 690, 00:30 → 750) and
    /// wake as minutes after midnight, so averages, lows and highs are plain arithmetic with no wrap.
    var isClockTime: Bool { self == .bedtime || self == .wake }

    /// Which way is good, for the chart's accessibility hint; nil where neither is.
    var higherIsBetter: Bool? {
        switch self {
        case .hrv, .readiness, .sleepDuration, .sleepEfficiency, .steps, .intensityMinutes: return true
        case .rhr: return false
        // Stress is elevated time against the person's own floor, never judged as good or bad.
        case .bedtime, .wake, .effort, .calories, .stressAvg, .heartRate: return nil
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
    /// A sum metric's weeks and days (`MetricKey.sumsPerBucket`); nil for every other key.
    var sums: MetricSums? = nil

    var isEmpty: Bool { points.isEmpty }

    /// How `points` are grouped: the range's bucket, or weeks for a sum metric's 4W / 1Y.
    var bucket: RangeBucket { range.bucket(for: key) }
}

// MARK: - Sum metrics: weeks against a goal

/// A target per period for a sum metric (`MetricKey.sumsPerBucket`, `MetricDetailSpec.goal`): Intensity
/// minutes' weekly goal (Settings › Profile › Intensity goal, `IntensityMinutes.goal()`, default 150).
struct MetricGoal: Equatable {
    enum Period: Equatable {
        case day, week
    }

    let value: Double
    let period: Period

    /// The goal for a Monday-to-Sunday week (a daily goal times seven).
    var perWeek: Double { period == .week ? value : value * 7 }
    /// The pace per day that reaches it: the 7D chart's dashed "daily pace" rule (a weekly goal over seven).
    var perDay: Double { period == .day ? value : value / 7 }
}

/// One Monday-to-Sunday week of a sum metric, cut at the window's end day: the week `BaselineRangeSeries
/// .weekTotals` builds for Home's Intensity card, Trends' Intensity card and the detail alike.
struct MetricWeekTotal: Identifiable, Equatable {
    /// The Monday's day key.
    let id: String
    /// Local midnight of the Monday.
    let date: Date
    /// Monday … Sunday: the day's value, nil for a day without a reading or after the end day. A day the
    /// strap scored with nothing credited is 0, never nil.
    let days: [Double?]
    /// The week's Sunday is after the end day.
    let inProgress: Bool

    var total: Double { days.compactMap { $0 }.reduce(0, +) }
    /// Days with a reading (a recorded zero included).
    var recordedDays: Int { days.compactMap { $0 }.count }
    /// Days with a value above zero.
    var activeDays: Int { days.filter { ($0 ?? 0) > 0 }.count }
    /// No day of the week has a reading: a missing week, drawn as no bar and judged by nobody.
    var hasData: Bool { recordedDays > 0 }

    /// The week's total reached the goal. A week still in progress counts once it has: a met goal stays met.
    func reached(_ goal: MetricGoal) -> Bool { total >= goal.perWeek }
}

/// A sum metric's window read as totals (`MetricKey.sumsPerBucket`): the whole weeks it covers and its
/// own days. Goal-free: the hero (`metricSumHero`) and the chart judge the weeks against the live goal.
struct MetricSums: Equatable {
    /// Whole Monday weeks, oldest first; the last is the week the end day falls in (in progress until its
    /// Sunday). 1D and 7D: that week alone (7D's "This week"); 4W four; 1Y fifty-two.
    let weeks: [MetricWeekTotal]
    /// Calendar days in the window (1 / 7 / 28 / 364) and those with a value above zero ("Days active").
    let windowDays: Int
    let activeDays: Int
    /// The end day's value (nil: no reading) and the day before's.
    let dayValue: Double?
    let dayBefore: Double?
    /// Intensity minutes only: raw moderate and vigorous minutes over the span the hero speaks for (1D the
    /// day, 7D this week, 4W / 1Y the weeks drawn) and the basis of the window's newest recorded day.
    var moderate: Int? = nil
    var vigorous: Int? = nil
    var basis: IntensityMinutes.Basis? = nil

    /// The week the end day falls in.
    var thisWeek: MetricWeekTotal? { weeks.last }
    /// Weeks with at least one reading: the denominator of "Weeks at goal".
    var weeksWithData: [MetricWeekTotal] { weeks.filter(\.hasData) }

    /// Weeks with data whose total reached the goal (the week in progress once it has).
    func weeksAtGoal(_ goal: MetricGoal) -> Int { weeksWithData.filter { $0.reached(goal) }.count }

    /// The mean total of the FINISHED weeks with data: a week still in progress would pull it down
    /// half-built, and a week with no reading at all is missing, not a zero. nil before one has ended.
    var averageWeek: Double? {
        let done = weeksWithData.filter { !$0.inProgress }
        guard !done.isEmpty else { return nil }
        return done.map(\.total).reduce(0, +) / Double(done.count)
    }
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

    /// The ONE week builder of a sum metric: whole Monday-to-Sunday weeks (ISO, local, `bucketStart`)
    /// from the week `from` falls in to the week `to` falls in, each day's value in its slot and the days
    /// after `to` left empty. A day without a reading is nil (missing), a recorded zero is 0; values that
    /// are not finite are skipped; a day listed twice keeps the last. Home's Intensity card
    /// (`BaselineReadouts.intensity`), Trends' weeks (`TrendsIntensity.build`) and the detail
    /// (`metricSeries`) all sum their weeks here, so the three cannot print different totals for one week.
    static func weekTotals(_ values: [MetricDayValue], from: String, to: String,
                           calendar: Calendar = .current) -> [MetricWeekTotal] {
        guard let firstMonday = bucketStart(of: from, bucket: .week, calendar: calendar),
              let lastMonday = bucketStart(of: to, bucket: .week, calendar: calendar),
              firstMonday <= lastMonday else { return [] }
        var byDay: [String: Double] = [:]
        for v in values where v.value.isFinite && v.day >= firstMonday && v.day <= to { byDay[v.day] = v.value }
        var out: [MetricWeekTotal] = []
        var monday = firstMonday
        while monday <= lastMonday, let date = BaselineReadouts.localMidnight(of: monday) {
            // Negative carryDays adds days: Monday … Sunday, then the next Monday.
            let keys = (0..<7).map { Baselines.cutoffKey(todayKey: monday, carryDays: -$0) }
            out.append(MetricWeekTotal(id: monday, date: date, days: keys.map { $0 <= to ? byDay[$0] : nil },
                                       inProgress: keys[6] > to))
            monday = Baselines.cutoffKey(todayKey: monday, carryDays: -7)
        }
        return out
    }
}

// MARK: - Readings per key (pure)

extension BaselineReadouts {

    /// Per-day facts the intraday stream yields, keyed by day: Stress elevated HOURS on the personal lens
    /// (`StressDayStore.elevatedHours`; never the 0–3 level), credited Intensity minutes, and the day's
    /// heart-rate low / mean / high (`IntradayDayStore`). Any map may be empty.
    struct IntradayDayValues {
        var stressElevatedHours: [String: Double] = [:]
        var intensityMinutes: [String: Double] = [:]
        /// The same Intensity days' raw moderate and vigorous minutes and the basis they were scored on
        /// (the detail's split and basis lines).
        var intensityParts: [String: (moderate: Int, vigorous: Int)] = [:]
        var intensityBasis: [String: IntensityMinutes.Basis] = [:]
        var heartRate: [String: (min: Double, avg: Double, max: Double)] = [:]

        static let none = IntradayDayValues()
    }

    /// The `(day, value)` readings behind a key, oldest → newest, from the funnel's `days`, the Sleep
    /// tab's `nights` (bedtime / wake; `.dailyMetric` nights carry no times) and the intraday facts.
    /// `stepReadings` (`BaselineReadouts.stepReadings`, the strap → phone → estimate resolution) replaces
    /// the funnel's `steps` column when given; `calorieReadings` (`BaselineReadouts.calorieReadings`, the
    /// resting + active figure Home's and Trends' Calories cards print) replaces the funnel's
    /// `active_kcal` column the same way, and the repository accessor always passes them. Efficiency is a
    /// percent (0–100); bedtime and wake are clock minutes (`MetricKey.isClockTime`).
    static func metricReadings(key: MetricKey, days: [DailyMetric], nights: [SleepNight] = [],
                               stepReadings: [(day: String, value: Double)]? = nil,
                               calorieReadings: [(day: String, value: Double)]? = nil,
                               intraday: IntradayDayValues = .none, calendar: Calendar = .current) -> [MetricDayValue] {
        switch key {
        case .calories:
            let readings = calorieReadings ?? BaselineDays.series(key: key.seriesKey ?? "", days: days)
            return readings.filter { $0.value.isFinite && $0.value >= 0 }.sorted { $0.day < $1.day }
                .map { MetricDayValue(day: $0.day, value: $0.value) }
        case .hrv, .rhr, .readiness, .sleepDuration, .effort:
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
            return intraday.stressElevatedHours.map { MetricDayValue(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
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

    /// The window for `key`: a sum metric's 4W and 1Y are whole weeks (`MetricRange.sumWeeks`), from the
    /// Monday three or fifty-one weeks before the end day's own; every other window as above.
    static func metricWindow(key: MetricKey, range: MetricRange, endKey: String,
                             calendar: Calendar = .current) -> (startKey: String, endKey: String) {
        guard key.sumsPerBucket, let weeks = range.sumWeeks,
              let monday = BaselineRangeSeries.bucketStart(of: endKey, bucket: .week, calendar: calendar) else {
            return metricWindow(range: range, endKey: endKey)
        }
        return (Baselines.cutoffKey(todayKey: monday, carryDays: 7 * (weeks - 1)), endKey)
    }

    /// The series for `key` over `range` ending on `endKey`, from readings already resolved
    /// (`metricReadings`). `bands` (day key → band, `metricBands`) is attached to day points by key and to
    /// week points as the mean band of their days. `intraday` supplies the 1D heart-rate trace: its
    /// points become the series (one per sample) and its low / mean / high the stats. A sum metric
    /// (`MetricKey.sumsPerBucket`) also carries `sums` (`metricSums`; `dayFacts` gives Intensity minutes'
    /// split and basis) and on 4W / 1Y its points are the weeks' TOTALS, one per week with data.
    static func metricSeries(key: MetricKey, range: MetricRange, endKey: String, readings: [MetricDayValue],
                             bands: [String: MetricBand] = [:], intraday: IntradayHeartRate? = nil,
                             dayFacts: IntradayDayValues = .none,
                             calendar: Calendar = .current) -> MetricSeries {
        let (startKey, _) = metricWindow(key: key, range: range, endKey: endKey, calendar: calendar)
        if key.sumsPerBucket {
            return sumSeries(key: key, range: range, startKey: startKey, endKey: endKey, readings: readings,
                             dayFacts: dayFacts, calendar: calendar)
        }
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

    /// A sum metric's series: 1D / 7D keep their daily points (each bar a day's credited minutes, a
    /// recorded zero a zero), 4W / 1Y take one point per WEEK with data at the week's total (`n` its
    /// recorded days), and `sums` carries the weeks, the window's active days, the day and the day
    /// before, and Intensity minutes' split and basis. The stats stay over daily values (the chart's
    /// VoiceOver sentence reads none of them as a week).
    private static func sumSeries(key: MetricKey, range: MetricRange, startKey: String, endKey: String,
                                  readings: [MetricDayValue], dayFacts: IntradayDayValues,
                                  calendar: Calendar) -> MetricSeries {
        // 1D and 7D speak for the end day's own week ("This week"); 4W and 1Y for every week they draw.
        let weeksFrom = range.sumWeeks != nil ? startKey : endKey
        let weeks = BaselineRangeSeries.weekTotals(readings, from: weeksFrom, to: endKey, calendar: calendar)
        let points: [RangePoint]
        if range.bucket(for: key) == .week {
            points = weeks.filter(\.hasData).map { w in
                RangePoint(id: w.id, date: w.date, value: w.total, min: nil, max: nil, n: w.recordedDays)
            }
        } else {
            points = BaselineRangeSeries.buckets(readings, from: startKey, to: endKey, bucket: .day, calendar: calendar)
        }
        let inWindow = readings.filter { $0.day >= startKey && $0.day <= endKey && $0.value.isFinite }
        let dayBeforeKey = Baselines.cutoffKey(todayKey: endKey, carryDays: 1)
        var sums = MetricSums(weeks: weeks,
                              windowDays: BaselineRangeSeries.dayCount(from: startKey, to: endKey),
                              activeDays: Set(inWindow.filter { $0.value > 0 }.map(\.day)).count,
                              dayValue: readings.last { $0.day == endKey && $0.value.isFinite }?.value,
                              dayBefore: readings.last { $0.day == dayBeforeKey && $0.value.isFinite }?.value)
        if key == .intensityMinutes {
            let splitFrom: String
            switch range {
            case .day: splitFrom = endKey
            case .week: splitFrom = weeks.last?.id ?? endKey
            case .fourWeeks, .year: splitFrom = startKey
            }
            let split = dayFacts.intensityParts.filter { $0.key >= splitFrom && $0.key <= endKey }.values
            sums.moderate = split.reduce(0) { $0 + $1.moderate }
            sums.vigorous = split.reduce(0) { $0 + $1.vigorous }
            sums.basis = dayFacts.intensityBasis.filter { $0.key >= startKey && $0.key <= endKey }
                .max { $0.key < $1.key }?.value
        }
        let last = weeks.last
        return MetricSeries(key: key, range: range, startKey: startKey, endKey: endKey, points: points,
                            stats: BaselineRangeSeries.stats(readings, from: startKey, to: endKey),
                            lastBucketPartial: range.sumWeeks != nil && (last?.inProgress ?? false) && (last?.hasData ?? false),
                            sums: sums)
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
    private static func metricSteadyFloor(unit: String) -> Double {
        unit == "%" || unit == "ms" || unit == "bpm" || unit == "h" ? 0.5 : 0
    }

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

    // MARK: Sum metrics' hero

    /// The hero of a sum metric's detail (`MetricKey.sumsPerBucket`): the cells, ONE sentence under them
    /// and the basis footnote. What a week of Intensity minutes is judged by is its total against the
    /// weekly goal, so no range prints a mean of the days that happened to record.
    struct MetricSumHero: Equatable {
        struct Cell: Equatable {
            let label: String
            let value: String
            let unit: String?
        }

        let cells: [Cell]
        /// Under the cells (secondary): the split, the zero day, or why the window is empty.
        let sentence: String
        /// What the minutes were scored on (tertiary); nil on 1D, whose week card prints it.
        let footnote: String?

        /// The cells as one line: "This week 112 of 150 min · Days active 4 of 7".
        var cellsText: String {
            cells.map { [$0.label, $0.value, $0.unit].compactMap { $0 }.joined(separator: " ") }.joined(separator: " · ")
        }
    }

    /// The sum hero per range (`series.sums`; `goal` is the live goal, `isToday` whether the end day is today):
    ///   • 1D: "This day" / "Day before". A day the strap scored with nothing credited is "0" with "No
    ///     moderate or vigorous minutes today." (Home's card says "0 min today"); today counts from 0 like
    ///     Home's card even before its first minute is banked; only a finished day with no heart rate (and
    ///     no workout credit) at all is "–". A credited day gets the change against the day before.
    ///   • 7D: "This week 112 of 150 min" (Monday → the end day, the number Home's track and Trends' card
    ///     print) and "Days active 4 of 7" (days of the seven drawn with a minute), the week's split.
    ///   • 4W / 1Y: "Weeks at goal 2 of 4" (weeks with data whose total reached the goal) and "Average
    ///     week 131 min" (finished weeks with data), the split over the weeks drawn.
    static func metricSumHero(series: MetricSeries, goal: MetricGoal?, noun: String, unit: String,
                              format: (Double) -> String, isToday: Bool) -> MetricSumHero {
        let u = unit.isEmpty ? nil : unit
        let intensity = series.key == .intensityMinutes
        guard let sums = series.sums else { return MetricSumHero(cells: [], sentence: "", footnote: nil) }
        if series.range == .day {
            let value = sums.dayValue ?? (isToday ? 0 : nil)
            // A dash stands alone: "– min" reads as a number that failed to load.
            let cells = [MetricSumHero.Cell(label: "This day", value: value.map(format) ?? "–", unit: value == nil ? nil : u),
                         MetricSumHero.Cell(label: "Day before", value: sums.dayBefore.map(format) ?? "–",
                                            unit: sums.dayBefore == nil ? nil : u)]
            let sentence: String
            if value == nil {
                sentence = intensity ? "No heart rate recorded on this day." : "No \(noun) recorded for this day."
            } else if value == 0 {
                let what = intensity ? "moderate or vigorous minutes" : noun
                sentence = isToday ? "No \(what) today." : "No \(what) on this day."
            } else {
                sentence = metricContext(series: series, noun: noun, unit: unit, format: format)
            }
            return MetricSumHero(cells: cells, sentence: sentence, footnote: nil)
        }
        // A window with no reading at all: the one sentence, no cells of dashes.
        guard !series.isEmpty, let week = sums.thisWeek else {
            return MetricSumHero(cells: [], sentence: metricContext(series: series, noun: noun, unit: unit, format: format),
                                 footnote: nil)
        }
        let unitSuffix = u.map { " \($0)" } ?? ""
        var cells: [MetricSumHero.Cell] = []
        if series.range == .week {
            cells.append(.init(label: "This week", value: format(week.total),
                               unit: goal.map { "of \(format($0.perWeek))\(unitSuffix)" } ?? u))
            cells.append(.init(label: "Days active", value: "\(sums.activeDays)", unit: "of \(sums.windowDays)"))
        } else {
            if let goal {
                cells.append(.init(label: "Weeks at goal", value: "\(sums.weeksAtGoal(goal))",
                                   unit: "of \(sums.weeksWithData.count)"))
            }
            cells.append(.init(label: "Average week", value: sums.averageWeek.map(format) ?? "–", unit: u))
        }
        return MetricSumHero(cells: cells, sentence: intensity ? intensitySplitSentence(series) : "",
                             footnote: intensity ? sums.basis?.caption : nil)
    }

    /// The split under a range's hero: this week's on 7D ("38 moderate · 37 vigorous, counted double"),
    /// the weeks with data on 4W / 1Y ("Over 18 weeks: …", the denominator "Weeks at goal" prints: a
    /// week without a reading adds nothing and is not counted), or that there were none.
    private static func intensitySplitSentence(_ series: MetricSeries) -> String {
        let m = series.sums?.moderate ?? 0, v = series.sums?.vigorous ?? 0
        let n = series.sums?.weeksWithData.count ?? 0
        if series.range == .week {
            return m + v > 0 ? IntensityMinutes.splitText(moderate: m, vigorous: v) : "No moderate or vigorous minutes this week."
        }
        let weeks = "\(n) week\(n == 1 ? "" : "s")"
        return m + v > 0 ? "Over \(weeks): " + IntensityMinutes.splitText(moderate: m, vigorous: v)
                         : "No moderate or vigorous minutes over \(weeks)."
    }

    /// The sum chart's one VoiceOver sentence. 7D: "Intensity minutes, last 7 days: 5 days recorded, 4
    /// active, highest 40 min; this week 112 of 150 min; daily pace 21 min." Weeks: "Intensity minutes,
    /// last 4 weeks: 4 weeks recorded, 2 at the goal of 150 min; average week 131 min; this week 75 min so far."
    static func metricSumChartSummary(series: MetricSeries, goal: MetricGoal?, name: String, unit: String,
                                      format: (Double) -> String) -> String {
        guard let sums = series.sums else { return metricChartSummary(series: series, name: name, unit: unit, format: format) }
        let u = unit.isEmpty ? "" : " \(unit)"
        var out = "\(name), \(series.range.subtitle.lowercased()): "
        if series.bucket == .week {
            let n = sums.weeksWithData.count
            out += "\(n) week\(n == 1 ? "" : "s") recorded"
            if let goal { out += ", \(sums.weeksAtGoal(goal)) at the goal of \(format(goal.perWeek))\(u)" }
            if let avg = sums.averageWeek { out += "; average week \(format(avg))\(u)" }
            if let w = sums.thisWeek, w.inProgress { out += "; this week \(format(w.total))\(u) so far" }
        } else {
            let n = series.stats.count
            out += "\(n) day\(n == 1 ? "" : "s") recorded, \(sums.activeDays) active"
            if let hi = series.stats.max, hi > 0 { out += ", highest \(format(hi))\(u)" }
            if let w = sums.thisWeek {
                out += "; this week \(format(w.total))" + (goal.map { " of \(format($0.perWeek))" } ?? "") + u
            }
            if let goal { out += "; daily pace \(format(goal.perDay))\(u)" }
        }
        return out + "."
    }
}

// MARK: - Repository accessor (@MainActor)

extension BaselineReadouts {

    /// The series for `key` over `range` ending on `endDay`, read through the funnel: daily columns from
    /// `repo.baselineDays`, steps through `stepReadings` (strap → phone → estimate), Calories through
    /// `calorieReadings` (the resting + active figure Home's and Trends' cards print), bedtime / wake from
    /// the Sleep tab's nights (`nights`, built here when not passed), Intensity minutes and heart rate
    /// from `IntradayDayStore` and Stress elevated hours from `StressDayStore` (per-day facts, computed
    /// once per day and persisted; the year never re-reads 365 days of samples). `profile` supplies the max heart rate the Intensity classifier needs
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
        let (startKey, _) = metricWindow(key: key, range: range, endKey: endDay, calendar: calendar)
        // Readings reach back one more window so the "vs the period before" comparison has its days; a
        // sum metric's weekly windows compare nothing, so they read from their first Monday; its 1D and
        // 7D reach back to the day before and to the Monday of the end day's week ("This week").
        var readFrom = key.sumsPerBucket && range.sumWeeks != nil
            ? startKey
            : Baselines.cutoffKey(todayKey: startKey, carryDays: range.days)
        if key.sumsPerBucket, let monday = BaselineRangeSeries.bucketStart(of: endDay, bucket: .week, calendar: calendar) {
            readFrom = min(readFrom, monday)
        }

        if key == .heartRate, range == .day {
            let trace = await intradayHeartRate(repo, for: endDay, nights: nights, mode: mode, calendar: calendar, now: now)
            return metricSeries(key: key, range: range, endKey: endDay, readings: [], intraday: trace, calendar: calendar)
        }

        var stepReadings: [(day: String, value: Double)]? = nil
        var calorieReadings: [(day: String, value: Double)]? = nil
        var nightList: [SleepNight] = []
        var intraday = IntradayDayValues.none
        switch key {
        case .steps:
            stepReadings = await self.stepReadings(repo, from: readFrom, to: endDay, mode: mode)
        case .calories:
            // The figure Home's card and Trends' card print (`caloriesDay`: resting + active, or active
            // alone while no age and sex exist), never the funnel's `active_kcal` column.
            calorieReadings = await self.calorieReadings(repo, profile: profile, from: readFrom, to: endDay,
                                                         mode: mode, entered: entered, calendar: calendar, now: now)
        case .bedtime, .wake:
            if let nights {
                nightList = nights
            } else {
                let habitual = await repo.habitualMidsleepSec()
                let sessions = await self.nights(repo, mode: mode, now: now)
                nightList = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
            }
        case .stressAvg:
            // Elevated HOURS per day, never the 0–3 level: each past day's facts on its own lens from
            // `StressDayStore` (scored once and kept, the records the card's 14-day typical reads; 1Y
            // reads only days already scored, never a year of raw streams), today's through NOOP's
            // `StressDayCurve.today` as on Home. Only days that may be totalled are readings.
            let keys = dayKeys(from: readFrom, to: endDay)
            var facts = await StressDayStore.shared.facts(repo, days: keys, scoreMissing: range != .year,
                                                          calendar: calendar, now: now)
            let todayKey = Repository.localDayKey(now)
            if keys.contains(todayKey),
               let today = await stressDay(repo, for: todayKey, now: now, calendar: calendar, includeTypical: false) {
                facts[todayKey] = StressDayFacts(today)
            }
            intraday.stressElevatedHours = StressDayStore.elevatedHours(facts)
        case .intensityMinutes, .heartRate:
            let keys = dayKeys(from: readFrom, to: endDay)
            let records = await IntradayDayStore.shared.records(repo, profile: profile, days: keys, mode: mode,
                                                                entered: entered, calendar: calendar, now: now)
            intraday = intradayValues(records)
        default:
            break
        }
        let readings = metricReadings(key: key, days: days, nights: nightList, stepReadings: stepReadings,
                                      calorieReadings: calorieReadings, intraday: intraday, calendar: calendar)
        let bands = bandProvider?(days, endDay) ?? metricBands(key: key, days: days, endKey: endDay)
        return metricSeries(key: key, range: range, endKey: endDay, readings: readings, bands: bands,
                            dayFacts: intraday, calendar: calendar)
    }

    /// The intraday facts the range readings take from per-day records (pure): the credited Intensity
    /// minutes of a day that is a reading (`IntradayDayRecord.recordedIntensity`: scored on a basis,
    /// never a `.needsAge` day's zeros, and recorded, never a day the strap was off or not yet paired;
    /// the predicate Trends' weeks count with) and the day's heart-rate low / mean / high. Stress hours
    /// come from `StressDayStore`, not from these records.
    static func intradayValues(_ records: [String: IntradayDayRecord]) -> IntradayDayValues {
        var out = IntradayDayValues.none
        for (day, r) in records {
            if r.recordedIntensity {
                out.intensityMinutes[day] = Double(r.credited)
                out.intensityParts[day] = (r.moderateMin, r.vigorousMin)
                out.intensityBasis[day] = r.basis
            }
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
