#if os(iOS)
import Foundation
import WhoopStore

// Sample data: a Release-safe way to see every screen populated without a strap (App Review has none,
// and NOOP's `--demo-seed` is compiled only in DEBUG).
//
// WHAT IT WRITES. `generate(anchor:)` is a pure, deterministic generator (fixed-seed SplitMix64, the
// anchor day = today): 60 nights of internally consistent synthetic data. HRV drifts slowly upward
// around a personal baseline with nightly noise; resting HR moves inversely to that night's HRV; sleep
// is 6–8 h with a light/deep/REM timeline the hypnogram can draw; a few workouts a week carry an
// effort; every day carries a step count (higher on training days) and NOOP's whole-day calorie
// estimate (`activeKcalEst`, resting + active, following the steps and that day's workouts), so Home's
// Steps card, the Calories cell and Trends' Steps card fill in; the last month has journal answers
// (alcohol, late caffeine, stress) that HRV reacts to, so Trends › Habits ranks something. Steps and
// calories draw from their own fixed-seed stream (`activitySeedSalt`), so adding them left every other
// column of the dataset byte-identical. Nothing here is real biometric data.
//
// WHERE IT LIVES. Every row goes through WhoopStore's PUBLIC upserts under TWO dedicated device ids and
// nothing else: the daily table and the sleep sessions under `computedDeviceId` ("baseline-sample-noop"),
// workouts and journal under `deviceId` ("baseline-sample"). `remove(from:)` is
// `WhoopStore.deleteAllData(deviceId:)` for exactly those two ids (every deviceId-keyed table, one
// transaction), so toggling off leaves no trace and never touches a strap's, an import's or Apple
// Health's rows. No registry (`pairedDevice`) row is ever written: the sample is not a device.
//
// HOW IT IS READ. NOOP's `Repository.refresh` surfaces daily rows only under the ACTIVE strap id, the
// canonical "my-whoop", their "-noop" siblings, "apple-health" and "activity-file" (`importedReadIds` /
// `computedReadIds`, Strand/Data/Repository.swift), so a dedicated id is invisible until the read spine
// is pointed at it. `applyReadSpine(_:)` does that with `Repository.adoptActiveDeviceId`, NOOP's own
// read-side re-pointer (it moves the READ id only; BLE and the engine keep writing under the registry's
// active strap). With it in place the sample's daily rows arrive as `.noopComputed` (the "-noop"
// sibling), which `BaselineDays` treats as the strap's own nights under the default strap-first
// precedence; the sleep sessions come through `repo.computedSleepSessions`, workouts through
// `workoutNamespaces`, the journal through `importedReadIds`. The real "my-whoop" history stays in
// the union beneath (the sample wins a shared day while it is on). The re-point is in-memory: AppModel
// re-adopts the registry's active id on every launch, so `SampleDataPill` (on Home while the flag is
// on) re-applies it and refreshes until the two agree. Steps reach Home through NOOP's strap → phone →
// estimate resolver (its third strap candidate is `<active>-noop`, the sample's daily rows, so they read
// as the strap's counter), calories' legacy figure through `activeKcalEst`.
//
// INTRADAY STREAMS. The daily rows alone left Heart rate, Stress and scored Intensity minutes empty and
// the Calories card without an active part, because those read the strap's raw seconds. `insert` also
// writes a heart-rate trace for every day and wrist motion for walks and workouts
// (`BaselineSampleStreams`, deterministic) through `WhoopStore.insert(_:deviceId:)` under `deviceId`.
// The sample id is in no registry, so NOOP's engine never re-scores those seconds (the sample's own
// daily rows stay authoritative), while the read spine's `rawPhysiologyReadIds` puts the ACTIVE id first,
// so `hrSamples`, `hrBuckets` and `gravitySamplesUnion` all see them while the sample is read.
// `deleteAllData(deviceId:)` clears `hrSample` and `gravitySample` with everything else.
//
// TODAY. The anchor day is written "so far": its steps scaled by the share of the waking day (06–22)
// that has passed at the anchor, its calorie estimate by the share of the whole day, its streams cut at
// the anchor. `refreshIfStale` (from `applyReadSpine`, on every activation) tops today up as the day
// goes on, and re-anchors the whole dataset on a new day, so the sample never shows a whole day's count
// at 9:41 or a stale week.
enum BaselineSampleData {

    /// Workouts and journal answers live under this id.
    static let deviceId = "baseline-sample"
    /// The daily table and sleep sessions live under the computed sibling, so the engine's read spine
    /// files them as `.noopComputed` (a strap's own nights), never as an import.
    static let computedDeviceId = deviceId + "-noop"
    /// `UserDefaults.standard` flag: true while the sample rows are in the store. Home shows the
    /// "Sample data" pill on it and the About toggle binds to it.
    static let activeKey = "baseline.sampleData.active"
    /// Nights generated.
    static let nights = 60
    /// The fixed seed; the dataset for one anchor day is the same on every device and every run.
    static let seed: UInt64 = 0xBA5E_11E5
    /// XORed into `seed` for the steps / calories stream, which runs beside the main one.
    static let activitySeedSalt: UInt64 = 0x57E9_5CA1
    /// `UserDefaults.standard`: the day key the stored dataset is anchored on, and the unix second its
    /// streams and today's row were last written up to (`refreshIfStale`).
    static let anchorDayKey = "baseline.sampleData.anchorDay"
    static let writtenUntilKey = "baseline.sampleData.writtenUntil"
    /// Today is topped up at most this often (seconds).
    static let topUpInterval = 15 * 60

    /// True while the sample rows are in the store (the flag `setActive` writes).
    static var isActive: Bool { UserDefaults.standard.bool(forKey: activeKey) }

    /// Everything one anchor day generates, as the store's own row types.
    struct Dataset: Equatable {
        var days: [DailyMetric]
        var sleeps: [CachedSleepSession]
        var workouts: [WorkoutRow]
        var journal: [JournalEntry]
    }

    private static let sports = ["Running", "Cycling", "Strength", "Yoga", "Walking", "Swimming", "Rowing"]
    private static let distanceSports: Set<String> = ["Running", "Cycling", "Walking", "Swimming", "Rowing"]

    static let alcoholQuestion = "Did you drink any alcohol?"
    static let caffeineQuestion = "Did you have caffeine late in the day?"
    static let stressQuestion = "Did you feel stressed?"
    /// Journal answers cover the newest this-many nights.
    static let journalNights = 30

    // MARK: - Generator (pure)

    /// 60 nights ending on `anchor`'s local day (today by default), oldest → newest. Pure: the same
    /// anchor day and calendar give the same rows, byte for byte.
    static func generate(anchor: Date = Date(), calendar: Calendar = .current) -> Dataset {
        var rng = BaselineSampleRNG(seed: seed)
        var activityRng = BaselineSampleRNG(seed: seed ^ activitySeedSalt)
        let start = calendar.date(byAdding: .day, value: -(nights - 1), to: calendar.startOfDay(for: anchor))!

        var days: [DailyMetric] = []
        var sleeps: [CachedSleepSession] = []
        var workouts: [WorkoutRow] = []
        var journal: [JournalEntry] = []

        for i in 0..<nights {
            let date = calendar.date(byAdding: .day, value: i, to: start)!
            let day = Repository.localDayKey(date)
            let weekday = calendar.component(.weekday, from: date)
            let weekend = weekday == 1 || weekday == 7

            // Journal first, so tonight's HRV can react to it (the pattern Habits is meant to find).
            var alcohol = false, lateCaffeine = false, stressed = false
            if i >= nights - journalNights {
                alcohol = rng.nextDouble() < (weekend ? 0.35 : 0.12)
                lateCaffeine = rng.nextDouble() < 0.30
                stressed = rng.nextDouble() < 0.25
                journal.append(JournalEntry(day: day, question: alcoholQuestion, answeredYes: alcohol, notes: nil))
                journal.append(JournalEntry(day: day, question: caffeineQuestion, answeredYes: lateCaffeine, notes: nil))
                journal.append(JournalEntry(day: day, question: stressQuestion, answeredYes: stressed, notes: nil))
            }

            // Training: most weekdays, fewer weekends; occasionally two sessions.
            let trains = rng.nextDouble() < (weekend ? 0.30 : 0.50)
            let nWorkouts = !trains ? 0 : (rng.nextDouble() < 0.15 ? 2 : 1)

            // Sleep: 6–8 h with a plausible architecture.
            let totalSleep = gauss(&rng, 420, 28).clamped(360, 480)
            let efficiency = (gauss(&rng, 90, 3) - (alcohol ? 3 : 0)).clamped(80, 97)
            let deep = (totalSleep * gauss(&rng, 0.21, 0.025) * (alcohol ? 0.85 : 1)).clamped(50, 130)
            let rem = (totalSleep * gauss(&rng, 0.23, 0.025)).clamped(60, 140)
            let light = totalSleep - deep - rem
            let disturbances = Int(gauss(&rng, 5, 2.2).clamped(1, 12))

            // Autonomic markers: HRV around a slowly rising baseline, resting HR inversely related.
            let baselineHrv = 62.0 + Double(i) * 0.12
            let hrvNoise = gauss(&rng, 0, 6.5)
            let hrv = (baselineHrv + hrvNoise + (weekend ? 2 : 0) - Double(nWorkouts) * 3
                       - (alcohol ? 7 : 0) - (lateCaffeine ? 2 : 0) - (stressed ? 3 : 0)).clamped(30, 140)
            let rhr = Int((58.0 - Double(i) * 0.03 - (hrv - baselineHrv) * 0.3 + gauss(&rng, 0, 1.2)
                           + (alcohol ? 2 : 0)).rounded().clamped(44, 72))
            let resp = gauss(&rng, 14.5, 0.7).clamped(12, 18)
            let skinTempDev = gauss(&rng, 0, 0.2).clamped(-0.8, 0.8)

            let recovery = (40 + (hrv - 65) * 0.6 + (efficiency - 88) * 0.5 + (totalSleep - 420) * 0.03
                            - (Double(rhr) - 56) * 1.2 - Double(disturbances) * 0.6).clamped(10, 98)
            let strain = (nWorkouts == 0 ? gauss(&rng, 28, 6)
                          : 52 + Double(nWorkouts - 1) * 12 + gauss(&rng, 0, 7)).clamped(8, 95)

            // Steps: a daily count that rises on training days and a little at the weekend.
            let steps = Int(gauss(&activityRng, 7_400 + Double(nWorkouts) * 2_600 + (weekend ? 900 : 0), 1_700)
                .clamped(2_000, 19_000).rounded())
            // The day row is appended after the workouts below, so its calorie estimate can include them.
            var dayWorkoutKcal = 0.0

            // The night ending on `day`: onset the previous evening around 23:00, with a stage timeline.
            let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
            let onset = Int(calendar.startOfDay(for: previousDay).timeIntervalSince1970)
                + 23 * 3600 + rng.nextInt(-1500, 1500)
            let awakeMin = Double(disturbances) * 1.5
            let timeline = stageTimeline(deep: deep, rem: rem, light: light, awakeMin: awakeMin)
            let inBedSec = timeline.reduce(0) { $0 + $1.seconds }
            sleeps.append(CachedSleepSession(
                startTs: onset, endTs: onset + inBedSec, efficiency: round1(efficiency), restingHr: rhr,
                avgHrv: round1(hrv), stagesJSON: stagesJSON(onset: onset, timeline: timeline)))

            // Workouts: an early slot on weekends, after work on weekdays.
            for k in 0..<nWorkouts {
                let sport = sports[rng.nextInt(0, sports.count)]
                // Whole seconds so `durationS` is exactly `endTs - startTs` (the row must agree with itself).
                let durationSec = Double(Int(gauss(&rng, 45, 12).clamped(25, 75) * 60))
                let startOfDay = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
                let startTs = startOfDay + (weekend ? 9 : 18) * 3600 + rng.nextInt(0, 40) * 60 + k * 2 * 3600
                let avgHr = Int(gauss(&rng, 136, 8).clamped(118, 155))
                let maxHr = avgHr + Int(gauss(&rng, 24, 5).clamped(14, 36))
                let zones = [gauss(&rng, 14, 4), gauss(&rng, 30, 7), gauss(&rng, 30, 7), gauss(&rng, 18, 6), gauss(&rng, 8, 3)]
                    .map { $0.clamped(0, 100) }
                let energyKcal = round1(durationSec / 60 * gauss(&rng, 8.5, 1.5).clamped(5, 12))
                dayWorkoutKcal += energyKcal
                workouts.append(WorkoutRow(
                    startTs: startTs, endTs: startTs + Int(durationSec), sport: sport, source: deviceId,
                    durationS: durationSec,
                    energyKcal: energyKcal,
                    avgHr: avgHr, maxHr: maxHr,
                    strain: round1((strain * gauss(&rng, 0.65, 0.08)).clamped(10, 95)),
                    distanceM: distanceSports.contains(sport) ? round1(gauss(&rng, 6000, 2000).clamped(1500, 14000)) : nil,
                    zonesJSON: "{\"zone1\":\(round1(zones[0])),\"zone2\":\(round1(zones[1])),\"zone3\":\(round1(zones[2])),\"zone4\":\(round1(zones[3])),\"zone5\":\(round1(zones[4]))}",
                    notes: nil, steps: nil))
            }

            // Calories: NOOP's whole-day HR-only estimate (resting + active): a resting floor, the steps,
            // the day's workouts and a little noise. Never below the workouts it contains.
            let activeKcal = round1((1_640 + Double(steps) * 0.032 + dayWorkoutKcal + gauss(&activityRng, 0, 45))
                .clamped(1_500, 4_000))

            days.append(DailyMetric(
                day: day, totalSleepMin: round1(totalSleep), efficiency: round1(efficiency),
                deepMin: round1(deep), remMin: round1(rem), lightMin: round1(light),
                disturbances: disturbances, restingHr: rhr, avgHrv: round1(hrv),
                recovery: round1(recovery), strain: round1(strain), exerciseCount: nWorkouts,
                spo2Pct: nil, skinTempDevC: round2(skinTempDev), respRateBpm: round1(resp),
                steps: steps, activeKcalEst: activeKcal))
        }
        return Dataset(days: days, sleeps: sleeps, workouts: workouts, journal: journal)
    }

    // MARK: - Store (public WhoopStore APIs only)

    /// The share of the waking day (06:00–22:00 local) that has passed at `date`, 0…1: how far today's
    /// step count has got.
    static func wakingFraction(_ date: Date, calendar: Calendar = .current) -> Double {
        let secs = date.timeIntervalSince(calendar.startOfDay(for: date))
        return min(1, max(0, (secs - 6 * 3_600) / (16 * 3_600)))
    }

    /// `days` with the row for `anchor`'s day written "so far": steps × `wakingFraction`, the calorie
    /// estimate × the share of the whole day. Every other row and column unchanged. Pure.
    static func scaledToAnchor(_ days: [DailyMetric], anchor: Date, calendar: Calendar = .current) -> [DailyMetric] {
        let key = Repository.localDayKey(anchor)
        let steps = wakingFraction(anchor, calendar: calendar)
        let whole = BaselineReadouts.dayFraction(anchor, calendar: calendar)
        return days.map { d in
            guard d.day == key else { return d }
            return DailyMetric(
                day: d.day, totalSleepMin: d.totalSleepMin, efficiency: d.efficiency,
                deepMin: d.deepMin, remMin: d.remMin, lightMin: d.lightMin,
                disturbances: d.disturbances, restingHr: d.restingHr, avgHrv: d.avgHrv,
                recovery: d.recovery, strain: d.strain, exerciseCount: d.exerciseCount,
                spo2Pct: d.spo2Pct, skinTempDevC: d.skinTempDevC, respRateBpm: d.respRateBpm,
                steps: d.steps.map { Int((Double($0) * steps).rounded()) },
                activeKcalEst: d.activeKcalEst.map { round1($0 * whole) })
        }
    }

    /// Writes the dataset for `anchor` under the two sample ids, today "so far" (`scaledToAnchor`), and,
    /// with `includeStreams`, every day's heart rate and motion up to the anchor (`BaselineSampleStreams`)
    /// under `deviceId`. Idempotent: every upsert is keyed by its natural key, so a second insert for the
    /// same anchor rewrites the same rows.
    static func insert(into store: WhoopStore, anchor: Date = Date(), includeStreams: Bool = true) async throws {
        let data = generate(anchor: anchor)
        _ = try await store.upsertDailyMetrics(scaledToAnchor(data.days, anchor: anchor), deviceId: computedDeviceId)
        _ = try await store.upsertSleepSessions(data.sleeps, deviceId: computedDeviceId)
        if !data.workouts.isEmpty { _ = try await store.upsertWorkouts(data.workouts, deviceId: deviceId) }
        if !data.journal.isEmpty { _ = try await store.upsertJournal(data.journal, deviceId: deviceId) }
        if includeStreams {
            try await BaselineSampleStreams.insert(BaselineSampleStreams.plans(for: data, anchor: anchor),
                                                   into: store, deviceId: deviceId,
                                                   until: Int(anchor.timeIntervalSince1970))
        }
    }

    /// Today's row and today's streams written up to `now` (a top-up of an insert anchored earlier the
    /// same day). Idempotent.
    static func topUpToday(into store: WhoopStore, now: Date = Date()) async throws {
        let data = generate(anchor: now)
        let key = Repository.localDayKey(now)
        let today = scaledToAnchor(data.days.filter { $0.day == key }, anchor: now)
        _ = try await store.upsertDailyMetrics(today, deviceId: computedDeviceId)
        let plans = BaselineSampleStreams.plans(for: data, anchor: now).filter { $0.day == key }
        try await BaselineSampleStreams.insert(plans, into: store, deviceId: deviceId, until: Int(now.timeIntervalSince1970))
    }

    /// Deletes every row under the two sample ids, across every deviceId-keyed table, and nothing else.
    static func remove(from store: WhoopStore) async throws {
        try await store.deleteAllData(deviceId: deviceId)
        try await store.deleteAllData(deviceId: computedDeviceId)
    }

    /// How many sample rows the store holds right now (daily + sleep + workouts + journal), for tests
    /// and the About card's caption.
    static func storedRowCount(in store: WhoopStore) async -> Int {
        let far = 4_102_444_800   // 2100-01-01, past any row
        let days = (try? await store.dailyMetrics(deviceId: computedDeviceId, from: "0000-01-01", to: "9999-12-31"))?.count ?? 0
        let sleeps = (try? await store.sleepSessions(deviceId: computedDeviceId, from: 0, to: far, limit: 10_000))?.count ?? 0
        let workouts = (try? await store.workouts(deviceId: deviceId, from: 0, to: far, limit: 10_000))?.count ?? 0
        let journal = (try? await store.journalEntries(deviceId: deviceId, from: "0000-01-01", to: "9999-12-31"))?.count ?? 0
        return days + sleeps + workouts + journal
    }

    // MARK: - App wiring

    /// Points the repository's READ id at the sample while the flag is on. Returns true when it moved
    /// (the caller then refreshes). A no-op when the flag is off or the id is already the sample's.
    /// While the flag is on it also keeps the sample current (`refreshIfStale`, in the background). In a
    /// DEBUG build launched with `--demo-seed` it starts the demo augmentation (the same streams under the
    /// same id, `BaselineDemoAugmentation`, and only over a store NOOP's seeder seeded) and, once that has
    /// written, points the read id the same way.
    /// `keepCurrent: false` skips the background refresh (tests, whose repository has no store of its own).
    @MainActor
    static func applyReadSpine(_ repo: Repository, keepCurrent: Bool = true) -> Bool {
        #if DEBUG
        if !isActive, BaselineDemoAugmentation.requested {
            BaselineDemoAugmentation.startIfNeeded(repo)
            guard BaselineDemoAugmentation.isReady else { return false }
            return repo.adoptActiveDeviceId(deviceId)
        }
        #endif
        guard isActive else { return false }
        if keepCurrent { refreshIfStale(repo) }
        return repo.adoptActiveDeviceId(deviceId)
    }

    @MainActor private static var refreshing = false

    /// Keeps the stored sample current while it is on: a dataset anchored on an earlier day is replaced
    /// by today's (the whole 60 days move with the calendar), and today's row and streams are topped up
    /// to now at most every `topUpInterval`. Runs once at a time, in the background; refreshes the
    /// repository when it wrote anything.
    @MainActor
    static func refreshIfStale(_ repo: Repository, now: Date = Date()) {
        guard isActive, !refreshing else { return }
        let defaults = UserDefaults.standard
        let today = Repository.localDayKey(now)
        let stale = defaults.string(forKey: anchorDayKey) != today
        let nowTs = Int(now.timeIntervalSince1970)
        guard stale || nowTs - defaults.integer(forKey: writtenUntilKey) >= topUpInterval else { return }
        refreshing = true
        Task { @MainActor in
            defer { refreshing = false }
            guard let store = await repo.storeHandle() else { return }
            do {
                if stale {
                    try await remove(from: store)
                    try await insert(into: store, anchor: now)
                } else {
                    try await topUpToday(into: store, now: now)
                }
                defaults.set(today, forKey: anchorDayKey)
                defaults.set(nowTs, forKey: writtenUntilKey)
                await repo.refresh()
            } catch {
                // The next activation tries again; the rows already stored stay readable.
            }
        }
    }

    /// The About toggle: inserts (or removes) the rows, moves the read id onto the sample (or back to
    /// `restoreId`, the registry's active strap), persists the flag and refreshes. Errors leave the flag
    /// where it was and are returned for the card's caption.
    @MainActor
    @discardableResult
    static func setActive(_ on: Bool, repo: Repository, restoreId: String) async -> Error? {
        guard let store = await repo.storeHandle() else { return SampleDataError.storeUnavailable }
        do {
            if on {
                let now = Date()
                try await insert(into: store, anchor: now)
                UserDefaults.standard.set(true, forKey: activeKey)
                UserDefaults.standard.set(Repository.localDayKey(now), forKey: anchorDayKey)
                UserDefaults.standard.set(Int(now.timeIntervalSince1970), forKey: writtenUntilKey)
                _ = repo.adoptActiveDeviceId(deviceId)
            } else {
                try await remove(from: store)
                UserDefaults.standard.set(false, forKey: activeKey)
                UserDefaults.standard.removeObject(forKey: anchorDayKey)
                UserDefaults.standard.removeObject(forKey: writtenUntilKey)
                _ = repo.adoptActiveDeviceId(restoreId.isEmpty ? Repository.whoopSource : restoreId)
            }
        } catch {
            // A half-written insert must not linger under the sample ids.
            if on { try? await remove(from: store) }
            return error
        }
        await repo.refresh()
        return nil
    }

    enum SampleDataError: LocalizedError {
        case storeUnavailable
        var errorDescription: String? { "The local store could not be opened." }
    }

    // MARK: - Helpers

    private static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    /// Box–Muller normal sample.
    private static func gauss(_ rng: inout BaselineSampleRNG, _ mean: Double, _ sd: Double) -> Double {
        let u1 = rng.nextDouble().clamped(1e-9, 1)
        let u2 = rng.nextDouble()
        return mean + sd * (Foundation.sqrt(-2 * Foundation.log(u1)) * Foundation.cos(2 * Double.pi * u2))
    }

    /// A light → deep → light → REM → deep → light → REM → wake cycle, each block in whole minutes, so
    /// the session's `endTs` is exactly the timeline's end and the stage totals match the daily row to
    /// within the rounding of its three or four blocks.
    static func stageTimeline(deep: Double, rem: Double, light: Double, awakeMin: Double) -> [(stage: String, seconds: Int)] {
        let plan: [(String, Double)] = [("light", light * 0.35), ("deep", deep * 0.6), ("light", light * 0.30),
                                        ("rem", rem * 0.6), ("deep", deep * 0.4), ("light", light * 0.35),
                                        ("rem", rem * 0.4), ("wake", awakeMin)]
        var out: [(stage: String, seconds: Int)] = []
        for (stage, minutes) in plan {
            let secs = Int(minutes.rounded()) * 60
            if secs > 0 { out.append((stage: stage, seconds: secs)) }
        }
        return out
    }

    /// The timeline as the `[StageSegment]` JSON `AnalyticsEngine.decodeStages` reads, laid end to end
    /// from `onset`.
    static func stagesJSON(onset: Int, timeline: [(stage: String, seconds: Int)]) -> String {
        var t = onset
        var parts: [String] = []
        for block in timeline {
            parts.append("{\"start\":\(t),\"end\":\(t + block.seconds),\"stage\":\"\(block.stage)\"}")
            t += block.seconds
        }
        return "[" + parts.joined(separator: ",") + "]"
    }
}

/// SplitMix64, so the dataset is reproducible. NOOP's `SplitMix64` is compiled only in DEBUG
/// (`AppleDemoSeeder.swift`), and this must exist in Release. Not for any security use.
struct BaselineSampleRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextDouble() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }

    /// Uniform Int in [lower, upper).
    mutating func nextInt(_ lower: Int, _ upper: Int) -> Int {
        guard upper > lower else { return lower }
        return lower + Int(next() % UInt64(upper - lower))
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
#endif
