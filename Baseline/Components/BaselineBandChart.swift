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
