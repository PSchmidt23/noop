#if os(iOS)
import SwiftUI
import Charts
import WhoopStore
import StrandAnalytics

// The generic metric detail: one spec (title, key, unit, colour, accuracy, formatter, optional band
// provider and 1D view) → one pushed screen with a pinned glass range picker (1D / 7D / 4W / 1Y), a hero
// stat row, the chart, one context sentence, the accuracy badge and an "About this metric" footnote.
// Every number comes from `BaselineReadouts.metricSeries` (the funnel); the screen formats and draws.

// MARK: - Spec

/// What a metric detail needs to know about its metric. `standard(_:)` builds the one every key ships
/// with; a screen can pass its own (another colour, a custom 1D view, a different band provider).
struct MetricDetailSpec {
    let key: MetricKey
    /// The navigation title and the card title ("HRV", "Resting HR").
    var title: String
    /// How the metric reads mid-sentence ("HRV", "resting HR", "sleep").
    var noun: String
    var unit: String
    var color: Color
    /// The chart's accessibility hint ("Higher is better"); nil where neither direction is.
    var higherIsBetter: Bool?
    /// `MetricAccuracy` key for the badge; `accuracy` overrides it for a metric the table has no row for.
    var accuracyKey: String?
    var accuracy: (tier: MetricAccuracy.Tier, caveat: String)?
    /// Prints a value in the metric's own spelling ("64", "7h 24m", "11:30 PM").
    var format: (Double) -> String
    /// Prints a difference (defaults to `format` of the magnitude).
    var formatDelta: ((Double) -> String)?
    /// The personal band per day (day key → band) from the funnel's rows ending on the selected day;
    /// nil draws no band. `BaselineReadouts.metricBands` for HRV and resting HR.
    var bandProvider: (([DailyMetric], String) -> [String: MetricBand])?
    /// The 1D content for the selected day key, under the hero (heart rate draws `IntradayHRChart` on
    /// its own). Without one a 1D detail is the hero alone: its "This day" / "Day before" cells already
    /// are the day's number, so no second card repeats it.
    var dayView: ((String) -> AnyView)?
    /// The "About this metric" footnote; defaults to the accuracy caveat.
    var about: String?

    /// The spec every key ships with: Baseline's colours, units, formatters and accuracy rows.
    static func standard(_ key: MetricKey) -> MetricDetailSpec {
        let whole: (Double) -> String = { "\(Int($0.rounded()))" }
        switch key {
        case .hrv:
            return MetricDetailSpec(key: key, title: "HRV", noun: "HRV", unit: "ms", color: BaselineTheme.hrv,
                                    higherIsBetter: true, accuracyKey: "hrv", format: whole,
                                    bandProvider: { BaselineReadouts.metricBands(key: .hrv, days: $0, endKey: $1) })
        case .rhr:
            return MetricDetailSpec(key: key, title: "Resting HR", noun: "resting HR", unit: "bpm", color: BaselineTheme.rhr,
                                    higherIsBetter: false, accuracyKey: "restingHr", format: whole,
                                    bandProvider: { BaselineReadouts.metricBands(key: .rhr, days: $0, endKey: $1) })
        case .readiness:
            return MetricDetailSpec(key: key, title: "Readiness", noun: "Readiness", unit: "/ 100", color: BaselineTheme.accent,
                                    higherIsBetter: true, accuracyKey: "readiness", format: whole)
        case .sleepDuration:
            return MetricDetailSpec(key: key, title: "Sleep", noun: "sleep", unit: "", color: BaselineTheme.sleep,
                                    higherIsBetter: true, accuracyKey: "sleepDuration",
                                    format: { BaselineReadouts.durationText(minutes: $0) })
        case .sleepEfficiency:
            return MetricDetailSpec(key: key, title: "Sleep efficiency", noun: "sleep efficiency", unit: "%", color: BaselineTheme.sleep,
                                    higherIsBetter: true, accuracyKey: "sleepDuration", format: whole)
        case .bedtime:
            return MetricDetailSpec(key: key, title: "Bedtime", noun: "bedtime", unit: "", color: BaselineTheme.sleep,
                                    higherIsBetter: nil, accuracyKey: "sleepTiming",
                                    format: { BaselineReadouts.clockValueText($0, key: .bedtime) },
                                    formatDelta: { BaselineReadouts.durationText(minutes: $0) })
        case .wake:
            return MetricDetailSpec(key: key, title: "Wake time", noun: "wake time", unit: "", color: BaselineTheme.sleep,
                                    higherIsBetter: nil, accuracyKey: "sleepTiming",
                                    format: { BaselineReadouts.clockValueText($0, key: .wake) },
                                    formatDelta: { BaselineReadouts.durationText(minutes: $0) })
        case .steps:
            return MetricDetailSpec(key: key, title: "Steps", noun: "steps", unit: "", color: BaselineTheme.steps,
                                    higherIsBetter: true, accuracyKey: "steps",
                                    format: { BaselineReadouts.stepsText(Int($0.rounded())) })
        case .effort:
            return MetricDetailSpec(key: key, title: "Effort", noun: "effort", unit: "/ 100", color: BaselineTheme.effort,
                                    higherIsBetter: nil, accuracyKey: "effort", format: { BaselineReadouts.effortText($0) })
        case .calories:
            return MetricDetailSpec(key: key, title: "Calories", noun: "calories", unit: "kcal", color: BaselineTheme.effort,
                                    higherIsBetter: nil, accuracyKey: "calories",
                                    format: { BaselineReadouts.caloriesText($0) })
        case .stressAvg:
            return MetricDetailSpec(key: key, title: "Stress", noun: "stress", unit: "of 3", color: BaselineTheme.stress,
                                    higherIsBetter: false, accuracyKey: "stress",
                                    format: { String(format: "%.1f", $0) })
        case .intensityMinutes:
            return MetricDetailSpec(key: key, title: "Intensity minutes", noun: "intensity minutes", unit: "min",
                                    color: BaselineTheme.effort, higherIsBetter: true, accuracyKey: nil,
                                    accuracy: (.medium, BaselineReadouts.IntensityReadout.caveat), format: whole)
        case .heartRate:
            return MetricDetailSpec(key: key, title: "Heart rate", noun: "heart rate", unit: "bpm", color: BaselineTheme.rhr,
                                    higherIsBetter: nil, accuracyKey: nil,
                                    accuracy: (.medium, "Validated against ECG at rest and in steady aerobic exercise; optical readings lag and under-read during strength work and cycling."),
                                    format: whole)
        }
    }

    /// The badge for this spec: the table's row, else the override, else nothing.
    var badge: AccuracyBadge? {
        if let accuracyKey, let b = AccuracyBadge(metric: accuracyKey) { return b }
        if let a = accuracy { return AccuracyBadge(tier: a.tier, caveat: a.caveat, name: title) }
        return nil
    }

    /// The footnote text, when there is one.
    var aboutText: String? {
        if let about { return about }
        if let accuracyKey, let row = MetricAccuracy.lookup(accuracyKey) { return row.caveat }
        return accuracy?.caveat
    }
}

// MARK: - Screen

/// The pushed detail for one metric. `day` is the selected day the ranges end on (Home's day switcher
/// passes its day; defaults to today). The range is the screen's own state, opening on `initialRange`.
struct MetricDetailScreen: View {
    let spec: MetricDetailSpec
    var day: String = Repository.localDayKey(Date())
    var initialRange: MetricRange = .week

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    /// Settings › Profile's "entered" flag: the Intensity series is scored only once an age (or a max
    /// heart rate) is entered, as on Home and the 1D week view; part of the reload key.
    @AppStorage(BaselineReadouts.ProfileSet.key) private var profileSet = false
    @State private var range: MetricRange
    @State private var series: MetricSeries?
    @State private var selected: RangePoint?
    /// The 1D heart-rate trace (the day window and its spans), read once beside the series.
    @State private var dayTrace: BaselineReadouts.IntradayHeartRate?

    init(spec: MetricDetailSpec, day: String = Repository.localDayKey(Date()), initialRange: MetricRange = .week) {
        self.spec = spec
        self.day = day
        self.initialRange = initialRange
        _range = State(initialValue: initialRange)
    }

    private struct LoadKey: Equatable {
        let seq: Int
        let range: MetricRange
        let day: String
        let dataSource: String
        let hrMax: Int
        let entered: Bool
        let loaded: Bool
    }

    var body: some View {
        BaselineScreen(title: spec.title, titleMode: .inline, pinned: {
            BaselineRangePicker(selection: $range, style: .glass)
        }) {
            if let series {
                heroCard(series)
                chartCard(series)
                if let about = spec.aboutText {
                    BaselineCard(title: "About this metric") {
                        Text(about)
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, range: range, day: day, dataSource: dataSourceRaw,
                          hrMax: profile.hrMax, entered: profileSet, loaded: repo.loaded)) {
            await load()
        }
        .onChange(of: range) { _, _ in selected = nil }
    }

    @MainActor
    private func load() async {
        if spec.key == .heartRate, range == .day {
            // One bucket read: the trace feeds both the chart and the series' stats.
            let trace = await BaselineReadouts.intradayHeartRate(repo, for: day)
            dayTrace = trace
            series = BaselineReadouts.metricSeries(key: .heartRate, range: .day, endKey: day, readings: [], intraday: trace)
        } else {
            dayTrace = nil
            series = await BaselineReadouts.metricSeries(repo, profile: profile, key: spec.key, range: range,
                                                         endDay: day, entered: profileSet, bandProvider: spec.bandProvider)
        }
    }

    // MARK: Cards

    private func heroCard(_ s: MetricSeries) -> some View {
        BaselineCard(title: spec.title, accessory: spec.badge.map { AnyView($0) }) {
            let st = s.stats
            if range == .day, spec.key != .heartRate {
                BaselineStatRow {
                    StatCell(label: "This day", value: st.latest.map(spec.format) ?? "–", unit: unitOrNil, color: spec.color)
                    StatCell(label: "Day before", value: st.previousAverage.map(spec.format) ?? "–", unit: unitOrNil)
                }
            } else if !s.isEmpty {
                // An empty window shows no row of dashes: the sentence below says there is nothing in it.
                BaselineStatRow {
                    StatCell(label: "Latest", value: st.latest.map(spec.format) ?? "–", unit: unitOrNil, color: spec.color)
                    StatCell(label: "Average", value: st.average.map(spec.format) ?? "–", unit: unitOrNil)
                    StatCell(label: "Low", value: st.min.map(spec.format) ?? "–", unit: unitOrNil)
                    StatCell(label: "High", value: st.max.map(spec.format) ?? "–", unit: unitOrNil)
                }
            }
            Text(contextSentence(s))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func chartCard(_ s: MetricSeries) -> some View {
        if range == .day {
            if let custom = spec.dayView {
                custom(day)
            } else if spec.key == .heartRate {
                BaselineCard(title: "Through the day") {
                    if let trace = dayTrace {
                        IntradayHRChart(trace: trace, color: spec.color,
                                        accessibilitySummary: BaselineReadouts.intradaySummary(trace))
                        if let caption = traceCaption(trace) {
                            Text(caption)
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("No heart-rate trace for this day. The strap records one while it is worn and off the charger.")
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textSecondary)
                    }
                }
            }
            // Any other key: the hero's "This day" / "Day before" cells are the day; no second card.
        } else {
            // Untitled: the pinned picker's selected pill already names the window ("7D"), so only the
            // scrub line appears here, while a finger is on the chart (as Trends' cards do). An empty
            // window draws no card: the hero's sentence already says there is nothing in it.
            if !s.points.isEmpty {
                BaselineCard {
                    if let subtitle = scrubSubtitle {
                        Text(subtitle)
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    MetricRangeChart(series: s, color: spec.color, selected: $selected,
                                     yLabel: spec.format,
                                     accessibilitySummary: BaselineReadouts.metricChartSummary(series: s, name: spec.title, unit: spec.unit, format: spec.format),
                                     accessibilityHint: spec.higherIsBetter.map { $0 ? "Higher is better" : "Lower is better" })
                    if s.lastBucketPartial {
                        Text("The newest week is still in progress.")
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: Text

    private var unitOrNil: String? { spec.unit.isEmpty ? nil : spec.unit }

    /// Under the hero's cells: what they do not say. Heart rate on 1D gets the day's coverage and spans
    /// (`intradayContext`; the low / mean / high sentence, `intradaySummary`, is the chart's VoiceOver
    /// label only); every other key the comparison sentence (`metricContext`).
    private func contextSentence(_ s: MetricSeries) -> String {
        if spec.key == .heartRate, range == .day, let t = dayTrace {
            return BaselineReadouts.intradayContext(t)
        }
        // Nothing scored because no age or max heart rate is set: say what fills it, not "no days".
        if spec.key == .intensityMinutes, s.points.isEmpty,
           !IntensityMinutes.mayScore(entered: profileSet, hrMaxOverride: profile.hrMaxOverride) {
            return IntensityMinutes.Basis.needsAge.caption + "."
        }
        return BaselineReadouts.metricContext(series: s, noun: spec.noun, unit: spec.unit,
                                              format: spec.format, delta: spec.formatDelta)
    }

    /// Under the day trace, only when it has no shading: the chart's own legend ("Asleep", "Workout")
    /// already says how to read the shaded spans, and coverage ("Partial day: …") is the hero's.
    private func traceCaption(_ t: BaselineReadouts.IntradayHeartRate) -> String? {
        guard t.sleep.isEmpty, t.workouts.isEmpty else { return nil }
        return "Measured every second while the strap was worn."
    }

    /// While scrubbing: the point's day (or week) and value.
    private var scrubSubtitle: String? {
        guard let p = selected else { return nil }
        let v = spec.format(p.value) + (spec.unit.isEmpty ? "" : " \(spec.unit)")
        if range.bucket == .week {
            return "Week of \(TrendsFormat.shortDate(p.date)) · average \(v) over \(p.n) day\(p.n == 1 ? "" : "s")"
        }
        return "\(TrendsFormat.shortDate(p.date)) · \(v)"
    }
}

// MARK: - Range chart

/// 7D / 4W / 1Y: a line over its personal band (when the points carry one) and, for bucketed points,
/// the lows-to-highs envelope; bars with an average rule for count-like metrics. Scrub shows the
/// nearest point through `selected`. One VoiceOver element (`accessibilitySummary`).
struct MetricRangeChart: View {
    let series: MetricSeries
    let color: Color
    var height: CGFloat = 180
    @Binding var selected: RangePoint?
    /// Axis labels in the metric's spelling.
    var yLabel: (Double) -> String = { "\(Int($0.rounded()))" }
    var accessibilitySummary: String? = nil
    var accessibilityHint: String? = nil

    private var points: [RangePoint] { series.points }
    private var isBars: Bool { series.key.isCountLike }
    private var isWeekly: Bool { series.range.bucket == .week }
    private var hasEnvelope: Bool { !isBars && points.contains { $0.min != nil && $0.max != nil } }

    var body: some View {
        Chart {
            if isBars {
                ForEach(points) { p in
                    BarMark(x: .value("Day", p.date, unit: isWeekly ? .weekOfYear : .day), y: .value("Value", p.value))
                        .foregroundStyle(color.opacity(BaselineChartStyle.barOpacity))
                        .cornerRadius(BaselineChartStyle.barRadius)
                }
                if let avg = series.stats.average {
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            } else {
                ForEach(points) { p in
                    if let b = p.band {
                        AreaMark(x: .value("Day", p.date), yStart: .value("Low", b.low), yEnd: .value("High", b.high))
                            .foregroundStyle(color.opacity(BaselineChartStyle.bandOpacity))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Day", p.date), y: .value("Baseline", b.baseline), series: .value("s", "baseline"))
                            .foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .interpolationMethod(.monotone)
                    }
                }
                if hasEnvelope {
                    ForEach(points) { p in
                        if let lo = p.min, let hi = p.max {
                            AreaMark(x: .value("Day", p.date), yStart: .value("Lowest", lo), yEnd: .value("Highest", hi), series: .value("s", "envelope"))
                                .foregroundStyle(color.opacity(BaselineChartStyle.envelopeOpacity))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
                ForEach(points) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Value", p.value), series: .value("s", "value"))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last {
                    PointMark(x: .value("Day", last.date), y: .value("Value", last.value))
                        .foregroundStyle(color).symbolSize(50)
                }
            }
            if let s = selected {
                RuleMark(x: .value("Day", s.date)).foregroundStyle(BaselineTheme.hairline)
                PointMark(x: .value("Day", s.date), y: .value("Value", s.value))
                    .symbol { BaselineChartStyle.selectedPoint(color) }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline.opacity(0.75))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(yLabel(d)).foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
                    }
                }
            }
        }
        .chartXAxis { xAxis }
        .chartXScale(domain: xDomain, range: .plotDimension(endPadding: isBars ? 0 : 18))
        .chartPlotStyle { $0.background(.clear) }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard let plot = proxy.plotFrame else { return }
                            let x = g.location.x - geo[plot].origin.x
                            if let date: Date = proxy.value(atX: x) {
                                selected = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) { selected = nil }
                        })
            }
        }
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: accessibilitySummary))
        .modifier(OptionalAccessibilityHint(hint: accessibilityHint))
    }

    /// Months over a year, days otherwise (the same axes Progress and Trends draw).
    /// The whole window, not the extent of the points: a 7D series with one recorded day draws one
    /// day-wide bar on a seven-day axis (a data-extent domain stretched that bar across the chart and
    /// printed its date twice). Bars reach the end of their last bucket; lines end on its start.
    private var xDomain: ClosedRange<Date> {
        let bucket = series.range.bucket
        let cal = Calendar.current
        if let s = BaselineRangeSeries.bucketStart(of: series.startKey, bucket: bucket),
           let e = BaselineRangeSeries.bucketStart(of: series.endKey, bucket: bucket),
           let lo = BaselineReadouts.localMidnight(of: s),
           let lastStart = BaselineReadouts.localMidnight(of: e) {
            let hi = isBars ? (cal.date(byAdding: .day, value: isWeekly ? 7 : 1, to: lastStart) ?? lastStart) : lastStart
            if hi > lo { return lo...hi }
        }
        let dates = points.map(\.date)
        let lo = dates.min() ?? Date()
        let hi = dates.max() ?? lo
        return lo...max(hi, lo.addingTimeInterval(86_400))
    }

    private var xAxis: AnyAxisContent {
        series.range == .year
            ? AnyAxisContent(BaselineChartStyle.monthAxis(spansOverAYear: false))
            : AnyAxisContent(BaselineChartStyle.dayAxis(desiredCount: series.range == .week ? 3 : 4))
    }

    /// Values, band edges and envelope with ~12% padding; bars start at zero.
    private var yDomain: ClosedRange<Double> {
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        for p in points {
            lo = min(lo, p.value, p.band?.low ?? p.value, hasEnvelope ? (p.min ?? p.value) : p.value)
            hi = max(hi, p.value, p.band?.high ?? p.value, hasEnvelope ? (p.max ?? p.value) : p.value)
        }
        guard lo <= hi else { return 0...1 }
        if isBars { return 0...max(hi * 1.12, 1) }
        let pad = max(hi - lo, 1) * 0.12
        return max(0, lo - pad)...(hi + pad)
    }
}

// MARK: - Intraday chart

/// 1D heart rate: a light area under the line over the local day (00:00 → 24:00), the night(s)
/// shaded in `sleep`, workouts shaded in `effort` with a marker at their start. Gaps over ten minutes
/// break the line; a PPG-derived stretch (WHOOP 5.0 / MG, `conf` < 1) is drawn lighter, never another
/// colour. One VoiceOver element (`BaselineReadouts.intradaySummary`).
struct IntradayHRChart: View {
    let trace: BaselineReadouts.IntradayHeartRate
    var color: Color = BaselineTheme.rhr
    var height: CGFloat = 180
    var accessibilitySummary: String? = nil

    /// A gap longer than this between two points breaks the line.
    static let gapSeconds: TimeInterval = 600

    private struct Run: Identifiable {
        let id: Int
        let measured: Bool
        let points: [BaselineReadouts.IntradayHeartRate.Point]
    }

    private var runs: [Run] {
        var out: [Run] = []
        var current: [BaselineReadouts.IntradayHeartRate.Point] = []
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

    private var yDomain: ClosedRange<Double> {
        let lo = max(30, (floor((trace.minBpm - 5) / 10)) * 10)
        let hi = (ceil((trace.maxBpm + 5) / 10)) * 10
        return lo...max(hi, lo + 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(trace.sleep) { s in
                    RectangleMark(xStart: .value("From", s.start), xEnd: .value("To", s.end),
                                  yStart: .value("Low", yDomain.lowerBound), yEnd: .value("High", yDomain.upperBound))
                        .foregroundStyle(BaselineTheme.sleep.opacity(BaselineChartStyle.bandOpacity))
                }
                ForEach(trace.workouts) { w in
                    RectangleMark(xStart: .value("From", w.start), xEnd: .value("To", w.end),
                                  yStart: .value("Low", yDomain.lowerBound), yEnd: .value("High", yDomain.upperBound))
                        .foregroundStyle(BaselineTheme.effort.opacity(BaselineChartStyle.bandOpacity))
                    PointMark(x: .value("Start", w.start), y: .value("Top", yDomain.upperBound))
                        .foregroundStyle(BaselineTheme.effort).symbolSize(30)
                }
                ForEach(runs) { run in
                    ForEach(run.points) { p in
                        // From the bottom of the y domain, not from zero: an area to 0 bpm is drawn below the
                        // plot (over the axis labels and the legend) when the domain starts at 40.
                        AreaMark(x: .value("Time", p.date), yStart: .value("Floor", yDomain.lowerBound),
                                 yEnd: .value("Heart rate", p.bpm), series: .value("s", "a\(run.id)"))
                            .foregroundStyle(color.opacity(run.measured ? BaselineChartStyle.bandOpacity : BaselineChartStyle.envelopeOpacity))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", p.date), y: .value("Heart rate", p.bpm), series: .value("s", "l\(run.id)"))
                            .foregroundStyle(color.opacity(run.measured ? 1 : BaselineChartStyle.baselineOpacity))
                            .lineStyle(StrokeStyle(lineWidth: run.measured ? BaselineChartStyle.lineWidth : 1.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXScale(domain: trace.dayStart...trace.dayEnd)
            .chartYScale(domain: yDomain)
            .chartYAxis { BaselineChartStyle.yAxis() }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour(), collisionResolution: .greedy)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .font(BaselineTheme.caption)
                }
            }
            .chartPlotStyle { $0.background(.clear).clipped() }
            .chartLegend(.hidden)
            .frame(height: height)
            .modifier(BaselineChartSummary(summary: accessibilitySummary))

            if !trace.sleep.isEmpty || !trace.workouts.isEmpty {
                HStack(spacing: 14) {
                    if !trace.sleep.isEmpty { legend("Asleep", BaselineTheme.sleep) }
                    if !trace.workouts.isEmpty { legend("Workout", BaselineTheme.effort) }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func legend(_ text: String, _ swatch: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(swatch).frame(width: 6, height: 6)
            Text(text).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        }
    }
}

extension BaselineChartStyle {
    /// The lows-to-highs envelope under a weekly line, and a PPG-derived stretch of the day trace:
    /// metric colour at this opacity, lighter than the personal band so the two never read as one.
    static let envelopeOpacity = 0.07
}
#endif
