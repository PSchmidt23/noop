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
    }
}

/// `BaselineBarChart` (same bars and average rule) with the edge-safe x labels.
struct TrendsBarChart: View {
    let bars: [BaselineBarChart.Bar]
    let color: Color
    var average: Double? = nil
    var height: CGFloat = 140

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
    }
}
#endif
