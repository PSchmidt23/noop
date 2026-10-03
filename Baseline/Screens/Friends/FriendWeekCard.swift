#if os(iOS)
import SwiftUI

/// One accepted friend's compact week (`friend-row-<name>`), drawn alphabetically by `FriendsScreen`:
/// name and "Updated …", Mon–Sun goal-day dots and seven thin bars for their first shared behaviour
/// metric (against THEIR own goal), a one-line summary of the other shared behaviour metrics, and the
/// neutral physiology pills ("HRV +8 % vs own baseline") only when they share them. No raw heart-rate
/// or HRV value is ever drawn. The whole card opens `FriendDetailScreen`.
struct FriendWeekCard: View {
    let friend: Friend
    var week: [String] = FriendsUI.weekKeys()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Behaviour metrics this friend shows at the Friends level (any day in the overview carries one).
    static func sharedBehaviour(_ friend: Friend) -> [FriendsMetric] { friend.sharedBehaviour }

    static func values(_ friend: Friend, _ metric: FriendsMetric, days: [String]) -> [Int?] {
        let byDay = Dictionary(friend.days.filter { $0.metric == metric }.map { ($0.day, $0.value) },
                               uniquingKeysWith: { a, _ in a })
        return days.map { byDay[$0] }
    }

    private var lead: FriendsMetric? { Self.sharedBehaviour(friend).first }
    private var trends: [TrendShare] { FriendsUI.latestTrends(friend.trends) }
    private var today: String { FriendsUI.today() }

    var body: some View {
        NavigationLink {
            FriendDetailScreen(friendID: friend.id)
        } label: {
            BaselineCard {
                header
                if let lead {
                    let vals = Self.values(friend, lead, days: week)
                    let dots: [Bool?] = zip(week, vals).map { day, v in
                        guard day <= today, let v else { return nil }
                        return FriendsUI.atGoal(lead, value: v, profile: friend.profile)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Text(FriendsUI.chip(lead)).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        Spacer(minLength: 4)
                        FriendsGoalDots(days: dots, color: FriendsUI.color(lead))
                    }
                    FriendsDayBars(values: vals, color: FriendsUI.color(lead),
                                   goal: FriendsUI.dailyGoal(lead, profile: friend.profile), height: 32)
                    let others = Self.sharedBehaviour(friend).dropFirst()
                    if !others.isEmpty {
                        Text(others.map { m in
                            let v = Self.values(friend, m, days: week).compactMap { $0 }
                            return "\(FriendsUI.chip(m)): \(FriendsUI.total(m, v.reduce(0, +), days: v.count))"
                        }.joined(separator: " · "))
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("\(friend.profile.displayName) isn't sharing any activity with friends yet.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !trends.isEmpty {
                    BaselineFlowLayout(spacing: 6) {
                        ForEach(trends, id: \.metric) { FriendsTrendPill(trend: $0) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens \(friend.profile.displayName)'s week")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("friend-row-\(friend.profile.displayName)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            FriendsInitials(name: friend.profile.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.profile.displayName).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                Text(FriendsUI.updated(lastDay: friend.lastDay))
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(BaselineTheme.symbolSmall).foregroundStyle(BaselineTheme.textTertiary)
        }
    }

    /// "Alex, updated today. Steps: 4 of 7 goal days, 48,200 steps this week. HRV +8 % vs own baseline."
    private var accessibilitySummary: String {
        var parts = ["\(friend.profile.displayName), \(FriendsUI.updated(lastDay: friend.lastDay).lowercased())"]
        for m in Self.sharedBehaviour(friend) {
            let vals = Self.values(friend, m, days: week).compactMap { $0 }
            let total = FriendsUI.total(m, vals.reduce(0, +), days: vals.count)
            if m.isDayCount {
                // "Sleep goal: 3 of 5 nights this week": the count is the goal count; no second "of 7".
                parts.append("\(FriendsUI.chip(m)): \(total) this week")
            } else {
                let goalDays = vals.filter { FriendsUI.atGoal(m, value: $0, profile: friend.profile) }.count
                parts.append("\(FriendsUI.chip(m)): \(goalDays) of 7 goal days, \(total) this week")
            }
        }
        parts += trends.map { FriendsBoard.trendPill($0) }
        return parts.joined(separator: ". ")
    }
}
#endif
