#if os(iOS)
import SwiftUI

/// "Invite a friend" (`friends-invite`): a fresh single-use code from the server, grouped "ABCD 2345" in
/// `BaselineTheme.code` (fixed-width), when it expires, a `ShareLink` with the code and the join link, and Copy.
/// Codes never carry health data; the friend enters it in their own Friends tab.
struct InviteSheet: View {
    @EnvironmentObject private var store: FriendsStore
    @Environment(\.dismiss) private var dismiss
    @State private var invite: (code: String, expiresAt: Date)?
    @State private var error: FriendsError?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                    BaselineCard(title: "Your invite code") {
                        if let invite {
                            Text(FriendInviteCode.grouped(invite.code))
                                .font(BaselineTheme.code)
                                .foregroundStyle(BaselineTheme.text)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .accessibilityLabel("Code \(invite.code.map(String.init).joined(separator: " "))")
                            Text("Single use · expires \(invite.expiresAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textTertiary)
                            ShareLink(item: FriendInviteCode.shareText(invite.code)) {
                                BaselineCTALabel(title: "Share code", systemImage: "square.and.arrow.up")
                            }
                            .baselineCTAStyle()
                            BaselineCTA(title: copied ? "Copied" : "Copy code", systemImage: "doc.on.doc", prominent: false) {
                                UIPasteboard.general.string = invite.code
                                copied = true
                            }
                        } else if let error {
                            FriendsErrorLine(error: error)
                            BaselineCTA(title: "Try again", prominent: false) { Task { await load() } }
                        } else {
                            HStack(spacing: 10) {
                                ProgressView().tint(BaselineTheme.accent)
                                Text("Making a code…").font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Codes never show your health data. Your friend enters it in Friends, you accept, then you each choose what to share.")
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle("Invite a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("friends-invite")
        .task { if invite == nil { await load() } }
    }

    private func load() async {
        error = nil; store.lastError = nil
        invite = await store.createInvite()
        if invite == nil { error = store.lastError ?? .server }
    }
}
#endif
