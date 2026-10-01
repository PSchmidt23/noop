#if os(iOS)
import SwiftUI

/// Settings › Export: what the CSV zip holds, how much history it will carry, and the one button. The
/// writer is NOOP's `CsvExport.run(repo:)`, which assembles the archive off the main actor and then
/// presents the system document picker (`DocumentPicker.export`) so the file lands in Files or iCloud
/// Drive; this screen only describes the file and shows what came back. The stored-history line counts
/// the engine's merged table (`repo.days` / `repo.sleeps`), which is exactly what `CsvExport` writes.
struct ExportScreen: View {
    @EnvironmentObject private var repo: Repository
    @State private var exporting = false
    @State private var outcome: (text: String, failed: Bool)?

    var body: some View {
        BaselineScreen(title: "Export") {
            BaselineCard {
                HStack(spacing: 14) {
                    SettingsIconTile(icon: "square.and.arrow.up")
                    // A plain Text: the UI test's first-card anchor.
                    Text("CSV export").font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                    Spacer()
                    if exporting { ProgressView().tint(BaselineTheme.accent) }
                }
                Text(ExportFacts.summary)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ExportFacts.files, id: \.name) { file in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(BaselineTheme.label)
                                .foregroundStyle(BaselineTheme.text)
                            Text(file.contents)
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(storedLine)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                if let outcome {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: outcome.failed ? "exclamationmark.circle" : "checkmark.circle")
                            .font(BaselineTheme.symbolSmall)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(outcome.text)
                            .font(BaselineTheme.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(outcome.failed ? BaselineTheme.watch : BaselineTheme.good)
                }
                BaselineCTA(title: exporting ? "Exporting\u{2026}" : "Export CSV\u{2026}",
                            systemImage: "square.and.arrow.up", action: export)
                    .disabled(!canExport)
            }
            Text(ExportFacts.footer)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var canExport: Bool { !exporting && repo.loaded && !repo.days.isEmpty }

    /// "412 days · Jan 2025 – Sep 2026 · 398 nights" from the published caches; nothing is read for it.
    private var storedLine: String {
        guard repo.loaded else { return "Reading your history\u{2026}" }
        guard !repo.days.isEmpty else { return "Nothing to export yet. Days appear after the first synced night." }
        return ExportFacts.storedLine(days: repo.days.count, nights: repo.sleeps.count,
                                      firstDay: repo.days.first?.day, lastDay: repo.days.last?.day)
    }

    private func export() {
        exporting = true
        outcome = nil
        Task {
            let result = await CsvExport.run(repo: repo)
            exporting = false
            switch result {
            case .cancelled:
                outcome = nil
            case .exported(let url):
                outcome = ("Saved \(url.lastPathComponent).", false)
            case .failure(let message):
                outcome = (message, true)
            }
        }
    }
}

/// What NOOP's `CsvExport` writes, in Baseline's words. Mirrors the files and columns of
/// `WhoopCsvExporter` (Packages/StrandImport); nothing here names a column the exporter does not write.
enum ExportFacts {
    struct File {
        let name: String
        let contents: String
    }

    static let summary = "A zip in WHOOP\u{2019}s export layout, so it re-imports here under Settings \u{203A} Import and into NOOP on any device. Your strap\u{2019}s nights and any WHOOP import are merged one row per day, the import winning where both recorded; a Source column marks each row \u{201C}import\u{201D} or \u{201C}noop (APPROXIMATE)\u{201D}. Apple Health rows are left out so a re-import can never mislabel them. Timestamps are UTC."

    static let files: [File] = [
        File(name: "physiological_cycles.csv",
             contents: "One row per day: resting HR, HRV, skin temperature, blood oxygen, effort on WHOOP\u{2019}s 0\u{2013}21 day scale, the engine\u{2019}s 0\u{2013}100 daily score under WHOOP\u{2019}s \u{201C}Recovery score %\u{201D} header, respiratory rate, time asleep, in bed, light, deep and REM minutes, awake minutes, sleep efficiency, and the sleep performance, consistency, need, debt, energy and average/max HR figures an import supplied."),
        File(name: "sleeps.csv",
             contents: "Every sleep, naps included: onset, wake, minutes asleep and in bed, stage minutes, efficiency."),
        File(name: "workouts.csv",
             contents: "Start, end, activity, effort on WHOOP\u{2019}s scale, energy, average and max HR, zone percentages, distance."),
        File(name: "journal_entries.csv",
             contents: "Day, question, yes/no, notes."),
        File(name: "noop_metric_series.json",
             contents: "Every stored daily series, for fidelity; an import does not read it back.")
    ]

    static let footer = "The file goes only where you save it. The .sqlite backup remains the lossless copy; this zip is the portable, spreadsheet-friendly one."

    /// "412 days · Jan 2025 – Sep 2026 · 398 nights"; the span is dropped when a day key does not parse.
    static func storedLine(days: Int, nights: Int, firstDay: String?, lastDay: String?) -> String {
        var parts = ["\(days) day\(days == 1 ? "" : "s")"]
        if let span = spanText(firstDay: firstDay, lastDay: lastDay) { parts.append(span) }
        parts.append("\(nights) night\(nights == 1 ? "" : "s")")
        return parts.joined(separator: " \u{B7} ")
    }

    /// "Jan 2025 – Sep 2026", or "Sep 2026" when both ends fall in one month.
    static func spanText(firstDay: String?, lastDay: String?) -> String? {
        guard let firstDay, let lastDay,
              let first = TrendsDayKey.date(firstDay), let last = TrendsDayKey.date(lastDay) else { return nil }
        let a = first.formatted(.dateTime.month(.abbreviated).year())
        let b = last.formatted(.dateTime.month(.abbreviated).year())
        return a == b ? a : "\(a) \u{2013} \(b)"
    }
}
#endif
