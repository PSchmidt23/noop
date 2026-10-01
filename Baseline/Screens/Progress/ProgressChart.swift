#if os(iOS)
import SwiftUI
import Charts

/// The baseline alone over months: a soft ± sigma area, the baseline line, a dashed rule at the anchor's
/// level (the vertical distance from the rule to the last point IS the sentence's number), a hollow
/// point at the anchor and a filled one at the end. No drag selection, no scrubbing: the sentence is the
/// reading; the chart shows its shape.
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
                    .foregroundStyle(color.opacity(0.10))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("Baseline", p.baseline))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            if let then {
                RuleMark(y: .value("Then", then.baseline))
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
                PointMark(x: .value("Day", then.date), y: .value("Baseline", then.baseline))
                    .symbol {
                        // A custom symbol view is laid out at its own size, not `symbolSize`, so the
                        // ring needs an explicit frame or it fills the plot.
                        Circle()
                            .strokeBorder(color, lineWidth: 2)
                            .background(Circle().fill(BaselineTheme.background))
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
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline)
                AxisValueLabel().foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: xFormat, collisionResolution: .greedy)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .font(BaselineTheme.caption)
            }
        }
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }

    /// "Mar" for a window inside a year, "Mar 2026" once it spans more.
    private var xFormat: Date.FormatStyle {
        if spansOverAYear { return Date.FormatStyle.dateTime.month(.abbreviated).year() }
        return Date.FormatStyle.dateTime.month(.abbreviated)
    }
}
#endif
