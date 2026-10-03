#if os(iOS)
import SwiftUI

/// "Enter a code" (`friends-enter-code`): 8 characters, auto-uppercased, dashes and spaces ignored. The
/// peek asks "Connect with Sam?" (nothing changes on the server yet); Connect sends the request, which
/// the inviter accepts. A `baseline://friends/join/CODE` link is peeked by the store once the person is
/// ready (`FriendsStore.joinPrompt`); `FriendsScreen` then opens this sheet straight on the question.
struct EnterCodeSheet: View {
    @EnvironmentObject private var store: FriendsStore
    @Environment(\.dismiss) private var dismiss
    @State private var raw: String
    @State private var peeked: (code: String, name: String)?
    @State private var sentTo: String?
    @State private var error: FriendsError?
    @State private var busy = false
    @FocusState private var focused: Bool

    init(initialCode: String? = nil, prompt: FriendsStore.JoinPrompt? = nil) {
        _raw = State(initialValue: prompt?.code ?? initialCode ?? "")
        _peeked = State(initialValue: prompt.map { (code: $0.code, name: $0.name) })
    }

    private var normalized: String? { FriendInviteCode.normalize(raw) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                    if let sentTo {
                        BaselineCard {
                            BaselineEmptyState(icon: "paperplane", title: "Request sent to \(sentTo).",
                                               message: "You'll see each other once \(sentTo) accepts. Nothing is shared until you each turn it on.")
                            BaselineCTA(title: "Done") { dismiss() }
                        }
                    } else if let peeked {
                        BaselineCard {
                            Text("Connect with \(peeked.name)?")
                                .font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                            Text("\(peeked.name) accepts before either of you sees anything, and only what each of you shares.")
                                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            FriendsErrorLine(error: error)
                            BaselineCTA(title: "Connect") { Task { await redeem(peeked) } }
                                .disabled(busy)
                            BaselineCTA(title: "Not now", prominent: false) { dismiss() }
                        }
                    } else {
                        BaselineCard(title: "Friend's code") {
                            TextField("ABCD 2345", text: $raw)
                                .font(BaselineTheme.codeField)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($focused)
                                .submitLabel(.go)
                                .onSubmit { Task { await peek() } }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(BaselineTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(BaselineTheme.hairline, lineWidth: 1))
                                .onChange(of: raw) { _, new in
                                    let up = new.uppercased()
                                    if up != new { raw = up }
                                    error = nil
                                }
                                .accessibilityLabel("Friend's code")
                            Text("8 letters and numbers. Spaces and dashes don't matter.")
                                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                            FriendsErrorLine(error: error)
                            BaselineCTA(title: busy ? "Checking…" : "Continue") { Task { await peek() } }
                                .disabled(normalized == nil || busy)
                        }
                    }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle("Enter a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .accessibilityIdentifier("friends-enter-code")
        .task {
            // A link handed us a full code: peek straight away.
            if normalized != nil, peeked == nil { await peek() } else { focused = true }
        }
    }

    private func peek() async {
        guard normalized != nil else { error = .inviteInvalid; return }
        busy = true; store.lastError = nil
        defer { busy = false }
        if let found = await store.peek(code: raw) {
            peeked = (found.code, found.name)
        } else {
            error = store.lastError ?? .inviteInvalid
        }
    }

    private func redeem(_ p: (code: String, name: String)) async {
        busy = true; store.lastError = nil
        defer { busy = false }
        if let name = await store.redeem(code: p.code) {
            sentTo = name
        } else {
            error = store.lastError ?? .server
        }
    }
}
#endif
