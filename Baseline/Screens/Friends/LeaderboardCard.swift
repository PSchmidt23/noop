#if os(iOS)
import SwiftUI

/// The Friends leaderboard (`friends-leaderboard`). Behaviour only, head-to-head: chips for the metrics
/// you and at least one friend share at the Friends level (Steps, Intensity minutes, Active days, Sleep
/// goal, Bedtime consistency), "This week | 4 weeks", and for Steps "% of own goal | Total" (% of each
/// person's OWN goal by default, so different goals compete fairly). The headline names only the person
/// directly above you. Ranking comes from `FriendsBoard`; this view only draws it.
///
/// HRV, resting HR and readiness never appear here, not even unranked: one person's heart rate or HRV
/// means nothing next to another's, so each friend's change against their OWN baseline lives only on
/// their alphabetical `FriendWeekCard` and `FriendDetailScreen`. With only physiology shared, this card is
/// the empty state. With Competitive view off (Settings › Friends & sharing) the board is alphabetical
/// with no places and no headline.
struct LeaderboardCard: View {
    let overview: FriendsOverview
    @EnvironmentObject private var store: FriendsStore
    @State private var metricRaw = FriendsMetric.steps.rawValue
    @State private var window: FriendsBoard.Window = .week
    @State private var scoring: FriendsBoard.Scoring = .goalPercent

    private var metrics: [FriendsMetric] { FriendsBoard.boardMetrics(overview: overview) }
    private var selected: FriendsMetric? {
        metrics.first { $0.rawValue == metricRaw } ?? metrics.first
    }

    var body: some View {
        BaselineCard(title: "Leaderboard") {
            if let metric = selected {
                chips
                board(metric)
            } else {
                emptyBoard
            }
        }
        .accessibilityIdentifier("friends-leaderboard")
    }

    // MARK: Pieces

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(metrics) { m in
                    FriendsChoiceChip(title: FriendsUI.chip(m), selected: selected == m,
                                      systemImage: FriendsUI.symbol(m)) {
                        metricRaw = m.rawValue
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder private func board(_ metric: FriendsMetric) -> some View {
        let b = FriendsBoard.board(metric: metric, scoring: scoring, window: window, today: FriendsUI.today(),
                                   overview: overview, competitive: store.competitiveView, muted: store.muted)
        BaselineSegmentedPicker(options: FriendsBoard.Window.allCases, selection: $window,
                                label: { $0.title }, groupLabel: "Window", style: .flat)
        if metric == .steps {
            BaselineSegmentedPicker(options: FriendsBoard.Scoring.allCases, selection: $scoring,
                                    label: { $0.title }, groupLabel: "Scoring", style: .flat)
        }
        if let headline = b.headline {
            Text(headline).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: 6) {
            ForEach(b.rows) { r in
                FriendsBoardRow(place: r.placeText, name: r.name, isMe: r.isMe, fraction: r.fraction,
                                value: r.valueText, color: FriendsUI.color(metric),
                                accessibilityText: r.accessibilityText)
            }
        }
        if !b.meIncluded {
            BaselineChevronRow(text: "Share \(metric.title) with friends to appear here",
                               systemImage: "person.2", accessibilityHint: "Opens Friends & sharing") {
                FriendsSharingScreen()
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(FriendsBoard.Board.rankingCaption)
            if let n = b.nonSharersText { Text(n) }
        }
        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A leaderboard appears once you and a friend both share the same activity with friends.")
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            BaselineChevronRow(text: "Choose what you share", systemImage: "slider.horizontal.3",
                               accessibilityHint: "Opens Friends & sharing") { FriendsSharingScreen() }
            Text(FriendsBoard.Board.rankingCaption)
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
