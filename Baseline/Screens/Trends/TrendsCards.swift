#if os(iOS)
import SwiftUI
import StrandAnalytics

extension TrendsRange: BaselineRangeOption {}

/// 7D / 30D / 90D segmented pill: the shared `BaselineRangePicker`, the same control Progress uses.
typealias TrendRangePicker = BaselineRangePicker<TrendsRange>

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
                TrendsBandChart(points: metric.points, color: color, yDomain: metric.yDomain, selected: $selected)
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
            // `BaselineBand.positionPhrase`: the same words Today and the morning summary use.
            let band: BaselineBand = inside ? .inside : (delta > 0 ? .above : .below)
            return "\(TrendsFormat.signed(delta, unit: unit)) vs baseline · \(band.positionPhrase ?? "")"
        }
        return "\(range.subtitle) · \(higherIsBetter ? "higher" : "lower") is better"
    }

    /// Selected night: its date and value. Otherwise the trend over the range, worded as a change
    /// ("Up 4 ms · 30 days") rather than the "+4 ms vs baseline" deviation Today shows, because the two
    /// are different numbers. `fixedSize` keeps the pill on one line; the subtitle wraps first if it must.
    private var accessory: AnyView? {
        if let s = selected {
            let text = "\(TrendsFormat.shortDate(s.date)) · \(TrendsFormat.whole(s.value)) \(unit)"
            return AnyView(BaselinePill(text: text, color: color)
                .fixedSize()
                .accessibilityLabel("\(title) on \(TrendsFormat.shortDate(s.date)): \(TrendsFormat.whole(s.value)) \(unit)"))
        }
        guard let t = metric.trend else { return nil }
        let steady = abs(t) < 0.5
        let improving = higherIsBetter ? t > 0 : t < 0
        let pillColor: Color = steady ? BaselineTheme.textSecondary
            : (improving ? BaselineTheme.good : BaselineTheme.watch)
        let direction = t > 0 ? "Up" : "Down"
        let amount = "\(TrendsFormat.whole(abs(t))) \(unit)"
        let text = steady ? "Steady" : "\(direction) \(amount) · \(range.days) days"
        let spoken = steady ? "steady" : "\(direction.lowercased()) \(amount)"
        return AnyView(BaselinePill(text: text, color: pillColor)
            .fixedSize()
            .accessibilityLabel("\(title) trend: \(spoken) across the last \(range.days) days"))
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

/// A quiet text link under a card's chart that pushes another screen ("All workouts").
struct TrendCardLink {
    let label: String
    let hint: String
    let destination: () -> AnyView
}

/// Sleep / Effort: two stats over bars with a dashed average rule, and an optional link row beneath.
struct TrendBarCard: View {
    let title: String
    let subtitle: String
    let color: Color
    let bars: [BaselineBarChart.Bar]
    let average: Double?
    let stats: [TrendStat]
    let emptyText: String
    var link: TrendCardLink? = nil

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
                TrendsBarChart(bars: bars, color: color, average: average)
            }
            if let link {
                NavigationLink { link.destination() } label: {
                    HStack(spacing: 4) {
                        Text(link.label)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(BaselineTheme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(link.hint)
            }
        }
    }
}

/// Fourteen dots, one per night, coloured by that morning's HRV readiness tier. Labels and colours are
/// `ReadinessTier.baselineLabel` / `.baselineColor`, the same words and hues as the Today pill.
struct ReadinessStripCard: View {
    let readiness: TrendsSeries.Readiness

    var body: some View {
        BaselineCard(title: "Readiness", subtitle: "Last \(TrendsSeries.readinessNights) nights", accessory: latestPill) {
            HStack(spacing: 0) {
                ForEach(readiness.nights) { night in
                    dot(night.tier)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(TrendsFormat.shortDate(night.date)): \(night.tier?.baselineLabel ?? "no reading")")
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
        return AnyView(BaselinePill(text: tier.baselineLabel, color: tier.baselineColor))
    }

    @ViewBuilder
    private func dot(_ tier: ReadinessTier?) -> some View {
        if let tier {
            Circle().fill(tier.baselineColor).frame(width: 10, height: 10)
        } else {
            Circle().strokeBorder(BaselineTheme.hairline, lineWidth: 1).frame(width: 10, height: 10)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([ReadinessTier.primed, .normal, .suppressed], id: \.self) { tier in
                HStack(spacing: 5) {
                    Circle().fill(tier.baselineColor).frame(width: 6, height: 6)
                    Text(tier.baselineLabel)
                }
            }
        }
        .font(BaselineTheme.caption)
        .foregroundStyle(BaselineTheme.textTertiary)
    }
}
#endif
