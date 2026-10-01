#if os(iOS)
import SwiftUI

/// The few profile fields NOOP's engine actually reads: date of birth (age), sex, weight, height and an
/// optional manual max heart rate. Writes straight to `ProfileStore`, which persists each change. The
/// two segmented choices (sex, units) are flat in-card `BaselineSegmentedPicker`s, like every picker
/// inside content.
struct SettingsProfileForm: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

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
                    SettingsFieldLabel(title: "Date of birth", value: "\(profile.age) yrs")
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
            }

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
            }

            BaselineCard(title: "Max heart rate") {
                Text("Sets the top of your effort scale and zones.")
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
                    SettingsFieldLabel(title: "Estimated from your age", value: "\(profile.hrMax) bpm")
                }
            }
        }
        .tint(BaselineTheme.accent)
    }

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
