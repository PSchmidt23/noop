#if os(iOS)
import SwiftUI

/// Thin wrapper kept for compatibility: today's habits card (last night) over the patterns view. Journal
/// is not a tab any more; Home opens `JournalSheet(day:)` and Trends embeds `JournalPatternsView()`.
/// Nothing should link here.
struct JournalScreen: View {
    /// Held in state and rolled on `.NSCalendarDayChanged`, so the card never straddles midnight.
    @State private var today = Date()

    var body: some View {
        BaselineScreen(title: "Journal") {
            JournalDayHabits(day: JournalDay.key(for: today))
            JournalPatternsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
    }
}
#endif
