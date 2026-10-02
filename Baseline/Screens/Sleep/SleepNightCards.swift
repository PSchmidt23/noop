#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics

// MARK: - Hero

/// The night's headline: ONE ring ("7h 24m" asleep against the 30-night average, the average as the
/// ring's baseline tick and band) beside bedtime / wake / efficiency cells. The ring's context line is
/// the one place the night is compared with the average; nothing else on the card repeats it.
/// The only ring on the Sleep tab (trademark guardrail: never three circular gauges together).
struct SleepHeroCard: View {
    let title: String
    let night: SleepNight
    /// `BaselineReadouts.sleepAverage30(before:in:)`: the 30 nights before this one; nil while too few.
    let average: Double?
    /// The day label as the card's accessory. `NightDetailScreen` passes false: its title is the day.
    var showsDayLabel: Bool = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Width of the ring column in the side-by-side layout (the 168pt ring plus its line caps), so the
    /// three cells keep a predictable column beside it.
    private static let ringColumn: CGFloat = 184

    var body: some View {
        BaselineCard(title: title, accessory: dayAccessory) {
            // Ring beside the cells while both fit; at accessibility Dynamic Type sizes the ring sits
            // centred over a row of the three cells instead, so a clock like "11:21 PM" never breaks.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    ring.frame(width: Self.ringColumn)
                    VStack(alignment: .leading, spacing: 12) { cells }
                }
                VStack(spacing: 16) {
                    ring
                    BaselineStatRow { cells }
                }
            }
        }
    }

    private var dayAccessory: AnyView? {
        guard showsDayLabel else { return nil }
        return AnyView(
            Text(SleepFormat.dayLabel(night.dayDate))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
        )
    }

    private var ring: some View {
        MetricRing(value: night.asleepMin,
                   domain: MetricRingScale.sleepDomain(average30: average),
                   color: BaselineTheme.sleep,
                   label: "Asleep",
                   unit: "",
                   context: contextText,
                   band: average.map { ($0 - 30)...($0 + 30) },
                   baseline: average,
                   tone: tone,
                   // 200 at accessibility sizes: the scaled "6h 49m" needs the room (the ring is on its
                   // own row there, so the width is free).
                   size: dynamicTypeSize.isAccessibilitySize ? 200 : 168,
                   lineWidth: 12,
                   valueText: BaselineReadouts.durationText(minutes: night.asleepMin),
                   numeralFont: BaselineTheme.hero(36))
    }

    /// The ONE context sentence: the funnel's delta wording (`SleepFormat.deltaText`, the same number
    /// and steady threshold Home's sleep card prints) and the name of the average it is against.
    private var contextText: String {
        guard let average else {
            return "30\u{2011}night average appears after \(BaselineReadouts.sleepAverageMinNights) nights"
        }
        // `deltaText` says "vs average" (the morning summary's wording, where the window is implied);
        // here the window is named once, inside the delta, so the sentence never says "average" twice.
        return SleepFormat.deltaText(asleepMin: night.asleepMin, average: average)
            .replacingOccurrences(of: "vs average", with: "vs your 30\u{2011}night average")
            .replacingOccurrences(of: "On your average", with: "On your 30\u{2011}night average")
    }

    /// Dot before the context: well over the average → good, well under → watch, otherwise the sleep
    /// colour; tertiary while there is no average yet.
    private var tone: Color {
        guard let average else { return BaselineTheme.textTertiary }
        let delta = night.asleepMin - average
        if delta >= 15 { return BaselineTheme.good }
        if delta <= -45 { return BaselineTheme.watch }
        return BaselineTheme.sleep
    }

    @ViewBuilder private var cells: some View {
        if let onset = night.onset, let wake = night.wake {
            StatCell(label: "Bedtime", value: SleepFormat.clock(onset))
            StatCell(label: "Wake", value: SleepFormat.clock(wake))
        }
        if let eff = SleepFormat.percent(night.efficiency) {
            StatCell(label: "Efficiency", value: eff)
        }
    }
}

// MARK: - Hypnogram

/// Stage timeline plus minutes per stage. The chart's slot carries a quiet note instead when the night has
/// no timeline (daily-row or imported nights), and beneath the chart when the strap's staging ran on
/// sparse motion. The stage cells and the proportional bar stay whenever totals exist. Stage colours are
/// fills and dots only: the cell values are ink (light and wake fail as text).
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
                // Four cells in a row while their "1h 12m" values fit; at larger type a 2 × 2 grid, so a
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
        StatCell(label: "Deep", value: BaselineReadouts.durationText(minutes: night.deepMin), dot: BaselineTheme.stageColor("deep"))
        StatCell(label: "REM", value: BaselineReadouts.durationText(minutes: night.remMin), dot: BaselineTheme.stageColor("rem"))
        StatCell(label: "Light", value: BaselineReadouts.durationText(minutes: night.lightMin), dot: BaselineTheme.stageColor("light"))
        StatCell(label: "Awake", value: BaselineReadouts.durationText(minutes: night.awakeMin), dot: BaselineTheme.stageColor("wake"))
    }

    private func note(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(BaselineTheme.symbol).accessibilityHidden(true)
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
                .cornerRadius(3)
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
                AxisGridLine().foregroundStyle(BaselineTheme.hairline.opacity(0.75))
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .font(BaselineTheme.caption)
            }
        }
        .chartPlotStyle { $0.background(.clear) }
        .frame(height: height)
        // One element: the stage cells below carry the totals, so a span is all the timeline needs to say.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage timeline from \(SleepFormat.clock(onset)) to \(SleepFormat.clock(wake))")
    }
}

// MARK: - Vitals (NightDetailScreen only)

/// Resting HR, HRV, breathing rate and skin-temperature deviation for the night. Cells without data
/// are hidden; the caller hides the card when nothing is present (`night.hasVitals`). Shown on a
/// night's detail only: the tab keeps to the ring, the stages and the list.
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

/// Compact list row: date, a thin stage-proportion bar, "7h 24m" asleep, efficiency, chevron.
struct SleepNightRow: View {
    let night: SleepNight

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Date and bar lead, the numbers trail on the same line while they fit; at larger type the
            // numbers drop under the date so "92%" is never squeezed or truncated.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    dateAndBar
                    Spacer(minLength: 8)
                    numbers
                }
                VStack(alignment: .leading, spacing: 6) {
                    dateAndBar
                    numbers
                }
            }
            Image(systemName: "chevron.right")
                .font(BaselineTheme.symbolSmall)
                .foregroundStyle(BaselineTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the night's stages and vitals")
    }

    private var dateAndBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(SleepFormat.dayLabel(night.dayDate))
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.text)
            SleepStageBar(night: night)
                .frame(height: 4)
        }
    }

    private var numbers: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(BaselineReadouts.durationText(minutes: night.asleepMin))
                .font(BaselineTheme.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.text)
            Text(SleepFormat.percent(night.efficiency) ?? "\u{2014}")
                .font(BaselineTheme.caption)
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.textSecondary)
                .frame(minWidth: 38, alignment: .trailing)
        }
        .fixedSize()
    }
}

/// Thin horizontal bar split by stage proportion (deep, REM, light, awake). A `GeometryReader`, so the
/// caller gives it an explicit height (the stack it sits in is lazy).
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
        .accessibilityHidden(true)
    }
}
#endif
