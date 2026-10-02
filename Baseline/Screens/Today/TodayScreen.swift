#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// Home: one day at a time. The navigation title is the selected day ("Today" / "Yesterday" /
/// "Wednesday 1 October"), a glass day switcher is pinned under the bar and a horizontal swipe over the
/// cards moves a day too (never into the future, never before the first stored night). Every card shows
/// THAT day: the Readiness score (with the Progress chevron), the HRV and Resting HR rings against the
/// baseline going into that night (the week's HRV tier on the HRV tile), the day's steps, the night's
/// sleep, the day's Stress curve, the day's effort, calories and workouts; Signals only on today. The
/// floating glass "Journal" button opens `JournalSheet` for the selected day. Reads `repo.baselineDays`,
/// `repo.baselineNights()`, `repo.workoutRows(days:)`, the steps and stress accessors of
/// `BaselineReadouts` and the recent journal; reloads on `repo.refreshSeq`, the data-source setting and
/// the selected day. A day once built is kept in `HomeDayCache` until the store refreshes, so swiping
/// back and forth never recomputes it.
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
    /// The Readiness score card's state, the day's steps (nil hides the card), calories and Stress curve
    /// (`HomeDayCache.Entry`).
    @State private var readiness: TodayReadinessScore = .missing
    @State private var steps: BaselineReadouts.StepsReadout?
    @State private var calories: BaselineReadouts.CaloriesReadout?
    @State private var stress: BaselineReadouts.StressDayReadout?
    /// NOOP's 04:00-rollover day, the row today's effort is read from (`TodaySnapshot.build(logicalKey:)`).
    @State private var todayLogicalKey = Repository.logicalDayKey(Date())
    /// The Readiness card's chevron row: the HRV sentence Progress prints for the same persisted horizon
    /// (`ProgressSnapshot.hrvHeadline`); nil until the HRV baseline has settled once.
    @AppStorage("baseline.progressHorizon") private var progressHorizonRaw: Int = ProgressHorizon.quarter.rawValue
    @State private var progressHeadline: String?
    /// Strap-first precedence (`BaselineDays`): part of the reload key so a change in Settings re-reads.
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    /// Settings › About › "Show sample data": Home wears the "Sample data" pill while it is on.
    @AppStorage(BaselineSampleData.activeKey) private var sampleDataActive = false
    /// Bumped when the journal sheet closes, so the Signals card's confounders see the new answers.
    @State private var journalSeq = 0
    /// Per-day memo keyed by (day, logical day, `refreshSeq`, data source, horizon); emptied on a new
    /// `refreshSeq`. A class in `@State`: the same instance for the screen's whole life.
    @State private var cache = HomeDayCache()
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
        // The one glass button on Home floats over the scrolling cards (never inside a card). A bottom
        // safe-area inset on the scroll view, not padding on the last card: the content scrolls under the
        // button and the last card can still come fully above it. No `safeAreaBar`: that would draw a
        // full-width bar edge under a button that hugs the trailing corner.
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
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
        // Midnight: the switcher's upper bound moves and the selection jumps back to the new today.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in roll() }
        // The logical day rolls at 04:00 with no system notice; re-read both keys whenever the app returns
        // (a day that was crossed while suspended jumps to today too; the same day stays put).
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
        if sampleDataActive { SampleDataPill() }
        if !repo.loaded {
            ProgressView()
                .tint(BaselineTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if repo.baselineDays.isEmpty {
            emptyStore
        } else if let s = snapshot {
            ReadinessCard(readiness: readiness, progressHeadline: progressHeadline, isToday: selection.isToday)
            if selection.isToday, let signals, !signals.isEmpty {
                SignalsCard(signals: signals)
            }
            rings(s)
            if let steps, steps.hasRecordedSource {
                StepsCard(readout: steps)
            }
            LastNightCard(sleep: s.sleep, dayKey: s.todayKey, isToday: selection.isToday)
            // Today's card waits for the day with a paired strap ("No daytime data yet"); a past day
            // without a scored hour, or any day without a strap, shows no Stress card at all.
            if stress != nil || (selection.isToday && isPaired) {
                StressCard(stress: stress, isToday: selection.isToday)
            }
            EffortCard(effort: s.effort, workouts: workouts, calories: calories, isToday: selection.isToday)
        }
    }

    private var isPaired: Bool { StrapStatusPill.isPaired(live: live, registry: model.deviceRegistry) }

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
                                higherIsBetter: true, reading: s.hrv, dayKey: s.todayKey,
                                weekLine: s.readiness.weekPhrase)
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
        let isToday = selection.isToday
        let cacheKey = HomeDayCache.Key(dayKey: key,
                                        logicalKey: selection.logicalKey(todayLogicalKey: todayLogicalKey),
                                        refreshSeq: repo.refreshSeq, dataSource: dataSourceRaw,
                                        horizon: progressHorizonRaw)
        let seq = journalSeq

        if let hit = cache.entry(for: cacheKey) {
            // Already built under this store state: show it at once. Only today's signals (the journal
            // was edited since) and today's Stress curve (daytime heart rate lands without a refresh)
            // can be stale; the curve goes through NOOP's fingerprint memo, so an unchanged day costs
            // one small query.
            show(hit)
            if isToday, hit.signalsJournalSeq != seq {
                let journal = await repo.journalEntries(days: 7)
                guard key == selection.key, let nights = cache.nights(refreshSeq: cacheKey.refreshSeq,
                                                                     dataSource: cacheKey.dataSource) else { return }
                let fresh = TodaySignals.build(days: days, nights: nights, snapshot: hit.snapshot, journal: journal)
                cache.updateSignals(fresh, journalSeq: seq, for: cacheKey)
                signals = fresh
            }
            if isToday {
                let fresh = await BaselineReadouts.stressDay(repo, for: key)
                guard key == selection.key else { return }
                cache.updateStress(fresh, for: cacheKey)
                stress = fresh
            }
            return
        }

        // The same night list the Sleep tab builds, so a night's total and its 30-night average are one
        // number on both tabs; one list per store state, shared by every day.
        let nights: [SleepNight]
        if let cached = cache.nights(refreshSeq: cacheKey.refreshSeq, dataSource: cacheKey.dataSource) {
            nights = cached
        } else {
            let habitual = await repo.habitualMidsleepSec()
            let sessions = await repo.baselineNights()
            nights = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
            cache.storeNights(nights, refreshSeq: cacheKey.refreshSeq, dataSource: cacheKey.dataSource)
        }
        let snap = TodaySnapshot.build(days: days, nights: nights, todayKey: key, logicalKey: cacheKey.logicalKey)
        var daySignals: TodaySignals?
        if isToday {
            // The recent journal only feeds the illness watch's confounders (alcohol, a hard workout, …).
            let journal = await repo.journalEntries(days: 7)
            daySignals = TodaySignals.build(days: days, nights: nights, snapshot: snap, journal: journal)
        }
        let headline = ProgressSnapshot.hrvHeadline(days: days, horizon: ProgressHorizon.resolve(progressHorizonRaw),
                                                    todayKey: key)
        let rows = await repo.workoutRows(days: selection.workoutWindowDays)
        let dayWorkouts = rows
            .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == key }
            .sorted { $0.startTs < $1.startTs }
            .map(TodayWorkout.init)
        // The metrics layer: the stored Readiness score (never recomputed), steps through NOOP's
        // strap → phone → estimate resolver, the whole-day calorie estimate, the day's Stress curve.
        let dayReadiness = TodayReadinessScore.build(for: key, days: days, readiness: snap.readiness)
        let daySteps = await BaselineReadouts.steps(repo, for: key, mode: BaselineDataSource.resolve(dataSourceRaw))
        let dayCalories = BaselineReadouts.calories(for: key, days: days)
        let dayStress = await BaselineReadouts.stressDay(repo, for: key)
        let entry = HomeDayCache.Entry(snapshot: snap, signals: daySignals, signalsJournalSeq: seq,
                                       workouts: dayWorkouts, progressHeadline: headline,
                                       readiness: dayReadiness, steps: daySteps, calories: dayCalories, stress: dayStress)
        cache.store(entry, for: cacheKey)
        // The person may have swiped on while the store answered: never land an older day's cards (the
        // entry stays cached for when they come back).
        guard key == selection.key else { return }
        show(entry)
    }

    private func show(_ entry: HomeDayCache.Entry) {
        snapshot = entry.snapshot
        signals = selection.isToday ? entry.signals : nil
        workouts = entry.workouts
        progressHeadline = entry.progressHeadline
        readiness = entry.readiness
        steps = entry.steps
        calories = entry.calories
        stress = entry.stress
    }
}
#endif
