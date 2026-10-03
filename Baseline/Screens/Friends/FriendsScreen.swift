#if os(iOS)
import SwiftUI

/// The Friends tab root (the fourth tab, `person.2`). Opt-in: signed out it is the intro
/// (`FriendsIntroView`); right after sign-in the setup sheet takes the name, the 16+ confirmation and the
/// per-metric consent; ready, it is a pinned glass "Friends | Compete" control over the two segments.
///
/// Friends: requests, the leaderboard (behaviour only, head-to-head as % of each person's own goal), then
/// one compact week per friend, ALPHABETICAL (never by value), muted friends folded into "Muted (n)".
/// Compete: invitations, active and finished competitions. Physiology appears only as each person's change
/// against their own baseline, never ranked. Glass budget: the pinned control + the system bars. No rings.
struct FriendsScreen: View {
    @EnvironmentObject private var store: FriendsStore
    @State private var segment: Segment = Segment.initial
    @State private var sheet: ActiveSheet?
    @State private var showMuted = false

    enum Segment: String, CaseIterable, Hashable {
        case friends, compete
        var label: String { self == .friends ? "Friends" : "Compete" }
        /// DEBUG `--friends-segment compete` opens the Compete segment (screenshots).
        static var initial: Segment {
            #if DEBUG
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--friends-segment"), i + 1 < args.count, args[i + 1] == "compete" {
                return .compete
            }
            #endif
            return .friends
        }
    }

    enum ActiveSheet: Identifiable {
        case invite, enterCode(String?), joinPrompt(FriendsStore.JoinPrompt)
        var id: String {
            switch self {
            case .invite: return "invite"
            case .enterCode(let c): return "enter-\(c ?? "")"
            case .joinPrompt(let p): return "join-\(p.code)"
            }
        }
    }

    private var isReady: Bool { store.phase == .ready }
    private var needsSetup: Bool { store.phase == .needsProfile || store.phase == .needsConsent }

    var body: some View {
        Group {
            if isReady, let overview = store.overview {
                readyScreen(overview)
            } else if isReady {
                BaselineScreen(title: "Friends", subtitle: subtitle) {
                    BaselineCard {
                        if let error = store.lastError {
                            FriendsErrorLine(error: error)
                            BaselineCTA(title: "Try again", prominent: false) { Task { await store.refresh() } }
                        } else {
                            ProgressView().tint(BaselineTheme.accent).frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                BaselineScreen(title: "Friends", subtitle: subtitle) {
                    FriendsIntroView()
                }
            }
        }
        .toolbar {
            if isReady && segment == .friends {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { sheet = .invite } label: { Label("Invite a friend", systemImage: "qrcode") }
                        Button { sheet = .enterCode(nil) } label: { Label("Enter a code", systemImage: "keyboard") }
                    } label: {
                        Image(systemName: "person.badge.plus").font(BaselineTheme.symbolAccessory.weight(.medium))
                    }
                    .accessibilityLabel("Add a friend")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                BaselineToolbarLink(systemImage: "gearshape", accessibilityLabel: "Settings") { SettingsScreen() }
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .invite: InviteSheet()
            case .enterCode(let code): EnterCodeSheet(initialCode: code)
            case .joinPrompt(let prompt): EnterCodeSheet(prompt: prompt)
            }
        }
        .sheet(isPresented: Binding(get: { needsSetup }, set: { _ in })) {
            FriendsSetupSheet()
        }
        // Chooses the backend and restores the session (idempotent; also run by the app on activation).
        .task { if store.phase == .ready { await store.refresh() } else { await store.start() } }
        // A join link the store has peeked ("Connect with Sam?"): open the code sheet on that question. The
        // sheet keeps the prompt itself, so the store's copy is cleared at once.
        .onChange(of: store.joinPrompt, initial: true) { _, prompt in
            guard let prompt else { return }
            store.dismissJoin()
            sheet = .joinPrompt(prompt)
        }
    }

    private var subtitle: String? { store.isDemo ? "Demo friends" : nil }

    // MARK: Ready

    private func readyScreen(_ overview: FriendsOverview) -> some View {
        BaselineScreen(title: "Friends", titleMode: .inline, subtitle: subtitle, pinned: {
            BaselineSegmentedPicker(options: Segment.allCases, selection: $segment, label: { $0.label },
                                    groupLabel: "Section", style: .glass)
        }) {
            switch segment {
            case .friends: friendsSegment(overview)
            case .compete: CompeteSection(overview: overview)
            }
        }
        .refreshable { await store.refresh() }
    }

    @ViewBuilder private func friendsSegment(_ overview: FriendsOverview) -> some View {
        Group {
            if !overview.incoming.isEmpty || !overview.outgoing.isEmpty {
                FriendsRequestsCard(incoming: overview.incoming, outgoing: overview.outgoing)
            }
            if overview.accepted.isEmpty {
                emptyFriends
            } else {
                LeaderboardCard(overview: overview)
                let cards = FriendsBoard.friendCards(overview, muted: store.muted)
                BaselineSectionLabel(text: "This week")
                ForEach(cards.visible) { FriendWeekCard(friend: $0) }
                if !cards.muted.isEmpty {
                    BaselineCard {
                        DisclosureGroup(isExpanded: $showMuted) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(cards.muted.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { SettingsDivider() }
                                    NavigationLink { FriendDetailScreen(friendID: f.id) } label: {
                                        HStack(spacing: 12) {
                                            FriendsInitials(name: f.name)
                                            Text(f.name).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                                            Spacer(minLength: 8)
                                            SettingsChevron()
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Muted (\(cards.muted.count))").font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
                        }
                        .tint(BaselineTheme.textTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends-list")
    }

    private var emptyFriends: some View {
        BaselineCard {
            BaselineEmptyState(icon: "person.2", title: "Invite a friend",
                               message: "They'll get a code to enter in Baseline. You both choose what to share.")
            HStack(spacing: 10) {
                BaselineCTA(title: "Invite") { sheet = .invite }
                BaselineCTA(title: "Enter code", prominent: false) { sheet = .enterCode(nil) }
            }
        }
    }
}
#endif
