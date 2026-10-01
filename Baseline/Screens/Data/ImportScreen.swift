#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Import: a WHOOP CSV export or an Apple Health export, one card each. The file picker,
/// the parsers and the result line are NOOP's (`AppModel.importWhoop(url:)` / `importAppleHealth(url:)`
/// publish their progress and summary); this screen only chooses the file and shows what came back.
struct ImportScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository

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
            Text("Imports land in the same local store as your strap's nights, so Trends and Progress reach back as far as the export does. Importing the same file again changes nothing.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var storedLine: String {
        "\(repo.days.count) days · \(repo.sleeps.count) nights stored"
    }
}

/// One import source: guidance, the picker button, a spinner while NOOP imports, and the last result.
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
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BaselineTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(BaselineTheme.accent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 1)
                    Text(summary)
                        .font(BaselineTheme.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(failed ? BaselineTheme.watch : BaselineTheme.good)
            }
            Button(action: pick) {
                Text(importing ? "Importing…" : buttonTitle)
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BaselineTheme.accent.opacity(busy ? 0.3 : 1), in: Capsule())
            }
            .buttonStyle(.plain)
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
