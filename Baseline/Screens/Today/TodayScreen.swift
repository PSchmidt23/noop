#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// Today: strap status, the date with a readiness line, HRV and resting HR against the person's own
/// baseline, last night, today's effort, and a four-chip journal prompt. Reads `repo.days`, `repo.sleeps`,
/// `repo.workoutRows(days:)` and the native journal; reloads on `repo.refreshSeq`.
@MainActor
struct TodayScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    /// The app's one catalog store (injected by `BaselineApp`), shared with the Journal tab so a habit
    /// hidden, renamed or added there changes these chips at once rather than at the next launch.
    @EnvironmentObject private var catalog: JournalCatalogStore

    @State private var snapshot: TodaySnapshot?
    @State private var workouts: [TodayWorkout] = []
    @State private var answers: [String: Bool] = [:]
    @State private var todayKey = Repository.localDayKey(Date())
    /// NOOP's 04:00-rollover day, the row today's effort is read from (`TodaySnapshot.build(logicalKey:)`).
    @State private var logicalKey = Repository.logicalDayKey(Date())
    /// Bumped by every journal chip tap, so a `load()` that was mid-await when the person tapped never
    /// lands its older `answers` on top of the optimistic update (`JournalScreenModel.readDay`'s guard).
    @State private var writeSeq = 0
    @Environment(\.scenePhase) private var scenePhase
    /// "Pair strap" first asks which WHOOP model, then opens the wizard on that model's prep step
    /// (`pairing`), past NOOP's device-type chooser and its Experimental tier.
    @State private var showPair = false
    @State private var pairing: AddDeviceWizard.DeviceType?
    /// The Progress row under the hero tiles: the HRV sentence the Progress screen prints for the same
    /// persisted horizon (`ProgressSnapshot.hrvHeadline`); nil until the HRV baseline has settled once.
    @AppStorage("baseline.progressHorizon") private var progressHorizonRaw: Int = ProgressHorizon.quarter.rawValue
    @State private var progressHeadline: String?

    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let day: String
        let logicalDay: String
        let horizon: Int
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
                if let progressHeadline {
                    TodayProgressRow(sentence: progressHeadline)
                }
                LastNightCard(sleep: s.sleep, todayKey: s.todayKey)
                EffortCard(effort: s.effort, workouts: workouts)
                JournalPromptCard(items: journalItems, label: label(_:), answers: answers, onCycle: cycle)
            }
        }
        .refreshable {
            model.ble.syncNow()
            await repo.refresh()
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, day: todayKey, logicalDay: logicalKey,
                          horizon: progressHorizonRaw)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollDayKeys() }
        // The logical day rolls at 04:00 with no system notice; re-read both keys whenever the app returns.
        .onChange(of: scenePhase) { _, phase in if phase == .active { rollDayKeys() } }
        .confirmationDialog("Which strap do you have?", isPresented: $showPair, titleVisibility: .visible) {
            Button("WHOOP 4.0") { pairing = .whoop4 }
            Button("WHOOP 5.0 / MG") { pairing = .whoop5mg }
        }
        .sheet(item: $pairing) { type in
            AddDeviceWizard(live: model.live, onClose: { pairing = nil }, startAt: (type: type, step: .prep))
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

    /// Date, the readiness pill, then its sentence on its own line (never beside the pill), so the
    /// sentence can run to its full length at any type size.
    private func headline(_ s: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(BaselineTheme.title)
                .foregroundStyle(BaselineTheme.text)
            BaselinePill(text: readinessPill(s.readiness), color: readinessColor(s.readiness))
            if let line = readinessLine(s.readiness) {
                Text(line)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func heroes(_ s: TodaySnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TodayHeroTile(title: "HRV", unit: "ms", color: BaselineTheme.hrv,
                          higherIsBetter: true, reading: s.hrv, todayKey: s.todayKey)
            TodayHeroTile(title: "Resting HR", unit: "bpm", color: BaselineTheme.rhr,
                          higherIsBetter: false, reading: s.restingHr, todayKey: s.todayKey)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Readiness copy

    /// The calibrating pill names what its count unlocks (readiness, 14 nights), the same shape the hero
    /// tiles use for their own, smaller count ("Baseline after 4 nights · n so far").
    private func readinessPill(_ r: TodayReadiness) -> String {
        switch r {
        case .calibrating(let n): return "Readiness after \(HRVReadiness.minNights) nights · \(n) so far"
        case .stale: return "Paused"
        case .tier(let tier): return tier.baselineLabel   // shared with Trends' readiness strip
        }
    }

    private func readinessColor(_ r: TodayReadiness) -> Color {
        switch r {
        case .calibrating, .stale: return BaselineTheme.textTertiary
        case .tier(let tier): return tier.baselineColor
        }
    }

    /// nil while calibrating: the pill already says when readiness arrives. A tier's sentence is
    /// `ReadinessTier.baselineWeekSentence` (shared vocabulary): it speaks of the week, so the seven-night
    /// tier and the one-night delta on the HRV tile are two facts, never a contradiction.
    private func readinessLine(_ r: TodayReadiness) -> String? {
        switch r {
        case .calibrating: return nil
        case .stale(let day): return "No HRV since \(TodayFormat.dayLabel(day)). Readiness returns with the next synced night."
        case .tier(let tier): return tier.baselineWeekSentence
        }
    }

    // MARK: Journal

    private var journalItems: [JournalCatalogItem] {
        Array(catalog.resolvedItems(imported: []).filter { !$0.hidden && !$0.kind.isNumeric }.prefix(4))
    }

    /// Chip label: the user's rename, else `JournalLabels.short`, the one table the Journal tab reads
    /// (`JournalScreen.label(for:)`), so a habit has one name on both tabs. The canonical question is
    /// what is saved.
    private func label(_ item: JournalCatalogItem) -> String {
        if let n = item.displayName, !n.isEmpty { return n }
        return JournalLabels.short(item.canonical)
    }

    /// yes → no → clear → yes, as the Journal tab's chips cycle. A "no" is a real answer (the control
    /// night the effects engine compares against); only clear deletes the row.
    private func cycle(_ question: String) {
        let next: Bool?
        switch answers[question] {
        case nil: next = true
        case .some(true): next = false
        case .some(false): next = nil
        }
        writeSeq += 1
        answers[question] = next
        let day = todayKey
        Task {
            if let next {
                await repo.saveJournalAnswer(day: day, question: question, answeredYes: next, notes: nil)
            } else {
                await repo.clearJournalAnswer(day: day, question: question)
            }
        }
    }

    // MARK: Load

    private func rollDayKeys() {
        let now = Date()
        todayKey = Repository.localDayKey(now)
        logicalKey = Repository.logicalDayKey(now)
    }

    private func load() async {
        let key = todayKey
        let seq = writeSeq
        // The same night list the Sleep tab builds, so last night's total and its 30-night average
        // are one number on both tabs.
        let habitual = await repo.habitualMidsleepSec()
        let nights = SleepNightBuilder.nights(sessions: repo.sleeps, days: repo.days, habitualMidsleepSec: habitual)
        snapshot = TodaySnapshot.build(days: repo.days, nights: nights, todayKey: key, logicalKey: logicalKey)
        progressHeadline = ProgressSnapshot.hrvHeadline(days: repo.days, horizon: ProgressHorizon.resolve(progressHorizonRaw),
                                                        todayKey: key)
        let rows = await repo.workoutRows(days: 2)
        workouts = rows
            .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == key }
            .sorted { $0.startTs < $1.startTs }
            .map(TodayWorkout.init)
        let stored = await repo.nativeJournalAnswers(day: key)
        // A chip tapped while the store answered already holds the newer state; keep it.
        guard seq == writeSeq else { return }
        answers = stored
    }
}
#endif
