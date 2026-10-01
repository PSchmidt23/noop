#if os(iOS)
import SwiftUI
import StrandAnalytics

/// 7D / 30D / 90D segmented pill with a sliding teal selection.
struct TrendRangePicker: View {
    @Binding var selection: TrendsRange
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TrendsRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = range }
                } label: {
                    Text(range.label)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(selection == range ? BaselineTheme.accent : BaselineTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == range {
                                Capsule()
                                    .fill(BaselineTheme.accent.opacity(0.16))
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(range.subtitle)
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BaselineTheme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(BaselineTheme.cardStroke, lineWidth: 1))
    }
}

/// HRV / Resting HR: baseline and average, the nightly line over its band, and a one-line footnote.
/// Dragging the chart shows that night in the header; tapping the numbers clears it.
struct TrendBandCard: View {
    let title: String
    /// How the metric reads mid-sentence ("HRV", "resting HR").
    let noun: String
    let unit: String
    let color: Color
    let higherIsBetter: Bool
    let range: TrendsRange
    let metric: TrendsSeries.BandMetric
    @State private var selected: BandPoint?

    var body: some View {
        BaselineCard(title: title, subtitle: subtitle, accessory: accessory) {
            if metric.points.isEmpty {
                Text("No nights with \(noun) in the last \(range.days) days.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            } else {
                HStack(spacing: 12) {
                    StatCell(label: "Baseline", value: baselineText, unit: unit, color: color)
                    StatCell(label: "Average", value: averageText, unit: unit)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected != nil { withAnimation(.easeOut(duration: 0.2)) { selected = nil } }
                }
                BaselineBandChart(points: metric.points, color: color, unit: unit, selected: $selected)
                Text(footnote)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            }
        }
        .onChange(of: metric.points.map(\.id)) { _, _ in selected = nil }
    }

    private var baselineText: String {
        metric.current.usable ? TrendsFormat.whole(metric.current.baseline) : "—"
    }

    private var averageText: String {
        metric.average.map(TrendsFormat.whole) ?? "—"
    }

    private var subtitle: String {
        if let s = selected {
            guard let b = s.baseline else { return "Before your band was ready" }
            let delta = s.value - b
            let inside: Bool = {
                guard let lo = s.low, let hi = s.high else { return true }
                return s.value >= lo && s.value <= hi
            }()
            let position = inside ? "inside your band" : (delta > 0 ? "above your band" : "below your band")
            return "\(TrendsFormat.signed(delta, unit: unit)) vs baseline · \(position)"
        }
        return "\(range.subtitle) · \(higherIsBetter ? "higher" : "lower") is better"
    }

    private var accessory: AnyView? {
        if let s = selected {
            let text = "\(TrendsFormat.shortDate(s.date)) · \(TrendsFormat.whole(s.value)) \(unit)"
            return AnyView(BaselinePill(text: text, color: color))
        }
        guard let t = metric.trend else { return nil }
        let steady = abs(t) < 0.5
        let improving = higherIsBetter ? t > 0 : t < 0
        let pillColor: Color = steady ? BaselineTheme.textSecondary
            : (improving ? BaselineTheme.good : BaselineTheme.watch)
        return AnyView(BaselinePill(text: steady ? "Steady" : TrendsFormat.signed(t, unit: unit), color: pillColor))
    }

    private var footnote: String {
        let s = metric.current
        if s.trusted {
            return "Shaded band is your typical range going into each night."
        }
        if s.usable {
            return "Shaded band is your typical range · provisional until \(Baselines.minNightsTrust) nights (\(s.nValid) so far)."
        }
        return "Your band appears after \(Baselines.minNightsSeed) nights and settles after \(Baselines.minNightsTrust) · \(s.nValid) so far."
    }
}

/// A labelled number in the header row of a bar card.
struct TrendStat {
    let label: String
    let value: String
    var unit: String? = nil
}

/// Sleep / Effort: two stats over bars with a dashed average rule.
struct TrendBarCard: View {
    let title: String
    let subtitle: String
    let color: Color
    let bars: [BaselineBarChart.Bar]
    let average: Double?
    let stats: [TrendStat]
    let emptyText: String

    var body: some View {
        BaselineCard(title: title, subtitle: subtitle) {
            if bars.isEmpty {
                Text(emptyText)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            } else {
                HStack(spacing: 12) {
                    ForEach(stats, id: \.label) { stat in
                        StatCell(label: stat.label, value: stat.value, unit: stat.unit)
                    }
                }
                BaselineBarChart(bars: bars, color: color, average: average)
            }
        }
    }
}

/// Fourteen dots, one per night, coloured by that morning's HRV readiness tier.
struct ReadinessStripCard: View {
    let readiness: TrendsSeries.Readiness

    var body: some View {
        BaselineCard(title: "Readiness", subtitle: "Last \(TrendsSeries.readinessNights) nights", accessory: latestPill) {
            HStack(spacing: 0) {
                ForEach(readiness.nights) { night in
                    dot(night.tier)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(TrendsFormat.shortDate(night.date)): \(night.tier.map(Self.label) ?? "no reading")")
                }
            }
            .padding(.vertical, 4)
            HStack {
                if let first = readiness.nights.first { Text(TrendsFormat.shortDate(first.date)) }
                Spacer()
                Text("Today")
            }
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textTertiary)
            legend
        }
    }

    private var latestPill: AnyView? {
        guard let tier = readiness.latest else { return nil }
        return AnyView(BaselinePill(text: Self.label(tier), color: Self.color(tier)))
    }

    @ViewBuilder
    private func dot(_ tier: ReadinessTier?) -> some View {
        if let tier {
            Circle().fill(Self.color(tier)).frame(width: 10, height: 10)
        } else {
            Circle().strokeBorder(BaselineTheme.hairline, lineWidth: 1).frame(width: 10, height: 10)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([ReadinessTier.primed, .normal, .suppressed], id: \.self) { tier in
                HStack(spacing: 5) {
                    Circle().fill(Self.color(tier)).frame(width: 6, height: 6)
                    Text(Self.label(tier))
                }
            }
        }
        .font(BaselineTheme.caption)
        .foregroundStyle(BaselineTheme.textTertiary)
    }

    static func color(_ tier: ReadinessTier) -> Color {
        switch tier {
        case .primed: return BaselineTheme.good
        case .normal: return BaselineTheme.accent
        case .suppressed: return BaselineTheme.watch
        }
    }

    static func label(_ tier: ReadinessTier) -> String {
        switch tier {
        case .primed: return "Primed"
        case .normal: return "Normal"
        case .suppressed: return "Suppressed"
        }
    }
}
#endif
