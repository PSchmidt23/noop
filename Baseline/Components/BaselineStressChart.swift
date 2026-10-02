#if os(iOS)
import SwiftUI
import Charts

/// A day's Stress curve: NOOP's hourly 0–3 proxy as a light area under a line in `BaselineTheme.stress`,
/// over the waking hours (06:00–22:00) of that day. Unscored windows break the line; windows the strap
/// masked as walking are shaded in `fill` so "you were moving" never reads as "calm". The y axis names
/// the bands the card's Average cell uses (`BaselineReadouts.stressLevelText`: Low under 1, Medium under
/// 2, High from 2), each word at the middle of its band, with gridlines at the band edges and a dashed
/// rule at the high edge (2.0). Axes from `BaselineChartStyle`; flat;
/// lives inside a card with an `AccuracyBadge(metric: "stress")` (Low: an estimate, not a feeling).
///
/// ```swift
/// if let s = await BaselineReadouts.stressDay(repo, for: day) {
///     StressCurveChart(points: s.points, accessibilitySummary: BaselineReadouts.stressSummary(s))
/// }
/// ```
struct StressCurveChart: View {
    let points: [BaselineReadouts.StressCurvePoint]
    var height: CGFloat = 140
    /// The one VoiceOver sentence for the whole chart (`BaselineReadouts.stressSummary`).
    var accessibilitySummary: String? = nil

    private static let highBand = 2.0

    /// A contiguous scored run, so a gap is a break in the line rather than a straight bridge.
    private struct Run: Identifiable {
        let id: Int
        let points: [BaselineReadouts.StressCurvePoint]
    }

    private var runs: [Run] {
        var out: [Run] = []
        var current: [BaselineReadouts.StressCurvePoint] = []
        for p in points {
            if p.level != nil {
                current.append(p)
            } else if !current.isEmpty {
                out.append(Run(id: current[0].id, points: current)); current = []
            }
        }
        if !current.isEmpty { out.append(Run(id: current[0].id, points: current)) }
        return out
    }

    /// The waking-hours x domain of the day the points fall on (06:00 → 22:00), so an afternoon with
    /// no data still shows where it would sit.
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let anchor = points.first?.date ?? Date()
        let start = cal.startOfDay(for: anchor)
        let lo = cal.date(byAdding: .hour, value: 6, to: start) ?? start
        let hi = cal.date(byAdding: .hour, value: 22, to: start) ?? start.addingTimeInterval(79_200)
        return lo...hi
    }

    private var movingSpans: [BaselineReadouts.StressCurvePoint] { points.filter(\.moving) }

    var body: some View {
        Chart {
            ForEach(movingSpans) { p in
                RectangleMark(xStart: .value("From", p.date), xEnd: .value("To", p.date.addingTimeInterval(3_600)),
                              yStart: .value("Low", BaselineReadouts.stressDomain.lowerBound),
                              yEnd: .value("High", BaselineReadouts.stressDomain.upperBound))
                    .foregroundStyle(BaselineTheme.fill)
            }
            RuleMark(y: .value("High", Self.highBand))
                .foregroundStyle(BaselineTheme.stress.opacity(BaselineChartStyle.baselineOpacity))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(runs) { run in
                ForEach(run.points) { p in
                    AreaMark(x: .value("Time", p.date), y: .value("Stress", p.level ?? 0), series: .value("s", "a\(run.id)"))
                        .foregroundStyle(BaselineTheme.stress.opacity(BaselineChartStyle.bandOpacity))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", p.date), y: .value("Stress", p.level ?? 0), series: .value("s", "l\(run.id)"))
                        .foregroundStyle(BaselineTheme.stress)
                        .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if let last = runs.last?.points.last, let level = last.level {
                PointMark(x: .value("Time", last.date), y: .value("Stress", level))
                    .foregroundStyle(BaselineTheme.stress).symbolSize(50)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: BaselineReadouts.stressDomain)
        .chartYAxis {
            // Gridlines at the band edges (0 / 1 / 2 / 3), unlabelled.
            AxisMarks(position: .trailing, values: Self.bandEdges) { _ in
                AxisGridLine().foregroundStyle(BaselineTheme.hairline.opacity(0.75))
            }
            // One word per band at its midpoint, from the same table as the Average cell's unit, so the
            // axis and the cell can never name a level differently.
            AxisMarks(position: .trailing, values: Self.bandMidpoints) { v in
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(BaselineReadouts.stressLevelText(d))
                            .foregroundStyle(BaselineTheme.textTertiary)
                            .font(BaselineTheme.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour(), collisionResolution: .greedy)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .font(BaselineTheme.caption)
            }
        }
        .chartPlotStyle { $0.background(.clear) }
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: accessibilitySummary))
    }

    /// The band edges on the 0–3 scale (the gridlines) and the midpoints the band words sit on, so the
    /// y axis reads Low / Medium / High, one word per band, like the Average cell beside it.
    static let bandEdges: [Double] = [0, 1, 2, 3]
    static let bandMidpoints: [Double] = [0.5, 1.5, 2.5]
}
#endif
