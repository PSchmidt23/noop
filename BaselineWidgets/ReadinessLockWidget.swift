import WidgetKit
import SwiftUI

/// Lock Screen accessories. Circular: the HRV ring with the number. Rectangular: the Readiness score and
/// its tone word, as Home's card leads ("Readiness 72 · Good"), over HRV and Resting HR. Rendered
/// `.vibrant` by the system, so these use `.primary` / `.secondary` only, never a tint (a colour handed
/// to the lock screen lands as an arbitrary grey).
struct ReadinessLockWidget: Widget {
    static let kind = "com.patrickschmidt.baseline.widgets.readiness"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BaselineWidgetProvider()) { entry in
            ReadinessLockView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(BaselineDeepLink.home)
        }
        .configurationDisplayName("Readiness")
        .description("Readiness, HRV and resting HR at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct ReadinessLockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BaselineWidgetEntry

    var body: some View {
        if let snap = entry.snapshot, !snap.isEmpty {
            switch family {
            case .accessoryRectangular: rectangular(snap)
            default: circular(snap)
            }
        } else {
            switch family {
            case .accessoryRectangular: WidgetEmptyView(compact: true)
            default:
                WidgetRing(fraction: nil, color: .primary, lineWidth: 5) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 14, weight: .medium, design: .rounded))
                }
            }
        }
    }

    private func circular(_ snap: BaselineWidgetSnapshot) -> some View {
        WidgetRing(fraction: snap.hrvRingFraction, color: .primary, lineWidth: 5) {
            VStack(spacing: -3) {
                Text(WidgetFormat.whole(snap.hrvMs))
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("ms").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("HRV \(WidgetFormat.whole(snap.hrvMs)) milliseconds")
    }

    private func rectangular(_ snap: BaselineWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill").font(.system(size: 6))
                Text(readinessText(snap)).font(.system(.headline, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                cell("HRV", value: WidgetFormat.whole(snap.hrvMs), unit: "ms")
                cell("Resting HR", value: WidgetFormat.whole(snap.rhrBpm), unit: "bpm")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Home's number and word under their noun ("Readiness 72 · Good", the morning summary's line too);
    /// "Readiness · 2 of 4 nights" while the score is calibrating; "Readiness · –" when it is stale or
    /// missing, never the seven-night HRV tier under the same word.
    private func readinessText(_ snap: BaselineWidgetSnapshot) -> String {
        if let score = snap.readinessScore, let label = snap.readinessToneLabel {
            return "Readiness \(WidgetFormat.whole(score)) · \(label)"
        }
        if let n = snap.readinessNightsSoFar, let seed = snap.readinessSeedNights { return "Readiness · \(n) of \(seed) nights" }
        return "Readiness · –"
    }

    private func cell(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(unit).font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
