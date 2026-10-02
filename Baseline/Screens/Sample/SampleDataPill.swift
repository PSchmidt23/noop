#if os(iOS)
import SwiftUI

/// The small flat "Sample data" pill Home shows under the day switcher while `BaselineSampleData` is on.
/// It also keeps the sample visible: NOOP's `AppModel` re-points the repository's read id at the
/// registry's active strap on every launch (and on every registry change), which hides the sample's
/// rows again, so whenever the store publishes a refresh this re-applies the sample's read id and
/// refreshes once more. `adoptActiveDeviceId` returns false once the two agree, so the loop settles.
struct SampleDataPill: View {
    @EnvironmentObject private var repo: Repository

    var body: some View {
        BaselinePill(text: "Sample data", color: BaselineTheme.textTertiary)
            .accessibilityLabel("Sample data is shown")
            .accessibilityHint("Turn it off under Settings, About")
            .task(id: repo.refreshSeq) {
                if BaselineSampleData.applyReadSpine(repo) { await repo.refresh() }
            }
    }
}
#endif
