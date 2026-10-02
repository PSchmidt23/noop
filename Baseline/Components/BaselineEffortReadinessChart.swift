#if os(iOS)
import SwiftUI
import Charts

/// One day on the Effort / Readiness chart. Both are 0–100 (the funnel's `strain` and `recovery`
/// columns), so the chart has ONE y axis and nothing is rescaled.
struct EffortReadinessPoint: Identifiable, Equatable {
    let id: String      // day key
    let date: Date
    /// That day's Effort (0–100), nil when the strap recorded none.
    let effort: Double?
    /// That morning's Readiness score (0–100), nil before it exists.
    let readiness: Double?
}

/// Effort as amber bars under a Readiness line in the accent, days on the x axis, one 0–100 y axis.
/// The pairing answers "did yesterday's effort show up in this morning's readiness?" without a second
/// scale to misread. Light: `BaselineChartStyle` axes, the bars at `barOpacity`, the line at `lineWidth`,
/// a small legend of two 6pt dots under the plot. Flat; inside a card titled "Effort and Readiness".
///
/// ```swift
/// let days = repo.baselineDays.suffix(30)
/// let points = days.compactMap { d in BaselineReadouts.localMidnight(of: d.day).map {
///     EffortReadinessPoint(id: d.day, date: $0, effort: d.strain, readiness: d.recovery) } }
/// EffortReadinessChart(points: points, accessibilitySummary: "…")
/// ```
struct EffortReadinessChart: View {
    let points: [EffortReadinessPoint]
    var height: CGFloat = 180
    /// The one VoiceOver sentence for the whole chart.
    var accessibilitySummary: String? = nil

    private var effortBars: [EffortReadinessPoint] { points.filter { $0.effort != nil } }
    private var readinessLine: [EffortReadinessPoint] { points.filter { $0.readiness != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(effortBars) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("Effort", p.effort ?? 0))
                        .foregroundStyle(BaselineTheme.effort.opacity(BaselineChartStyle.barOpacity))
                        .cornerRadius(BaselineChartStyle.barRadius)
                }
                ForEach(readinessLine) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("Readiness", p.readiness ?? 0),
                             series: .value("s", "readiness"))
                        .foregroundStyle(BaselineTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = readinessLine.last, let r = last.readiness {
                    PointMark(x: .value("Day", last.date, unit: .day), y: .value("Readiness", r))
                        .foregroundStyle(BaselineTheme.accent).symbolSize(50)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { BaselineChartStyle.yAxis(desiredCount: 3) }
            .chartXAxis { BaselineChartStyle.dayAxis() }
            .chartXScale(range: .plotDimension(endPadding: 18))
            .chartPlotStyle { $0.background(.clear) }
            .frame(height: height)
            .modifier(BaselineChartSummary(summary: accessibilitySummary ?? defaultSummary))
            HStack(spacing: 14) {
                legend("Effort", BaselineTheme.effort)
                legend("Readiness", BaselineTheme.accent)
            }
            .accessibilityHidden(true)
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        }
    }

    /// "Effort and Readiness over 30 days: effort averaged 42 of 100, readiness 63 of 100." when the
    /// caller passes no sentence.
    private var defaultSummary: String {
        let e = effortBars.compactMap(\.effort)
        let r = readinessLine.compactMap(\.readiness)
        var parts: [String] = []
        if !e.isEmpty { parts.append("effort averaged \(Int((e.reduce(0, +) / Double(e.count)).rounded())) of 100") }
        if !r.isEmpty { parts.append("readiness \(Int((r.reduce(0, +) / Double(r.count)).rounded())) of 100") }
        let span = "Effort and Readiness over \(points.count) day\(points.count == 1 ? "" : "s")"
        return parts.isEmpty ? span + ": nothing recorded yet." : span + ": " + parts.joined(separator: ", ") + "."
    }
}
#endif
