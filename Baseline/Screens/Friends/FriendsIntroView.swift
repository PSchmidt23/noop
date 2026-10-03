#if os(iOS)
import SwiftUI
import AuthenticationServices

/// The signed-out Friends tab (`friends-intro`): one card that says what can be shared, how physiology
/// appears (only as each person's change against their own baseline) and what never leaves the phone;
/// then Sign in with Apple when a server is configured, or "Preview with demo friends" when it is not
/// (session only, so App Review can try the tab), or "Continue with demo account" on the demo backend.
struct FriendsIntroView: View {
    @EnvironmentObject private var store: FriendsStore
    @State private var nonce = AppleSignIn.randomNonce()
    /// Apple's own failure line ("Sign in with Apple didn't finish."); server errors come from `store.lastError`.
    @State private var appleFailure: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
            BaselineCard {
                Text("Compete on what you do, not on your body")
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                FriendsIntroRow(icon: "figure.walk",
                                text: "You choose what to share: steps, intensity minutes, active days, nights at your sleep goal, on-time bedtimes. Nothing is shared until you turn it on.")
                FriendsIntroRow(icon: "arrow.up.right",
                                text: "HRV, resting HR and readiness: only as your change against your own baseline, like “HRV +8 %”. Never your numbers, never ranked.")
                FriendsIntroRow(icon: "lock",
                                text: "Never shared: heart-rate data, stress, calories, journal, location.")
            }

            VStack(alignment: .leading, spacing: 12) {
                if store.offersPreview {
                    BaselineCTA(title: "Preview with demo friends", systemImage: "person.2") {
                        Task { await run { await store.requestPreview() } }
                    }
                    .accessibilityIdentifier("friends-preview")
                    Text("Friends isn't connected to a server in this build. The preview uses made-up friends and is forgotten when you close Baseline.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if store.isDemo {
                    BaselineCTA(title: "Continue with demo account", systemImage: "person.2") {
                        Task { await run { await store.signInDemo() } }
                    }
                    .accessibilityIdentifier("friends-signin")
                } else {
                    SignInWithAppleButton(.continue) { request in
                        nonce = AppleSignIn.randomNonce()
                        AppleSignIn.configure(request, rawNonce: nonce)
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .disabled(busy)
                    .accessibilityIdentifier("friends-signin")
                }
                if let appleFailure {
                    Text(appleFailure).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FriendsErrorLine(error: store.lastError)
                Text("Friends needs Sign in with Apple. Everything else in Baseline works without an account. Your email is not requested. 16 and over.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends-intro")
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        appleFailure = nil
        switch AppleSignIn.outcome(result) {
        case .token(let token):
            let raw = nonce
            Task { await run { await store.signInWithApple(idToken: token, nonce: raw) } }
        case .canceled:
            return   // closing Apple's sheet is not an error
        case .failed(let line):
            appleFailure = line
        }
    }

    private func run(_ work: () async -> Void) async {
        busy = true
        store.lastError = nil
        defer { busy = false }
        await work()
    }
}

private struct FriendsIntroRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconTile(icon: icon)
            Text(text)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
