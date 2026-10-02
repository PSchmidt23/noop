#if os(iOS)
import SwiftUI
import Charts

/// Line of nightly values over a soft baseline band (baseline ± sigma), with an explicit y-domain (so a
/// 50–70 bpm resting-HR line is not flattened against a wide axis) and edge-safe x labels (three ticks;
/// the last label is anchored to its trailing edge so it never truncates against the y-axis column).
/// Dragging across the plot selects the nearest night; the selection clears the moment the finger lifts,
/// so the header's pill never lingers over a chart nobody is touching. Colours and axes come from
/// `BaselineChartStyle`, so this chart and Progress' draw the same grid, rule and marker.
struct TrendsBandChart: View {
    let points: [BandPoint]
    let color: Color
    let yDomain: ClosedRange<Double>
    var height: CGFloat = 180
    @Binding var selected: BandPoint?
    /// The one VoiceOver sentence for the whole chart (the scrub gesture is touch-only).
    var accessibilitySummary: String? = nil
    var accessibilityHint: String? = nil

    var body: some View {
        Chart {
            ForEach(points) { p in
                if let low = p.low, let high = p.high {
                    AreaMark(x: .value("Day", p.date), yStart: .value("Low", low), yEnd: .value("High", high))
                        .foregroundStyle(color.opacity(BaselineChartStyle.bandOpacity))
                        .interpolationMethod(.monotone)
                }
                if let b = p.baseline {
                    LineMark(x: .value("Day", p.date), y: .value("Baseline", b), series: .value("s", "baseline"))
                        .foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .interpolationMethod(.monotone)
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
            if let s = selected {
                RuleMark(x: .value("Day", s.date)).foregroundStyle(BaselineTheme.hairline)
                PointMark(x: .value("Day", s.date), y: .value("Value", s.value))
                    .symbol { BaselineChartStyle.selectedPoint(color) }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis { BaselineChartStyle.yAxis() }
        .chartXAxis { BaselineChartStyle.dayAxis() }
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartPlotStyle { $0.background(.clear) }
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
}

/// `BaselineBarChart` (same bars and average rule) with the edge-safe x labels.
struct TrendsBarChart: View {
    let bars: [BaselineBarChart.Bar]
    let color: Color
    var average: Double? = nil
    var height: CGFloat = 140
    var accessibilitySummary: String? = nil

    var body: some View {
        Chart {
            ForEach(bars) { b in
                BarMark(x: .value("Day", b.date, unit: .day), y: .value("Value", b.value))
                    .foregroundStyle(color.opacity(BaselineChartStyle.barOpacity))
                    .cornerRadius(BaselineChartStyle.barRadius)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYAxis { BaselineChartStyle.yAxis(desiredCount: 3) }
        .chartXAxis { BaselineChartStyle.dayAxis() }
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartPlotStyle { $0.background(.clear) }
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: accessibilitySummary))
    }
}

/// Intensity minutes: one bar per ISO week with a dashed rule at the weekly goal. The week in progress
/// is drawn lighter (the Steps tile's "earlier days" opacity), so a half-built bar is never read as a
/// short week. Weeks are keyed by their Monday and binned on the ISO calendar
/// (`BaselineRangeSeries.isoCalendar`), whatever the device locale starts its week on, so a bar sits on
/// the seven days it sums. The y-axis always reaches the goal rule.
struct TrendsWeekBarChart: View {
    let weeks: [TrendsIntensity.Week]
    let goal: Int
    var color: Color = BaselineTheme.effort
    var height: CGFloat = 140
    var accessibilitySummary: String? = nil

    /// The in-progress week's bar opacity.
    static let inProgressOpacity = BaselineChartStyle.mutedBarOpacity
    /// Share of the week a bar fills; the rest is the gap between bars.
    static let barFill = 0.7

    /// The bar's span: the week from its Monday's local midnight, inset on both sides by the gap.
    static func span(of w: TrendsIntensity.Week) -> ClosedRange<Date> {
        let week = 7.0 * 86_400
        let inset = week * (1 - barFill) / 2
        return w.date.addingTimeInterval(inset)...w.date.addingTimeInterval(week - inset)
    }

    private var yDomain: ClosedRange<Double> {
        let peak = Double(weeks.map(\.credited).max() ?? 0)
        return 0...max(Double(goal) * 1.15, peak * 1.12, 1)
    }

    var body: some View {
        Chart {
            ForEach(weeks) { w in
                // An explicit span over the Monday-to-Sunday week, as the metric detail draws it: a
                // `.weekOfYear` unit bins on the locale's week (Sunday first in the US) even under an ISO
                // environment calendar, which drew each bar a day early.
                let span = Self.span(of: w)
                RectangleMark(xStart: .value("From", span.lowerBound), xEnd: .value("To", span.upperBound),
                              yStart: .value("Zero", 0.0), yEnd: .value("Minutes", Double(w.credited)))
                    .foregroundStyle(color.opacity(w.inProgress ? Self.inProgressOpacity : BaselineChartStyle.barOpacity))
                    .cornerRadius(BaselineChartStyle.barRadius)
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: yDomain)
        .chartYAxis { BaselineChartStyle.yAxis(desiredCount: 3) }
        .chartXAxis { BaselineChartStyle.dayAxis(desiredCount: weeks.count > 6 ? 4 : 3) }
        .chartPlotStyle { $0.background(.clear) }
        .environment(\.calendar, BaselineRangeSeries.isoCalendar())
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: accessibilitySummary))
    }
}
#endif
