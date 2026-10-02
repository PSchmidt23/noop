#if os(iOS)
import SwiftUI

/// The Sleep tab's timing card, directly under the hero: the last 14 nights as a strip against the target
/// window, the 30-night average bedtime and wake, the regularity index with a one-word label, tonight's
/// bedtime to aim for, the way to the bedtime / wake detail (`SleepTimingDetailScreen`, 7D / 4W / 1Y
/// ending on this night) and the way to the window in Settings. Everything comes from ONE readout
/// (`BaselineReadouts.sleepTiming(for:nights:window:)`, over the funnel's nights), so the strip, the
/// cells and the aim can never disagree. `AccuracyBadge(metric: "sleepTiming")` in the accessory slot.
/// Each fact once: the window's clock times appear only in the "Set window" row, the count of nights
/// inside it only in the strip's caption, the averages only in their cells.
struct SleepTimingCard: View {
    let timing: BaselineReadouts.SleepTiming

    var body: some View {
        BaselineCard(title: "Sleep timing", accessory: AccuracyBadge(metric: "sleepTiming").map { AnyView($0) }) {
            if timing.nights.isEmpty {
                SleepCardNote(text: "Bed and wake times appear once the strap records a night")
            } else {
                strip
                BaselineStatRow { cells }
                if timing.averageBedMinutes == nil || timing.regularity == nil {
                    SleepCardNote(text: calibrationText)
                }
            }
            Rectangle().fill(BaselineTheme.hairline).frame(height: 1)
            tonight
            BaselineChevronRow(text: "Bedtime and wake over time",
                               accessibilityHint: "Opens bedtime and wake over 7 days, 4 weeks and a year") {
                SleepTimingDetailScreen(day: timing.day)
            }
            BaselineChevronRow(text: "Set window \u{00B7} \(windowText)",
                               accessibilityHint: "Opens Settings, where the target window is set") { SettingsScreen() }
        }
    }

    // MARK: Strip

    @ViewBuilder private var strip: some View {
        TimingStripChart(nights: timing.nights.prefix(14).reversed(), target: timing.target,
                         averageBed: timing.averageBedMinutes, averageWake: timing.averageWakeMinutes)
        // The strip's ONE caption: how many of the drawn nights sat inside the window.
        Text("\(timing.nightsInWindow) of \(timing.nightsCounted) night\(timing.nightsCounted == 1 ? "" : "s") inside your window")
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textTertiary)
    }

    // MARK: Cells

    @ViewBuilder private var cells: some View {
        StatCell(label: "Average bedtime", value: clock(timing.averageBedMinutes))
        StatCell(label: "Average wake", value: clock(timing.averageWakeMinutes))
        StatCell(label: "Regularity",
                 value: timing.regularity.map { "\($0)" } ?? "\u{2014}",
                 unit: timing.regularity.map(SleepTimingAim.regularityLabel))
    }

    private func clock(_ minutes: Double?) -> String {
        minutes.map { BaselineReadouts.clockText(minutes: $0) } ?? "\u{2014}"
    }

    /// One line for whichever of the averages and the index is still waiting for nights.
    private var calibrationText: String {
        let averages = "\(BaselineReadouts.sleepAverageMinNights) nights"
        let regularity = "\(BaselineReadouts.regularityMinPairs + 1) nights in a row"
        switch (timing.averageBedMinutes == nil, timing.regularity == nil) {
        case (true, true): return "Averages appear after \(averages), regularity after \(regularity)"
        case (true, false): return "Averages appear after \(averages)"
        default: return "Regularity appears after \(regularity)"
        }
    }

    // MARK: Tonight

    private var aim: SleepTimingAim { SleepTimingAim.tonight(nights: timing.nights, target: timing.target) }

    private var tonight: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tonight: aim for \(BaselineReadouts.clockText(minutes: aim.minutes))")
                .font(BaselineTheme.headline)
                .foregroundStyle(BaselineTheme.text)
            Text(aim.contextText)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var windowText: String {
        "\(BaselineReadouts.clockText(minutes: Double(timing.target.bedMinutes)))\u{2013}"
            + BaselineReadouts.clockText(minutes: Double(timing.target.wakeMinutes))
    }
}

/// Tonight's bedtime to aim for, and the one-word reading of the regularity index. Pure, so
/// `SleepTimingCardTests` can pin the numbers.
struct SleepTimingAim: Equatable {
    enum Source: Equatable {
        /// The midpoint (median, round the clock) of the newest `count` bedtimes.
        case recentNights(count: Int)
        /// Too few timed nights, so the target window's bedtime.
        case target
    }

    /// Minutes after local midnight (0 ≤ m < 1440).
    let minutes: Double
    let source: Source

    /// Nights the aim reads over, and the fewest it needs before it prefers them to the target.
    static let nights = 7
    static let minNights = BaselineReadouts.sleepAverageMinNights

    /// `nights` is `SleepTiming.nights` (newest first). The midpoint is the median of the bedtimes measured
    /// from noon, so 11:50 PM and 12:10 AM sit beside each other, and the result is a bedtime that was
    /// actually kept, not an average pulled toward a one-off late night.
    static func tonight(nights: [BaselineReadouts.SleepTiming.Night], target: BaselineReadouts.SleepWindow,
                        calendar: Calendar = .current) -> SleepTimingAim {
        let recent = Array(nights.prefix(Self.nights))
        guard recent.count >= minNights else {
            return SleepTimingAim(minutes: Double(target.bedMinutes), source: .target)
        }
        let sinceNoon = recent.map { (BaselineReadouts.minutesOfDay($0.bed, calendar: calendar) + 720).truncatingRemainder(dividingBy: 1440) }
        let mid = (BaselineReadouts.median(sinceNoon) + 720).truncatingRemainder(dividingBy: 1440)
        // Whole minutes: the clock shows none finer, and a half-minute median would round in the text only.
        return SleepTimingAim(minutes: mid.rounded(), source: .recentNights(count: recent.count))
    }

    /// The caption under "Tonight: aim for …", naming where the time came from.
    var contextText: String {
        switch source {
        case .recentNights(let count):
            return "The middle of your last \(count) bedtimes"
        case .target:
            return "Your target bedtime, until \(Self.minNights) nights are recorded"
        }
    }

    /// ONE word for a 0–100 regularity index: "Steady" from 80, "Varied" from 60, "Scattered" below.
    static func regularityLabel(_ index: Int) -> String {
        if index >= 80 { return "Steady" }
        if index >= 60 { return "Varied" }
        return "Scattered"
    }
}
#endif
