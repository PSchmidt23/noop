#if os(iOS)
import SwiftUI

/// Settings › Profile (second card): the target sleep window the Sleep tab's timing card draws as
/// its strip's band and counts nights against ("N of 14 nights inside your window", each within
/// `SleepWindow.toleranceMin` of both targets). The regularity index is NOT read against it: that
/// compares consecutive nights with each other (`BaselineReadouts.sleepRegularity`), so moving the
/// window never moves the Regularity cell. Two `hourAndMinute` pickers (bedtime, wake time) bound
/// straight to the readout's UserDefaults keys (`BaselineReadouts.SleepWindow.bedKey` / `wakeKey`,
/// minutes since midnight), so the Sleep tab reads the same numbers through `SleepWindow.stored()`
/// with no model in between. The span the two times enclose is the card's one context fact, in the
/// accessory pill; the one line under the pickers (`contextText`) says what the window does.
/// Defaults 23:00 → 07:00 until a time is changed. Under them, the "Sleep goal" stepper (FRIENDS_SPEC D16:
/// `BaselineReadouts.SleepGoal`, `baseline.sleepGoalMinutes`, 5h–10h in steps of 15 min, default 7h 30m):
/// the asleep time a night must reach to count as a night at the sleep goal in Friends, bound straight to
/// its key so the upload reads the number shown here, with one line saying what it counts.
struct SettingsSleepWindowCard: View {
    @AppStorage(BaselineReadouts.SleepWindow.bedKey)
    private var bedMinutes = BaselineReadouts.SleepWindow.default.bedMinutes
    @AppStorage(BaselineReadouts.SleepWindow.wakeKey)
    private var wakeMinutes = BaselineReadouts.SleepWindow.default.wakeMinutes
    @AppStorage(BaselineReadouts.SleepGoal.key)
    private var sleepGoal = BaselineReadouts.SleepGoal.defaultMinutes

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
            Text(Self.contextText)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsDivider()
            HStack(spacing: 14) {
                SettingsIconTile(icon: "moon.zzz")
                Stepper(value: $sleepGoal, in: BaselineReadouts.SleepGoal.range, step: BaselineReadouts.SleepGoal.step) {
                    SettingsFieldLabel(title: "Sleep goal", value: BaselineReadouts.SleepGoal.text(sleepGoal))
                }
                .accessibilityValue(Self.sleepGoalSpoken(sleepGoal))
                .accessibilityIdentifier("settings-sleep-goal")
            }
            .padding(.vertical, 4)
            Text(Self.sleepGoalLine)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(BaselineTheme.accent)
        // A goal outside the range or off the grid (a hand-edited plist) snaps to what the upload reads.
        .onAppear {
            let stored = BaselineReadouts.SleepGoal.minutes()
            if stored != sleepGoal { sleepGoal = stored }
        }
    }

    /// What the goal counts, said once: Friends' "Nights at sleep goal" (asleep time, not time in bed).
    static let sleepGoalLine = "Friends counts a night at your sleep goal when you were asleep at least this long. Only whether you reached it is shared."

    /// "7 hours 30 minutes" for VoiceOver.
    static func sleepGoalSpoken(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let hours = "\(h) hour\(h == 1 ? "" : "s")"
        return m == 0 ? hours : "\(hours) \(m) minutes"
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

    /// What the window drives, with the tolerance read from the readout so the two cannot drift apart.
    /// It names the count, not regularity: the index is window-independent.
    static var contextText: String {
        "The Sleep tab counts the nights that land inside this window (\u{00B1} \(BaselineReadouts.SleepWindow.toleranceMin) min)."
    }

    /// "8h" / "7h 30m" for the window's span; "0h" when both times match (no window to measure against).
    static func spanText(_ spanMinutes: Int) -> String {
        let h = spanMinutes / 60, m = spanMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
#endif
