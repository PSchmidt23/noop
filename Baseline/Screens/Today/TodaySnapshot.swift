#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Pure derivations for the Today screen. Everything here is a value type built from `repo.days` and
// `repo.workoutRows(days:)`; nothing touches the store or SwiftUI.

/// One metric (HRV or resting HR) read against the person's own baseline.
struct TodayMetricReading {
    /// Last night's value and the day key (the morning) it belongs to.
    let value: Double
    let day: String
    /// Baseline folded from every night BEFORE `day`, so the value is judged against history it is not part of.
    let state: BaselineState
    /// nil until the baseline is usable (`Baselines.minNightsSeed` nights).
    let deviation: Deviation?
    /// Up to the last 14 nights with a value, oldest to newest, for the sparkline.
    let recent: [(day: String, value: Double)]

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

/// Last night, as the sleep card shows it. Stage minutes come from the daily row; wake is derived from
/// efficiency (in-bed = asleep / efficiency) because the daily row carries no wake figure.
struct TodaySleepReading {
    let day: String
    let totalMin: Double
    let efficiencyPct: Double?
    let deepMin: Double
    let remMin: Double
    let lightMin: Double
    let wakeMin: Double
    /// Mean total sleep over the 30 recorded nights before this one; nil on the first night.
    let avg30Min: Double?

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
/// calibrating case carries the honest count rather than a fabricated tier.
enum TodayReadiness {
    case calibrating(nights: Int)
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

    static func build(days: [DailyMetric], todayKey: String) -> TodaySnapshot {
        let scoped = days.filter { $0.day <= todayKey }
        return TodaySnapshot(
            todayKey: todayKey,
            hrv: reading(scoped, cfg: Baselines.hrvCfg) { $0.avgHrv },
            restingHr: reading(scoped, cfg: Baselines.restingHRCfg) { $0.restingHr.map(Double.init) },
            readiness: readiness(scoped),
            sleep: sleep(scoped),
            effort: scoped.last(where: { $0.day == todayKey })?.strain)
    }

    private static func reading(_ scoped: [DailyMetric], cfg: MetricCfg,
                                value: (DailyMetric) -> Double?) -> TodayMetricReading? {
        guard let latest = scoped.last(where: { value($0) != nil }), let v = value(latest) else { return nil }
        let history = scoped.filter { $0.day < latest.day }
        let state = Baselines.foldHistory(history.map(value), dayKeys: history.map(\.day), cfg: cfg)
        let deviation = state.usable ? Baselines.deviation(v, state: state) : nil
        let recent = scoped.compactMap { d -> (day: String, value: Double)? in
            guard let x = value(d) else { return nil }
            return (day: d.day, value: x)
        }.suffix(14)
        return TodayMetricReading(value: v, day: latest.day, state: state, deviation: deviation,
                                  recent: Array(recent))
    }

    private static func readiness(_ scoped: [DailyMetric]) -> TodayReadiness {
        let series = scoped.map(\.avgHrv)
        if let r = HRVReadiness.evaluate(avgHrv: series) { return .tier(r.tier) }
        let cfg = Baselines.hrvCfg
        let valid = series.compactMap { $0 }.filter { cfg.minVal <= $0 && $0 <= cfg.maxVal }.count
        return .calibrating(nights: min(valid, HRVReadiness.minNights))
    }

    private static func sleep(_ scoped: [DailyMetric]) -> TodaySleepReading? {
        guard let night = scoped.last(where: { $0.totalSleepMin != nil }),
              let total = night.totalSleepMin else { return nil }
        // Daily rows carry efficiency as a percentage; a value at or below 1 can only be a fraction.
        let eff = night.efficiency.map { $0 <= 1 ? $0 * 100 : $0 }
        let deep = max(0, night.deepMin ?? 0)
        let rem = max(0, night.remMin ?? 0)
        let light = max(0, night.lightMin ?? (total - deep - rem))
        let wake: Double = {
            guard let e = eff, e > 0 else { return 0 }
            return max(0, total / (e / 100) - total)
        }()
        let prior = scoped.filter { $0.day < night.day }.compactMap(\.totalSleepMin).suffix(30)
        let avg = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
        return TodaySleepReading(day: night.day, totalMin: total, efficiencyPct: eff,
                                 deepMin: deep, remMin: rem, lightMin: light, wakeMin: wake, avg30Min: avg)
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
}
#endif
