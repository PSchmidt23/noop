#if os(iOS)
import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

// The second half of `BaselineReadouts`: Readiness (NOOP's 0–100 composite), Steps, Calories, Stress,
// sleep timing and fitness. Pure value math over the funnel's rows (`repo.baselineDays`), the Sleep tab's
// `SleepNight`s and NOOP's own engine results; the `@MainActor` accessors at the bottom are the only
// place a repository is read, and they only fetch streams NOOP already stores. Vocabulary: Readiness,
// Effort, Steps, Calories, Stress, Sleep. NOOP's identifiers (`recovery`, `strain`, `ChargeDriver`)
// appear only as code names.

// MARK: - Readiness

/// The three judgements the Readiness score can carry, cut at NOOP's own bands
/// (`RecoveryScorer.bandRedMax` 34 / `bandYellowMax` 67): `good` ≥ 67, `watch` 34…66, `low` < 34.
enum ReadinessTone: Equatable {
    case good, watch, low

    /// The pill / bar label beside the number: one plain word in Baseline's vocabulary.
    var label: String {
        switch self {
        case .good: return "Good"
        case .watch: return "Steady"
        case .low: return "Low"
        }
    }
}

extension BaselineReadouts {

    /// NOOP's weighted-z composite for one morning, read from the funnel (`DailyMetric.recovery`), never
    /// recomputed: the number the strap scored (or, on an imported day, WHOOP's own) is the number shown.
    struct ReadinessScore {
        let day: String
        /// 0–100.
        let score: Double
        let tone: ReadinessTone
        /// `.calibrating` never reaches a caller (the readout is nil without a score); `.building` until
        /// the HRV baseline is trusted (14 valid nights), then `.solid`.
        let confidence: ScoreConfidence
        /// NOOP's driver rows (`RecoveryScorer.chargeDrivers`), biggest mover first; empty when the night
        /// cannot be broken down (no HRV or resting HR, or an HRV baseline not yet usable, as on the
        /// first imported days).
        let drivers: [ChargeDriver]
        /// One short sentence from the top two drivers ("Lifted by heart rate variability (+6), held
        /// back by resting heart rate (−3)."); nil when there are no drivers.
        let driversSentence: String?

        /// The whole number a card prints.
        var scoreText: String { "\(Int(score.rounded()))" }
    }

    /// `score` → tone by NOOP's bands (`RecoveryScorer.band`: red / yellow / green).
    static func readinessTone(_ score: Double) -> ReadinessTone {
        switch RecoveryScorer.band(score) {
        case "red": return .low
        case "yellow": return .watch
        default: return .good
        }
    }

    /// The Readiness score for `day`, or nil when the funnel row for that morning carries none (the first
    /// four HRV nights, an Apple-only day). `days` is the funnel table, oldest → newest. Drivers and the
    /// confidence tier are folded from every night BEFORE `day` (the rule every Baseline baseline follows:
    /// a night never sits inside its own baseline), honouring the persisted HRV recalibration epoch like
    /// the engine (`epoch` overrides it, for tests).
    static func readinessScore(for day: String, days: [DailyMetric], epoch: Double? = nil) -> ReadinessScore? {
        guard let row = days.last(where: { $0.day == day }), let score = row.recovery else { return nil }
        let history = days.filter { $0.day < day }
        let sleepPerf = AnalyticsEngine.Rest.composite(daily: row)
        let breakdown = ChargeBreakdownWiring.breakdown(days: history, row: row, sleepPerfPercent: sleepPerf,
                                                        hrvBaselineEpoch: epoch ?? Baselines.hrvBaselineEpoch())
        let hrvState = Baselines.foldHistory(history.map(\.avgHrv), dayKeys: history.map(\.day), cfg: Baselines.hrvCfg,
                                             baselineEpoch: epoch ?? Baselines.hrvBaselineEpoch())
        let drivers = breakdown?.drivers ?? []
        return ReadinessScore(day: day, score: min(100, max(0, score)), tone: readinessTone(score),
                              confidence: breakdown?.confidence ?? ScoreConfidence.charge(recovery: score, hrvBaseline: hrvState),
                              drivers: drivers, driversSentence: driversSentence(drivers))
    }

    /// The honest "N of 4 nights" while the score is still calibrating: the HRV baseline's valid-night
    /// count over `days` up to and including `day`, nil once a score exists or the seed gate is passed
    /// (`RecoveryScorer.calibrationNights`).
    static func readinessCalibrationNights(for day: String, days: [DailyMetric], epoch: Double? = nil) -> Int? {
        let scoped = days.filter { $0.day <= day }
        let hasScore = scoped.last(where: { $0.day == day })?.recovery != nil
        return RecoveryScorer.calibrationNights(nightlyHrv: scoped.map(\.avgHrv), dayKeys: scoped.map(\.day),
                                                hasRecovery: hasScore, baselineEpoch: epoch ?? Baselines.hrvBaselineEpoch())
    }

    /// Nights the Readiness score needs before it appears (`Baselines.minNightsSeed`).
    static var readinessSeedNights: Int { Baselines.minNightsSeed }

    /// "Lifted by heart rate variability (+6), held back by resting heart rate (−3)." from the two biggest
    /// non-zero movers; a single mover reads "Lifted by …" / "Held back by …" alone. Built from the
    /// driver's label and signed points only, never its verdict text, so NOOP's wording stays out of
    /// Baseline's vocabulary.
    static func driversSentence(_ drivers: [ChargeDriver]) -> String? {
        let movers = drivers.filter { $0.deltaPoints != 0 }
            .sorted { abs($0.deltaPoints) > abs($1.deltaPoints) }
            .prefix(2)
        guard !movers.isEmpty else { return nil }
        var parts: [String] = []
        for (i, d) in movers.enumerated() {
            let verb = d.deltaPoints > 0 ? "Lifted by" : "Held back by"
            let name = d.label.lowercased()
            let pts = (d.deltaPoints < 0 ? "\u{2212}" : "+") + "\(abs(d.deltaPoints))"
            parts.append((i == 0 ? verb : verb.lowercased()) + " \(name) (\(pts))")
        }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: - Windowed averages (steps, calories)

    /// Fewest recorded days before a "vs your average" is shown.
    static let averageMinDays = 3

    /// The mean of `readings` over the `window` CALENDAR days strictly BEFORE `day` (`day − window` …
    /// `day − 1`), missing days excluded rather than zero-filled, so a day is never measured against an
    /// average it is part of. `mean` is nil under `averageMinDays` observed days. Day keys are
    /// "yyyy-MM-dd" and the window is pure UTC key math (`Baselines.cutoffKey`).
    static func windowAverage(before day: String, window: Int,
                              readings: [(day: String, value: Double)]) -> (mean: Double?, observed: Int) {
        let start = Baselines.cutoffKey(todayKey: day, carryDays: window)
        var byDay: [String: Double] = [:]
        for r in readings where r.day >= start && r.day < day && r.value.isFinite && r.value >= 0 {
            byDay[r.day] = r.value
        }
        guard byDay.count >= averageMinDays else { return (nil, byDay.count) }
        return (byDay.values.reduce(0, +) / Double(byDay.count), byDay.count)
    }

    // MARK: - Steps

    /// One day's steps against the person's own 7- and 30-day averages.
    struct StepsReadout {
        let day: String
        /// The day's count; nil when nothing recorded it (no strap counter, no phone count).
        let steps: Int?
        /// Mean over the 7 calendar days before `day` (≥ 3 recorded), and the 30.
        let average7: Double?
        let average30: Double?
        let observed7: Int
        let observed30: Int
        /// The 7 calendar days ending on `day`, oldest → newest, nil where nothing was recorded: the
        /// sparkline's bars, one per day whether or not it has a value.
        let recent: [(day: String, value: Double?)]

        /// Signed difference against an average: nil when either side is missing.
        func delta(against average: Double?) -> Double? {
            guard let steps, let average else { return nil }
            return Double(steps) - average
        }
    }

    /// `readings` are `(day, steps)` pairs from any source resolution (`BaselineReadouts.stepReadings`
    /// in the app; the funnel's `steps` column in tests). Days are keys; values are counts.
    static func steps(for day: String, readings: [(day: String, value: Double)]) -> StepsReadout {
        var byDay: [String: Double] = [:]
        for r in readings where r.value.isFinite && r.value >= 0 { byDay[r.day] = r.value }
        let a7 = windowAverage(before: day, window: 7, readings: readings)
        let a30 = windowAverage(before: day, window: 30, readings: readings)
        let recent: [(day: String, value: Double?)] = (0..<7).reversed().map { back in
            let key = Baselines.cutoffKey(todayKey: day, carryDays: back)
            return (day: key, value: byDay[key])
        }
        return StepsReadout(day: day, steps: byDay[day].map { Int($0.rounded()) },
                            average7: a7.mean, average30: a30.mean, observed7: a7.observed, observed30: a30.observed,
                            recent: recent)
    }

    /// ONE spelling for a step count ("8,412"; "–" when nothing was recorded).
    static func stepsText(_ steps: Int?) -> String {
        guard let steps else { return "–" }
        return steps.formatted(.number.grouping(.automatic))
    }

    /// Inside this fraction of the average either way, a day is "on" its average.
    static let stepsSteadyFraction = 0.05

    /// "+1,240 vs your 7-day average" / "−860 vs your 30-day average" / "On your 7-day average"; nil when
    /// either side is missing (the caller prints the "average after N days" line instead).
    static func stepsDeltaText(steps: Int?, average: Double?, windowLabel: String) -> String? {
        guard let steps, let average else { return nil }
        let delta = Double(steps) - average
        if abs(delta) <= average * stepsSteadyFraction { return "On your \(windowLabel) average" }
        let sign = delta < 0 ? "\u{2212}" : "+"
        return sign + Int(abs(delta).rounded()).formatted(.number.grouping(.automatic)) + " vs your \(windowLabel) average"
    }

    // MARK: - Calories

    /// One day's whole-day calorie estimate (NOOP's HR-only `activeKcalEst`, resting + active) against
    /// the 30-day mean. A Low-accuracy figure (`MetricAccuracy` "calories"): shown rounded to the nearest
    /// 10 and only relative to the person's own average.
    struct CaloriesReadout {
        let day: String
        let kcal: Double?
        let average30: Double?
        let observed30: Int

        var delta: Double? {
            guard let kcal, let average30 else { return nil }
            return kcal - average30
        }
    }

    static func calories(for day: String, days: [DailyMetric]) -> CaloriesReadout {
        let readings = BaselineDays.series(key: "active_kcal", days: days)
        let a = windowAverage(before: day, window: 30, readings: readings)
        let today = days.last(where: { $0.day == day })?.activeKcalEst
        return CaloriesReadout(day: day, kcal: today.flatMap { $0 > 0 ? $0 : nil }, average30: a.mean, observed30: a.observed)
    }

    /// ONE spelling for a calorie figure, rounded to the nearest 10 ("2,140"); "–" when there is none.
    /// Never to the kcal: no consumer device is within 20% of calorimetry.
    static func caloriesText(_ kcal: Double?) -> String {
        guard let kcal else { return "–" }
        let tens = Int((kcal / 10).rounded()) * 10
        return tens.formatted(.number.grouping(.automatic))
    }

    /// "+180 vs your 30-day average" / "On your 30-day average" (inside ±5%); nil when either is missing.
    static func caloriesDeltaText(kcal: Double?, average: Double?) -> String? {
        guard let kcal, let average else { return nil }
        let delta = kcal - average
        if abs(delta) <= average * stepsSteadyFraction { return "On your 30\u{2011}day average" }
        let sign = delta < 0 ? "\u{2212}" : "+"
        let tens = Int((abs(delta) / 10).rounded()) * 10
        return sign + tens.formatted(.number.grouping(.automatic)) + " vs your 30\u{2011}day average"
    }

    // MARK: - Stress (daytime)

    /// One point of a day's Stress curve: a full-hour window scored on the shared 0–3 scale (NOOP's
    /// `DaytimeStress`), stepped every half hour for display.
    struct StressCurvePoint: Identifiable, Equatable {
        /// Start of the window (unix seconds).
        let id: Int
        let date: Date
        /// 0–3, or nil when the window had too little heart rate or was masked as movement.
        let level: Double?
        /// True when the window was left unscored because the strap saw walking (exertion, not stress).
        let moving: Bool
    }

    /// A scored day. nil from `stressDay(_:day:)` when no waking hour could be scored, so a card shows
    /// nothing rather than a flat line.
    struct StressDayReadout {
        let day: String
        /// Half-hour display points, earliest → latest, including unscored gaps.
        let points: [StressCurvePoint]
        /// Mean over the scored hours.
        let dayMean: Double
        let peak: (date: Date, level: Double)?
        /// Scored hours at or above the high band (2.0), in minutes.
        let highMinutes: Int
        /// Waking hours excluded because the person was moving.
        let movingHours: Int
        let scoredHours: Int
        /// True when the most recent three scored hours were all high.
        let sustainedHigh: Bool
    }

    /// The display scale every Stress drawing shares.
    static let stressDomain: ClosedRange<Double> = 0...3

    /// NOOP's bands on the 0–3 scale: < 1 "Low", < 2 "Medium", else "High".
    static func stressLevelText(_ level: Double) -> String {
        if level < 1 { return "Low" }
        if level < 2 { return "Medium" }
        return "High"
    }

    /// `DaytimeStress.Result` → the readout, or nil when nothing was scored (`.empty`, or a day the
    /// strap spent on the charger). Pure, so a test can hand it a built `Result`.
    static func stressDay(_ result: DaytimeStress.Result, day: String) -> StressDayReadout? {
        let scored = result.scored
        guard let mean = result.dayMean, !scored.isEmpty else { return nil }
        let points = result.timeline.map { h in
            StressCurvePoint(id: h.startTs, date: Date(timeIntervalSince1970: TimeInterval(h.startTs)),
                        level: h.level, moving: h.maskedForActivity)
        }
        let peak = result.peak.flatMap { p in
            p.level.map { (date: Date(timeIntervalSince1970: TimeInterval(p.startTs)), level: $0) }
        }
        return StressDayReadout(day: day, points: points, dayMean: mean, peak: peak,
                                highMinutes: result.highStressMinutes, movingHours: result.activityMaskedHours,
                                scoredHours: scored.count, sustainedHigh: result.sustainedHigh)
    }

    /// The one VoiceOver / caption sentence for a day's curve: "Stress averaged 1.4 of 3 (Medium), peak
    /// 2.3 at 3 PM; 2 hours left out while you were moving."
    static func stressSummary(_ r: StressDayReadout) -> String {
        var s = "Stress averaged " + String(format: "%.1f", r.dayMean) + " of 3 (\(stressLevelText(r.dayMean)))"
        if let p = r.peak {
            s += ", peak " + String(format: "%.1f", p.level) + " at " + p.date.formatted(date: .omitted, time: .shortened)
        }
        if r.movingHours > 0 {
            s += "; \(r.movingHours) hour\(r.movingHours == 1 ? "" : "s") left out while you were moving"
        }
        return s + "."
    }

    // MARK: - Sleep timing

    /// The person's target bed and wake clock times, minutes after local midnight, persisted under
    /// `baseline.sleepWindow.bedMinutes` / `baseline.sleepWindow.wakeMinutes` (defaults 23:00 / 07:00).
    struct SleepWindow: Equatable {
        let bedMinutes: Int
        let wakeMinutes: Int

        static let bedKey = "baseline.sleepWindow.bedMinutes"
        static let wakeKey = "baseline.sleepWindow.wakeMinutes"
        static let `default` = SleepWindow(bedMinutes: 23 * 60, wakeMinutes: 7 * 60)

        /// A night counts as inside the window when BOTH its bed and wake land within this many minutes
        /// of the targets.
        static let toleranceMin = 30

        /// The stored window; the default for a missing or out-of-range key.
        static func stored(_ defaults: UserDefaults = .standard) -> SleepWindow {
            func read(_ key: String, fallback: Int) -> Int {
                guard let v = defaults.object(forKey: key) as? Int, (0..<1440).contains(v) else { return fallback }
                return v
            }
            return SleepWindow(bedMinutes: read(bedKey, fallback: SleepWindow.default.bedMinutes),
                               wakeMinutes: read(wakeKey, fallback: SleepWindow.default.wakeMinutes))
        }

        func save(_ defaults: UserDefaults = .standard) {
            defaults.set(bedMinutes, forKey: Self.bedKey)
            defaults.set(wakeMinutes, forKey: Self.wakeKey)
        }

        /// Hours in bed the window allows ("8h 00m" for 23:00 → 07:00), wrapping past midnight.
        var spanMinutes: Int { (wakeMinutes - bedMinutes + 1440) % 1440 }
    }

    /// Bedtime and wake per night plus the averages and regularity over them.
    struct SleepTiming {
        struct Night: Identifiable, Equatable {
            let day: String
            let bed: Date
            let wake: Date
            var id: String { day }
        }

        let day: String
        /// Nights with a bed and a wake time on or before `day`, newest first, at most 30 (the
        /// `.dailyMetric` nights of an import without sessions carry none and are skipped).
        let nights: [Night]
        /// Circular mean of the clock time, minutes after midnight (0 ≤ m < 1440), over the newest 30
        /// nights; nil under `sleepAverageMinNights`.
        let averageBedMinutes: Double?
        let averageWakeMinutes: Double?
        /// 0–100 over the newest 14 nights; nil under `regularityMinPairs` consecutive-night pairs.
        let regularity: Int?
        let target: SleepWindow
        /// Of the newest 14 nights, how many landed inside the target window (± tolerance).
        let nightsInWindow: Int
        let nightsCounted: Int
    }

    /// Nights the regularity index is read over, and the fewest consecutive-night pairs it needs.
    static let regularityNights = 14
    static let regularityMinPairs = 5

    /// Minutes after local midnight (0 ≤ m < 1440) of a wall-clock instant.
    static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// The circular mean of clock times in minutes (so 23:30 and 00:30 average to 00:00, not 12:00),
    /// back in 0 ≤ m < 1440. nil for an empty list or times spread evenly round the clock.
    static func circularMeanMinutes(_ minutes: [Double]) -> Double? {
        guard !minutes.isEmpty else { return nil }
        var x = 0.0, y = 0.0
        for m in minutes {
            let a = m / 1440 * 2 * Double.pi
            x += cos(a); y += sin(a)
        }
        guard hypot(x, y) > 1e-9 else { return nil }
        var mean = atan2(y, x) / (2 * Double.pi) * 1440
        if mean < 0 { mean += 1440 }
        // A hair under 1440 (a tiny negative atan2) is midnight, not a minute before it.
        if mean >= 1440 - 1e-6 { mean = 0 }
        return mean
    }

    /// "11:12 PM" / "23:12" for minutes after midnight, in the device's clock style.
    static func clockText(minutes: Double, calendar: Calendar = .current) -> String {
        let m = Int(minutes.rounded()) % 1440
        var c = DateComponents()
        c.year = 2001; c.month = 1; c.day = 1; c.hour = m / 60; c.minute = m % 60
        guard let date = calendar.date(from: c) else { return "–" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// A night as a half-open interval in minutes since NOON of the day before it ends, clamped to one
    /// noon-to-noon day (0 … 1440): the frame every timing drawing and the regularity index share.
    static func noonInterval(bed: Date, wake: Date, calendar: Calendar = .current) -> ClosedRange<Double> {
        let start = (minutesOfDay(bed, calendar: calendar) + 720).truncatingRemainder(dividingBy: 1440)
        let end = min(1440, start + max(0, wake.timeIntervalSince(bed) / 60))
        return start...end
    }

    /// The sleep regularity index, SRI-like (Phillips et al. 2017): for every pair of CONSECUTIVE nights,
    /// the share of the noon-to-noon day on which the two nights agree minute by minute about asleep vs
    /// awake (1 − |A △ B| / 1440), rescaled so chance is 0 and identical nights are 100 (200·mean − 100,
    /// clamped 0…100, rounded). Only sleep/wake timing goes in, the part a wearable gets right; an
    /// 8-hour night that drifts by an hour every day scores about 83. nil under `regularityMinPairs`
    /// pairs. `nights` is any order; pairs are consecutive day keys.
    static func sleepRegularity(nights: [SleepTiming.Night], calendar: Calendar = .current) -> Int? {
        let byDay = Dictionary(nights.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        var agreements: [Double] = []
        for (day, b) in byDay {
            let previous = Baselines.cutoffKey(todayKey: day, carryDays: 1)
            guard previous != day, let a = byDay[previous] else { continue }
            let ia = noonInterval(bed: a.bed, wake: a.wake, calendar: calendar)
            let ib = noonInterval(bed: b.bed, wake: b.wake, calendar: calendar)
            let lenA = ia.upperBound - ia.lowerBound, lenB = ib.upperBound - ib.lowerBound
            let overlap = max(0, min(ia.upperBound, ib.upperBound) - max(ia.lowerBound, ib.lowerBound))
            let symmetricDifference = lenA + lenB - 2 * overlap
            agreements.append(1 - symmetricDifference / 1440)
        }
        guard agreements.count >= regularityMinPairs else { return nil }
        let mean = agreements.reduce(0, +) / Double(agreements.count)
        return Int(min(100, max(0, 200 * mean - 100)).rounded())
    }

    /// Minutes between two clock times, the short way round (23:50 vs 00:10 = 20, not 1420).
    static func clockDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1440)
        return min(d, 1440 - d)
    }

    /// The timing readout for `day`. `nights` is `SleepNightBuilder.nights(…)` (newest first) from the
    /// funnel; only `.session` nights carry times. `window` defaults to the stored target.
    static func sleepTiming(for day: String, nights: [SleepNight], window: SleepWindow = .stored(),
                            calendar: Calendar = .current) -> SleepTiming {
        let timed: [SleepTiming.Night] = nights
            .filter { $0.dayKey <= day }
            .sorted { $0.dayKey > $1.dayKey }
            .compactMap { n in
                guard let bed = n.onset, let wake = n.wake, wake > bed else { return nil }
                return SleepTiming.Night(day: n.dayKey, bed: bed, wake: wake)
            }
        let last30 = Array(timed.prefix(30))
        let last14 = Array(timed.prefix(regularityNights))
        let enough = last30.count >= sleepAverageMinNights
        let bedAvg = enough ? circularMeanMinutes(last30.map { minutesOfDay($0.bed, calendar: calendar) }) : nil
        let wakeAvg = enough ? circularMeanMinutes(last30.map { minutesOfDay($0.wake, calendar: calendar) }) : nil
        let inWindow = last14.filter { n in
            clockDistance(minutesOfDay(n.bed, calendar: calendar), Double(window.bedMinutes)) <= Double(SleepWindow.toleranceMin)
                && clockDistance(minutesOfDay(n.wake, calendar: calendar), Double(window.wakeMinutes)) <= Double(SleepWindow.toleranceMin)
        }.count
        return SleepTiming(day: day, nights: last30, averageBedMinutes: bedAvg, averageWakeMinutes: wakeAvg,
                           regularity: sleepRegularity(nights: last14, calendar: calendar), target: window,
                           nightsInWindow: inWindow, nightsCounted: last14.count)
    }

    // MARK: - Fitness (VO2 max, fitness age)

    /// NOOP's weekly fitness read (`FitnessAgeEngine`, Nes 2011 HUNT model) for the seven days ending on
    /// a day: a fitness age with its ±5-year band and an estimated VO2 max (Nes with a waist measurement,
    /// else the rougher Uth HR-ratio fallback). Low/Medium accuracy (`MetricAccuracy` "vo2"): show the
    /// band and the word "estimate".
    struct FitnessReadout {
        let weekEnding: String
        let result: FitnessAgeResult
        /// Estimated VO2 max (ml/kg/min): the Nes value when a waist was supplied, else Uth
        /// (15.3 × age-predicted HR max ÷ resting HR). nil only when resting HR is 0.
        let vo2max: Double?
        /// True when `vo2max` came from the waist-free fallback.
        let vo2IsFallback: Bool
        /// Median resting HR over the week and how many nights carried one.
        let restingHr: Double
        let rhrNights: Int
        /// Days with an Effort of 30 or more.
        let activeDays: Int
        let inputs: FitnessAgeReadiness

        /// Nes carries a ±5-year band; VO2 max from HR alone an SEE of about 5 ml/kg/min.
        var vo2BandText: String? { vo2max.map { String(format: "%.0f–%.0f", max(0, $0 - 5), $0 + 5) } }
    }

    /// The checklist alone (what is missing before a number can exist), always available.
    static func fitnessInputs(for day: String, days: [DailyMetric], age: Int?, sex: String?,
                              waistCm: Double?, hasHeightWeight: Bool) -> FitnessAgeReadiness {
        let week = fitnessWeek(for: day, days: days)
        return FitnessAgeEngine.assessReadiness(
            hasAge: (age ?? 0) > 0, hasSex: !(sex ?? "").isEmpty,
            rhrDays: week.compactMap(\.restingHr).count, activityDays: week.compactMap(\.strain).count,
            hasHeightWeight: hasHeightWeight, hasWaist: (waistCm ?? 0) > 0)
    }

    /// The readout for the week ending on `day`, nil until age, sex and four nights of resting HR exist
    /// (`FitnessAgeEngine.minCoverageDays`). Mirrors NOOP's `IntelligenceEngine.fitnessAgeRows` gate and
    /// inputs: RHR = the week's median, PA index from the days with Effort ≥ 30.
    static func fitness(for day: String, days: [DailyMetric], age: Int?, sex: String?,
                        waistCm: Double? = nil, hasHeightWeight: Bool = false) -> FitnessReadout? {
        let inputs = fitnessInputs(for: day, days: days, age: age, sex: sex, waistCm: waistCm, hasHeightWeight: hasHeightWeight)
        guard inputs.canCompute, let age, let sex else { return nil }
        let week = fitnessWeek(for: day, days: days)
        let rhrs = week.compactMap(\.restingHr).map(Double.init)
        let active = week.compactMap(\.strain).filter { $0 >= 30 }
        let meanActive = active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)
        let rhr = median(rhrs)
        let pa = FitnessAgeEngine.physicalActivityIndexFromStrain(activeDaysPerWeek: active.count, meanActiveStrain: meanActive)
        let waist = (waistCm ?? 0) > 0 ? waistCm : nil
        guard let result = FitnessAgeEngine.compute(age: Double(age), sex: sex, restingHR: rhr, paIndex: pa, waistCm: waist,
                                                    lowerConfidence: inputs.confidence != .ready) else { return nil }
        let fallback = result.vo2max == nil
        let vo2 = result.vo2max
            ?? Calories.vo2maxFor(hrmax: StrainScorer.estimateHRmax([], age: Double(age)).0, restingHR: rhr)
        return FitnessReadout(weekEnding: day, result: result, vo2max: vo2, vo2IsFallback: fallback && vo2 != nil,
                              restingHr: rhr, rhrNights: rhrs.count, activeDays: active.count, inputs: inputs)
    }

    /// The seven calendar days ending on `day`, oldest → newest.
    private static func fitnessWeek(for day: String, days: [DailyMetric]) -> [DailyMetric] {
        let start = Baselines.cutoffKey(todayKey: day, carryDays: 6)
        return days.filter { $0.day >= start && $0.day <= day }
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    // MARK: - Day keys

    private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local midnight of a "yyyy-MM-dd" key; nil for a key that does not parse.
    static func localMidnight(of dayKey: String) -> Date? { dayKeyParser.date(from: dayKey) }
}

// MARK: - Repository accessors (@MainActor; the only reads outside the funnel's tables)

extension BaselineReadouts {

    /// `(day, steps)` readings over `from`…`to` (inclusive day keys) with the funnel's precedence: under
    /// strap-first / merged NOOP's own resolver (`repo.resolvedSteps`: the strap's counted steps, then
    /// the phone's, then the strap's calibrated estimate, first non-nil per day, so live-HealthKit steps
    /// and the 4.0 estimate are seen); under imports-only the phone's series alone. Days the resolver has
    /// no point for fall back to the funnel table's `steps` column (previews and tests that assign
    /// `repo.days` directly have no store behind the resolver).
    @MainActor
    static func stepReadings(_ repo: Repository, from: String, to: String,
                             mode: BaselineDataSource = .current()) async -> [(day: String, value: Double)] {
        let resolved: [(day: String, value: Double)]
        switch mode {
        case .importOnly:
            resolved = await repo.resolvedSeries(key: "steps", source: Repository.appleHealthSource, from: from, to: to).values
        case .strapFirst, .merged:
            resolved = await repo.resolvedSteps(from: from, to: to).values
        }
        var byDay = Dictionary(resolved.map { ($0.day, $0.value) }, uniquingKeysWith: { first, _ in first })
        for p in BaselineDays.series(key: "steps", days: days(repo, mode: mode)) where byDay[p.day] == nil
            && p.day >= from && p.day <= to {
            byDay[p.day] = p.value
        }
        return byDay.map { (day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }

    /// The steps readout for `day` (31 calendar days of readings ending on it).
    @MainActor
    static func steps(_ repo: Repository, for day: String, mode: BaselineDataSource = .current()) async -> StepsReadout {
        let from = Baselines.cutoffKey(todayKey: day, carryDays: 30)
        let readings = await stepReadings(repo, from: from, to: day, mode: mode)
        return steps(for: day, readings: readings)
    }

    /// The Stress curve for `day`, or nil when the strap banked no daytime heart rate for it (it was off,
    /// on the charger, or a WHOOP 5 / MG day whose PPG bursts have not been derived yet). Today goes
    /// through NOOP's fingerprint-gated memo (`StressDayCurve.today`); an earlier day reads its streams
    /// once (`repo.hrSamples` / `rrIntervals` / `gravitySamplesUnion`, strap-only, so the data-source
    /// precedence does not apply) and scores them day-relative (`DaytimeStress.analyze`, the mode NOOP
    /// defaults to: the day's own calm hours are the reference, no history needed).
    @MainActor
    static func stressDay(_ repo: Repository, for day: String, now: Date = Date(),
                          calendar: Calendar = .current) async -> StressDayReadout? {
        guard let start = localMidnight(of: day) else { return nil }
        if day == Repository.localDayKey(now) {
            guard let scored = await StressDayCurve.today(repo: repo, now: now, calendar: calendar) else { return nil }
            return stressDay(scored.result, day: day)
        }
        let from = Int(start.timeIntervalSince1970)
        let to = Int((calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)).timeIntervalSince1970) - 1
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { return nil }
        let rr = await repo.rrIntervals(from: from, to: to, limit: 200_000)
        let gravity = await repo.gravitySamplesUnion(from: from, to: to, limit: 200_000)
        let tz = TimeZone.current.secondsFromGMT(for: start)
        let result = DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity, tzOffsetSeconds: tz,
                                           mode: .dayRelative, includeTimeline: true)
        return stressDay(result, day: day)
    }

    /// The fitness readout from the profile the app keeps (`ProfileStore`: date of birth, sex, waist,
    /// height and weight) over the funnel's days.
    @MainActor
    static func fitness(_ repo: Repository, profile: ProfileStore, for day: String,
                        mode: BaselineDataSource = .current()) -> FitnessReadout? {
        fitness(for: day, days: days(repo, mode: mode), age: profile.age, sex: profile.sex,
                waistCm: profile.waistCm, hasHeightWeight: profile.heightCm > 0 && profile.weightKg > 0)
    }
}
#endif
