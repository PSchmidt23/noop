#if os(iOS)
import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

// The per-day facts the intraday stream yields (Intensity minutes, the day's heart-rate low / mean /
// high, the strap's ACTIVE energy for the Calories card, and the Stress day mean once a screen asked for
// it), computed ONCE per day and kept, so a 1-year chart never reclassifies 365 days of samples on a
// render.
//
// Active energy (`activeKcal`): NOOP's own day estimator (`Calories.estimateDayEnergy`, Keytel 2005
// above 50 % heart-rate reserve), its ACTIVE part only: NOOP's resting part is integrated over the
// seconds the strap observed, and the Calories card credits a Mifflin–St Jeor resting figure for the
// whole day instead (`Research/ACTIVITY_METRICS.md` §2). Computed from the day's raw samples when this
// pass reads them (inside the verify window, once the profile may score), else from the 60-second
// bucket means; stamped with `energySignature` (the body, age, sex, max heart rate and that day's
// resting reference it ran on), so a profile change re-estimates the days it touches. A caller that
// passes no `CalorieInputs` leaves a record's figure as it found it.
//
// Two layers, as the brief asks:
//   • an in-memory memo keyed by (dayKey, refreshSeq): while the store's `refreshSeq` stands, a PAST day
//     is never looked at twice. Today never comes from the memo: live heart rate lands without a
//     `refreshSeq` bump (`HomeDayCache`), so every ask re-reads today's buckets and recomputes the day
//     when they moved, the same read the Heart rate card beside it makes;
//   • a persisted JSON file keyed by day, each record stamped with the WITNESS it was computed from (the
//     day's 60-second buckets: their count, the last bucket's start and the sum of their means), the
//     thresholds' signature and the store it describes (`storeIdentity`). A record is reused across
//     launches and refreshes while all three still match.
//
// Why the buckets and not `repo.hrFingerprint`: that COUNT / MAX covers the measured `hrSample` table
// only, while `hrBuckets` is measured ∪ PPG-derived (`ppgHrSample`). A WHOOP 4.0 on v25 firmware banks no
// per-second heart rate at all and a WHOOP 5.0 / MG banks most of its seconds as PPG estimates, so a day
// witnessed by `hrSample` alone read as empty, was persisted with no minutes and trusted forever, and
// PPG rows landing later never moved it. The witness is what the record was scored from, so it moves
// exactly when the figures can.
//
// Minutes: a day inside the verify window is classified from its raw samples under
// `INTENSITY_MINUTES.md` §5 (≥ 20 samples a minute, their median); an older day computed for the first
// time from its bucket means (`IntensityMinutes.minutes(buckets:)`, no sample floor), see the header of
// `IntensityMinutes.swift`.
//
// Where it lives: `<Application Support>/Baseline/intraday-days.json`, not UserDefaults and not
// Documents. UserDefaults is read whole into memory and rewritten as one plist on every change, which
// is wrong for hundreds of growing records; Documents is the folder iOS exposes through file sharing
// and the Files app when an app opts in, and a cache is not a document. Application Support is backed
// up, private to the app and the place Apple names for exactly this. Losing the file costs nothing but
// a recomputation.
//
// Verification cost: a day inside the last `verifyWindowDays` is re-read (60-second buckets, at most
// 1,440 SQL-aggregated rows) on every new `refreshSeq` and today on every ask (the strap re-offloads its
// 14-day store while connected, so those days can still gain seconds); its raw samples are read only
// when the buckets moved. An older day with a matching record is trusted without a query, because the
// strap trims acked history and never re-sends it (`INTRADAY_AND_RANGES.md` §1.3), UNLESS the store
// under it changed identity (a NOOP backup restored, the strap's data deleted, another strap or the
// sample data being read): then it is re-read once and re-stamped. A thresholds change (a new age, a
// max-HR override, a resting-HR reference moving after an import) re-scores any day it touches. When
// the store cannot be opened nothing is computed or persisted ("cannot tell" is not "empty").
// Settings › Data › "Recompute heart-rate days" drops the file (`reset()`).

/// What a record was computed from: the day's 60-second buckets over measured ∪ PPG-derived heart
/// rate. `sum` is a checksum over every bucket's mean, low, high and weakest confidence: it moves when a
/// late PPG row fills seconds inside a minute that already had a bucket (the mean shifts, and the
/// bucket's confidence drops below the measured 1.0), which the count and the last start alone miss.
struct IntradayWitness: Equatable {
    let count: Int
    let maxTs: Int
    let sum: Int

    init(count: Int, maxTs: Int, sum: Int) {
        self.count = count; self.maxTs = maxTs; self.sum = sum
    }

    /// Over the buckets that carry a heart rate (`bpm > 0`, finite), as `compute` scores them.
    init(buckets: [HRBucket]) {
        let scored = buckets.filter { $0.bpm > 0 && $0.bpm.isFinite }
        func whole(_ x: Double, _ scale: Double) -> Int { x.isFinite ? Int((x * scale).rounded()) : 0 }
        var sum = 0
        for b in scored {
            let mean: Int = whole(b.bpm, 1_000)
            let conf: Int = whole(b.conf, 1_000)
            let low: Int = whole(b.minBpm, 1)
            let high: Int = whole(b.maxBpm, 1)
            sum += mean + 3 * conf + 7 * low + 11 * high
        }
        self.init(count: scored.count, maxTs: scored.map(\.ts).max() ?? 0, sum: sum)
    }
}

/// One persisted day.
struct IntradayDayRecord: Codable, Equatable {
    let day: String
    /// `IntradayDayStore.version`; a record from an older classifier is recomputed.
    let version: Int
    /// The `IntradayWitness` the record was computed from.
    let fingerprintCount: Int
    let fingerprintMaxTs: Int
    let fingerprintSum: Int
    /// `IntensityMinutes.Basis.signature` + the bout rule; the thresholds the minutes were scored with.
    let thresholdSignature: String
    /// `IntradayDayStore.storeIdentity` when the record was computed or last re-read ("" = unknown).
    var storeIdentity: String
    /// `Basis` as a raw tag ("hrr" / "hrmax" / "workouts" / "needsAge") with its numbers.
    let basisTag: String
    let restingHr: Int?
    let hrMaxBpm: Int?
    let moderateMin: Int
    let vigorousMin: Int
    let scoredMinutes: Int
    /// The day's heart rate over its 60-second buckets; nil when the strap banked none.
    let bpmMin: Double?
    let bpmAvg: Double?
    let bpmMax: Double?
    /// The Stress day mean (0–3) once computed; `stressComputed` says a nil means "nothing scored"
    /// rather than "not asked yet".
    var stressMean: Double?
    var stressComputed: Bool
    let computedAt: Double
    /// Active energy (kcal) over the day's heart rate (see the header); nil when the strap banked none
    /// or no caller has asked with `CalorieInputs` yet.
    var activeKcal: Double? = nil
    /// `IntradayDayStore.energySignature` the figure was computed under; nil = not computed.
    var energySignature: String? = nil

    var credited: Int { moderateMin + 2 * vigorousMin }

    var witness: IntradayWitness {
        IntradayWitness(count: fingerprintCount, maxTs: fingerprintMaxTs, sum: fingerprintSum)
    }

    /// The basis the record was scored under.
    var basis: IntensityMinutes.Basis {
        switch basisTag {
        case "hrr": return .hrr(restingHr: restingHr ?? 0, hrMax: hrMaxBpm ?? 0)
        case "hrmax": return .hrMax(hrMax: hrMaxBpm ?? 0)
        case "workouts": return .workoutsOnly
        default: return .needsAge
        }
    }

    /// False for `.needsAge`: the heart-rate facts stand, the Intensity figures are not a reading.
    var basisIsScored: Bool { basisTag != "needsAge" }

    /// The strap scored heart rate on the day, or imported workouts earned minutes: something was
    /// recorded. The ONE predicate, shared with `TrendsIntensity.Day.recorded`.
    static func isRecorded(scoredMinutes: Int, credited: Int) -> Bool { scoredMinutes > 0 || credited > 0 }

    var recorded: Bool { Self.isRecorded(scoredMinutes: scoredMinutes, credited: credited) }

    /// The day is an Intensity READING: recorded and scored on a basis. A day the strap was off or on
    /// the charger (or a day before it was paired) is a record with zero minutes, not a zero-minute
    /// reading, so it never dilutes a range's average or the period before it.
    var recordedIntensity: Bool { basisIsScored && recorded }

    var hrMin: Double? { bpmMin }
    var hrAvg: Double? { bpmAvg }
    var hrMax: Double? { bpmMax }

    /// The day as the pure engine's result (bouts are not persisted; the week draws totals).
    var dayResult: IntensityMinutes.DayResult {
        IntensityMinutes.DayResult(day: day, moderateMin: moderateMin, vigorousMin: vigorousMin, bouts: [],
                                   scoredMinutes: scoredMinutes, basis: basis)
    }
}

@MainActor
final class IntradayDayStore {
    static let shared = IntradayDayStore()

    /// Bump when the classifier or the record's meaning changes; every stored day recomputes.
    /// 2: the witness covers PPG-derived heart rate, the verify window scores raw samples (§5's floor),
    /// workouts credit the day they started on, records carry the store identity.
    /// 3: records carry the strap's active energy (Calories card), and the Stress day mean is scored on
    /// the personal lens.
    static let version = 3
    /// Days back from today that are re-read on every new `refreshSeq`, and classified from raw samples.
    static let verifyWindowDays = 14
    /// Raw samples read for one day (a fully worn day is 86,400 seconds).
    static let sampleLimit = 200_000
    static let fileName = "intraday-days.json"

    /// `<Application Support>/Baseline/intraday-days.json`.
    nonisolated static var defaultFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Baseline", isDirectory: true).appendingPathComponent(fileName)
    }

    private struct Memo {
        let seq: Int
        let identity: String?
        let record: IntradayDayRecord
    }

    let fileURL: URL?
    let rule: IntensityMinutes.BoutRule
    private var persisted: [String: IntradayDayRecord] = [:]
    private var memo: [String: Memo] = [:]
    private var loaded = false
    private var dirty = false

    init(fileURL: URL? = IntradayDayStore.defaultFileURL, rule: IntensityMinutes.BoutRule = .default) {
        self.fileURL = fileURL
        self.rule = rule
    }

    // MARK: Persistence

    /// The stored records (loaded on first use).
    var storedRecords: [String: IntradayDayRecord] {
        loadIfNeeded()
        return persisted
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: IntradayDayRecord].self, from: data) else { return }
        persisted = decoded.filter { $0.value.version == Self.version }
    }

    /// Writes the records atomically when anything changed since the last flush.
    func flush() {
        guard dirty, let url = fileURL else { return }
        dirty = false
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: url, options: .atomic)
        } catch {
            // A cache that cannot be written is recomputed next time; nothing shown depends on the file.
        }
    }

    /// Drops every record: Settings › Data's "Recompute heart-rate days" row, and tests. Every day is
    /// read again the next time a screen asks for it.
    func reset() {
        loadIfNeeded()
        persisted.removeAll()
        memo.removeAll()
        dirty = true
        flush()
    }

    /// Stores one record (tests seed the file with it).
    func store(_ record: IntradayDayRecord) {
        loadIfNeeded()
        persisted[record.day] = record
        memo.removeValue(forKey: record.day)
        dirty = true
    }

    // MARK: Compute (pure)

    /// A record for `day` from its 60-second buckets under `thresholds` (nil = `.needsAge`: the heart-rate
    /// facts are kept, the minutes are zero). `samples`, when given, are the day's raw samples and the
    /// minutes come from them (§5: ≥ 20 samples a minute, their median); otherwise from the bucket
    /// means. The heart-rate low / mean / high and the witness always come from the buckets.
    /// `workouts` are rows that STARTED on the day, the fallback when the strap banked nothing.
    /// `fingerprint` pins the witness's count and last start (tests); by default both come from the
    /// buckets. `stress` carries a Stress mean forward when the caller already has one.
    nonisolated static func compute(day: String, buckets: [HRBucket], samples: [IntensityMinutes.Sample]? = nil,
                                    thresholds: IntensityMinutes.Thresholds?,
                                    fingerprint: (count: Int, maxTs: Int)? = nil, workouts: [WorkoutRow] = [],
                                    rule: IntensityMinutes.BoutRule = .default,
                                    stress: (mean: Double?, computed: Bool) = (nil, false),
                                    energy: (inputs: CalorieInputs, restingHr: Int?)? = nil,
                                    carriedEnergy: (kcal: Double?, signature: String?) = (nil, nil),
                                    storeIdentity: String = "", now: Date = Date()) -> IntradayDayRecord {
        let scored = buckets.filter { $0.bpm > 0 && $0.bpm.isFinite }
        let bpmMin = scored.map(\.minBpm).min()
        let bpmMax = scored.map(\.maxBpm).max()
        let bpmAvg = scored.isEmpty ? nil : scored.map(\.bpm).reduce(0, +) / Double(scored.count)
        let witness = IntradayWitness(buckets: scored)
        let minutes = samples.map { IntensityMinutes.minutes(samples: $0) } ?? IntensityMinutes.minutes(buckets: scored)

        let result: IntensityMinutes.DayResult
        if let thresholds, !minutes.isEmpty {
            result = IntensityMinutes.credit(day: day, minutes: minutes, thresholds: thresholds, rule: rule)
        } else if scored.isEmpty, let fromWorkouts = IntensityMinutes.creditFromWorkouts(day: day, rows: workouts) {
            result = fromWorkouts
        } else {
            result = .empty(day: day, basis: thresholds?.basis ?? .needsAge, scoredMinutes: minutes.count)
        }

        let tag: String
        var rhr: Int? = nil
        var hrMax: Int? = nil
        switch result.basis {
        case .hrr(let r, let m): tag = "hrr"; rhr = r; hrMax = m
        case .hrMax(let m): tag = "hrmax"; hrMax = m
        case .workoutsOnly: tag = "workouts"
        case .needsAge: tag = "needsAge"
        }
        var activeKcal = carriedEnergy.kcal
        var energySig = carriedEnergy.signature
        if let energy {
            energySig = energySignature(energy.inputs, restingHr: energy.restingHr)
            activeKcal = activeEnergy(buckets: scored, samples: samples, inputs: energy.inputs, restingHr: energy.restingHr)
        }
        return IntradayDayRecord(day: day, version: version,
                                 fingerprintCount: fingerprint?.count ?? witness.count,
                                 fingerprintMaxTs: fingerprint?.maxTs ?? witness.maxTs,
                                 fingerprintSum: witness.sum,
                                 thresholdSignature: signature(thresholds, rule: rule),
                                 storeIdentity: storeIdentity,
                                 basisTag: tag, restingHr: rhr, hrMaxBpm: hrMax,
                                 moderateMin: result.moderateMin, vigorousMin: result.vigorousMin,
                                 scoredMinutes: result.scoredMinutes, bpmMin: bpmMin, bpmAvg: bpmAvg, bpmMax: bpmMax,
                                 stressMean: stress.mean, stressComputed: stress.computed,
                                 computedAt: now.timeIntervalSince1970,
                                 activeKcal: activeKcal, energySignature: energySig)
    }

    /// The day's ACTIVE energy from its heart rate: NOOP's `Calories.estimateDayEnergy(...).activeKcal`
    /// over the raw samples when given, else over the 60-second bucket means (one reading a minute, which
    /// the estimator's inferred cadence carries for 60 s). nil when the strap banked nothing. The resting
    /// part NOOP returns is dropped on purpose (observed seconds only; the card credits Mifflin–St Jeor).
    nonisolated static func activeEnergy(buckets: [HRBucket], samples: [IntensityMinutes.Sample]?,
                                         inputs: CalorieInputs, restingHr: Int?) -> Double? {
        let hr: [HRSample]
        if let samples, !samples.isEmpty {
            hr = samples.map { HRSample(ts: $0.ts, bpm: Int($0.bpm.rounded())) }
        } else {
            hr = buckets.filter { $0.bpm > 0 && $0.bpm.isFinite }.map { HRSample(ts: $0.ts, bpm: Int($0.bpm.rounded())) }
        }
        guard !hr.isEmpty else { return nil }
        let estimate = Calories.estimateDayEnergy(hr, profile: inputs.energyProfile, hrmax: inputs.hrMax,
                                                  restingHR: restingHr.map(Double.init))
        return max(0, estimate.activeKcal)
    }

    /// What an active-energy figure was computed with: the profile's signature and that day's resting
    /// reference (the Karvonen reserve the 50 % gate sits on).
    nonisolated static func energySignature(_ inputs: CalorieInputs, restingHr: Int?) -> String {
        inputs.energySignature + "|r=" + (restingHr.map { "\($0)" } ?? "-")
    }

    nonisolated static func signature(_ thresholds: IntensityMinutes.Thresholds?, rule: IntensityMinutes.BoutRule) -> String {
        (thresholds?.basis.signature ?? "needsAge") + "|" + rule.signature
    }

    /// The rows a workouts-only day is credited from: the sessions that STARTED on `day` (local), the
    /// rule the day's workout list on Home uses. A session crossing midnight belongs to one day, so its
    /// zone minutes are never counted on both days and twice in the week.
    nonisolated static func workouts(startedOn day: String, rows: [WorkoutRow]) -> [WorkoutRow] {
        rows.filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == day }
    }

    /// The store the records describe: the active read id and the first night the strap's own rows
    /// (`.noopComputed`) cover. It moves when the history under the records is replaced rather than
    /// extended: a NOOP backup restored (older nights appear), the strap's data deleted, another strap
    /// or the sample data read (`adoptActiveDeviceId`). nil before the store's first refresh, when
    /// nothing can be told and the stamps are left alone.
    static func storeIdentity(_ repo: Repository) -> String? {
        guard repo.loaded else { return nil }
        let first = repo.vitalRows.first { $0.source == .noopComputed }?.metric.day ?? "none"
        return repo.deviceId + "|" + first
    }

    // MARK: Records over the repository

    /// The records for `days` (keys on or before today), computing what is missing or stale: one
    /// 60-second bucket read per day inside `verifyWindowDays` per `refreshSeq` (today on every call),
    /// or for a day without a trusted record; one raw-sample read per day inside the window whose
    /// buckets moved; the Stress day mean (`BaselineReadouts.stressDay`, a raw read) only when
    /// `computeStress` asks and the record has none. Thresholds come from `profile` (`effortHRmax`,
    /// `hrZoneSet`) and the funnel's nights, behind the profile gate (`IntensityMinutes.mayScore`:
    /// `entered` is `BaselineReadouts.ProfileSet`, or a max-HR override): the seeded 30-year-old scores
    /// nothing, whichever screen asks, so every reader writes one signature per day and no tab re-scores
    /// another's days. Flushes the file at the end.
    ///
    /// With a `profile`, the pass also estimates each day's active energy under that profile's
    /// `CalorieInputs` (`BaselineReadouts.calorieInputs`, the one resolver the Calories card reads); with
    /// none, it leaves the records' figures as they are.
    func records(_ repo: Repository, profile: ProfileStore?, days: [String], mode: BaselineDataSource = .current(),
                 entered: Bool = BaselineReadouts.ProfileSet.current(), computeStress: Bool = false,
                 calendar: Calendar = .current, now: Date = Date()) async -> [String: IntradayDayRecord] {
        var energy: CalorieInputs? = nil
        if let profile {
            energy = await BaselineReadouts.calorieInputs(repo, profile: profile, entered: entered, now: now)
        }
        return await records(repo, effortHRmax: profile?.effortHRmax, zoneSet: profile?.hrZoneSet,
                             hrMaxOverride: profile?.hrMaxOverride ?? 0, days: days, mode: mode, entered: entered,
                             computeStress: computeStress, energy: energy, calendar: calendar, now: now)
    }

    /// `records(_:profile:days:…)` over the profile's numbers (tests pass them without a `ProfileStore`).
    func records(_ repo: Repository, effortHRmax: Double?, zoneSet: HRZoneSet?, hrMaxOverride: Int = 0,
                 days: [String], mode: BaselineDataSource = .current(),
                 entered: Bool = BaselineReadouts.ProfileSet.current(), computeStress: Bool = false,
                 energy: CalorieInputs? = nil,
                 calendar: Calendar = .current, now: Date = Date()) async -> [String: IntradayDayRecord] {
        loadIfNeeded()
        let todayKey = Repository.localDayKey(now)
        let wanted = days.filter { $0 <= todayKey }
        guard !wanted.isEmpty else { return [:] }
        // The funnel walked once for every day's resting-HR reference, and only when scoring is allowed.
        let scoring = IntensityMinutes.mayScore(entered: entered, hrMaxOverride: hrMaxOverride) && (effortHRmax ?? 0) > 0
        let funnelReferences = scoring || energy != nil
            ? IntensityMinutes.RestingReferences(BaselineReadouts.days(repo, mode: mode)) : nil
        let references = scoring ? (funnelReferences ?? IntensityMinutes.RestingReferences([]))
                                 : IntensityMinutes.RestingReferences([])
        let verifyFrom = Baselines.cutoffKey(todayKey: todayKey, carryDays: Self.verifyWindowDays)
        let seq = repo.refreshSeq
        let identity = Self.storeIdentity(repo)
        var storeOpen: Bool? = nil
        var workoutRows: [WorkoutRow]? = nil
        var out: [String: IntradayDayRecord] = [:]

        for day in wanted {
            guard let start = BaselineReadouts.localMidnight(of: day),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let from = Int(start.timeIntervalSince1970), to = Int(end.timeIntervalSince1970) - 1
            let thresholds = IntensityMinutes.thresholds(for: day, references: references, effortHRmax: effortHRmax,
                                                         zoneSet: zoneSet, entered: entered, hrMaxOverride: hrMaxOverride)
            let signature = Self.signature(thresholds, rule: rule)
            // The day's energy inputs (nil: this caller does not estimate; records keep their figures).
            let dayEnergy: (inputs: CalorieInputs, restingHr: Int?)? = energy.map {
                (inputs: $0, restingHr: funnelReferences?.reference(for: day))
            }
            let energySig = dayEnergy.map { Self.energySignature($0.inputs, restingHr: $0.restingHr) }
            func energyFresh(_ r: IntradayDayRecord?) -> Bool { energySig == nil || r?.energySignature == energySig }

            if day != todayKey, let m = memo[day], m.seq == seq, m.identity == identity,
               m.record.thresholdSignature == signature, !computeStress || m.record.stressComputed,
               energyFresh(m.record) {
                out[day] = m.record
                continue
            }

            var record = persisted[day]
            let scoredUnder = record.map { $0.thresholdSignature == signature && $0.version == Self.version } ?? false
            let sameStore = identity == nil || record?.storeIdentity == identity
            let inWindow = day >= verifyFrom
            let energyOK = energyFresh(record)
            if !(scoredUnder && sameStore && energyOK) || inWindow {
                if storeOpen == nil { storeOpen = await repo.storeHandle() != nil }
                guard storeOpen == true else {
                    // No store (a failed open): cannot tell, so nothing is computed or persisted; a record
                    // already scored under these thresholds is still shown.
                    if scoredUnder, let r = record { out[day] = r }
                    continue
                }
                let buckets = await repo.hrBuckets(from: from, to: to, bucketSeconds: 60)
                let witness = IntradayWitness(buckets: buckets)
                let same = record.map { $0.witness == witness } ?? false
                if scoredUnder && same && energyOK {
                    if let identity, record?.storeIdentity != identity {
                        record?.storeIdentity = identity
                        dirty = true
                    }
                } else {
                    // Inside the window the minutes follow §5's per-minute sample floor; a day the
                    // strap banked nothing for, or one nobody may score yet, needs no raw read.
                    var samples: [IntensityMinutes.Sample]? = nil
                    if inWindow, thresholds != nil, witness.count > 0 {
                        samples = await repo.hrSamples(from: from, to: to, limit: Self.sampleLimit)
                            .map { IntensityMinutes.Sample($0) }
                    }
                    var rows: [WorkoutRow] = []
                    if witness.count == 0 {
                        if workoutRows == nil {
                            let back = BaselineRangeSeries.dayCount(from: wanted.min() ?? day, to: todayKey) + 2
                            workoutRows = await repo.workoutRows(days: max(3, back))
                        }
                        rows = Self.workouts(startedOn: day, rows: workoutRows ?? [])
                    }
                    // A Stress mean survives a thresholds-only change (same seconds, same calm hours).
                    let carried: (Double?, Bool) = same ? (record?.stressMean, record?.stressComputed ?? false) : (nil, false)
                    // Without inputs this caller cannot estimate energy: the figure survives a thresholds-only
                    // change (same seconds), and is dropped when the seconds moved.
                    let carriedEnergy: (Double?, String?) = same ? (record?.activeKcal, record?.energySignature) : (nil, nil)
                    // The minute scan and the energy estimate are pure: run off the main actor, so a
                    // first open after a version bump (every stored day recomputed) never stalls the UI.
                    let dayRule = rule
                    let storeId = identity ?? record?.storeIdentity ?? ""
                    let workoutsForDay = rows
                    let rawSamples = samples
                    record = await Task.detached(priority: .userInitiated) {
                        Self.compute(day: day, buckets: buckets, samples: rawSamples, thresholds: thresholds,
                                     workouts: workoutsForDay, rule: dayRule, stress: carried, energy: dayEnergy,
                                     carriedEnergy: carriedEnergy, storeIdentity: storeId, now: now)
                    }.value
                    dirty = true
                }
            }
            guard var r = record else { continue }
            if computeStress, !r.stressComputed || day == todayKey {
                let mean = await BaselineReadouts.stressDay(repo, for: day, now: now, calendar: calendar,
                                                            includeTypical: false)?.dayMean
                if !r.stressComputed || mean != r.stressMean {
                    r.stressMean = mean
                    r.stressComputed = true
                    dirty = true
                }
            }
            persisted[day] = r
            memo[day] = Memo(seq: seq, identity: identity, record: r)
            out[day] = r
        }
        flush()
        return out
    }
}
#endif
