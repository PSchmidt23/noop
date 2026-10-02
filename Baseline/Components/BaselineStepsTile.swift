#if os(iOS)
import SwiftUI

/// The day's steps against the person's own average, with a seven-bar sparkline of the week ending on
/// that day. Number in `hero(36)`, ONE context line ("+1,240 vs your 7-day average" / "7-day average
/// after 3 days"), then seven 4pt capsules scaled to the week's highest count (a day with no count is an
/// empty `ringTrack` stub). Flat; sits in a `BaselineCard` or a tile. The tile prints its own "Steps"
/// header unless the host card carries the title (`showsHeader: false`), so a card with an accessory
/// (the accuracy badge) keeps that badge in its header row, off the hero numeral's line. On today
/// (`isToday`) the count is still accruing, so the header reads "Steps so far", the dot stays in `steps`
/// and the line says the day is still building: a morning's partial count is never judged against
/// whole-day averages (the rule the Effort cell follows with "Effort so far").
///
/// ```swift
/// let s = await BaselineReadouts.steps(repo, for: day)
/// StepsTile(readout: s, window: .week)        // or .month for the 30-day average
/// BaselineCard(title: StepsTile.title(isToday: isToday), accessory: AccuracyBadge(metric: "steps").map { AnyView($0) }) {
///     StepsTile(readout: s, window: .week, showsHeader: false, isToday: isToday)
/// }
/// ```
struct StepsTile: View {
    /// Which average the context line compares against.
    enum Window { case week, month }

    struct Bar: Identifiable, Equatable {
        let id: String      // day key
        let value: Double?  // nil = nothing recorded that day
    }

    let steps: Int?
    /// The average named in `averageLabel` (nil until enough days exist).
    let average: Double?
    /// "7-day" / "30-day": the window's name inside the context line.
    let averageLabel: String
    /// Days still needed before `average` appears, nil once it exists.
    var daysUntilAverage: Int? = nil
    /// Oldest → newest, the sparkline's bars (seven for a week).
    let bars: [Bar]
    /// The tile's own "Steps" header row; false when the host card's title names the metric.
    var showsHeader: Bool = true
    /// True while the count is still accruing (the selected day is today): "Steps so far", a neutral dot
    /// and a "still building" line instead of a delta and a judgement against full-day averages.
    var isToday: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(steps: Int?, average: Double?, averageLabel: String, daysUntilAverage: Int? = nil, bars: [Bar],
         showsHeader: Bool = true, isToday: Bool = false) {
        self.steps = steps
        self.average = average
        self.averageLabel = averageLabel
        self.daysUntilAverage = daysUntilAverage
        self.bars = bars
        self.showsHeader = showsHeader
        self.isToday = isToday
    }

    init(readout r: BaselineReadouts.StepsReadout, window: Window = .week, showsHeader: Bool = true,
         isToday: Bool = false) {
        let avg = window == .week ? r.average7 : r.average30
        let observed = window == .week ? r.observed7 : r.observed30
        self.init(steps: r.steps, average: avg, averageLabel: window == .week ? "7\u{2011}day" : "30\u{2011}day",
                  daysUntilAverage: avg == nil ? max(0, BaselineReadouts.averageMinDays - observed) : nil,
                  bars: r.recent.map { Bar(id: $0.day, value: $0.value) },
                  showsHeader: showsHeader, isToday: isToday)
    }

    private var numeral: String { BaselineReadouts.stepsText(steps) }

    /// The header's word for the count: "Steps so far" while it is still accruing.
    static func title(isToday: Bool) -> String { isToday ? "Steps so far" : "Steps" }

    /// The ONE context line. A completed day is judged against the average (`stepsDeltaText`); today is
    /// not: its count is partial and the averages are whole days, so the line says the day is still
    /// building (and when the average arrives, if it has not yet), the average itself staying in the
    /// "avg" caption beside the numeral so it is said once. Pure, for the tests.
    static func context(steps: Int?, average: Double?, averageLabel: String, daysUntilAverage: Int?,
                        isToday: Bool) -> String {
        let n = daysUntilAverage ?? BaselineReadouts.averageMinDays
        let waiting = "\(averageLabel) average after \(n) more day\(n == 1 ? "" : "s")"
        if steps == nil { return isToday ? "No steps recorded yet" : "No steps recorded" }
        if isToday { return average == nil ? "Builds through the day · \(waiting)" : "Builds through the day" }
        if let delta = BaselineReadouts.stepsDeltaText(steps: steps, average: average, windowLabel: averageLabel) {
            return delta
        }
        return waiting
    }

    /// The dot's colour: good from +5% over the average, watch from 25% under it, else `steps`;
    /// `textTertiary` without both sides; always `steps` on today, where a partial count earns no judgement.
    static func tone(steps: Int?, average: Double?, isToday: Bool) -> Color {
        guard let steps, let average else { return BaselineTheme.textTertiary }
        if isToday { return BaselineTheme.steps }
        let delta = Double(steps) - average
        if delta >= average * BaselineReadouts.stepsSteadyFraction { return BaselineTheme.good }
        if delta <= -average * 0.25 { return BaselineTheme.watch }
        return BaselineTheme.steps
    }

    /// VoiceOver's one sentence for the tile: the count, the average the "avg" caption shows (so it is
    /// heard, not only seen) and the context line: "8,412 steps, 7‑day average 6,000, +2,412 vs your 7‑day average".
    static func accessibilityLabel(numeral: String, average: Double?, averageLabel: String, context: String) -> String {
        var s = "\(numeral) steps"
        if let average { s += ", \(averageLabel) average \(BaselineReadouts.stepsText(Int(average.rounded())))" }
        return s + ", \(context)"
    }

    private var context: String {
        Self.context(steps: steps, average: average, averageLabel: averageLabel,
                     daysUntilAverage: daysUntilAverage, isToday: isToday)
    }

    private var tone: Color { Self.tone(steps: steps, average: average, isToday: isToday) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack(spacing: 6) {
                    Circle().fill(BaselineTheme.steps).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(Self.title(isToday: isToday)).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(numeral)
                        .font(BaselineTheme.hero(36))
                        .foregroundStyle(BaselineTheme.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    if let average {
                        Text("avg " + BaselineReadouts.stepsText(Int(average.rounded())))
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textSecondary)
                            .monospacedDigit()
                    }
                }
                sparkline
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(tone).frame(width: 6, height: 6)
                    Text(context)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(numeral: numeral, average: average,
                                                        averageLabel: averageLabel, context: context))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let sparkHeight: CGFloat = 28

    private var sparkline: some View {
        let peak = bars.compactMap(\.value).max() ?? 0
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(bars) { b in
                let h: CGFloat = {
                    guard let v = b.value, peak > 0 else { return 4 }
                    return max(4, Self.sparkHeight * CGFloat(v / peak))
                }()
                Capsule()
                    .fill(b.value == nil ? BaselineTheme.ringTrack
                          : (b.id == bars.last?.id ? BaselineTheme.steps : BaselineTheme.steps.opacity(0.45)))
                    .frame(width: 10, height: h)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.5), value: h)
            }
        }
        .frame(height: Self.sparkHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
#endif
