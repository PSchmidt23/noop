#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// Resolvers for facts that more than one tab prints. Two readouts of one fact must not be able to
/// disagree, so each fact here has exactly one funnel: the Today hero tiles and the Trends "Baseline"
/// cell both read `latestNight(…)`; the Today sleep card and the Sleep tab both read `sleepAverage30(before:in:)`;
/// every span of minutes, asleep or in a workout, is spelled by `durationText(…)`.
/// Pure and synchronous; nothing here touches the store or SwiftUI.
enum BaselineReadouts {

    /// The newest night with a metric and the baseline it is judged against.
    struct NightReadout {
        /// The newest night (on or before today) whose value sits in the metric's valid range; nil when
        /// no night carries the metric yet.
        let latest: (day: String, value: Double)?
        /// The fold of every night BEFORE `latest.day` (every scoped night when there is no latest), so a
        /// night never sits inside its own baseline. This is the band drawn at the last point of the
        /// Trends chart, the Trends "Baseline" cell and the Today hero, so all three show one number and
        /// one calibrating count.
        let state: BaselineState
    }

    /// The recalibration epoch (seconds; 0 = none) a metric's fold honours, the split NOOP's engine makes:
    /// HRV re-anchors on `noop.hrvBaselineEpoch`, every other vital (resting HR, respiration, skin temp)
    /// on `noop.recoveryBaselineEpoch`. `IntelligenceEngine` folds resting HR with the recovery epoch, so
    /// the fold here must too or the two readouts could disagree after a "Recalibrate".
    static func baselineEpoch(for cfg: MetricCfg) -> Double {
        cfg == Baselines.hrvCfg ? Baselines.hrvBaselineEpoch() : Baselines.recoveryBaselineEpoch()
    }

    /// `upToToday` is `repo.days` (oldest → newest) already cut to `day <= todayKey`. The fold honours the
    /// metric's recalibration `epoch` (`baselineEpoch(for:)` by default) exactly as
    /// `Baselines.foldHistory(_:dayKeys:cfg:baselineEpoch:)` does.
    static func latestNight(upToToday: [DailyMetric], cfg: MetricCfg, epoch: Double? = nil,
                            value: (DailyMetric) -> Double?) -> NightReadout {
        let latestRow = upToToday.last { d in
            guard let v = value(d) else { return false }
            return cfg.minVal <= v && v <= cfg.maxVal
        }
        let history = latestRow.map { l in upToToday.filter { $0.day < l.day } } ?? upToToday
        let state = Baselines.foldHistory(history.map(value), dayKeys: history.map(\.day), cfg: cfg,
                                          baselineEpoch: epoch ?? baselineEpoch(for: cfg))
        let latest = latestRow.flatMap { row in value(row).map { (day: row.day, value: $0) } }
        return NightReadout(latest: latest, state: state)
    }

    /// One row per night of `upToToday` on or after the recalibration epoch, in order. The one fold walk
    /// behind the Trends band and the Progress trajectory, so the dashed line Trends draws under a night
    /// and the line Progress draws over months are the same numbers.
    struct NightState {
        let day: String
        /// `value(d)` when it lies in `cfg.minVal...cfg.maxVal`, else nil.
        let validValue: Double?
        /// The fold of every (post-epoch) night BEFORE this one; nil only before the first row.
        let stateGoingIn: BaselineState?
    }

    /// Walks `upToToday` (oldest → newest) night by night. Nights dated before the metric's recalibration
    /// `epoch` (`baselineEpoch(for:)` by default: the HRV epoch for HRV, the recovery epoch for resting HR)
    /// are dropped (not held), exactly as `Baselines.foldHistory(_:dayKeys:cfg:baselineEpoch:)` drops
    /// them; a nil or out-of-range night is skip-and-hold, as the engine defines. For the newest valid
    /// night `stateGoingIn` equals `latestNight(...).state`, the number the Today hero and the Trends
    /// "Baseline" cell print.
    static func nightlyStates(upToToday: [DailyMetric], cfg: MetricCfg, epoch: Double? = nil,
                              value: (DailyMetric) -> Double?) -> [NightState] {
        let epoch = epoch ?? baselineEpoch(for: cfg)
        var state: BaselineState? = nil
        var out: [NightState] = []
        out.reserveCapacity(upToToday.count)
        for d in upToToday {
            if TrendsDayKey.isBeforeEpoch(d.day, epoch: epoch) { continue }
            let raw = value(d)
            let valid = raw.flatMap { cfg.minVal <= $0 && $0 <= cfg.maxVal ? $0 : nil }
            out.append(NightState(day: d.day, validValue: valid, stateGoingIn: state))
            state = Baselines.update(state, value: raw, cfg: cfg)
        }
        return out
    }

    /// Minimum nights before a 30-night sleep average is shown.
    static let sleepAverageMinNights = 3

    /// Minutes asleep over the latest 30 nights INCLUDING the newest: the descriptive "you're averaging …"
    /// figure (Progress). nil until `sleepAverageMinNights` exist. `nights` is `SleepNightBuilder.nights(…)`,
    /// newest first. A night compared against an average goes through `sleepAverage30(before:in:)`.
    static func sleepAverage30(_ nights: [SleepNight]) -> Double? {
        mean(of: nights.prefix(30))
    }

    /// ONE comparison average for a night, wherever a screen says "vs your 30-night average" (Today's
    /// sleep card, the Sleep hero pill and its bar rule, a night's detail, the morning summary): the mean
    /// of the (up to) 30 recorded nights strictly BEFORE `day`, so a night is never measured against an
    /// average it is part of (the rule the HRV and resting-HR baselines follow). nil until
    /// `sleepAverageMinNights` earlier nights exist. `nights` is newest first.
    static func sleepAverage30(before day: String, in nights: [SleepNight]) -> Double? {
        mean(of: nights.filter { $0.dayKey < day }.prefix(30))
    }

    private static func mean(of nights: ArraySlice<SleepNight>) -> Double? {
        guard nights.count >= sleepAverageMinNights else { return nil }
        return nights.reduce(0) { $0 + $1.asleepMin } / Double(nights.count)
    }

    // MARK: Effort

    /// ONE rendering of an effort value (the day's `DailyMetric.strain` or a session's `WorkoutRow.strain`,
    /// both stored 0–100) wherever a screen prints it: Today's effort cell, the Workouts list and the
    /// workout detail. A whole number; "–" when nothing has been recorded.
    static func effortText(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))"
    }

    /// The denominator every effort readout wears beside `effortText`.
    static let effortUnit = "/ 100"

    // MARK: Durations

    /// ONE spelling for a span of minutes wherever a screen prints one: a night's minutes asleep (Today's
    /// sleep card, the Sleep tab, Trends, Progress, the morning summary), a stage's minutes, a workout's
    /// length. "6h 42m"; "42 min" under an hour. Rounded to the minute and never negative, so a hero
    /// numeral, a stat cell and a sentence cannot spell one quantity three ways.
    static func durationText(minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60)h " + String(format: "%02d", m % 60) + "m"
    }

    /// `durationText(minutes:)` from seconds, for sessions (`WorkoutRow.durationS`); "–" when nothing
    /// was recorded, as `effortText` prints a missing effort.
    static func durationText(seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        return durationText(minutes: seconds / 60)
    }

    /// Inside this many minutes either way, a night is "on" its average rather than above or below it.
    static let durationSteadyMin = 5

    /// A delta in `durationText`'s spelling with a typographic sign: "+22 min" / "−1h 05m". nil inside
    /// ±`durationSteadyMin`, so every "vs average" phrase (Today's sleep card, the Sleep hero pill, the
    /// morning summary) turns into "on your average" at the same point.
    static func signedDurationText(minutes delta: Double) -> String? {
        let m = Int(delta.rounded())
        guard abs(m) >= durationSteadyMin else { return nil }
        return (m < 0 ? "\u{2212}" : "+") + durationText(minutes: Double(abs(m)))
    }
}
#endif
