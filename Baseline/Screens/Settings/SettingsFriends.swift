#if os(iOS)
import SwiftUI

/// Settings › Friends (`settings-friends`), the section between Notifications and About. Signed out it
/// says Friends is optional; signed in (in any phase: ready, before consent, or before a name) it is one
/// row into `FriendsSharingScreen`, where the person sees and changes everything that leaves the phone and
/// can always sign out or delete the account Sign in with Apple created.
struct SettingsFriendsCard: View {
    @EnvironmentObject private var store: FriendsStore

    var body: some View {
        BaselineCard {
            switch store.phase {
            case .ready, .needsConsent:
                SettingsLinkRow(icon: "person.2", title: "Friends & sharing",
                                subtitle: sharingSubtitle,
                                badge: demoBadge) {
                    FriendsSharingScreen()
                }
            case .needsProfile:
                // The account already exists on the server, so the row still opens Friends & sharing for
                // Sign out and "Delete account" (App Store 5.1.1(v)), not only a pointer to the Friends tab.
                SettingsLinkRow(icon: "person.2", title: "Friends & sharing",
                                subtitle: "Signed in. Finish setting up in the Friends tab.",
                                badge: demoBadge) {
                    FriendsSharingScreen()
                }
            case .signedOut, .unavailable:
                SettingsRowLabel(icon: "person.2", title: "Friends",
                                 subtitle: "Not signed in. Friends is optional; everything else works without an account.") { EmptyView() }
            }
        }
        .accessibilityIdentifier("settings-friends")
    }

    private var demoBadge: (text: String, color: Color)? {
        store.isDemo ? (text: "Demo", color: BaselineTheme.textTertiary) : nil
    }

    /// "Sam · 2 things shared"; just "Sam · Signed in" while the overview has not loaded, rather than a
    /// "Nothing shared" the server never said.
    private var sharingSubtitle: String {
        let name = store.me?.displayName
        guard let shares = store.overview?.myShares else {
            return [name, "Signed in"].compactMap { $0 }.joined(separator: " · ")
        }
        let shared = shares.count
        let what = shared == 0 ? "Nothing shared" : (shared == 1 ? "1 thing shared" : "\(shared) things shared")
        return [name, what].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Settings › Friends & sharing: your name, Competitive view, what you share (eight menus; turning one
/// on from Off asks for explicit consent first, `FriendsShareConsentSheet`; turning one off asks first,
/// because it deletes that metric from the server now), who you're hidden from, sign out, and "Delete
/// account and shared data" (Apple re-authorisation, then a hard delete of every shared row).
///
/// It branches on `store.phase`, not on whether the overview loaded: signed in without an overview
/// (offline, a server error, or just after setup) it says so with "Try again", and before a name exists
/// (`.needsProfile`) it points to the Friends tab. In every signed-in state the Account card (Sign out,
/// Delete account) is there, because the account exists from the moment Sign in with Apple finished.
struct FriendsSharingScreen: View {
    @EnvironmentObject private var store: FriendsStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var pendingOff: FriendsMetric?
    @State private var pendingOn: FriendsShareChange?
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteResult: String?
    @State private var error: FriendsError?
    @State private var busy = false
    @State private var loading = false

    private var overview: FriendsOverview? { store.overview }
    private var signedIn: Bool { Self.isSignedIn(store.phase) }
    /// Signed in with Apple, no profile yet: nothing is shared and the server copy (`my_data`) needs a profile.
    private var needsName: Bool { store.phase == .needsProfile }
    /// Signed in with a profile, but the overview did not load.
    private var overviewMissing: Bool { deleteResult == nil && signedIn && !needsName && overview == nil }

    /// Whether an account exists on the server (any phase after Sign in with Apple or the demo sign-in).
    static func isSignedIn(_ phase: FriendsStore.Phase) -> Bool {
        switch phase {
        case .ready, .needsConsent, .needsProfile: return true
        case .signedOut, .unavailable: return false
        }
    }

    var body: some View {
        BaselineScreen(title: "Friends & sharing", titleMode: .inline) {
            // One VStack, so BaselineScreen's LazyVStack sees a single item. With the cards as separate lazy
            // items the stack re-placed them on every frame once scrolled (a layout loop at full CPU that
            // never let the screen go idle; reproduced in the UI suite, gone with one item).
            VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                content
            }
        }
        .accessibilityIdentifier("settings-friends")
        // Opened while signed in without an overview (a failed fetch, or straight after setup): load it once.
        .task { if overviewMissing { await reload() } }
        .confirmationDialog("Stop sharing \(pendingOff?.title ?? "")?",
                            isPresented: Binding(get: { pendingOff != nil }, set: { if !$0 { pendingOff = nil } }),
                            titleVisibility: .visible, presenting: pendingOff) { m in
            Button("Stop sharing", role: .destructive) { act { await store.setShare(m, audience: nil) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its values are deleted from the server now. Friends and competitions stop seeing it.")
        }
        .confirmationDialog("Sign out of Friends?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out") { Task { await store.signOut(); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Friends keep seeing what you last shared until it ages out after 35 days or you stop sharing.")
        }
        .confirmationDialog("Delete your Friends account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account and shared data", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(needsName ? FriendsAccountDeletion.noProfileMessage : FriendsAccountDeletion.message)
        }
        .sheet(isPresented: $editingName) { nameSheet }
        // Off → on: the explicit, per-metric consent (FRIENDS_SPEC §7.2) before `set_share` logs it.
        .sheet(item: $pendingOn) { change in
            FriendsShareConsentSheet(change: change) {
                act { await store.setShare(change.metric, audience: change.audience) }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let deleteResult {
            BaselineCard {
                BaselineEmptyState(icon: "checkmark.circle", title: "Account deleted", message: deleteResult)
            }
        } else if !signedIn {
            BaselineCard {
                Text("Not signed in. Friends is optional; everything else in Baseline works without an account.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            if needsName {
                finishSetupCard
            } else if let overview {
                profileCard(overview)
                shareCard(overview)
            } else {
                notLoadedCard
            }
            accountCard
        }
        // The not-loaded card carries its own error line beside its "Try again".
        if !overviewMissing { FriendsErrorLine(error: error) }
    }

    // MARK: Cards

    /// `.needsProfile`: signed in with Apple, stopped before choosing a name.
    private var finishSetupCard: some View {
        BaselineCard {
            Text("Signed in, no name yet. Finish setting up in the Friends tab: a name friends will see, then what to share. Nothing is shared until then.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Signed in with a profile, but what you share did not load: the reason and "Try again".
    private var notLoadedCard: some View {
        BaselineCard {
            // No failure known yet: the `.task` load is about to run (or running), so no "didn't load" flash.
            if loading || (error == nil && store.lastError == nil) {
                HStack(spacing: 10) {
                    ProgressView().tint(BaselineTheme.accent)
                    Text("Loading what you share…")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                }
            } else {
                Text("Signed in. What you share didn't load, so it can't be changed right now.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FriendsErrorLine(error: error ?? store.lastError)
                BaselineCTA(title: "Try again", prominent: false) { Task { await reload() } }
                    .accessibilityIdentifier("friends-sharing-retry")
            }
        }
    }

    private func profileCard(_ o: FriendsOverview) -> some View {
        BaselineCard(title: "You") {
            Button {
                nameDraft = o.me.displayName
                editingName = true
            } label: {
                SettingsRowLabel(icon: "person.text.rectangle", title: o.me.displayName,
                                 subtitle: "The only thing friends see about you besides what you share") { SettingsChevron() }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your name")
            SettingsDivider()
            Toggle(isOn: $store.competitiveView) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Competitive view").font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                    Text("Off shows friends alphabetically, without places.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                }
            }
            .tint(BaselineTheme.accent)
        }
    }

    private func shareCard(_ o: FriendsOverview) -> some View {
        BaselineCard(title: "What you share") {
            ForEach(Array(FriendsMetric.allCases.enumerated()), id: \.element) { i, m in
                if i > 0 { SettingsDivider() }
                FriendsShareRow(metric: m, audience: o.myShares[m]) { new in
                    let old = o.myShares[m]
                    if new == nil, old != nil {
                        pendingOff = m
                    } else if let new, old == nil {
                        // Off → on needs the explicit consent; the menu stays Off until "I agree".
                        pendingOn = FriendsShareChange(metric: m, audience: new)
                    } else if new != old {
                        // Between two on levels: already consented, a plain choice.
                        act { await store.setShare(m, audience: new) }
                    }
                }
            }
            Text("Activity can be shared with friends or only inside competitions you join. HRV, resting HR and readiness only ever go up as a weekly change against your own baseline, and are never ranked. Calories, stress and heart-rate data are never shared.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if o.hiddenFromCount > 0 {
                SettingsDivider()
                SettingsRowLabel(icon: "eye.slash", title: "Hidden from \(o.hiddenFromCount)",
                                 subtitle: "Change it on each friend's page") { EmptyView() }
            }
        }
    }

    /// Sign out and Delete account in every signed-in state; the server copy once a profile exists.
    private var accountCard: some View {
        BaselineCard(title: "Account") {
            if !needsName {
                SettingsLinkRow(icon: "server.rack", title: "See what's on the server",
                                subtitle: "Everything Baseline's server holds for you, with a JSON export") {
                    FriendsServerDataScreen()
                }
                SettingsDivider()
            }
            // What signing out leaves behind is said once, in its confirmation.
            Button { confirmSignOut = true } label: {
                SettingsRowLabel(icon: "rectangle.portrait.and.arrow.right", title: "Sign out") { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friends-signout")
            SettingsDivider()
            Button(role: .destructive) { confirmDelete = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "trash")
                        .font(BaselineTheme.symbolAccessory.weight(.medium))
                        .foregroundStyle(BaselineTheme.low)
                        .frame(width: 30, height: 30)
                        .background(BaselineTheme.low.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    Text(busy ? "Deleting…" : "Delete account and shared data")
                        .font(BaselineTheme.body).foregroundStyle(BaselineTheme.low)
                    Spacer(minLength: 8)
                    if busy { ProgressView().tint(BaselineTheme.low) }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("friends-delete")
        }
    }

    private var nameSheet: some View {
        NavigationStack {
            ScrollView {
                BaselineCard(title: "Your name") {
                    TextField("First name or nickname", text: $nameDraft)
                        .font(BaselineTheme.body)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(BaselineTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(BaselineTheme.hairline, lineWidth: 1))
                    Text("Friends see only this name. No photo, no email.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    if case .failure(let e) = DisplayName.validate(nameDraft) { FriendsErrorLine(error: e) }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle("Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingName = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard case .success(let clean) = DisplayName.validate(nameDraft) else { return }
                        editingName = false
                        act { await store.rename(clean) }
                    }
                    .disabled({ if case .success = DisplayName.validate(nameDraft) { return false } else { return true } }())
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions

    /// Loads the overview (and competitions) again; a failure stays in `error` for the not-loaded card.
    private func reload() async {
        loading = true
        error = nil
        store.lastError = nil
        await store.refresh()
        error = store.lastError
        loading = false
    }

    private func delete() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            if let line = await FriendsAccountDeletion.run(store) {
                deleteResult = line
            } else {
                error = store.lastError ?? .server
            }
        }
    }

    /// Runs a store action; the store records a failure in `lastError`, which this view shows.
    private func act(_ work: @escaping () async -> Void) {
        Task {
            error = nil
            store.lastError = nil
            await work()
            error = store.lastError
        }
    }
}

/// "Delete account and shared data", shared by Friends & sharing and the setup sheet's name step. Apple asks
/// once more for a fresh authorization code, which the server revokes; cancelling that still deletes the
/// account and its data. `delete_account` needs only the sign-in, not a profile, so the account Sign in with
/// Apple creates can be deleted in the app from the moment it exists (App Store 5.1.1(v)).
enum FriendsAccountDeletion {
    /// The line to show after a delete; nil when it failed (`store.lastError` says why).
    @MainActor
    static func run(_ store: FriendsStore) async -> String? {
        store.lastError = nil
        let code = store.isDemo ? nil : await AppleSignIn.reauthorizeForDeletion()
        guard await store.deleteAccount(appleAuthorizationCode: code) else { return nil }
        return resultLine(revoked: store.lastDeleteRevoked == true)
    }

    static func resultLine(revoked: Bool) -> String {
        revoked ? "Deleted. Apple sign-in for Baseline was revoked." : "Deleted. \(manualRevocation)"
    }

    /// Where the person stops Sign in with Apple themselves when the server could not revoke it.
    static let manualRevocation = "To also stop Sign in with Apple for Baseline: iPhone Settings › your name › Sign in with Apple › Baseline › Stop Using."

    /// The confirmation once a profile exists.
    static let message = "Your profile, everything you shared, your friendships and competitions are deleted from the server. Your data on this iPhone stays. Apple asks you to confirm once more."

    /// The confirmation before a name exists: only the sign-in is on the server.
    static let noProfileMessage = "Your sign-in is deleted from Baseline's server; nothing was shared yet. Your data on this iPhone stays. Apple asks you to confirm once more."

    /// The setup sheet closes as soon as the account is gone, so it says up front what the result line would.
    static let setupMessage = "\(noProfileMessage) If Baseline is still listed afterwards: iPhone Settings › your name › Sign in with Apple › Baseline › Stop Using."
}

/// One Off → on change in Settings › Friends & sharing, waiting for its explicit consent.
struct FriendsShareChange: Identifiable, Equatable {
    let metric: FriendsMetric
    let audience: ShareAudience
    var id: String { "\(metric.rawValue).\(audience.rawValue)" }
}

/// Turning a metric on from Off in Settings › Friends & sharing (FRIENDS_SPEC §7.2: Art. 9(2)(a) explicit
/// consent, per metric): the exact form that leaves the phone, the consent paragraph the setup sheet shows,
/// and "I agree". Only agreeing calls `set_share`, which logs `consent_version`; "Not now" leaves the row
/// Off. Moving between two on levels needs no new consent and stays a plain menu choice.
struct FriendsShareConsentSheet: View {
    let change: FriendsShareChange
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                    BaselineCard {
                        Text(Self.question(change))
                            .font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Self.sharedLine(change.metric))
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(FriendsConsent.paragraph)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    BaselineCTA(title: "I agree") { onAgree(); dismiss() }
                        .accessibilityIdentifier("share-consent-agree")
                    BaselineCTA(title: "Not now", prominent: false) { dismiss() }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle("Share \(change.metric.title)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("share-consent")
    }

    /// "Share HRV trend with friends?" / "Share Steps for competitions only?"
    static func question(_ change: FriendsShareChange) -> String {
        switch change.audience {
        case .friends: return "Share \(change.metric.title) with friends?"
        case .competitions: return "Share \(change.metric.title) for competitions only?"
        }
    }

    /// "Shared: weekly HRV change vs your own baseline, e.g. +8 %; never your HRV."
    static func sharedLine(_ metric: FriendsMetric) -> String { "Shared: \(metric.sharedForm)." }
}

/// "See what's on the server" (Art. 15/20): the `my_data` JSON for the signed-in person, pretty-printed, with a
/// share/export button. It is only ever the person's own rows (profile, shares, consent log, uploaded values,
/// friendships by name, hides, blocks, competitions); nothing about anyone else is stored on the phone.
struct FriendsServerDataScreen: View {
    @EnvironmentObject private var store: FriendsStore
    @State private var json: String?
    @State private var failed = false

    var body: some View {
        BaselineScreen(title: "On the server", titleMode: .inline) {
            BaselineCard {
                if let json {
                    Text("Everything Baseline's server holds for you, as stored.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    ShareLink(item: json, preview: SharePreview("Baseline Friends data")) {
                        BaselineCTALabel(title: "Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .baselineCTAStyle(prominent: false)
                    Text(json)
                        .font(BaselineTheme.codeSmall)
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if failed {
                    FriendsErrorLine(error: store.lastError ?? .server)
                    BaselineCTA(title: "Try again", prominent: false) { Task { await load() } }
                } else {
                    ProgressView().tint(BaselineTheme.accent).frame(maxWidth: .infinity)
                }
            }
        }
        .task { if json == nil { await load() } }
    }

    private func load() async {
        failed = false
        store.lastError = nil
        guard let data = await store.myServerData() else { failed = true; return }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            json = text
        } else {
            json = String(data: data, encoding: .utf8) ?? ""
        }
    }
}
#endif
