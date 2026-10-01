#if os(iOS)
import SwiftUI
import Charts

/// Settings › Compare: the Baseline strap's nights against an imported source (the WHOOP export, or
/// Apple Health when it overlaps), one metric at a time. A summary over every shared night, the two
/// lines over a 30 / 90 / all window, and the last 30 shared nights with both values and the difference.
/// Everything is derived in `CompareSnapshot.build` from `repo.vitalRows`, the per-source daily rows the
/// engine publishes on every refresh (before any merge, by provenance: that is the point of Compare);
/// the screen only picks and draws. The in-card pickers are flat; the chart takes its axes from
/// `BaselineChartStyle`.
struct CompareScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage("baseline.compareMetric") private var metricRaw: String = CompareMetric.hrv.rawValue
    @AppStorage("baseline.compareRange") private var rangeRaw: Int = BaselineCompareRange.month.rawValue
    @AppStorage("baseline.compareSource") private var sourceRaw: String = CompareSource.whoopExport.rawValue
    /// The precedence Settings › Data persists, so the footnote says what Home actually shows.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    @State private var snapshot: CompareSnapshot?
    /// Rolled on `.NSCalendarDayChanged`, so the window's "today" end moves at midnight.
    @State private var todayKey = Repository.localDayKey(Date())

    private struct LoadKey: Equatable {
        let seq: Int
        let loaded: Bool
        let metric: String
        let range: Int
        let source: String
        let day: String
    }

    private var metric: CompareMetric { CompareMetric.resolve(metricRaw) }
    private var range: BaselineCompareRange { BaselineCompareRange.resolve(rangeRaw) }
    private var source: CompareSource { CompareSource.resolve(sourceRaw) }

    var body: some View {
        BaselineScreen(title: "Compare") {
            if let s = snapshot {
                if s.availableSources.isEmpty {
                    emptyState
                } else {
                    if s.availableSources.count > 1 {
                        BaselineSegmentedPicker(
                            options: s.availableSources,
                            selection: Binding(get: { s.source }, set: { sourceRaw = $0.rawValue }),
                            label: { $0.label },
                            accessibilityLabel: { "Compare with \($0.label)" },
                            style: .flat)
                    }
                    BaselineSegmentedPicker(
                        options: CompareMetric.allCases,
                        selection: Binding(get: { metric }, set: { metricRaw = $0.rawValue }),
                        label: { $0.label },
                        style: .flat)
                    CompareSummaryCard(snapshot: s)
                    CompareChartCard(snapshot: s,
                                     range: Binding(get: { range }, set: { rangeRaw = $0.rawValue }))
                    CompareNightsCard(snapshot: s)
                    Text(footnote(s))
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            } else {
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, metric: metricRaw, range: rangeRaw,
                          source: sourceRaw, day: todayKey)) {
            guard repo.loaded else { snapshot = nil; return }
            snapshot = CompareSnapshot.build(rows: repo.vitalRows, source: source, metric: metric,
                                             range: range, todayKey: todayKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            todayKey = Repository.localDayKey(Date())
        }
    }

    private var emptyState: some View {
        BaselineCard {
            BaselineEmptyState(
                icon: "arrow.left.arrow.right",
                title: "Nothing to compare yet",
                message: "Import your WHOOP export under Settings \u{203A} Import data. Nights both sources recorded will appear here.")
        }
    }

    /// Where the two columns come from, and which of them a night both recorded shows elsewhere: that
    /// follows the Data source setting (`BaselineDataSource.shownOnTabs`), never this screen.
    private func footnote(_ s: CompareSnapshot) -> String {
        "Baseline is what your strap recorded; \(s.source.label) is what the import carried. Differences are Baseline minus \(s.source.shortName). \(BaselineDataSource.resolve(dataSourceRaw).shownOnTabs)"
    }
}

// MARK: - Data source sentence

extension BaselineDataSource {
    /// The one sentence Import and Compare print about which source a night both recorded shows on the
    /// tabs, resolved from the persisted setting so the two screens cannot disagree with each other or
    /// with the picker under Settings › Data (whose footer is `subtitle`). It names the default as such,
    /// so a person whose numbers moved after an import or an update can see why without opening Settings.
    var shownOnTabs: String {
        let setting = "Data source: \(label)" + (self == .default ? ", the default" : "")
        switch self {
        case .strapFirst:
            return "On a night both recorded, Home, Trends and Sleep show your strap\u{2019}s figure (\(setting))."
        case .merged:
            return "On a night both recorded, Home, Trends and Sleep show the import\u{2019}s figure (\(setting))."
        case .importOnly:
            return "Home, Trends and Sleep show the imports alone right now (\(setting))."
        }
    }
}

// MARK: - Summary

/// Nights compared, mean difference, mean gap, r, and the sentence, over every shared night.
private struct CompareSummaryCard: View {
    let snapshot: CompareSnapshot

    var body: some View {
        BaselineCard(title: "\(snapshot.metric.label) · Baseline vs \(snapshot.source.shortName)",
                     accessory: AnyView(CompareAccessory(text: "Every night both recorded"))) {
            if let stats = snapshot.stats {
                let m = snapshot.metric
                HStack(spacing: 12) {
                    StatCell(label: "Nights", value: String(stats.nights))
                    StatCell(label: "Mean difference", value: m.differenceText(stats.meanDifference))
                }
                HStack(spacing: 12) {
                    StatCell(label: "Mean gap", value: m.differenceText(stats.meanAbsoluteDifference))
                    StatCell(label: "Correlation r", value: CompareModel.rText(stats.r))
                }
                if let sentence = snapshot.sentence {
                    Text(sentence)
                        .font(BaselineTheme.body)
                        .foregroundStyle(BaselineTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caveat = snapshot.source.caveat(for: m) {
                    Text(caveat)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(noNights)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noNights: String {
        "No night has \(snapshot.metric.noun) from both Baseline and \(snapshot.source.label)."
    }
}

// MARK: - Chart

/// Two lines over the shared nights in the window: teal is Baseline, the dashed grey line the import.
private struct CompareChartCard: View {
    let snapshot: CompareSnapshot
    @Binding var range: BaselineCompareRange

    var body: some View {
        BaselineCard(title: "Night by night", accessory: AnyView(CompareAccessory(text: subtitle))) {
            BaselineRangePicker<BaselineCompareRange>(selection: $range, style: .flat)
            if snapshot.windowed.isEmpty {
                Text("No shared nights in this window.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            } else {
                HStack(spacing: 16) {
                    CompareLegendSwatch(label: "Baseline", color: BaselineTheme.accent, dashed: false)
                    CompareLegendSwatch(label: snapshot.source.label, color: BaselineTheme.textSecondary, dashed: true)
                }
                CompareChart(points: snapshot.windowed, metric: snapshot.metric, yDomain: snapshot.yDomain)
                    .accessibilityLabel(chartAccessibility)
            }
        }
    }

    private var subtitle: String {
        let unit = snapshot.metric.chartUnit
        return unit.isEmpty ? snapshot.range.subtitle : "\(snapshot.range.subtitle) · \(unit)"
    }

    private var chartAccessibility: String {
        let n = snapshot.windowed.count
        return "\(snapshot.metric.label) on \(n) shared night\(n == 1 ? "" : "s"): Baseline and \(snapshot.source.label)"
    }
}

/// The caption at a card's trailing edge (the window, the unit): `caption` in `textTertiary`.
private struct CompareAccessory: View {
    let text: String
    var body: some View {
        Text(text)
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct CompareLegendSwatch: View {
    let label: String
    let color: Color
    let dashed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1.5))
                p.addLine(to: CGPoint(x: 18, y: 1.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [4, 3] : []))
            .frame(width: 18, height: 3)
            Text(label)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(dashed ? "dashed" : "solid") line")
    }
}

/// Two monotone lines sharing one y-domain, with the one chart style (`BaselineChartStyle`: three
/// edge-safe date labels, trailing y labels on faint grid lines, the marker on the latest night).
struct CompareChart: View {
    let points: [ComparePair]
    let metric: CompareMetric
    let yDomain: ClosedRange<Double>
    var height: CGFloat = 180

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("Import", metric.chartValue(p.other)),
                         series: .value("s", "other"))
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth - 0.6, lineCap: .round, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("Baseline", metric.chartValue(p.baseline)),
                         series: .value("s", "baseline"))
                    .foregroundStyle(BaselineTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("Baseline", metric.chartValue(last.baseline)))
                    .symbol { BaselineChartStyle.selectedPoint(BaselineTheme.accent) }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis { BaselineChartStyle.yAxis() }
        .chartXAxis { BaselineChartStyle.dayAxis() }
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartPlotStyle { $0.background(.clear) }
        .frame(height: height)
    }
}

// MARK: - Nights

/// The last 30 shared nights, newest first: date, Baseline's value, the import's, and the difference.
/// Numbers in the text colours only; a difference is a fact, not a judgement.
private struct CompareNightsCard: View {
    let snapshot: CompareSnapshot

    private var nights: [ComparePair] { snapshot.recentNights }

    var body: some View {
        BaselineCard(title: "Nights", accessory: AnyView(CompareAccessory(text: subtitle))) {
            if nights.isEmpty {
                Text("No night has \(snapshot.metric.noun) from both sources.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            } else {
                header
                VStack(spacing: 0) {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
                        CompareNightRow(pair: night, metric: snapshot.metric, source: snapshot.source)
                        if index < nights.count - 1 {
                            Rectangle().fill(BaselineTheme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let n = nights.count
        let unit = snapshot.metric.unit
        let count = n == 1 ? "The one night both recorded" : "Last \(n) nights both recorded"
        return unit.isEmpty ? count : "\(count) · \(unit)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Text("Baseline").frame(width: CompareNightRow.columnWidth, alignment: .trailing)
            Text(snapshot.source.shortName).frame(width: CompareNightRow.columnWidth, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("Diff").frame(width: CompareNightRow.columnWidth, alignment: .trailing)
        }
        .font(BaselineTheme.caption)
        .foregroundStyle(BaselineTheme.textTertiary)
        .accessibilityHidden(true)
    }
}

private struct CompareNightRow: View {
    static let columnWidth: CGFloat = 64

    let pair: ComparePair
    let metric: CompareMetric
    let source: CompareSource

    var body: some View {
        HStack(spacing: 8) {
            Text(TrendsFormat.shortDate(pair.date))
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.text)
            Spacer(minLength: 0)
            Text(metric.valueText(pair.baseline))
                .font(BaselineTheme.headline)
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.text)
                .frame(width: Self.columnWidth, alignment: .trailing)
            Text(metric.valueText(pair.other))
                .font(BaselineTheme.body)
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.textSecondary)
                .frame(width: Self.columnWidth, alignment: .trailing)
            Text(metric.differenceText(pair.difference))
                .font(BaselineTheme.body)
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.text)
                .frame(width: Self.columnWidth, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
        return "\(TrendsFormat.shortDate(pair.date)): Baseline \(metric.valueText(pair.baseline))\(unit), \(source.shortName) \(metric.valueText(pair.other))\(unit), difference \(metric.differenceText(pair.difference))"
    }
}
#endif
