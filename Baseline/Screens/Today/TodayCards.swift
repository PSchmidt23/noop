#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Readiness

/// The first card of the day: the readiness tier as a flat pill, one sentence about the week, and the
/// Progress chevron row once the HRV baseline has settled. Readiness is a pill and a sentence, never a
/// ring. The tier is a seven-night reading, so its sentence speaks of the week and never contradicts the
/// one-night delta under the HRV ring.
struct ReadinessCard: View {
    let readiness: TodayReadiness
    /// `ProgressSnapshot.hrvHeadline`, the sentence Progress prints for the persisted horizon; nil hides the row.
    let progressHeadline: String?

    var body: some View {
        BaselineCard(title: "Readiness") {
            BaselinePill(text: pill, color: color)
            if let line {
                Text(line)
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progressHeadline {
                Divider().overlay(BaselineTheme.hairline)
                BaselineChevronRow(text: progressHeadline, systemImage: "chart.line.uptrend.xyaxis",
                                   accessibilityHint: "Opens Progress") { ProgressScreen() }
            }
        }
    }

    /// The calibrating pill names what its count unlocks (readiness, 14 nights), the same shape the ring
    /// tiles use for their own, smaller count ("Baseline after 4 nights · n so far").
    private var pill: String {
        switch readiness {
        case .calibrating(let n): return "Readiness after \(HRVReadiness.minNights) nights · \(n) so far"
        case .stale: return "Paused"
        case .tier(let tier): return tier.baselineLabel
        }
    }

    private var color: Color {
        switch readiness {
        case .calibrating, .stale: return BaselineTheme.textTertiary
        case .tier(let tier): return tier.baselineColor
        }
    }

    /// nil while calibrating: the pill already says when readiness arrives. A tier's sentence is
    /// `ReadinessTier.baselineWeekSentence` (shared vocabulary).
    private var line: String? {
        switch readiness {
        case .calibrating: return nil
        case .stale(let day): return "No HRV since \(TodayFormat.dayLabel(day)). Readiness returns with the next synced night."
        case .tier(let tier): return tier.baselineWeekSentence
        }
    }
}

// MARK: - Rings

/// HRV or resting HR as one `MetricRing` in its own tile: the night's value on a gauge whose domain is
/// the funnel's baseline ± 3σ (`MetricRingScale.domain`), the band as a translucent arc, a baseline tick,
/// and ONE context sentence. A value carried from an earlier morning wears its date ("Woke Mon 28 Sep ·
/// …"); past `Baselines.vitalCarryDays` the numeral is "–", the ring is a bare track and the sentence
/// names the last night instead. Nothing here computes a baseline: `reading.state` is the funnel's.
struct TodayRingTile: View {
    let title: String
    let unit: String
    let color: Color
    let cfg: MetricCfg
    let higherIsBetter: Bool
    let reading: TodayMetricReading?
    /// The selected day's key: a reading dated earlier is a carried value.
    let dayKey: String

    var body: some View {
        BaselineCard(padding: 16) {
            MetricRing(value: reading?.value, domain: domain, color: color, label: title, unit: unit,
                       context: contextText, band: band, baseline: baseline, tone: tone)
        }
    }

    /// The gauge's span; nil (track only) while the baseline is calibrating or the value is stale.
    private var domain: ClosedRange<Double>? {
        guard let r = reading, !r.isStale else { return nil }
        return MetricRingScale.domain(state: r.state, cfg: cfg)
    }

    private var band: ClosedRange<Double>? {
        guard let r = reading, !r.isStale, let low = r.bandLow, let high = r.bandHigh, low <= high else { return nil }
        return low...high
    }

    private var baseline: Double? {
        guard let r = reading, !r.isStale else { return nil }
        return r.baseline
    }

    private var contextText: String {
        guard let r = reading else { return "Waiting for the first night" }
        if r.isStale { return "No night since \(TodayFormat.dayLabel(r.day))" }
        let text: String
        if r.state.usable, let d = r.deviation {
            let delta = abs(d.delta) < 0.5 ? "On your baseline"
                                           : "\(TodayFormat.signed(d.delta, unit: unit)) vs baseline"
            // `BaselineBand.positionPhrase`: the same words Trends and the morning summary use.
            text = r.band.positionPhrase.map { "\(delta) · \($0)" } ?? delta
        } else {
            text = "Baseline after \(Baselines.minNightsSeed) nights · \(r.state.nValid) so far"
        }
        // A carried (still fresh) value from an earlier morning is dated first.
        guard let stamp = TodayFormat.wokeStamp(day: r.day, todayKey: dayKey) else { return text }
        return "\(stamp) · \(text)"
    }

    /// inside → good; above / below → good or watch by the metric's direction; calibrating → tertiary.
    private var tone: Color {
        guard let r = reading, !r.isStale else { return BaselineTheme.textTertiary }
        switch r.band {
        case .inside: return BaselineTheme.good
        case .calibrating: return BaselineTheme.textTertiary
        case .above: return higherIsBetter ? BaselineTheme.good : BaselineTheme.watch
        case .below: return higherIsBetter ? BaselineTheme.watch : BaselineTheme.good
        }
    }
}

// MARK: - Signals

/// The early-warning card, directly under Readiness and only on today, when `TodaySignals.build` found
/// something to say: one calm sentence per signal under a watch-coloured pill, and a single "How this
/// is computed" disclosure listing each signal's method. The screen omits the card entirely when the
/// list is empty, so a quiet morning shows no "all clear" either.
struct SignalsCard: View {
    let signals: TodaySignals
    @State private var showMethod = false

    var body: some View {
        BaselineCard(title: "Signals") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(signals.signals) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        BaselinePill(text: s.pill, color: BaselineTheme.watch)
                        Text(s.sentence)
                            .font(BaselineTheme.body)
                            .foregroundStyle(BaselineTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                DisclosureGroup(isExpanded: $showMethod) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(signals.signals) { s in
                            Text(s.method)
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("How this is computed")
                        .font(BaselineTheme.caption.weight(.semibold))
                        .foregroundStyle(BaselineTheme.accent)
                }
                .tint(BaselineTheme.textTertiary)
            }
        }
    }
}

// MARK: - The night

/// The night leading into the selected morning: the duration numeral, the efficiency cell, the stage
/// bar and one line against the 30-night average. "Last night" on today, "Night" on an earlier day. A
/// night older than the selected morning wears its date as the accessory pill. A flat numeral and a bar,
/// never a ring: the sleep ring lives on the Sleep tab.
struct LastNightCard: View {
    let sleep: TodaySleepReading?
    /// The selected day's key.
    let dayKey: String
    var isToday: Bool = true

    var body: some View {
        BaselineCard(title: isToday ? "Last night" : "Night", accessory: accessory) {
            if let s = sleep {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(BaselineReadouts.durationText(minutes: s.totalMin))
                        .font(BaselineTheme.hero(36))
                        .foregroundStyle(BaselineTheme.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("asleep")
                        .font(BaselineTheme.headline)
                        .foregroundStyle(BaselineTheme.textSecondary)
                    Spacer(minLength: 8)
                    if let e = s.efficiencyPct {
                        StatCell(label: "Efficiency", value: "\(Int(e.rounded()))%")
                            .fixedSize()
                    }
                }
                if s.hasStages {
                    TodayStageBar(stages: s.stages)
                }
                Text(averageLine(s))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(isToday ? "No night recorded yet." : "No night recorded.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
        }
    }

    /// Only when the night is older than the selected morning, so a carried night says so.
    private var accessory: AnyView? {
        guard let s = sleep, let stamp = TodayFormat.wokeStamp(day: s.day, todayKey: dayKey) else { return nil }
        return AnyView(BaselinePill(text: stamp, color: BaselineTheme.textTertiary))
    }

    /// The Sleep tab's average and wording: `BaselineReadouts.sleepAverage30(before:in:)`, "30-night average".
    private func averageLine(_ s: TodaySleepReading) -> String {
        guard let avg = s.avg30Min else {
            return "Your 30\u{2011}night average appears after \(BaselineReadouts.sleepAverageMinNights) nights"
        }
        if let delta = BaselineReadouts.signedDurationText(minutes: s.totalMin - avg) {
            return "\(delta) vs your 30\u{2011}night average"
        }
        return "On your 30\u{2011}night average"
    }
}

/// Slim proportional bar of deep / REM / light / awake. Keeps its explicit height: the card stack is lazy
/// and the bar measures itself with a `GeometryReader`.
struct TodayStageBar: View {
    let stages: [TodayStage]

    var body: some View {
        let total = stages.reduce(0) { $0 + $1.minutes }
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(stages) { s in
                    if total > 0, s.minutes > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BaselineTheme.stageColor(s.id))
                            .frame(width: max(2, geo.size.width * s.minutes / total - 2))
                    }
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Effort

/// The day's effort and its workouts (at most three rows; the chevron row opens the whole list). Each
/// workout row pushes `WorkoutDetailScreen` (resolved by the row's start, the only key `TodayWorkout`
/// carries). The effort number is `BaselineReadouts.effortText`, the same rendering the Workouts
/// screens use. "All workouts" is the visible label of the chevron row (a UI-test anchor).
struct EffortCard: View {
    let effort: Double?
    let workouts: [TodayWorkout]
    var isToday: Bool = true

    /// Rows shown inline before the list takes over.
    static let maxRows = 3

    var body: some View {
        BaselineCard(title: "Effort") {
            HStack(alignment: .top, spacing: 12) {
                StatCell(label: isToday ? "Effort so far" : "Effort", value: BaselineReadouts.effortText(effort),
                         unit: BaselineReadouts.effortUnit, color: BaselineTheme.effort)
                // The sentence below already says when there are none; a "Workouts 0" cell would say it twice.
                if !workouts.isEmpty {
                    StatCell(label: "Workouts", value: "\(workouts.count)")
                }
            }
            if workouts.isEmpty {
                Text(emptyLine)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts.prefix(Self.maxRows)) { w in
                        NavigationLink {
                            WorkoutDetailScreen(startTs: w.id, sport: w.sport)
                        } label: {
                            TodayWorkoutRow(workout: w)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if workouts.count > Self.maxRows {
                    Text("\(workouts.count - Self.maxRows) more in All workouts")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                }
            }
            Divider().overlay(BaselineTheme.hairline)
            BaselineChevronRow(text: "All workouts", accessibilityHint: "Shows every recorded workout") { WorkoutsScreen() }
        }
    }

    private var emptyLine: String {
        if effort == nil {
            return isToday ? "Builds through the day as the strap records." : "Nothing recorded on this day."
        }
        return isToday ? "No workouts recorded yet today." : "No workouts recorded."
    }
}

struct TodayWorkoutRow: View {
    let workout: TodayWorkout

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sportSymbol(workout.sport))
                .font(BaselineTheme.symbol)
                .foregroundStyle(BaselineTheme.effort)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(WorkoutSource.displaySport(workout.sport))
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.text)
                .lineLimit(1)
            Spacer()
            Text(BaselineReadouts.durationText(seconds: workout.durationS))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
            if let hr = workout.avgHr {
                Text("\(hr) bpm")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.rhr)
            }
            Image(systemName: "chevron.right")
                .font(BaselineTheme.symbolSmall)
                .foregroundStyle(BaselineTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
#endif
