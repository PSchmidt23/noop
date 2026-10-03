#if os(iOS)
import SwiftUI

/// "New competition" (`compete-create`): one of the five behaviour metrics (never HRV, resting HR or
/// readiness), a scoring mode with its one-line explanation (% of own goal is the default: fair across
/// different goals), when (This week / Next week / Weekdays / Weekend / Custom ≤ 31 days), and up to nine
/// accepted friends. A summary sentence says the whole thing before Create. Creating on a metric the
/// person does not share yet first asks to share it for competitions only.
struct CreateCompetitionSheet: View {
    @EnvironmentObject private var store: FriendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var metric: FriendsMetric = .steps
    @State private var mode: CompetitionMode = .goalPercent
    @State private var when: When = .nextWeek
    @State private var customStart = Date()
    @State private var customEnd = Date().addingTimeInterval(6 * 86_400)
    @State private var invitees: Set<UUID> = []
    @State private var error: FriendsError?
    @State private var busy = false
    @State private var askConsent = false

    var initialInvitees: Set<UUID> = []

    enum When: String, CaseIterable, Identifiable {
        case thisWeek, nextWeek, weekdays, weekend, custom
        var id: Self { self }
        var title: String {
            switch self {
            case .thisWeek: return "This week"
            case .nextWeek: return "Next week"
            case .weekdays: return "Weekdays"
            case .weekend: return "Weekend"
            case .custom: return "Custom"
            }
        }
    }

    /// The start and end day keys for a choice. The server accepts a start from yesterday up to 30 days
    /// ahead, so "This week" starts today when Monday is further back than yesterday.
    static func window(_ when: When, today: String, customStart: String, customEnd: String) -> (start: String, end: String) {
        let monday = FriendsDates.monday(of: today)
        let nextMonday = FriendsDates.adding(7, to: monday)
        switch when {
        case .thisWeek:
            let start = FriendsDates.distance(from: monday, to: today) > 1 ? today : monday
            return (start, FriendsDates.adding(6, to: monday))
        case .nextWeek:
            return (nextMonday, FriendsDates.adding(6, to: nextMonday))
        case .weekdays:
            // This week's Mon–Fri while it can still start (Monday or Tuesday), else next week's.
            let base = FriendsDates.distance(from: monday, to: today) <= 1 ? monday : nextMonday
            return (base, FriendsDates.adding(4, to: base))
        case .weekend:
            // The coming Saturday–Sunday (this one while it is still Saturday or Sunday).
            let saturday = FriendsDates.adding(5, to: monday)
            let base = FriendsDates.distance(from: saturday, to: today) <= 1 ? saturday : FriendsDates.adding(7, to: saturday)
            return (base, FriendsDates.adding(1, to: base))
        case .custom:
            return (customStart, max(customStart, customEnd))
        }
    }

    private var today: String { FriendsUI.today() }
    private var window: (start: String, end: String) {
        Self.window(when, today: today, customStart: FriendsDates.localKey(customStart),
                    customEnd: FriendsDates.localKey(customEnd))
    }
    private var length: Int { FriendsDates.distance(from: window.start, to: window.end) + 1 }
    private var windowValid: Bool {
        length >= 1 && length <= 31
            && FriendsDates.distance(from: today, to: window.start) >= -1
            && FriendsDates.distance(from: today, to: window.start) <= 30
    }
    private var friends: [Friend] {
        (store.overview?.accepted ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var canCreate: Bool { windowValid && !invitees.isEmpty && invitees.count <= 9 && !busy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                    metricCard
                    modeCard
                    whenCard
                    whoCard
                    summaryCard
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle("New competition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(!canCreate)
                }
            }
            .sheet(isPresented: $askConsent) {
                CompetitionsOnlyConsentSheet(metric: metric) {
                    Task {
                        store.lastError = nil
                        if await store.setShare(metric, audience: .competitions) {
                            await submit()
                        } else {
                            error = store.lastError ?? .server
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("compete-create")
        .onAppear { if invitees.isEmpty { invitees = initialInvitees } }
    }

    // MARK: Cards

    private var metricCard: some View {
        BaselineCard(title: "What") {
            BaselineFlowLayout(spacing: 8) {
                ForEach(FriendsMetric.behaviour) { m in
                    FriendsChoiceChip(title: m.title, selected: metric == m, systemImage: FriendsUI.symbol(m)) {
                        metric = m
                        if !CompetitionMode.allowed(for: m).contains(mode) { mode = CompetitionMode.allowed(for: m).first ?? .total }
                    }
                }
            }
            Text("HRV, resting HR and readiness are never competed on.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        }
    }

    private var modeCard: some View {
        BaselineCard(title: "Scoring") {
            let modes = CompetitionMode.allowed(for: metric)
            if modes.count > 1 {
                BaselineFlowLayout(spacing: 8) {
                    ForEach(modes, id: \.self) { m in
                        FriendsChoiceChip(title: m.title, selected: mode == m) { mode = m }
                    }
                }
            }
            Text(mode.explanation(for: metric))
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whenCard: some View {
        BaselineCard(title: "When") {
            BaselineFlowLayout(spacing: 8) {
                ForEach(When.allCases) { w in
                    FriendsChoiceChip(title: w.title, selected: when == w) { when = w }
                }
            }
            if when == .custom {
                DatePicker("Starts", selection: $customStart,
                           in: Date().addingTimeInterval(-86_400)...Date().addingTimeInterval(30 * 86_400),
                           displayedComponents: .date)
                    .font(BaselineTheme.body)
                DatePicker("Ends", selection: $customEnd,
                           in: customStart...customStart.addingTimeInterval(30 * 86_400),
                           displayedComponents: .date)
                    .font(BaselineTheme.body)
            }
            Text(windowValid ? "\(FriendsUI.range(window.start, window.end)) · \(length) day\(length == 1 ? "" : "s")"
                             : FriendsError.invalidWindow.message)
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        }
        .tint(BaselineTheme.accent)
    }

    @ViewBuilder private var whoCard: some View {
        BaselineCard(title: "Who") {
            if friends.isEmpty {
                Text("Add a friend first: competitions are between accepted friends.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            }
            ForEach(Array(friends.enumerated()), id: \.element.id) { i, f in
                if i > 0 { SettingsDivider() }
                Button {
                    if invitees.contains(f.id) { invitees.remove(f.id) }
                    else if invitees.count < 9 { invitees.insert(f.id) }
                } label: {
                    HStack(spacing: 12) {
                        FriendsInitials(name: f.name)
                        Text(f.name).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                        Spacer(minLength: 8)
                        Image(systemName: invitees.contains(f.id) ? "checkmark.circle.fill" : "circle")
                            .font(BaselineTheme.symbolAccessory)
                            .foregroundStyle(invitees.contains(f.id) ? BaselineTheme.accent : BaselineTheme.inactive)
                            .accessibilityHidden(true)   // the isSelected trait carries the state
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(invitees.contains(f.id) ? .isSelected : [])
            }
            Text("Up to 9 friends. They'll see your score in this competition only.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryCard: some View {
        BaselineCard {
            Text("\(metric.title) · \(mode.title) · \(FriendsUI.range(window.start, window.end)), each in your own time zone · goals lock when you join.")
                .font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            if store.overview?.myShares[metric] == nil {
                Text("You don't share \(metric.title) yet. Creating asks to share it for competitions only.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FriendsErrorLine(error: error)
            BaselineCTA(title: busy ? "Creating…" : "Create competition") { create() }
                .disabled(!canCreate)
        }
    }

    // MARK: Actions

    private func create() {
        if store.overview?.myShares[metric] == nil { askConsent = true; return }
        Task { await submit() }
    }

    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        let w = window
        let draft = CompetitionDraft(metric: metric, mode: mode, start: w.start, end: w.end, invitees: Array(invitees))
        store.lastError = nil
        if await store.createCompetition(draft) != nil {
            dismiss()
        } else {
            error = store.lastError ?? .server
        }
    }
}
#endif
