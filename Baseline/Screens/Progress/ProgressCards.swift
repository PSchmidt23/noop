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
            Circle().fill(dotColor).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(BaselineTheme.headline)
                .foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dotColor: Color {
        switch tone {
        case .improving: return BaselineTheme.good
        case .worsening: return BaselineTheme.watch
        case .steady, .none: return BaselineTheme.textTertiary
        }
    }
}

/// Header row shared by the Progress cards: colour dot + title, trailing caption.
private struct ProgressCardHeader: View {
    let title: String
    let color: Color
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
            }
            Spacer()
            Text(trailing).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressFootnote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - HRV / resting HR

/// One baseline over the horizon: the sentence, then / now cells, the trajectory and a footnote.
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
                if let footnote = ProgressCopy.footnote(unit: unit, status: status) {
                    ProgressFootnote(text: footnote)
                }
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

// MARK: - Sleep (how much)

struct ProgressSleepCard: View {
    let duration: ProgressSleep.Duration
    let horizon: ProgressHorizon

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressCardHeader(title: "Sleep", color: BaselineTheme.sleep, trailing: "30-night average")
                ProgressSentence(text: ProgressCopy.sleepSentence(duration, horizon: horizon),
                                 tone: ProgressCopy.sleepTone(duration))
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
                if let footnote = ProgressCopy.sleepFootnote(duration) {
                    ProgressFootnote(text: footnote)
                }
            }
        }
    }
}

// MARK: - Sleep timing (how regular)

struct ProgressSleepTimingCard: View {
    let regularity: ProgressSleep.Regularity
    let horizon: ProgressHorizon

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressCardHeader(title: "Sleep timing", color: BaselineTheme.sleep, trailing: "last 30 strap nights")
                ProgressSentence(text: ProgressCopy.timingSentence(regularity, horizon: horizon),
                                 tone: ProgressCopy.timingTone(regularity))
                let rows = timingRows
                if !rows.isEmpty {
                    // Label column beside the clock while both fit on one line. The column is sized to its
                    // widest label, so "Bedtime" never breaks mid-word at larger type, and the "was …" line
                    // shares the clock's column. Once the clock no longer fits beside the label, the label
                    // moves above it instead.
                    ViewThatFits(in: .horizontal) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                            ForEach(rows) { row in
                                GridRow {
                                    label(row)
                                        .accessibilityHidden(true)
                                    values(row)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(row.spoken)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    label(row)
                                    values(row)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(row.spoken)
                            }
                        }
                    }
                }
            }
        }
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
            .font(BaselineTheme.label)
            .foregroundStyle(BaselineTheme.textSecondary)
    }

    /// The clock with its spread and, when there is a comparison, the "was …" line directly beneath it.
    private func values(_ row: TimingRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
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

// MARK: - Today row

/// One quiet caption row under Today's hero tiles: the Progress HRV sentence verbatim, pushing
/// `ProgressScreen`. Styled like `StrapStatusStrip` (caption, no card, 4pt side padding). The sentence
/// wraps to as many lines as it needs at larger type, so its comparison date is never truncated away.
struct TodayProgressRow: View {
    let sentence: String

    var body: some View {
        NavigationLink { ProgressScreen() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.accent)
                Text(sentence).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(BaselineTheme.textTertiary)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress: \(sentence)")
        .accessibilityHint("Opens Progress")
    }
}
#endif
