#if os(iOS)
import SwiftUI
import StrandAnalytics

/// Trends: HRV and resting HR against the personal baseline band, sleep and effort bars, and a 14-night
/// readiness strip, over a 7 / 30 / 90 day window. Series are built once per (data, range) in `.task`.
struct TrendsScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage("baseline.trendsRange") private var rangeRaw: Int = TrendsRange.month.rawValue
    @State private var series: TrendsSeries?

    private struct LoadKey: Equatable {
        let seq: Int
        let range: Int
        let loaded: Bool
    }

    private var range: TrendsRange { TrendsRange.resolve(rangeRaw) }

    var body: some View {
        BaselineScreen(title: "Trends") {
            if let series {
                if series.totalNights < 2 {
                    emptyState
                } else {
                    TrendRangePicker(selection: Binding(get: { range }, set: { rangeRaw = $0.rawValue }))
                    cards(series)
                }
            } else {
                // Until the store's first refresh lands (`loaded` and `refreshSeq` flip together).
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, range: rangeRaw, loaded: repo.loaded)) {
            guard repo.loaded else { series = nil; return }
            series = TrendsSeries.build(days: repo.days, range: range)
        }
        // A text label, not an icon, so the destination is named. Present in every state, including
        // the empty one: Progress explains what it needs. The tab's NavigationStack pushes it.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ProgressScreen() } label: {
                    Text("Progress").font(BaselineTheme.label)
                }
                .accessibilityHint("Shows whether your baseline has moved over months")
            }
        }
    }

    @ViewBuilder
    private func cards(_ s: TrendsSeries) -> some View {
        TrendBandCard(title: "HRV", noun: "HRV", unit: "ms", color: BaselineTheme.hrv,
                      higherIsBetter: true, range: s.range, metric: s.hrv)

        TrendBandCard(title: "Resting HR", noun: "resting HR", unit: "bpm", color: BaselineTheme.rhr,
                      higherIsBetter: false, range: s.range, metric: s.restingHr)

        if let readiness = s.readiness {
            ReadinessStripCard(readiness: readiness)
        }

        TrendBarCard(
            title: "Sleep",
            subtitle: s.range.subtitle,
            color: BaselineTheme.sleep,
            bars: s.sleep.bars,
            average: s.sleep.average,
            stats: [
                TrendStat(label: "Average", value: s.sleep.average.map { BaselineReadouts.durationText(minutes: $0 * 60) } ?? "—"),
                TrendStat(label: "7h or more", value: String(s.sleepNights7h),
                          unit: "of \(s.sleepNights) night\(s.sleepNights == 1 ? "" : "s")")
            ],
            emptyText: "No nights of sleep in the last \(s.range.days) days.")

        TrendBarCard(
            title: "Effort",
            subtitle: s.range.subtitle,
            color: BaselineTheme.effort,
            bars: s.effort.bars,
            average: s.effort.average,
            stats: [
                TrendStat(label: "Average", value: s.effort.average.map(TrendsFormat.whole) ?? "—"),
                TrendStat(label: "Highest", value: s.effortPeak.map { TrendsFormat.whole($0.value) } ?? "—",
                          unit: s.effortPeak.map { TrendsFormat.shortDate($0.date) })
            ],
            emptyText: "No effort recorded in the last \(s.range.days) days.",
            link: TrendCardLink(label: "All workouts",
                                hint: "Shows every recorded workout",
                                destination: { AnyView(WorkoutsScreen()) }))
    }

    private var emptyState: some View {
        BaselineCard {
            BaselineEmptyState(
                icon: "chart.xyaxis.line",
                title: "Trends take a few nights",
                message: "Charts appear after a few synced nights. Your personal baseline needs \(Baselines.minNightsTrust) nights before the band around HRV and Resting HR settles.")
        }
    }
}
#endif
