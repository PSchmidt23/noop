#if os(iOS)
import SwiftUI

/// Settings › About (bottom): the "Sample data" card. One sentence and one toggle; on inserts
/// `BaselineSampleData`'s 60 nights under its own device ids and points the read spine at them, off
/// deletes exactly those rows and points it back at the registry's active strap. Both end in
/// `repo.refresh()`. The toggle is disabled while a write is in flight and springs back if one fails.
@MainActor
struct SettingsSampleDataCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @AppStorage(BaselineSampleData.activeKey) private var active = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        BaselineCard(title: "Sample data") {
            Text("For trying Baseline without a strap. Replaces nothing; remove any time.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $active) {
                SettingsRowLabel(icon: "sparkles", title: "Show sample data", subtitle: subtitle) {
                    if busy { ProgressView().tint(BaselineTheme.accent) }
                }
            }
            .tint(BaselineTheme.accent)
            .disabled(busy)
            .accessibilityIdentifier("sample-data-toggle")
            .accessibilityHint("Sixty nights of made-up HRV, resting HR, sleep, workouts and journal answers, stored under their own id")
            if let failure {
                Text(failure)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.watch)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: active) { was, on in
            // A failed write puts `was` back while `busy` is still set, so that re-entry is ignored;
            // `setActive` persists the value the toggle already holds, which raises no change.
            guard !busy else { return }
            apply(on, restoreTo: was)
        }
    }

    private var subtitle: String {
        if busy { return active ? "Adding 60 nights…" : "Removing…" }
        return active ? "60 made-up nights are shown on every screen" : "Off"
    }

    private func apply(_ on: Bool, restoreTo was: Bool) {
        busy = true
        failure = nil
        Task {
            let restoreId = model.deviceRegistry?.activeDeviceId ?? Repository.whoopSource
            if let error = await BaselineSampleData.setActive(on, repo: repo, restoreId: restoreId) {
                failure = "Could not \(on ? "add" : "remove") the sample data: \(error.localizedDescription)"
                active = was
            }
            busy = false
        }
    }
}
#endif
