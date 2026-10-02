#if os(iOS)
import SwiftUI
import UserNotifications

/// Settings: grouped cards, one idea each, under pinned glass section headers. Pushed from the gear in
/// every tab's navigation bar, so it assumes nothing about a tab: the title is "Settings" and the bar's
/// Back button takes the person to wherever they came from. Strap, Apple Health and Data push Baseline's
/// own screens over NOOP's engine (`DevicesScreen`, `AppleHealthScreen`, `ImportScreen`, `CompareScreen`,
/// `ExportScreen`); Profile is Baseline's small form over `ProfileStore`; About carries attribution, the
/// privacy policy, license and the disclaimer. Each card observes only what it needs, so the root never
/// re-renders on strap ticks.
struct SettingsScreen: View {
    var body: some View {
        BaselineScreen(title: "Settings") {
            SettingsSection(label: "Strap") { SettingsStrapCard() }
            SettingsSection(label: "Apple Health") { SettingsHealthCard() }
            SettingsSection(label: "Data") { SettingsDataCard() }
            SettingsSection(label: "Profile") { SettingsProfileCard() }
            SettingsSection(label: "Notifications") { SettingsNotificationsCard() }
            #if DEBUG
            SettingsSection(label: "Developer") { SettingsDeveloperCard() }
            #endif
            SettingsSection(label: "About") {
                SettingsAboutCard()
                // Release-safe stand-in for the DEBUG demo seed: App Review has no strap.
                SettingsSampleDataCard()
            }
        }
    }
}

// MARK: - Strap

private struct SettingsStrapCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var live: LiveState

    private var canSync: Bool { live.connected && live.bonded && !live.backfilling }

    var body: some View {
        BaselineCard {
            HStack(spacing: 10) {
                Circle()
                    .fill(live.connected ? BaselineTheme.good : BaselineTheme.inactive)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                // The "connected" UI-test anchor: a plain Text, never folded into a button.
                Text(live.connected ? "Connected" : "Not connected")
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.text)
                Spacer(minLength: 8)
                if let battery, !dynamicTypeSize.isAccessibilitySize {
                    BaselinePill(text: battery.text, color: battery.color)
                }
            }
            if let battery, dynamicTypeSize.isAccessibilitySize {
                BaselinePill(text: battery.text, color: battery.color)
            }
            Text(lastSyncLine)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
            SettingsDivider()
            SettingsLinkRow(icon: "dot.radiowaves.left.and.right", title: "Devices",
                            subtitle: "Pair, rename or forget a strap") {
                DevicesScreen()
            }
            SettingsDivider()
            Button(action: { ble.syncNow() }) {
                SettingsRowLabel(icon: "arrow.triangle.2.circlepath",
                                 title: live.backfilling ? "Syncing…" : "Sync now",
                                 subtitle: syncSubtitle) {
                    if live.backfilling { ProgressView().tint(BaselineTheme.accent) }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSync)
            .opacity(canSync || live.backfilling ? 1 : 0.5)
        }
    }

    /// Battery is the strap's own number and outlives its link, so it is only shown while the strap is
    /// the connected source. The pill's text is ink; the dot carries the level.
    private var battery: (text: String, color: Color)? {
        guard live.connected, live.activeIsWhoop, let pct = live.batteryPct else { return nil }
        let n = max(0, min(100, Int(pct.rounded())))
        let text = live.charging == true ? "Charging · \(n)%" : "\(n)%"
        let color: Color = n <= 20 ? BaselineTheme.low : (n <= 40 ? BaselineTheme.watch : BaselineTheme.good)
        return (text, color)
    }

    private var lastSyncLine: String {
        guard let ts = live.lastSyncedAt else { return "No sync yet" }
        let when = Date(timeIntervalSince1970: ts)
            .formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "Last sync \(when)"
    }

    private var syncSubtitle: String {
        if live.backfilling { return "Reading the strap's stored nights" }
        if !live.connected || !live.bonded { return "Connect a strap to sync" }
        return "Pull the strap's stored nights now"
    }
}

// MARK: - Apple Health

private struct SettingsHealthCard: View {
    @EnvironmentObject private var health: HealthKitBridge

    var body: some View {
        BaselineCard {
            SettingsLinkRow(icon: "heart.text.square", title: "Apple Health",
                            subtitle: "Reads sleep and workouts, writes back what Baseline computes",
                            badge: AppleHealthStatus.pill(for: health.auth)) {
                AppleHealthScreen()
            }
        }
    }
}

// MARK: - Data

/// Import / Compare / Export rows (unchanged: Compare is where an imported WHOOP export is checked
/// against the strap) and the data-source precedence `BaselineDataSourceSetting` persists: which
/// source a night both recorded shows on Home, Trends and Sleep. Three ways, one sentence each.
private struct SettingsDataCard: View {
    @StateObject private var dataSource = BaselineDataSourceSetting()

    var body: some View {
        BaselineCard {
            SettingsLinkRow(icon: "square.and.arrow.down", title: "Import data",
                            subtitle: "WHOOP export or Apple Health export") {
                ImportScreen()
            }
            SettingsDivider()
            SettingsLinkRow(icon: "arrow.left.arrow.right", title: "Compare sources",
                            subtitle: "Baseline vs your WHOOP export, night by night") {
                CompareScreen()
            }
            SettingsDivider()
            SettingsLinkRow(icon: "tablecells", title: "Export CSV",
                            subtitle: "Your daily table as a file") {
                ExportScreen()
            }
            SettingsDivider()
            SettingsRowLabel(icon: "arrow.triangle.branch", title: BaselineDataSourceSetting.title,
                             subtitle: "Which source a night both recorded shows") {
                EmptyView()
            }
            BaselineSegmentedPicker(options: BaselineDataSourceSetting.options,
                                    selection: $dataSource.selection,
                                    label: { $0.label },
                                    accessibilityLabel: { "\(BaselineDataSourceSetting.title): \($0.label)" },
                                    style: .flat)
            Text(dataSource.selection.subtitle)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.snappy(duration: 0.25), value: dataSource.selection)
        }
        .onAppear { dataSource.reload() }
    }
}

// MARK: - Profile

private struct SettingsProfileCard: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var body: some View {
        BaselineCard {
            SettingsLinkRow(icon: "person.crop.circle", title: "Profile", subtitle: summary) {
                SettingsProfileForm()
            }
        }
    }

    private var summary: String {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let sex: String
        switch profile.sex.lowercased() {
        case "female": sex = "Female"
        case "male":   sex = "Male"
        default:       sex = "Other"
        }
        return [
            "\(profile.age) yrs", sex,
            UnitFormatter.heightFromCentimeters(profile.heightCm, system: system),
            UnitFormatter.massFromKilograms(profile.weightKg, system: system),
            "max HR \(profile.hrMax)"
        ].joined(separator: " · ")
    }
}

// MARK: - Notifications

/// The opt-in morning summary (`MorningSummaryNotifier`) and evening check-in (`EveningCheckInScheduler`).
/// Turning either on asks for notification permission right here, at a predictable moment, through the
/// one authorization flow; a refusal leaves the toggle on (that is still what the person wants) and
/// points at iOS Settings, re-checking whenever the app comes back to the foreground. Each row carries a
/// one-line subtitle; the longer explanation is the row's accessibility hint.
private struct SettingsNotificationsCard: View {
    @AppStorage(MorningSummaryNotifier.enabledKey) private var enabled = false
    @AppStorage(EveningCheckInScheduler.enabledKey) private var eveningEnabled = false
    /// Minutes since midnight; the picker edits it through `eveningTime`.
    @AppStorage(EveningCheckInScheduler.minutesKey) private var eveningMinutes = EveningCheckInScheduler.defaultMinutes
    @State private var status: UNAuthorizationStatus?

    private var denied: Bool { (enabled || eveningEnabled) && status == .denied }

    private static let morningHint = "One notification when the first sync of the day lands: HRV, resting HR and sleep against your baseline. Never on a schedule."
    private static let eveningHint = "One reminder each evening to log tonight's habits, so the Journal can learn what moves your HRV. Opens the day's Journal."

    /// The `DatePicker` edits a `Date`; only its hour and minute are kept.
    private var eveningTime: Binding<Date> {
        Binding(get: { EveningCheckInScheduler.date(minutesSinceMidnight: eveningMinutes) },
                set: { eveningMinutes = EveningCheckInScheduler.minutes(from: $0) })
    }

    var body: some View {
        BaselineCard {
            Toggle(isOn: $enabled) {
                SettingsRowLabel(icon: "sun.max", title: "Morning summary",
                                 subtitle: "When the first sync of the day lands.") {
                    EmptyView()
                }
            }
            .tint(BaselineTheme.accent)
            .accessibilityHint(Self.morningHint)
            SettingsDivider()
            Toggle(isOn: $eveningEnabled) {
                SettingsRowLabel(icon: "moon", title: "Evening check-in",
                                 subtitle: "A reminder to log tonight's habits.") {
                    EmptyView()
                }
            }
            .tint(BaselineTheme.accent)
            .accessibilityHint(Self.eveningHint)
            if eveningEnabled {
                HStack {
                    Text("Time")
                        .font(BaselineTheme.label)
                        .foregroundStyle(BaselineTheme.textSecondary)
                    Spacer()
                    DatePicker("Evening check-in time", selection: eveningTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(BaselineTheme.accent)
                }
                .padding(.leading, 44)   // under the row's text, past the 30pt icon tile and its 14pt gap
            }
            if denied {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are turned off for Baseline in iOS Settings, so nothing can arrive.")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.watch)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Link(destination: url) {
                            Label("Open iOS Settings", systemImage: "arrow.up.forward.app")
                                .font(BaselineTheme.label)
                                .foregroundStyle(BaselineTheme.accent)
                        }
                    }
                }
            }
        }
        .task { status = await MorningSummaryNotifier.authorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { status = await MorningSummaryNotifier.authorizationStatus() }
        }
        .onChange(of: enabled) { _, on in
            if on {
                Task { status = await MorningSummaryNotifier.requestAuthorization() }
            } else {
                MorningSummaryNotifier.removeDelivered()
            }
        }
        .onChange(of: eveningEnabled) { _, on in
            if on {
                // The same ask as the morning toggle, then schedule once we know where it left us.
                Task {
                    status = await MorningSummaryNotifier.requestAuthorization()
                    await EveningCheckInScheduler.sync()
                }
            } else {
                EveningCheckInScheduler.cancel()
            }
        }
        .onChange(of: eveningMinutes) { _, _ in
            // A new time replaces the pending request (same identifier); a no-op while the toggle is off.
            Task { await EveningCheckInScheduler.sync() }
        }
    }
}

// MARK: - Developer (DEBUG only)

#if DEBUG
private struct SettingsDeveloperCard: View {
    @AppStorage("baseline.onboarded") private var onboarded = false

    var body: some View {
        BaselineCard {
            Button(action: { onboarded = false }) {
                SettingsRowLabel(icon: "arrow.counterclockwise", title: "Reset onboarding",
                                 subtitle: "Shows the welcome flow again on the next launch") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }
}
#endif

// MARK: - Shared rows

/// A `Section` whose header is the pinned glass capsule: `BaselineScreen`'s `LazyVStack(pinnedViews:
/// [.sectionHeaders])` keeps it floating over the rows that scroll beneath it. The only custom glass on
/// this screen (≤ 7 small capsules; the downgrade on a device that shows jank is `style: .flat`).
private struct SettingsSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        Section {
            content()
        } header: {
            BaselineSectionLabel(text: label, style: .glass)
        }
    }
}

struct SettingsDivider: View {
    var body: some View { Divider().overlay(BaselineTheme.hairline) }
}

/// The 30pt icon tile every Settings-style row leads with: a glyph in accent on `accent @ 0.10`,
/// radius 10 continuous. Shared by the Settings rows and the Apple Health / Import / Export / Devices
/// card headers so one tile looks the same everywhere.
struct SettingsIconTile: View {
    let icon: String
    var body: some View {
        Image(systemName: icon)
            .font(BaselineTheme.symbolAccessory.weight(.medium))
            .foregroundStyle(BaselineTheme.accent)
            .frame(width: 30, height: 30)
            .background(BaselineTheme.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon tile, title, optional subtitle, and whatever sits at the trailing edge (a pill, a chevron, a
/// spinner). The title comes first in the folded accessibility label, so a UI test's `label BEGINSWITH
/// "Devices"` resolves the row.
struct SettingsRowLabel<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    /// A status pill: trailing beside the chevron, or under the subtitle at accessibility sizes, where
    /// a pill beside a 40pt title would squeeze both ("Apple / Health", "Not s…").
    var badge: (text: String, color: Color)? = nil
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                if let subtitle {
                    Text(subtitle).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let badge, dynamicTypeSize.isAccessibilitySize {
                    BaselinePill(text: badge.text, color: badge.color).padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            if let badge, !dynamicTypeSize.isAccessibilitySize {
                BaselinePill(text: badge.text, color: badge.color)
            }
            trailing()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The trailing chevron of a row that pushes or presents something.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(BaselineTheme.symbolSmall)
            .foregroundStyle(BaselineTheme.textTertiary)
            .accessibilityHidden(true)
    }
}

/// A row that pushes `destination` on the navigation stack it sits in.
struct SettingsLinkRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var badge: (text: String, color: Color)? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle, badge: badge) {
                SettingsChevron()
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
