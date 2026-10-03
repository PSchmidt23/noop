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

/// Trends: HRV and resting HR against the personal baseline band, effort bars under the readiness
/// line, sleep and steps bars (steps against the daily goal), Intensity minutes by week and daily
/// calories over a 7 / 30 / 90 day window (the "Trends" section; order HRV, Resting HR, Effort &
/// Readiness, Sleep, Steps, Intensity minutes, Calories), the
/// baseline over months ("Progress", `ProgressSection`) and the journal patterns ("Habits",
/// `JournalPatternsView`). Every card's title opens its `MetricDetailScreen` (`TrendsCardTitle`). One
/// pinned glass control picks the section; the range picker sits flat at the top of the Trends
/// section's content. Series are built once per (data, range) in `.task`; the Intensity weeks follow
/// in the same task from the per-day records (`IntradayDayStore`), so the cards above never wait on a
/// day's heart rate being classified. Settings is the gear in the toolbar.
struct TrendsScreen: View {
    @EnvironmentObject private var repo: Repository
    /// Max heart rate (age or override) for the Intensity thresholds; part of the reload key.
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("baseline.trendsRange") private var rangeRaw: Int = TrendsRange.month.rawValue
    /// Strap-first / merged / import-only precedence (Settings → Data); part of the reload key.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    /// Settings › Profile's "entered" flag: the Intensity weeks are scored only once an age (or a max
    /// heart rate) is entered, the gate Home and the detail use (`IntensityMinutes.mayScore`); until
    /// then the card asks for the age. Part of the reload key.
    @AppStorage(BaselineReadouts.ProfileSet.key) private var profileSet = false
    /// Settings › Activity goals: the daily step goal the Steps card counts "Goal met" days against, and
    /// whether height and weight were entered (the calorie estimate's resting part). Both reload.
    @AppStorage(ActivityGoals.stepKey) private var stepGoal = ActivityGoals.stepDefault
    @AppStorage(ActivityGoals.bodySetKey) private var bodySet = false
    /// Always opens on the charts (a `@State`, not persisted, so a launch is deterministic).
    @State private var section: TrendsSection = .trends
    @State private var series: TrendsSeries?
    /// The Intensity-minutes weeks over the range; nil until read, and the card is left out while
    /// `hasAny` is false.
    @State private var intensity: TrendsIntensity?
    /// Daily calories over the range (the readings the Calories detail draws); nil until read, and the
    /// card is left out while it has no bar.
    @State private var calories: TrendsSeries.BarMetric?
    /// Held in state and rolled on `.NSCalendarDayChanged`, so the window's "today" end moves at midnight
    /// instead of waiting for the next store refresh.
    @State private var todayKey = Repository.localDayKey(Date())

    private struct LoadKey: Equatable {
        let seq: Int
        let range: Int
        let loaded: Bool
        let day: String
        let dataSource: String
        let hrMax: Int
        let entered: Bool
        let stepGoal: Int
        let profile: String
    }

    private var range: TrendsRange { TrendsRange.resolve(rangeRaw) }

    /// What the calorie estimate reads from Settings › Profile; an edit there re-reads the calories.
    private var profileStamp: String {
        "\(bodySet)|\(profile.sex)|\(profile.age)|\(Int(profile.weightKg.rounded()))|\(Int(profile.heightCm.rounded()))"
    }

    var body: some View {
        BaselineScreen(title: "Trends", titleMode: .inline, pinned: {
            // Segment labels are the spoken labels too: `buttons["Progress"]` is a UI-test anchor.
            BaselineSegmentedPicker(options: TrendsSection.allCases, selection: $section,
                                    label: { $0.label }, groupLabel: "Section", style: .glass)
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
                          dataSource: dataSourceRaw, hrMax: profile.hrMax, entered: profileSet,
                          stepGoal: stepGoal, profile: profileStamp)) {
            guard repo.loaded else { series = nil; intensity = nil; calories = nil; return }
            // Steps resolve outside the funnel table (strap counter → phone → strap estimate), over the
            // longest range so the Steps card's "any steps at all" gate does not flip with the picker.
            let now = Date()
            let (startKey, today) = TrendsSeries.window(range: range, now: now)
            let from = Baselines.cutoffKey(todayKey: today, carryDays: TrendsSeries.stepsLookbackDays - 1)
            let steps = await BaselineReadouts.stepReadings(repo, from: from, to: today)
            guard !Task.isCancelled else { return }
            series = TrendsSeries.build(days: repo.baselineDays, range: range, stepReadings: steps,
                                        stepGoal: ActivityGoals.stepGoal(), now: now)

            // Intensity minutes: each day classified once and kept (`IntradayDayStore`), the weeks drawn
            // whole from the Monday the range starts in, behind the same profile gate as Home (the
            // seeded age scores nothing). Read after the series lands, so a first-time classification
            // of ninety days never holds the other cards back.
            let keys = BaselineReadouts.dayKeys(from: TrendsIntensity.lookbackKey(startKey: startKey), to: today)
            let records = await IntradayDayStore.shared.records(repo, profile: profile, days: keys,
                                                                entered: profileSet, now: now)
            guard !Task.isCancelled else { return }
            intensity = TrendsIntensity.build(days: records.values.map { TrendsIntensity.Day($0) },
                                              startKey: startKey, todayKey: today, goal: IntensityMinutes.goal())

            // Calories: each day through the pure builder Home's card reads (`caloriesDay`): the strap's
            // active energy from the same day records (the profile overload estimates it under this
            // profile), Apple Health's active energy as the fallback, resting from the profile.
            let mode = BaselineDataSource.resolve(dataSourceRaw)
            let inputs = await BaselineReadouts.calorieInputs(repo, profile: profile, entered: profileSet,
                                                              bodySet: bodySet, now: now)
            var strap: [String: Double] = [:]
            if mode != .importOnly { for (k, r) in records { if let a = r.activeKcal { strap[k] = a } } }
            let applePoints = await repo.resolvedSeries(key: "active_kcal", source: Repository.appleHealthSource,
                                                        from: Baselines.cutoffKey(todayKey: startKey, carryDays: 30),
                                                        to: today).points
            var apple: [String: Double] = [:]
            for p in applePoints where p.source == Repository.appleHealthSource { apple[p.day] = p.value }
            guard !Task.isCancelled else { return }
            calories = TrendsSeries.caloriesMetric(startKey: startKey, todayKey: today, inputs: inputs,
                                                   strapActive: strap, appleActive: apple, mode: mode,
                                                   todayFraction: BaselineReadouts.dayFraction(now))
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
                BaselineRangePicker<TrendsRange>(selection: Binding(get: { range }, set: { rangeRaw = $0.rawValue }), style: .flat)
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
        TrendBandCard(title: "HRV", key: .hrv, noun: "HRV", unit: "ms", color: BaselineTheme.hrv,
                      higherIsBetter: true, range: s.range, metric: s.hrv)

        TrendBandCard(title: "Resting HR", key: .rhr, noun: "resting HR", unit: "bpm", color: BaselineTheme.rhr,
                      higherIsBetter: false, range: s.range, metric: s.restingHr)

        // Effort bars under the Readiness line; the "All workouts" row closes this card.
        TrendEffortReadinessCard(range: s.range, metric: s.effortReadiness, peak: s.effortPeak)

        // No "Last 30 days" caption on either bar card: the range picker a few points above says it.
        TrendBarCard(
            title: "Sleep",
            key: .sleepDuration,
            range: s.range,
            color: BaselineTheme.sleep,
            bars: s.sleep.bars,
            average: s.sleep.average,
            stats: [
                TrendStat(label: "Average", value: s.sleep.average.map { BaselineReadouts.durationText(minutes: $0 * 60) } ?? "—"),
                TrendStat(label: "7h or more", value: String(s.sleepNights7h),
                          unit: "of \(s.sleepNights) night\(s.sleepNights == 1 ? "" : "s")")
            ],
            emptyText: "No nights of sleep in the last \(s.range.days) days.")

        // Only once some day in the last quarter counted steps: a strap without a counter and no phone
        // steps would otherwise show an empty card forever. The badge says what a step count is worth.
        if s.hasSteps {
            TrendBarCard(
                title: "Steps",
                key: .steps,
                range: s.range,
                accessory: AccuracyBadge(metric: "steps").map { AnyView($0) },
                color: BaselineTheme.steps,
                bars: s.steps.bars,
                average: s.steps.average,
                goal: s.stepGoal.map(Double.init),
                stats: [
                    TrendStat(label: "Average", value: s.steps.average.map { BaselineReadouts.stepsText(Int($0.rounded())) } ?? "—"),
                    TrendStat(label: "Goal met", value: String(s.stepsAtGoal),
                              unit: "of \(s.stepsDays) day\(s.stepsDays == 1 ? "" : "s")")
                ],
                emptyText: "No steps recorded in the last \(s.range.days) days.")
        }

        // Only once some day in the weeks drawn recorded daytime heart rate (or imported workouts with
        // zones): an import-only history would otherwise show an empty card forever.
        if let intensity, intensity.hasAny {
            TrendIntensityCard(range: s.range, intensity: intensity)
        }

        // Only once some day in the range has an estimate. The total per day (resting + active) against
        // its own average over whole days: today's partial total is drawn muted and kept out of it, as
        // Home keeps today out of its comparisons. The badge says what a calorie figure is worth.
        if let calories, !calories.bars.isEmpty {
            TrendBarCard(
                title: "Calories",
                key: .calories,
                range: s.range,
                accessory: AnyView(CaloriesBadges()),
                color: BaselineTheme.effort,
                bars: calories.bars,
                average: calories.average,
                inProgressID: calories.inProgressID,
                stats: [
                    TrendStat(label: "Average", value: BaselineReadouts.caloriesText(calories.average),
                              unit: calories.average == nil ? nil : "kcal"),
                    TrendStat(label: "Days", value: String(calories.bars.count), unit: "of \(s.range.days)")
                ],
                emptyText: "No calorie estimate in the last \(s.range.days) days.")
        }
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
