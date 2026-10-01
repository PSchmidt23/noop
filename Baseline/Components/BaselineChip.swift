#if os(iOS)
import SwiftUI

/// A yes / no / unanswered habit chip (Today's journal prompt, the Journal tab). Flat, never glass:
/// seven to twenty of these sit in one card. Capsule, 44pt hit target. nil: card fill with a 1pt
/// `inactive` stroke, text secondary. true: accent @ 0.12 fill, a bold check in accent, ink text.
/// false: `chipFill`, an x in tertiary, tertiary text.
struct BaselineChip: View {
    let label: String
    let state: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let state {
                    Image(systemName: state ? "checkmark" : "xmark")
                        .font(BaselineTheme.symbolSmall.weight(.bold))
                        .foregroundStyle(state ? BaselineTheme.accent : BaselineTheme.textTertiary)
                }
                Text(label)
                    .font(BaselineTheme.label)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: state)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        switch state {
        case .some(true): return "yes"
        case .some(false): return "no"
        case nil: return "not answered"
        }
    }

    private var fill: Color {
        switch state {
        case .some(true): return BaselineTheme.accent.opacity(0.12)
        case .some(false): return BaselineTheme.chipFill
        case nil: return BaselineTheme.card
        }
    }
    private var stroke: Color {
        state == nil ? BaselineTheme.inactive : Color.clear
    }
    private var textColor: Color {
        switch state {
        case .some(true): return BaselineTheme.text
        case .some(false): return BaselineTheme.textTertiary
        case nil: return BaselineTheme.textSecondary
        }
    }
}

/// The Journal screens' name for the same chip.
typealias JournalHabitChip = BaselineChip

/// A stepper chip for a numeric habit: "Alcohol · 2" with − and + inside the capsule. The same three
/// fills as `BaselineChip`. The magnitude is ink like the label (the flat-pill rule: colour as a fill,
/// text in ink), semibold so the number still leads; the accent @ 0.12 fill alone carries the yes state.
/// Accent text on that fill measures ≈ 4.4:1, under the 4.5:1 every text inside a card must keep.
struct JournalNumericChip: View {
    enum Entry: Equatable { case unanswered, no, value(Double) }

    let label: String
    let unit: String?
    let state: Entry
    /// nil = clear, 0 = no, ≥ 1 = value.
    let onChange: (Double?) -> Void

    private var value: Double? { if case let .value(v) = state { return v } else { return nil } }
    private var isYes: Bool { value != nil }

    var body: some View {
        HStack(spacing: 0) {
            if state != .unanswered {
                stepButton("minus") {
                    switch state {
                    case .value(let v) where v > 1: onChange(v - 1)
                    case .value: onChange(0)
                    case .no: onChange(nil)
                    case .unanswered: break
                    }
                }
            }
            Button {
                if state == .unanswered { onChange(1) }
            } label: {
                HStack(spacing: 5) {
                    if state == .no {
                        Image(systemName: "xmark").font(BaselineTheme.symbolSmall.weight(.bold))
                            .foregroundStyle(BaselineTheme.textTertiary)
                    }
                    Text(label).lineLimit(1)
                    if let value {
                        Text("·").foregroundStyle(BaselineTheme.textTertiary)
                        Text(JournalLabels.magnitude(value))
                            .font(BaselineTheme.label.weight(.semibold))
                            .foregroundStyle(BaselineTheme.text)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if let unit, !unit.isEmpty {
                            Text(unit).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        }
                    }
                }
                .font(BaselineTheme.label)
                .foregroundStyle(textColor)
                .padding(.horizontal, state == .unanswered ? 14 : 6)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            stepButton("plus") { onChange((value ?? 0) + 1) }
        }
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(state == .unanswered ? BaselineTheme.inactive : Color.clear, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        switch state {
        case .value: return BaselineTheme.accent.opacity(0.12)
        case .no: return BaselineTheme.chipFill
        case .unanswered: return BaselineTheme.card
        }
    }

    private var textColor: Color {
        switch state {
        case .value: return BaselineTheme.text
        case .no: return BaselineTheme.textTertiary
        case .unanswered: return BaselineTheme.textSecondary
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BaselineTheme.symbolSmall)
                .foregroundStyle(BaselineTheme.textSecondary)
                .frame(width: 28, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase \(label)" : "Decrease \(label)")
    }
}

/// The "Add" chip at the end of a habit flow: a plus and the title in accent on accent @ 0.10 with a
/// faint accent stroke. `wide` stretches it to the row (the empty-card case).
struct BaselineAddChip: View {
    let title: String
    var wide: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(BaselineTheme.symbolSmall.weight(.bold))
                Text(title).font(BaselineTheme.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(BaselineTheme.accent)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(BaselineTheme.accent.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(BaselineTheme.accent.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
