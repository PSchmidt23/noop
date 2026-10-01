#if os(iOS)
import SwiftUI
import StrandDesign

/// Baseline's shell: five tabs, each with its own navigation stack. A first-run gate covers it until the
/// person has paired a strap (or chosen to skip).
struct BaselineRoot: View {
    @AppStorage(BaselineRoot.onboardedKey) private var onboarded = false
    /// Raised by `BaselineNotificationDelegate` when the evening check-in is tapped; consumed below.
    @AppStorage(BaselineNotificationDelegate.pendingTabKey) private var pendingTab: String?
    @State private var tab: Tab = BaselineRoot.launchTab ?? .today
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Touching the static runs the launch-argument override exactly once per process, before the
        // first @AppStorage read, however many times SwiftUI re-creates this value.
        _ = BaselineRoot.onboardingOverrideApplied
    }

    static let onboardedKey = "baseline.onboarded"

    /// DEBUG-only: `--skip-onboarding` forces `baseline.onboarded` to true for this launch (tab
    /// screenshots land on the tab, not the welcome gate); `--reset-onboarding` forces it to false so
    /// the welcome flow shows regardless of what an earlier run saved. The override lives in the
    /// VOLATILE argument domain (`UserDefaults.argumentDomain`, first in the search list, never written
    /// to disk), so `@AppStorage` reads it for this process while the value an earlier run saved stays
    /// untouched for the next ordinary launch. Applied once per process (a static `let`). Both flags are
    /// no-ops in Release.
    private static let onboardingOverrideApplied: Void = {
        #if DEBUG
        let args = CommandLine.arguments
        let forced: Bool?
        if args.contains("--reset-onboarding") { forced = false }
        else if args.contains("--skip-onboarding") { forced = true }
        else { forced = nil }
        if let forced {
            var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            domain[onboardedKey] = forced
            UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        }
        #endif
    }()

    /// Finishing the welcome flow under `--reset-onboarding` must still dismiss the gate: the volatile
    /// override would otherwise shadow the `true` the flow writes. Lifts the override (DEBUG only; a no-op
    /// when none was applied) so the persisted value is what `@AppStorage` reads again.
    private static func clearOnboardingOverride() {
        #if DEBUG
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard domain.removeValue(forKey: onboardedKey) != nil else { return }
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        #endif
    }

    /// DEBUG-only: `--tab trends` opens the app on that tab (used for screenshots and verification).
    private static var launchTab: Tab? {
        #if DEBUG
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--tab"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "trends": return .trends
        case "sleep": return .sleep
        case "journal": return .journal
        case "settings": return .settings
        default: return .today
        }
        #else
        return nil
        #endif
    }

    enum Tab: Hashable { case today, trends, sleep, journal, settings }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                NavigationStack { TodayScreen() }
                    .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(Tab.today)
                NavigationStack { TrendsScreen() }
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(Tab.trends)
                NavigationStack { SleepScreen() }
                    .tabItem { Label("Sleep", systemImage: "moon.zzz") }.tag(Tab.sleep)
                NavigationStack { JournalScreen() }
                    .tabItem { Label("Journal", systemImage: "checklist") }.tag(Tab.journal)
                NavigationStack { SettingsScreen() }
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(Tab.settings)
            }
            .tint(BaselineTheme.accent)
            if !onboarded {
                WelcomeScreen(onFinished: {
                    BaselineRoot.clearOnboardingOverride()
                    onboarded = true
                })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: onboarded)
        // `initial: true` covers a cold start whose tap landed before this view existed; the scene-phase
        // check covers a flag written while the app was suspended and never observed.
        .onChange(of: pendingTab, initial: true) { _, _ in consumePendingTab() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { consumePendingTab() } }
    }

    /// Switch to the tab a notification asked for, once, then clear the request so the same tap cannot
    /// re-fire on the next activation. Unknown values are cleared without effect.
    private func consumePendingTab() {
        guard let value = pendingTab else { return }
        if value == BaselineNotificationDelegate.pendingTabJournal { tab = .journal }
        pendingTab = nil
    }
}

#endif
