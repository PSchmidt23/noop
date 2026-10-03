#if os(iOS)
import SwiftUI

/// First sign-in (`friends-setup`), three steps: (a) a name friends will see, validated inline with the
/// same rule the server applies (`DisplayName.validate`); (b) "I'm 16 or older", required; (c) the
/// per-metric consent (`FriendsConsentView`), every row Off. "I agree" needs at least one row on; "Share
/// nothing for now" finishes with nothing shared. Steps (a)+(b) create the profile; step (c) sets each
/// chosen share. Presented by `FriendsScreen` while the phase is `.needsProfile` or `.needsConsent`.
/// Sign in with Apple has already created the account by step (a), so besides "Not now" (sign out) that
/// step offers "Delete account" (`friends-setup-delete`, App Store 5.1.1(v)); Settings › Friends & sharing
/// offers the same in every signed-in phase.
struct FriendsSetupSheet: View {
    @EnvironmentObject private var store: FriendsStore
    @State private var name = ""
    @State private var adult = false
    @State private var shares: [FriendsMetric: ShareAudience] = [:]
    @State private var error: FriendsError?
    @State private var busy = false
    @State private var confirmDelete = false

    private var onConsentStep: Bool { store.phase == .needsConsent }

    private var nameCheck: Result<String, FriendsError> { DisplayName.validate(name) }
    private var nameError: FriendsError? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if case .failure(let e) = nameCheck { return e }
        return nil
    }
    private var nameOK: Bool { if case .success = nameCheck { return true } else { return false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                    if onConsentStep { consentStep } else { profileStep }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle(onConsentStep ? "What to share" : "Set up Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !onConsentStep {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not now") { Task { await store.signOut() } }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("friends-setup")
        .confirmationDialog("Delete your Friends account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(FriendsAccountDeletion.setupMessage)
        }
    }

    // MARK: (a) + (b)

    @ViewBuilder private var profileStep: some View {
        BaselineCard(title: "Your name") {
            TextField("First name or nickname", text: $name)
                .font(BaselineTheme.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(BaselineTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BaselineTheme.hairline, lineWidth: 1))
            Text("Friends see only this name. No photo, no email.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            FriendsErrorLine(error: nameError)
        }
        BaselineCard {
            Toggle(isOn: $adult) {
                Text("I'm 16 or older").font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
            }
            .tint(BaselineTheme.accent)
            Text("Friends is for people 16 and over.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        }
        FriendsErrorLine(error: error)
        BaselineCTA(title: busy ? "Saving…" : "Continue") {
            Task { await createProfile() }
        }
        .disabled(!nameOK || !adult || busy)
        // The account Sign in with Apple just made, deleted here rather than only signed out of.
        Button(role: .destructive) { confirmDelete = true } label: {
            Text("Delete account")
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.low)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("friends-setup-delete")
    }

    /// The sheet closes as soon as the account is gone (the phase leaves `.needsProfile`), so a failure is the
    /// only outcome it shows; the confirmation already said what happens with Sign in with Apple.
    private func deleteAccount() async {
        busy = true; error = nil
        defer { busy = false }
        if await FriendsAccountDeletion.run(store) == nil {
            error = store.lastError ?? .server
        }
    }

    private func createProfile() async {
        guard case .success(let clean) = nameCheck else { return }
        busy = true; error = nil; store.lastError = nil
        defer { busy = false }
        if !(await store.completeProfile(displayName: clean, ageConfirmed: adult)) {
            error = store.lastError ?? .server
        }
    }

    // MARK: (c)

    @ViewBuilder private var consentStep: some View {
        BaselineCard(title: "Choose what friends can see") {
            Text("Everything starts off. “Only in competitions” shares a metric just for scoring in competitions you join.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            FriendsConsentView(shares: $shares)
        }
        Text(FriendsConsent.paragraph)
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        FriendsErrorLine(error: error)
        BaselineCTA(title: busy ? "Saving…" : "I agree") { Task { await finish(with: shares) } }
            .disabled(shares.isEmpty || busy)
        BaselineCTA(title: "Share nothing for now", prominent: false) { Task { await finish(with: [:]) } }
            .disabled(busy)
    }

    private func finish(with chosen: [FriendsMetric: ShareAudience]) async {
        busy = true; error = nil; store.lastError = nil
        defer { busy = false }
        if chosen.isEmpty { await store.skipConsent() } else { await store.finishConsent(chosen) }
        // A share the server refused leaves its row Off; the store records why.
        error = store.lastError
    }
}
#endif
