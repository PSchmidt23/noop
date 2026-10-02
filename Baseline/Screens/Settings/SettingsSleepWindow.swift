#if os(iOS)
import SwiftUI

/// Settings › Profile (second card): the sleep window Baseline measures regularity against. Two
/// `hourAndMinute` pickers (bedtime, wake time) bound straight to the readout's UserDefaults keys
/// (`BaselineReadouts.SleepWindow.bedKey` / `wakeKey`, minutes since midnight), so the Sleep tab's
/// timing card reads the same numbers through `SleepWindow.stored()` with no model in between. The
/// span the two times enclose is the card's one context fact, in the accessory pill; the one line
/// under the pickers says what the window is for. Defaults 23:00 → 07:00 until a time is changed.
struct SettingsSleepWindowCard: View {
    @AppStorage(BaselineReadouts.SleepWindow.bedKey)
    private var bedMinutes = BaselineReadouts.SleepWindow.default.bedMinutes
    @AppStorage(BaselineReadouts.SleepWindow.wakeKey)
    private var wakeMinutes = BaselineReadouts.SleepWindow.default.wakeMinutes

    /// The pickers edit a `Date`; only its hour and minute are kept (the scheduler's two converters
    /// clamp to 0…1439, the range `SleepWindow.stored` accepts).
    private var bedTime: Binding<Date> { time($bedMinutes) }
    private var wakeTime: Binding<Date> { time($wakeMinutes) }

    private var window: BaselineReadouts.SleepWindow {
        BaselineReadouts.SleepWindow(bedMinutes: bedMinutes, wakeMinutes: wakeMinutes)
    }

    var body: some View {
        BaselineCard(title: "Sleep window",
                     accessory: AnyView(BaselinePill(text: Self.spanText(window.spanMinutes), color: BaselineTheme.sleep))) {
            timeRow(icon: "bed.double", title: "Bedtime", selection: bedTime)
            SettingsDivider()
            timeRow(icon: "sunrise", title: "Wake time", selection: wakeTime)
            Text("Baseline measures regularity against this window.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(BaselineTheme.accent)
    }

    /// Icon tile and title on the left, the compact picker on the right. The picker keeps `title` as
    /// its accessibility label while its visible label is hidden.
    private func timeRow(icon: String, title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: icon)
            Text(title).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
            Spacer(minLength: 8)
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.vertical, 4)
    }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { EveningCheckInScheduler.date(minutesSinceMidnight: minutes.wrappedValue) },
                set: { minutes.wrappedValue = EveningCheckInScheduler.minutes(from: $0) })
    }

    /// "8h" / "7h 30m" for the window's span; "0h" when both times match (no window to measure against).
    static func spanText(_ spanMinutes: Int) -> String {
        let h = spanMinutes / 60, m = spanMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
#endif
