#if os(iOS)
import SwiftUI

/// The day's habits as a wrapping row of chips (`BaselineChip` / `JournalNumericChip`, Components).
/// Yes-no chips cycle yes → no → clear; numeric chips step a count. A "no" is a real answer here: it
/// is the control night the effects engine compares against, so the card also offers "Mark the rest
/// as no" once something is logged. Hold a chip to hide or delete the habit. Title "Habits" is a
/// UI-test anchor.
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
        BaselineCard(title: "Habits", accessory: items.isEmpty ? nil : AnyView(countText)) {
            if items.isEmpty {
                BaselineEmptyState(icon: "checklist",
                                   title: "No habits yet",
                                   message: "Add the things you want to test against your HRV: a late coffee, a drink, a sauna. Tap a chip for yes, again for no, once more to clear; hold one to hide it.")
                BaselineCTA(title: "Add a habit", prominent: false, action: onAdd)
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
                            BaselineChip(label: label(item.canonical),
                                         state: model.answers[item.canonical],
                                         action: { cycle(item) })
                                .contextMenu { hideButton(item) }
                        }
                    }
                    BaselineAddChip(title: "Add habit", action: onAdd)
                        .accessibilityLabel("Add a habit")
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

    /// "3 of 7", good once every habit has an answer.
    private var countText: some View {
        Text("\(answeredCount) of \(items.count)")
            .font(BaselineTheme.caption)
            .foregroundStyle(answeredCount == items.count ? BaselineTheme.good : BaselineTheme.textTertiary)
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

/// One day's habits card with its own model and the add-habit sheet: the body of `JournalSheet`, and
/// of the thin `JournalScreen` wrapper. `day` is the engine's "yyyy-MM-dd" key; the card reloads when
/// the store refreshes or the day changes.
struct JournalDayHabits: View {
    @EnvironmentObject private var repo: Repository
    /// The app's one catalog store (injected by `BaselineApp`), shared with Home's journal prompt.
    @EnvironmentObject private var catalog: JournalCatalogStore
    @StateObject private var model = JournalScreenModel()
    @State private var showAddHabit = false
    let day: String

    private struct LoadKey: Hashable {
        let seq: Int
        let day: String
    }

    /// The merged catalog (imported ∪ starter ∪ custom), hidden items dropped, grouped then ordered.
    private var items: [JournalCatalogItem] {
        let order = Dictionary(uniqueKeysWithValues: JournalGroup.displayOrder.enumerated().map { ($1, $0) })
        return catalog.resolvedItems(imported: model.importedQuestions).sorted {
            let ga = order[$0.group] ?? 99, gb = order[$1.group] ?? 99
            if ga != gb { return ga < gb }
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.display < $1.display
        }
    }

    var body: some View {
        JournalHabitsCard(model: model, items: items, dayKey: day,
                          label: label(for:),
                          onAdd: { showAddHabit = true },
                          onHide: { catalog.remove($0.canonical) })
            .task(id: LoadKey(seq: repo.refreshSeq, day: day)) { await model.loadDay(repo: repo, day: day) }
            .sheet(isPresented: $showAddHabit) {
                JournalAddHabitSheet(catalog: catalog, imported: model.importedQuestions)
            }
    }

    /// Short chip label for a canonical question: the user's rename, else the short form (the same
    /// table Home's prompt reads, so a habit has one name everywhere).
    private func label(for canonical: String) -> String {
        if let n = catalog.item(for: canonical)?.displayName, !n.isEmpty { return n }
        return JournalLabels.short(canonical)
    }
}
#endif
