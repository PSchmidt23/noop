import XCTest
@testable import Baseline

/// `FriendsBackendFactory.choose` and `FriendsConfig`: which backend the tab talks to, and which config files the app
/// refuses.
final class FriendsBackendFactoryTests: XCTestCase {

    // An anon JWT ({"role":"anon"}) and a service-role JWT ({"role":"service_role"}); signatures are dummies.
    private let anonJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.c2ln"
    private let serviceJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2ln"
    private var config: FriendsConfig { FriendsConfig.make(url: "https://abc.supabase.co", key: anonJWT)! }

    private func choose(config: FriendsConfig? = nil, sample: Bool = false, args: [String] = [], debug: Bool = true,
                        preview: Bool = false) -> FriendsBackendFactory.Choice {
        FriendsBackendFactory.choose(config: config, sampleDataActive: sample, arguments: args, isDebug: debug,
                                     previewRequested: preview)
    }

    func testSampleData_forcesDemo_evenWithAConfig() {
        XCTAssertEqual(choose(config: config, sample: true), .demo(signedIn: true))
        XCTAssertEqual(choose(config: config, sample: true, debug: false), .demo(signedIn: true))
    }

    func testDebugArguments_forceDemo() {
        XCTAssertEqual(choose(config: config, args: ["--demo-seed"]), .demo(signedIn: true))
        XCTAssertEqual(choose(config: config, args: ["--ui-testing"]), .demo(signedIn: true))
        XCTAssertEqual(choose(args: ["--friends-demo"]), .demo(signedIn: true))
        XCTAssertEqual(choose(args: ["--friends-state", "signedOut"]), .demo(signedIn: false))
        XCTAssertEqual(choose(args: ["--friends-state", "setup"]), .demo(signedIn: true, needsProfile: true))
        XCTAssertEqual(choose(args: ["--friends-state", "ready"]), .demo(signedIn: true))
    }

    func testDebugArguments_ignoredInRelease() {
        XCTAssertEqual(choose(config: config, args: ["--demo-seed"], debug: false), .live(config))
        XCTAssertEqual(choose(args: ["--friends-state", "signedOut"], debug: false), .unavailable)
    }

    func testConfig_live_none_unavailable_preview_demo() {
        XCTAssertEqual(choose(config: config), .live(config))
        XCTAssertEqual(choose(), .unavailable)
        XCTAssertEqual(choose(preview: true), .demo(signedIn: true))
        XCTAssertEqual(choose(config: config, preview: true), .live(config), "a real server wins over the preview")
    }

    func testDemoStart() {
        XCTAssertEqual(FriendsBackendFactory.Choice.demo(signedIn: false).demoStart, .signedOut)
        XCTAssertEqual(FriendsBackendFactory.Choice.demo(signedIn: true, needsProfile: true).demoStart, .setup)
        XCTAssertEqual(FriendsBackendFactory.Choice.demo(signedIn: true).demoStart, .ready)
        XCTAssertNil(FriendsBackendFactory.Choice.unavailable.demoStart)
        XCTAssertEqual(FriendsBackendFactory.makeBackend(.demo(signedIn: true))?.kind, .demo)
        let suite = "baseline.tests.friendsFactory"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FriendsBackendFactory.makeBackend(.live(config), keychain: testKeychain, defaults: defaults)?.kind, .live)
        XCTAssertNil(FriendsBackendFactory.makeBackend(.unavailable))
    }

    // MARK: Reinstall

    private let testKeychain = FriendsKeychain(service: "com.patrickschmidt.baseline.friends.tests.install")

    private func session() -> FriendsStoredSession {
        FriendsStoredSession(access: "A", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: UUID())
    }

    /// Keychain items outlive the app; UserDefaults do not. A reinstall (no marker, no local Friends keys) must not
    /// silently sign back in and resume uploads: the stored session is dropped before the live backend is made.
    func testReinstall_dropsTheSessionAPreviousInstallLeft() {
        let suite = "baseline.tests.friendsInstall"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite); testKeychain.clear() }

        testKeychain.save(session())
        _ = FriendsBackendFactory.makeBackend(.live(config), keychain: testKeychain, defaults: defaults)
        XCTAssertNil(testKeychain.load(), "a fresh install starts signed out")
        XCTAssertTrue(defaults.bool(forKey: FriendsKeychain.installMarkerKey))

        // Same install, later launches: the session stays.
        testKeychain.save(session())
        _ = FriendsBackendFactory.makeBackend(.live(config), keychain: testKeychain, defaults: defaults)
        XCTAssertNotNil(testKeychain.load())
    }

    @MainActor
    func testUpdateFromABuildWithoutTheMarker_keepsTheSession() {
        let suite = "baseline.tests.friendsInstallUpdate"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite); testKeychain.clear() }

        defaults.set(true, forKey: FriendsStore.consentShownKey)   // this install was set up before the marker existed
        testKeychain.save(session())
        XCTAssertFalse(testKeychain.clearIfNewInstall(defaults))
        XCTAssertNotNil(testKeychain.load())
        XCTAssertEqual(FriendsKeychain.installEvidenceKeys, [FriendsStore.consentShownKey, FriendsStore.digestKey])
    }

    // MARK: FriendsConfig

    func testConfig_rejectsUnsafeOrPlaceholderFiles() {
        XCTAssertNil(FriendsConfig.make(url: nil, key: anonJWT), "missing")
        XCTAssertNil(FriendsConfig.make(url: "https://YOUR-PROJECT.supabase.co", key: anonJWT), "placeholder URL")
        XCTAssertNil(FriendsConfig.make(url: "https://abc.supabase.co", key: "PASTE_ANON_OR_PUBLISHABLE_KEY"), "placeholder key")
        XCTAssertNil(FriendsConfig.make(url: "http://abc.supabase.co", key: anonJWT), "http")
        XCTAssertNil(FriendsConfig.make(url: "https://abc.supabase.co", key: "sb_secret_abc123"), "secret key")
        XCTAssertNil(FriendsConfig.make(url: "https://abc.supabase.co", key: serviceJWT), "service_role JWT")
        XCTAssertNil(FriendsConfig.make(url: "https://abc.supabase.co", key: "not-a-key"), "unknown key shape")
    }

    func testConfig_acceptsAnonJWTAndPublishableKey() {
        XCTAssertEqual(FriendsConfig.make(url: "https://abc.supabase.co", key: anonJWT)?.anonKey, anonJWT)
        XCTAssertNotNil(FriendsConfig.make(url: " https://abc.supabase.co ", key: "sb_publishable_abc123"))
        XCTAssertEqual(FriendsConfig.jwtRole(serviceJWT), "service_role")
        XCTAssertEqual(FriendsConfig.jwtRole(anonJWT), "anon")
    }

    func testConfig_missingFileInBundleIsNil() {
        // The test bundle carries no Supabase.plist.
        XCTAssertNil(FriendsConfig.load(bundle: Bundle(for: Self.self)))
    }
}
