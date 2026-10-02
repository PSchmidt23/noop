#if os(iOS)
import SwiftUI
import StrandAnalytics

/// Progress: is the personal baseline itself moving over months? Draws the baseline alone (never
/// nights) over 90 / 180 / 365 days or all time, one sentence per metric, with the EWMA noise floor
/// deciding "steady". Lives as the "Progress" section of the Trends tab (`ProgressSection`, embedded in
/// that screen's scroll); `ProgressScreen` is the same content on its own page for the readiness
/// chevron on Home.
struct ProgressScreen: View {
    var body: some View {
        BaselineScreen(title: "Progress", titleMode: .inline) {
            ProgressSection()
        }
    }
}

/// The Progress content: horizon picker (flat, in the content — the pinned row belongs to the screen
/// that embeds this), the HRV / resting HR / sleep / fitness cards and, only after a recalibration, the
/// closing caption. Built once per (data, horizon, data source, profile) in `.task`, exactly Trends'
/// pattern: two fold walks, one sleep pass and one weekly fitness pass, sub-millisecond at 4000 rows.
/// One `VStack`, so a `LazyVStack` host sees a single item and the task runs once.
struct ProgressSection: View {
    @EnvironmentObject private var repo: Repository
    /// Age, sex and body fields for the fitness estimate (Settings › Profile); part of the reload key.
    @EnvironmentObject private var profile: ProfileStore
    /// Whether the person has entered a date of birth and sex (`BaselineReadouts.ProfileSet`, written by
    /// Settings › Profile); until then the store's seeded age and sex are not used. Part of the reload
    /// key through `profileInputs`, so confirming the profile rebuilds the Fitness card at once.
    @AppStorage(BaselineReadouts.ProfileSet.key) private var profileSet = false
    @AppStorage("baseline.progressHorizon") private var horizonRaw: Int = ProgressHorizon.quarter.rawValue
    /// Strap-first / merged / import-only precedence (Settings → Data); part of the reload key.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    @State private var snapshot: ProgressSnapshot?

    private struct LoadKey: Equatable {
        let seq: Int
        let loaded: Bool
        let horizon: Int
        let dataSource: String
        let profile: ProgressProfile
    }

    private var horizon: ProgressHorizon { ProgressHorizon.resolve(horizonRaw) }

    /// The profile as the pure model takes it, through the one resolver: age and sex only once entered,
    /// a waist of 0 is "none".
    private var profileInputs: ProgressProfile {
        ProgressProfile.lifted(from: profile, entered: profileSet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
            if let s = snapshot {
                if s.totalNights == 0 {
                    emptyState
                } else {
                    // The horizon only changes something once a metric has settled (settling / paused /
                    // ready) or a sleep window can be compared; until then the HRV card leads.
                    if s.hasHorizonContent {
                        BaselineRangePicker<ProgressHorizon>(
                            selection: Binding(get: { horizon }, set: { horizonRaw = $0.rawValue }),
                            groupLabel: "Horizon", style: .flat)
                    }
                    cards(s)
                    if s.recalibratedOn != nil {
                        Text(ProgressCopy.closingCaption(recalibratedOn: s.recalibratedOn))
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
            } else {
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, horizon: horizonRaw, dataSource: dataSourceRaw,
                          profile: profileInputs)) {
            guard repo.loaded else { snapshot = nil; return }
            // The same night list Today and Sleep build, so the 30-night average is one number everywhere.
            let days = repo.baselineDays
            let habitual = await repo.habitualMidsleepSec()
            let sessions = await repo.baselineNights()
            let nights = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
            snapshot = ProgressSnapshot.build(days: days, nights: nights, horizon: horizon,
                                              todayKey: Repository.localDayKey(Date()), profile: profileInputs)
        }
    }

    @ViewBuilder
    private func cards(_ s: ProgressSnapshot) -> some View {
        ProgressMetricCard(title: "HRV baseline", noun: "HRV", unit: "ms", color: BaselineTheme.hrv,
                           higherIsBetter: true, status: s.hrv, horizon: s.horizon, todayKey: s.todayKey, step: 5)

        ProgressMetricCard(title: "Resting HR baseline", noun: "resting HR", unit: "bpm", color: BaselineTheme.rhr,
                           higherIsBetter: false, status: s.restingHr, horizon: s.horizon, todayKey: s.todayKey, step: 2)

        ProgressSleepCard(duration: s.sleep.duration, regularity: s.sleep.regularity, horizon: s.horizon)

        ProgressFitnessCard(status: s.fitness, horizon: s.horizon, todayKey: s.todayKey)
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
