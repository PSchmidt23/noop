#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics

// MARK: - Hero

/// The night's headline: big h:mm asleep, bedtime / wake / efficiency, and the night versus the
/// 30-night average as a pill.
struct SleepHeroCard: View {
    let title: String
    let night: SleepNight
    /// Average asleep minutes over the latest 30 nights; nil while there are too few nights.
    let average: Double?

    var body: some View {
        BaselineCard(title: title, subtitle: SleepFormat.dayLabel(night.dayDate), accessory: pill) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(SleepFormat.hhmm(night.asleepMin))
                    .font(BaselineTheme.hero())
                    .foregroundStyle(BaselineTheme.text)
                    .contentTransition(.numericText())
                Text("asleep")
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            HStack(spacing: 12) {
                if let onset = night.onset, let wake = night.wake {
                    StatCell(label: "Bedtime", value: SleepFormat.clock(onset))
                    StatCell(label: "Wake", value: SleepFormat.clock(wake))
                }
                if let eff = SleepFormat.percent(night.efficiency) {
                    StatCell(label: "Efficiency", value: eff)
                }
            }
        }
    }

    private var pill: AnyView? {
        guard let average else { return nil }
        let delta = night.asleepMin - average
        let color: Color = delta >= 15 ? BaselineTheme.good
            : (delta <= -45 ? BaselineTheme.watch : BaselineTheme.sleep)
        return AnyView(BaselinePill(text: SleepFormat.deltaText(asleepMin: night.asleepMin, average: average),
                                    color: color))
    }
}

// MARK: - Hypnogram

/// Stage timeline plus minutes per stage. The chart's slot carries a quiet note instead when the night has
/// no timeline (daily-row or imported nights), and beneath the chart when the strap's staging ran on
/// sparse motion. The stage cells and the proportional bar stay whenever totals exist.
struct SleepHypnogramCard: View {
    let night: SleepNight

    var body: some View {
        BaselineCard(title: "Stages") {
            if let onset = night.onset, let wake = night.wake, night.hasTimeline {
                BaselineHypnogram(segments: night.segments, onset: onset, wake: wake)
                if night.stagingSparse { note("Stages are approximate on this strap") }
            } else {
                note("Stage timeline not available for this night")
            }
            if night.hasStageTotals {
                SleepStageBar(night: night)
                    .frame(height: 6)
                // Four cells in a row while their h:mm values fit; at larger type a 2 × 2 grid, so a
                // value never character-wraps inside a ~70pt cell.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { stageCells }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              alignment: .leading, spacing: 14) { stageCells }
                }
            }
        }
    }

    @ViewBuilder private var stageCells: some View {
        StatCell(label: "Deep", value: SleepFormat.hhmm(night.deepMin), color: BaselineTheme.stageColor("deep"))
        StatCell(label: "REM", value: SleepFormat.hhmm(night.remMin), color: BaselineTheme.stageColor("rem"))
        StatCell(label: "Light", value: SleepFormat.hhmm(night.lightMin), color: BaselineTheme.stageColor("light"))
        StatCell(label: "Awake", value: SleepFormat.hhmm(night.awakeMin), color: BaselineTheme.stageColor("wake"))
    }

    private func note(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(BaselineTheme.caption)
            Text(text).font(BaselineTheme.caption)
        }
        .foregroundStyle(BaselineTheme.textTertiary)
        .padding(.vertical, 4)
    }
}

/// Swift Charts hypnogram: one lane per stage (awake, REM, light, deep from top to bottom), one
/// rectangle per segment, x = clock time.
struct BaselineHypnogram: View {
    let segments: [StageSegment]
    let onset: Date
    let wake: Date
    var height: CGFloat = 150

    private struct Band: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let stage: String
        let lane: String
    }

    private static let lanes = ["Awake", "REM", "Light", "Deep"]

    private static func lane(_ stage: String) -> String {
        switch stage.lowercased() {
        case "deep": return "Deep"
        case "rem": return "REM"
        case "light": return "Light"
        default: return "Awake"
        }
    }

    private var bands: [Band] {
        segments.enumerated().map { i, s in
            Band(id: i,
                 start: Date(timeIntervalSince1970: TimeInterval(s.start)),
                 end: Date(timeIntervalSince1970: TimeInterval(s.end)),
                 stage: s.stage,
                 lane: Self.lane(s.stage))
        }
    }

    var body: some View {
        Chart(bands) { b in
            RectangleMark(xStart: .value("Start", b.start),
                          xEnd: .value("End", b.end),
                          y: .value("Stage", b.lane),
                          height: .ratio(0.7))
                .foregroundStyle(BaselineTheme.stageColor(b.stage))
                .cornerRadius(2)
        }
        .chartYScale(domain: Self.lanes)
        .chartXScale(domain: onset...wake)
        .chartYAxis {
            AxisMarks(position: .leading, values: Self.lanes) { _ in
                AxisValueLabel()
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .font(BaselineTheme.caption)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline)
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .font(BaselineTheme.caption)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Vitals

/// Resting HR, HRV, breathing rate and skin-temperature deviation for the night. Cells without data
/// are hidden; the caller hides the card when nothing is present (`night.hasVitals`).
struct SleepVitalsCard: View {
    let night: SleepNight

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        BaselineCard(title: "Night vitals") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                if let hr = night.restingHr {
                    StatCell(label: "Resting HR", value: "\(hr)", unit: "bpm", color: BaselineTheme.rhr)
                }
                if let hrv = night.avgHrv {
                    StatCell(label: "HRV", value: "\(Int(hrv.rounded()))", unit: "ms", color: BaselineTheme.hrv)
                }
                if let rr = night.respRateBpm {
                    StatCell(label: "Breathing", value: String(format: "%.1f", rr), unit: "/min")
                }
                if let t = night.skinTempDevC {
                    StatCell(label: "Skin temp", value: String(format: "%+.1f", t), unit: "\u{00B0}C")
                }
            }
        }
    }
}

// MARK: - Night row

/// Compact list row: date, h:mm asleep, efficiency, and a thin stage-proportion bar.
struct SleepNightRow: View {
    let night: SleepNight

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(SleepFormat.dayLabel(night.dayDate))
                    .font(BaselineTheme.label)
                    .foregroundStyle(BaselineTheme.text)
                SleepStageBar(night: night)
                    .frame(height: 4)
            }
            Spacer(minLength: 8)
            Text(SleepFormat.hhmm(night.asleepMin))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.text)
            Text(SleepFormat.percent(night.efficiency) ?? "\u{2014}")
                .font(BaselineTheme.caption)
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.textSecondary)
                .frame(width: 38, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(BaselineTheme.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Thin horizontal bar split by stage proportion (deep, REM, light, awake).
struct SleepStageBar: View {
    let night: SleepNight

    private struct Part: Identifiable {
        let id: String
        let minutes: Double
    }

    private var parts: [Part] {
        [Part(id: "deep", minutes: night.deepMin),
         Part(id: "rem", minutes: night.remMin),
         Part(id: "light", minutes: night.lightMin),
         Part(id: "wake", minutes: night.awakeMin)]
    }

    var body: some View {
        GeometryReader { geo in
            let total = parts.reduce(0) { $0 + $1.minutes }
            HStack(spacing: 0) {
                if total > 0 {
                    ForEach(parts) { p in
                        if p.minutes > 0 {
                            Rectangle()
                                .fill(BaselineTheme.stageColor(p.id))
                                .frame(width: geo.size.width * p.minutes / total)
                        }
                    }
                } else {
                    Rectangle().fill(BaselineTheme.hairline)
                }
            }
            .clipShape(Capsule())
        }
    }
}
#endif
