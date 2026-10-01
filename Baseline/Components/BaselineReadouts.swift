#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// Resolvers for facts that more than one tab prints. Two readouts of one fact must not be able to
/// disagree, so each fact here has exactly one funnel: the Today hero tiles and the Trends "Baseline"
/// cell both read `latestNight(…)`; the Today sleep card and the Sleep tab both read `sleepAverage30(…)`.
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

    /// `upToToday` is `repo.days` (oldest → newest) already cut to `day <= todayKey`. The fold honours the
    /// recalibration epoch exactly as `Baselines.foldHistory(_:dayKeys:cfg:baselineEpoch:)` does.
    static func latestNight(upToToday: [DailyMetric], cfg: MetricCfg,
                            value: (DailyMetric) -> Double?) -> NightReadout {
        let latestRow = upToToday.last { d in
            guard let v = value(d) else { return false }
            return cfg.minVal <= v && v <= cfg.maxVal
        }
        let history = latestRow.map { l in upToToday.filter { $0.day < l.day } } ?? upToToday
        let state = Baselines.foldHistory(history.map(value), dayKeys: history.map(\.day), cfg: cfg,
                                          baselineEpoch: Baselines.hrvBaselineEpoch())
        let latest = latestRow.flatMap { row in value(row).map { (day: row.day, value: $0) } }
        return NightReadout(latest: latest, state: state)
    }

    /// Minimum nights before a 30-night sleep average is shown.
    static let sleepAverageMinNights = 3

    /// ONE sleep average for the app: minutes asleep over the latest 30 nights (including the latest), nil
    /// until `sleepAverageMinNights` exist. `nights` is `SleepNightBuilder.nights(…)`, newest first.
    static func sleepAverage30(_ nights: [SleepNight]) -> Double? {
        let recent = nights.prefix(30)
        guard recent.count >= sleepAverageMinNights else { return nil }
        return recent.reduce(0) { $0 + $1.asleepMin } / Double(recent.count)
    }
}
#endif
