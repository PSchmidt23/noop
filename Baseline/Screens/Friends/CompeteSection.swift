#if os(iOS)
import SwiftUI

/// The Compete segment (`compete-list`): "New competition", invitations (Join / Decline; joining a metric
/// you don't share yet first asks to share it for competitions only), active competitions, and finished
/// ones from the last 90 days with a "Final" pill (Rematch lives on the detail). Competitions are on
/// behaviour only: steps, intensity minutes, active days, nights at your sleep goal, on-time bedtimes.
struct CompeteSection: View {
    let overview: FriendsOverview
    @EnvironmentObject private var store: FriendsStore
    @State private var showCreate = false
    @State private var consentFor: (competition: UUID, metric: FriendsMetric)?
    @State private var error: FriendsError?

    private var today: String { FriendsUI.today() }
    private var invitations: [CompetitionSummary] {
        store.competitions.filter { $0.myState == .invited && !$0.isFinal }.sorted { $0.start < $1.start }
    }
    private var active: [CompetitionSummary] {
        store.competitions.filter { !$0.isFinal && ($0.myState == .joined || $0.myState == .left) }.sorted { $0.start < $1.start }
    }
    private var finished: [CompetitionSummary] {
        store.competitions.filter { $0.isFinal && $0.myState != .declined && $0.myState != .removed }.sorted { $0.end > $1.end }
    }

    var body: some View {
        Group {
            BaselineCTA(title: "New competition", systemImage: "flag.checkered") { showCreate = true }
                .accessibilityIdentifier("compete-new")
                .disabled(overview.accepted.isEmpty)
            if overview.accepted.isEmpty {
                Text("Add a friend first: competitions are between accepted friends.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .padding(.horizontal, 4)
            }
            FriendsErrorLine(error: error)

            if !invitations.isEmpty {
                BaselineSectionLabel(text: "Invitations")
                ForEach(invitations) { c in invitationCard(c) }
            }
            if !active.isEmpty {
                BaselineSectionLabel(text: "Active")
                ForEach(active) { CompetitionCard(competition: $0) }
            }
            if !finished.isEmpty {
                BaselineSectionLabel(text: "Finished")
                ForEach(finished) { CompetitionCard(competition: $0) }
            }
            if invitations.isEmpty && active.isEmpty && finished.isEmpty {
                BaselineCard {
                    BaselineEmptyState(icon: "flag.checkered", title: "No competitions yet",
                                       message: "Start one on steps, intensity minutes, active days, sleep goal or bedtimes. Scoring is % of each person's own goal by default, so different goals compete fairly.")
                }
            }
            Text("Competitions use what you do. HRV, resting HR and readiness are never part of one.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compete-list")
        .sheet(isPresented: $showCreate) { CreateCompetitionSheet() }
        .sheet(isPresented: Binding(get: { consentFor != nil }, set: { if !$0 { consentFor = nil } })) {
            if let c = consentFor {
                CompetitionsOnlyConsentSheet(metric: c.metric) {
                    act {
                        if await store.setShare(c.metric, audience: .competitions) {
                            _ = await store.respondCompetition(c.competition, accept: true)
                        }
                    }
                }
            }
        }
    }

    private func invitationCard(_ c: CompetitionSummary) -> some View {
        let from = c.members.first { $0.userID == c.createdBy }?.name ?? "A friend"
        return BaselineCard {
            NavigationLink { CompetitionDetailScreen(competitionID: c.id) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(from) invited you · \(c.metric.title) · \(FriendsUI.range(c.start, c.end))")
                        .font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    SettingsChevron()
                }
            }
            .buttonStyle(.plain)
            Text(c.mode.explanation(for: c.metric))
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                BaselineCTA(title: "Join") {
                    if overview.myShares[c.metric] == nil { consentFor = (c.id, c.metric) }
                    else { act { _ = await store.respondCompetition(c.id, accept: true) } }
                }
                BaselineCTA(title: "Decline", prominent: false) {
                    act { _ = await store.respondCompetition(c.id, accept: false) }
                }
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
#endif
