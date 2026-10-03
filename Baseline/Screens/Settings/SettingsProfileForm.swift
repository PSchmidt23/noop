#if os(iOS)
import SwiftUI

/// The few profile fields NOOP's engine actually reads: date of birth (age), sex, weight, height and an
/// optional manual max heart rate. Writes straight to `ProfileStore`, which persists each change. The
/// two segmented choices (sex, units) are flat in-card `BaselineSegmentedPicker`s, like every picker
/// inside content. `ProfileStore` seeds a 30-year-old male when nothing was ever stored, so the form
/// also keeps `BaselineReadouts.ProfileSet` (`baseline.profileSet`): false until a date of birth or sex
/// is changed here, or the ones shown are confirmed with "Use these". Until then the "About you" card
/// says so and the fitness estimate (Progress' Fitness card) asks for the profile instead of using the
/// seeded values.
struct SettingsProfileForm: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(BaselineReadouts.ProfileSet.key) private var profileSet = false
    /// `baseline.bodySet` (`BodySet`): height and weight entered or confirmed. Until then the Calories card
    /// says which seeded values it used ("Using 178 cm · 75 kg") and links here.
    @AppStorage(BodySet.key) private var bodySet = false

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private static let sexes: [(key: String, label: String)] = [
        ("male", "Male"), ("female", "Female"), ("nonbinary", "Other")
    ]
    private static let sexKeys = sexes.map(\.key)
    private static func sexLabel(_ key: String) -> String {
        sexes.first { $0.key == key }?.label ?? key
    }
    private static let unitKeys = [UnitSystem.metric.rawValue, UnitSystem.imperial.rawValue]
    private static func unitLabel(_ raw: String) -> String {
        raw == UnitSystem.imperial.rawValue ? "Imperial" : "Metric"
    }

    var body: some View {
        BaselineScreen(title: "Profile") {
            Text("Used for heart-rate zones, calorie estimates and your max heart rate. Stays on this iPhone.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            BaselineCard(title: "About you") {
                DatePicker(selection: $profile.dateOfBirth,
                           in: ProfileStore.dateOfBirthRange,
                           displayedComponents: .date) {
                    SettingsFieldLabel(title: "Date of birth", value: profileSet ? "\(profile.age) yrs" : "Not set")
                }
                .tint(BaselineTheme.accent)
                SettingsDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sex").font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    BaselineSegmentedPicker(options: Self.sexKeys, selection: $profile.sex,
                                            label: Self.sexLabel,
                                            accessibilityLabel: { "Sex: \(Self.sexLabel($0))" },
                                            style: .flat)
                }
                if !profileSet {
                    SettingsDivider()
                    Text("Not entered yet. Pick your date of birth and sex, or keep the ones shown; your estimated VO2 max and fitness age wait for them.")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    BaselineCTA(title: "Use these", prominent: false) { profileSet = true }
                }
            }
            // The bindings write `ProfileStore` directly, so there is no save point: a change to either
            // field is the entry. `onChange` never fires for the store's own seeded values.
            .onChange(of: profile.dateOfBirth) { _, _ in profileSet = true }
            .onChange(of: profile.sex) { _, _ in profileSet = true }

            BaselineCard(title: "Body") {
                BaselineSegmentedPicker(options: Self.unitKeys, selection: $unitSystemRaw,
                                        label: Self.unitLabel,
                                        accessibilityLabel: { "Units: \(Self.unitLabel($0))" },
                                        style: .flat)
                SettingsDivider()
                Stepper(value: $profile.weightKg, in: 30...250, step: 0.5) {
                    SettingsFieldLabel(title: "Weight",
                                       value: UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem))
                }
                SettingsDivider()
                Stepper(value: $profile.heightCm, in: 120...230, step: 1) {
                    SettingsFieldLabel(title: "Height",
                                       value: UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem))
                }
                if !bodySet {
                    SettingsDivider()
                    Text("Not entered yet. Set your weight and height, or keep the ones shown; resting calories use them.")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    BaselineCTA(title: "Use these", prominent: false) { bodySet = true }
                        .accessibilityIdentifier("settings-body-use-these")
                }
            }
            // Same rule as "About you": a change to either stepper is the entry.
            .onChange(of: profile.weightKg) { _, _ in bodySet = true }
            .onChange(of: profile.heightCm) { _, _ in bodySet = true }

            BaselineCard(title: "Max heart rate") {
                Text("Sets the top of your effort scale, your zones and the intensity-minute lines.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                Toggle(isOn: manualMaxHR) {
                    SettingsFieldLabel(title: "Set manually", value: nil)
                }
                .tint(BaselineTheme.accent)
                SettingsDivider()
                if profile.hrMaxOverride > 0 {
                    Stepper(value: $profile.hrMaxOverride, in: 100...230) {
                        SettingsFieldLabel(title: "Max HR", value: "\(profile.hrMaxOverride) bpm")
                    }
                } else {
                    SettingsFieldLabel(title: "Estimated from your age", value: estimatedMaxHR)
                }
            }
        }
        .tint(BaselineTheme.accent)
    }

    /// The "Estimated from your age" value, through the gate Home's Intensity card reads
    /// (`TodayDetail.intensityProfile`): the estimate once a date of birth exists, else
    /// `estimatePending`, so this row cannot quote an age the "About you" card says is not set.
    private var estimatedMaxHR: String {
        TodayDetail.intensityProfile(profile, entered: profileSet).map { "\($0.hrMax) bpm" } ?? Self.estimatePending
    }

    /// The "Estimated from your age" value while there is no date of birth to estimate from.
    static let estimatePending = "Needs your date of birth"

    /// On: seed the override with today's estimate so the stepper starts from a sensible number.
    /// Off: clear it (0 means "estimate from age").
    private var manualMaxHR: Binding<Bool> {
        Binding(get: { profile.hrMaxOverride > 0 },
                set: { on in profile.hrMaxOverride = on ? profile.hrMax : 0 })
    }
}

/// Title on the left, the current value on the right. Used as the label of pickers and steppers.
struct SettingsFieldLabel: View {
    let title: String
    let value: String?
    var body: some View {
        HStack {
            Text(title).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}
#endif
