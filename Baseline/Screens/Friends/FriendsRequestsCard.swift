#if os(iOS)
import SwiftUI

/// Pending friend requests (only drawn when there are any): "Chris wants to connect" with Accept /
/// Decline and a "…" menu (Report…, Block), and "Waiting for Casey to accept" with Cancel (which withdraws
/// the request). The sender's name is the one thing a stranger with a leaked code controls, so it can be
/// reported and blocked right here (App Store 1.2): the server accepts `report_user` while the request is
/// pending (a pending row counts in `knows()`, a declined one does not), and `block_user` removes the
/// request and stops that person sending another.
struct FriendsRequestsCard: View {
    @EnvironmentObject private var store: FriendsStore
    let incoming: [Friend]
    let outgoing: [Friend]
    @State private var error: FriendsError?
    @State private var reporting: Friend?
    @State private var blocking: Friend?
    @State private var reported: Set<UUID> = []

    var body: some View {
        BaselineCard(title: "Requests") {
            ForEach(Array(incoming.enumerated()), id: \.element.id) { i, f in
                if i > 0 { SettingsDivider() }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            FriendsInitials(name: f.profile.displayName)
                            Text("\(f.profile.displayName) wants to connect")
                                .font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 8)
                        moreMenu(f)
                    }
                    HStack(spacing: 10) {
                        BaselineCTA(title: "Accept") { act { await store.respondFriend(f.id, accept: true) } }
                            .accessibilityLabel("Accept \(f.profile.displayName)")
                        BaselineCTA(title: "Decline", prominent: false) { act { await store.respondFriend(f.id, accept: false) } }
                            .accessibilityLabel("Decline \(f.profile.displayName)")
                    }
                }
            }
            if !incoming.isEmpty && !outgoing.isEmpty { SettingsDivider() }
            ForEach(Array(outgoing.enumerated()), id: \.element.id) { i, f in
                if i > 0 { SettingsDivider() }
                HStack(spacing: 12) {
                    FriendsInitials(name: f.profile.displayName)
                    Text("Waiting for \(f.profile.displayName) to accept")
                        .font(BaselineTheme.body).foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Cancel") { act { await store.removeFriend(f.id) } }
                        .font(BaselineTheme.label)
                        .tint(BaselineTheme.accent)
                        .accessibilityLabel("Cancel request to \(f.profile.displayName)")
                }
            }
            FriendsErrorLine(error: error)
            Text("Accepting shows each of you only what the other has chosen to share.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Report \(reporting?.profile.displayName ?? "")?",
                            isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                            titleVisibility: .visible, presenting: reporting) { f in
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.title) {
                    act { if await store.report(f.id, reason: reason, competition: nil) { reported.insert(f.id) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Reports go to Baseline's developer. Nothing you write is sent; only the reason. The request stays until you decline or block it.")
        }
        .confirmationDialog("Block \(blocking?.profile.displayName ?? "")?",
                            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                            titleVisibility: .visible, presenting: blocking) { f in
            Button("Block", role: .destructive) { act { await store.block(f.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Their request is removed and they can't send you a request again. Report first if the name is the problem.")
        }
    }

    /// "…" on an incoming request: Report… (before any decline, while the server still knows the request)
    /// and Block.
    private func moreMenu(_ f: Friend) -> some View {
        let done = reported.contains(f.id)
        return Menu {
            Button { reporting = f } label: { Label(done ? "Reported" : "Report…", systemImage: "flag") }
                .disabled(done)
            Button(role: .destructive) { blocking = f } label: { Label("Block", systemImage: "hand.raised") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(BaselineTheme.symbolAccessory.weight(.medium))
                .foregroundStyle(BaselineTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(f.profile.displayName)")
        .accessibilityHint("Report or block")
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
#endif
