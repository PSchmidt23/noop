#if os(iOS)
import SwiftUI

/// The Readiness score as a NUMBER with a horizontal track bar, never a ring (trademark guardrail): the
/// numeral in `hero(36)` with "/ 100" beside it, the tone's pill, then an 8pt capsule track filled to the
/// score in the tone colour with two hairline ticks at NOOP's band edges (34 / 67) so the reader sees
/// which third the number sits in. ONE context sentence under the bar (the drivers sentence, or the
/// confidence caption), never truncated. Flat: lives inside a `BaselineCard`.
///
/// ```swift
/// let r = BaselineReadouts.readinessScore(for: day, days: repo.baselineDays)
/// ReadinessBar(score: r.score, tone: r.tone, label: r.tone.label, context: r.driversSentence)
/// ```
struct ReadinessBar: View {
    /// 0–100.
    let score: Double
    let tone: ReadinessTone
    /// The pill's text (`tone.label` unless the screen has a better word).
    let label: String
    /// The sentence under the bar (the funnel's drivers sentence or a calibration caption), verbatim.
    var context: String? = nil
    /// Draw the band ticks (34 / 67). Off for a compact tile.
    var showsBands: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackHeight: CGFloat = 8
    private static let bands: [Double] = [34, 67]

    private var fraction: Double { min(1, max(0, score / 100)) }
    private var numeral: String { "\(Int(score.rounded()))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(numeral)
                    .font(BaselineTheme.hero(36))
                    .foregroundStyle(BaselineTheme.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(BaselineReadouts.effortUnit)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                Spacer(minLength: 8)
                BaselinePill(text: label, color: color)
            }
            track
            if let context {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(context)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var s = "Readiness \(numeral) of 100, \(label)"
        if let context { s += ". \(context)" }
        return s
    }

    private var color: Color {
        switch tone {
        case .good: return BaselineTheme.good
        case .watch: return BaselineTheme.watch
        case .low: return BaselineTheme.low
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(BaselineTheme.ringTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(Self.trackHeight, w * fraction))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.6), value: fraction)
                if showsBands {
                    ForEach(Self.bands, id: \.self) { b in
                        Rectangle()
                            .fill(BaselineTheme.card)
                            .frame(width: 2, height: Self.trackHeight)
                            .offset(x: w * b / 100 - 1)
                    }
                }
            }
        }
        .frame(height: Self.trackHeight)
        .accessibilityHidden(true)
    }
}

extension ReadinessTone {
    /// The judgement colour a screen passes to a pill or dot for this tone (good / watch / low).
    var baselineColor: Color {
        switch self {
        case .good: return BaselineTheme.good
        case .watch: return BaselineTheme.watch
        case .low: return BaselineTheme.low
        }
    }
}
#endif
