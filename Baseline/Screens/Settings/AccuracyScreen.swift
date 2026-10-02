#if os(iOS)
import SwiftUI

/// Settings › About › "How accurate is this?": every metric Baseline shows, grouped by the evidence tier
/// the cited review gives it (`MetricAccuracy.all`, the machine-readable table of
/// `Baseline/Research/METRIC_ACCURACY.md`), each with the table's one-line caveat and the studies behind
/// it as tappable author–year links (`AccuracyCitations`). Intensity minutes and the day's heart rate,
/// rated by the second review (`Baseline/Research/INTENSITY_MINUTES.md` §4), join the tier cards through
/// `AccuracyExtras`, their caveats read from the detail screens' own badges. One card per tier, one
/// sentence on what the tier means, each review linked once at the foot. The tiers and caveats are not
/// restated here: change the research doc, then `MetricAccuracy` / `MetricDetailSpec`, and this screen
/// follows.
struct AccuracyScreen: View {
    /// The review itself, rendered by GitHub (the fork, next to the engine map and the design notes).
    static let reviewURL = URL(string: "https://github.com/PSchmidt23/noop/blob/main/Baseline/Research/METRIC_ACCURACY.md")!
    /// The second review: the definition and evidence behind Intensity minutes and daytime heart rate.
    static let intensityReviewURL = URL(string: "https://github.com/PSchmidt23/noop/blob/main/Baseline/Research/INTENSITY_MINUTES.md")!

    var body: some View {
        BaselineScreen(title: "Accuracy") {
            Text("Every number here comes from a strap's optical heart-rate sensor and motion sensor. Published studies that compared such devices with laboratory references rate how far each reading can be trusted; the tier beside a metric is that rating. Nothing is a medical measurement.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            ForEach(MetricAccuracy.Tier.allCases, id: \.self) { tier in
                AccuracyTierCard(tier: tier)
            }

            BaselineCard(title: "The full reviews") {
                Text("Two cited reviews, every reference checked for title, authors, journal and year; the vendor documents they cite are left out of the lists above.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsDivider()
                reviewLink(Self.reviewURL, title: "Every metric",
                           subtitle: "About 1,800 words, 31 references")
                SettingsDivider()
                reviewLink(Self.intensityReviewURL, title: "Intensity minutes and heart rate",
                           subtitle: "The definition and 17 references")
            }
        }
        .tint(BaselineTheme.accent)
    }

    /// A row that opens one review on GitHub.
    private func reviewLink(_ url: URL, title: String, subtitle: String) -> some View {
        Link(destination: url) {
            SettingsRowLabel(icon: "doc.text.magnifyingglass", title: title, subtitle: subtitle) {
                Image(systemName: "arrow.up.right")
                    .font(BaselineTheme.symbolSmall)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The metrics the second review rates (`INTENSITY_MINUTES.md` §4) that `MetricAccuracy.all`, pinned to
/// `METRIC_ACCURACY.md`'s table, does not carry: Intensity minutes and the day's heart rate. Tier and
/// caveat are the ones the detail screens' badges show (`MetricDetailSpec.standard`), read from there so a
/// row here and a badge there can never disagree; a spec without an explicit rating adds no row.
enum AccuracyExtras {
    static let keys: [MetricKey] = [.intensityMinutes, .heartRate]

    static let rows: [MetricAccuracy] = keys.compactMap { key in
        let spec = MetricDetailSpec.standard(key)
        guard spec.accuracyKey == nil, let rating = spec.accuracy else { return nil }
        return MetricAccuracy(key: key.rawValue, name: spec.title, tier: rating.tier, caveat: rating.caveat)
    }

    /// Both tables in the literature's order: the metric review's rows, then the second review's.
    static var allRows: [MetricAccuracy] { MetricAccuracy.all + rows }
}

/// One tier: its label as the card title, the badge's dot as the accessory, one sentence on what the
/// tier means for how a card shows the number, then a row per metric in the literature's order.
private struct AccuracyTierCard: View {
    let tier: MetricAccuracy.Tier

    private var rows: [MetricAccuracy] { AccuracyExtras.allRows.filter { $0.tier == tier } }

    var body: some View {
        BaselineCard(title: tier.label,
                     accessory: AnyView(Circle().fill(tier.color).frame(width: 8, height: 8).accessibilityHidden(true))) {
            Text(Self.meaning(tier))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(rows) { metric in
                SettingsDivider()
                AccuracyRow(metric: metric)
            }
        }
    }

    /// What a tier means for a card: the one place the three sentences live.
    static func meaning(_ tier: MetricAccuracy.Tier) -> String {
        switch tier {
        case .high:
            return "Close to the laboratory reference. A change against your own baseline is real signal."
        case .medium:
            return "Honest as a trend against your own average, not as an exact count."
        case .low:
            return "An estimate. Shown as a direction with a caveat, or not at all; never a goal."
        }
    }
}

/// Name, the table's caveat, and the studies as links. The caveat is said here once; the badge on the
/// metric's card shows the same text in its popover, so the two can never disagree.
private struct AccuracyRow: View {
    let metric: MetricAccuracy

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.name)
                .font(BaselineTheme.body)
                .foregroundStyle(BaselineTheme.text)
            Text(metric.caveat)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let sources = AccuracyCitations.sourcesText(for: metric.key) {
                Text(sources)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metric.name), \(metric.tier.label)")
    }
}

/// The references behind each `MetricAccuracy` row, as author–year shorts with their DOI links, numbered
/// as in `METRIC_ACCURACY.md`'s reference list so a number here is the same number there. Peer-reviewed
/// work only: the review's two vendor documents (23, 24) and the preprint duplicate of 29 (30) are not
/// listed. The second review (`INTENSITY_MINUTES.md`) keeps its own list and numbering
/// (`intensityReferences`, `intensityByMetric`); its vendor pages (G1–G12, F1–F3, A1, W1–W2) and the
/// Karvonen paper (5, PMID only, no DOI) are not listed. Pure data; `AccuracyScreenTests` pins every
/// metric to at least one reference.
enum AccuracyCitations {
    struct Reference: Identifiable, Equatable {
        let number: Int
        /// "Bellenger 2021": first author and year, the link's visible text.
        let short: String
        let url: URL
        var id: Int { number }
    }

    private static func doi(_ n: Int, _ short: String, _ doi: String) -> Reference {
        Reference(number: n, short: short, url: URL(string: "https://doi.org/" + doi)!)
    }

    /// The review's reference list, by number.
    static let references: [Reference] = [
        doi(1, "Bellenger 2021", "10.3390/s21103571"),
        doi(2, "Miller 2022", "10.3390/s22166317"),
        doi(3, "Dial 2025", "10.14814/phy2.70527"),
        doi(4, "Shcherbina 2017", "10.3390/jpm7020003"),
        doi(5, "Khodr 2024", "10.1101/2024.01.04.24300784"),
        doi(6, "Miller 2020", "10.1080/02640414.2020.1797448"),
        doi(7, "Chinoy 2021", "10.1093/sleep/zsaa291"),
        doi(8, "Chinoy 2022", "10.2147/NSS.S348795"),
        doi(9, "Stone 2020", "10.2147/NSS.S270705"),
        doi(10, "Lee 2025", "10.5664/jcsm.11460"),
        doi(11, "Robbins 2024", "10.3390/s24206532"),
        doi(12, "Phillips 2017", "10.1038/s41598-017-03171-4"),
        doi(13, "Fischer 2021", "10.1093/sleep/zsab103"),
        doi(14, "Lunsford-Avery 2018", "10.1038/s41598-018-32402-5"),
        doi(15, "Windred 2024", "10.1093/sleep/zsad253"),
        doi(16, "Lujan 2021", "10.3389/fdgth.2021.721919"),
        doi(17, "Walch 2019", "10.1093/sleep/zsz180"),
        doi(18, "Svensson 2024", "10.1016/j.sleep.2024.01.020"),
        doi(19, "Evenson 2015", "10.1186/s12966-015-0314-1"),
        doi(20, "Fuller 2020", "10.2196/18694"),
        doi(21, "Molina-Garcia 2022", "10.1007/s40279-021-01639-y"),
        doi(22, "Caserman 2024", "10.2196/59459"),
        doi(25, "Pipek 2021", "10.1038/s41598-021-98453-3"),
        doi(26, "Jiang 2023", "10.1371/journal.pdig.0000296"),
        doi(27, "Mason 2022", "10.1038/s41598-022-07314-0"),
        doi(28, "Kim 2018", "10.30773/pi.2017.08.17"),
        doi(29, "Rosenbach 2025", "10.1002/smi.70125"),
        doi(31, "Doherty 2025", "10.1515/teb-2025-0001"),
    ]

    /// `metric_key` → reference numbers, in the order the review's section for that metric cites them.
    static let byMetric: [String: [Int]] = [
        "hrv": [1, 3, 5, 2],
        "restingHr": [1, 2, 3],
        "sleepDuration": [6, 7, 8, 10],
        "sleepTiming": [7, 11, 6],
        "sleepRegularity": [12, 13, 14, 15, 16],
        "sleepStages": [7, 2, 9, 17, 18],
        "steps": [19, 20],
        "calories": [4, 20],
        "vo2": [21, 22],
        "spo2": [25, 26],
        "skinTemp": [27],
        "stress": [28, 29, 31],
        "readiness": [31, 5],
        "effort": [4, 20],
    ]

    /// `INTENSITY_MINUTES.md`'s peer-reviewed references, by ITS numbers (1–17): the guidelines and the
    /// cut-offs the definition rests on, and the heart-rate validation studies behind the two tiers.
    static let intensityReferences: [Reference] = [
        doi(1, "Bull 2020", "10.1136/bjsports-2020-102955"),
        doi(2, "Piercy 2018", "10.1001/jama.2018.14854"),
        doi(4, "Garber 2011", "10.1249/MSS.0b013e318213fefb"),
        doi(8, "Ho 2022", "10.1177/20552076221124393"),
        doi(9, "Dooley 2017", "10.2196/mhealth.7043"),
        doi(10, "Reddy 2018", "10.2196/10338"),
        doi(11, "Wallen 2016", "10.1371/journal.pone.0154420"),
        doi(12, "Warner 2025", "10.1177/20552076251326225"),
        doi(13, "Boudreaux 2018", "10.1249/MSS.0000000000001471"),
        doi(14, "Bai 2018", "10.1080/02640414.2017.1412235"),
        doi(15, "Schweizer 2025", "10.2196/67110"),
        doi(16, "Briggs 2021", "10.3389/fspor.2021.766317"),
        doi(17, "Tanaka 2001", "10.1016/S0735-1097(00)01054-8"),
    ]

    /// `MetricKey.rawValue` → numbers in `intensityReferences`, in the order §4 and §5 cite them: the
    /// one study at the Karvonen cut-offs first, then minutes-level evidence, then the definition's
    /// sources for Intensity minutes; arm-versus-wrist, treadmill and resistance-exercise accuracy for
    /// heart rate.
    static let intensityByMetric: [String: [Int]] = [
        MetricKey.intensityMinutes.rawValue: [8, 16, 12, 4, 1, 17],
        MetricKey.heartRate.rawValue: [8, 15, 9, 10, 11, 13, 14],
    ]

    private static let byNumber = Dictionary(references.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
    private static let intensityByNumber = Dictionary(intensityReferences.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })

    /// The references for a metric, in citation order; empty for an unknown key. A key rated by the
    /// metric review resolves against its list, one rated by the second review against that list.
    static func sources(for key: String) -> [Reference] {
        if let cited = byMetric[key] { return cited.compactMap { byNumber[$0] } }
        return (intensityByMetric[key] ?? []).compactMap { intensityByNumber[$0] }
    }

    /// "Sources: [Bellenger 2021](https://doi.org/…) · [Dial 2025](…)" — Markdown for `Text`.
    static func sourcesMarkdown(for key: String) -> String? {
        let refs = sources(for: key)
        guard !refs.isEmpty else { return nil }
        return "Sources: " + refs.map { "[\($0.short)](\($0.url.absoluteString))" }.joined(separator: " · ")
    }

    /// The same line as an `AttributedString` with its links live; the plain shorts when the Markdown
    /// cannot be parsed (it always can; this keeps the row from vanishing if it ever cannot).
    static func sourcesText(for key: String) -> AttributedString? {
        guard let markdown = sourcesMarkdown(for: key) else { return nil }
        if let attributed = try? AttributedString(markdown: markdown) { return attributed }
        return AttributedString("Sources: " + sources(for: key).map(\.short).joined(separator: " · "))
    }
}
#endif
