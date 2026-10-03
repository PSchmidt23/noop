import Foundation

/// Which backend the Friends tab talks to (FRIENDS_SPEC.md D12, §5.3). Pure, so every branch is unit-tested.
///
/// In order:
/// 1. DEBUG `--ui-testing`, `--friends-demo`, `--friends-state …` or `--demo-seed` → demo. The signed-in state follows
///    `--friends-state signedOut | setup | ready` (default ready).
/// 2. Sample data on → demo, signed in, EVEN WHEN a config exists: synthetic numbers must never reach a server.
/// 3. A valid `Supabase.plist` → live.
/// 4. "Preview with demo friends" tapped this session → demo, signed in.
/// 5. Otherwise → unavailable (the intro offers the preview, in DEBUG and Release alike).
enum FriendsBackendFactory {

    enum Choice: Equatable, Sendable {
        case demo(signedIn: Bool, needsProfile: Bool = false)
        case live(FriendsConfig)
        case unavailable

        var isDemo: Bool { if case .demo = self { return true } else { return false } }

        /// The demo backend's starting state for this choice (nil for live / unavailable).
        var demoStart: LocalDemoFriendsBackend.StartState? {
            guard case let .demo(signedIn, needsProfile) = self else { return nil }
            if !signedIn { return .signedOut }
            return needsProfile ? .setup : .ready
        }
    }

    static let demoArguments = ["--ui-testing", "--friends-demo", "--demo-seed"]

    static func choose(config: FriendsConfig?, sampleDataActive: Bool, arguments: [String], isDebug: Bool,
                       previewRequested: Bool) -> Choice {
        if isDebug {
            let state = friendsState(arguments)
            let forced = demoArguments.contains(where: arguments.contains)
                || arguments.contains { $0.hasPrefix("--friends-demo") }
            if state != nil || forced {
                switch state ?? "ready" {
                case "signedOut", "signedout", "signed-out": return .demo(signedIn: false)
                case "setup": return .demo(signedIn: true, needsProfile: true)
                default: return .demo(signedIn: true)
                }
            }
        }
        if sampleDataActive { return .demo(signedIn: true) }
        if let config { return .live(config) }
        if previewRequested { return .demo(signedIn: true) }
        return .unavailable
    }

    /// The value after `--friends-state`, or "ready" when the flag is present without a value; nil when absent.
    static func friendsState(_ arguments: [String]) -> String? {
        guard let i = arguments.firstIndex(of: "--friends-state") else { return nil }
        return i + 1 < arguments.count ? arguments[i + 1] : "ready"
    }

    /// The backend for a choice. `keychain` and `defaults` are injectable for tests. The live backend first drops a
    /// session a previous install left in the Keychain (`FriendsKeychain.clearIfNewInstall`).
    static func makeBackend(_ choice: Choice, keychain: FriendsKeychain = FriendsKeychain(),
                            defaults: UserDefaults = .standard,
                            now: @escaping @Sendable () -> Date = { Date() }) -> FriendsBackend? {
        switch choice {
        case let .demo(signedIn, needsProfile):
            let start: LocalDemoFriendsBackend.StartState = !signedIn ? .signedOut : (needsProfile ? .setup : .ready)
            return LocalDemoFriendsBackend(start: start, now: now)
        case let .live(config):
            keychain.clearIfNewInstall(defaults)
            return SupabaseFriendsBackend(config: config, keychain: keychain)
        case .unavailable:
            return nil
        }
    }
}
