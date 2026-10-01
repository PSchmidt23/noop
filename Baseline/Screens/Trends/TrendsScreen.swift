#if os(iOS)
import SwiftUI
import StrandAnalytics

/// The three sections under the Trends tab's pinned glass control: the metric charts over 7 / 30 / 90
/// days, the long-term baseline (Progress, embedded, not pushed) and the journal patterns (Habits).
/// `label` is the segment text; "Progress" is also the UI tests' `buttons["Progress"]` anchor.
enum TrendsSection: String, CaseIterable, Identifiable {
    case trends, progress, habits

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trends: return "Trends"
        case .progress: return "Progress"
        case .habits: return "Habits"
        }
    }
}

/// Trends: HRV and resting HR against the personal baseline band, sleep and effort bars over a
/// 7 / 30 / 90 day window (the "Trends" section), the baseline over months ("Progress", `ProgressSection`)
/// and the journal patterns ("Habits", `JournalPatternsView`). One pinned glass control picks the section;
/// the range picker sits flat at the top of the Trends section's content. Series are built once per
/// (data, range) in `.task`. Settings is the gear in the toolbar.
struct TrendsScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage("baseline.trendsRange") private var rangeRaw: Int = TrendsRange.month.rawValue
    /// Strap-first / merged / import-only precedence (Settings → Data); part of the reload key.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    /// Always opens on the charts (a `@State`, not persisted, so a launch is deterministic).
    @State private var section: TrendsSection = .trends
    @State private var series: TrendsSeries?
    /// Held in state and rolled on `.NSCalendarDayChanged`, so the window's "today" end moves at midnight
    /// instead of waiting for the next store refresh.
    @State private var todayKey = Repository.localDayKey(Date())

    private struct LoadKey: Equatable {
        let seq: Int
        let range: Int
        let loaded: Bool
        let day: String
        let dataSource: String
    }

    private var range: TrendsRange { TrendsRange.resolve(rangeRaw) }

    var body: some View {
        BaselineScreen(title: "Trends", titleMode: .inline, pinned: {
            // Segment labels are the spoken labels too: `buttons["Progress"]` is a UI-test anchor.
            BaselineSegmentedPicker(options: TrendsSection.allCases, selection: $section,
                                    label: { $0.label }, style: .glass)
        }) {
            switch section {
            case .trends:
                trendsSection
            case .progress:
                ProgressSection()
            case .habits:
                JournalPatternsView()
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, range: rangeRaw, loaded: repo.loaded, day: todayKey,
                          dataSource: dataSourceRaw)) {
            guard repo.loaded else { series = nil; return }
            series = TrendsSeries.build(days: repo.baselineDays, range: range)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            todayKey = Repository.localDayKey(Date())
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BaselineToolbarLink(systemImage: "gearshape", accessibilityLabel: "Settings") { SettingsScreen() }
            }
        }
    }

    // MARK: - Trends section

    @ViewBuilder
    private var trendsSection: some View {
        if let series {
            if series.totalNights < 2 {
                emptyState
            } else {
                // Flat, inside the content: the pinned row is the section control (one pinned row per screen).
                TrendRangePicker(selection: Binding(get: { range }, set: { rangeRaw = $0.rawValue }), style: .flat)
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

    @ViewBuilder
    private func cards(_ s: TrendsSeries) -> some View {
        TrendBandCard(title: "HRV", noun: "HRV", unit: "ms", color: BaselineTheme.hrv,
                      higherIsBetter: true, range: s.range, metric: s.hrv)

        TrendBandCard(title: "Resting HR", noun: "resting HR", unit: "bpm", color: BaselineTheme.rhr,
                      higherIsBetter: false, range: s.range, metric: s.restingHr)

        // No "Last 30 days" caption on either bar card: the range picker a few points above says it.
        TrendBarCard(
            title: "Sleep",
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
            color: BaselineTheme.effort,
            bars: s.effort.bars,
            average: s.effort.average,
            stats: [
                TrendStat(label: "Average", value: s.effort.average.map(TrendsFormat.whole) ?? "—"),
                TrendStat(label: "Highest", value: s.effortPeak.map { TrendsFormat.whole($0.value) } ?? "—",
                          unit: s.effortPeak.map { TrendsFormat.shortDate($0.date) })
            ],
            emptyText: "No effort recorded in the last \(s.range.days) days.",
            showsAllWorkouts: true)
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
