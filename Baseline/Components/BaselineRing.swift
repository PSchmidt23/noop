#if os(iOS)
import SwiftUI
import StrandAnalytics

/// Pure, testable scale math for a metric ring: a display domain and a clamped fraction. It NEVER
/// changes a number: the domain only decides how much of the arc fills, the numeral is always the
/// funnel's exact value (`BaselineReadouts` / `TodaySnapshot` / `SleepNightBuilder`). No view computes a
/// baseline, band or average itself; it hands the funnel's `BaselineState` here.
enum MetricRingScale {
    /// `baseline ∓ 3·sigma`, sigma floored at 5% of the baseline, clamped to `cfg.minVal…cfg.maxVal`.
    /// nil while `!state.usable` (calibrating): the ring shows its track only.
    static func domain(state: BaselineState, cfg: MetricCfg) -> ClosedRange<Double>? {
        guard state.usable else { return nil }
        let sigma = max(Baselines.sigma(state), abs(state.baseline) * 0.05)
        let lower = max(cfg.minVal, state.baseline - 3 * sigma)
        let upper = min(cfg.maxVal, state.baseline + 3 * sigma)
        guard lower < upper else { return nil }
        return lower...upper
    }

    /// `0…max(540, (average30 ?? 0) + 60)` minutes: nine hours, or an hour past the 30-night average.
    static func sleepDomain(average30: Double?) -> ClosedRange<Double> {
        0...max(540, (average30 ?? 0) + 60)
    }

    /// `(value − lower) / (upper − lower)` clamped to 0…1.
    static func fraction(_ value: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - domain.lowerBound) / span))
    }

    /// `valueText ?? "\(Int(value.rounded()))"`; "–" when there is no value. Never clamped.
    static func numeral(value: Double?, valueText: String?) -> String {
        if let valueText { return valueText }
        guard let value else { return "–" }
        return "\(Int(value.rounded()))"
    }
}

/// A single Garmin / Oura-style 270° gauge (open at the bottom) for ONE metric: track, the baseline
/// band as a thicker translucent arc, the value arc in the metric colour, a baseline tick, the numeral
/// in the centre, the label above and ONE context sentence (the funnel's text verbatim) below.
/// Today shows exactly two (HRV, Resting HR), each in its own tile; the Sleep tab shows one. Never
/// three together, never concentric, never a readiness ring (trademark guardrail).
struct MetricRing: View {
    let value: Double?
    /// nil → empty ring (track only); the numeral is still printed.
    let domain: ClosedRange<Double>?
    let color: Color
    /// "HRV" — rendered as its own Text, OUTSIDE the ring's combined accessibility element, so a UI
    /// test's `staticTexts["HRV"]` matches.
    let label: String
    /// "ms" / "bpm" / "" (a duration numeral carries its own units).
    let unit: String
    /// The ONE sentence under the ring (funnel text verbatim). Wraps to as many lines as it needs; it is
    /// never truncated, so the band position at its end always survives.
    let context: String
    /// baseline ± sigma → a thicker arc under the value arc, `color.opacity(0.18)`.
    var band: ClosedRange<Double>? = nil
    /// 2pt × 14pt radial tick in `color.opacity(0.5)` at the baseline angle.
    var baseline: Double? = nil
    /// 6pt dot before `context` (good / watch / textTertiary), computed by the caller.
    var tone: Color? = nil
    var size: CGFloat = BaselineTheme.ringSize
    var lineWidth: CGFloat = BaselineTheme.ringLineWidth
    var valueText: String? = nil
    var numeralFont: Font = BaselineTheme.hero(44)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 270° sweep: trim 0…0.75 of a circle rotated 135°, so the gap sits at the bottom.
    private static let sweep = 0.75
    private static let startAngle = 135.0

    private var numeral: String { MetricRingScale.numeral(value: value, valueText: valueText) }

    private var valueFraction: Double {
        guard let value, let domain else { return 0 }
        return MetricRingScale.fraction(value, in: domain)
    }

    private var bandFractions: (from: Double, to: Double)? {
        guard let band, let domain else { return nil }
        return (MetricRingScale.fraction(band.lowerBound, in: domain), MetricRingScale.fraction(band.upperBound, in: domain))
    }

    private var baselineFraction: Double? {
        guard let baseline, let domain else { return nil }
        return MetricRingScale.fraction(baseline, in: domain)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(label).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
            }
            VStack(spacing: 8) {
                ring
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let tone { Circle().fill(tone).frame(width: 6, height: 6) }
                    // No line limit: the sentence is the number's context (its baseline delta AND its
                    // band position) and must never end in an ellipsis. A carried value's "Woke Mon 28 Sep
                    // · +6 ms vs baseline · inside your band" needs three lines in a 170pt tile at the
                    // default size and more at the larger Dynamic Type sizes; the tile grows with it.
                    Text(context)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityText: String {
        let units = unit.isEmpty ? numeral : "\(numeral) \(unit)"
        return "\(label) \(units), \(context)"
    }

    private var ring: some View {
        ZStack {
            // 1 · track
            arc(from: 0, to: 1)
                .stroke(BaselineTheme.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // 2 · band arc (thicker, translucent)
            if let b = bandFractions, b.to > b.from {
                arc(from: b.from, to: b.to)
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .round))
            }
            // 3 · value arc
            if domain != nil, value != nil {
                arc(from: 0, to: valueFraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.6), value: valueFraction)
            }
            // 4 · baseline tick
            if let f = baselineFraction {
                Rectangle()
                    .fill(color.opacity(0.5))
                    .frame(width: 2, height: 14)
                    .offset(y: -(size / 2))
                    .rotationEffect(.degrees(Self.tickDegrees(fraction: f)))
            }
            VStack(spacing: 0) {
                Text(numeral)
                    .font(numeralFont)
                    .foregroundStyle(BaselineTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                }
            }
            .padding(.horizontal, lineWidth + 10)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// A slice of the 270° sweep, `from`…`to` as fractions of the sweep (0…1), clockwise from the
    /// bottom-left start.
    private func arc(from: Double, to: Double) -> some Shape {
        Circle()
            .trim(from: from * Self.sweep, to: to * Self.sweep)
            .rotation(.degrees(Self.startAngle))
    }

    /// `rotationEffect` of a view offset straight up: 0° is 12 o'clock, clockwise positive. The sweep
    /// starts at 7:30 (225° from 12 o'clock) and runs 270° clockwise.
    static func tickDegrees(fraction: Double) -> Double { 225 + 270 * fraction }
}
#endif
