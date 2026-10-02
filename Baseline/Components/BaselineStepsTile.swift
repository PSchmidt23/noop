#if os(iOS)
import SwiftUI

/// The day's steps against the person's own average, with a seven-bar sparkline of the week ending on
/// that day. Number in `hero(36)`, ONE context line ("+1,240 vs your 7-day average" / "7-day average
/// after 3 days"), then seven 4pt capsules scaled to the week's highest count (a day with no count is an
/// empty `ringTrack` stub). Flat; sits in a `BaselineCard(title: "Steps")` or a tile.
///
/// ```swift
/// let s = await BaselineReadouts.steps(repo, for: day)
/// StepsTile(readout: s, window: .week)        // or .month for the 30-day average
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(steps: Int?, average: Double?, averageLabel: String, daysUntilAverage: Int? = nil, bars: [Bar]) {
        self.steps = steps
        self.average = average
        self.averageLabel = averageLabel
        self.daysUntilAverage = daysUntilAverage
        self.bars = bars
    }

    init(readout r: BaselineReadouts.StepsReadout, window: Window = .week) {
        let avg = window == .week ? r.average7 : r.average30
        let observed = window == .week ? r.observed7 : r.observed30
        self.init(steps: r.steps, average: avg, averageLabel: window == .week ? "7\u{2011}day" : "30\u{2011}day",
                  daysUntilAverage: avg == nil ? max(0, BaselineReadouts.averageMinDays - observed) : nil,
                  bars: r.recent.map { Bar(id: $0.day, value: $0.value) })
    }

    private var numeral: String { BaselineReadouts.stepsText(steps) }

    /// The ONE context line.
    private var context: String {
        if let delta = BaselineReadouts.stepsDeltaText(steps: steps, average: average, windowLabel: averageLabel) {
            return delta
        }
        if steps == nil { return "No steps recorded" }
        let n = daysUntilAverage ?? BaselineReadouts.averageMinDays
        return "\(averageLabel) average after \(n) more day\(n == 1 ? "" : "s")"
    }

    private var tone: Color {
        guard let steps, let average else { return BaselineTheme.textTertiary }
        let delta = Double(steps) - average
        if delta >= average * BaselineReadouts.stepsSteadyFraction { return BaselineTheme.good }
        if delta <= -average * 0.25 { return BaselineTheme.watch }
        return BaselineTheme.steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(BaselineTheme.steps).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("Steps").font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
                    .accessibilityAddTraits(.isHeader)
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
            .accessibilityLabel("\(numeral) steps, \(context)")
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
