#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Strap status

/// The one-line status strip once a strap is paired, or the pairing card until then. Observes the
/// registry directly: `AppModel` does not republish when the nested registry's device list changes.
struct StrapStatusSection: View {
    @ObservedObject var registry: DeviceRegistry
    let onPair: () -> Void

    var body: some View {
        if registry.devices.isEmpty {
            PairStrapCard(onPair: onPair)
        } else {
            StrapStatusStrip()
        }
    }
}

/// Connection · battery · last sync, with a small Sync control. Context, not a card, so it stays quiet.
struct StrapStatusStrip: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(live.connected ? BaselineTheme.good : BaselineTheme.textTertiary)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
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
            .foregroundStyle(live.connected ? BaselineTheme.accent : BaselineTheme.textTertiary)
            .disabled(live.backfilling || !live.connected)
            .accessibilityLabel(live.backfilling ? "Syncing" : "Sync strap")
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        var parts: [String] = [live.connected ? "Strap connected" : "Strap not connected"]
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
struct TodayHeroTile: View {
    let title: String
    let unit: String
    let color: Color
    let higherIsBetter: Bool
    let reading: TodayMetricReading?

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 14) {
                MetricHero(title: title, value: valueText, unit: unit, color: color,
                           context: contextText, band: reading?.band ?? .calibrating,
                           higherIsBetter: higherIsBetter)
                Spacer(minLength: 0)
                TodaySparkline(points: reading?.recent ?? [], color: color,
                               baseline: reading?.baseline, low: reading?.bandLow, high: reading?.bandHigh)
                    .frame(height: 56)
            }
        }
    }

    private var valueText: String {
        reading.map { "\(Int($0.value.rounded()))" } ?? "–"
    }

    private var contextText: String {
        guard let r = reading else { return "Waiting for the first night" }
        guard r.state.usable, let d = r.deviation else {
            return "Calibrating · \(r.state.nValid) of \(Baselines.minNightsSeed) nights"
        }
        if abs(d.delta) < 0.5 { return "On your baseline" }
        return "\(TodayFormat.signed(d.delta, unit: unit)) vs baseline"
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

// MARK: - Last night

struct LastNightCard: View {
    let sleep: TodaySleepReading?
    let todayKey: String

    var body: some View {
        BaselineCard(title: "Last night", subtitle: subtitle) {
            if let s = sleep {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(TodayFormat.hoursMinutes(s.totalMin))
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
                TodayStageBar(stages: s.stages)
                HStack(spacing: 12) {
                    ForEach(s.stages) { st in
                        HStack(spacing: 5) {
                            Circle().fill(BaselineTheme.stageColor(st.id)).frame(width: 6, height: 6)
                            Text("\(stageLabel(st.id)) \(TodayFormat.hoursMinutes(st.minutes))")
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textSecondary)
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
        guard let s = sleep, s.day != todayKey, let d = TodayFormat.date(fromDayKey: s.day) else { return nil }
        return "Woke " + d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "deep": return "Deep"
        case "rem": return "REM"
        case "light": return "Light"
        default: return "Awake"
        }
    }

    private func averageLine(_ s: TodaySleepReading) -> String {
        guard let avg = s.avg30Min else { return "First night on record" }
        if let delta = TodayFormat.signedMinutes(s.totalMin - avg) { return "\(delta) vs your 30-day average" }
        return "On your 30-day average"
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

struct EffortCard: View {
    let effort: Double?
    let workouts: [TodayWorkout]

    var body: some View {
        BaselineCard(title: "Today's effort") {
            HStack(alignment: .top, spacing: 12) {
                StatCell(label: "Effort", value: effort.map { "\(Int($0.rounded()))" } ?? "–",
                         unit: "/ 100", color: BaselineTheme.effort)
                StatCell(label: "Workouts", value: "\(workouts.count)")
            }
            if workouts.isEmpty {
                Text(effort == nil ? "Builds through the day as the strap records."
                                   : "No workouts recorded yet today.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts) { w in TodayWorkoutRow(workout: w) }
                }
            }
        }
    }
}

struct TodayWorkoutRow: View {
    let workout: TodayWorkout

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sportSymbol(workout.sport))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BaselineTheme.effort)
                .frame(width: 18)
            Text(WorkoutSource.displaySport(workout.sport))
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.text)
                .lineLimit(1)
            Spacer()
            Text(TodayFormat.duration(workout.durationS))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
            if let hr = workout.avgHr {
                Text("\(hr) bpm")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.rhr)
            }
        }
    }
}

// MARK: - Journal prompt

struct JournalPromptCard: View {
    let items: [JournalCatalogItem]
    /// Chip-length label per canonical question.
    let labels: [String: String]
    let answers: [String: Bool]
    let onToggle: (String) -> Void

    var body: some View {
        BaselineCard(title: "How was yesterday?", subtitle: "Tap what applies. The full list lives in Journal.") {
            if items.isEmpty {
                Text("Add questions in the Journal tab.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(items) { item in
                        TodayChip(text: labels[item.canonical] ?? item.display,
                                  on: answers[item.canonical] == true) { onToggle(item.canonical) }
                    }
                }
            }
        }
    }
}

struct TodayChip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(BaselineTheme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? BaselineTheme.accent : BaselineTheme.textSecondary)
            .background(on ? BaselineTheme.accent.opacity(0.16) : BaselineTheme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? BaselineTheme.accent.opacity(0.5) : BaselineTheme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
#endif
