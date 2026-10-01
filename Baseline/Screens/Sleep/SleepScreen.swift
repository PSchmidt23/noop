#if os(iOS)
import SwiftUI

/// The Sleep tab: last night's hero, stages and vitals, the last 14 nights as bars, and a list of the
/// last 30 nights that pushes `NightDetailScreen`.
struct SleepScreen: View {
    @EnvironmentObject private var repo: Repository
    @State private var nights: [SleepNight] = []

    /// Reload key: `refreshSeq` for every changed refresh, plus `loaded` so the first publish is never
    /// missed if the store finishes loading between two sequence values.
    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
    }

    /// ONE comparison average for the app: `BaselineReadouts.sleepAverage30(before:in:)`, the 30 nights
    /// before the latest, which the Today tab's sleep card reads too, so the hero pill, the bar chart's
    /// rule and Today's delta can never disagree. nil until three earlier nights exist.
    private var average30: Double? {
        nights.first.flatMap { BaselineReadouts.sleepAverage30(before: $0.dayKey, in: nights) }
    }

    private var listed: [SleepNight] { Array(nights.prefix(30)) }

    var body: some View {
        BaselineScreen(title: "Sleep") {
            if let last = nights.first {
                SleepHeroCard(title: heroTitle(for: last), night: last, average: average30)
                SleepHypnogramCard(night: last)
                if last.hasVitals {
                    SleepVitalsCard(night: last)
                }
                if nights.count >= 2 {
                    recentCard
                }
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
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded)) { await reload() }
    }

    private func heroTitle(for night: SleepNight) -> String {
        let cal = Calendar.current
        return (cal.isDateInToday(night.dayDate) || cal.isDateInYesterday(night.dayDate)) ? "Last night" : "Latest night"
    }

    private var recentCard: some View {
        let bars = nights.prefix(14).reversed().map { n in
            BaselineBarChart.Bar(id: n.dayKey,
                                 date: n.dayDate,
                                 value: (n.hoursAsleep * 10).rounded() / 10)
        }
        return BaselineCard(title: "Last 14 nights",
                            subtitle: average30 != nil ? "Hours asleep. The dashed line is your 30-night average."
                                                       : "Hours asleep") {
            BaselineBarChart(bars: bars, color: BaselineTheme.sleep, average: average30.map { $0 / 60.0 })
        }
    }

    private var nightsCard: some View {
        BaselineCard(title: "Nights", subtitle: "Tap a night for its stages and vitals") {
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
        nights = SleepNightBuilder.nights(sessions: repo.sleeps, days: repo.days, habitualMidsleepSec: habitual)
    }
}
#endif
