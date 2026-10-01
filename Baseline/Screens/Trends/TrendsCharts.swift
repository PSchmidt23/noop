#if os(iOS)
import SwiftUI
import Charts

/// Trends' twin of `BaselineBandChart`, identical in look, with two additions the shared component has no
/// hooks for: an explicit y-domain (so a 50–70 bpm resting-HR line is not flattened against a wide axis)
/// and edge-safe x labels (three ticks; the last label is anchored to its trailing edge so it never
/// truncates against the y-axis column).
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
                        .foregroundStyle(color.opacity(0.14))
                        .interpolationMethod(.monotone)
                }
                if let b = p.baseline {
                    LineMark(x: .value("Day", p.date), y: .value("Baseline", b), series: .value("s", "baseline"))
                        .foregroundStyle(color.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value), series: .value("s", "value"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("Value", last.value))
                    .foregroundStyle(color).symbolSize(50)
            }
            if let s = selected {
                RuleMark(x: .value("Day", s.date)).foregroundStyle(BaselineTheme.hairline)
                PointMark(x: .value("Day", s.date), y: .value("Value", s.value))
                    .foregroundStyle(.white).symbolSize(70)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline)
                AxisValueLabel().foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartXAxis { TrendsAxis.dayMarks() }
        .chartXScale(range: .plotDimension(endPadding: 18))
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
                        .onEnded { _ in })
            }
        }
        .frame(height: height)
    }
}

/// Trends' twin of `BaselineBarChart` (same bars and average rule) with the edge-safe x labels.
struct TrendsBarChart: View {
    let bars: [BaselineBarChart.Bar]
    let color: Color
    var average: Double? = nil
    var height: CGFloat = 140

    var body: some View {
        Chart {
            ForEach(bars) { b in
                BarMark(x: .value("Day", b.date, unit: .day), y: .value("Value", b.value))
                    .foregroundStyle(color.opacity(0.85))
                    .cornerRadius(3)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline)
                AxisValueLabel().foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartXAxis { TrendsAxis.dayMarks() }
        .chartXScale(range: .plotDimension(endPadding: 18))
        .frame(height: height)
    }
}

/// Shared x-axis for the Trends charts: a few "Sep 28"-style labels. Overlapping labels are dropped
/// (greedy collision resolution) and the plot keeps trailing room so the last label is never clipped.
enum TrendsAxis {
    static func dayMarks() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                .foregroundStyle(BaselineTheme.textTertiary)
                .font(BaselineTheme.caption)
        }
    }
}
#endif
