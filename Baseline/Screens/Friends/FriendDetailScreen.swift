#if os(iOS)
import SwiftUI
import Charts

/// One friend (`friend-detail`): "This week" (a bar block per behaviour metric they share), "Trends"
/// (one sentence per physiology metric they share, plus up to five weekly points around a zero line
/// labelled "own baseline", neutral ink: each person against their own baseline, never comparable
/// between people), "Together" (competitions you share), and "Manage" (hide my data, mute, remove,
/// block, report), every destructive action behind a confirmation.
struct FriendDetailScreen: View {
    let friendID: UUID
    @EnvironmentObject private var store: FriendsStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirm: Confirm?
    @State private var showReport = false
    @State private var error: FriendsError?
    @State private var reported = false

    enum Confirm: Identifiable { case remove, block; var id: Self { self } }

    private var friend: Friend? { store.overview?.friends.first { $0.id == friendID } }
    private var week: [String] { FriendsUI.weekKeys() }

    var body: some View {
        Group {
            if let friend {
                BaselineScreen(title: friend.profile.displayName, titleMode: .inline) {
                    content(friend)
                }
            } else {
                BaselineScreen(title: "Friend", titleMode: .inline) {
                    BaselineCard {
                        BaselineEmptyState(icon: "person.crop.circle.badge.questionmark", title: "Not connected",
                                           message: "This person is no longer in your friends.")
                    }
                }
            }
        }
        .accessibilityIdentifier("friend-detail")
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { c in
            switch c {
            case .remove:
                Button("Remove friend", role: .destructive) { act(pop: true) { await store.removeFriend(friendID) } }
            case .block:
                Button("Block", role: .destructive) { act(pop: true) { await store.block(friendID) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            switch c {
            case .remove: Text("You stop seeing each other's shared data. You can connect again with a new code.")
            case .block: Text("They're removed from your friends and from competitions you created, and can't send you a request again.")
            }
        }
        .confirmationDialog("Report \(friend?.profile.displayName ?? "")?", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(ReportReason.allCases, id: \.self) { r in
                Button(r.title) {
                    act { if await store.report(friendID, reason: r, competition: nil) { reported = true } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports go to Baseline's developer. Nothing you write is sent; only the reason.")
        }
    }

    private var confirmTitle: String {
        let name = friend?.profile.displayName ?? "this friend"
        switch confirm {
        case .remove?: return "Remove \(name)?"
        case .block?: return "Block \(name)?"
        case nil: return ""
        }
    }


    // MARK: Content

    @ViewBuilder private func content(_ f: Friend) -> some View {
        let behaviour = FriendWeekCard.sharedBehaviour(f)
        BaselineCard(title: "This week") {
            Text(FriendsUI.updated(lastDay: f.lastDay))
                .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            if behaviour.isEmpty {
                Text("\(f.profile.displayName) isn't sharing any activity with friends.")
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            }
            ForEach(Array(behaviour.enumerated()), id: \.element) { i, m in
                if i > 0 { SettingsDivider() }
                metricBlock(f, m)
            }
        }

        let trends = FriendsUI.latestTrends(f.trends)
        if !trends.isEmpty {
            BaselineCard(title: "Trends") {
                ForEach(Array(trends.enumerated()), id: \.element.metric) { i, t in
                    if i > 0 { SettingsDivider() }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(FriendsBoard.trendSentence(t, name: f.profile.displayName))
                            .font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        FriendTrendChart(metric: t.metric, rows: f.trends.filter { $0.metric == t.metric })
                    }
                }
                Text(FriendsBoard.trendFootnote)
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        let together = store.competitions.filter { c in c.members.contains { $0.userID == f.id && $0.state != .declined && $0.state != .removed } }
        if !together.isEmpty {
            BaselineCard(title: "Together") {
                ForEach(Array(together.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { SettingsDivider() }
                    NavigationLink { CompetitionDetailScreen(competitionID: c.id) } label: {
                        SettingsRowLabel(icon: FriendsUI.symbol(c.metric), title: c.title,
                                         subtitle: c.isFinal ? "Final" : CompetitionCard.status(c)) { SettingsChevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        BaselineCard(title: "Manage") {
            Toggle(isOn: Binding(get: { f.iHide }, set: { on in act { await store.setHidden(f.id, hidden: on) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide my data from \(f.profile.displayName)").font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                    Text("They stop seeing what you share. They aren't told.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                }
            }
            .tint(BaselineTheme.accent)
            SettingsDivider()
            Toggle(isOn: Binding(get: { store.muted.contains(f.id) }, set: { store.setMuted(f.id, $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mute").font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                    Text("Folds their card away on this phone only.")
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                }
            }
            .tint(BaselineTheme.accent)
            SettingsDivider()
            manageButton("Remove friend", icon: "person.badge.minus") { confirm = .remove }
            SettingsDivider()
            manageButton("Block", icon: "hand.raised") { confirm = .block }
            SettingsDivider()
            manageButton(reported ? "Reported" : "Report…", icon: "flag") { showReport = true }
                .disabled(reported)
            FriendsErrorLine(error: error)
        }
    }

    private func manageButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRowLabel(icon: icon, title: title) { EmptyView() }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func metricBlock(_ f: Friend, _ m: FriendsMetric) -> some View {
        let vals = FriendWeekCard.values(f, m, days: week)
        let have = vals.compactMap { $0 }
        let goalDays = have.filter { FriendsUI.atGoal(m, value: $0, profile: f.profile) }.count
        let total = FriendsUI.total(m, have.reduce(0, +), days: have.count)
        let line = goalLine(m, f.profile, goalDays: goalDays, of: have.count)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
                Spacer(minLength: 8)
                Text(total)
                    .font(BaselineTheme.label).monospacedDigit().foregroundStyle(BaselineTheme.text)
            }
            FriendsDayBars(values: vals, color: FriendsUI.color(m), goal: FriendsUI.dailyGoal(m, profile: f.profile),
                           height: 44, capped: Set(week.enumerated().compactMap { i, d in
                               f.days.contains { $0.metric == m && $0.day == d && $0.capped } ? i : nil }))
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { d in
                    Text(FriendsUI.weekdayLetter(d)).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            if let line {
                Text(line)
                    .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.title)
        .accessibilityValue(line.map { "\(total) this week, \($0)" } ?? "\(total) this week")
    }

    /// The line under a block's bars. nil for the day-count metrics (Active days, Sleep goal, Bedtimes):
    /// for them the header's "3 of 5 nights" already IS the goal count, so a second "3 of 7" under it
    /// would state the same fact against a different denominator.
    /// The denominator is the days the friend has shared so far this week, the same one the
    /// day-count headers use ("3 of 5 days"), never the seven days of a week still running.
    private func goalLine(_ m: FriendsMetric, _ p: FriendsProfile, goalDays: Int, of days: Int) -> String? {
        switch m {
        case .steps: return "\(goalDays) of \(days) day\(days == 1 ? "" : "s") at their own goal of \(FriendsUI.number(p.stepGoal))"
        case .intensity: return "Against their own weekly goal of \(p.intensityGoal) min"
        default: return nil
        }
    }

    /// Runs a store action; a failure lands in `store.lastError` and is shown here, success may pop.
    private func act(pop: Bool = false, _ work: @escaping () async -> Void) {
        Task {
            error = nil
            store.lastError = nil
            await work()
            error = store.lastError
            if pop && error == nil { dismiss() }
        }
    }
}

/// Up to five weekly points around a zero line labelled "own baseline", in neutral ink. The scale is the
/// metric's clip range (HRV ±30 %, resting HR ±10 bpm, readiness ±15), so the shape never looks bigger
/// than the rounded change it draws. Calibrating weeks are left out.
struct FriendTrendChart: View {
    let metric: FriendsMetric
    let rows: [TrendShare]

    private var limit: Int {
        switch metric { case .hrv: return 30; case .rhr: return 10; default: return 15 }
    }
    private var points: [(date: Date, delta: Int)] {
        rows.filter { $0.status == .ready }
            .compactMap { r in r.delta.flatMap { d in FriendsDates.date(r.weekStart).map { ($0, d) } } }
            .sorted { $0.date < $1.date }
            .suffix(5)
            .map { $0 }
    }

    var body: some View {
        if points.count >= 2 {
            Chart {
                RuleMark(y: .value("Own baseline", 0))
                    .foregroundStyle(BaselineTheme.textTertiary.opacity(BaselineChartStyle.baselineOpacity))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("own baseline").font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                    }
                ForEach(points, id: \.date) { p in
                    LineMark(x: .value("Week", p.date), y: .value("Change", p.delta))
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .lineStyle(.init(lineWidth: BaselineChartStyle.lineWidth))
                    PointMark(x: .value("Week", p.date), y: .value("Change", p.delta))
                        .foregroundStyle(BaselineTheme.text)
                        .symbolSize(30)
                }
            }
            .chartYScale(domain: -limit...limit)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: points.map(\.date)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(BaselineTheme.caption)
                }
            }
            .chartPlotStyle { $0.background(.clear) }
            .frame(height: 90)
            .accessibilityHidden(true)
        }
    }
}
#endif
