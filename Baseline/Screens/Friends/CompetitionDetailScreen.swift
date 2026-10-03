#if os(iOS)
import SwiftUI

/// One competition (`competition-standings`): the rule in one line, the standings (grey "Not sharing" /
/// "Left"; while only invited, or after leaving a running one, who is taking part and no scores), "Your days" bars with a capped mark (labelled in the rule's own unit, see `YourDays`), the rules
/// card (your locked goal, own day in own time zone, "Results become final on Wed 15 Oct"), the status
/// ("Day 4 of 7" → "Final on Wed 15 Oct" → "Final"), and the actions:
/// Join / Decline while invited, Leave, Remove a participant (creator only), Report, Rematch once final.
/// Scores come from the server (or the demo backend's `FriendsScoring`); nothing is computed here.
struct CompetitionDetailScreen: View {
    let competitionID: UUID
    @EnvironmentObject private var store: FriendsStore
    @Environment(\.dismiss) private var dismiss
    @State private var standings: CompetitionStandings?
    @State private var error: FriendsError?
    @State private var confirmLeave = false
    @State private var removing: CompetitionMember?
    @State private var reporting: CompetitionMember?
    @State private var showReportPicker = false
    @State private var consentFor: FriendsMetric?
    @State private var rematched = false

    private var summary: CompetitionSummary? {
        standings?.summary ?? store.competitions.first { $0.id == competitionID }
    }
    private var me: UUID? { store.overview?.me.id }

    var body: some View {
        BaselineScreen(title: summary?.title ?? "Competition", titleMode: .inline) {
            if let summary {
                content(summary)
            } else if let error {
                BaselineCard { FriendsErrorLine(error: error) }
            } else {
                BaselineCard { ProgressView().tint(BaselineTheme.accent).frame(maxWidth: .infinity) }
            }
        }
        .accessibilityIdentifier("competition-standings")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Leave this competition?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { act(pop: true) { await store.leaveCompetition(competitionID) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your score stays visible as “Left” and is no longer ranked.")
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { r in
            Button("Remove", role: .destructive) { act { await store.removeParticipant(competitionID, user: r.userID) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Report \(reporting?.name ?? "")?", isPresented: $showReportPicker, titleVisibility: .visible,
                            presenting: reporting) { r in
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.title) {
                    act { await store.report(r.userID, reason: reason, competition: competitionID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $consentFor) { metric in
            CompetitionsOnlyConsentSheet(metric: metric) {
                act {
                    if await store.setShare(metric, audience: .competitions) {
                        _ = await store.respondCompetition(competitionID, accept: true)
                    }
                }
            }
        }
    }

    private func load() async {
        store.lastError = nil
        if let s = await store.standings(competitionID) {
            standings = s
            error = nil
        } else {
            error = store.lastError ?? .notFound
        }
    }

    // MARK: Content

    @ViewBuilder private func content(_ c: CompetitionSummary) -> some View {
        BaselineCard {
            Text(FriendsScoring.ruleText(metric: c.metric, mode: c.mode) + ".").font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            // The dates are the bar title already ("Steps · Mon 28 Sep – Sun 4 Oct"); the pill alone, so
            // "Day 5 of 7 · 2 days left" never truncates beside a second copy of them.
            BaselinePill(text: CompetitionCard.status(c), color: c.isFinal ? BaselineTheme.textTertiary : BaselineTheme.accent)
        }

        if c.myState == .invited {
            BaselineCard(title: "Invitation") {
                Text("\(creatorName(c)) invited you.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    BaselineCTA(title: "Join") { join(c) }
                    BaselineCTA(title: "Decline", prominent: false) { act(pop: true) { _ = await store.respondCompetition(c.id, accept: false) } }
                }
            }
        }

        if let s = standings {
            if s.rows.isEmpty {
                // competition_standings sends no scores to someone invited, or who left while it runs: the roster only.
                BaselineCard(title: "Taking part") {
                    Text(Self.rosterText(c.members, me: me))
                        .font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.noScoresText(c))
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                BaselineCard(title: "Standings") {
                    if let line = CompetitionCard.placeLine(s, me: me) {
                        Text(line).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                    }
                    CompetitionTopBars(rows: FriendsScoring.sortStandings(s.rows), me: me, metric: c.metric, mode: c.mode)
                    if c.metric == .steps && c.mode == .total {
                        let mixes = s.rows.compactMap { r in
                            r.sourceMix.map { "\(r.userID == me ? "You" : r.name), \(Self.sourceText($0))" }
                        }
                        if !mixes.isEmpty {
                            Text("Counted by: " + mixes.joined(separator: " · "))
                                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !s.myDays.isEmpty {
                let days = YourDays(s.myDays, metric: c.metric, mode: c.mode, profile: store.overview?.me)
                BaselineCard(title: "Your days") {
                    FriendsDayBars(values: days.bars, color: FriendsUI.color(c.metric), goal: days.goal, height: 56,
                                   capped: Set(s.myDays.enumerated().compactMap { $0.element.capped ? $0.offset : nil }))
                    HStack(spacing: 0) {
                        ForEach(s.myDays, id: \.day) { d in
                            Text(FriendsUI.weekdayLetter(d.day)).font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textTertiary).frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                    Text(days.caption)
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your days")
                .accessibilityValue(days.spoken)
            }
        }

        BaselineCard(title: "Rules") {
            Text(rulesLine(c)).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        actions(c)
        FriendsErrorLine(error: error)
    }

    @ViewBuilder private func actions(_ c: CompetitionSummary) -> some View {
        // From the roster, not the scored rows: an invited person (or one who left) gets no rows but can still report,
        // and the creator can remove someone who has not answered yet.
        let others = c.members.filter { $0.userID != me }
        let removable = others.filter { $0.state == .joined || $0.state == .invited }
        BaselineCard {
            if c.isFinal {
                Button { rematch(c) } label: {
                    SettingsRowLabel(icon: "arrow.clockwise", title: rematched ? "Rematch created" : "Rematch",
                                     subtitle: "Same rules, starting next Monday") { EmptyView() }
                }
                .buttonStyle(.plain)
                .disabled(rematched)
                SettingsDivider()
            }
            if c.myState == .joined && !c.isFinal {
                Button { confirmLeave = true } label: {
                    SettingsRowLabel(icon: "rectangle.portrait.and.arrow.right", title: "Leave") { EmptyView() }
                }
                .buttonStyle(.plain)
                SettingsDivider()
            }
            if c.createdBy == me && !c.isFinal {
                Menu {
                    ForEach(removable) { r in
                        Button(r.name, role: .destructive) { removing = r }
                    }
                } label: {
                    SettingsRowLabel(icon: "person.badge.minus", title: "Remove a participant") { SettingsChevron() }
                }
                .buttonStyle(.plain)
                .disabled(removable.isEmpty)
                SettingsDivider()
            }
            Menu {
                ForEach(others) { r in
                    Button(r.name) { reporting = r; showReportPicker = true }
                }
            } label: {
                SettingsRowLabel(icon: "flag", title: "Report…") { SettingsChevron() }
            }
            .buttonStyle(.plain)
            .disabled(others.isEmpty)
        }
    }

    private func rulesLine(_ c: CompetitionSummary) -> String {
        var parts: [String] = []
        if let goal = lockedGoalText(c) { parts.append(goal) }
        parts.append("Each person's own day counts, in their own time zone.")
        // The same instant the status pill prints ("Final on Wed 15 Oct"): (end_day + 3) 12:00 UTC.
        parts.append(c.isFinal ? "Results are final." : "Results become final on \(FriendsDates.shortDate(c.freezeAt)).")
        return parts.joined(separator: " ")
    }

    /// A step source as words: "strap", "iPhone", "strap and iPhone" (the server sends "strap", "phone" or
    /// "phone+strap").
    static func sourceText(_ mix: String) -> String {
        let tokens = Set(mix.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let order = ["strap", "phone"]
        let known = order.filter(tokens.contains).map { $0 == "phone" ? "iPhone" : $0 }
        let other = tokens.subtracting(order).sorted()
        let words = known + other
        return words.isEmpty ? mix : words.joined(separator: " and ")
    }

    /// Who else is in it, without scores: "Alex and Sam have joined. Priya is invited."
    static func rosterText(_ members: [CompetitionMember], me: UUID?) -> String {
        let others = members.filter { $0.userID != me }
        let joined = others.filter { $0.state == .joined }.map(\.name)
        let invited = others.filter { $0.state == .invited }.map(\.name)
        var parts: [String] = []
        if !joined.isEmpty { parts.append("\(nameList(joined)) \(joined.count == 1 ? "has" : "have") joined.") }
        if !invited.isEmpty { parts.append("\(nameList(invited)) \(invited.count == 1 ? "is" : "are") invited.") }
        return parts.isEmpty ? "Nobody else has joined yet." : parts.joined(separator: " ")
    }

    /// Why there are no scores: the server sends them only to people taking part.
    static func noScoresText(_ c: CompetitionSummary) -> String {
        switch c.myState {
        case .invited: return c.isFinal ? "Scores went only to the people who joined." : "Scores show once you join."
        case .left: return "You left, so scores show once the results are final."
        default: return "No scores yet."
        }
    }

    /// "Alex", "Alex and Sam", "Alex, Sam and Priya".
    static func nameList(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    private func lockedGoalText(_ c: CompetitionSummary) -> String? {
        guard c.mode != .total, let p = store.overview?.me else { return nil }
        switch c.metric {
        case .steps: return "Your goal is locked at \(FriendsUI.number(p.stepGoal)) when you join."
        case .intensity: return "Your weekly goal is locked at \(p.intensityGoal) min when you join."
        default: return nil
        }
    }

    private func creatorName(_ c: CompetitionSummary) -> String {
        c.members.first { $0.userID == c.createdBy }?.name ?? "A friend"
    }

    private func join(_ c: CompetitionSummary) {
        if store.overview?.myShares[c.metric] == nil {
            consentFor = c.metric
        } else {
            act { _ = await store.respondCompetition(c.id, accept: true) }
        }
    }

    /// Same metric, mode and length, the members who are still friends, starting next Monday
    /// (`FriendsStore.rematch`).
    private func rematch(_ c: CompetitionSummary) {
        act {
            if await store.rematch(c) != nil { rematched = true }
        }
    }

    /// Runs a store action; a failure lands in `store.lastError` and is shown here, success pops or reloads.
    private func act(pop: Bool = false, _ work: @escaping () async -> Void) {
        Task {
            error = nil
            store.lastError = nil
            await work()
            let failed = store.lastError
            if pop && failed == nil { dismiss() } else { await load() }
            error = failed ?? error
        }
    }
}

/// "Your days" in the competition rule's own unit. `DayPoints.points` (server and `FriendsScoring.dayPoints`)
/// is a per-day score only for steps · % of own goal; intensity · % of own goal scores the whole window, so
/// its days are minutes; a total's days are the raw steps / minutes / 0-or-1; days at goal are 1 or 0. The
/// bars, the line, the caption and VoiceOver all use the same words.
struct YourDays {
    /// One bar per day.
    let bars: [Int?]
    /// Where the line sits, in the bars' unit; nil when there is no daily target to draw.
    let goal: Double?
    let caption: String
    /// "Mon 6 Oct, 84 points; Tue 7 Oct, 112 points, capped".
    let spoken: String

    init(_ days: [DayPoints], metric: FriendsMetric, mode: CompetitionMode, profile: FriendsProfile?) {
        let dayWords: (DayPoints) -> String
        var lines: [String] = []
        switch (mode, metric) {
        case (.goalPercent, .steps):
            bars = days.map { $0.points }
            goal = 100
            dayWords = { "\($0.points) \($0.points == 1 ? "point" : "points")" }
            lines.append("Points a day. The line is 100 points, your own goal.")
        case (.goalPercent, _):
            // Scored over the whole window (minutes ÷ weekly goal × days ÷ 7), so each day is just minutes.
            bars = days.map { $0.value }
            let daily = profile.map { Double(FriendsScoring.storedIntensityGoal($0.intensityGoal)) / 7 }
            goal = daily
            dayWords = { FriendsUI.dayValue(metric, $0.value) }
            lines.append(daily.map { "Minutes a day. The line is \(Int($0.rounded())) min, a seventh of your own weekly goal." }
                         ?? "Minutes a day.")
        case (.daysAtGoal, _):
            bars = days.map { $0.points }
            goal = nil
            dayWords = { "\($0.points > 0 ? "At goal" : "Missed"), \(FriendsUI.dayValue(metric, $0.value))" }
            lines.append("Full bars are days at your own goal.")
        case (.total, _):
            bars = days.map { $0.value }
            goal = nil
            dayWords = { FriendsUI.dayValue(metric, $0.value) }
            switch metric {
            case .active: lines.append("Full bars are active days.")
            case .sleepGoal: lines.append("Full bars are nights at your own sleep goal.")
            case .bedtime: lines.append("Full bars are on-time bedtimes.")
            default: lines.append("Best day \(FriendsUI.dayValue(metric, days.map(\.value).max() ?? 0)).")
            }
        }
        if days.contains(where: \.capped) { lines.append("Bars with an orange cap hit the daily cap.") }
        caption = lines.joined(separator: " ")
        spoken = days.map { "\(FriendsUI.shortDay($0.day)), \(dayWords($0))\($0.capped ? ", capped" : "")" }
            .joined(separator: "; ")
    }
}

/// "Share Intensity minutes for competitions only?" shown before joining (or creating) a competition on a
/// metric the person does not share yet. Agreeing sets that one metric to "Only in competitions".
struct CompetitionsOnlyConsentSheet: View {
    let metric: FriendsMetric
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
                    BaselineCard {
                        Text("Share \(metric.title) for competitions only?")
                            .font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Shared: \(metric.sharedForm). It's used for scoring in competitions you join; friends outside them don't see it. You can stop any time in Settings › Friends & sharing, which deletes it from the server.")
                            .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        BaselineCTA(title: "Share for competitions") { onAgree(); dismiss() }
                        BaselineCTA(title: "Not now", prominent: false) { dismiss() }
                    }
                }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 12)
            }
            .background(BaselineBackground())
            .navigationTitle("Share to compete")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
