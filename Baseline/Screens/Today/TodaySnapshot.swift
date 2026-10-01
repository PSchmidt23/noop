#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Pure derivations for the Today screen. Everything here is a value type built from `repo.days`, the
// Sleep tab's `SleepNight` list and `repo.workoutRows(days:)`; nothing touches the store or SwiftUI.

/// One metric (HRV or resting HR) read against the person's own baseline.
struct TodayMetricReading {
    /// Day key (the morning) of the newest night with a value, whatever its age.
    let day: String
    /// That night's value, or nil once the night is older than `Baselines.vitalCarryDays`: a weeks-old
    /// number must not read as this morning's measurement (NOOP's carry rule), so the tile shows "–"
    /// and names the day instead.
    let value: Double?
    /// Baseline folded from every night BEFORE `day`, so the value is judged against history it is not
    /// part of. Shared with the Trends tab through `BaselineReadouts.latestNight`.
    let state: BaselineState
    /// nil until the baseline is usable (`Baselines.minNightsSeed` nights) or when the value is stale.
    let deviation: Deviation?
    /// Up to the last 14 nights with a value, oldest to newest, for the sparkline. Empty when stale, so
    /// an axis-free line never reads as "the last 14 nights".
    let recent: [(day: String, value: Double)]

    var isStale: Bool { value == nil }

    var band: BaselineBand {
        guard state.usable, let d = deviation else { return .calibrating }
        if d.inNormalRange { return .inside }
        return d.z > 0 ? .above : .below
    }
    var baseline: Double? { state.usable ? state.baseline : nil }
    var bandLow: Double? { state.usable ? state.baseline - Baselines.sigma(state) : nil }
    var bandHigh: Double? { state.usable ? state.baseline + Baselines.sigma(state) : nil }
}

/// One sleep stage's share of the night, for the stage bar and its legend.
struct TodayStage: Identifiable {
    /// "deep" / "rem" / "light" / "wake", the key `BaselineTheme.stageColor` understands.
    let id: String
    let minutes: Double
}

/// Last night, as the sleep card shows it. Built from the same `SleepNight` the Sleep tab's hero shows,
/// so the two tabs print one total, one efficiency and one delta for the night.
struct TodaySleepReading {
    let day: String
    let totalMin: Double
    let efficiencyPct: Double?
    let deepMin: Double
    let remMin: Double
    let lightMin: Double
    let wakeMin: Double
    /// False when the night carries no per-stage minutes (an imported total only); the card then skips
    /// the stage bar rather than painting the whole night as one stage.
    let hasStages: Bool
    /// `BaselineReadouts.sleepAverage30` over the same nights; nil until three nights exist.
    let avg30Min: Double?

    init(night: SleepNight, avg30Min: Double?) {
        day = night.dayKey
        totalMin = night.asleepMin
        efficiencyPct = night.efficiency.map { $0 * 100 }
        deepMin = max(0, night.deepMin)
        remMin = max(0, night.remMin)
        lightMin = max(0, night.lightMin)
        wakeMin = max(0, night.awakeMin)
        hasStages = night.hasStageTotals
        self.avg30Min = avg30Min
    }

    var stages: [TodayStage] {
        [TodayStage(id: "deep", minutes: deepMin),
         TodayStage(id: "rem", minutes: remMin),
         TodayStage(id: "light", minutes: lightMin),
         TodayStage(id: "wake", minutes: wakeMin)]
    }
}

/// A workout started today, trimmed to what the effort card shows.
struct TodayWorkout: Identifiable {
    let id: Int
    let sport: String
    let durationS: Double?
    let avgHr: Int?

    init(_ row: WorkoutRow) {
        id = row.startTs
        sport = row.sport
        durationS = row.durationS
        avgHr = row.avgHr
    }
}

/// The readiness line under the date. `HRVReadiness` refuses to score below 14 valid nights, so the
/// calibrating case carries the honest count rather than a fabricated tier. `stale` is the HRV tile's
/// carry cap applied here too: once the newest HRV night is older than `Baselines.vitalCarryDays`, a
/// tier evaluated from it must not read as this morning's.
enum TodayReadiness {
    case calibrating(nights: Int)
    case stale(lastDay: String)
    case tier(ReadinessTier)
}

struct TodaySnapshot {
    let todayKey: String
    let hrv: TodayMetricReading?
    let restingHr: TodayMetricReading?
    let readiness: TodayReadiness
    let sleep: TodaySleepReading?
    /// Today's effort 0-100 (`DailyMetric.strain`); nil until the strap has recorded part of the day.
    let effort: Double?

    /// `nights` is `SleepNightBuilder.nights(…)` (newest first), the same list the Sleep tab draws.
    static func build(days: [DailyMetric], nights: [SleepNight], todayKey: String) -> TodaySnapshot {
        let scoped = days.filter { $0.day <= todayKey }
        let hrv = reading(scoped, todayKey: todayKey, cfg: Baselines.hrvCfg) { $0.avgHrv }
        return TodaySnapshot(
            todayKey: todayKey,
            hrv: hrv,
            restingHr: reading(scoped, todayKey: todayKey, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) },
            readiness: readiness(scoped, hrv: hrv),
            sleep: sleep(nights, todayKey: todayKey),
            effort: scoped.last(where: { $0.day == todayKey })?.strain)
    }

    private static func reading(_ scoped: [DailyMetric], todayKey: String, cfg: MetricCfg,
                                value: (DailyMetric) -> Double?) -> TodayMetricReading? {
        let readout = BaselineReadouts.latestNight(upToToday: scoped, cfg: cfg, value: value)
        guard let latest = readout.latest else { return nil }
        // NOOP's carry rule: a nightly vital is presented as "latest" for `vitalCarryDays`, then blanked.
        let fresh = Baselines.freshestCarried([latest], todayKey: todayKey) != nil
        let state = readout.state
        let deviation = fresh && state.usable ? Baselines.deviation(latest.value, state: state) : nil
        var recent: [(day: String, value: Double)] = []
        if fresh {
            let valued = scoped.compactMap { d -> (day: String, value: Double)? in
                guard let x = value(d), cfg.minVal <= x, x <= cfg.maxVal else { return nil }
                return (day: d.day, value: x)
            }
            recent = Array(valued.suffix(14))
        }
        return TodayMetricReading(day: latest.day, value: fresh ? latest.value : nil, state: state,
                                  deviation: deviation, recent: recent)
    }

    private static func readiness(_ scoped: [DailyMetric], hrv: TodayMetricReading?) -> TodayReadiness {
        if let hrv, hrv.isStale { return .stale(lastDay: hrv.day) }
        let series = scoped.map(\.avgHrv)
        if let r = HRVReadiness.evaluate(avgHrv: series) { return .tier(r.tier) }
        let cfg = Baselines.hrvCfg
        let valid = series.compactMap { $0 }.filter { cfg.minVal <= $0 && $0 <= cfg.maxVal }.count
        return .calibrating(nights: min(valid, HRVReadiness.minNights))
    }

    private static func sleep(_ nights: [SleepNight], todayKey: String) -> TodaySleepReading? {
        let scoped = nights.filter { $0.dayKey <= todayKey }
        guard let night = scoped.first else { return nil }
        return TodaySleepReading(night: night, avg30Min: BaselineReadouts.sleepAverage30(scoped))
    }
}

// MARK: - Formatting shared by the Today cards

enum TodayFormat {
    /// "7:42" from minutes.
    static func hoursMinutes(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// "+22 min" / "−1 h 05" for a minutes delta; nil inside ±5 min.
    static func signedMinutes(_ delta: Double) -> String? {
        let m = Int(delta.rounded())
        guard abs(m) >= 5 else { return nil }
        let sign = m < 0 ? "−" : "+"
        let a = abs(m)
        return a < 60 ? "\(sign)\(a) min" : "\(sign)\(a / 60) h " + String(format: "%02d", a % 60)
    }

    /// "42 min" / "1 h 05" from seconds.
    static func duration(_ seconds: Double?) -> String {
        guard let s = seconds, s > 0 else { return "–" }
        let m = Int((s / 60).rounded())
        return m < 60 ? "\(m) min" : "\(m / 60) h " + String(format: "%02d", m % 60)
    }

    /// Signed whole-number delta with a unit: "+6 ms", "−2 bpm".
    static func signed(_ delta: Double, unit: String) -> String {
        let v = Int(delta.rounded())
        return (v < 0 ? "−" : "+") + "\(abs(v)) \(unit)"
    }

    private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(fromDayKey key: String) -> Date? { dayKeyParser.date(from: key) }

    /// "Mon 28 Sep" for a day key; the key itself if it does not parse.
    static func dayLabel(_ key: String) -> String {
        guard let d = date(fromDayKey: key) else { return key }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The provenance stamp every carried value on Today wears: "Woke Mon 28 Sep" when `day` is not this
    /// morning, nil when it is. One phrase for the sleep card and the hero tiles, so the screen dates a
    /// night one way.
    static func wokeStamp(day: String, todayKey: String) -> String? {
        day == todayKey ? nil : "Woke " + dayLabel(day)
    }
}
#endif
