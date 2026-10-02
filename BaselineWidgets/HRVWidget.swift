import WidgetKit
import SwiftUI

/// Home Screen widget. Small: the HRV ring with the number, "ms", the one context line and the readiness
/// pill. Medium: the HRV ring beside Resting HR and last night's sleep. One ring only, never a triad.
struct HRVWidget: Widget {
    static let kind = "com.patrickschmidt.baseline.widgets.hrv"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BaselineWidgetProvider()) { entry in
            HRVWidgetView(entry: entry)
                .containerBackground(WidgetPalette.card, for: .widget)
                .widgetURL(BaselineDeepLink.home)
        }
        .configurationDisplayName("HRV")
        .description("Last night's HRV against your baseline, with readiness, resting HR and sleep.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HRVWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BaselineWidgetEntry

    var body: some View {
        if let snap = entry.snapshot, !snap.isEmpty {
            switch family {
            case .systemMedium: medium(snap)
            default: small(snap)
            }
        } else {
            WidgetEmptyView()
        }
    }

    // MARK: Small

    private func small(_ snap: BaselineWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HRV").font(WidgetPalette.label).foregroundStyle(WidgetPalette.textTertiary)
                Spacer()
                readinessPill(snap)
            }
            HStack(spacing: 10) {
                ring(snap, size: 64, numeral: 22)
                VStack(alignment: .leading, spacing: 2) {
                    if let b = snap.hrvBaselineMs {
                        Text("Baseline \(WidgetFormat.whole(b))")
                            .font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textTertiary)
                    }
                }
            }
            contextLine(snap.hrvDeltaText, bandPosition: snap.hrvBandPosition, higherIsBetter: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Medium

    private func medium(_ snap: BaselineWidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HRV").font(WidgetPalette.label).foregroundStyle(WidgetPalette.textTertiary)
                ring(snap, size: 76, numeral: 26)
                contextLine(snap.hrvDeltaText, bandPosition: snap.hrvBandPosition, higherIsBetter: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                readinessPill(snap)
                stat("Resting HR", value: WidgetFormat.whole(snap.rhrBpm), unit: "bpm", color: WidgetPalette.rhr,
                     caption: snap.rhrBaselineBpm.map { "Baseline \(WidgetFormat.whole($0))" })
                stat("Sleep", value: snap.sleepMinutes.map { WidgetFormat.duration(minutes: $0) } ?? "–", unit: nil,
                     color: WidgetPalette.sleep,
                     caption: snap.sleepMinutes.flatMap { WidgetFormat.sleepDelta(minutes: $0, average: snap.sleepAverageMinutes) })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Pieces

    private func ring(_ snap: BaselineWidgetSnapshot, size: CGFloat, numeral: CGFloat) -> some View {
        WidgetRing(fraction: snap.hrvRingFraction, color: WidgetPalette.hrv, lineWidth: size / 9) {
            VStack(spacing: -2) {
                Text(WidgetFormat.whole(snap.hrvMs))
                    .font(WidgetPalette.hero(numeral)).monospacedDigit().foregroundStyle(WidgetPalette.text)
                Text("ms").font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textTertiary)
            }
        }
        .frame(width: size, height: size)
    }

    /// Readiness as a pill and a label, as Home shows it: filled in the tier's colour; a quiet
    /// "Calibrating" chip while the seven-night tier has too few nights.
    @ViewBuilder
    private func readinessPill(_ snap: BaselineWidgetSnapshot) -> some View {
        if let label = snap.readinessLabel {
            Text(label)
                .font(WidgetPalette.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(WidgetPalette.named(snap.readinessColorName)))
                .lineLimit(1).minimumScaleFactor(0.8)
        } else if let n = snap.readinessCalibratingNights {
            Text("Readiness \(n)/14")
                .font(WidgetPalette.caption2)
                .foregroundStyle(WidgetPalette.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(WidgetPalette.ringTrack))
                .lineLimit(1)
        }
    }

    private func contextLine(_ text: String?, bandPosition: String?, higherIsBetter: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle().fill(WidgetPalette.tone(bandPosition: bandPosition, higherIsBetter: higherIsBetter))
                .frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text ?? "Waiting for the first night")
                .font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
    }

    private func stat(_ label: String, value: String, unit: String?, color: Color, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(WidgetPalette.stat).monospacedDigit().foregroundStyle(color)
                if let unit { Text(unit).font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textTertiary) }
            }
            if let caption {
                Text(caption).font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textTertiary).lineLimit(1)
            }
        }
    }
}
