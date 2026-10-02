#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

/// 7 / 30 / 90 day window on the Trends tab. Raw value = number of days (what AppStorage persists).
enum TrendsRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { "\(rawValue)D" }
    var subtitle: String { "Last \(rawValue) days" }
    /// Nights compared at each end of the range for the trend pill (first vs last).
    var trendWindow: Int { self == .week ? 3 : 7 }

    static func resolve(_ raw: Int) -> TrendsRange { TrendsRange(rawValue: raw) ?? .month }

    /// The detail range a card header opens on (`MetricDetailScreen`), the detail's window nearest the
    /// picker's: 7D → 7D, 30D → 4W (daily points over 28 days), 90D → 1Y (the detail has no quarter;
    /// the year keeps the weekly points a quarter view is after).
    var detailRange: MetricRange {
        switch self {
        case .week: return .week
        case .month: return .fourWeeks
        case .quarter: return .year
        }
    }
}

/// Cached "yyyy-MM-dd" parsers. `local` places a night on the phone's calendar day (chart x-axis);
/// `utc` mirrors the formatter `Baselines.foldHistory(_:dayKeys:cfg:)` uses to apply the recalibration epoch.
enum TrendsDayKey {
    static let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let utc: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ key: String) -> Date? { local.date(from: key) }

    /// True when `day` is dated before the recalibration `epoch` (seconds), by the same UTC day-start
    /// parse and strict `<` the engine's `foldHistory(_:dayKeys:cfg:baselineEpoch:)` applies. An
    /// epoch of 0 (no recalibration) or an unparseable key never drops a night.
    static func isBeforeEpoch(_ day: String, epoch: Double) -> Bool {
        guard epoch > 0, let d = utc.date(from: day) else { return false }
        return d.timeIntervalSince1970 < epoch
    }
}

/// Small formatting helpers shared by the Trends cards.
enum TrendsFormat {
    static func whole(_ v: Double) -> String { String(Int(v.rounded())) }

    /// "+4 ms" / "−3 bpm" (typographic minus).
    static func signed(_ delta: Double, unit: String) -> String {
        let n = Int(abs(delta).rounded())
        let sign = delta < 0 ? "−" : "+"
        return "\(sign)\(n) \(unit)"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Everything the Trends screen draws, computed once per (days, range) in `build`. Pure and synchronous:
/// a few linear passes over `repo.baselineDays`, cheap enough for the main actor.
struct TrendsSeries {
    /// A nightly metric drawn over its time-varying personal band (HRV, resting HR).
    struct BandMetric {
        let points: [BandPoint]
        /// The baseline the newest night in history was judged against: the fold of every night before
        /// it, from `BaselineReadouts.latestNight`, the same state the Today hero reads, so the "Baseline"
        /// cell, the band at the chart's last point and Today's tile show one number and one count.
        let current: BaselineState
        /// Mean of the valid nights in range.
        let average: Double?
        /// Last-window mean minus first-window mean (nil until both ends have ≥2 nights).
        let trend: Double?
        /// Y-axis span: values and band edges with ~12% padding, snapped to a sensible step (5 ms / 2 bpm).
        let yDomain: ClosedRange<Double>
    }

    struct BarMetric {
        let bars: [BaselineBarChart.Bar]
        let average: Double?
    }

    /// Effort bars under the Readiness line, one point per day in range that has either. A point holds
    /// that morning's score and the effort that followed it; the two are drawn on one 0–100 axis (the
    /// funnel's `strain` and `recovery`) but are different scales (a log of training load against a
    /// z-composite anchored near 58), so they are never compared number against number. The one
    /// relation the engine itself reads is lagged, effort on day D into the score of D+1 (NOOP's
    /// `RecoveryScorer` takes `priorDayEffort`), and that is what `morningAfter` states.
    struct EffortReadiness {
        let points: [EffortReadinessPoint]
        /// Mean effort over the days that recorded one (the same number as `effort.average`).
        let effortAverage: Double?
        /// Mean readiness over the days that have a score.
        let readinessAverage: Double?
        let effortDays: Int
        let readinessDays: Int
        /// In-range days with an effort and a readiness score the next morning (the pairs
        /// `morningAfter` reads; the range's last day never pairs, its next morning has not come).
        let nextMorningPairs: Int
        /// nil until `minMorningAfterPairs` pairs exist.
        let morningAfter: MorningAfter?
    }

    /// Readiness the morning after the range's hardest days against the morning after the others.
    struct MorningAfter {
        /// The top `hardDays` paired days by effort (`maxHardDays` at most, a third of the pairs).
        let hardDays: Int
        /// Mean next-morning readiness after those days …
        let afterHard: Double
        /// … and after every other paired day.
        let afterOthers: Double
    }

    /// Pairs before the morning-after sentence is said: two hard days against four others at the least.
    static let minMorningAfterPairs = 6
    static let maxHardDays = 5

    let range: TrendsRange
    /// Nights anywhere in history carrying HRV, resting HR or sleep — the empty-state gate.
    let totalNights: Int
    let hrv: BandMetric
    let restingHr: BandMetric
    let sleep: BarMetric
    let sleepNights: Int
    let sleepNights7h: Int
    let effort: BarMetric
    let effortPeak: BaselineBarChart.Bar?
    let effortReadiness: EffortReadiness
    /// Daily steps in range with their mean; `stepsAboveAverage` of `stepsDays` beat that mean.
    let steps: BarMetric
    let stepsDays: Int
    let stepsAboveAverage: Int
    /// False when no day in the quarter behind `now` recorded steps (a 4.0 without phone steps, a CSV
    /// import): the screen then leaves the Steps card out instead of showing an empty one forever.
    let hasSteps: Bool

    /// The window's first and last day keys (local calendar days, `range.days` long, ending on `now`).
    static func window(range: TrendsRange, now: Date = Date()) -> (startKey: String, todayKey: String) {
        let startDate = Calendar.current.date(byAdding: .day, value: -(range.days - 1), to: now) ?? now
        return (Repository.localDayKey(startDate), Repository.localDayKey(now))
    }

    /// The farthest back any range reaches: the `hasSteps` gate looks over this many days.
    static let stepsLookbackDays = TrendsRange.quarter.days

    /// `stepReadings` are `(day, steps)` pairs from `BaselineReadouts.stepReadings` (the strap's counter,
    /// then the phone's, then the strap's estimate), covering at least `stepsLookbackDays` before `now`;
    /// nil falls back to the funnel table's `steps` column (previews, tests).
    static func build(days: [DailyMetric], range: TrendsRange,
                      stepReadings: [(day: String, value: Double)]? = nil, now: Date = Date()) -> TrendsSeries {
        let (startKey, todayKey) = window(range: range, now: now)

        // `days` is oldest → newest; ISO keys compare chronologically.
        let upToToday = days.filter { $0.day <= todayKey }
        let inRange = upToToday.filter { $0.day >= startKey }

        let totalNights = upToToday.reduce(into: 0) { acc, d in
            if d.avgHrv != nil || d.restingHr != nil || d.totalSleepMin != nil { acc += 1 }
        }

        let hrv = bandMetric(upToToday: upToToday, startKey: startKey,
                             cfg: Baselines.hrvCfg, window: range.trendWindow, step: 5) { $0.avgHrv }
        let rhr = bandMetric(upToToday: upToToday, startKey: startKey,
                             cfg: Baselines.restingHRCfg, window: range.trendWindow, step: 2) {
            $0.restingHr.map { Double($0) }
        }

        // Sleep duration (hours) per night, plus how many nights reached 7h.
        var sleepBars: [BaselineBarChart.Bar] = []
        var sleep7h = 0
        for d in inRange {
            guard let m = d.totalSleepMin, m > 0, let date = TrendsDayKey.date(d.day) else { continue }
            sleepBars.append(.init(id: d.day, date: date, value: m / 60))
            if m >= 7 * 60 { sleep7h += 1 }
        }
        let sleep = BarMetric(bars: sleepBars, average: mean(sleepBars.map(\.value)))

        // Daily effort (0–100).
        var effortBars: [BaselineBarChart.Bar] = []
        for d in inRange {
            guard let s = d.strain, let date = TrendsDayKey.date(d.day) else { continue }
            effortBars.append(.init(id: d.day, date: date, value: s))
        }
        let effort = BarMetric(bars: effortBars, average: mean(effortBars.map(\.value)))
        let peak = effortBars.max { $0.value < $1.value }

        let effortReadiness = effortReadiness(inRange: inRange, effortAverage: effort.average)
        let stepsStart = Baselines.cutoffKey(todayKey: todayKey, carryDays: stepsLookbackDays - 1)
        let steps = stepsMetric(readings: stepReadings ?? BaselineDays.series(key: "steps", days: upToToday),
                                startKey: startKey, todayKey: todayKey, lookbackKey: stepsStart)

        return TrendsSeries(range: range, totalNights: totalNights, hrv: hrv, restingHr: rhr,
                            sleep: sleep, sleepNights: sleepBars.count, sleepNights7h: sleep7h,
                            effort: effort, effortPeak: peak, effortReadiness: effortReadiness,
                            steps: steps.metric, stepsDays: steps.metric.bars.count,
                            stepsAboveAverage: steps.aboveAverage, hasSteps: steps.hasAny)
    }

    // MARK: - Effort and Readiness

    /// One point per in-range day with effort or a readiness score; the averages count only the days
    /// that have each. The morning-after pairs are built inside the range too: the day after an
    /// in-range day is either in range or tomorrow, which no row carries yet.
    static func effortReadiness(inRange: [DailyMetric], effortAverage: Double?) -> EffortReadiness {
        var points: [EffortReadinessPoint] = []
        var readinessValues: [Double] = []
        var effortDays = 0
        var recoveryByDay: [String: Double] = [:]
        for d in inRange {
            guard d.strain != nil || d.recovery != nil, let date = TrendsDayKey.date(d.day) else { continue }
            points.append(EffortReadinessPoint(id: d.day, date: date, effort: d.strain, readiness: d.recovery))
            if d.strain != nil { effortDays += 1 }
            if let r = d.recovery {
                readinessValues.append(r)
                recoveryByDay[d.day] = r
            }
        }

        // Effort on D with the score of D+1 (`cutoffKey` with a negative carry is "the day after").
        var pairs: [(day: String, effort: Double, nextMorning: Double)] = []
        for d in inRange {
            guard let e = d.strain,
                  let next = recoveryByDay[Baselines.cutoffKey(todayKey: d.day, carryDays: -1)] else { continue }
            pairs.append((d.day, e, next))
        }

        return EffortReadiness(points: points, effortAverage: effortAverage, readinessAverage: mean(readinessValues),
                               effortDays: effortDays, readinessDays: readinessValues.count,
                               nextMorningPairs: pairs.count, morningAfter: morningAfter(pairs: pairs))
    }

    /// The hardest third of the pairs (at most `maxHardDays`, ties to the earlier day) against the rest;
    /// nil below `minMorningAfterPairs` pairs, so a two-day week never reads as a pattern.
    static func morningAfter(pairs: [(day: String, effort: Double, nextMorning: Double)]) -> MorningAfter? {
        guard pairs.count >= minMorningAfterPairs else { return nil }
        let hardCount = min(maxHardDays, pairs.count / 3)
        let byEffort = pairs.sorted { $0.effort != $1.effort ? $0.effort > $1.effort : $0.day < $1.day }
        guard let hard = mean(byEffort.prefix(hardCount).map(\.nextMorning)),
              let others = mean(byEffort.dropFirst(hardCount).map(\.nextMorning)) else { return nil }
        return MorningAfter(hardDays: hardCount, afterHard: hard, afterOthers: others)
    }

    // MARK: - Steps

    /// Daily step bars over `startKey`…`todayKey` with their mean; a zero is kept (a day the strap
    /// counted nothing is still a count). `hasAny` looks back to `lookbackKey` so a quiet week inside
    /// a recorded quarter keeps the card (empty text) while a history with no steps at all drops it.
    static func stepsMetric(readings: [(day: String, value: Double)], startKey: String, todayKey: String,
                            lookbackKey: String) -> (metric: BarMetric, aboveAverage: Int, hasAny: Bool) {
        var byDay: [String: Double] = [:]
        var hasAny = false
        for r in readings where r.value.isFinite && r.value >= 0 && r.day <= todayKey {
            if r.day >= lookbackKey { hasAny = true }
            if r.day >= startKey { byDay[r.day] = r.value }
        }
        var bars: [BaselineBarChart.Bar] = []
        for (day, value) in byDay.sorted(by: { $0.key < $1.key }) {
            guard let date = TrendsDayKey.date(day) else { continue }
            bars.append(.init(id: day, date: date, value: value))
        }
        let average = mean(bars.map(\.value))
        let above = average.map { avg in bars.filter { $0.value > avg }.count } ?? 0
        return (BarMetric(bars: bars, average: average), above, hasAny)
    }

    // MARK: - Band metrics

    /// The band drawn at night N is the baseline ± σ *going into* that night (the state after folding
    /// every night before it), so "inside / outside the band" matches what the Today screen said that
    /// morning. The fold itself is `BaselineReadouts.nightlyStates`, the one walk the Progress screen
    /// draws its baseline line from, so the two screens cannot disagree about a night's band. Nights
    /// dated before the recalibration epoch are dropped exactly as `Baselines.foldHistory(_:dayKeys:cfg:)`
    /// drops them.
    private static func bandMetric(upToToday: [DailyMetric], startKey: String,
                                   cfg: MetricCfg, window: Int, step: Double,
                                   value: (DailyMetric) -> Double?) -> BandMetric {
        let walk = BaselineReadouts.nightlyStates(upToToday: upToToday, cfg: cfg, value: value)

        var points: [BandPoint] = []
        var values: [Double] = []
        for n in walk where n.day >= startKey {
            guard let v = n.validValue, let date = TrendsDayKey.date(n.day) else { continue }
            var baseline: Double? = nil
            var low: Double? = nil
            var high: Double? = nil
            if let s = n.stateGoingIn, s.usable {
                let sigma = Baselines.sigma(s)
                baseline = s.baseline
                low = s.baseline - sigma
                high = s.baseline + sigma
            }
            points.append(BandPoint(id: n.day, date: date, value: v, baseline: baseline, low: low, high: high))
            values.append(v)
        }

        let current = BaselineReadouts.latestNight(upToToday: upToToday, cfg: cfg, value: value).state
        return BandMetric(points: points, current: current, average: mean(values),
                          trend: trend(values, window: window), yDomain: yDomain(points: points, step: step))
    }

    /// min(values, band lows) … max(values, band highs), padded ~12% and snapped outward to `step`,
    /// never below zero. Keeps a 50–70 bpm line from being flattened against a wide automatic axis.
    static func yDomain(points: [BandPoint], step: Double) -> ClosedRange<Double> {
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for p in points {
            lo = min(lo, p.value, p.low ?? p.value)
            hi = max(hi, p.value, p.high ?? p.value)
        }
        guard lo <= hi else { return 0...step }
        let pad = max(hi - lo, step) * 0.12
        let floorLo = max(0, (lo - pad) / step).rounded(.down) * step
        let ceilHi = ((hi + pad) / step).rounded(.up) * step
        return floorLo...max(ceilHi, floorLo + step)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Mean of the last `window` valid nights minus the mean of the first `window`. The window shrinks to
    /// half the available nights so a sparse range still reads, and gives up below 2 nights per end.
    static func trend(_ values: [Double], window: Int) -> Double? {
        let w = min(window, values.count / 2)
        guard w >= 2 else { return nil }
        guard let first = mean(Array(values.prefix(w))), let last = mean(Array(values.suffix(w))) else { return nil }
        return last - first
    }
}

// MARK: - Intensity minutes

/// Intensity minutes on the Trends tab: one bar per ISO week (Monday → Sunday, local, the same seven
/// days `IntensityMinutes.weekDays` sums and the detail's 1Y points use) against the weekly goal. The
/// first bar is the week the range's first day falls in, drawn WHOLE (its days before the range are
/// counted too, so a bar is always a week against a weekly goal, never a tail of one); the last is the
/// week of today, still in progress. Pure: per-day facts in (`IntradayDayStore`'s records, lifted to
/// `Day`), weeks out.
struct TrendsIntensity: Equatable {
    /// One day's facts off `IntradayDayRecord`: credited minutes (moderate + 2·vigorous), minutes of
    /// the day with a scored heart rate and the basis the day was scored under.
    struct Day: Equatable {
        let day: String
        let credited: Int
        let scoredMinutes: Int
        let basis: IntensityMinutes.Basis

        init(day: String, credited: Int, scoredMinutes: Int, basis: IntensityMinutes.Basis) {
            self.day = day; self.credited = credited; self.scoredMinutes = scoredMinutes; self.basis = basis
        }

        init(_ r: IntradayDayRecord) {
            self.init(day: r.day, credited: r.basisIsScored ? r.credited : 0, scoredMinutes: r.scoredMinutes, basis: r.basis)
        }

        /// The strap recorded daytime heart rate, or imported workouts earned minutes: the same predicate
        /// the detail's range series reads (`IntradayDayRecord.isRecorded` / `recordedIntensity`), so the
        /// two never count a different set of days.
        var recorded: Bool { IntradayDayRecord.isRecorded(scoredMinutes: scoredMinutes, credited: credited) }
    }

    struct Week: Identifiable, Equatable {
        /// The Monday's day key.
        let id: String
        /// Local midnight of the Monday.
        let date: Date
        /// Credited minutes over the week's days so far.
        let credited: Int
        /// Days of the week with a scored heart rate (or workout credit).
        let recordedDays: Int
        /// The week has not reached its Sunday yet.
        let inProgress: Bool
    }

    let weeks: [Week]
    let goal: Int
    /// The week today falls in (the last of `weeks`).
    let thisWeek: Week?
    /// Weeks that have ended.
    let completedWeeks: Int
    /// Weeks with at least one recorded day, and how many of them reached the goal: the same rule as the
    /// metric detail's hero (`MetricSums.weeksAtGoal`), so the two never disagree. The week in progress
    /// counts once it has reached the goal (a met goal stays met); a week with no recorded day is missing.
    let weeksWithData: Int
    let weeksAtGoal: Int
    /// The newest recorded day's basis: `.needsAge` means the strap recorded heart rate but no age or
    /// max heart rate exists to judge it, so the card asks instead of drawing zero bars.
    let basis: IntensityMinutes.Basis?
    /// False when no day in the weeks drawn recorded anything: the screen then leaves the card out.
    let hasAny: Bool

    var needsAge: Bool { basis == .needsAge }

    /// "112 / 150" for the week in progress.
    var thisWeekText: String { "\(thisWeek?.credited ?? 0) / \(goal)" }

    /// The first day key the weeks need facts from: the Monday of the week `startKey` falls in.
    static func lookbackKey(startKey: String, calendar: Calendar = .current) -> String {
        IntensityMinutes.weekStart(of: startKey, calendar: calendar)
    }

    /// `days` are the facts for any day from `lookbackKey(startKey:)` to `todayKey` (missing days are
    /// unrecorded); `goal` is `IntensityMinutes.goal()`.
    static func build(days: [Day], startKey: String, todayKey: String, goal: Int,
                      calendar: Calendar = .current) -> TrendsIntensity {
        let firstMonday = lookbackKey(startKey: startKey, calendar: calendar)
        var byDay: [String: Day] = [:]
        for d in days where d.day >= firstMonday && d.day <= todayKey { byDay[d.day] = d }

        // The weeks through the one week builder Home's card and the detail's hero sum with
        // (`BaselineRangeSeries.weekTotals`): one reading per recorded day, so the week in progress
        // here is the "This week" both of them print.
        let readings = byDay.values.filter(\.recorded).map { MetricDayValue(day: $0.day, value: Double($0.credited)) }
        let weeks = BaselineRangeSeries.weekTotals(readings, from: firstMonday, to: todayKey, calendar: calendar).map { w in
            Week(id: w.id, date: w.date, credited: Int(w.total.rounded()), recordedDays: w.recordedDays,
                 inProgress: w.inProgress)
        }

        let completed = weeks.filter { !$0.inProgress }
        let withData = weeks.filter { $0.recordedDays > 0 }
        let newest = byDay.values.filter(\.recorded).max { $0.day < $1.day }
        return TrendsIntensity(weeks: weeks, goal: goal, thisWeek: weeks.last,
                               completedWeeks: completed.count,
                               weeksWithData: withData.count,
                               weeksAtGoal: withData.filter { $0.credited >= goal }.count,
                               basis: newest?.basis, hasAny: newest != nil)
    }

    /// What VoiceOver reads for the chart: "Intensity minutes, last 30 days: 5 weeks, 3 of 4 weeks at
    /// the 150-minute goal; this week 112 of 150."
    func chartSummary(range: TrendsRange) -> String {
        var s = "Intensity minutes, last \(range.days) days: \(weeks.count) week\(weeks.count == 1 ? "" : "s")"
        if weeksWithData > 0 {
            s += ", \(weeksAtGoal) of \(weeksWithData) week\(weeksWithData == 1 ? "" : "s") at the \(goal)-minute goal"
        }
        if let w = thisWeek, w.inProgress {
            s += "; this week \(w.credited) of \(goal)"
        }
        return s + "."
    }
}
#endif
