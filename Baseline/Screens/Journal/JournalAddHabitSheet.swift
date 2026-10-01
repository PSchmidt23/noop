#if os(iOS)
import SwiftUI

/// Add a custom habit (yes-no or a count) to the catalog, and restore any hidden ones.
struct JournalAddHabitSheet: View {
    @ObservedObject var catalog: JournalCatalogStore
    let imported: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isNumeric = false
    @State private var unit = ""
    @State private var group: JournalGroup = .lifestyle
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hidden: [JournalCatalogItem] {
        catalog.resolvedItems(imported: imported, includeHidden: true).filter(\.hidden)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Habit") {
                        TextField("e.g. Cold shower", text: $name)
                            .font(BaselineTheme.body)
                            .foregroundStyle(BaselineTheme.text)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                    }
                    // The shared segmented pill carries its own capsule, so it sits under the caption
                    // without `field`'s card around it.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type").font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        BaselineSegmentedPicker(options: [false, true], selection: $isNumeric,
                                                label: { $0 ? "Count" : "Yes / No" },
                                                accessibilityLabel: { $0 ? "A count, like drinks or minutes" : "A yes or no" })
                    }
                    if isNumeric {
                        field("Unit (optional)") {
                            TextField("drinks, mg, minutes", text: $unit)
                                .font(BaselineTheme.body)
                                .foregroundStyle(BaselineTheme.text)
                        }
                    }
                    field("Group") {
                        Picker("Group", selection: $group) {
                            ForEach(JournalGroup.displayOrder, id: \.self) { g in Text(g.title).tag(g) }
                        }
                        .pickerStyle(.menu)
                        .tint(BaselineTheme.accent)
                    }
                    Text("Baseline keeps the name as the key for this habit, so pick one you will keep. Short names read best as chips.")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !hidden.isEmpty {
                        BaselineSectionLabel(text: "Hidden")
                        BaselineCard {
                            VStack(spacing: 0) {
                                ForEach(Array(hidden.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().overlay(BaselineTheme.hairline) }
                                    HStack {
                                        Text(JournalLabels.short(item.displayName ?? item.canonical))
                                            .font(BaselineTheme.body)
                                            .foregroundStyle(BaselineTheme.textSecondary)
                                        Spacer()
                                        Button("Restore") { catalog.restore(item.canonical) }
                                            .font(BaselineTheme.caption.weight(.semibold))
                                            .foregroundStyle(BaselineTheme.accent)
                                            .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(BaselineBackground())
            .scrollIndicators(.hidden)
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(BaselineTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .fontWeight(.semibold)
                        .foregroundStyle(trimmed.isEmpty ? BaselineTheme.textTertiary : BaselineTheme.accent)
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            content()
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BaselineTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BaselineTheme.cardStroke, lineWidth: 1))
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        catalog.addCustom(trimmed, kind: isNumeric ? .numeric(unitLabel: u.isEmpty ? nil : u) : .bool, group: group)
        dismiss()
    }
}
#endif
