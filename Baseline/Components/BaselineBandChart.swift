#if os(iOS)
import SwiftUI
import Charts

struct BandPoint: Identifiable {
    let id: String          // day key
    let date: Date
    let value: Double
    let baseline: Double?
    let low: Double?
    let high: Double?
}

/// Line of nightly values over a soft baseline band (baseline ± sigma). Tap/drag to inspect a day.
struct BaselineBandChart: View {
    let points: [BandPoint]
    let color: Color
    var unit: String = ""
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
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline)
                AxisValueLabel().foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let x = g.location.x - geo[proxy.plotFrame!].origin.x
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

/// Simple bars (sleep hours, effort) with an optional average rule.
struct BaselineBarChart: View {
    struct Bar: Identifiable { let id: String; let date: Date; let value: Double }
    let bars: [Bar]
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
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .frame(height: height)
    }
}
#endif
