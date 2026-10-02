#if os(iOS)
import SwiftUI
import Charts

// The night's reusable builders: the views any screen that shows ONE night composes from, so the Sleep
// tab, a night's detail and the Home 1D sleep view (`MetricDetailScreen`'s `dayView` for sleep) draw the
// same hypnogram and the same heart-rate trace from the same readouts.
//
//   SleepHypnogramCard(night:)          — the "Stages" card (SleepNightCards.swift): timeline + stage cells
//   SleepHeartRateCard(night:)          — "Heart rate while asleep": loads the strap's one-minute means itself
//   SleepHeartRateChart(trace:)         — the pure chart over a `SleepHeartRate`
//   SleepNightDayView(day:)             — both cards for the night ending on a day key, loading the night itself
//   SleepDetail.durationSpec()          — the sleepDuration `MetricDetailSpec` whose 1D view is `SleepNightDayView`

// MARK: - Heart rate while asleep

/// One night's heart rate under the hypnogram's clock: a light area under the line in `rhr` over
/// onset → wake, gaps over ten minutes break the line, a PPG-derived stretch (`conf` < 1) is drawn
/// lighter, never another colour. Flat; inside a card. One VoiceOver element (`accessibilitySummary`).
struct SleepHeartRateChart: View {
    let trace: SleepHeartRate
    var color: Color = BaselineTheme.rhr
    var height: CGFloat = 120
    var accessibilitySummary: String? = nil

    /// A gap longer than this between two points breaks the line (the strap off the wrist).
    static let gapSeconds: TimeInterval = 600

    private struct Run: Identifiable {
        let id: Int
        let measured: Bool
        let points: [SleepHeartRate.Point]
    }

    /// Consecutive points split at gaps and where the signal changes between measured and derived.
    private var runs: [Run] {
        var out: [Run] = []
        var current: [SleepHeartRate.Point] = []
        var measured = true
        for p in trace.points {
            let m = p.conf >= 1
            if let last = current.last, p.date.timeIntervalSince(last.date) > Self.gapSeconds || m != measured {
                out.append(Run(id: current[0].id, measured: measured, points: current))
                current = []
            }
            if current.isEmpty { measured = m }
            current.append(p)
        }
        if !current.isEmpty { out.append(Run(id: current[0].id, measured: measured, points: current)) }
        return out
    }

    /// Tens around the night's one-minute lows and highs, never under 30 bpm.
    private var yDomain: ClosedRange<Double> {
        let lo = max(30, floor((trace.lowBpm - 5) / 10) * 10)
        let hi = ceil((trace.highBpm + 5) / 10) * 10
        return lo...max(hi, lo + 20)
    }

    var body: some View {
        Chart {
            ForEach(runs) { run in
                ForEach(run.points) { p in
                    AreaMark(x: .value("Time", p.date), y: .value("Heart rate", p.bpm), series: .value("s", "a\(run.id)"))
                        .foregroundStyle(color.opacity(run.measured ? BaselineChartStyle.bandOpacity : BaselineChartStyle.envelopeOpacity))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", p.date), y: .value("Heart rate", p.bpm), series: .value("s", "l\(run.id)"))
                        .foregroundStyle(color.opacity(run.measured ? 1 : BaselineChartStyle.baselineOpacity))
                        .lineStyle(StrokeStyle(lineWidth: run.measured ? BaselineChartStyle.lineWidth : 1.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXScale(domain: trace.onset...trace.wake)
        .chartYScale(domain: yDomain)
        .chartYAxis { BaselineChartStyle.yAxis(desiredCount: 3) }
        // The hypnogram's axis (four hour labels over onset → wake), so the two charts line up.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline.opacity(0.75))
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .font(BaselineTheme.caption)
            }
        }
        .chartPlotStyle { $0.background(.clear) }
        .chartLegend(.hidden)
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: accessibilitySummary ?? SleepHeartRateBuilder.summary(trace)))
    }
}

/// "Heart rate while asleep": the trace over the night's clock, then Lowest / Average / Highest cells
/// (one-minute means) and ONE caption naming what a point is. Loads its own trace
/// (`SleepHeartRateBuilder.trace(_:night:)`, reloading on `repo.refreshSeq`) so any screen that has a
/// `SleepNight` can show it. Renders nothing for a night without times (`.dailyMetric`), and a quiet
/// note when the strap banked no heart rate inside the night. The badge is the heart-rate spec's
/// (`MetricDetailSpec.standard(.heartRate)`), so the caveat is written once.
struct SleepHeartRateCard: View {
    let night: SleepNight

    @EnvironmentObject private var repo: Repository
    @State private var trace: SleepHeartRate?
    @State private var loaded = false

    private struct LoadKey: Hashable {
        let seq: Int
        let night: String
        let onset: Int?
    }

    var body: some View {
        if night.onsetTs != nil, night.wakeTs != nil {
            BaselineCard(title: "Heart rate while asleep",
                         accessory: MetricDetailSpec.standard(.heartRate).badge.map { AnyView($0) }) {
                if let trace {
                    SleepHeartRateChart(trace: trace)
                    BaselineStatRow { cells(trace) }
                    Text(SleepHeartRateBuilder.caption(trace))
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if loaded {
                    SleepCardNote(text: "No heart-rate trace for this night. The strap records one while it is worn.")
                } else {
                    ProgressView()
                        .tint(BaselineTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .task(id: LoadKey(seq: repo.refreshSeq, night: night.dayKey, onset: night.onsetTs)) {
                trace = await SleepHeartRateBuilder.trace(repo, night: night)
                loaded = true
            }
        }
    }

    @ViewBuilder private func cells(_ t: SleepHeartRate) -> some View {
        StatCell(label: "Lowest", value: "\(Int(t.lowBpm.rounded()))", unit: "bpm", color: BaselineTheme.rhr)
        StatCell(label: "Average", value: "\(Int(t.averageBpm.rounded()))", unit: "bpm")
        StatCell(label: "Highest", value: "\(Int(t.highBpm.rounded()))", unit: "bpm")
    }
}

// MARK: - One night by day key

/// The night ending on the morning `day` ("yyyy-MM-dd", `SleepNight.dayKey`): its "Stages" card and its
/// "Heart rate while asleep" card, built from the strap-first funnel (`repo.baselineNights()` /
/// `repo.baselineDays`) exactly as the Sleep tab builds its nights, and reloaded on `repo.refreshSeq` and
/// the data-source setting. The 1D content of the sleep detail (`SleepDetail.durationSpec()`), and what
/// Home's day view composes for a night. A card with a note when no night ended that morning.
struct SleepNightDayView: View {
    let day: String

    @EnvironmentObject private var repo: Repository
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    @State private var night: SleepNight?
    @State private var loaded = false

    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let dataSource: String
        let day: String
    }

    var body: some View {
        Group {
            if let night {
                SleepHypnogramCard(night: night)
                SleepHeartRateCard(night: night)
            } else if loaded {
                BaselineCard(title: "Stages") {
                    SleepCardNote(text: "No night recorded for this morning")
                }
            } else {
                BaselineCard(title: "Stages") {
                    ProgressView()
                        .tint(BaselineTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, dataSource: dataSourceRaw, day: day)) {
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        let habitual = await repo.habitualMidsleepSec()
        let sessions = await repo.baselineNights()
        let nights = SleepNightBuilder.nights(sessions: sessions, days: repo.baselineDays, habitualMidsleepSec: habitual)
        night = nights.first { $0.dayKey == day }
        loaded = repo.loaded
    }
}

// MARK: - The sleep detail spec

enum SleepDetail {
    /// `MetricDetailSpec.standard(.sleepDuration)` with the night's cards as its 1D view: the hero card
    /// taps into `MetricDetailScreen(spec: SleepDetail.durationSpec(), day: night.dayKey)`.
    static func durationSpec() -> MetricDetailSpec {
        var spec = MetricDetailSpec.standard(.sleepDuration)
        spec.dayView = { day in AnyView(SleepNightDayView(day: day)) }
        return spec
    }
}
#endif
