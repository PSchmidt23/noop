#if os(iOS)
import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

// Intensity minutes: minutes of the day spent at moderate (≥ 40 % of heart-rate reserve) or vigorous
// (≥ 60 %) intensity, vigorous counted twice, summed Monday → Sunday against a weekly goal (default
// 150). The definition, the evidence and every number here are in
// `Baseline/Research/INTENSITY_MINUTES.md` §5 (Karvonen %HRR with ACSM cut-offs; WHO 2020 / HHS 2018:
// bouts of any length count, so the bout floor below is a noise filter, not a guideline). "Intensity
// minutes" is the generic term; no vendor's feature name appears in copy.
//
// Two ways from heart rate to scored minutes, and which one a day gets:
//   • `minutes(samples:)`, §5's rule: a minute counts only with ≥ 20 samples, its heart rate their
//     median. `IntradayDayStore` classifies every day inside its 14-day verify window this way (raw
//     `repo.hrSamples`, measured ∪ PPG-derived), so a sparse minute (the ~30-second live heart rate of a
//     WHOOP 5.0 / MG, the edges of wear) neither earns credit nor counts toward the 240-minute line
//     under which a day is captioned "partial day";
//   • `minutes(buckets:)`, the 60-second bucket means with NO sample floor (a bucket carries no count):
//     only an older day the store computes for the first time (a long range opened after install), where
//     reading every second of every day is the cost the per-day cache exists to avoid. Such a day keeps
//     its bucket-mean figures; the three-minute bout floor is its only noise filter.
//
// Pure: minutes in, minutes out. The per-day record cache and the weekly readout over the repository
// live in `IntradayDayStore` / `BaselineReadouts.intensity`.

enum IntensityMinutes {

    // MARK: Inputs

    /// One heart-rate sample (`HRSample` without the protocol import, so tests can build traces).
    struct Sample: Equatable {
        /// Unix seconds.
        let ts: Int
        let bpm: Double

        init(ts: Int, bpm: Double) { self.ts = ts; self.bpm = bpm }
        init(_ s: HRSample) { self.init(ts: s.ts, bpm: Double(s.bpm)) }
    }

    /// One scored local-clock minute: its start (unix seconds, a multiple of 60 in the day's zone) and
    /// the heart rate that stands for it (the median of its samples, or a 60-second bucket's mean).
    struct Minute: Equatable {
        let start: Int
        let bpm: Double
    }

    /// Where the thresholds come from, carried on every readout so a card can say which.
    enum Basis: Equatable {
        /// Karvonen %HRR against the resting-HR reference and the max heart rate.
        case hrr(restingHr: Int, hrMax: Int)
        /// No resting-HR reference: NOOP's %HRmax zones (moderate = Zone 3+, vigorous = Zone 4+).
        case hrMax(hrMax: Int)
        /// A day with no strap heart rate but imported workouts carrying zone percentages.
        case workoutsOnly
        /// No max heart rate: the profile has neither an age nor an override; nothing is computed.
        case needsAge

        /// A short stable string for cache keys ("hrr:52:182").
        var signature: String {
            switch self {
            case .hrr(let r, let m): return "hrr:\(r):\(m)"
            case .hrMax(let m): return "hrmax:\(m)"
            case .workoutsOnly: return "workouts"
            case .needsAge: return "needsAge"
            }
        }

        /// The basis line under the week: "40 % / 60 % of your heart-rate reserve (resting 52, max 182)".
        var caption: String {
            switch self {
            case .hrr(let r, let m):
                return "\(Int(Thresholds.moderatePctHRR)) % / \(Int(Thresholds.vigorousPctHRR)) % of your heart-rate reserve (resting \(r), max \(m))"
            case .hrMax(let m):
                return "Zone 3 / Zone 4 of your max heart rate (\(m)), no resting-HR reference yet"
            case .workoutsOnly:
                return "From workouts only"
            case .needsAge:
                return "Add your age or max heart rate in Settings › Profile"
            }
        }
    }

    /// The bpm floors a minute is judged against.
    struct Thresholds: Equatable {
        /// Lowest heart rate that counts as moderate / vigorous.
        let moderateBpm: Double
        let vigorousBpm: Double
        let basis: Basis

        /// ACSM / Garber 2011 cut-offs in percent of heart-rate reserve.
        static let moderatePctHRR = 40.0
        static let vigorousPctHRR = 60.0

        /// Karvonen: `bpm = resting + pct · (max − resting)`. nil when the reserve is not positive.
        static func karvonen(restingHr: Int, hrMax: Int) -> Thresholds? {
            let reserve = Double(hrMax - restingHr)
            guard reserve > 0, restingHr > 0 else { return nil }
            return Thresholds(moderateBpm: Double(restingHr) + moderatePctHRR / 100 * reserve,
                              vigorousBpm: Double(restingHr) + vigorousPctHRR / 100 * reserve,
                              basis: .hrr(restingHr: restingHr, hrMax: hrMax))
        }

        /// The %HRmax fallback over NOOP's zone model (`ProfileStore.hrZoneSet`, custom bounds honoured):
        /// moderate from Zone 3's lower edge (70 % by default), vigorous from Zone 4's (80 %).
        static func hrMax(zoneSet: HRZoneSet) -> Thresholds? {
            guard zoneSet.zones.count == 5 else { return nil }
            return Thresholds(moderateBpm: zoneSet.zones[2].lower, vigorousBpm: zoneSet.zones[3].lower,
                              basis: .hrMax(hrMax: Int(zoneSet.maxHR.rounded())))
        }

        /// `pctHRR` for a heart rate under an HRR basis (nil under another basis).
        func pctHRR(_ bpm: Double) -> Double? {
            guard case .hrr(let r, let m) = basis, m > r else { return nil }
            return (bpm - Double(r)) / Double(m - r) * 100
        }
    }

    /// The bout rule. A bout is a maximal run of moderate-or-above minutes tolerating gaps of at most
    /// `gapToleranceMinutes` consecutive below / unscored minutes (a gap minute earns nothing and does not
    /// break the bout); a longer gap ends it. A bout is credited only when it holds at least `minMinutes`
    /// qualifying minutes.
    struct BoutRule: Equatable {
        let minMinutes: Int
        let gapToleranceMinutes: Int

        /// Baseline's rule (`INTENSITY_MINUTES.md` §5): three qualifying minutes, one-minute gaps
        /// tolerated. WHO 2020 and HHS 2018 count bouts of any duration; the three-minute floor only damps
        /// single-minute artefacts and HR rises without movement.
        static let `default` = BoutRule(minMinutes: 3, gapToleranceMinutes: 1)

        /// The older ten-consecutive-minute convention (pre-2018 guidelines, older Garmin manuals). Kept
        /// so a stricter reading can be compared; not what the app shows.
        static let tenMinute = BoutRule(minMinutes: 10, gapToleranceMinutes: 1)

        var signature: String { "b\(minMinutes)g\(gapToleranceMinutes)" }
    }

    enum Class: Equatable {
        case vigorous, moderate, below
    }

    /// One credited bout: its first and last qualifying minute and what it earned.
    struct Bout: Equatable, Identifiable {
        let start: Int
        let end: Int
        let moderateMin: Int
        let vigorousMin: Int

        var id: Int { start }
        var credited: Int { moderateMin + 2 * vigorousMin }
    }

    /// A day's result.
    struct DayResult: Equatable {
        let day: String
        /// Raw minutes at moderate (≥ 40 % and < 60 % HRR) and vigorous (≥ 60 %) intensity inside
        /// credited bouts.
        let moderateMin: Int
        let vigorousMin: Int
        let bouts: [Bout]
        /// Minutes of the day with a scored heart rate at all.
        let scoredMinutes: Int
        let basis: Basis

        /// Moderate ×1 + vigorous ×2: the number a card prints and the week sums.
        var credited: Int { moderateMin + 2 * vigorousMin }

        static func empty(day: String, basis: Basis, scoredMinutes: Int = 0) -> DayResult {
            DayResult(day: day, moderateMin: 0, vigorousMin: 0, bouts: [], scoredMinutes: scoredMinutes, basis: basis)
        }
    }

    // MARK: Minutes from streams

    /// Fewest samples a minute needs before its heart rate is trusted (≈ 20 s at 1 Hz).
    static let minSamplesPerMinute = 20

    /// Raw samples → scored minutes (`INTENSITY_MINUTES.md` §5): samples bucketed into local-clock
    /// minutes (`start = ts − ts mod 60`, which in every whole-minute zone is the clock minute), a minute
    /// scored only with `minSamples` or more, its heart rate the MEDIAN of its samples (robust to a
    /// single artefact). Sorted by start.
    static func minutes(samples: [Sample], minSamples: Int = minSamplesPerMinute) -> [Minute] {
        var byMinute: [Int: [Double]] = [:]
        for s in samples where s.bpm > 0 && s.bpm.isFinite {
            byMinute[s.ts - ((s.ts % 60) + 60) % 60, default: []].append(s.bpm)
        }
        return byMinute.keys.sorted().compactMap { start in
            guard let v = byMinute[start], v.count >= minSamples else { return nil }
            return Minute(start: start, bpm: BaselineReadouts.median(v))
        }
    }

    /// 60-second store buckets (`repo.hrBuckets(from:to:bucketSeconds: 60)`) → scored minutes: one
    /// minute per bucket at its mean. The per-sample floor above cannot be applied (a bucket carries no
    /// count), so a bucket of one or two seconds is a whole minute here; the bout rule damps it. The app
    /// takes this path only for an older day computed for the first time (60× fewer rows than samples);
    /// the days inside `IntradayDayStore.verifyWindowDays` go through `minutes(samples:)`.
    static func minutes(buckets: [HRBucket]) -> [Minute] {
        buckets.filter { $0.bpm > 0 && $0.bpm.isFinite }
            .sorted { $0.ts < $1.ts }
            .map { Minute(start: $0.ts - (($0.ts % 60) + 60) % 60, bpm: $0.bpm) }
    }

    // MARK: Classification

    static func classify(_ bpm: Double, thresholds: Thresholds) -> Class {
        if bpm >= thresholds.vigorousBpm { return .vigorous }
        if bpm >= thresholds.moderateBpm { return .moderate }
        return .below
    }

    /// The credited bouts over `minutes` (any order; duplicates by start keep the first) under `rule`.
    /// Minutes absent from the list are unscored and behave as gaps.
    static func bouts(_ minutes: [Minute], thresholds: Thresholds, rule: BoutRule = .default) -> [Bout] {
        var byStart: [Int: Double] = [:]
        for m in minutes where byStart[m.start] == nil { byStart[m.start] = m.bpm }
        let starts = byStart.keys.sorted()
        var out: [Bout] = []
        var current: (start: Int, end: Int, moderate: Int, vigorous: Int)? = nil
        var gap = 0

        func close() {
            if let c = current, c.moderate + c.vigorous >= rule.minMinutes {
                out.append(Bout(start: c.start, end: c.end, moderateMin: c.moderate, vigorousMin: c.vigorous))
            }
            current = nil
            gap = 0
        }

        var previous: Int? = nil
        for start in starts {
            // Unscored minutes between two scored ones are gaps too.
            if let p = previous, current != nil {
                let missing = (start - p) / 60 - 1
                if missing > 0 {
                    gap += missing
                    if gap > rule.gapToleranceMinutes { close() }
                }
            }
            previous = start
            guard let bpm = byStart[start] else { continue }
            switch classify(bpm, thresholds: thresholds) {
            case .below:
                if current != nil {
                    gap += 1
                    if gap > rule.gapToleranceMinutes { close() }
                }
            case .moderate, .vigorous:
                let vigorous = bpm >= thresholds.vigorousBpm
                if var c = current {
                    c.end = start
                    if vigorous { c.vigorous += 1 } else { c.moderate += 1 }
                    current = c
                } else {
                    current = (start, start, vigorous ? 0 : 1, vigorous ? 1 : 0)
                }
                gap = 0
            }
        }
        close()
        return out
    }

    /// The day's result: bouts credited under `rule`, totals summed.
    static func credit(day: String, minutes: [Minute], thresholds: Thresholds, rule: BoutRule = .default) -> DayResult {
        let list = bouts(minutes, thresholds: thresholds, rule: rule)
        return DayResult(day: day,
                         moderateMin: list.reduce(0) { $0 + $1.moderateMin },
                         vigorousMin: list.reduce(0) { $0 + $1.vigorousMin },
                         bouts: list, scoredMinutes: Set(minutes.map(\.start)).count, basis: thresholds.basis)
    }

    /// A day with no heart-rate stream but imported workouts carrying zone percentages
    /// (`WorkoutZones.summary` over the rows that overlap the day): moderate = Zone 3 minutes, vigorous =
    /// Zones 4 + 5, no bout rule, `basis: .workoutsOnly`. nil when no row carries zones.
    static func creditFromWorkouts(day: String, rows: [WorkoutRow]) -> DayResult? {
        guard let summary = WorkoutZones.summary(from: rows), summary.minutes.count == 5 else { return nil }
        let moderate = Int(summary.minutes[2].rounded())
        let vigorous = Int((summary.minutes[3] + summary.minutes[4]).rounded())
        guard moderate + vigorous > 0 else { return nil }
        return DayResult(day: day, moderateMin: moderate, vigorousMin: vigorous, bouts: [],
                         scoredMinutes: 0, basis: .workoutsOnly)
    }

    // MARK: Resting-HR reference

    /// Nights the resting-HR reference needs before the median is used.
    static let referenceMinNights = 3

    /// The resting-HR reference for `day`: the median of the last seven nights' resting HR in `days`
    /// (the funnel, oldest → newest) ending the night BEFORE the day (≥ `referenceMinNights`), else the
    /// day's own resting HR, else nil (the %HRmax fallback applies).
    static func restingReference(for day: String, days: [DailyMetric]) -> Int? {
        let from = Baselines.cutoffKey(todayKey: day, carryDays: 7)
        let recent = days.filter { $0.day >= from && $0.day < day }.compactMap(\.restingHr).map(Double.init)
        if recent.count >= referenceMinNights {
            return Int(BaselineReadouts.median(recent).rounded())
        }
        return days.last(where: { $0.day == day })?.restingHr
    }

    /// `restingReference(for:days:)` for many days over ONE funnel: the rows walked once into a sorted
    /// list, then each day is two binary searches and at most seven values. A 1-year range asks the day
    /// store for 730 days, and filtering the whole funnel per day was ~3 M string compares per reload.
    /// Same answer as `restingReference(for:days:)` for every day (`IntensityMinutesTests`).
    struct RestingReferences {
        /// Day keys of the rows carrying a resting HR, ascending, and their values.
        private let keys: [String]
        private let values: [Double]
        /// The LAST row's resting HR per day (nil when that row has none), the fallback's lookup.
        private let own: [String: Int?]

        init(_ days: [DailyMetric]) {
            // (row order, day, value) for every row with a resting HR, then by day (stable on order).
            var rows: [(order: Int, day: String, value: Double)] = []
            var own: [String: Int?] = [:]
            for (order, d) in days.enumerated() {
                if let rhr = d.restingHr { rows.append((order: order, day: d.day, value: Double(rhr))) }
                own.updateValue(d.restingHr, forKey: d.day)
            }
            rows.sort { a, b in a.day == b.day ? a.order < b.order : a.day < b.day }
            keys = rows.map { $0.day }
            values = rows.map { $0.value }
            self.own = own
        }

        /// The reference for `day` (see `restingReference(for:days:)`).
        func reference(for day: String) -> Int? {
            let lo = lowerBound(Baselines.cutoffKey(todayKey: day, carryDays: 7)), hi = lowerBound(day)
            let recent = lo < hi ? Array(values[lo..<hi]) : []
            if recent.count >= referenceMinNights {
                return Int(BaselineReadouts.median(recent).rounded())
            }
            return own[day] ?? nil
        }

        /// First index whose key is not below `key`.
        private func lowerBound(_ key: String) -> Int {
            var lo = 0, hi = keys.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if keys[mid] < key { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
    }

    /// The thresholds for `day` from the profile's max heart rate and the funnel's nights: Karvonen when
    /// a resting reference exists, else NOOP's %HRmax zones, else `.needsAge` (nil thresholds).
    static func thresholds(for day: String, days: [DailyMetric], effortHRmax: Double?,
                           zoneSet: HRZoneSet?) -> Thresholds? {
        thresholds(effortHRmax: effortHRmax, zoneSet: zoneSet) { restingReference(for: day, days: days) }
    }

    /// The one rule behind both forms: the reference is asked for only once a max heart rate exists.
    private static func thresholds(effortHRmax: Double?, zoneSet: HRZoneSet?,
                                   restingReference: () -> Int?) -> Thresholds? {
        guard let hrMax = effortHRmax, hrMax > 0 else { return nil }
        if let rhr = restingReference(),
           let t = Thresholds.karvonen(restingHr: rhr, hrMax: Int(hrMax.rounded())) {
            return t
        }
        if let zoneSet { return Thresholds.hrMax(zoneSet: zoneSet) }
        return nil
    }

    // MARK: The profile gate

    /// Whether the classifier may score against the profile's max heart rate: the person has entered a
    /// date of birth (`entered`, `BaselineReadouts.ProfileSet`) or set a max heart rate by hand. NOOP's
    /// `ProfileStore` seeds a 30-year-old when nothing is stored, so its `effortHRmax` (Tanaka from that
    /// age) is never nil by itself; until this is true the minutes are `.needsAge` and every screen asks
    /// for the age instead of crediting a stranger's maximum. The ONE predicate: the store's thresholds
    /// (`thresholds(for:days:effortHRmax:zoneSet:entered:hrMaxOverride:)`) and the profile the screens
    /// quote (`BaselineReadouts.intensityProfile`) both read it.
    static func mayScore(entered: Bool, hrMaxOverride: Int) -> Bool {
        entered || hrMaxOverride > 0
    }

    /// `thresholds(for:days:effortHRmax:zoneSet:)` behind `mayScore`: nil (`.needsAge`) for the seeded
    /// profile. What `IntradayDayStore.records` scores every day with, so no reader can bypass the gate.
    static func thresholds(for day: String, days: [DailyMetric], effortHRmax: Double?, zoneSet: HRZoneSet?,
                           entered: Bool, hrMaxOverride: Int) -> Thresholds? {
        guard mayScore(entered: entered, hrMaxOverride: hrMaxOverride) else { return nil }
        return thresholds(for: day, days: days, effortHRmax: effortHRmax, zoneSet: zoneSet)
    }

    /// The same gated thresholds over a `RestingReferences` index built once per read (the day store's
    /// path; the reference is looked up only when the gate and the max heart rate allow scoring).
    static func thresholds(for day: String, references: RestingReferences, effortHRmax: Double?,
                           zoneSet: HRZoneSet?, entered: Bool, hrMaxOverride: Int) -> Thresholds? {
        guard mayScore(entered: entered, hrMaxOverride: hrMaxOverride) else { return nil }
        return thresholds(effortHRmax: effortHRmax, zoneSet: zoneSet) { references.reference(for: day) }
    }

    // MARK: Week and goal

    /// The Monday (local) of the week `day` falls in, as a day key; `day` itself when the key does not parse.
    static func weekStart(of day: String, calendar: Calendar = .current) -> String {
        BaselineRangeSeries.bucketStart(of: day, bucket: .week, calendar: calendar) ?? day
    }

    /// Monday … `day` inclusive (1–7 keys), the days a week total sums up to `day`.
    static func weekDays(ending day: String, calendar: Calendar = .current) -> [String] {
        BaselineReadouts.dayKeys(from: weekStart(of: day, calendar: calendar), to: day)
    }

    /// The week `day` falls in, Monday → `day`, over per-day credited minutes (`readings`: one per
    /// recorded day): `BaselineRangeSeries.weekTotals`, the one week builder Home's card, Trends' card and
    /// the detail's hero all sum through. nil only for an unparseable key.
    static func week(ending day: String, readings: [MetricDayValue], calendar: Calendar = .current) -> MetricWeekTotal? {
        BaselineRangeSeries.weekTotals(readings, from: day, to: day, calendar: calendar).last
    }

    /// "38 moderate · 37 vigorous, counted double": raw minutes, the vigorous ones credited twice. The one
    /// spelling of the split (Home's card, the 1D week card, the range hero).
    static func splitText(moderate: Int, vigorous: Int) -> String {
        "\(moderate) moderate · \(vigorous) vigorous, counted double"
    }

    /// `baseline.intensityGoalMinutes` in `UserDefaults.standard`: credited minutes per week, default 150
    /// (WHO 2020 / HHS 2018), editable `goalRange` in steps of `goalStep`.
    static let goalKey = "baseline.intensityGoalMinutes"
    static let goalDefault = 150
    static let goalRange = 60...600
    static let goalStep = 10

    /// The stored goal, clamped to `goalRange`; the default when unset.
    static func goal(_ defaults: UserDefaults = .standard) -> Int {
        guard let v = defaults.object(forKey: goalKey) as? Int else { return goalDefault }
        return min(goalRange.upperBound, max(goalRange.lowerBound, v))
    }

    static func saveGoal(_ goal: Int, _ defaults: UserDefaults = .standard) {
        defaults.set(min(goalRange.upperBound, max(goalRange.lowerBound, goal)), forKey: goalKey)
    }

    /// Minutes of heart rate under which a day is captioned "partial day".
    static let partialDayMinutes = 240
}

// MARK: - Readout

extension BaselineReadouts {

    /// A day's Intensity minutes with its week, as Home's card and the detail print them.
    struct IntensityReadout: Equatable {
        let day: String
        let moderateMin: Int
        let vigorousMin: Int
        /// The Monday's day key.
        let weekStart: String
        /// Credited minutes Monday … `day` (length 1–7); a day with nothing scored is 0.
        let weekDays: [Int]
        let weekGoal: Int
        let basis: IntensityMinutes.Basis
        /// Minutes of the day with a scored heart rate; under `IntensityMinutes.partialDayMinutes` the
        /// card says "partial day".
        let scoredMinutes: Int

        var creditedToday: Int { moderateMin + 2 * vigorousMin }
        var weekCredited: Int { weekDays.reduce(0, +) }
        var partialDay: Bool { basis != .workoutsOnly && scoredMinutes < IntensityMinutes.partialDayMinutes }
        /// 0…1 of the goal.
        var weekFraction: Double { weekGoal > 0 ? min(1, Double(weekCredited) / Double(weekGoal)) : 0 }

        /// "112 / 150 this week".
        var weekText: String { "\(weekCredited) / \(weekGoal) this week" }
        /// "38 moderate · 37 vigorous, counted double" (`IntensityMinutes.splitText`).
        var splitText: String { IntensityMinutes.splitText(moderate: moderateMin, vigorous: vigorousMin) }
        /// The one caveat under the detail (`MetricAccuracy`-style; the metric is Medium).
        static let caveat = "Minutes near the moderate line and strength sessions are uncertain."
    }

    /// The readout for `day` over the per-day records (`IntradayDayStore`), the week summed Monday → `day`
    /// through `IntensityMinutes.week(ending:readings:)` (the week builder Trends and the detail share).
    /// Pure: `records` is day key → result, `goal` the stored weekly goal. `basis` is the day's own; a
    /// day without a record reads as zero scored minutes under `fallbackBasis`.
    static func intensity(for day: String, records: [String: IntensityMinutes.DayResult], goal: Int,
                          fallbackBasis: IntensityMinutes.Basis, calendar: Calendar = .current) -> IntensityReadout {
        let keys = IntensityMinutes.weekDays(ending: day, calendar: calendar)
        let today = records[day]
        // One reading per recorded day (the predicate the detail and Trends count with); a day without
        // one is 0 on the track's bars and in the total.
        let readings = records.compactMap { key, r -> MetricDayValue? in
            IntradayDayRecord.isRecorded(scoredMinutes: r.scoredMinutes, credited: r.credited)
                ? MetricDayValue(day: key, value: Double(r.credited)) : nil
        }
        let week = IntensityMinutes.week(ending: day, readings: readings, calendar: calendar)
        let weekDays = (week?.days ?? []).prefix(keys.count).map { Int(($0 ?? 0).rounded()) }
        return IntensityReadout(day: day,
                                moderateMin: today?.moderateMin ?? 0,
                                vigorousMin: today?.vigorousMin ?? 0,
                                weekStart: week?.id ?? keys.first ?? day,
                                weekDays: weekDays.isEmpty ? keys.map { _ in 0 } : weekDays,
                                weekGoal: goal,
                                basis: today?.basis ?? fallbackBasis,
                                scoredMinutes: today?.scoredMinutes ?? 0)
    }

    /// The readout over the day store's records (`IntradayDayStore.records`): the days scored on a basis
    /// (never a `.needsAge` day's zeros), then `intensity(for:records:…)`. Pure; what the repository
    /// accessor below returns.
    static func intensity(for day: String, dayRecords: [String: IntradayDayRecord], goal: Int,
                          fallbackBasis: IntensityMinutes.Basis, calendar: Calendar = .current) -> IntensityReadout {
        var results: [String: IntensityMinutes.DayResult] = [:]
        for (k, r) in dayRecords where r.basisIsScored { results[k] = r.dayResult }
        return intensity(for: day, records: results, goal: goal, fallbackBasis: fallbackBasis, calendar: calendar)
    }

    /// The profile the Intensity classifier may use, nil until `IntensityMinutes.mayScore` holds (a date
    /// of birth entered, `ProfileSet`, or a max heart rate set by hand). The one resolver for every
    /// screen that quotes or keys on the classifier's max heart rate (Home, the detail's week view,
    /// Settings); `IntradayDayStore.records` applies the same predicate to every day it scores.
    @MainActor
    static func intensityProfile(_ profile: ProfileStore?, entered: Bool = ProfileSet.current()) -> ProfileStore? {
        guard let profile, IntensityMinutes.mayScore(entered: entered, hrMaxOverride: profile.hrMaxOverride) else { return nil }
        return profile
    }

    /// The readout for `day` through the repository: the week's records from `IntradayDayStore` (each
    /// day classified once and persisted), thresholds from `profile` behind the profile gate
    /// (`intensityProfile`: `.needsAge` until an age or a max heart rate is entered) and the funnel's
    /// nights. nil only when the day key does not parse.
    @MainActor
    static func intensity(_ repo: Repository, profile: ProfileStore?, for day: String,
                          mode: BaselineDataSource = .current(), entered: Bool = ProfileSet.current(),
                          calendar: Calendar = .current, now: Date = Date()) async -> IntensityReadout? {
        guard localMidnight(of: day) != nil else { return nil }
        let keys = IntensityMinutes.weekDays(ending: day, calendar: calendar)
        let records = await IntradayDayStore.shared.records(repo, profile: profile, days: keys, mode: mode,
                                                            entered: entered, computeStress: false,
                                                            calendar: calendar, now: now)
        let hrMax = intensityProfile(profile, entered: entered)?.effortHRmax ?? 0
        let fallback: IntensityMinutes.Basis = hrMax > 0 ? .hrMax(hrMax: Int(hrMax.rounded())) : .needsAge
        return intensity(for: day, dayRecords: records, goal: IntensityMinutes.goal(), fallbackBasis: fallback, calendar: calendar)
    }
}
#endif
