#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// Today: strap status, the date with a readiness line, HRV and resting HR against the person's own
/// baseline, last night, today's effort, and a four-chip journal prompt. Reads `repo.days`,
/// `repo.workoutRows(days:)` and the native journal; reloads on `repo.refreshSeq`.
@MainActor
struct TodayScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @StateObject private var catalog = JournalCatalogStore()

    @State private var snapshot: TodaySnapshot?
    @State private var workouts: [TodayWorkout] = []
    @State private var answers: [String: Bool] = [:]
    @State private var todayKey = Repository.localDayKey(Date())
    @State private var showPair = false

    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let day: String
    }

    var body: some View {
        BaselineScreen(title: "Today") {
            strapStatus
            if !repo.loaded {
                ProgressView()
                    .tint(BaselineTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if repo.days.isEmpty {
                BaselineEmptyState(
                    icon: "moon.stars",
                    title: "Your first night fills this in",
                    message: "Wear the strap tonight. After the first synced night, HRV, resting HR, sleep and effort appear here against your own baseline.")
                    .padding(.top, 24)
            } else if let s = snapshot {
                headline(s)
                heroes(s)
                LastNightCard(sleep: s.sleep, todayKey: s.todayKey)
                EffortCard(effort: s.effort, workouts: workouts)
                JournalPromptCard(items: journalItems, labels: journalLabels, answers: answers, onToggle: toggle)
            }
        }
        .refreshable {
            model.ble.syncNow()
            await repo.refresh()
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, day: todayKey)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            todayKey = Repository.localDayKey(Date())
        }
        .sheet(isPresented: $showPair) {
            AddDeviceWizard(live: model.live, onClose: { showPair = false })
        }
    }

    // MARK: Sections

    @ViewBuilder private var strapStatus: some View {
        if let registry = model.deviceRegistry {
            StrapStatusSection(registry: registry) { showPair = true }
        } else {
            PairStrapCard { showPair = true }
        }
    }

    private func headline(_ s: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(BaselineTheme.title)
                .foregroundStyle(BaselineTheme.text)
            HStack(alignment: .center, spacing: 10) {
                BaselinePill(text: readinessPill(s.readiness), color: readinessColor(s.readiness))
                Text(readinessLine(s.readiness))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
    }

    private func heroes(_ s: TodaySnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TodayHeroTile(title: "HRV", unit: "ms", color: BaselineTheme.hrv,
                          higherIsBetter: true, reading: s.hrv)
            TodayHeroTile(title: "Resting HR", unit: "bpm", color: BaselineTheme.rhr,
                          higherIsBetter: false, reading: s.restingHr)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Readiness copy

    private func readinessPill(_ r: TodayReadiness) -> String {
        switch r {
        case .calibrating(let n): return "Calibrating · \(n) of \(HRVReadiness.minNights) nights"
        case .tier(.primed): return "Primed"
        case .tier(.normal): return "On baseline"
        case .tier(.suppressed): return "Below your normal range"
        }
    }

    private func readinessColor(_ r: TodayReadiness) -> Color {
        switch r {
        case .calibrating: return BaselineTheme.textTertiary
        case .tier(.primed): return BaselineTheme.good
        case .tier(.normal): return BaselineTheme.accent
        case .tier(.suppressed): return BaselineTheme.watch
        }
    }

    private func readinessLine(_ r: TodayReadiness) -> String {
        switch r {
        case .calibrating: return "Readiness arrives after 14 nights."
        case .tier(.primed): return "HRV is running above its usual range. A good day to push."
        case .tier(.normal): return "HRV is where it usually is."
        case .tier(.suppressed): return "HRV is lower than usual. Go gently today."
        }
    }

    // MARK: Journal

    private var journalItems: [JournalCatalogItem] {
        Array(catalog.resolvedItems(imported: []).filter { !$0.hidden && !$0.kind.isNumeric }.prefix(4))
    }

    private var journalLabels: [String: String] {
        var out: [String: String] = [:]
        for item in journalItems {
            out[item.canonical] = item.displayName ?? Self.shortLabels[item.canonical] ?? item.canonical
        }
        return out
    }

    /// Chip-length labels for the starter questions. Display only: the canonical question is what is saved.
    private static let shortLabels: [String: String] = [
        "Did you drink any alcohol?": "Alcohol",
        "Did you have caffeine late in the day?": "Late caffeine",
        "Did you view a screen in bed?": "Screen in bed",
        "Did you eat close to bedtime?": "Ate late",
        "Did you feel stressed?": "Stressed",
        "Did you use a sauna?": "Sauna",
        "Did you share your bed?": "Shared bed",
        "Did you feel sick or ill?": "Felt ill",
        "Did you take magnesium?": "Magnesium",
        "Did you read before bed?": "Read in bed",
    ]

    private func toggle(_ question: String) {
        let next = !(answers[question] ?? false)
        answers[question] = next
        let day = todayKey
        Task { await repo.saveJournalAnswer(day: day, question: question, answeredYes: next, notes: nil) }
    }

    // MARK: Load

    private func load() async {
        let key = todayKey
        snapshot = TodaySnapshot.build(days: repo.days, todayKey: key)
        let rows = await repo.workoutRows(days: 2)
        workouts = rows
            .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == key }
            .sorted { $0.startTs < $1.startTs }
            .map(TodayWorkout.init)
        answers = await repo.nativeJournalAnswers(day: key)
    }
}
#endif
