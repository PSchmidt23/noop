#if os(iOS)
import SwiftUI

/// Settings: grouped cards, one idea each. Strap, Apple Health and Import push NOOP's own screens;
/// Profile is Baseline's small form over `ProfileStore`; About carries attribution, license and the
/// disclaimer. Each card observes only what it needs, so the root never re-renders on strap ticks.
struct SettingsScreen: View {
    var body: some View {
        BaselineScreen(title: "Settings") {
            SettingsSection(label: "Strap") { SettingsStrapCard() }
            SettingsSection(label: "Apple Health") { SettingsHealthCard() }
            SettingsSection(label: "Data") { SettingsImportCard() }
            SettingsSection(label: "Profile") { SettingsProfileCard() }
            #if DEBUG
            SettingsSection(label: "Developer") { SettingsDeveloperCard() }
            #endif
            SettingsSection(label: "About") { SettingsAboutCard() }
        }
    }
}

// MARK: - Strap

private struct SettingsStrapCard: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var live: LiveState

    private var canSync: Bool { live.connected && live.bonded && !live.backfilling }

    var body: some View {
        BaselineCard {
            HStack(spacing: 10) {
                Circle()
                    .fill(live.connected ? BaselineTheme.good : BaselineTheme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(live.connected ? "Connected" : "Not connected")
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.text)
                Spacer()
                if let battery {
                    BaselinePill(text: battery.text, color: battery.color)
                }
            }
            Text(lastSyncLine)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
            SettingsDivider()
            SettingsLinkRow(icon: "dot.radiowaves.left.and.right", title: "Devices",
                            subtitle: "Pair, rename or remove a strap") {
                SettingsHostedScreen { DevicesView() }
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
    /// the connected source.
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
                            badge: status) {
                SettingsHostedScreen { AppleHealthView() }
            }
        }
    }

    private var status: (text: String, color: Color) {
        switch health.auth {
        case .authorized:         return ("Allowed", BaselineTheme.good)
        case .denied:             return ("Not allowed", BaselineTheme.watch)
        case .unavailable:        return ("Unavailable", BaselineTheme.textTertiary)
        case .entitlementMissing: return ("Not in this build", BaselineTheme.textTertiary)
        case .unknown:            return ("Not set up", BaselineTheme.textTertiary)
        }
    }
}

// MARK: - Import

private struct SettingsImportCard: View {
    var body: some View {
        BaselineCard {
            SettingsLinkRow(icon: "square.and.arrow.down", title: "Import data",
                            subtitle: "WHOOP CSV export or Apple Health export") {
                SettingsHostedScreen { DataSourcesView() }
            }
        }
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

/// Section label plus its card, so the screen body stays within the view-builder limit.
private struct SettingsSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BaselineSectionLabel(text: label)
            content()
        }
    }
}

struct SettingsDivider: View {
    var body: some View { Divider().overlay(BaselineTheme.hairline) }
}

/// Icon, title, optional subtitle, and whatever sits at the trailing edge (a pill, a chevron, a spinner).
struct SettingsRowLabel<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BaselineTheme.accent)
                .frame(width: 30, height: 30)
                .background(BaselineTheme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                if let subtitle {
                    Text(subtitle).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// A row that pushes `destination` on the tab's navigation stack.
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
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle) {
                if let badge { BaselinePill(text: badge.text, color: badge.color) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BaselineTheme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Hosts one of NOOP's screens inside Baseline's navigation stack. They draw their own in-content
/// title, so the bar is kept compact and dark.
struct SettingsHostedScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
#endif
