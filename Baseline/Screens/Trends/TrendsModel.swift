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

    struct ReadinessNight: Identifiable {
        let id: String
        let date: Date
        /// nil = no HRV that night, or fewer than 14 valid nights banked by then.
        let tier: ReadinessTier?
    }

    struct Readiness {
        let nights: [ReadinessNight]
        /// Tier this morning (fold of every night up to today).
        let latest: ReadinessTier?
    }

    static let readinessNights = 14

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
    let readiness: Readiness?

    static func build(days: [DailyMetric], range: TrendsRange, now: Date = Date()) -> TrendsSeries {
        let cal = Calendar.current
        let todayKey = Repository.localDayKey(now)
        let startDate = cal.date(byAdding: .day, value: -(range.days - 1), to: now) ?? now
        let startKey = Repository.localDayKey(startDate)

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

        let readiness = readinessStrip(days: upToToday, now: now, cal: cal)

        return TrendsSeries(range: range, totalNights: totalNights, hrv: hrv, restingHr: rhr,
                            sleep: sleep, sleepNights: sleepBars.count, sleepNights7h: sleep7h,
                            effort: effort, effortPeak: peak, readiness: readiness)
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

    // MARK: - Readiness strip

    /// One dot per calendar night for the last 14 nights, coloured by the HRV readiness tier *as of that
    /// morning* (evaluate over everything up to and including that night). nil when no night has a tier
    /// yet (fewer than 14 valid HRV nights), so the screen can skip the strip.
    private static func readinessStrip(days: [DailyMetric], now: Date, cal: Calendar) -> Readiness? {
        guard let windowStart = cal.date(byAdding: .day, value: -(readinessNights - 1), to: now) else { return nil }
        let windowKey = Repository.localDayKey(windowStart)

        var series: [Double?] = []
        series.reserveCapacity(days.count)
        var tierByDay: [String: ReadinessTier] = [:]
        for d in days {
            series.append(d.avgHrv)
            if d.day >= windowKey, d.avgHrv != nil, let r = HRVReadiness.evaluate(avgHrv: series) {
                tierByDay[d.day] = r.tier
            }
        }
        guard !tierByDay.isEmpty else { return nil }

        var nights: [ReadinessNight] = []
        for offset in 0..<readinessNights {
            guard let date = cal.date(byAdding: .day, value: offset, to: windowStart) else { continue }
            let key = Repository.localDayKey(date)
            nights.append(ReadinessNight(id: key, date: date, tier: tierByDay[key]))
        }
        return Readiness(nights: nights, latest: HRVReadiness.evaluate(avgHrv: series)?.tier)
    }
}
#endif
