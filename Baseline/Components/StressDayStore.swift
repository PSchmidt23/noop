#if os(iOS)
import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

// Past days' Stress on the PERSONAL lens, and the 14-day typical the card compares a day with.
//
// Why Baseline folds its own lens for a past day: NOOP's `DaytimeStressMode.selected` keeps ONE slot
// (`StressLensCache`), keyed on the day it resolved for, so asking it about yesterday evicts today's lens
// and the next Home tick pays the 30-day fold again. This store makes the same two calls NOOP makes
// (`DaytimeStress.dayDaytimeAggregate` per day over `repo.hrSamples`, with R-R only while
// `daytimeRMSSDScoringEnabled`, then `scoringModeFromAggregates` over the 30 days before the day, each
// window re-anchored with `startOfDay` the way NOOP anchors it, a day with no heart rate left out of the
// fold the way NOOP leaves it out), so a past day is scored against exactly
// the lens NOOP would have resolved for it. Each day's aggregate is cached, so neighbouring days share
// their 29 overlapping days.
//
// What is kept, per local day: the heart-rate fingerprint it was computed from (`repo.hrFingerprint`, a
// COUNT and a MAX over the union of the strap ids, no rows read), the day's daytime aggregate (its P10
// waking-hour mean heart rate), and the day's state counts (`StressDayFacts`) with the lens they were
// scored under. A record is reused while its fingerprint and the lens still match; a backfill moves the
// fingerprint and the day is read again. Persisted at `<Application Support>/Baseline/stress-days.json`
// (the place `IntradayDayStore` keeps its records, for the same reasons); losing it costs a recomputation.
//
// Today is never scored here: Home reads it through NOOP's fingerprint-gated `StressDayCurve.today`.

/// One day's Stress hours as the typical needs them.
struct StressDayFacts: Codable, Equatable, Sendable {
    let restored: Int
    let calm: Int
    let elevated: Int
    let moving: Int
    let scored: Int
    /// True when the hours were judged against the personal floor (only those days enter the typical).
    let personal: Bool

    init(restored: Int, calm: Int, elevated: Int, moving: Int, scored: Int, personal: Bool) {
        self.restored = restored; self.calm = calm; self.elevated = elevated
        self.moving = moving; self.scored = scored; self.personal = personal
    }

    init(_ r: BaselineReadouts.StressDayReadout) {
        self.init(restored: r.restoredHours, calm: r.calmHours, elevated: r.elevatedHours,
                  moving: r.movingHours, scored: r.scoredHours, personal: r.lens.isPersonal)
    }

    /// The day may stand in the typical: personal lens, at least `StressState.minTotalledHours` scored.
    var qualifies: Bool { personal && scored >= StressState.minTotalledHours }
}

/// One persisted day.
struct StressDayRecord: Codable, Equatable {
    let day: String
    let version: Int
    var identity: String
    var fpCount: Int
    var fpMaxTs: Int
    /// `DaytimeStress.dayDaytimeAggregate(...).hr` once computed (nil = the day had no hour that cleared
    /// the 300-sample gate); `aggregateComputed` says a nil is an answer.
    var aggregateHR: Double?
    var aggregateComputed: Bool
    /// The day's hour counts once scored (nil = nothing scored), the lens key they were scored under.
    var facts: StressDayFacts?
    var factsComputed: Bool
    var factsLensKey: String?
    /// True when the day's heart-rate read came back empty although the fingerprint counted rows. nil on
    /// a record written before this was kept (read as false; such a day had samples).
    var aggregateReadEmpty: Bool? = nil

    /// Whether the day enters the lens fold. NOOP's resolver (`DaytimeStressMode.selected`) leaves a day
    /// with no heart rate OUT (`guard !dayHR.isEmpty else { continue }`) and folds every day with heart
    /// rate, its aggregate nil when no waking hour cleared the 300-sample gate. A left-out day is not a
    /// skip-and-hold night, so a long strap-off gap does not age the floor into `.stale`.
    var hasHeartRate: Bool { fpCount > 0 && aggregateReadEmpty != true }
}

@MainActor
final class StressDayStore {
    static let shared = StressDayStore()

    /// Bump when the record's meaning changes; every stored day recomputes.
    static let version = 1
    /// Days before a day its lens is folded from (NOOP's `DaytimeStressMode.baselineHistoryDays`).
    static let historyDays = 30
    /// Days before a day the typical is read over, and the fewest qualifying days it needs (the Oura
    /// convention; `Research/ACTIVITY_METRICS.md` §3).
    static let typicalDays = 14
    static let typicalMinDays = 5
    static let sampleLimit = 200_000
    static let fileName = "stress-days.json"

    nonisolated static var defaultFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Baseline", isDirectory: true).appendingPathComponent(fileName)
    }

    let fileURL: URL?
    private var records: [String: StressDayRecord] = [:]
    /// Day → the `refreshSeq` its fingerprint was last checked at (a past day does not move between
    /// refreshes, so one Home load checks each day once).
    private var checkedAt: [String: (seq: Int, identity: String)] = [:]
    private var loaded = false
    private var dirty = false

    init(fileURL: URL? = StressDayStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    // MARK: Pure

    /// The person's typical elevated hours: the median over `facts` of the days that qualify
    /// (`StressDayFacts.qualifies`), nil under `typicalMinDays` such days.
    /// NOOP's daytime aggregate for one day's samples, computed off the main actor.
    nonisolated static func aggregate(hr: [HRSample], rr: [RRInterval], tz: Int) async -> Double? {
        await Task.detached(priority: .userInitiated) {
            DaytimeStress.dayDaytimeAggregate(hr: hr, rr: rr, tzOffsetSeconds: tz).hr
        }.value
    }

    nonisolated static func typical(_ facts: [StressDayFacts?]) -> Double? {
        let hours = facts.compactMap { $0 }.filter(\.qualifies).map { Double($0.elevated) }
        guard hours.count >= typicalMinDays else { return nil }
        return BaselineReadouts.median(hours)
    }

    /// The Stress detail's readings: each day that may be totalled (`StressDayFacts.qualifies`: the
    /// personal lens, at least 3 scored hours) → its elevated HOURS, the Home card's "2 h elevated". A
    /// learning day or a day with too little still wear says nothing about elevated time and is absent,
    /// never a 0. The 0–3 level is never a reading.
    nonisolated static func elevatedHours(_ facts: [String: StressDayFacts]) -> [String: Double] {
        facts.filter { $0.value.qualifies }.mapValues { Double($0.elevated) }
    }

    /// The identity of a lens for the facts' staleness check (the floor to 0.1 bpm).
    nonisolated static func lensKey(_ lens: BaselineReadouts.StressLens) -> String {
        switch lens {
        case .personal(let floor): return "p:\(Int((floor * 10).rounded()))"
        case .learning(let n): return "l:\(n)"
        }
    }

    /// The lens for a day from the aggregates of the days before it (oldest → newest), and the days of
    /// history behind it: NOOP's own `scoringModeFromAggregates` and `foldAggregates`.
    nonisolated static func lens(aggregates: [Double?]) -> (mode: DaytimeStress.ScoringMode, lens: BaselineReadouts.StressLens) {
        let pairs: [(hr: Double?, rmssd: Double?)] = aggregates.map { (hr: $0, rmssd: nil) }
        let mode = DaytimeStress.scoringModeFromAggregates(pairs)
        let n = DaytimeStress.foldAggregates(pairs).hr.nValid
        return (mode, BaselineReadouts.StressLens.of(mode, daysOfHistory: n))
    }

    // MARK: Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: StressDayRecord].self, from: data) else { return }
        records = decoded.filter { $0.value.version == Self.version }
    }

    func flush() {
        guard dirty, let url = fileURL else { return }
        dirty = false
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            // A cache that cannot be written is recomputed next time.
        }
    }

    /// Drops every record (Settings › Data's "Recompute heart-rate days", and tests).
    func reset() {
        loadIfNeeded()
        records.removeAll()
        checkedAt.removeAll()
        dirty = true
        flush()
    }

    /// The stored record for `day` (tests).
    func storedRecord(_ day: String) -> StressDayRecord? {
        loadIfNeeded()
        return records[day]
    }

    // MARK: Days

    /// Local midnight → the next local midnight − 1 s of the day `back` days before `dayStart`, both
    /// re-anchored with `startOfDay` (a day-add keeps the time of day, which is an hour off on a DST day).
    private static func window(back: Int, from dayStart: Date, calendar: Calendar) -> (key: String, start: Date, from: Int, to: Int)? {
        guard let raw = calendar.date(byAdding: .day, value: -back, to: dayStart) else { return nil }
        let start = calendar.startOfDay(for: raw)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start).map({ calendar.startOfDay(for: $0) }) else { return nil }
        return (Repository.localDayKey(start), start, Int(start.timeIntervalSince1970), Int(next.timeIntervalSince1970) - 1)
    }

    /// The record for a day, its fingerprint checked against the store once per `refreshSeq`: a moved
    /// fingerprint (or another store) drops the day's aggregate and facts. nil when the store cannot tell.
    private func checkedRecord(_ repo: Repository, key: String, from: Int, to: Int) async -> StressDayRecord? {
        loadIfNeeded()
        let identity = repo.deviceId
        if let c = checkedAt[key], c.seq == repo.refreshSeq, c.identity == identity, let r = records[key] { return r }
        guard let fp = await repo.hrFingerprint(from: from, to: to) else { return nil }
        var r = records[key] ?? StressDayRecord(day: key, version: Self.version, identity: identity, fpCount: fp.count,
                                                fpMaxTs: fp.maxTs, aggregateHR: nil, aggregateComputed: false,
                                                facts: nil, factsComputed: false, factsLensKey: nil)
        if r.fpCount != fp.count || r.fpMaxTs != fp.maxTs || r.identity != identity {
            r = StressDayRecord(day: key, version: Self.version, identity: identity, fpCount: fp.count, fpMaxTs: fp.maxTs,
                                aggregateHR: nil, aggregateComputed: false, facts: nil, factsComputed: false, factsLensKey: nil)
            dirty = true
        }
        if fp.count == 0, !r.aggregateComputed {
            // No heart rate at all: the answer is known without a read.
            r.aggregateComputed = true
            r.aggregateHR = nil
            dirty = true
        }
        records[key] = r
        checkedAt[key] = (repo.refreshSeq, identity)
        return r
    }

    /// A day's entry in the lens fold: `hr` is its daytime aggregate (NOOP's P10 of its waking-hour
    /// means), nil when the day had heart rate but no waking hour cleared the 300-sample gate.
    struct FoldEntry: Equatable {
        let hr: Double?
    }

    /// The day's fold entry, read once per fingerprint; nil when the day is left out of the fold (no heart
    /// rate, or the store cannot tell: NOOP's read then comes back empty and it skips the day too).
    private func foldEntry(_ repo: Repository, key: String, start: Date, from: Int, to: Int) async -> FoldEntry? {
        guard var r = await checkedRecord(repo, key: key, from: from, to: to) else { return nil }
        if r.aggregateComputed { return r.hasHeartRate ? FoldEntry(hr: r.aggregateHR) : nil }
        let hr = await repo.hrSamples(from: from, to: to, limit: Self.sampleLimit)
        let rr = DaytimeStress.daytimeRMSSDScoringEnabled && !hr.isEmpty
            ? await repo.rrIntervals(from: from, to: to, limit: Self.sampleLimit) : []
        let tz = TimeZone.current.secondsFromGMT(for: start)
        r.aggregateHR = hr.isEmpty ? nil : await Self.aggregate(hr: hr, rr: rr, tz: tz)
        r.aggregateReadEmpty = hr.isEmpty
        r.aggregateComputed = true
        records[key] = r
        dirty = true
        return r.hasHeartRate ? FoldEntry(hr: r.aggregateHR) : nil
    }

    /// The lens for the day starting at `dayStart`: the fold over the `historyDays` days before it, and
    /// the days of history behind it. Days without heart rate are left out, as NOOP's resolver leaves
    /// them out, so a past day gets the lens NOOP gave it when it was today.
    func lens(_ repo: Repository, dayStart: Date, calendar: Calendar = .current)
        async -> (mode: DaytimeStress.ScoringMode, lens: BaselineReadouts.StressLens, daysOfHistory: Int) {
        var aggregates: [Double?] = []
        aggregates.reserveCapacity(Self.historyDays)
        for back in stride(from: Self.historyDays, through: 1, by: -1) {
            guard let w = Self.window(back: back, from: dayStart, calendar: calendar),
                  let entry = await foldEntry(repo, key: w.key, start: w.start, from: w.from, to: w.to) else { continue }
            aggregates.append(entry.hr)
        }
        let pairs: [(hr: Double?, rmssd: Double?)] = aggregates.map { (hr: $0, rmssd: nil) }
        let n = DaytimeStress.foldAggregates(pairs).hr.nValid
        let resolved = Self.lens(aggregates: aggregates)
        flush()
        return (resolved.mode, resolved.lens, n)
    }

    /// A PAST day scored on its personal lens: its streams read once (heart rate, R-R, gravity for the
    /// motion gate), nil when it carries fewer than `DaytimeStress.minHourHRSamples` samples. Its facts
    /// are kept for the typical.
    func analyze(_ repo: Repository, day: String, dayStart: Date, calendar: Calendar = .current)
        async -> (result: DaytimeStress.Result, lens: BaselineReadouts.StressLens)? {
        guard let w = Self.window(back: 0, from: dayStart, calendar: calendar) else { return nil }
        let resolved = await lens(repo, dayStart: w.start, calendar: calendar)
        let hr = await repo.hrSamples(from: w.from, to: w.to, limit: Self.sampleLimit)
        guard hr.count >= DaytimeStress.minHourHRSamples else {
            await storeFacts(repo, key: w.key, from: w.from, to: w.to, facts: nil, lens: resolved.lens, hr: hr, start: w.start)
            return nil
        }
        let rr = await repo.rrIntervals(from: w.from, to: w.to, limit: Self.sampleLimit)
        let gravity = await repo.gravitySamplesUnion(from: w.from, to: w.to, limit: Self.sampleLimit)
        let tz = TimeZone.current.secondsFromGMT(for: w.start)
        let mode = resolved.mode
        // A day of samples is tens of thousands of points: scored off the main actor so the screen that
        // asked stays responsive (the store itself stays main-actor; only the pure fold moves).
        let result = await Task.detached(priority: .userInitiated) {
            DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity, tzOffsetSeconds: tz,
                                  mode: mode, includeTimeline: true)
        }.value
        let facts = BaselineReadouts.stressDay(result, day: day, lens: resolved.lens).map(StressDayFacts.init)
        await storeFacts(repo, key: w.key, from: w.from, to: w.to, facts: facts, lens: resolved.lens, hr: hr, start: w.start)
        return (result, resolved.lens)
    }

    /// Keeps a scored day's facts (and its aggregate, from the samples already in hand).
    private func storeFacts(_ repo: Repository, key: String, from: Int, to: Int, facts: StressDayFacts?,
                            lens: BaselineReadouts.StressLens, hr: [HRSample], start: Date) async {
        guard var r = await checkedRecord(repo, key: key, from: from, to: to) else { return }
        // The aggregate from the samples already in hand, when R-R cannot change it (NOOP folds HR only
        // while the RMSSD term is disabled); otherwise `aggregate` reads it with R-R when asked.
        if !r.aggregateComputed, !DaytimeStress.daytimeRMSSDScoringEnabled {
            let tz = TimeZone.current.secondsFromGMT(for: start)
            r.aggregateHR = hr.isEmpty ? nil : await Self.aggregate(hr: hr, rr: [], tz: tz)
            r.aggregateReadEmpty = hr.isEmpty
            r.aggregateComputed = true
        }
        r.facts = facts
        r.factsComputed = true
        r.factsLensKey = Self.lensKey(lens)
        records[key] = r
        dirty = true
        flush()
    }

    /// The person's typical elevated hours for `day`: the median elevated hours over the 14 days before
    /// it that were scored on the personal lens with at least 3 scored hours, nil under 5 such days. A
    /// day whose facts are missing, or were scored under another lens or other heart rate, is scored
    /// again (once; then kept).
    func typicalElevatedHours(_ repo: Repository, before day: String, calendar: Calendar = .current) async -> Double? {
        guard let dayStart = BaselineReadouts.localMidnight(of: day) else { return nil }
        var facts: [StressDayFacts?] = []
        for back in stride(from: Self.typicalDays, through: 1, by: -1) {
            guard let w = Self.window(back: back, from: dayStart, calendar: calendar) else { continue }
            facts.append(await cachedFacts(repo, key: w.key, start: w.start, from: w.from, to: w.to, calendar: calendar))
        }
        flush()
        return Self.typical(facts)
    }

    /// Each PAST day's facts among `days` on its own lens: the records the typical reads, so the Stress
    /// detail's 7D / 4W hours and the card's typical come from one place. A day whose facts are missing,
    /// or were scored under another lens or other heart rate, is scored once and kept. With
    /// `scoreMissing` false (the 1Y range) only days already scored are read, never a year of raw
    /// streams. A day without heart rate is absent, and so is today (NOOP's `StressDayCurve.today`).
    func facts(_ repo: Repository, days: [String], scoreMissing: Bool = true, calendar: Calendar = .current,
               now: Date = Date()) async -> [String: StressDayFacts] {
        loadIfNeeded()
        let todayKey = Repository.localDayKey(now)
        var out: [String: StressDayFacts] = [:]
        for day in days where day < todayKey {
            guard scoreMissing else {
                if let r = records[day], r.factsComputed, let f = r.facts { out[day] = f }
                continue
            }
            guard let start = BaselineReadouts.localMidnight(of: day),
                  let w = Self.window(back: 0, from: start, calendar: calendar) else { continue }
            if let f = await cachedFacts(repo, key: w.key, start: w.start, from: w.from, to: w.to, calendar: calendar) {
                out[day] = f
            }
        }
        flush()
        return out
    }

    /// One past day's facts, reused while they were scored under the day's current lens and heart rate,
    /// otherwise scored again (once; then kept). nil without heart rate or when nothing was scored.
    private func cachedFacts(_ repo: Repository, key: String, start: Date, from: Int, to: Int,
                             calendar: Calendar) async -> StressDayFacts? {
        guard let r = await checkedRecord(repo, key: key, from: from, to: to), r.fpCount > 0 else { return nil }
        let resolved = await lens(repo, dayStart: start, calendar: calendar)
        if r.factsComputed, r.factsLensKey == Self.lensKey(resolved.lens) { return r.facts }
        _ = await analyze(repo, day: key, dayStart: start, calendar: calendar)
        return records[key]?.facts
    }
}
#endif
