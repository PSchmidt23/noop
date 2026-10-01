#if os(iOS)
import SwiftUI

/// The journal's patterns, built to sit inside Trends' "Habits" section (a `BaselineScreen` /
/// `LazyVStack` child, no screen wrapper of its own): the "What moves your HRV / Resting HR" card with
/// its flat outcome picker, the ranked effect rows or their empty states, and the dose-response rows at
/// its foot. Reads the outcome series through the strap-first funnel (`repo.baselineSeries`), reloads
/// on a data refresh, a data-source change in Settings, and after any journal write
/// (`JournalScreenModel.didChange`).
struct JournalPatternsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var catalog: JournalCatalogStore
    @StateObject private var model = JournalScreenModel()
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""

    init() {}

    var body: some View {
        JournalEffectsCard(model: model, label: label(for:))
            .task(id: repo.baselineReloadID(dataSourceRaw: dataSourceRaw)) { await model.loadPatterns(repo: repo) }
            .onReceive(NotificationCenter.default.publisher(for: JournalScreenModel.didChange)) { _ in
                Task { await model.reloadJournal(repo: repo) }
            }
    }

    /// Short row label for a canonical question: the user's rename, else the short form.
    private func label(for canonical: String) -> String {
        if let n = catalog.item(for: canonical)?.displayName, !n.isEmpty { return n }
        return JournalLabels.short(canonical)
    }
}
#endif
