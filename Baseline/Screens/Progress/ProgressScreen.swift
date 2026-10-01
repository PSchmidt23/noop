#if os(iOS)
import SwiftUI
import StrandAnalytics

/// Progress: is the personal baseline itself moving over months? Pushed from the Trends toolbar and the
/// Today row. Draws the baseline alone (never nights) over 90 / 180 / 365 days or all time, one sentence
/// per metric, with the EWMA noise floor deciding "steady". Built once per (data, horizon) in `.task`,
/// exactly Trends' pattern: two fold walks and one sleep pass, sub-millisecond at 4000 rows.
struct ProgressScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage("baseline.progressHorizon") private var horizonRaw: Int = ProgressHorizon.quarter.rawValue
    @State private var snapshot: ProgressSnapshot?

    private struct LoadKey: Equatable {
        let seq: Int
        let loaded: Bool
        let horizon: Int
    }

    private var horizon: ProgressHorizon { ProgressHorizon.resolve(horizonRaw) }

    var body: some View {
        BaselineScreen(title: "Progress") {
            if let s = snapshot {
                if s.totalNights == 0 {
                    emptyState
                } else {
                    // The horizon only changes something once a metric has settled (settling / paused /
                    // ready) or a sleep window can be compared; until then the HRV card leads.
                    if s.hasHorizonContent {
                        BaselineRangePicker<ProgressHorizon>(
                            selection: Binding(get: { horizon }, set: { horizonRaw = $0.rawValue }))
                    }
                    cards(s)
                    Text(ProgressCopy.closingCaption(recalibratedOn: s.recalibratedOn))
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            } else {
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, horizon: horizonRaw)) {
            guard repo.loaded else { snapshot = nil; return }
            // The same night list Today and Sleep build, so the 30-night average is one number everywhere.
            let habitual = await repo.habitualMidsleepSec()
            let nights = SleepNightBuilder.nights(sessions: repo.sleeps, days: repo.days, habitualMidsleepSec: habitual)
            snapshot = ProgressSnapshot.build(days: repo.days, nights: nights, horizon: horizon,
                                              todayKey: Repository.localDayKey(Date()))
        }
    }

    @ViewBuilder
    private func cards(_ s: ProgressSnapshot) -> some View {
        ProgressMetricCard(title: "HRV baseline", noun: "HRV", unit: "ms", color: BaselineTheme.hrv,
                           higherIsBetter: true, status: s.hrv, horizon: s.horizon, todayKey: s.todayKey, step: 5)

        ProgressMetricCard(title: "Resting HR baseline", noun: "resting HR", unit: "bpm", color: BaselineTheme.rhr,
                           higherIsBetter: false, status: s.restingHr, horizon: s.horizon, todayKey: s.todayKey, step: 2)

        ProgressSleepCard(duration: s.sleep.duration, horizon: s.horizon)

        ProgressSleepTimingCard(regularity: s.sleep.regularity, horizon: s.horizon)
    }

    private var emptyState: some View {
        BaselineCard {
            BaselineEmptyState(icon: "chart.line.uptrend.xyaxis",
                               title: ProgressCopy.emptyTitle,
                               message: ProgressCopy.emptyMessage)
        }
    }
}
#endif
