#if os(iOS)
import SwiftUI

/// The Readiness score as a NUMBER with a horizontal track bar, never a ring (trademark guardrail): the
/// numeral in `hero(36)` with "/ 100" beside it, the tone's pill, then an 8pt capsule track filled to the
/// score in the tone colour. The track is a plain fill, no marks at NOOP's band edges: tick marks at
/// 34 / 67 on a 0–100 bar would reproduce WHOOP's published Recovery banding (the one trait a bar can
/// still copy from a ring), and in `card` white on `ringTrack` they were barely visible anyway. The
/// judgement lives in the pill and the fill's tone, which come from the engine's `RecoveryScorer.band`
/// through `ReadinessTone`, so no cut point is spelled here. ONE context sentence under the bar (the
/// drivers sentence, or the confidence caption), never truncated. Flat: lives inside a `BaselineCard`.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackHeight: CGFloat = 8

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

    private var color: Color { tone.baselineColor }

    /// The track: a `ringTrack` capsule with a single tone-coloured fill to the score.
    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(BaselineTheme.ringTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(Self.trackHeight, w * fraction))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.6), value: fraction)
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
