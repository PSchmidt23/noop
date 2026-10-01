#if os(iOS)
import SwiftUI
import StrandAnalytics

/// "What moves your HRV": each logged habit compared on nights with and without it, ranked solid
/// first then by the size of the shift. Association on your own nights, never a causal claim.
struct JournalEffectsCard: View {
    @ObservedObject var model: JournalScreenModel
    let label: (String) -> String

    var body: some View {
        BaselineCard(title: "What moves your \(model.outcome.label)",
                     subtitle: "Nights with a habit versus nights without. Patterns, not causes.") {
            Picker("Outcome", selection: $model.outcome) {
                ForEach(JournalOutcome.allCases) { o in Text(o.label).tag(o) }
            }
            .pickerStyle(.segmented)

            if !model.loaded {
                BaselineEmptyState(icon: "hourglass", title: "Reading your journal", message: " ")
            } else if model.loggedDayCount < JournalScreenModel.minLoggedDays {
                BaselineEmptyState(icon: "sparkles",
                                   title: "Patterns take a few nights",
                                   message: "Log a few more days and Baseline will start finding patterns. \(model.loggedDayCount) of \(JournalScreenModel.minLoggedDays) logged so far.")
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
        }
    }
}

/// One ranked habit: name, signed shift, confidence pill, and the nights behind it.
struct JournalEffectRow: View {
    let effect: RankedEffect
    let label: String
    let outcome: JournalOutcome

    private var delta: Double { effect.effect.delta }
    private var deltaColor: Color {
        if abs(delta) < 0.5 { return BaselineTheme.textSecondary }
        let good = outcome.higherIsBetter ? delta > 0 : delta < 0
        return good ? BaselineTheme.good : BaselineTheme.watch
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.text)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    JournalConfidencePill(confidence: effect.confidence)
                    Text(detail)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(JournalLabels.signedDelta(delta, unit: outcome.unit))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(deltaColor)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// "12 nights · vs 30 without · next morning"
    private var detail: String {
        let n = effect.effect.nWith
        let nights = n == 1 ? "1 night" : "\(n) nights"
        return "\(nights) · vs \(effect.effect.nWithout) without · \(effect.leadLagText)"
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

/// A dose-response read for alcohol or caffeine timing: one sentence, the per-unit shift, nights.
struct JournalDoseCard: View {
    let dose: JournalDose

    var body: some View {
        BaselineCard(title: dose.title, subtitle: "Dose response · \(dose.outcomeLabel) next morning",
                     accessory: AnyView(Image(systemName: dose.icon)
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(BaselineTheme.textTertiary))) {
            Text(dose.sentence)
                .font(BaselineTheme.body)
                .foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 12) {
                StatCell(label: dose.perUnitLabel,
                         value: JournalLabels.signedDelta(dose.response.perUnit, unit: ""),
                         unit: dose.unit,
                         color: dose.perUnitColor)
                StatCell(label: "Nights", value: "\(dose.response.nUser)")
                JournalConfidencePill(confidence: dose.response.confidence)
            }
        }
    }
}
#endif
