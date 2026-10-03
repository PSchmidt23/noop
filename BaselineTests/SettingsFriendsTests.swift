import XCTest
@testable import Baseline

/// Settings › Friends & sharing's testable parts: which phases count as signed in (the Account card, with
/// Sign out and "Delete account and shared data", is offered in every one of them, profile or not), the
/// Off → on consent sheet's wording, and the account delete that works before a name exists (App Store
/// 5.1.1(v): Sign in with Apple has already created the account at that point).
@MainActor
final class SettingsFriendsTests: XCTestCase {

    private let suite = "baseline.tests.settingsFriends"
    private var defaults: UserDefaults!
    private let anonJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.c2ln"
    private let forbidden = ["strain", "recovery", "coach", "active zone", "body battery", "stress monitor",
                             "circles", "activity rings"]

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeStore(_ fake: RecordingFriendsBackend) -> FriendsStore {
        let env = FriendsStore.Environment(arguments: [], isDebug: true,
                                           config: FriendsConfig.make(url: "https://stub.supabase.co", key: anonJWT),
                                           sampleDataActive: { false })
        return FriendsStore(environment: env, defaults: defaults, makeBackend: { _ in fake },
                            inputsLoader: { _ in nil }, now: { Date() }, timeZone: TimeZone(identifier: "UTC")!)
    }

    /// The screen branches on the phase, not on whether the overview loaded: every phase after sign-in has an
    /// account on the server, so every one of them keeps Sign out and Delete account.
    func testEverySignedInPhaseKeepsTheAccountCard() {
        XCTAssertTrue(FriendsSharingScreen.isSignedIn(.ready))
        XCTAssertTrue(FriendsSharingScreen.isSignedIn(.needsConsent))
        XCTAssertTrue(FriendsSharingScreen.isSignedIn(.needsProfile))
        XCTAssertFalse(FriendsSharingScreen.isSignedIn(.signedOut))
        XCTAssertFalse(FriendsSharingScreen.isSignedIn(.unavailable))
    }

    /// Off → on asks with the metric, the exact form that leaves the phone and the audience chosen.
    func testConsentSheetNamesTheMetricItsSharedFormAndTheAudience() {
        let hrv = FriendsShareChange(metric: .hrv, audience: .friends)
        XCTAssertEqual(FriendsShareConsentSheet.question(hrv), "Share HRV trend with friends?")
        XCTAssertEqual(FriendsShareConsentSheet.sharedLine(.hrv), "Shared: \(FriendsMetric.hrv.sharedForm).")
        let steps = FriendsShareChange(metric: .steps, audience: .competitions)
        XCTAssertEqual(FriendsShareConsentSheet.question(steps), "Share Steps for competitions only?")
        XCTAssertNotEqual(steps.id, FriendsShareChange(metric: .steps, audience: .friends).id)
    }

    func testCopyCarriesNoBannedWords() {
        var texts = [FriendsAccountDeletion.message, FriendsAccountDeletion.noProfileMessage,
                     FriendsAccountDeletion.setupMessage,
                     FriendsAccountDeletion.resultLine(revoked: true), FriendsAccountDeletion.resultLine(revoked: false)]
        for metric in FriendsMetric.allCases {
            texts.append(FriendsShareConsentSheet.sharedLine(metric))
            for audience in metric.allowedAudiences {
                texts.append(FriendsShareConsentSheet.question(FriendsShareChange(metric: metric, audience: audience)))
            }
        }
        for text in texts {
            for word in forbidden {
                XCTAssertFalse(text.lowercased().contains(word), "\(text) carries \(word)")
            }
        }
    }

    /// Signed in with Apple, stopped before the name step: the account can still be deleted in the app.
    func testDeleteBeforeAName_deletesTheSignIn() async {
        let fake = RecordingFriendsBackend(kind: .demo)
        fake.signedIn = true
        let store = makeStore(fake)
        await store.start()
        XCTAssertEqual(store.phase, .needsProfile)

        let line = await FriendsAccountDeletion.run(store)
        XCTAssertEqual(line, FriendsAccountDeletion.resultLine(revoked: false))
        XCTAssertEqual(fake.deleteCodes, [nil], "the demo never asks Apple for a code")
        XCTAssertFalse(fake.signedIn)
        XCTAssertEqual(store.phase, .signedOut)
    }
}
