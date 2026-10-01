#if os(iOS)
import SwiftUI

/// The journal for one day, as a sheet over Home: the day's night label under the "Journal" title,
/// that day's habit chips (yes / no / clear, numeric steps), "Add habit", and a Done item. `day` is the
/// engine's "yyyy-MM-dd" key for the morning the night led into (`JournalDay.key(for:)` /
/// `Repository.localDayKey`), the same day Home shows. System sheet chrome (the Done item takes the
/// bar's glass; nothing adds glass inside), flat body on `BaselineBackground`.
///
/// Home can refresh its own journal prompt on `.sheet(onDismiss:)` or on `JournalScreenModel.didChange`;
/// journal writes never bump `Repository.refreshSeq`.
struct JournalSheet: View {
    let day: String
    @Environment(\.dismiss) private var dismiss

    init(day: String) { self.day = day }

    var body: some View {
        NavigationStack {
            BaselineScreen(title: "Journal", titleMode: .inline, subtitle: JournalDay.label(key: day)) {
                JournalDayHabits(day: day)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
