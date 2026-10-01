#if os(iOS)
import SwiftUI

/// The Sleep tab: last night's hero, stages and vitals, the last 14 nights as bars, and a list of the
/// last 30 nights that pushes `NightDetailScreen`.
struct SleepScreen: View {
    @EnvironmentObject private var repo: Repository
    @State private var nights: [SleepNight] = []

    /// ONE average for the whole screen: asleep minutes over the latest 30 nights. Both the hero pill
    /// and the bar chart's rule read this, so they can never disagree. nil until three nights exist.
    private var average30: Double? {
        let recent = nights.prefix(30)
        guard recent.count >= 3 else { return nil }
        return recent.reduce(0) { $0 + $1.asleepMin } / Double(recent.count)
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
        .task(id: repo.refreshSeq) { await reload() }
    }

    private func heroTitle(for night: SleepNight) -> String {
        let cal = Calendar.current
        return (cal.isDateInToday(night.wake) || cal.isDateInYesterday(night.wake)) ? "Last night" : "Latest night"
    }

    private var recentCard: some View {
        let cal = Calendar.current
        let bars = nights.prefix(14).reversed().map { n in
            BaselineBarChart.Bar(id: n.dayKey,
                                 date: cal.startOfDay(for: n.wake),
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
                        NightDetailScreen(night: n, average: average30)
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
