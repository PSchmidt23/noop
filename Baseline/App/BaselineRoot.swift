#if os(iOS)
import SwiftUI
import StrandDesign

/// Baseline's shell: four tabs (Home, Trends, Sleep, Friends), each with its own navigation stack.
/// Settings is the gear in every tab's toolbar, the journal is a sheet Home presents, so neither is a
/// tab. Friends is opt-in: the tab is always there, but Home, Trends and Sleep never need an account
/// (Baseline/Research/FRIENDS_SPEC.md). A first-run gate covers the shell until the person has paired a
/// strap (or chosen to skip).
struct BaselineRoot: View {
    @AppStorage(BaselineRoot.onboardedKey) private var onboarded = false
    /// Raised by `BaselineNotificationDelegate` when the evening check-in is tapped; consumed below.
    @AppStorage(BaselineNotificationDelegate.pendingTabKey) private var pendingTab: String?
    @State private var tab: Tab
    /// Bumped whenever something asks Home to present the journal sheet (`--tab journal`, the evening
    /// check-in's tap). Home watches it with `initial: true`, so a request raised before the view
    /// existed (a cold start) is still honoured.
    @State private var journalRequest: Int
    /// Bumped when `--tab settings` asks Home to push Settings.
    @State private var settingsRequest: Int
    @Environment(\.scenePhase) private var scenePhase
    /// The Friends tab's state (created in `BaselineApp`): its badge (incoming requests + competition
    /// invitations) and the join code a `baseline://friends/join/CODE` link hands over.
    @EnvironmentObject private var friends: FriendsStore

    init() {
        // Touching the static runs the launch-argument override exactly once per process, before the
        // first @AppStorage read, however many times SwiftUI re-creates this value.
        _ = BaselineRoot.onboardingOverrideApplied
        let request = BaselineRoot.launchRequest
        _tab = State(initialValue: request.tab)
        _journalRequest = State(initialValue: request.journal ? 1 : 0)
        _settingsRequest = State(initialValue: request.settings ? 1 : 0)
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

    /// What `--tab …` asked for: the tab to open and whether Home should present the journal sheet
    /// (`journal`) or push Settings (`settings`) on top. Pure, so `parse` is unit-tested.
    struct LaunchRequest: Equatable {
        var tab: Tab = .home
        var journal = false
        var settings = false

        /// `--tab home|trends|sleep|friends`, with the aliases the screenshot harness and older notes use:
        /// `today` → home; `journal` → home with the journal sheet presented; `settings` → home with
        /// Settings pushed. Anything else, or a missing value, is Home.
        static func parse(_ arguments: [String]) -> LaunchRequest {
            guard let i = arguments.firstIndex(of: "--tab"), i + 1 < arguments.count else { return LaunchRequest() }
            switch arguments[i + 1] {
            case "trends": return LaunchRequest(tab: .trends)
            case "sleep": return LaunchRequest(tab: .sleep)
            case "friends": return LaunchRequest(tab: .friends)
            case "journal": return LaunchRequest(tab: .home, journal: true)
            case "settings": return LaunchRequest(tab: .home, settings: true)
            default: return LaunchRequest(tab: .home)   // "home", "today", unknown
            }
        }
    }

    /// DEBUG-only: `--tab trends` opens the app on that tab (used for screenshots and verification).
    /// Always Home in Release.
    private static var launchRequest: LaunchRequest {
        #if DEBUG
        return LaunchRequest.parse(CommandLine.arguments)
        #else
        return LaunchRequest()
        #endif
    }

    /// DEBUG-only: `--ui-testing` (passed by BaselineUITests' ScreenshotTests and MarketingShots) pins the
    /// tab bar so a scrolled capture is deterministic. Always false in Release.
    private static let isUITesting: Bool = {
        #if DEBUG
        return CommandLine.arguments.contains("--ui-testing")
        #else
        return false
        #endif
    }()

    enum Tab: Hashable { case home, trends, sleep, friends }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                NavigationStack { TodayScreen(journalRequest: journalRequest, settingsRequest: settingsRequest) }
                    .tabItem { Label("Home", systemImage: "house") }.tag(Tab.home)
                NavigationStack { TrendsScreen() }
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(Tab.trends)
                NavigationStack { SleepScreen() }
                    .tabItem { Label("Sleep", systemImage: "moon.zzz") }.tag(Tab.sleep)
                NavigationStack { FriendsScreen() }
                    .tabItem { Label("Friends", systemImage: "person.2") }.tag(Tab.friends)
                    .badge(friends.badgeCount)
            }
            .tint(BaselineTheme.accent)
            // The native glass tab bar shrinks while reading data; `.never` under `--ui-testing` so the
            // screenshot harness' frame-compare scroll loop never sees the bar animating.
            .tabBarMinimizeBehavior(BaselineRoot.isUITesting ? .never : .onScrollDown)
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
        // A widget tap (`baseline://home`, the one `widgetURL` the BaselineWidgets extension sets; the
        // scheme is registered in project.yml's Baseline block), or a friend's invite link
        // (`baseline://friends/join/CODE`): the Friends tab, with the code kept on the store until the
        // person is signed in, when FriendsScreen asks "Connect with …?". Any other scheme or host is ignored.
        .onOpenURL { url in
            guard let destination = BaselineDeepLink.destination(for: url) else { return }
            switch destination {
            case .home: tab = .home
            case .trends: tab = .trends
            case .sleep: tab = .sleep
            case .friends: tab = .friends
            case .join(let code):
                tab = .friends
                // Kept by the store until the person is signed in and set up, then peeked ("Connect with …?").
                Task { await friends.handleJoinLink(code: code) }
            }
        }
    }

    /// Open what a notification asked for, once, then clear the request so the same tap cannot re-fire
    /// on the next activation. "journal" is Home with the journal sheet for today (the evening check-in
    /// logs tonight's habits). Unknown values are cleared without effect.
    private func consumePendingTab() {
        guard let value = pendingTab else { return }
        if value == BaselineNotificationDelegate.pendingTabJournal {
            tab = .home
            journalRequest += 1
        }
        pendingTab = nil
    }
}

#endif
