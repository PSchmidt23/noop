#if os(iOS)
import SwiftUI

/// Settings › Apple Health: the permission state in one pill and one sentence, what Baseline reads and
/// writes, and the two actions (Allow, Sync now). The engine is NOOP's `HealthKitBridge`; a sync is
/// always followed by the engine's own refresh, in the order `BaselineApp` uses on foreground.
struct AppleHealthScreen: View {
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel
    @State private var requesting = false

    var body: some View {
        BaselineScreen(title: "Apple Health") {
            statusCard
            BaselineCard(title: "Baseline reads") {
                Text(AppleHealthFacts.reads)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BaselineCard(title: "Baseline writes back") {
                Text(AppleHealthFacts.writes)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The exchange happens on this iPhone only. Change or withdraw access at any time in the Health app under your profile › Apps › Baseline.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Status

    private var statusCard: some View {
        let pill = AppleHealthStatus.pill(for: health.auth)
        return BaselineCard {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BaselineTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(BaselineTheme.accent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("Apple Health").font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                Spacer()
                BaselinePill(text: health.syncing ? "Syncing" : pill.text, color: pill.color)
            }
            Text(AppleHealthStatus.sentence(for: health.auth))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if health.auth == .authorized {
                Text(lastSyncLine)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            }
            if let err = health.lastError {
                Text(err)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.watch)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        switch health.auth {
        case .unknown, .denied:
            SettingsDivider()
            Button(action: allow) {
                SettingsRowLabel(icon: "checkmark.circle", title: requesting ? "Asking…" : "Allow",
                                 subtitle: "iOS asks which types Baseline may read and write") {
                    if requesting { ProgressView().tint(BaselineTheme.accent) }
                }
            }
            .buttonStyle(.plain)
            .disabled(requesting)
            if health.auth == .denied, let url = URL(string: "x-apple-health://") {
                SettingsDivider()
                Link(destination: url) {
                    SettingsRowLabel(icon: "arrow.up.forward.app", title: "Open the Health app",
                                     subtitle: "Your profile › Apps › Baseline, then turn the types on") {
                        EmptyView()
                    }
                }
            }
        case .authorized:
            SettingsDivider()
            Button(action: syncNow) {
                SettingsRowLabel(icon: "arrow.triangle.2.circlepath",
                                 title: health.syncing ? "Syncing…" : "Sync now",
                                 subtitle: "Read the last 30 days and write back what Baseline computed") {
                    if health.syncing { ProgressView().tint(BaselineTheme.accent) }
                }
            }
            .buttonStyle(.plain)
            .disabled(health.syncing)
        case .unavailable, .entitlementMissing:
            EmptyView()
        }
    }

    private var lastSyncLine: String {
        guard let last = health.lastSync else { return "Not synced yet. New strap data is written as it lands." }
        return "Last sync \(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
    }

    /// The same request-then-sync-then-refresh sequence NOOP's screen runs, so a fresh grant fills the
    /// store before Today repaints.
    private func allow() {
        guard !requesting else { return }
        requesting = true
        Task {
            await health.requestAuthorization()
            await HealthSyncRefreshCoordinator.run(
                sync: { await health.sync() },
                refresh: { await model.refreshAfterAppleHealthSync(authorized: health.auth == .authorized) })
            requesting = false
        }
    }

    private func syncNow() {
        Task {
            await HealthSyncRefreshCoordinator.run(
                sync: { await health.sync() },
                refresh: { await model.refreshAfterAppleHealthSync(authorized: health.auth == .authorized) })
        }
    }
}

/// One wording per `HealthKitBridge.AuthState`, shared by this screen and the Settings row so the badge
/// on the row and the pill on the screen can never disagree.
enum AppleHealthStatus {
    static func pill(for auth: HealthKitBridge.AuthState) -> (text: String, color: Color) {
        switch auth {
        case .authorized:         return ("Allowed", BaselineTheme.good)
        case .denied:             return ("Not allowed", BaselineTheme.watch)
        case .unavailable:        return ("Unavailable", BaselineTheme.textTertiary)
        case .entitlementMissing: return ("Not in this build", BaselineTheme.textTertiary)
        case .unknown:            return ("Not set up", BaselineTheme.textTertiary)
        }
    }

    static func sentence(for auth: HealthKitBridge.AuthState) -> String {
        switch auth {
        case .authorized:
            return "Baseline reads from and writes to Apple Health on this iPhone. New strap data is written automatically."
        case .denied:
            return "Access was not granted. iOS shows the permission sheet once; after that it is changed in the Health app."
        case .unavailable:
            return "Apple Health is not available on this device."
        case .entitlementMissing:
            return "This build was signed without Apple's Health permission, so it cannot talk to Apple Health. Import an Apple Health export under Settings › Import instead."
        case .unknown:
            return "Not set up yet. Allow access and Baseline reads your sleep, workouts and heart data, and writes back what it computes."
        }
    }
}

/// What NOOP's bridge asks to read and to share, in Baseline's words. Mirrors the type sets in
/// `HealthKitBridge` (`quantityReadIds`, `quantityWriteIds`, `highResQuantityWriteIds`, sleep,
/// workouts and routes); keep in step when the engine's lists change.
enum AppleHealthFacts {
    static let reads = "Sleep, workouts and their routes, heart rate, resting heart rate, HRV, blood oxygen, respiratory rate, body temperature, steps, active and resting energy, VO₂ max, weight and body composition, water and caffeine."
    static let writes = "Sleep with stages, workouts with routes, continuous heart rate, resting heart rate, HRV, blood oxygen, respiratory rate, active energy, and walking, running and cycling distance."
}
#endif
