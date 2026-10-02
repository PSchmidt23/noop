#if os(iOS)
import Foundation
import WidgetKit
import WhoopStore
import StrandAnalytics

// MARK: - Builder (pure)

extension BaselineWidgetSnapshot {
    /// Flattens the `TodaySnapshot` Home draws into the widget's glance. Pure, so `WidgetSnapshotTests`
    /// can hold it against `TodaySnapshot` for a fixture: every number is read from the snapshot, never
    /// recomputed (the Readiness score from `TodaySnapshot.readinessScore`, the one Home's card and the
    /// morning summary read), and every phrase is the funnel's (`BaselineBand.positionPhrase`,
    /// `ReadinessTone.label`, `TodayFormat`), so the widget prints what the tile prints.
    static func make(from s: TodaySnapshot, lastSyncedAt: Date?, generatedAt: Date) -> BaselineWidgetSnapshot {
        var out = BaselineWidgetSnapshot(dayKey: s.todayKey, generatedAt: generatedAt)
        out.lastSyncedAt = lastSyncedAt

        if let hrv = s.hrv {
            out.hrvMs = hrv.value
            out.hrvDay = hrv.day
            out.hrvBaselineMs = hrv.isStale ? nil : hrv.baseline
            out.hrvBandLowMs = hrv.isStale ? nil : hrv.bandLow
            out.hrvBandHighMs = hrv.isStale ? nil : hrv.bandHigh
            out.hrvRingFraction = ringFraction(hrv, cfg: Baselines.hrvCfg)
            out.hrvBandPosition = bandName(hrv)
        }
        out.hrvDeltaText = contextText(s.hrv, unit: "ms", todayKey: s.todayKey)

        if let rhr = s.restingHr {
            out.rhrBpm = rhr.value
            out.rhrBaselineBpm = rhr.isStale ? nil : rhr.baseline
            out.rhrBandPosition = bandName(rhr)
        }
        out.rhrDeltaText = contextText(s.restingHr, unit: "bpm", todayKey: s.todayKey)

        switch s.readinessScore {
        case .score(let r, _):
            out.readinessScore = r.score
            out.readinessToneLabel = r.tone.label
            out.readinessToneName = colorName(r.tone)
            out.readinessDay = r.day
        case .calibrating(let nights):
            out.readinessNightsSoFar = nights
            out.readinessSeedNights = BaselineReadouts.readinessSeedNights
        case .stale, .missing:
            break
        }

        if let sleep = s.sleep {
            out.sleepMinutes = sleep.totalMin
            out.sleepAverageMinutes = sleep.avg30Min
            out.sleepDay = sleep.day
        }
        return out
    }

    /// The HRV tile's arc: `MetricRingScale.domain` (baseline ± 3σ) and `fraction`, nil (track only)
    /// while calibrating or stale, exactly as `TodayRingTile.domain` decides.
    static func ringFraction(_ r: TodayMetricReading, cfg: MetricCfg) -> Double? {
        guard let value = r.value, let domain = MetricRingScale.domain(state: r.state, cfg: cfg) else { return nil }
        return MetricRingScale.fraction(value, in: domain)
    }

    /// Home's context sentence, from the one function `TodayRingTile` itself prints (so the widget can
    /// never drift from the tab behind it). The empty case has its own sentence: never a blank line.
    static func contextText(_ r: TodayMetricReading?, unit: String, todayKey: String) -> String {
        TodayRingTile.contextText(r, unit: unit, dayKey: todayKey)
    }

    static func bandName(_ r: TodayMetricReading) -> String? {
        guard !r.isStale else { return nil }
        switch r.band {
        case .inside: return "inside"
        case .above: return "above"
        case .below: return "below"
        case .calibrating: return nil
        }
    }

    /// The `BaselineTheme` token `ReadinessBar` paints a tone with, by name, for the extension's palette.
    static func colorName(_ tone: ReadinessTone) -> String {
        switch tone {
        case .good: return "good"
        case .watch: return "watch"
        case .low: return "low"
        }
    }
}

// MARK: - Publisher (app only)

/// Writes the glance into the App Group and asks WidgetKit for a new timeline, the way NOOP's
/// `WidgetSnapshot.publish` does for its widgets. Reads through the SAME funnel as Home and the morning
/// summary (`BaselineReadouts.days` / `nights` under the persisted `baseline.dataSource`), so a widget
/// never disagrees with the tab behind it. Foreground-only and debounced by the caller (`BaselineApp`):
/// foreground-initiated reloads are exempt from WidgetKit's daily budget; a background bump is covered by
/// the widget's own six-hour safety reload and the republish on the next activation.
@MainActor
enum BaselineWidgetPublisher {
    private static var publishing = false
    private static var publishAgain = false

    /// Coalesces: a request that lands mid-publish queues exactly one more pass (the
    /// `MorningSummaryNotifier.evaluate` discipline).
    static func publish(repo: Repository, live: LiveState, now: @escaping () -> Date = Date.init) {
        if publishing { publishAgain = true; return }
        publishing = true
        Task {
            await run(repo: repo, live: live, now: now)
            publishing = false
            if publishAgain {
                publishAgain = false
                publish(repo: repo, live: live, now: now)
            }
        }
    }

    private static func run(repo: Repository, live: LiveState, now: () -> Date) async {
        guard repo.loaded else { return }
        let clock = now()
        let snapshot = await build(repo: repo, lastSyncedAt: live.lastSyncedAt.map(Date.init(timeIntervalSince1970:)),
                                   now: clock)
        let previous = BaselineWidgetStore.load()
        if let previous, previous.rendersSame(as: snapshot) { return }
        guard BaselineWidgetStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// THE resolver for the widget's figures: the night list and `TodaySnapshot` Home builds, through the
    /// strap-first funnel (`MorningSummaryNotifier.summary` reads the same way). `mode` is injectable
    /// for tests only.
    static func build(repo: Repository, lastSyncedAt: Date?, now: Date,
                      mode: BaselineDataSource = .current()) async -> BaselineWidgetSnapshot {
        let habitual = await repo.habitualMidsleepSec()
        let days = BaselineReadouts.days(repo, mode: mode)
        let sessions = await BaselineReadouts.nights(repo, mode: mode)
        let nights = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
        let today = TodaySnapshot.build(days: days, nights: nights, todayKey: Repository.localDayKey(now),
                                        logicalKey: Repository.logicalDayKey(now))
        return BaselineWidgetSnapshot.make(from: today, lastSyncedAt: lastSyncedAt, generatedAt: now)
    }
}
#endif
