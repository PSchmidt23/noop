#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Strap status

/// The one-line status strip once a strap is paired, or the pairing card until then. Observes the
/// registry directly: `AppModel` does not republish when the nested registry's device list changes.
/// The registry is seeded with a placeholder row that has no peripheral, so "non-empty" is not the
/// test (the same rule `WelcomePairActions` applies); an adopted device or a live bond is.
struct StrapStatusSection: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var live: LiveState
    let onPair: () -> Void

    private var paired: Bool {
        live.bonded || registry.devices.contains { $0.peripheralId != nil && !$0.isImportSource }
    }

    var body: some View {
        if paired {
            StrapStatusStrip()
        } else {
            PairStrapCard(onPair: onPair)
        }
    }
}

/// Connection · battery · last sync, with a small Sync control. Context, not a card, so it stays quiet.
/// One line while the caption fits beside the control; at larger type the control drops to its own
/// line and the caption wraps, so the sync time is never truncated away.
struct StrapStatusStrip: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                status
                Spacer(minLength: 8)
                syncButton
            }
            VStack(alignment: .leading, spacing: 6) {
                status
                HStack {
                    Spacer(minLength: 0)
                    syncButton
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(live.connected ? BaselineTheme.good : BaselineTheme.inactive)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var syncButton: some View {
        Button {
            model.ble.syncNow()
        } label: {
            if live.backfilling {
                ProgressView().controlSize(.small).tint(BaselineTheme.accent)
            } else {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(canSync ? BaselineTheme.accent : BaselineTheme.inactive)
        .disabled(!canSync)
        .accessibilityLabel(live.backfilling ? "Syncing" : "Sync strap")
    }

    /// The same gate Settings' "Sync now" applies: a connected AND bonded strap that is not mid-offload.
    private var canSync: Bool { live.connected && live.bonded && !live.backfilling }

    private var statusText: String {
        var parts: [String] = [live.connected ? "Connected" : "Not connected"]
        if live.connected, let pct = live.batteryPct {
            parts.append("\(Int(pct.rounded()))%" + (live.charging == true ? " charging" : ""))
        }
        if live.backfilling {
            parts.append("Syncing…")
        } else if let ts = live.lastSyncedAt {
            parts.append("Synced \(relativeAgo(ts))")
        } else {
            parts.append("Not synced yet")
        }
        return parts.joined(separator: " · ")
    }
}

struct PairStrapCard: View {
    let onPair: () -> Void

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                        .font(BaselineTheme.headline)
                        .foregroundStyle(BaselineTheme.accent)
                    Text("Pair your strap")
                        .font(BaselineTheme.headline)
                        .foregroundStyle(BaselineTheme.text)
                }
                Text("Baseline reads your strap directly over Bluetooth. Pair once and every night lands here, on this phone only.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                Button(action: onPair) {
                    Text("Pair strap")
                        .font(BaselineTheme.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(BaselineTheme.accent)
                .foregroundStyle(BaselineTheme.background)
            }
        }
    }
}

// MARK: - Hero tiles

/// HRV or resting HR: the hero number, where it sits against the baseline, and a 14-night sparkline.
/// A value carried from an earlier morning wears its date ("Woke Mon 28 Sep", the sleep card's stamp);
/// past `Baselines.vitalCarryDays` the tile shows "–" and names the last night instead.
struct TodayHeroTile: View {
    let title: String
    let unit: String
    let color: Color
    let higherIsBetter: Bool
    let reading: TodayMetricReading?
    let todayKey: String

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 14) {
                MetricHero(title: title, value: valueText, unit: unit, color: color,
                           context: contextText, band: reading?.band ?? .calibrating,
                           higherIsBetter: higherIsBetter)
                if let stamp {
                    Text(stamp)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .padding(.top, -8)
                }
                Spacer(minLength: 0)
                if let r = reading, !r.isStale {
                    TodaySparkline(points: r.recent, color: color,
                                   baseline: r.baseline, low: r.bandLow, high: r.bandHigh)
                        .frame(height: 56)
                }
            }
        }
    }

    private var valueText: String {
        reading?.value.map { "\(Int($0.rounded()))" } ?? "–"
    }

    private var contextText: String {
        guard let r = reading else { return "Waiting for the first night" }
        if r.isStale { return "No night since \(TodayFormat.dayLabel(r.day))" }
        guard r.state.usable, let d = r.deviation else {
            return "Baseline after \(Baselines.minNightsSeed) nights · \(r.state.nValid) so far"
        }
        let delta = abs(d.delta) < 0.5 ? "On your baseline"
                                       : "\(TodayFormat.signed(d.delta, unit: unit)) vs baseline"
        // `BaselineBand.positionPhrase`: the same words Trends and the morning summary use.
        guard let position = r.band.positionPhrase else { return delta }
        return "\(delta) · \(position)"
    }

    /// Only for a carried (still fresh) value from an earlier morning.
    private var stamp: String? {
        guard let r = reading, !r.isStale else { return nil }
        return TodayFormat.wokeStamp(day: r.day, todayKey: todayKey)
    }
}

/// Axis-free 14-night line over a flat band of the current normal range (baseline ± sigma).
struct TodaySparkline: View {
    let points: [(day: String, value: Double)]
    let color: Color
    let baseline: Double?
    let low: Double?
    let high: Double?

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                if let low, let high {
                    AreaMark(x: .value("Night", Double(i)), yStart: .value("Low", low), yEnd: .value("High", high))
                        .foregroundStyle(color.opacity(0.12))
                }
                LineMark(x: .value("Night", Double(i)), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let last = points.indices.last {
                PointMark(x: .value("Night", Double(last)), y: .value("Value", points[last].value))
                    .foregroundStyle(color)
                    .symbolSize(36)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0.0...Double(max(1, points.count - 1)))
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let low { values.append(low) }
        if let high { values.append(high) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 1)
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - Signals

/// The early-warning card, directly under the hero tiles and only when `TodaySignals.build` found
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
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(BaselineTheme.accent)
                }
                .tint(BaselineTheme.textTertiary)
            }
        }
    }
}

// MARK: - Last night

struct LastNightCard: View {
    let sleep: TodaySleepReading?
    let todayKey: String

    var body: some View {
        BaselineCard(title: "Last night", subtitle: subtitle) {
            if let s = sleep {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(BaselineReadouts.durationText(minutes: s.totalMin))
                        .font(BaselineTheme.hero(40))
                        .foregroundStyle(BaselineTheme.text)
                        .contentTransition(.numericText())
                    Text("asleep")
                        .font(BaselineTheme.headline)
                        .foregroundStyle(BaselineTheme.textSecondary)
                    Spacer()
                    if let e = s.efficiencyPct {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(e.rounded()))%")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(BaselineTheme.text)
                            Text("efficiency")
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textTertiary)
                        }
                    }
                }
                if s.hasStages {
                    TodayStageBar(stages: s.stages)
                    // Wraps at larger type instead of shrinking and truncating the last stages away.
                    BaselineFlowLayout(spacing: 12) {
                        ForEach(s.stages) { st in
                            HStack(spacing: 5) {
                                Circle().fill(BaselineTheme.stageColor(st.id)).frame(width: 6, height: 6)
                                Text("\(stageLabel(st.id)) \(BaselineReadouts.durationText(minutes: st.minutes))")
                                    .font(BaselineTheme.caption)
                                    .foregroundStyle(BaselineTheme.textSecondary)
                            }
                        }
                    }
                }
                Text(averageLine(s))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            } else {
                Text("No night recorded yet.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
        }
    }

    /// Only when the latest night is older than this morning, so a stale card says so.
    private var subtitle: String? {
        guard let s = sleep else { return nil }
        return TodayFormat.wokeStamp(day: s.day, todayKey: todayKey)
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "deep": return "Deep"
        case "rem": return "REM"
        case "light": return "Light"
        default: return "Awake"
        }
    }

    /// The Sleep tab's average and wording: `BaselineReadouts.sleepAverage30(before:in:)`, "30-night average".
    private func averageLine(_ s: TodaySleepReading) -> String {
        guard let avg = s.avg30Min else {
            return "Your 30-night average appears after \(BaselineReadouts.sleepAverageMinNights) nights"
        }
        if let delta = BaselineReadouts.signedDurationText(minutes: s.totalMin - avg) {
            return "\(delta) vs your 30-night average"
        }
        return "On your 30-night average"
    }
}

/// Slim proportional bar of deep / REM / light / awake.
struct TodayStageBar: View {
    let stages: [TodayStage]

    var body: some View {
        let total = stages.reduce(0) { $0 + $1.minutes }
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(stages) { s in
                    if total > 0, s.minutes > 0 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
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

/// Today's effort and its workouts. Each workout row pushes `WorkoutDetailScreen` (resolved by the
/// row's start, the only key `TodayWorkout` carries), and the quiet link at the foot opens the
/// year's list. The effort number is `BaselineReadouts.effortText`, the same rendering the Workouts
/// screens use.
struct EffortCard: View {
    let effort: Double?
    let workouts: [TodayWorkout]

    var body: some View {
        BaselineCard(title: "Today's effort") {
            HStack(alignment: .top, spacing: 12) {
                StatCell(label: "Effort so far", value: BaselineReadouts.effortText(effort),
                         unit: BaselineReadouts.effortUnit, color: BaselineTheme.effort)
                // The sentence below already says when there are none; a "Workouts 0" cell would say it twice.
                if !workouts.isEmpty {
                    StatCell(label: "Workouts", value: "\(workouts.count)")
                }
            }
            if workouts.isEmpty {
                Text(effort == nil ? "Builds through the day as the strap records."
                                   : "No workouts recorded yet today.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts) { w in
                        NavigationLink {
                            WorkoutDetailScreen(startTs: w.id, sport: w.sport)
                        } label: {
                            TodayWorkoutRow(workout: w)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            NavigationLink {
                WorkoutsScreen()
            } label: {
                HStack(spacing: 4) {
                    Text("All workouts")
                    Image(systemName: "chevron.right")
                        .font(BaselineTheme.symbolSmall)
                }
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(BaselineTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
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

// MARK: - Journal prompt

/// The first few yes-no habits for last night, as the Journal tab's own chips: three states (yes, no,
/// unanswered) and the same yes → no → clear cycle, so a chip here never looks blank while the store
/// holds a "no" the effects engine counts as a control night. Today's key describes the evening and
/// night leading into this morning, the engine's convention, hence "last night" not "yesterday".
struct JournalPromptCard: View {
    let items: [JournalCatalogItem]
    /// Chip-length label for a catalog item (the rename, else `JournalLabels.short`).
    let label: (JournalCatalogItem) -> String
    /// nil = unanswered, true = yes, false = no.
    let answers: [String: Bool]
    let onCycle: (String) -> Void

    var body: some View {
        BaselineCard(title: "Last night's habits",
                     subtitle: "Tap for yes, again for no, once more to clear. The full list lives in Journal.") {
            if items.isEmpty {
                Text("Add questions in the Journal tab.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                BaselineFlowLayout(spacing: 8) {
                    ForEach(items) { item in
                        JournalHabitChip(label: label(item),
                                         state: answers[item.canonical],
                                         action: { onCycle(item.canonical) })
                    }
                }
            }
        }
    }
}
#endif
