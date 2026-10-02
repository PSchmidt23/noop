#if os(iOS)
import SwiftUI

/// The Sleep tab: last night as a ring against the 30-night average (its "Sleep over time" row pushes
/// the sleep-duration detail, `MetricDetailScreen` with `SleepDetail.durationSpec()`), its timing (the
/// last 14 nights against the target window, the averages, regularity and tonight's aim; its "Bedtime
/// and wake over time" row pushes `SleepTimingDetailScreen`), its stages, and the last 30 nights as a
/// list that pushes `NightDetailScreen` (where the night's heart rate and vitals live). Nights come from
/// the strap-first funnel (`repo.baselineNights()` / `repo.baselineDays`), never from `repo.days`.
struct SleepScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    /// The target window's keys, observed so a change made in Settings redraws the timing card on the
    /// way back; `window` validates them exactly as `SleepWindow.stored()` does.
    @AppStorage(BaselineReadouts.SleepWindow.bedKey) private var windowBed = BaselineReadouts.SleepWindow.default.bedMinutes
    @AppStorage(BaselineReadouts.SleepWindow.wakeKey) private var windowWake = BaselineReadouts.SleepWindow.default.wakeMinutes
    @State private var nights: [SleepNight] = []

    /// Reload key: `refreshSeq` for every changed refresh, `loaded` so the first publish is never missed
    /// if the store finishes loading between two sequence values, and the data-source mode so a change
    /// in Settings → Data rebuilds the nights without waiting for the next refresh.
    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let dataSource: String
    }

    /// ONE comparison average for the app: `BaselineReadouts.sleepAverage30(before:in:)`, the 30 nights
    /// before the latest, which the Home tab's sleep card reads too, so the ring's context line and
    /// Home's delta can never disagree. nil until three earlier nights exist.
    private var average30: Double? {
        nights.first.flatMap { BaselineReadouts.sleepAverage30(before: $0.dayKey, in: nights) }
    }

    private var listed: [SleepNight] { Array(nights.prefix(30)) }

    private var window: BaselineReadouts.SleepWindow {
        func valid(_ v: Int, _ fallback: Int) -> Int { (0..<1440).contains(v) ? v : fallback }
        return BaselineReadouts.SleepWindow(bedMinutes: valid(windowBed, BaselineReadouts.SleepWindow.default.bedMinutes),
                                            wakeMinutes: valid(windowWake, BaselineReadouts.SleepWindow.default.wakeMinutes))
    }

    /// ONE timing readout for the tab, for the latest night, over the same nights the hero and list use.
    private func timing(for last: SleepNight) -> BaselineReadouts.SleepTiming {
        BaselineReadouts.sleepTiming(for: last.dayKey, nights: nights, window: window)
    }

    var body: some View {
        BaselineScreen(title: "Sleep") {
            if let last = nights.first {
                SleepHeroCard(title: heroTitle(for: last), night: last, average: average30, showsDetailLink: true)
                SleepTimingCard(timing: timing(for: last))
                SleepHypnogramCard(night: last)
                nightsCard
            } else if repo.loaded {
                BaselineCard {
                    BaselineEmptyState(icon: "moon.zzz",
                                       title: "No nights yet",
                                       message: "Your first night appears here after the strap syncs a full sleep.")
                }
            } else {
                BaselineCard {
                    BaselineEmptyState(icon: "hourglass",
                                       title: "Reading your nights",
                                       message: "Sleep appears here once the store has loaded.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BaselineToolbarLink(systemImage: "gearshape", accessibilityLabel: "Settings") { SettingsScreen() }
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, dataSource: dataSourceRaw)) { await reload() }
    }

    private func heroTitle(for night: SleepNight) -> String {
        let cal = Calendar.current
        return (cal.isDateInToday(night.dayDate) || cal.isDateInYesterday(night.dayDate)) ? "Last night" : "Latest night"
    }

    private var nightsCard: some View {
        BaselineCard(title: "Nights") {
            VStack(spacing: 0) {
                ForEach(listed) { n in
                    NavigationLink {
                        // Each night against the 30 nights before IT, as the hero compares the latest.
                        NightDetailScreen(night: n, average: BaselineReadouts.sleepAverage30(before: n.dayKey, in: nights))
                    } label: {
                        SleepNightRow(night: n)
                    }
                    .buttonStyle(.plain)
                    if n.id != listed.last?.id {
                        Rectangle().fill(BaselineTheme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    @MainActor
    private func reload() async {
        let habitual = await repo.habitualMidsleepSec()
        let sessions = await repo.baselineNights()
        nights = SleepNightBuilder.nights(sessions: sessions, days: repo.baselineDays, habitualMidsleepSec: habitual)
    }
}
#endif
