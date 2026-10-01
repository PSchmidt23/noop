#if os(iOS)
import SwiftUI

/// Journal: tag the habits behind last night, then see which of them move HRV and resting HR.
/// Day convention follows the engine: an answer stored under day D describes the evening and
/// night leading into morning D, so today's key reads "Last night".
struct JournalScreen: View {
    @EnvironmentObject private var repo: Repository
    /// The app's one catalog store (injected by `BaselineApp`), shared with the Today tab's chips.
    @EnvironmentObject private var catalog: JournalCatalogStore
    @StateObject private var model = JournalScreenModel()
    /// 0 = today's key (last night), 1 = yesterday's key, … 6.
    @State private var dayOffset = 0
    @State private var showAddHabit = false

    private var dayKey: String { JournalDay.key(offset: dayOffset) }

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
        BaselineScreen(title: "Journal") {
            JournalDayStrip(selected: $dayOffset, loggedDays: model.loggedDayKeys)
            Text(JournalDay.caption(offset: dayOffset))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .padding(.top, -6)

            JournalHabitsCard(model: model, items: items, dayKey: dayKey,
                              label: label(for:),
                              onAdd: { showAddHabit = true },
                              onHide: { catalog.remove($0.canonical) })

            BaselineSectionLabel(text: "Patterns")
            JournalEffectsCard(model: model, label: label(for:))
            ForEach(model.doses) { JournalDoseCard(dose: $0) }
        }
        .task(id: repo.refreshSeq) { await model.load(repo: repo, day: dayKey) }
        .onChange(of: dayOffset) { _, _ in
            Task { await model.reloadDay(repo: repo, day: dayKey) }
        }
        .sheet(isPresented: $showAddHabit) {
            JournalAddHabitSheet(catalog: catalog, imported: model.importedQuestions)
        }
    }

    /// Short chip / row label for a canonical question: the user's rename, else the short form.
    private func label(for canonical: String) -> String {
        if let n = catalog.item(for: canonical)?.displayName, !n.isEmpty { return n }
        return JournalLabels.short(canonical)
    }
}

/// The last seven days as equal-width chips, oldest → newest, today at the trailing edge. Fits every
/// iPhone width without scrolling, so no chip is ever cut off. A dot marks days that already carry
/// an answer; the caption under the strip names the selected night ("Last night", "Yesterday").
struct JournalDayStrip: View {
    @Binding var selected: Int
    let loggedDays: Set<String>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(JournalDay.offsets, id: \.self) { offset in chip(offset) }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ offset: Int) -> some View {
        let isSelected = offset == selected
        let logged = loggedDays.contains(JournalDay.key(offset: offset))
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selected = offset }
        } label: {
            VStack(spacing: 3) {
                Text(JournalDay.title(offset: offset))
                    .font(BaselineTheme.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? BaselineTheme.text : BaselineTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(JournalDay.dayNumber(offset: offset))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(isSelected ? BaselineTheme.text : BaselineTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Circle()
                    .fill(logged ? BaselineTheme.accent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(isSelected ? BaselineTheme.accent.opacity(0.18) : BaselineTheme.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? BaselineTheme.accent.opacity(0.55) : BaselineTheme.cardStroke, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(JournalDay.caption(offset: offset))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
