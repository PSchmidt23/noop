#if os(iOS)
import SwiftUI

/// How far a wearable's reading of a metric can be trusted, from the cited review in
/// `Baseline/Research/METRIC_ACCURACY.md` (its machine-readable table, keyed by `metric_key`). The tier
/// and caveat are copied from that table verbatim; change them there first. The one place a screen
/// reads accuracy from, so two cards cannot call one metric two things.
struct MetricAccuracy: Identifiable, Equatable {
    enum Tier: String, CaseIterable {
        case high, medium, low

        /// "High accuracy" / "Medium accuracy" / "Low accuracy" (the badge's text).
        var label: String { rawValue.capitalized + " accuracy" }

        /// The badge's dot: good for High, the accent for Medium, watch for Low. Text is always ink.
        var color: Color {
            switch self {
            case .high: return BaselineTheme.good
            case .medium: return BaselineTheme.accent
            case .low: return BaselineTheme.watch
            }
        }
    }

    /// `metric_key` in the literature table ("hrv", "restingHr", "sleepDuration", …).
    let key: String
    /// The metric's name in Baseline's vocabulary ("HRV", "Resting HR", "Sleep timing", …).
    let name: String
    let tier: Tier
    /// The table's one-line caveat, the popover's text.
    let caveat: String

    var id: String { key }

    /// The table, in the literature's order.
    static let all: [MetricAccuracy] = [
        MetricAccuracy(key: "hrv", name: "HRV", tier: .high,
                       caveat: "Trend against your own 30-night band; single nights are noisy and absolute ms differ between devices."),
        MetricAccuracy(key: "restingHr", name: "Resting HR", tier: .high,
                       caveat: "Nightly value within about 1 bpm of ECG; compare to your baseline, not to other people."),
        MetricAccuracy(key: "sleepDuration", name: "Sleep duration", tier: .medium,
                       caveat: "Within about 30 min of lab sleep; wake inside the night is under-counted."),
        MetricAccuracy(key: "sleepTiming", name: "Sleep timing", tier: .medium,
                       caveat: "Bed and wake times land within 10–15 min; auto-detection runs a little late."),
        MetricAccuracy(key: "sleepRegularity", name: "Sleep regularity", tier: .high,
                       caveat: "Built on sleep/wake only, the part wearables get right; strongest health evidence of any sleep metric."),
        MetricAccuracy(key: "sleepStages", name: "Sleep stages", tier: .low,
                       caveat: "Deep and REM misclassified 30–50% of the time; a visual, not a goal."),
        MetricAccuracy(key: "steps", name: "Steps", tier: .medium,
                       caveat: "Reliable as a self-consistent trend; strap placement and slow walking cost accuracy."),
        MetricAccuracy(key: "calories", name: "Calories", tier: .low,
                       caveat: "No consumer device within 20% of calorimetry; show relative to your average only."),
        MetricAccuracy(key: "vo2", name: "VO2 max", tier: .low,
                       caveat: "Resting-based estimates overestimate; typical error 4–5 mL/kg/min; show a band and direction."),
        MetricAccuracy(key: "spo2", name: "Blood oxygen", tier: .low,
                       caveat: "About 2–6% absolute error with missing readings; nightly deviation from baseline only."),
        MetricAccuracy(key: "skinTemp", name: "Skin temperature", tier: .medium,
                       caveat: "Not core temperature; meaningful only as a multi-night deviation from baseline."),
        MetricAccuracy(key: "stress", name: "Stress", tier: .low,
                       caveat: "Daytime HRV scores track heart rate, not felt stress; no independent validation."),
        MetricAccuracy(key: "readiness", name: "Readiness", tier: .low,
                       caveat: "No composite score has outcome validation; keep inputs visible and the number explainable."),
        MetricAccuracy(key: "effort", name: "Effort", tier: .medium,
                       caveat: "HR-zone load is good for running and cycling, poor for strength and wrist-flexion sports."),
    ]

    private static let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    /// The row for a `metric_key`, nil for a key the literature did not rate.
    static func lookup(_ key: String) -> MetricAccuracy? { byKey[key] }

    static subscript(_ key: String) -> MetricAccuracy? { lookup(key) }
}

/// A tiny flat pill, "High / Medium / Low accuracy", that opens a popover with the literature's caveat.
/// Sits in a card's `accessory:` slot or beside a card title. Flat (colour @ 0.10 capsule, ink text, a
/// 6pt dot in the tier colour), never glass; the popover is the system's.
///
/// ```swift
/// AccuracyBadge(metric: "hrv")                                       // from the table
/// AccuracyBadge(tier: .low, caveat: "…", name: "Calories")           // explicit
/// ```
struct AccuracyBadge: View {
    let tier: MetricAccuracy.Tier
    /// The popover's text. Without one the badge is a plain pill with no popover.
    var caveat: String? = nil
    /// Names the metric in the popover's title and the accessibility label ("Calories: Low accuracy").
    var name: String? = nil
    @State private var showCaveat = false

    init(tier: MetricAccuracy.Tier, caveat: String? = nil, name: String? = nil) {
        self.tier = tier
        self.caveat = caveat
        self.name = name
    }

    /// The badge for a `metric_key` in `MetricAccuracy.all`. An unrated key renders nothing.
    init?(metric key: String) {
        guard let row = MetricAccuracy.lookup(key) else { return nil }
        self.init(tier: row.tier, caveat: row.caveat, name: row.name)
    }

    var body: some View {
        if let caveat {
            Button { showCaveat = true } label: { pill }
                .buttonStyle(.plain)
                .popover(isPresented: $showCaveat, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name.map { "\($0) · \(tier.label)" } ?? tier.label)
                            .font(BaselineTheme.label).foregroundStyle(BaselineTheme.text)
                        Text(caveat)
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("From published validation studies; see Settings › About.")
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    }
                    .padding(16)
                    .frame(idealWidth: 300, maxWidth: 320)
                    .presentationCompactAdaptation(.popover)
                }
                .accessibilityLabel(accessibilityText)
                .accessibilityHint("Shows how accurate this reading is")
        } else {
            pill.accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String { name.map { "\($0): \(tier.label)" } ?? tier.label }

    private var pill: some View {
        HStack(spacing: 5) {
            Circle().fill(tier.color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(tier.label)
                .font(BaselineTheme.caption.weight(.semibold))
                .foregroundStyle(BaselineTheme.text)
                .lineLimit(1)
            if caveat != nil {
                Image(systemName: "info.circle")
                    .font(BaselineTheme.symbolSmall)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(tier.color.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
    }
}
#endif
