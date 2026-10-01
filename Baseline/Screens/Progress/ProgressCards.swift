#if os(iOS)
import SwiftUI
import StrandAnalytics

// MARK: - Sentence row

/// The hero of every Progress card: a 6pt dot carrying the judgement and the sentence in plain text.
/// The sentence is never coloured; it wraps to as many lines as it needs at large type.
struct ProgressSentence: View {
    let text: String
    let tone: ProgressCopy.Tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(ProgressToneDot.color(tone)).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(BaselineTheme.headline)
                .foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One mapping from a judgement to its dot colour (the sentence row and the timing grid share it).
enum ProgressToneDot {
    static func color(_ tone: ProgressCopy.Tone) -> Color {
        switch tone {
        case .improving: return BaselineTheme.good
        case .worsening: return BaselineTheme.watch
        case .steady, .none: return BaselineTheme.textTertiary
        }
    }
}

/// Header row shared by the Progress cards: 8pt colour dot + title, trailing caption. The title is a
/// plain `Text` on its own (not a combined element): "HRV baseline" is the UI tests' first-card anchor.
private struct ProgressCardHeader: View {
    let title: String
    let color: Color
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Text(trailing).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - HRV / resting HR

/// One baseline over the horizon: the sentence, then / now cells and the trajectory. No footnote: what
/// the line is gets said once, by the closing caption, and the noise figure lives in the sentence's
/// "about the same".
struct ProgressMetricCard: View {
    let title: String
    /// How the metric reads mid-sentence ("HRV", "resting HR").
    let noun: String
    let unit: String
    let color: Color
    let higherIsBetter: Bool
    let status: ProgressMetricStatus
    let horizon: ProgressHorizon
    let todayKey: String
    /// Y-axis snap (5 ms / 2 bpm).
    let step: Double

    private var sentence: String {
        ProgressCopy.sentence(noun: noun, unit: unit, status: status, horizon: horizon)
    }

    private var window: [ProgressPoint] {
        ProgressMetric.window(status, todayKey: todayKey, horizon: horizon)
    }

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressCardHeader(title: title, color: color,
                                   trailing: higherIsBetter ? "higher is better" : "lower is better")
                ProgressSentence(text: sentence, tone: ProgressCopy.tone(status: status, higherIsBetter: higherIsBetter))
                cells
                chart
            }
        }
    }

    @ViewBuilder private var cells: some View {
        switch status {
        case .ready(let c, _, let asOfDay):
            HStack(spacing: 12) {
                StatCell(label: ProgressCopy.thenLabel(c), value: TrendsFormat.whole(c.then.baseline), unit: unit)
                StatCell(label: ProgressCopy.nowLabel(c, asOfDay: asOfDay), value: TrendsFormat.whole(c.now.baseline),
                         unit: unit, color: color)
            }
        case .settling(_, _, let points), .paused(_, let points):
            if let last = points.last {
                StatCell(label: ProgressCopy.nowLabel(day: last.day), value: TrendsFormat.whole(last.baseline),
                         unit: unit, color: color)
            }
        case .calibrating, .empty:
            EmptyView()
        }
    }

    @ViewBuilder private var chart: some View {
        let w = window
        if w.count >= 2 {
            ProgressTrajectoryChart(points: w, color: color,
                                    yDomain: ProgressMetric.yDomain(window: w, step: step),
                                    then: status.comparison?.then, now: status.comparison?.now,
                                    spansOverAYear: ProgressMetric.spansOverAYear(w),
                                    sentence: sentence)
        }
    }
}

// MARK: - Sleep (how much, and how regular)

/// Sleep duration (the 30-night average then and now) and, under a hairline, bed / wake timing with its
/// spread. The regularity judgement is the 6pt dot before "Timing"; its sentence is the grid's
/// accessibility label, so VoiceOver hears the reading the dot stands for.
struct ProgressSleepCard: View {
    let duration: ProgressSleep.Duration
    let regularity: ProgressSleep.Regularity
    let horizon: ProgressHorizon

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressCardHeader(title: "Sleep", color: BaselineTheme.sleep, trailing: "30-night average")
                ProgressSentence(text: ProgressCopy.sleepSentence(duration, horizon: horizon),
                                 tone: ProgressCopy.sleepTone(duration))
                durationCells
                let rows = timingRows
                if !rows.isEmpty {
                    Divider().overlay(BaselineTheme.hairline)
                    timing(rows)
                }
            }
        }
    }

    @ViewBuilder private var durationCells: some View {
        switch duration {
        case .ready(let now, let then, _, _):
            HStack(spacing: 12) {
                StatCell(label: ProgressCopy.sleepThenLabel(then), value: BaselineReadouts.durationText(minutes: then.avgMin))
                StatCell(label: ProgressCopy.sleepNowLabel(nights: now.nights), value: BaselineReadouts.durationText(minutes: now.avgMin),
                         color: BaselineTheme.sleep)
            }
        case .nowOnly(let avg, let nights, _):
            StatCell(label: ProgressCopy.sleepNowLabel(nights: nights), value: BaselineReadouts.durationText(minutes: avg),
                     color: BaselineTheme.sleep)
        case .building, .none:
            EmptyView()
        }
    }

    /// "Timing" with the regularity dot, then the bed / wake grid. Label column beside the clock while
    /// both fit on one line (sized to its widest label, so "Bedtime" never breaks mid-word at larger
    /// type; the "was …" line shares the clock's column); once the clock no longer fits beside the
    /// label, the label moves above it.
    private func timing(_ rows: [TimingRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(ProgressToneDot.color(ProgressCopy.timingTone(regularity)))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text("Timing").font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
            }
            ViewThatFits(in: .horizontal) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(rows) { row in
                        GridRow {
                            label(row)
                            values(row)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            label(row)
                            values(row)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProgressCopy.timingSentence(regularity, horizon: horizon))
        .accessibilityValue(rows.map(\.spoken).joined(separator: " "))
    }

    /// Bedtime then wake, each with its spread and, over a comparison, the earlier window's figures.
    private var timingRows: [TimingRow] {
        switch regularity {
        case .ready(let now, let then, _):
            return [
                TimingRow(label: "Bedtime", mean: now.bedMeanSec, spread: now.bedSpreadMin,
                          wasMean: then.bedMeanSec, wasSpread: then.bedSpreadMin),
                TimingRow(label: "Wake", mean: now.wakeMeanSec, spread: now.wakeSpreadMin,
                          wasMean: then.wakeMeanSec, wasSpread: then.wakeSpreadMin),
            ]
        case .nowOnly(let now, _):
            return [
                TimingRow(label: "Bedtime", mean: now.bedMeanSec, spread: now.bedSpreadMin,
                          wasMean: nil, wasSpread: nil),
                TimingRow(label: "Wake", mean: now.wakeMeanSec, spread: now.wakeSpreadMin,
                          wasMean: nil, wasSpread: nil),
            ]
        case .building, .noTimedNights:
            return []
        }
    }

    private func label(_ row: TimingRow) -> some View {
        Text(row.label)
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textTertiary)
    }

    /// The clock with its spread and, when there is a comparison, the "was …" line directly beneath it.
    private func values(_ row: TimingRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.value)
                .font(BaselineTheme.stat)
                .monospacedDigit()
                .foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let was = row.was {
                Text(was)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct TimingRow: Identifiable {
        let label: String
        let mean: Int
        let spread: Double
        let wasMean: Int?
        let wasSpread: Double?

        var id: String { label }
        var value: String { ProgressCopy.timingValue(meanSec: mean, spreadMin: spread) }
        var was: String? {
            guard let wasMean, let wasSpread else { return nil }
            return ProgressCopy.timingWas(meanSec: wasMean, spreadMin: wasSpread)
        }
        var spoken: String {
            ProgressCopy.timingSpoken(label: label, meanSec: mean, spreadMin: spread,
                                      wasMeanSec: wasMean, wasSpreadMin: wasSpread)
        }
    }
}
#endif
