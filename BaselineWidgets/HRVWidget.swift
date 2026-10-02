import WidgetKit
import SwiftUI

/// Home Screen widget. Small: the Readiness pill Home leads with ("Readiness 72 · Good"), then the HRV
/// ring with the number, "ms", the one context line. Medium: the HRV ring beside Readiness, Resting HR
/// and last night's sleep. One ring only, never a triad; Readiness is a number and a word, never a ring.
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
            // Home's order: Readiness first, then the HRV ring with its name and baseline beside it.
            readinessPill(snap)
            HStack(spacing: 10) {
                ring(snap, size: 64, numeral: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HRV").font(WidgetPalette.label).foregroundStyle(WidgetPalette.textTertiary)
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
                readinessStat(snap)
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

    /// Readiness as Home's number and word under their noun, one filled pill in the tone's colour
    /// ("Readiness 72 · Good", the lock screen's and the morning summary's line); a quiet "Readiness 2/4"
    /// chip while the score is still calibrating; a quiet "Readiness –" while it is stale or missing (the
    /// HRV line below already says what is being waited for). Never the seven-night HRV tier.
    @ViewBuilder
    private func readinessPill(_ snap: BaselineWidgetSnapshot) -> some View {
        if let score = snap.readinessScore, let label = snap.readinessToneLabel {
            Text("Readiness \(WidgetFormat.whole(score)) · \(label)")
                .font(WidgetPalette.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(WidgetPalette.named(snap.readinessToneName)))
                .lineLimit(1).minimumScaleFactor(0.85)
                .accessibilityLabel("Readiness \(WidgetFormat.whole(score)) of 100, \(label)")
        } else if let n = snap.readinessNightsSoFar, let seed = snap.readinessSeedNights {
            quietChip("Readiness \(n)/\(seed)")
        } else {
            quietChip("Readiness –")
        }
    }

    private func quietChip(_ text: String) -> some View {
        Text(text)
            .font(WidgetPalette.caption2)
            .foregroundStyle(WidgetPalette.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(WidgetPalette.ringTrack))
            .lineLimit(1)
    }

    /// The medium family's Readiness row, shaped like the stats under it: the "Readiness" label, the
    /// numeral in ink beside the tone's pill (Home's `ReadinessBar` without the track); the calibrating
    /// count in Home's words; "–" while there is no score.
    private func readinessStat(_ snap: BaselineWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Readiness").font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textTertiary)
            if let score = snap.readinessScore, let label = snap.readinessToneLabel {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(WidgetFormat.whole(score)).font(WidgetPalette.stat).monospacedDigit().foregroundStyle(WidgetPalette.text)
                    Text(label)
                        .font(WidgetPalette.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.onAccent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(WidgetPalette.named(snap.readinessToneName)))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Readiness \(WidgetFormat.whole(score)) of 100, \(label)")
            } else if let n = snap.readinessNightsSoFar, let seed = snap.readinessSeedNights {
                Text("After \(seed) nights · \(n) so far")
                    .font(WidgetPalette.caption2).foregroundStyle(WidgetPalette.textSecondary).lineLimit(1)
            } else {
                Text("–").font(WidgetPalette.stat).foregroundStyle(WidgetPalette.textTertiary)
            }
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
