#if os(iOS)
import SwiftUI
import Charts

// Bedtime and wake over time, pushed from the Sleep tab's timing card: a pinned glass 7D / 4W / 1Y
// picker, a hero card (average bedtime, average wake, nights, one context sentence, the sleep-timing
// badge), the chart card (bedtime and wake as two lines on a noon-to-noon clock axis with the target
// window shaded; 1Y draws weekly means with their lows-to-highs envelopes) and the "About" footnote.
// The numbers come from `BaselineReadouts.metricSeries` over the `.bedtime` and `.wake` keys (the same
// readings `MetricDetailScreen` would show for either on its own); this screen only lays the two
// side by side, which a single-key detail cannot.

// MARK: - Range

/// The timing detail's window: the three ranges a clock-time series can show (a 1D bedtime is a cell on
/// the night's card, not a chart). Each maps onto its `MetricRange`.
enum SleepTimingRange: String, CaseIterable, Identifiable, BaselineRangeOption {
    case week, fourWeeks, year

    var id: String { rawValue }

    var metricRange: MetricRange {
        switch self {
        case .week: return .week
        case .fourWeeks: return .fourWeeks
        case .year: return .year
        }
    }

    var label: String { metricRange.label }
    var subtitle: String { metricRange.subtitle }
    var shortLabel: String { metricRange.shortLabel }
}

// MARK: - Model (pure; `SleepTimingDetailTests`)

/// Everything the screen draws for one day, one range and one target window. Bedtime values are minutes
/// after the previous NOON and wake values minutes after midnight (`MetricKey.isClockTime`); on the chart
/// both sit on one noon-to-noon axis (`noonAxis`), where a wake time is its minutes plus 720.
struct SleepTimingDetail {
    /// One x position on the chart: a day, or a week's Monday for 1Y, carrying whichever of the two
    /// lines has a value there (noon-axis minutes), with the bucket's lows and highs for the envelope.
    struct Row: Identifiable, Equatable {
        let id: String
        let date: Date
        let bed: Double?
        let bedLow: Double?
        let bedHigh: Double?
        let wake: Double?
        let wakeLow: Double?
        let wakeHigh: Double?
        /// Nights behind the row (1 for a day; the week's count for 1Y).
        let n: Int
    }

    let range: MetricRange
    let bed: MetricSeries
    let wake: MetricSeries
    let target: BaselineReadouts.SleepWindow
    let rows: [Row]

    /// The detail for the window ending on `day` over the Sleep tab's `nights` (any order; nights without
    /// times are skipped by the readings).
    static func build(day: String, nights: [SleepNight], range: MetricRange, window: BaselineReadouts.SleepWindow,
                      calendar: Calendar = .current) -> SleepTimingDetail {
        let bedReadings = BaselineReadouts.metricReadings(key: .bedtime, days: [], nights: nights, calendar: calendar)
        let wakeReadings = BaselineReadouts.metricReadings(key: .wake, days: [], nights: nights, calendar: calendar)
        let bed = BaselineReadouts.metricSeries(key: .bedtime, range: range, endKey: day, readings: bedReadings, calendar: calendar)
        let wake = BaselineReadouts.metricSeries(key: .wake, range: range, endKey: day, readings: wakeReadings, calendar: calendar)
        return SleepTimingDetail(range: range, bed: bed, wake: wake, target: window, rows: rows(bed: bed, wake: wake))
    }

    /// Bed and wake points merged by their id (a day key or a week's Monday), oldest first.
    static func rows(bed: MetricSeries, wake: MetricSeries) -> [Row] {
        let bedById = Dictionary(bed.points.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wakeById = Dictionary(wake.points.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Set(bedById.keys).union(wakeById.keys).sorted().compactMap { id in
            let b = bedById[id], w = wakeById[id]
            guard let date = b?.date ?? w?.date else { return nil }
            return Row(id: id, date: date,
                       bed: b?.value, bedLow: b?.min, bedHigh: b?.max,
                       wake: w.map { noonAxis(wakeMinutes: $0.value) },
                       wakeLow: w?.min.map { noonAxis(wakeMinutes: $0) },
                       wakeHigh: w?.max.map { noonAxis(wakeMinutes: $0) },
                       n: max(b?.n ?? 0, w?.n ?? 0))
        }
    }

    /// A wake clock time (minutes after midnight) on the noon-to-noon axis: 7:00 AM → 1 140.
    static func noonAxis(wakeMinutes: Double) -> Double { wakeMinutes + 720 }

    /// A bedtime clock time (minutes after midnight) on the noon-to-noon axis: 11:00 PM → 660, 12:30 AM → 750.
    static func noonAxis(bedMinutes: Double) -> Double { (bedMinutes + 720).truncatingRemainder(dividingBy: 1440) }

    /// The noon-axis minute back to a clock time: 1 140 → 7:00 AM.
    static func clockMinutes(noonAxis v: Double) -> Double { (v + 720).truncatingRemainder(dividingBy: 1440) }

    /// The target window on the noon axis (bed → wake; a window reaching past the next noon is clipped).
    var targetBand: ClosedRange<Double> {
        let lo = Self.noonAxis(bedMinutes: Double(target.bedMinutes))
        let hi = min(1440, Self.noonAxis(wakeMinutes: Double(target.wakeMinutes)))
        return lo...max(lo, hi)
    }

    /// The chart's y range: every value, envelope edge and the target band, with an hour of air on
    /// each side, inside one noon-to-noon day.
    var yDomain: ClosedRange<Double> {
        var lo = targetBand.lowerBound, hi = targetBand.upperBound
        for r in rows {
            for v in [r.bed, r.bedLow, r.wake, r.wakeHigh].compactMap({ $0 }) {
                lo = min(lo, v); hi = max(hi, v)
            }
        }
        return max(0, lo - 60)...min(1440, hi + 60)
    }

    /// Whole hours inside `yDomain`, every `stepHours`, for the axis.
    func axisTicks(stepHours: Int = 3) -> [Double] {
        let step = Double(stepHours * 60)
        let first = (yDomain.lowerBound / step).rounded(.up) * step
        return Array(stride(from: first, through: yDomain.upperBound, by: step))
    }

    /// Nights in the window with both times.
    var nightCount: Int { min(bed.stats.count, wake.stats.count) }

    var averageBedText: String { bed.stats.average.map { BaselineReadouts.clockValueText($0, key: .bedtime) } ?? "\u{2014}" }
    var averageWakeText: String { wake.stats.average.map { BaselineReadouts.clockValueText($0, key: .wake) } ?? "\u{2014}" }

    /// The ONE context sentence: the window's averages, then how each moved against the period before,
    /// said once. "Bedtime averaged 11:24 PM and wake 7:02 AM over the last 7 days; bedtime 18 min
    /// later and wake about the same as the 7 days before."
    var contextText: String {
        guard let bedAvg = bed.stats.average, let wakeAvg = wake.stats.average else {
            return "No nights with bed and wake times in \(range.phrase)."
        }
        var s = "Bedtime averaged \(BaselineReadouts.clockValueText(bedAvg, key: .bedtime)) and wake "
            + "\(BaselineReadouts.clockValueText(wakeAvg, key: .wake)) over \(range.phrase)"
        if let bedShift = Self.shiftWords(bed.stats.change), let wakeShift = Self.shiftWords(wake.stats.change) {
            s += "; bedtime \(bedShift) and wake \(wakeShift) \(Self.beforeWords(range))"
        }
        return s + "."
    }

    /// "18 min later" / "1h 05m earlier" / "about the same"; nil when there is no comparison.
    static func shiftWords(_ change: Double?) -> String? {
        guard let change else { return nil }
        let m = abs(change)
        if m < Double(BaselineReadouts.durationSteadyMin) { return "about the same as" }
        return "\(BaselineReadouts.durationText(minutes: m)) \(change > 0 ? "later than" : "earlier than")"
    }

    static func beforeWords(_ range: MetricRange) -> String {
        switch range {
        case .day: return "the day before"
        case .week: return "the 7 days before"
        case .fourWeeks: return "the 4 weeks before"
        case .year: return "the year before"
        }
    }

    /// The chart's ONE VoiceOver sentence: the window, the night count, both lines' spans and the target.
    var chartSummary: String {
        var s = "Bedtime and wake, \(range.subtitle.lowercased()): "
        guard nightCount > 0, let bLo = bed.stats.min, let bHi = bed.stats.max,
              let wLo = wake.stats.min, let wHi = wake.stats.max else {
            return s + "no nights recorded."
        }
        s += "\(nightCount) night\(nightCount == 1 ? "" : "s"), bedtime from "
            + "\(BaselineReadouts.clockValueText(bLo, key: .bedtime)) to \(BaselineReadouts.clockValueText(bHi, key: .bedtime)), "
            + "wake from \(BaselineReadouts.clockValueText(wLo, key: .wake)) to \(BaselineReadouts.clockValueText(wHi, key: .wake))"
        s += "; target window \(targetText)"
        return s + "."
    }

    /// "11:00 PM–7:00 AM".
    var targetText: String {
        "\(BaselineReadouts.clockText(minutes: Double(target.bedMinutes)))\u{2013}"
            + BaselineReadouts.clockText(minutes: Double(target.wakeMinutes))
    }

    /// While scrubbing: "Sep 28 · bed 11:24 PM · wake 7:02 AM", or for a week "Week of Sep 22 · average
    /// bed 11:24 PM · wake 7:02 AM over 6 nights".
    func scrubText(_ row: Row) -> String {
        let bedText = row.bed.map { BaselineReadouts.clockValueText($0, key: .bedtime) } ?? "\u{2014}"
        let wakeText = row.wake.map { BaselineReadouts.clockText(minutes: Self.clockMinutes(noonAxis: $0)) } ?? "\u{2014}"
        if range.bucket == .week {
            return "Week of \(TrendsFormat.shortDate(row.date)) \u{00B7} average bed \(bedText) \u{00B7} wake \(wakeText) over \(row.n) night\(row.n == 1 ? "" : "s")"
        }
        return "\(TrendsFormat.shortDate(row.date)) \u{00B7} bed \(bedText) \u{00B7} wake \(wakeText)"
    }
}

// MARK: - Screen

/// The pushed bedtime / wake detail. `day` is the morning the window ends on (the Sleep tab passes its
/// latest night's key). The nights come from the same funnel the tab reads, reloaded on
/// `repo.refreshSeq`, `repo.loaded` and the data-source setting; the target window is observed through
/// its keys so a change made in Settings redraws the band on the way back.
struct SleepTimingDetailScreen: View {
    let day: String
    var initialRange: SleepTimingRange = .week

    @EnvironmentObject private var repo: Repository
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    @AppStorage(BaselineReadouts.SleepWindow.bedKey) private var windowBed = BaselineReadouts.SleepWindow.default.bedMinutes
    @AppStorage(BaselineReadouts.SleepWindow.wakeKey) private var windowWake = BaselineReadouts.SleepWindow.default.wakeMinutes
    @State private var range: SleepTimingRange
    @State private var nights: [SleepNight] = []
    @State private var loaded = false
    @State private var selected: SleepTimingDetail.Row?

    init(day: String, initialRange: SleepTimingRange = .week) {
        self.day = day
        self.initialRange = initialRange
        _range = State(initialValue: initialRange)
    }

    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let dataSource: String
    }

    private var window: BaselineReadouts.SleepWindow {
        func valid(_ v: Int, _ fallback: Int) -> Int { (0..<1440).contains(v) ? v : fallback }
        return BaselineReadouts.SleepWindow(bedMinutes: valid(windowBed, BaselineReadouts.SleepWindow.default.bedMinutes),
                                            wakeMinutes: valid(windowWake, BaselineReadouts.SleepWindow.default.wakeMinutes))
    }

    private var detail: SleepTimingDetail {
        SleepTimingDetail.build(day: day, nights: nights, range: range.metricRange, window: window)
    }

    var body: some View {
        BaselineScreen(title: "Bedtime and wake", titleMode: .inline, pinned: {
            BaselineRangePicker(selection: $range, style: .glass)
        }) {
            if loaded {
                let d = detail
                heroCard(d)
                chartCard(d)
                if let about = MetricAccuracy.lookup("sleepTiming")?.caveat {
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
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, dataSource: dataSourceRaw)) { await reload() }
        .onChange(of: range) { _, _ in selected = nil }
    }

    private func heroCard(_ d: SleepTimingDetail) -> some View {
        BaselineCard(title: "Bedtime and wake", accessory: AccuracyBadge(metric: "sleepTiming").map { AnyView($0) }) {
            BaselineStatRow {
                StatCell(label: "Average bedtime", value: d.averageBedText, color: BaselineTheme.sleep)
                StatCell(label: "Average wake", value: d.averageWakeText, color: BaselineTheme.sleep)
                StatCell(label: "Nights", value: "\(d.nightCount)")
            }
            Text(d.contextText)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chartCard(_ d: SleepTimingDetail) -> some View {
        // Untitled, as on `MetricDetailScreen`: the pinned picker's selected pill names the window, so
        // only the scrub line appears here, while a finger is on the chart.
        BaselineCard {
            if let selected {
                Text(d.scrubText(selected))
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if d.rows.isEmpty {
                Text("No nights with bed and wake times in \(range.metricRange.phrase).")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            } else {
                SleepTimingRangeChart(detail: d, selected: $selected)
                // The window's clock times, said once on this screen.
                Text(d.bed.lastBucketPartial
                     ? "Target window \(d.targetText) shaded \u{00B7} the newest week is still in progress."
                     : "Target window \(d.targetText) shaded.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private func reload() async {
        let habitual = await repo.habitualMidsleepSec()
        let sessions = await repo.baselineNights()
        nights = SleepNightBuilder.nights(sessions: sessions, days: repo.baselineDays, habitualMidsleepSec: habitual)
        loaded = repo.loaded
    }
}

// MARK: - Chart

/// Bedtime and wake as two lines over one noon-to-noon clock axis: the target window as a `sleep` band
/// (`bandOpacity`) across the whole width, bedtime in `sleep`, wake in `sleep` at `baselineOpacity`, a
/// lows-to-highs envelope under each weekly line (`envelopeOpacity`), day or month labels along x and
/// whole hours along y in the device's clock style (`BaselineReadouts.hourText`). Scrub shows the
/// nearest row through `selected`. One VoiceOver element (`SleepTimingDetail.chartSummary`).
struct SleepTimingRangeChart: View {
    let detail: SleepTimingDetail
    var height: CGFloat = 200
    @Binding var selected: SleepTimingDetail.Row?

    private var rows: [SleepTimingDetail.Row] { detail.rows }
    private var isWeekly: Bool { detail.range.bucket == .week }
    private var bedColor: Color { BaselineTheme.sleep }
    private var wakeColor: Color { BaselineTheme.sleep.opacity(BaselineChartStyle.baselineOpacity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                RectangleMark(yStart: .value("Target bed", detail.targetBand.lowerBound),
                              yEnd: .value("Target wake", detail.targetBand.upperBound))
                    .foregroundStyle(BaselineTheme.sleep.opacity(BaselineChartStyle.bandOpacity))
                if isWeekly {
                    ForEach(rows) { r in
                        if let lo = r.bedLow, let hi = r.bedHigh {
                            AreaMark(x: .value("Week", r.date), yStart: .value("Earliest bed", lo), yEnd: .value("Latest bed", hi),
                                     series: .value("s", "bed-envelope"))
                                .foregroundStyle(bedColor.opacity(BaselineChartStyle.envelopeOpacity))
                                .interpolationMethod(.monotone)
                        }
                        if let lo = r.wakeLow, let hi = r.wakeHigh {
                            AreaMark(x: .value("Week", r.date), yStart: .value("Earliest wake", lo), yEnd: .value("Latest wake", hi),
                                     series: .value("s", "wake-envelope"))
                                .foregroundStyle(bedColor.opacity(BaselineChartStyle.envelopeOpacity))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
                ForEach(rows) { r in
                    if let bed = r.bed {
                        LineMark(x: .value("Day", r.date), y: .value("Bedtime", bed), series: .value("s", "bed"))
                            .foregroundStyle(bedColor)
                            .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let wake = r.wake {
                        LineMark(x: .value("Day", r.date), y: .value("Wake", wake), series: .value("s", "wake"))
                            .foregroundStyle(wakeColor)
                            .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                if let last = rows.last {
                    if let bed = last.bed {
                        PointMark(x: .value("Day", last.date), y: .value("Bedtime", bed)).foregroundStyle(bedColor).symbolSize(50)
                    }
                    if let wake = last.wake {
                        PointMark(x: .value("Day", last.date), y: .value("Wake", wake)).foregroundStyle(wakeColor).symbolSize(50)
                    }
                }
                if let s = selected {
                    RuleMark(x: .value("Day", s.date)).foregroundStyle(BaselineTheme.hairline)
                    if let bed = s.bed {
                        PointMark(x: .value("Day", s.date), y: .value("Bedtime", bed))
                            .symbol { BaselineChartStyle.selectedPoint(bedColor) }
                    }
                    if let wake = s.wake {
                        PointMark(x: .value("Day", s.date), y: .value("Wake", wake))
                            .symbol { BaselineChartStyle.selectedPoint(bedColor) }
                    }
                }
            }
            .chartYScale(domain: detail.yDomain)
            .chartYAxis {
                AxisMarks(position: .trailing, values: detail.axisTicks()) { v in
                    AxisGridLine().foregroundStyle(BaselineTheme.hairline.opacity(0.75))
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(BaselineReadouts.hourText(minutes: SleepTimingDetail.clockMinutes(noonAxis: d)))
                                .foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
                        }
                    }
                }
            }
            .chartXAxis { xAxis }
            .chartXScale(range: .plotDimension(endPadding: 18))
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
                                    selected = rows.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) { selected = nil }
                            })
                }
            }
            .frame(height: height)
            .modifier(BaselineChartSummary(summary: detail.chartSummary))

            HStack(spacing: 14) {
                legend("Bedtime", bedColor)
                legend("Wake", wakeColor)
            }
            .accessibilityHidden(true)
        }
    }

    /// Months over a year, days otherwise (the axes Progress and Trends draw).
    private var xAxis: AnyAxisContent {
        detail.range == .year
            ? AnyAxisContent(BaselineChartStyle.monthAxis(spansOverAYear: false))
            : AnyAxisContent(BaselineChartStyle.dayAxis(desiredCount: detail.range == .week ? 3 : 4))
    }

    private func legend(_ text: String, _ swatch: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(swatch).frame(width: 6, height: 6)
            Text(text).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        }
    }
}
#endif
