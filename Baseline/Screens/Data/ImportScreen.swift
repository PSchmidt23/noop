#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Import: a WHOOP CSV export or an Apple Health export, one card each. The file picker,
/// the parsers and the result line are NOOP's (`AppModel.importWhoop(url:)` / `importAppleHealth(url:)`
/// publish their progress and summary); this screen only chooses the file and shows what came back.
struct ImportScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    /// The precedence Settings › Data persists, so the footer says what the tabs will show once the
    /// import lands, and names the default as such.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""

    var body: some View {
        BaselineScreen(title: "Import") {
            ImportCard(
                title: "WHOOP export",
                icon: "square.and.arrow.down",
                guidance: "Get the export at app.whoop.com under Data Management, then choose the .zip here.",
                buttonTitle: "Choose export…",
                types: [.zip],
                importing: model.isImporting(.whoop),
                busy: model.hasActiveImport,
                summary: model.whoopImportSummary,
                failed: model.whoopImportFailed,
                onPick: { model.importWhoop(url: $0) })
            ImportCard(
                title: "Apple Health export",
                icon: "heart.text.square",
                guidance: "In the Health app, open your profile and choose Export All Health Data; then choose the export.zip here. Large exports take a minute or two.",
                buttonTitle: "Choose export.zip…",
                types: [.zip, .xml],
                importing: model.isImporting(.appleHealth),
                busy: model.hasActiveImport,
                summary: model.appleHealthImportSummary,
                failed: model.appleHealthImportFailed,
                onPick: { model.importAppleHealth(url: $0) })
            Text(storedLine)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .padding(.horizontal, 4)
            Text(footer)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// The engine's merged table (`repo.days` / `repo.sleeps`) on purpose: this line counts what the
    /// store holds, which is what an import adds to, whatever the Data source setting shows elsewhere.
    private var storedLine: String {
        "\(repo.days.count) days · \(repo.sleeps.count) nights stored"
    }

    /// Where imports go, and which source a night both recorded shows, from the same resolver Compare's
    /// footnote reads (`BaselineDataSource.shownOnTabs`): the default is named once, here, where a person
    /// looks when an import did not change the numbers they expected it to.
    private var footer: String {
        "Imports land in the same local store as your strap's nights, so Trends and Progress reach back as far as the export does. \(BaselineDataSource.resolve(dataSourceRaw).shownOnTabs) Change that under Data source on the Data card. Importing the same file again changes nothing."
    }
}

/// One import source: guidance, the picker CTA (flat, in-card), a spinner while NOOP imports, and the
/// last result. The stored-history line below the cards describes the engine's merged table, which is
/// what an import adds to; what Home shows is decided by the Data source setting.
private struct ImportCard: View {
    let title: String
    let icon: String
    let guidance: String
    let buttonTitle: String
    let types: [UTType]
    let importing: Bool
    /// Any import in flight (either source): NOOP runs one at a time.
    let busy: Bool
    let summary: String?
    let failed: Bool
    var onPick: (URL) -> Void

    var body: some View {
        BaselineCard {
            HStack(spacing: 14) {
                SettingsIconTile(icon: icon)
                // The card's title ("WHOOP export") is a plain Text: the UI test's first-card anchor.
                Text(title).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                Spacer()
                if importing { ProgressView().tint(BaselineTheme.accent) }
            }
            Text(guidance)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: failed ? "exclamationmark.circle" : "checkmark.circle")
                        .font(BaselineTheme.symbolSmall)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(summary)
                        .font(BaselineTheme.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(failed ? BaselineTheme.watch : BaselineTheme.good)
            }
            BaselineCTA(title: importing ? "Importing…" : buttonTitle, systemImage: "doc", action: pick)
                .disabled(busy)
        }
    }

    /// NOOP's own picker (`UIDocumentPickerViewController` with `asCopy`) rather than `.fileImporter`:
    /// it downloads an iCloud Drive placeholder and hands over a readable local copy, where the SwiftUI
    /// importer returns a security-scoped URL that cannot be read for an undownloaded file and the
    /// import silently did nothing (NOOP #179).
    private func pick() {
        Task {
            guard let url = await DocumentPicker.importFile(types) else { return }   // cancelled
            onPick(url)
        }
    }
}
#endif
