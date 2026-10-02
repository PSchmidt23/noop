#if os(iOS)
import SwiftUI

/// Sleep timing as a horizontal strip, one 6pt row per night (newest at the bottom) over a noon-to-noon
/// 24-hour axis: the target window (`SleepWindow`) as a translucent sleep-coloured band behind every row,
/// each night's bed → wake span as a sleep-coloured capsule, and the 30-night average bed and wake as
/// dashed ticks. A night inside the window (± 30 min at both ends) is drawn solid, one outside it at
/// 0.45. Plain SwiftUI (no Swift Charts): fourteen rows at 9pt pitch, then an axis whose hour labels
/// come from `BaselineReadouts.hourText` ("6 PM · 12 AM · 6 AM · 12 PM" on a 12-hour clock, "18 · 00 ·
/// 06 · 12" on a 24-hour one, so the axis and the card's `clockText` cells always agree), take their
/// height from the caption font and sit under their ticks by their own width (two of them at
/// accessibility sizes, where four would collide). ONE accessibility element with the summary sentence.
/// Flat; inside a card.
///
/// ```swift
/// let t = BaselineReadouts.sleepTiming(for: day, nights: nights)
/// TimingStripChart(nights: t.nights.prefix(14).reversed(), target: t.target,
///                  averageBed: t.averageBedMinutes, averageWake: t.averageWakeMinutes)
/// ```
struct TimingStripChart: View {
    /// Oldest → newest (top → bottom); pass at most 14.
    let nights: [BaselineReadouts.SleepTiming.Night]
    let target: BaselineReadouts.SleepWindow
    /// Minutes after midnight (`SleepTiming.averageBedMinutes` / `averageWakeMinutes`).
    var averageBed: Double? = nil
    var averageWake: Double? = nil
    var accessibilitySummary: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let rowHeight: CGFloat = 6
    private static let rowPitch: CGFloat = 9

    /// A labelled point on the noon-to-noon axis.
    struct AxisTick: Identifiable, Equatable {
        /// 0…1 across the strip (minutes since noon ÷ 1440).
        let fraction: Double
        /// The clock minute the label names (minutes after midnight).
        let minutesOfDay: Double
        /// Whether the label survives at accessibility sizes (midnight and the trailing noon only).
        let keptAtAccessibilitySizes: Bool
        var id: Double { fraction }
    }

    /// 6 PM, midnight, 6 AM and the trailing noon.
    static let axisTicks: [AxisTick] = [
        AxisTick(fraction: 0.25, minutesOfDay: 18 * 60, keptAtAccessibilitySizes: false),
        AxisTick(fraction: 0.5, minutesOfDay: 0, keptAtAccessibilitySizes: true),
        AxisTick(fraction: 0.75, minutesOfDay: 6 * 60, keptAtAccessibilitySizes: false),
        AxisTick(fraction: 1, minutesOfDay: 12 * 60, keptAtAccessibilitySizes: true),
    ]

    /// The ticks drawn at a type size: all four, or the two that cannot collide at accessibility sizes.
    static func ticks(accessibilitySize: Bool) -> [AxisTick] {
        axisTicks.filter { !accessibilitySize || $0.keptAtAccessibilitySizes }
    }

    init<S: Sequence>(nights: S, target: BaselineReadouts.SleepWindow, averageBed: Double? = nil,
                      averageWake: Double? = nil, accessibilitySummary: String? = nil)
    where S.Element == BaselineReadouts.SleepTiming.Night {
        self.nights = Array(nights)
        self.target = target
        self.averageBed = averageBed
        self.averageWake = averageWake
        self.accessibilitySummary = accessibilitySummary
    }

    /// Minutes since noon (0…1440) of a clock minute (0…1440).
    private static func sinceNoon(_ minutesOfDay: Double) -> Double {
        (minutesOfDay + 720).truncatingRemainder(dividingBy: 1440)
    }

    private var rowsHeight: CGFloat { CGFloat(max(nights.count, 1)) * Self.rowPitch }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // Target window band, bed → wake, across every row.
                    let tb = Self.sinceNoon(Double(target.bedMinutes)) / 1440 * w
                    let tw = Self.sinceNoon(Double(target.wakeMinutes)) / 1440 * w
                    if tw > tb {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BaselineTheme.sleep.opacity(BaselineChartStyle.bandOpacity))
                            .frame(width: tw - tb, height: rowsHeight)
                            .offset(x: tb)
                    }
                    // Average bed / wake ticks.
                    ForEach(Array([averageBed, averageWake].compactMap { $0 }.enumerated()), id: \.offset) { _, m in
                        Rectangle()
                            .fill(BaselineTheme.sleep.opacity(BaselineChartStyle.baselineOpacity))
                            .frame(width: 1, height: rowsHeight)
                            .offset(x: Self.sinceNoon(m) / 1440 * w)
                    }
                    // One capsule per night.
                    ForEach(Array(nights.enumerated()), id: \.element.id) { i, n in
                        let span = BaselineReadouts.noonInterval(bed: n.bed, wake: n.wake)
                        let x0 = span.lowerBound / 1440 * w
                        let x1 = span.upperBound / 1440 * w
                        Capsule()
                            .fill(BaselineTheme.sleep.opacity(inWindow(n) ? BaselineChartStyle.barOpacity : 0.45))
                            .frame(width: max(Self.rowHeight, x1 - x0), height: Self.rowHeight)
                            .offset(x: x0, y: CGFloat(i) * Self.rowPitch)
                    }
                }
            }
            .frame(height: rowsHeight)
            axis
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary ?? defaultSummary)
    }

    // MARK: Axis

    private struct AxisLabel: Identifiable {
        let tick: AxisTick
        let text: String
        var id: Double { tick.id }
    }

    private var axisLabels: [AxisLabel] {
        Self.ticks(accessibilitySize: dynamicTypeSize.isAccessibilitySize)
            .map { AxisLabel(tick: $0, text: BaselineReadouts.hourText(minutes: $0.minutesOfDay)) }
    }

    /// The hairline and its hour labels. The label row is exactly one caption line tall (an invisible
    /// copy of the widest label sizes it, so it grows with Dynamic Type instead of overflowing a fixed
    /// frame into the caption below); each visible label is centred under its tick by its own measured
    /// width, the trailing one ending at the trailing edge, with no pixel constant anywhere.
    private var axis: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(BaselineTheme.hairline).frame(height: 1)
            Text(axisLabels.map(\.text).max(by: { $0.count < $1.count }) ?? "")
                .font(BaselineTheme.caption)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    GeometryReader { geo in
                        let w = geo.size.width
                        ForEach(axisLabels) { label in
                            let trailing = label.tick.fraction >= 1
                            Text(label.text)
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textTertiary)
                                .fixedSize()
                                .frame(width: w, alignment: trailing ? .trailing : .center)
                                .offset(x: trailing ? 0 : w * label.tick.fraction - w / 2)
                        }
                    }
                }
        }
    }

    private func inWindow(_ n: BaselineReadouts.SleepTiming.Night) -> Bool {
        let tol = Double(BaselineReadouts.SleepWindow.toleranceMin)
        return BaselineReadouts.clockDistance(BaselineReadouts.minutesOfDay(n.bed), Double(target.bedMinutes)) <= tol
            && BaselineReadouts.clockDistance(BaselineReadouts.minutesOfDay(n.wake), Double(target.wakeMinutes)) <= tol
    }

    private var defaultSummary: String {
        let inside = nights.filter(inWindow).count
        var s = "Sleep timing for the last \(nights.count) night\(nights.count == 1 ? "" : "s"): \(inside) inside your "
            + "\(BaselineReadouts.clockText(minutes: Double(target.bedMinutes))) to "
            + "\(BaselineReadouts.clockText(minutes: Double(target.wakeMinutes))) window"
        if let b = averageBed, let w = averageWake {
            s += ", average bedtime \(BaselineReadouts.clockText(minutes: b)), average wake \(BaselineReadouts.clockText(minutes: w))"
        }
        return s + "."
    }
}
#endif
