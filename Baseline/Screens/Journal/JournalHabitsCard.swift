#if os(iOS)
import SwiftUI

/// The day's habits as a wrapping row of chips. Yes-no chips cycle yes → no → clear; numeric chips
/// step a count. A "no" is a real answer here: it is the control night the effects engine compares
/// against, so the card also offers "Mark the rest as no" once something is logged.
struct JournalHabitsCard: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject var model: JournalScreenModel
    let items: [JournalCatalogItem]
    let dayKey: String
    let label: (String) -> String
    let onAdd: () -> Void
    let onHide: (JournalCatalogItem) -> Void

    private var answeredCount: Int { items.filter { model.answers[$0.canonical] != nil }.count }
    private var unansweredCount: Int { items.count - answeredCount }

    var body: some View {
        BaselineCard(title: "Habits", subtitle: items.isEmpty ? nil : "Tap for yes, again for no, once more to clear. Hold to hide.",
                     accessory: items.isEmpty ? nil : AnyView(countPill)) {
            if items.isEmpty {
                BaselineEmptyState(icon: "checklist",
                                   title: "No habits yet",
                                   message: "Add the things you want to test against your HRV: a late coffee, a drink, a sauna.")
                addChip(wide: true)
            } else {
                BaselineFlowLayout(spacing: 8) {
                    ForEach(items) { item in
                        if item.kind.isNumeric {
                            JournalNumericChip(label: label(item.canonical),
                                               unit: item.kind.unitLabel,
                                               state: numericState(item),
                                               onChange: { v in step(item, to: v) })
                                .contextMenu { hideButton(item) }
                        } else {
                            JournalHabitChip(label: label(item.canonical),
                                             state: model.answers[item.canonical],
                                             action: { cycle(item) })
                                .contextMenu { hideButton(item) }
                        }
                    }
                    addChip(wide: false)
                }
                if answeredCount > 0 && unansweredCount > 0 {
                    Button {
                        Task { await model.markRestNo(questions: items.map(\.canonical), day: dayKey, repo: repo) }
                    } label: {
                        Label("Mark the rest as no", systemImage: "checkmark.circle")
                            .font(BaselineTheme.caption.weight(.semibold))
                            .foregroundStyle(BaselineTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var countPill: some View {
        Text("\(answeredCount) of \(items.count)")
            .font(BaselineTheme.caption)
            .foregroundStyle(answeredCount == items.count && !items.isEmpty ? BaselineTheme.good : BaselineTheme.textTertiary)
    }

    private func addChip(wide: Bool) -> some View {
        Button(action: onAdd) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(BaselineTheme.symbolSmall)
                Text(wide ? "Add a habit" : "Add")
            }
            .font(BaselineTheme.caption.weight(.semibold))
            .foregroundStyle(BaselineTheme.accent)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: wide ? CGFloat.infinity : nil)
            .background(BaselineTheme.accent.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(BaselineTheme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a habit")
    }

    private func hideButton(_ item: JournalCatalogItem) -> some View {
        Button(role: .destructive) { onHide(item) } label: {
            Label(item.custom ? "Delete habit" : "Hide habit", systemImage: "eye.slash")
        }
    }

    // MARK: State → writes

    /// yes → no → clear → yes.
    private func cycle(_ item: JournalCatalogItem) {
        let next: Bool?
        switch model.answers[item.canonical] {
        case nil: next = true
        case .some(true): next = false
        case .some(false): next = nil
        }
        Task { await model.setAnswer(next, question: item.canonical, day: dayKey, repo: repo) }
    }

    private func numericState(_ item: JournalCatalogItem) -> JournalNumericChip.Entry {
        if let v = model.numeric[item.canonical] { return .value(v) }
        switch model.answers[item.canonical] {
        case .some(true): return .value(1)
        case .some(false): return .no
        case nil: return .unanswered
        }
    }

    /// Steps walk value … 1 → no → clear; anything ≥ 1 is a numeric log.
    private func step(_ item: JournalCatalogItem, to value: Double?) {
        Task {
            if let value, value >= 1 {
                await model.setNumeric(value, question: item.canonical, day: dayKey, repo: repo)
            } else if value != nil {
                await model.setAnswer(false, question: item.canonical, day: dayKey, repo: repo)
            } else {
                await model.setAnswer(nil, question: item.canonical, day: dayKey, repo: repo)
            }
        }
    }
}

/// A yes-no chip. `state` nil = unanswered, true = yes (accent), false = no (dim with a cross).
struct JournalHabitChip: View {
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
            .padding(.horizontal, 12).padding(.vertical, 8)
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
        state == true ? BaselineTheme.accent.opacity(0.18) : BaselineTheme.card
    }
    private var stroke: Color {
        state == true ? BaselineTheme.accent.opacity(0.55) : BaselineTheme.hairline
    }
    private var textColor: Color {
        switch state {
        case .some(true): return BaselineTheme.text
        case .some(false): return BaselineTheme.textTertiary
        case nil: return BaselineTheme.textSecondary
        }
    }
}

/// A stepper chip for a numeric habit: "Alcohol · 2" with − and + inside the capsule.
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
                            .foregroundStyle(BaselineTheme.accent)
                            .contentTransition(.numericText())
                        if let unit, !unit.isEmpty {
                            Text(unit).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        }
                    }
                }
                .font(BaselineTheme.label)
                .foregroundStyle(textColor)
                .padding(.horizontal, state == .unanswered ? 12 : 6)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            stepButton("plus") { onChange((value ?? 0) + 1) }
        }
        .background(isYes ? BaselineTheme.accent.opacity(0.18) : BaselineTheme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(isYes ? BaselineTheme.accent.opacity(0.55) : BaselineTheme.hairline, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
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
                .frame(width: 28, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase \(label)" : "Decrease \(label)")
    }
}
#endif
