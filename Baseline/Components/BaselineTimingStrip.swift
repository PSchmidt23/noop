#if os(iOS)
import SwiftUI

/// Sleep timing as a horizontal strip, one 6pt row per night (newest at the bottom) over a noon-to-noon
/// 24-hour axis: the target window (`SleepWindow`) as a translucent sleep-coloured band behind every row,
/// each night's bed → wake span as a sleep-coloured capsule, and the 30-night average bed and wake as
/// dashed ticks. A night inside the window (± 30 min at both ends) is drawn solid, one outside it at
/// 0.45. Plain SwiftUI (no Swift Charts): fourteen rows at 9pt pitch, axis labels "6 PM · 12 AM · 6 AM
/// · 12 PM". ONE accessibility element with the summary sentence. Flat; inside a card.
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

    private static let rowHeight: CGFloat = 6
    private static let rowPitch: CGFloat = 9
    private static let axisHeight: CGFloat = 18
    private struct AxisTick: Identifiable {
        let minutes: Double
        let label: String
        var id: Double { minutes }
    }
    private static let axisTicks: [AxisTick] = [
        AxisTick(minutes: 360, label: "6 PM"), AxisTick(minutes: 720, label: "12 AM"),
        AxisTick(minutes: 1080, label: "6 AM"), AxisTick(minutes: 1440, label: "12 PM"),
    ]

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
            // Axis.
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(BaselineTheme.hairline).frame(height: 1)
                    ForEach(Self.axisTicks) { t in
                        let x = t.minutes / 1440 * w
                        Text(t.label)
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textTertiary)
                            .fixedSize()
                            .offset(x: t.minutes >= 1440 ? x - 40 : (t.minutes <= 0 ? x : x - 18), y: 4)
                    }
                }
            }
            .frame(height: Self.axisHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary ?? defaultSummary)
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
