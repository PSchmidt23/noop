#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// Home: one day at a time. The navigation title is the selected day ("Today" / "Yesterday" /
/// "Wednesday 1 October"), a glass day switcher is pinned under the bar and a horizontal swipe over the
/// cards moves a day too (never into the future, never before the first stored night). Every card shows
/// THAT day: readiness (with the Progress chevron), the HRV and Resting HR rings against the baseline
/// going into that night, the night's sleep, the day's effort and workouts; Signals only on today. The
/// floating glass "Journal" button opens `JournalSheet` for the selected day. Reads `repo.baselineDays`,
/// `repo.baselineNights()`, `repo.workoutRows(days:)` and the recent journal; reloads on
/// `repo.refreshSeq`, the data-source setting and the selected day.
@MainActor
struct TodayScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState

    /// Bumped by `BaselineRoot` whenever Home should present the journal sheet (`--tab journal`, the
    /// evening check-in's tap); watched with `initial: true` so a cold-start request is honoured.
    let journalRequest: Int
    /// Bumped by `BaselineRoot` when `--tab settings` asks Home to push Settings.
    let settingsRequest: Int

    init(journalRequest: Int = 0, settingsRequest: Int = 0) {
        self.journalRequest = journalRequest
        self.settingsRequest = settingsRequest
    }

    /// The selected day and its bounds (`TodayDaySelection`, pure).
    @State private var selection = TodayDaySelection()
    @State private var snapshot: TodaySnapshot?
    /// The Signals card under Readiness (`TodaySignals.build`), today only; nil or empty hides it.
    @State private var signals: TodaySignals?
    @State private var workouts: [TodayWorkout] = []
    /// NOOP's 04:00-rollover day, the row today's effort is read from (`TodaySnapshot.build(logicalKey:)`).
    @State private var todayLogicalKey = Repository.logicalDayKey(Date())
    /// The Readiness card's chevron row: the HRV sentence Progress prints for the same persisted horizon
    /// (`ProgressSnapshot.hrvHeadline`); nil until the HRV baseline has settled once.
    @AppStorage("baseline.progressHorizon") private var progressHorizonRaw: Int = ProgressHorizon.quarter.rawValue
    @State private var progressHeadline: String?
    /// Strap-first precedence (`BaselineDays`): part of the reload key so a change in Settings re-reads.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    /// Bumped when the journal sheet closes, so the Signals card's confounders see the new answers.
    @State private var journalSeq = 0
    @State private var showJournal = false
    @State private var showSettings = false
    /// "Pair strap" first asks which WHOOP model, then opens the wizard on that model's prep step
    /// (`pairing`), past NOOP's device-type chooser and its Experimental tier.
    @State private var showPair = false
    @State private var pairing: AddDeviceWizard.DeviceType?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let day: String
        let logicalDay: String
        let horizon: Int
        let dataSource: String
        let journalSeq: Int
    }

    var body: some View {
        BaselineScreen(title: selection.title, titleMode: .inline, subtitle: subtitle, pinned: { daySwitcher }) {
            content
        }
        .baselineDaySwipe(previous: { step(-1) }, next: { step(1) })
        .safeAreaBar(edge: .bottom, alignment: .trailing, spacing: 0) {
            // A floating control over the background, never inside a card: the one glass button on Home.
            GlassCTA(title: "Journal", systemImage: "checklist", fullWidth: false) { showJournal = true }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { StrapStatusPill(onPair: { showPair = true }) }
            ToolbarItem(placement: .topBarTrailing) {
                BaselineToolbarLink(systemImage: "gearshape", accessibilityLabel: "Settings") { SettingsScreen() }
            }
        }
        .refreshable {
            model.ble.syncNow()
            await repo.refresh()
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, day: selection.key,
                          logicalDay: selection.logicalKey(todayLogicalKey: todayLogicalKey),
                          horizon: progressHorizonRaw, dataSource: dataSourceRaw, journalSeq: journalSeq)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in roll() }
        // The logical day rolls at 04:00 with no system notice; re-read both keys whenever the app returns.
        .onChange(of: scenePhase) { _, phase in if phase == .active { roll() } }
        .onChange(of: journalRequest, initial: true) { _, n in if n > 0 { showJournal = true } }
        .onChange(of: settingsRequest, initial: true) { _, n in if n > 0 { showSettings = true } }
        .navigationDestination(isPresented: $showSettings) { SettingsScreen() }
        .sheet(isPresented: $showJournal, onDismiss: { journalSeq += 1 }) {
            JournalSheet(day: selection.key)
        }
        .confirmationDialog("Which strap do you have?", isPresented: $showPair, titleVisibility: .visible) {
            Button("WHOOP 4.0") { pairing = .whoop4 }
            Button("WHOOP 5.0 / MG") { pairing = .whoop5mg }
        }
        .sheet(item: $pairing) { type in
            AddDeviceWizard(live: model.live, onClose: { pairing = nil }, startAt: (type: type, step: .prep))
        }
    }

    // MARK: Chrome

    /// The strap's sync state under the title, only while a strap is paired ("Synced 2h ago" /
    /// "Syncing…" / "Not synced yet"); nothing otherwise, so the seeded screenshots stay clean.
    private var subtitle: String? {
        guard StrapStatusPill.isPaired(live: live, registry: model.deviceRegistry) else { return nil }
        return StrapStatusPill.syncStamp(live: live)
    }

    private var daySwitcher: some View {
        BaselineDaySwitcher(selection: Binding(get: { selection.day }, set: { selection.select($0) }),
                            earliest: selection.lowerBound, latest: selection.today, style: .glass,
                            title: { _ in selection.shortDate })
    }

    private func step(_ days: Int) {
        withAnimation(.snappy(duration: 0.25)) { selection.step(days) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !repo.loaded {
            ProgressView()
                .tint(BaselineTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if repo.baselineDays.isEmpty {
            emptyStore
        } else if let s = snapshot {
            ReadinessCard(readiness: s.readiness, progressHeadline: progressHeadline)
            if selection.isToday, let signals, !signals.isEmpty {
                SignalsCard(signals: signals)
            }
            rings(s)
            LastNightCard(sleep: s.sleep, dayKey: s.todayKey, isToday: selection.isToday)
            EffortCard(effort: s.effort, workouts: workouts, isToday: selection.isToday)
        }
    }

    /// No night yet: what will appear, and the one action that makes it appear.
    private var emptyStore: some View {
        BaselineCard {
            BaselineEmptyState(
                icon: "moon.stars",
                title: "Your first night fills this in",
                message: "Wear the strap tonight. After the first synced night, HRV, resting HR, sleep and effort appear here against your own baseline. Baseline reads your strap directly over Bluetooth, on this phone only.")
            if !StrapStatusPill.isPaired(live: live, registry: model.deviceRegistry) {
                BaselineCTA(title: "Pair strap") { showPair = true }
            }
        }
    }

    /// Exactly two rings, each in its own tile (never a third, never concentric): side by side, stacked
    /// at accessibility type sizes.
    @ViewBuilder private func rings(_ s: TodaySnapshot) -> some View {
        let hrv = TodayRingTile(title: "HRV", unit: "ms", color: BaselineTheme.hrv, cfg: Baselines.hrvCfg,
                                higherIsBetter: true, reading: s.hrv, dayKey: s.todayKey)
        let rhr = TodayRingTile(title: "Resting HR", unit: "bpm", color: BaselineTheme.rhr, cfg: Baselines.restingHRCfg,
                                higherIsBetter: false, reading: s.restingHr, dayKey: s.todayKey)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) { hrv; rhr }
        } else {
            HStack(alignment: .top, spacing: 12) { hrv; rhr }
        }
    }

    // MARK: Load

    private func roll() {
        let now = Date()
        selection.roll(now: now)
        todayLogicalKey = Repository.logicalDayKey(now)
    }

    private func load() async {
        guard repo.loaded else { return }
        // ONE table for everything on the screen (strap-first precedence), read once per load.
        let days = repo.baselineDays
        selection.setEarliest(days.first.flatMap { TodayFormat.date(fromDayKey: $0.day) })
        let key = selection.key
        let logical = selection.logicalKey(todayLogicalKey: todayLogicalKey)
        let isToday = selection.isToday
        // The same night list the Sleep tab builds, so a night's total and its 30-night average are one
        // number on both tabs.
        let habitual = await repo.habitualMidsleepSec()
        let sessions = await repo.baselineNights()
        let nights = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
        let snap = TodaySnapshot.build(days: days, nights: nights, todayKey: key, logicalKey: logical)
        // The person may have swiped on while the store answered: never land an older day's cards.
        guard key == selection.key else { return }
        snapshot = snap
        if isToday {
            // The recent journal only feeds the illness watch's confounders (alcohol, a hard workout, …).
            let journal = await repo.journalEntries(days: 7)
            guard key == selection.key else { return }
            signals = TodaySignals.build(days: days, nights: nights, snapshot: snap, journal: journal)
        } else {
            signals = nil
        }
        progressHeadline = ProgressSnapshot.hrvHeadline(days: days, horizon: ProgressHorizon.resolve(progressHorizonRaw),
                                                        todayKey: key)
        let rows = await repo.workoutRows(days: selection.workoutWindowDays)
        guard key == selection.key else { return }
        workouts = rows
            .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == key }
            .sorted { $0.startTs < $1.startTs }
            .map(TodayWorkout.init)
    }
}
#endif
