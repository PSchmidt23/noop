#if os(iOS)
import SwiftUI

/// Settings › Profile (third card): the weekly Intensity-minutes goal Home's card and the detail count
/// against (`IntensityMinutes.goal()`), bound straight to its UserDefaults key
/// (`IntensityMinutes.goalKey`) so the readout reads the same number with no model in between. One
/// stepper over the engine's range and step, one line on what a minute is, and one line on where the
/// heart-rate thresholds come from: the max heart rate in the Profile card above (the override, else the
/// age estimate), the two %HRR cut-offs read from `IntensityMinutes.Thresholds` so this card and the
/// detail's basis line can never disagree. The resting-HR side of the reserve is a nightly reading, not
/// a setting, so it is not repeated here. Which max heart rate (if any) is resolved by the one gate Home
/// and the detail read, `TodayDetail.intensityProfile(_:entered:)`: until a date of birth or an override
/// is set it is nil and the card says what it is waiting for, never the seeded 30-year-old's estimate
/// the Profile card above has just called "not set".
struct SettingsIntensityGoalCard: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(IntensityMinutes.goalKey) private var goal = IntensityMinutes.goalDefault
    /// Settings › Profile's "entered" flag (`baseline.profileSet`), the gate's other half.
    @AppStorage(BaselineReadouts.ProfileSet.key) private var profileSet = false

    /// The max heart rate the Intensity classifier will use, nil until the profile may be used.
    private var scoredHRmax: Int? { TodayDetail.intensityProfile(profile, entered: profileSet)?.hrMax }

    var body: some View {
        BaselineCard(title: "Intensity goal") {
            Stepper(value: $goal, in: IntensityMinutes.goalRange, step: IntensityMinutes.goalStep) {
                SettingsFieldLabel(title: "Weekly goal", value: Self.goalText(goal))
            }
            .accessibilityValue(Self.goalText(goal))
            Text(Self.goalLine)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsDivider()
            HStack(spacing: 14) {
                SettingsIconTile(icon: "heart")
                Text(Self.basisLine(hrMax: scoredHRmax, manual: profile.hrMaxOverride > 0))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
        .tint(BaselineTheme.accent)
        // A value outside the range (an older build, a hand-edited plist) snaps back to what the readout
        // would clamp it to, so the stepper and the card agree.
        .onAppear {
            let stored = IntensityMinutes.goal()
            if stored != goal { goal = stored }
        }
    }

    /// "150 min".
    static func goalText(_ goal: Int) -> String { "\(goal) min" }

    /// What the goal counts, said once: the credited total, vigorous already doubled.
    static let goalLine = "Weekly minutes of moderate activity; vigorous minutes count double."

    /// The basis line as drawn: `hrMax` is the classifier's max heart rate
    /// (`TodayDetail.intensityProfile(_:entered:)?.hrMax`), nil while the profile has neither a date of
    /// birth nor an override, when the card names what it waits for instead of quoting a number.
    static func basisLine(hrMax: Int?, manual: Bool) -> String {
        guard let hrMax else { return basisPending }
        return basisText(hrMax: hrMax, manual: manual)
    }

    /// No date of birth and no override: the Profile card above says "not set", so no bpm is quoted.
    static let basisPending = "Minutes are scored once a date of birth or a max heart rate is set above."

    /// Where the moderate / vigorous lines sit and which max heart rate they use: the cut-offs from the
    /// engine's constants, the max from Profile (manual override or the age estimate).
    static func basisText(hrMax: Int, manual: Bool) -> String {
        let moderate = Int(IntensityMinutes.Thresholds.moderatePctHRR)
        let vigorous = Int(IntensityMinutes.Thresholds.vigorousPctHRR)
        let source = manual ? "set manually" : "estimated from your age"
        return "Moderate from \(moderate) % and vigorous from \(vigorous) % of your heart-rate reserve, against the max heart rate in Profile (\(hrMax) bpm, \(source))."
    }
}
#endif
