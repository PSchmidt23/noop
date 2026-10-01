#if os(iOS)
import SwiftUI
import Charts

/// The baseline alone over months: a soft ± sigma area, the baseline line, a dashed rule at the anchor's
/// level (the vertical distance from the rule to the last point IS the sentence's number), a hollow
/// point at the anchor and a filled one at the end. No drag selection, no scrubbing: the sentence is the
/// reading; the chart shows its shape. Axes and opacities come from `BaselineChartStyle`.
struct ProgressTrajectoryChart: View {
    let points: [ProgressPoint]
    let color: Color
    let yDomain: ClosedRange<Double>
    var then: ProgressPoint? = nil
    var now: ProgressPoint? = nil
    var spansOverAYear: Bool = false
    /// Spoken for the whole chart; the marks themselves are hidden from VoiceOver.
    let sentence: String
    var height: CGFloat = 150

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.date),
                         yStart: .value("Low", p.baseline - p.sigma),
                         yEnd: .value("High", p.baseline + p.sigma))
                    .foregroundStyle(color.opacity(BaselineChartStyle.bandOpacity))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("Baseline", p.baseline))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            if let then {
                RuleMark(y: .value("Then", then.baseline))
                    .foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
                PointMark(x: .value("Day", then.date), y: .value("Baseline", then.baseline))
                    .symbol {
                        // A custom symbol view is laid out at its own size, not `symbolSize`, so the
                        // ring needs an explicit frame or it fills the plot. Filled with the card
                        // colour, so the hollow anchor reads as a hole in the line on a white card.
                        Circle()
                            .strokeBorder(color, lineWidth: 2)
                            .background(Circle().fill(BaselineTheme.card))
                            .frame(width: 9, height: 9)
                    }
                    .accessibilityHidden(true)
            }
            if let last = now ?? points.last {
                PointMark(x: .value("Day", last.date), y: .value("Baseline", last.baseline))
                    .foregroundStyle(color)
                    .symbolSize(50)
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis { BaselineChartStyle.yAxis() }
        .chartXAxis { BaselineChartStyle.monthAxis(spansOverAYear: spansOverAYear) }
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartPlotStyle { $0.background(.clear) }
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }
}
#endif
