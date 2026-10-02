#if os(iOS)
import SwiftUI
import Charts

/// One night on a band chart (`TrendsBandChart`; Progress draws the baseline itself as the value).
struct BandPoint: Identifiable {
    let id: String          // day key
    let date: Date
    let value: Double
    let baseline: Double?
    let low: Double?
    let high: Double?
}

/// The one set of chart constants and axes. Every Baseline chart (`BaselineBarChart`, `TrendsBandChart`,
/// `TrendsBarChart`, `ProgressTrajectoryChart`) takes its axes from here instead of its own block, so a
/// grid line, a tick label or a scrubbed point looks the same on every tab.
enum BaselineChartStyle {
    /// The shaded baseline band: metric colour at this opacity.
    static let bandOpacity = 0.12
    /// The dashed baseline / average rule: metric colour at this opacity.
    static let baselineOpacity = 0.50
    /// The value line.
    static let lineWidth: CGFloat = 2.2
    /// Bars: metric colour at this opacity.
    static let barOpacity = 0.90
    /// A muted bar beside full ones: earlier days on the Steps tile, nights outside the target window,
    /// the week still in progress on a weekly chart.
    static let mutedBarOpacity = 0.45
    static let barRadius: CGFloat = 4

    /// Trailing value ticks with a faint grid (`hairline` @ 0.75), labels in `textTertiary` / `caption`.
    static func yAxis(desiredCount: Int = 4) -> some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: desiredCount)) { _ in
            AxisGridLine().foregroundStyle(BaselineTheme.hairline.opacity(0.75))
            AxisValueLabel().foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
        }
    }

    /// Day labels ("Sep 28") with greedy collision resolution: a 7-day window keeps the three the chart
    /// can fit, never a label over a label.
    static func dayAxis(desiredCount: Int = 3) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: desiredCount)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                .foregroundStyle(BaselineTheme.textTertiary)
                .font(BaselineTheme.caption)
        }
    }

    /// Month labels for Progress' trajectory ("Sep", or "Sep 2025" once the horizon spans over a year).
    static func monthAxis(spansOverAYear: Bool) -> some AxisContent {
        let format: Date.FormatStyle = spansOverAYear
            ? Date.FormatStyle.dateTime.month(.abbreviated).year()
            : Date.FormatStyle.dateTime.month(.abbreviated)
        return AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisValueLabel(format: format, collisionResolution: .greedy)
                .foregroundStyle(BaselineTheme.textTertiary)
                .font(BaselineTheme.caption)
        }
    }

    /// The scrubbed point: a white marker with a 2pt stroke in the metric colour, 10pt. Use as the
    /// `PointMark`'s `.symbol { BaselineChartStyle.selectedPoint(color) }`.
    static func selectedPoint(_ color: Color) -> some View {
        Circle()
            .fill(BaselineTheme.marker)
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .frame(width: 10, height: 10)
    }
}

/// Simple bars (sleep hours, effort) with an optional average rule.
struct BaselineBarChart: View {
    struct Bar: Identifiable { let id: String; let date: Date; let value: Double }
    let bars: [Bar]
    let color: Color
    var average: Double? = nil
    var height: CGFloat = 140
    /// One sentence VoiceOver reads for the whole chart instead of one element per bar.
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
        .chartXAxis { BaselineChartStyle.dayAxis(desiredCount: 4) }
        .chartPlotStyle { $0.background(.clear) }
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: accessibilitySummary))
    }
}

/// Collapses a chart into ONE VoiceOver element with `summary` as its label, when a summary was given
/// (Swift Charts otherwise exposes every mark as "Day, Sep 28, Value, 7.2" with no metric or unit).
struct BaselineChartSummary: ViewModifier {
    let summary: String?
    func body(content: Content) -> some View {
        if let summary {
            content.accessibilityElement(children: .ignore).accessibilityLabel(summary)
        } else {
            content
        }
    }
}
#endif
