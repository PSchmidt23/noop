#if os(iOS)
import SwiftUI
import StrandAnalytics

extension TrendsRange: BaselineRangeOption {}

/// HRV / Resting HR: baseline and average, the nightly line over its band. The range is in the picker
/// above and "higher / lower is better" is the card's accessibility hint, so the header carries only
/// the title and the trend pill; dragging the chart shows that night instead (date and value in the
/// pill, deviation and band position in the subtitle) and lifting the finger returns the trend pill.
/// One caption appears only while the band is provisional or still calibrating.
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
        BaselineCard {
            header
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
                TrendsBandChart(points: metric.points, color: color, yDomain: metric.yDomain, selected: $selected,
                                accessibilitySummary: chartSummary,
                                accessibilityHint: higherIsBetter ? "Higher is better" : "Lower is better")
                if let footnote {
                    Text(footnote)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: metric.points.map(\.id)) { _, _ in selected = nil }
    }

    /// The card's own header: the pill trails the title while both fit on one line, otherwise it sits
    /// under the title (`ViewThatFits`, as the Sleep and Progress cards reflow), so at accessibility
    /// sizes "Down 4 bpm · 30 days" is never pushed past the card's trailing edge. Only the pill's own
    /// width can then exceed the card, and it scales down before it truncates. The scrub subtitle is a
    /// full-width line below the row rather than part of it, so its length never flips the row between
    /// the two layouts mid-drag.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let accessory {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        titleText
                        Spacer(minLength: 8)
                        accessory
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        titleText
                        accessory
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                titleText
            }
            if let subtitle {
                Text(subtitle)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The same title style `BaselineCard(title:)` draws.
    private var titleText: some View {
        Text(title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
    }

    private var baselineText: String {
        metric.current.usable ? TrendsFormat.whole(metric.current.baseline) : "—"
    }

    private var averageText: String {
        metric.average.map(TrendsFormat.whole) ?? "—"
    }

    /// What VoiceOver reads for the chart: the window, the count and span of nights, the baseline and
    /// the average, so nothing the band and the line show is lost to the touch-only scrub.
    private var chartSummary: String {
        let values = metric.points.map(\.value)
        var s = "\(title), last \(range.days) days: \(metric.points.count) nights"
        if let lo = values.min(), let hi = values.max() {
            s += " from \(TrendsFormat.whole(lo)) to \(TrendsFormat.whole(hi)) \(unit)"
        }
        s += "; baseline \(baselineText) \(unit), average \(averageText) \(unit)"
        return s
    }

    /// Only while scrubbing: the selected night against the band it was judged by.
    private var subtitle: String? {
        guard let s = selected else { return nil }
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

    /// Selected night: its date and value. Otherwise the trend over the range, worded as a change
    /// ("Up 4 ms · 30 days") rather than the "+4 ms vs baseline" deviation Today shows, because the two
    /// are different numbers. No `fixedSize`: `header` keeps the pill whole by moving it under the
    /// title when the row is too narrow, instead of letting it run past the card.
    private var accessory: AnyView? {
        if let s = selected {
            let text = "\(TrendsFormat.shortDate(s.date)) · \(TrendsFormat.whole(s.value)) \(unit)"
            return AnyView(BaselinePill(text: text, color: color)
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
        // The pill's good / watch colour, said: VoiceOver otherwise hears "up 4 bpm" with no judgement.
        let judgement = steady ? "" : (improving ? ", improving" : ", worsening")
        return AnyView(BaselinePill(text: text, color: pillColor)
            .accessibilityLabel("\(title) trend: \(spoken) across the last \(range.days) days\(judgement)"))
    }

    /// nil once the band is trusted; the provisional / calibrating sentence until then.
    private var footnote: String? {
        let s = metric.current
        if s.trusted { return nil }
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

/// Sleep / Steps: two stats over bars with a dashed average rule. On the Trends tab the window is the
/// 7D / 30D / 90D picker just above the cards, so the header carries no "Last 30 days" of its own (the
/// "of 28 nights" cell already counts the window). `accessory` takes the header's trailing slot (the
/// Steps card's `AccuracyBadge`); `caption` is the plain-text form for a host whose range is not on
/// screen. `showsAllWorkouts` closes the card with the "All workouts" row (kept for any host that still
/// draws an Effort-only card; on Trends that row lives in `TrendEffortReadinessCard`).
struct TrendBarCard: View {
    let title: String
    /// Trailing caption in the header, for a host whose range is not already on screen; nil omits it.
    var caption: String? = nil
    /// A trailing header view (a pill or badge); wins over `caption` when both are given.
    var accessory: AnyView? = nil
    let color: Color
    let bars: [BaselineBarChart.Bar]
    let average: Double?
    let stats: [TrendStat]
    let emptyText: String
    var showsAllWorkouts: Bool = false

    var body: some View {
        BaselineCard(title: title, accessory: accessory ?? caption.map { AnyView(captionView($0)) }) {
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
                TrendsBarChart(bars: bars, color: color, average: average, accessibilitySummary: chartSummary)
            }
            if showsAllWorkouts {
                Divider().overlay(BaselineTheme.hairline)
                BaselineChevronRow(text: "All workouts", accessibilityHint: "Shows every recorded workout") {
                    WorkoutsScreen()
                }
            }
        }
    }

    private func captionView(_ text: String) -> some View {
        Text(text)
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textTertiary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The chart's one VoiceOver sentence: the stats the header already prints ("Sleep: Average 7h 12m,
    /// Nights 28"), so a swipe never lands on one bar after another.
    private var chartSummary: String {
        let parts = stats.map { stat in
            stat.unit.map { "\(stat.label) \(stat.value) \($0)" } ?? "\(stat.label) \(stat.value)"
        }
        return "\(title): " + parts.joined(separator: ", ")
    }
}

/// Effort bars under the Readiness line over the picked range: did the day's effort show up in the next
/// morning's readiness? Two stats (the mean of each series over the days that have it), the chart, and
/// ONE sentence counting the days effort outran readiness. Closes with the "All workouts" row, the
/// Trends tab's path to the Workouts list (the standalone Effort card folded into this one: the same
/// bars and the same average would otherwise appear twice on the screen).
struct TrendEffortReadinessCard: View {
    let range: TrendsRange
    let metric: TrendsSeries.EffortReadiness
    /// The range's highest effort day, said in the chart's VoiceOver sentence rather than printed.
    let peak: BaselineBarChart.Bar?

    var body: some View {
        BaselineCard(title: "Effort & Readiness") {
            if metric.points.isEmpty {
                Text("No effort or readiness in the last \(range.days) days.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            } else {
                HStack(spacing: 12) {
                    StatCell(label: "Average effort", value: effortText, dot: BaselineTheme.effort)
                    StatCell(label: "Average readiness", value: readinessText, dot: BaselineTheme.accent)
                }
                EffortReadinessChart(points: metric.points, accessibilitySummary: chartSummary)
                Text(sentence)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(BaselineTheme.hairline)
            BaselineChevronRow(text: "All workouts", accessibilityHint: "Shows every recorded workout") {
                WorkoutsScreen()
            }
        }
    }

    private var effortText: String { metric.effortAverage.map(TrendsFormat.whole) ?? "—" }
    private var readinessText: String { metric.readinessAverage.map(TrendsFormat.whole) ?? "—" }

    /// The one line under the chart. With both series: the count of days effort outran readiness.
    /// With effort alone: why the line is missing (no score yet, or none from this source).
    private var sentence: String {
        if metric.pairedDays > 0 {
            return "Days where effort outran readiness: \(metric.outranDays) of \(metric.pairedDays)"
        }
        if metric.readinessDays == 0 {
            return "No readiness score in the last \(range.days) days; it starts after \(BaselineReadouts.readinessSeedNights) nights of HRV."
        }
        return "No day in the last \(range.days) days has both an effort and a readiness score."
    }

    /// What VoiceOver reads for the chart: the two averages the header prints, the peak day and the
    /// outran count, so nothing the bars and the line show is lost to the touch-only view.
    private var chartSummary: String {
        var s = "Effort and Readiness, last \(range.days) days: average effort \(effortText) of 100"
        if let peak { s += ", highest \(TrendsFormat.whole(peak.value)) on \(TrendsFormat.shortDate(peak.date))" }
        s += "; average readiness \(readinessText) of 100"
        if metric.pairedDays > 0 { s += "; effort outran readiness on \(metric.outranDays) of \(metric.pairedDays) days" }
        return s
    }
}
#endif
