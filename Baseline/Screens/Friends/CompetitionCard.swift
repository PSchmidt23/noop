#if os(iOS)
import SwiftUI

/// One competition in the Compete segment (`competition-card`): the generated title, the one-line rule,
/// your place, the top three as flat bars, and "3 days left" / "Final on Wed 15 Oct" / a "Final" pill.
/// The standings come from the server (`competition_standings`) through the store; this view never
/// scores anything. Tapping opens `CompetitionDetailScreen`.
struct CompetitionCard: View {
    let competition: CompetitionSummary
    @EnvironmentObject private var store: FriendsStore
    @State private var standings: CompetitionStandings?

    var body: some View {
        NavigationLink {
            CompetitionDetailScreen(competitionID: competition.id)
        } label: {
            BaselineCard {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(competition.title).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Self.modeLine(competition.mode, metric: competition.metric))
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    }
                    Spacer(minLength: 8)
                    if competition.isFinal {
                        BaselinePill(text: "Final", color: BaselineTheme.textTertiary)
                    } else {
                        Image(systemName: "chevron.right").font(BaselineTheme.symbolSmall)
                            .foregroundStyle(BaselineTheme.textTertiary)
                    }
                }
                if let standings {
                    if let headline = Self.placeLine(standings, me: store.overview?.me.id) {
                        Text(headline).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                    }
                    CompetitionTopBars(rows: FriendsScoring.sortStandings(standings.rows), me: store.overview?.me.id,
                                       metric: competition.metric, mode: competition.mode, limit: 3)
                }
                Text(Self.status(competition))
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("competition-card")
        .task(id: competition.id) {
            standings = await store.standings(competition.id)
        }
    }

    // MARK: Words

    /// "% of own goal", "Total", "Days at goal" with the metric where it reads better.
    static func modeLine(_ mode: CompetitionMode, metric: FriendsMetric) -> String {
        "\(mode.title) · \(metric.title)"
    }

    /// "Day 4 of 7 · 3 days left", "Starts Mon 13 Oct", "Final on Wed 15 Oct", "Final".
    static func status(_ c: CompetitionSummary, now: Date = Date()) -> String {
        if c.isFinal { return "Final" }
        let today = FriendsUI.today(now)
        if c.isUpcoming(today: today) { return "Starts \(FriendsUI.shortDay(c.start))" }
        guard let dayText = c.dayText(today: today) else {
            return "Final on \(FriendsDates.shortDate(c.freezeAt))"
        }
        let left = c.daysLeft(today: today) - 1   // daysLeft counts today
        let leftText = left <= 0 ? "last day" : (left == 1 ? "1 day left" : "\(left) days left")
        return "\(dayText) · \(leftText)"
    }

    /// "You're 2nd of 4", "Tied 1st of 4", "You're 1st of 4"; nil when you are not placed.
    static func placeLine(_ s: CompetitionStandings, me: UUID?) -> String? {
        let placed = s.rows.filter { $0.place != nil }
        guard let me, let mine = placed.first(where: { $0.userID == me }), let place = mine.place else { return nil }
        let tied = placed.filter { $0.place == place }.count > 1
        let prefix = s.isFinal ? (tied ? "Tied \(FriendsScoring.ordinal(place))" : "You finished \(FriendsScoring.ordinal(place))")
                               : (tied ? "Tied \(FriendsScoring.ordinal(place))" : "You're \(FriendsScoring.ordinal(place))")
        return "\(prefix) of \(placed.count)"
    }

    /// The score as printed: "1,240 points", "52,310 steps", "5 days".
    static func scoreText(_ score: Int?, metric: FriendsMetric, mode: CompetitionMode) -> String {
        guard let score else { return "Not sharing" }
        switch mode {
        case .goalPercent: return "\(FriendsUI.number(score)) points"
        case .daysAtGoal: return score == 1 ? "1 day" : "\(score) days"
        case .total:
            switch metric {
            case .steps: return "\(FriendsUI.number(score)) steps"
            case .intensity: return "\(FriendsUI.number(score)) min"
            case .sleepGoal, .bedtime: return score == 1 ? "1 night" : "\(score) nights"
            default: return score == 1 ? "1 day" : "\(score) days"
            }
        }
    }
}

/// Flat standings bars: place ("1st", "=2nd"), initials, name ("You" bold on an accent @ 0.14 row), a bar,
/// the score. `rows` is the FULL standings, so a tie that straddles the `limit` (3rd and 4th on the card)
/// still prints "=3rd". One combined accessibility element per row ("Sam, tied 2nd, 840 points"); at
/// accessibility sizes the value stacks under the name.
struct CompetitionTopBars: View {
    let rows: [Standing]
    let me: UUID?
    let metric: FriendsMetric
    let mode: CompetitionMode
    /// How many rows to draw (the card shows 3); nil draws them all.
    var limit: Int? = nil

    var body: some View {
        let shown = limit.map { Array(rows.prefix($0)) } ?? rows
        let top = Double(rows.compactMap(\.score).max() ?? 0)
        VStack(spacing: 6) {
            ForEach(shown) { r in
                let name = r.userID == me ? "You" : r.name
                let value = r.state == .left ? "Left" : CompetitionCard.scoreText(r.score, metric: metric, mode: mode)
                FriendsBoardRow(place: Self.placeText(r, in: rows), name: name,
                                isMe: r.userID == me,
                                fraction: top > 0 ? Double(r.score ?? 0) / top : 0,
                                value: value,
                                color: FriendsUI.color(metric), dimmed: r.score == nil || r.state == .left,
                                accessibilityText: [name, Self.placeSpoken(r, in: rows), value].compactMap { $0 }
                                    .joined(separator: ", "))
            }
        }
    }

    /// "1st", "=2nd", or "–" when unplaced; ties are counted across `rows` (pass the full standings).
    static func placeText(_ r: Standing, in rows: [Standing]) -> String {
        guard let p = r.place else { return "–" }
        return FriendsScoring.placeText(p, tied: rows.filter { $0.place == p }.count > 1)
    }

    /// "2nd", "tied 2nd", or nil when unplaced (the value already says "Left" / "Not sharing").
    static func placeSpoken(_ r: Standing, in rows: [Standing]) -> String? {
        guard let p = r.place else { return nil }
        return FriendsScoring.placeSpoken(p, tied: rows.filter { $0.place == p }.count > 1)
    }
}

/// One leaderboard / standings row. Shared by the Friends leaderboard and the competition standings.
struct FriendsBoardRow: View {
    let place: String?
    let name: String
    let isMe: Bool
    let fraction: Double
    let value: String
    let color: Color
    var dimmed = false
    var accessibilityText: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let place {
                    // A hidden "=00th" sizes the column, so "1st" and "=2nd" line their names up at any type size.
                    ZStack(alignment: .leading) {
                        Text("=00th").hidden()
                        Text(place).foregroundStyle(BaselineTheme.textSecondary)
                    }
                    .font(BaselineTheme.label).monospacedDigit()
                }
                FriendsInitials(name: name, highlighted: isMe)
                Text(name)
                    .font(isMe ? BaselineTheme.label.weight(.bold) : BaselineTheme.label)
                    .foregroundStyle(dimmed ? BaselineTheme.textTertiary : BaselineTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if !dynamicTypeSize.isAccessibilitySize { valueText }
            }
            if dynamicTypeSize.isAccessibilitySize { valueText }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BaselineTheme.ringTrack)
                    Capsule().fill(dimmed ? BaselineTheme.inactive : color.opacity(BaselineChartStyle.barOpacity))
                        .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isMe ? BaselineTheme.accent.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? [name, place.map { "place \($0)" }, value].compactMap { $0 }.joined(separator: ", "))
    }

    private var valueText: some View {
        Text(value).font(BaselineTheme.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(dimmed ? BaselineTheme.textTertiary : BaselineTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
