#if os(iOS)
import SwiftUI
import StrandAnalytics

/// "What moves your HRV": each logged habit compared on nights with and without it, ranked solid
/// first then by the size of the shift, with the dose-response rows (alcohol, caffeine timing) at the
/// foot. Association on your own nights, never a causal claim.
struct JournalEffectsCard: View {
    @ObservedObject var model: JournalScreenModel
    let label: (String) -> String

    var body: some View {
        BaselineCard(title: "What moves your \(model.outcome.label)") {
            // The app's one segmented control, flat inside a card.
            BaselineSegmentedPicker(options: JournalOutcome.allCases, selection: $model.outcome,
                                    label: { $0.label },
                                    accessibilityLabel: { "What moves your \($0.label)" },
                                    style: .flat)

            if !model.loaded {
                BaselineEmptyState(icon: "hourglass", title: "Reading your journal", message: " ")
            } else if model.loggedDayCount < JournalScreenModel.minLoggedDays {
                BaselineEmptyState(icon: "sparkles",
                                   title: "Patterns take a few nights",
                                   message: "Log a few more days and Baseline will compare nights with a habit against nights without. Patterns, not causes. \(model.loggedDayCount) of \(JournalScreenModel.minLoggedDays) logged so far.")
            } else if model.effects.isEmpty {
                BaselineEmptyState(icon: "scale.3d",
                                   title: "Keep logging both ways",
                                   message: "Baseline needs at least 5 nights with a habit and 5 without before it compares them. Yes and no both count.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.effects.enumerated()), id: \.element.behavior) { index, effect in
                        if index > 0 { Divider().overlay(BaselineTheme.hairline) }
                        JournalEffectRow(effect: effect, label: label(effect.behavior), outcome: model.outcome)
                            .padding(.vertical, 10)
                    }
                }
            }

            if !model.doses.isEmpty {
                Divider().overlay(BaselineTheme.hairline)
                VStack(spacing: 0) {
                    ForEach(Array(model.doses.enumerated()), id: \.element.id) { index, dose in
                        if index > 0 { Divider().overlay(BaselineTheme.hairline) }
                        JournalDoseRow(dose: dose)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

/// One ranked habit: name, confidence pill and the nights behind it, the signed shift trailing.
struct JournalEffectRow: View {
    let effect: RankedEffect
    let label: String
    let outcome: JournalOutcome
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var delta: Double { effect.effect.delta }
    private var steady: Bool { abs(delta) < 0.5 }
    private var good: Bool { outcome.higherIsBetter ? delta > 0 : delta < 0 }
    private var deltaColor: Color {
        if steady { return BaselineTheme.textSecondary }
        return good ? BaselineTheme.good : BaselineTheme.watch
    }
    /// The colour's judgement, said: "+4 ms, better".
    private var deltaSpoken: String {
        let text = JournalLabels.signedDelta(delta, unit: outcome.unit)
        return steady ? text : "\(text), \(good ? "better" : "worse")"
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The scaled delta would squeeze the name and pill into a word-per-line column.
                VStack(alignment: .leading, spacing: 6) {
                    name
                    deltaText
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    name
                    Spacer(minLength: 12)
                    deltaText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(BaselineTheme.body)
                .foregroundStyle(BaselineTheme.text)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                JournalConfidencePill(confidence: effect.confidence)
                Text(detail)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deltaText: some View {
        Text(JournalLabels.signedDelta(delta, unit: outcome.unit))
            .font(BaselineTheme.stat)
            .foregroundStyle(deltaColor)
            .monospacedDigit()
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel(deltaSpoken)
    }

    /// "13 vs 25 nights \u{00B7} next morning" (with-habit vs without-habit nights, then the lag).
    private var detail: String {
        "\(effect.effect.nWith) vs \(effect.effect.nWithout) nights \u{00B7} \(effect.leadLagText)"
    }
}

/// Calibrating / Building / Solid.
struct JournalConfidencePill: View {
    let confidence: ScoreConfidence
    var body: some View {
        switch confidence {
        case .calibrating: BaselinePill(text: "Calibrating", color: BaselineTheme.textTertiary)
        case .building: BaselinePill(text: "Building", color: BaselineTheme.watch)
        case .solid: BaselinePill(text: "Solid", color: BaselineTheme.good)
        }
    }
}

/// A dose-response read for alcohol or caffeine timing at the foot of the patterns card: glyph, title,
/// the one sentence, the confidence pill, and for caffeine the per-step shift in ms. Alcohol shows no
/// figure: its outcome is a score Baseline never renders (see `JournalDose`).
struct JournalDoseRow: View {
    let dose: JournalDose
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: dose.icon)
                .font(BaselineTheme.symbol)
                .foregroundStyle(BaselineTheme.textTertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(dose.title)
                    .font(BaselineTheme.label)
                    .foregroundStyle(BaselineTheme.text)
                Text(dose.sentence)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // At accessibility sizes the figure sits under the sentence, never beside it.
                if dynamicTypeSize.isAccessibilitySize { perUnit }
                JournalConfidencePill(confidence: dose.response.confidence)
            }
            if !dynamicTypeSize.isAccessibilitySize, dose.perUnitStat != nil {
                Spacer(minLength: 12)
                perUnit
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var perUnit: some View {
        if let stat = dose.perUnitStat {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(dose.perUnitText)
                    .font(BaselineTheme.stat)
                    .foregroundStyle(stat.color)
                    .monospacedDigit()
                Text(stat.unit)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel("\(dose.perUnitText) \(stat.unit) \(stat.label.lowercased())")
        }
    }
}
#endif
