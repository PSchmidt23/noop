#if os(iOS)
import SwiftUI

/// Settings › Profile › "Activity goals": the daily step goal Home's Steps card, the Steps detail and
/// Trends count against, bound straight to its UserDefaults key (`ActivityGoals.stepKey`,
/// `baseline.stepGoal`) so the cards read the same number with no model in between. One stepper (3,000
/// to 30,000 in steps of 500, default 8,000; a fixed target that never adjusts itself), one line on where
/// the default comes from, and a row into the weekly Intensity goal (`SettingsIntensityGoalCard`, its own
/// page under the same title), so both activity goals sit behind one card.
struct SettingsActivityGoalsCard: View {
    @AppStorage(ActivityGoals.stepKey) private var stepGoal = ActivityGoals.stepDefault
    @AppStorage(IntensityMinutes.goalKey) private var intensityGoal = IntensityMinutes.goalDefault

    var body: some View {
        BaselineCard(title: "Activity goals") {
            Stepper(value: $stepGoal, in: ActivityGoals.stepRange, step: ActivityGoals.stepIncrement) {
                SettingsFieldLabel(title: "Daily steps", value: Self.stepText(stepGoal))
            }
            .accessibilityValue(Self.stepText(stepGoal))
            .accessibilityIdentifier("settings-step-goal")
            Text(Self.stepLine)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsDivider()
            SettingsLinkRow(icon: "figure.run", title: "Intensity goal",
                            subtitle: Self.intensitySubtitle(intensityGoal)) {
                SettingsIntensityGoalScreen()
            }
        }
        .tint(BaselineTheme.accent)
        // A value outside the range (an older build, a hand-edited plist) snaps back to what the readout
        // would clamp it to, so the stepper and the cards agree.
        .onAppear {
            let stored = ActivityGoals.stepGoal()
            if stored != stepGoal { stepGoal = stored }
        }
    }

    /// "8,000 steps".
    static func stepText(_ goal: Int) -> String { BaselineReadouts.stepsText(goal) + " steps" }

    /// Why 8,000 by default, said once: where the measured benefit levels off (Paluch 2022, Lancet
    /// Public Health; Baseline/Research/ACTIVITY_METRICS.md).
    static let stepLine = "A fixed daily target. In large studies the benefit of daily steps levels off around 6,000–8,000 a day from age 60 and 8,000–10,000 under 60."

    /// "150 min a week".
    static func intensitySubtitle(_ goal: Int) -> String { "\(goal) min a week" }
}

/// The weekly Intensity-minutes goal on its own page, pushed from "Activity goals".
struct SettingsIntensityGoalScreen: View {
    var body: some View {
        BaselineScreen(title: "Intensity goal") {
            SettingsIntensityGoalCard()
        }
    }
}
#endif
