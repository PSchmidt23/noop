#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// The activity readouts' own types and settings: where a day's steps came from and the daily step goal
// (Steps card), the Mifflin–St Jeor resting figure and the profile inputs behind the Calories card, and
// the hour states the Stress card counts. Pure value math, plus the one `@MainActor` calories accessor
// at the bottom. Research, rules and the tests every number here is pinned to:
// `Baseline/Research/ACTIVITY_METRICS.md` ("Implementable spec").

// MARK: - Steps

/// Where a day's step count came from. One source per day, never summed: the strap's counted steps,
/// then the iPhone's (Apple Health), then the strap's calibrated estimate (NOOP's `steps_est`, a WHOOP
/// 4.0 without a counter), then a value only an import or the funnel table carried.
enum StepSource: String, Equatable, Hashable, Sendable, Codable {
    case strap, phone, estimate, imported

    /// The source of a resolver point (`Repository.resolvedSteps`, `resolvedSeries`): the estimate key
    /// first, then the phone's sources (`BaselineReadouts.importedStepSources`), then the strap's
    /// computed sibling (`<id>-noop`, where NOOP's engine files the counter's daily steps). A point under
    /// any other id is an import (a WHOOP export under "my-whoop", an activity file).
    static func of(_ point: ResolvedMetricPoint) -> StepSource {
        of(source: point.source, key: point.sourceKey)
    }

    static func of(source: String, key: String) -> StepSource {
        if key == "steps_est" { return .estimate }
        if BaselineReadouts.importedStepSources.contains(source) { return .phone }
        if source.hasSuffix("-noop") { return .strap }
        return .imported
    }

    /// A count a person's own device made today (the strap's counter or the iPhone's): the only kinds
    /// Friends may upload.
    var isCounted: Bool { self == .strap || self == .phone }
}

/// What a day's Steps card can say.
enum StepsDayState: Equatable {
    /// A count above zero.
    case counted
    /// A source recorded the day and it reads zero.
    case zero
    /// Nothing recorded the day ("No steps yet" today, "No steps recorded" on a past day).
    case noSource
}

/// The daily step goal, `baseline.stepGoal` in `UserDefaults.standard`: default 8,000 (the top of Ding
/// 2025's inflection range, the start of Paluch 2022's under-60 plateau and the contrast Saint-Maurice
/// 2020 tested), 3,000–30,000 in steps of 500. Fixed: it never adjusts itself. The floor is Friends'
/// (`FriendsScoring.stepGoalFloor`, the server's `step_goal` check), so a day Home calls "Goal met" is
/// never a missed day or under 100 % in Friends.
enum StepGoal {
    static let key = "baseline.stepGoal"
    static let defaultGoal = 8_000
    static let range = 3_000...30_000
    static let step = 500

    /// `value` snapped to the stepper's grid and clamped to `range`.
    static func clamp(_ value: Int) -> Int {
        let snapped = Int((Double(value) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    /// The stored goal, clamped; the default when unset.
    static func goal(_ defaults: UserDefaults = .standard) -> Int {
        guard let v = defaults.object(forKey: key) as? Int else { return defaultGoal }
        return clamp(v)
    }

    static func save(_ goal: Int, _ defaults: UserDefaults = .standard) {
        defaults.set(clamp(goal), forKey: key)
    }
}

extension BaselineReadouts.StepsReadout {
    /// The goal track's fill, 0…1.
    func goalFraction(goal: Int) -> Double {
        guard let steps, goal > 0 else { return 0 }
        return min(1, max(0, Double(steps) / Double(goal)))
    }

    /// True once the day's count reached `goal`.
    func goalMet(goal: Int) -> Bool { (steps ?? 0) >= goal && goal > 0 }

    /// Days among the week's bars (`recent`) that reached `goal`; days without a count are not counted.
    func goalDays(goal: Int) -> Int { recent.compactMap { $0.value }.filter { $0 >= Double(goal) }.count }
}

// MARK: - Body inputs (Calories)

/// `baseline.bodySet`: true once Settings › Profile has had its height or weight entered or confirmed.
/// NOOP seeds 178 cm / 75 kg and persists them, so the store alone cannot tell a default from an entry
/// (the same reason `ProfileSet` exists for age and sex).
enum BodySet {
    static let key = "baseline.bodySet"

    static func current(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
}

/// Where a day's active energy came from: the strap's heart rate, else Apple Health's active energy.
enum CalorieActiveSource: String, Equatable, Sendable {
    case strap, appleHealth
}

/// Everything the Calories card's two estimates run on, resolved once (`BaselineReadouts.calorieInputs`).
struct CalorieInputs: Equatable, Sendable {
    /// Weight (kg): the latest Apple Health weight within 90 days, else the profile's.
    let weightKg: Double
    let heightCm: Double
    /// Age (years) and sex, nil until the person entered them (`ProfileSet`): no resting figure then.
    let age: Double?
    let sex: String?
    /// The max heart rate the active estimate gates on (the profile's `effortHRmax`, Tanaka from the
    /// stored age when no override is set).
    let hrMax: Double?
    /// `baseline.bodySet`.
    let bodyConfirmed: Bool
    let weightFromAppleHealth: Bool

    /// Height and weight are still NOOP's seeded defaults (nothing entered or confirmed in Profile).
    var bodyAssumed: Bool { !bodyConfirmed }

    /// Mifflin–St Jeor for the whole day, nil without an age and sex.
    var bmr: Double? {
        guard let age, let sex else { return nil }
        return BaselineReadouts.bmrMifflin(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age)
    }

    /// The profile NOOP's active-energy model runs on: the entered age and sex, else the neutral 30-year
    /// nonbinary midpoint NOOP's own estimator falls back to (never the seeded 30-year-old male).
    var energyProfile: UserProfile {
        UserProfile(weightKg: weightKg, heightCm: heightCm, age: age ?? 30, sex: sex ?? "nonbinary")
    }

    /// What an active figure depends on (weight, height, age, sex, max heart rate), for
    /// `IntradayDayStore`'s staleness check. Rounded so a float round trip never re-estimates.
    var energySignature: String {
        let w = Int((weightKg * 10).rounded()), h = Int((heightCm * 10).rounded())
        let a = age.map { String(Int($0.rounded())) } ?? "-"
        let m = hrMax.map { String(Int($0.rounded())) } ?? "-"
        return "e1|w=\(w)|h=\(h)|a=\(a)|s=\(sex ?? "-")|m=\(m)"
    }
}

extension BaselineReadouts {

    // MARK: Resting energy (Mifflin–St Jeor)

    /// Resting energy bounds (kcal/day): a typo in Profile cannot print a 300 or a 9,000.
    static let bmrRange = 800.0...4_000.0

    /// Mifflin–St Jeor (1990), kcal/day, W kg, H cm, A years: `10W + 6.25H − 5A + 5` for "male",
    /// `… − 161` for "female", and the midpoint `… − 78` for anything else (the convention NOOP's
    /// `Calories.nonbinary` follows). Clamped to `bmrRange`. The Academy of Nutrition and Dietetics
    /// review (Frankenfield 2005) found it the most reliable of the common equations.
    static func bmrMifflin(sex: String, weightKg: Double, heightCm: Double, age: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * age
        let offset: Double
        switch sex.lowercased() {
        case "male": offset = 5
        case "female": offset = -161
        default: offset = -78
        }
        return min(bmrRange.upperBound, max(bmrRange.lowerBound, base + offset))
    }

    /// The share of a local day that has passed at `now` (today's resting figure is "so far"): seconds
    /// since local midnight over 86,400, 0…1.
    static func dayFraction(_ now: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: now)
        return min(1, max(0, now.timeIntervalSince(start) / 86_400))
    }

    /// The inputs from the numbers (pure; the `ProfileStore` resolver below reads them). Age and sex
    /// pass only when `entered` (`ProfileSet`); weight prefers Apple Health's when given.
    static func calorieInputs(weightKg: Double, heightCm: Double, age: Int?, sex: String?, hrMax: Double?,
                              entered: Bool, bodySet: Bool, appleWeightKg: Double?) -> CalorieInputs {
        let apple = appleWeightKg.flatMap { $0 > 20 && $0 < 400 ? $0 : nil }
        let weight = apple ?? (weightKg > 0 ? weightKg : 75)
        let height = heightCm > 0 ? heightCm : 178
        let enteredAge = entered ? age.flatMap { $0 > 0 ? Double($0) : nil } : nil
        let enteredSex = entered ? sex.flatMap { $0.isEmpty ? nil : $0 } : nil
        return CalorieInputs(weightKg: weight, heightCm: height, age: enteredAge, sex: enteredSex,
                             hrMax: hrMax, bodyConfirmed: bodySet, weightFromAppleHealth: apple != nil)
    }

    // MARK: Active energy and the day

    /// Fewest observed days before the active part is compared with its 30-day average.
    static let caloriesActiveMinDays = 7

    /// The day's active energy and its source: the strap's estimate first, Apple Health's when the strap
    /// banked no heart rate that day; Apple's alone under imports-only. Never the two added together.
    /// NOOP's day estimator credits active energy only above 50 % of heart-rate reserve (exercise-level
    /// heart rate), so a day without a workout scores exactly 0 from the strap; when the phone counted
    /// active energy that day (walking, stairs) its figure is used instead of that 0. Still one source.
    static func activeEnergy(for day: String, strap: [String: Double], apple: [String: Double],
                             mode: BaselineDataSource) -> (kcal: Double, source: CalorieActiveSource)? {
        let phone = apple[day].flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if mode != .importOnly, let s = strap[day], s.isFinite, s >= 0 {
            if s == 0, let phone, phone > 0 { return (phone, .appleHealth) }
            return (s, .strap)
        }
        if let phone { return (phone, .appleHealth) }
        return nil
    }

    /// The Calories readout for `day` (pure). `inputs` nil (no profile) leaves the resting part out;
    /// `strapActive` / `appleActive` are day → active kcal (the strap's from `IntradayDayStore`, Apple
    /// Health's `active_kcal`); `dayFraction` < 1 marks today and prorates the resting part.
    static func caloriesDay(for day: String, inputs: CalorieInputs?, strapActive: [String: Double],
                            appleActive: [String: Double], mode: BaselineDataSource,
                            dayFraction: Double = 1) -> CaloriesReadout {
        let active = activeEnergy(for: day, strap: strapActive, apple: appleActive, mode: mode)
        let fraction = min(1, max(0, dayFraction))
        let resting = inputs?.bmr.map { $0 * fraction }
        // The 30 calendar days before `day`, each by the same precedence, missing days excluded.
        var values: [Double] = []
        for back in 1...30 {
            let key = Baselines.cutoffKey(todayKey: day, carryDays: back)
            guard key != day else { continue }
            if let a = activeEnergy(for: key, strap: strapActive, apple: appleActive, mode: mode) { values.append(a.kcal) }
        }
        let average = values.count >= caloriesActiveMinDays ? values.reduce(0, +) / Double(values.count) : nil
        return CaloriesReadout(day: day, kcal: nil, average30: nil, observed30: 0,
                               restingKcal: resting, activeKcal: active?.kcal, activeSource: active?.source,
                               activeAverage30: average, activeObserved30: values.count,
                               bodyAssumed: inputs?.bodyAssumed ?? false,
                               heightCm: inputs?.heightCm, weightKg: inputs?.weightKg,
                               weightFromAppleHealth: inputs?.weightFromAppleHealth ?? false,
                               isPartialDay: fraction < 1)
    }

    /// Each day's Calories figure from `from` to `to` (oldest → newest) through `caloriesDay`, the ONE
    /// builder Home's card, Trends' card and the Calories detail read: the total (resting + active), or
    /// the active part alone while no age and sex exist. A day with no active estimate (no strap heart
    /// rate, no Apple Health active energy) is absent: a resting-only figure is the formula, not a
    /// recorded day. `todayKey`'s resting part is prorated by `todayFraction`, as on Home.
    static func calorieReadings(from: String, to: String, inputs: CalorieInputs?, strapActive: [String: Double],
                                appleActive: [String: Double], mode: BaselineDataSource,
                                todayKey: String? = nil, todayFraction: Double = 1) -> [(day: String, value: Double)] {
        dayKeys(from: from, to: to).compactMap { key in
            let r = caloriesDay(for: key, inputs: inputs, strapActive: strapActive, appleActive: appleActive,
                                mode: mode, dayFraction: key == todayKey ? todayFraction : 1)
            guard let value = r.totalKcal ?? r.activeKcal else { return nil }
            return (day: key, value: value)
        }
    }

    // MARK: Repository accessors

    /// The latest Apple Health weight (kg) within 90 days of `now`, nil when the phone shared none.
    @MainActor
    static func appleWeightKg(_ repo: Repository, now: Date = Date()) async -> Double? {
        let today = Repository.localDayKey(now)
        let from = Baselines.cutoffKey(todayKey: today, carryDays: 90)
        let points = await repo.resolvedSeries(key: "weight", source: Repository.appleHealthSource, from: from, to: today).points
        return points.filter { $0.source == Repository.appleHealthSource && $0.value > 0 }.last?.value
    }

    /// The one resolver for the Calories card's inputs (and the day store's active-energy pass): the
    /// profile's height and weight (weight from Apple Health when it has one in 90 days), age and sex only
    /// when entered (`ProfileSet`), the effort max heart rate.
    @MainActor
    static func calorieInputs(_ repo: Repository, profile: ProfileStore, entered: Bool = ProfileSet.current(),
                              bodySet: Bool = BodySet.current(), now: Date = Date()) async -> CalorieInputs {
        let apple = await appleWeightKg(repo, now: now)
        return calorieInputs(weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age, sex: profile.sex,
                             hrMax: profile.effortHRmax, entered: entered, bodySet: bodySet, appleWeightKg: apple)
    }

    /// What every Calories figure is built from over `from`…`to`, read once: the profile's inputs (nil
    /// without a profile: no resting part), the strap's active energy per day from `IntradayDayStore` (the
    /// pass that scores Intensity minutes, estimated under those inputs; none under imports-only) and
    /// Apple Health's `active_kcal` as the fallback (its own points only: NOOP's Apple-preferred resolver
    /// would append the strap's `activeKcalEst`, which is a resting + active total).
    @MainActor
    static func calorieSources(_ repo: Repository, profile: ProfileStore?, from: String, to: String,
                               mode: BaselineDataSource, entered: Bool, bodySet: Bool,
                               calendar: Calendar = .current, now: Date = Date())
        async -> (inputs: CalorieInputs?, strap: [String: Double], apple: [String: Double]) {
        var inputs: CalorieInputs? = nil
        if let profile {
            inputs = await calorieInputs(repo, profile: profile, entered: entered, bodySet: bodySet, now: now)
        }
        var strap: [String: Double] = [:]
        if mode != .importOnly {
            let records = await IntradayDayStore.shared.records(
                repo, effortHRmax: profile?.effortHRmax, zoneSet: profile?.hrZoneSet,
                hrMaxOverride: profile?.hrMaxOverride ?? 0, days: dayKeys(from: from, to: to), mode: mode,
                entered: entered, computeStress: false, energy: inputs, calendar: calendar, now: now)
            for (k, r) in records { if let a = r.activeKcal { strap[k] = a } }
        }
        let applePoints = await repo.resolvedSeries(key: "active_kcal", source: Repository.appleHealthSource,
                                                    from: from, to: to).points
        var apple: [String: Double] = [:]
        for p in applePoints where p.source == Repository.appleHealthSource { apple[p.day] = p.value }
        return (inputs, strap, apple)
    }

    /// The Calories readout for `day` through the repository (`calorieSources` over the day and the 30
    /// before it, for the active average, then `caloriesDay`).
    @MainActor
    static func calories(_ repo: Repository, profile: ProfileStore?, for day: String,
                         mode: BaselineDataSource = .current(), entered: Bool = ProfileSet.current(),
                         bodySet: Bool = BodySet.current(), calendar: Calendar = .current,
                         now: Date = Date()) async -> CaloriesReadout {
        let from = Baselines.cutoffKey(todayKey: day, carryDays: 30)
        let s = await calorieSources(repo, profile: profile, from: from, to: day, mode: mode, entered: entered,
                                     bodySet: bodySet, calendar: calendar, now: now)
        let fraction = day == Repository.localDayKey(now) ? dayFraction(now, calendar: calendar) : 1
        return caloriesDay(for: day, inputs: s.inputs, strapActive: s.strap, appleActive: s.apple, mode: mode,
                           dayFraction: fraction)
    }

    /// The Calories detail's readings over `from`…`to` through the repository: `calorieSources`, then
    /// `calorieReadings`, so the detail's hero and range chart print the figure Home's card and Trends'
    /// card print for the same day.
    @MainActor
    static func calorieReadings(_ repo: Repository, profile: ProfileStore?, from: String, to: String,
                                mode: BaselineDataSource = .current(), entered: Bool = ProfileSet.current(),
                                bodySet: Bool = BodySet.current(), calendar: Calendar = .current,
                                now: Date = Date()) async -> [(day: String, value: Double)] {
        let s = await calorieSources(repo, profile: profile, from: from, to: to, mode: mode, entered: entered,
                                     bodySet: bodySet, calendar: calendar, now: now)
        return calorieReadings(from: from, to: to, inputs: s.inputs, strapActive: s.strap, appleActive: s.apple,
                               mode: mode, todayKey: Repository.localDayKey(now),
                               todayFraction: dayFraction(now, calendar: calendar))
    }
}

// MARK: - Stress hour states

/// The state of one scored waking hour, on NOOP's 0–3 level (never printed). Under the personal lens the
/// level is `3 / (1 + e^(−(meanHR − floor) / 21.6))` (`DaytimeStress.marginToSigma(15, atBand: 2)`), so:
/// elevated ≥ 2.0 is mean heart rate ≥ floor + 15 bpm while still (NOOP's HIGH band); calm 1.6…2.0 is
/// floor + 3 to + 15 bpm; restored < 1.6 is at the floor, within its 3 bpm spread.
enum StressState: Equatable, Sendable {
    case restored, calm, elevated, moving, noReading

    /// NOOP's HIGH band floor (`DaytimeStress.highBandFloor`): elevated from here.
    static let elevatedFloor = DaytimeStress.highBandFloor
    /// Under this level an hour is restored (≈ floor + 3 bpm under the personal lens).
    static let restoredCeiling = 1.6
    /// Fewest scored hours before a day is totalled.
    static let minTotalledHours = 3

    /// The state of one non-overlapping hour of `DaytimeStress.Result.hours`.
    static func of(_ p: DaytimeStress.HourPoint) -> StressState {
        of(level: p.level, moving: p.maskedForActivity)
    }

    static func of(level: Double?, moving: Bool) -> StressState {
        guard let level else { return moving ? .moving : .noReading }
        if level >= elevatedFloor { return .elevated }
        if level >= restoredCeiling { return .calm }
        return .restored
    }

    /// The word the detail and VoiceOver use.
    var label: String {
        switch self {
        case .restored: return "Restored"
        case .calm: return "Calm"
        case .elevated: return "Elevated"
        case .moving: return "Moving"
        case .noReading: return "No reading"
        }
    }

    /// Hours per state over `hours` (the non-overlapping `Result.hours`, never the half-step timeline,
    /// which would count a minute twice).
    static func counts(_ hours: [DaytimeStress.HourPoint]) -> (restored: Int, calm: Int, elevated: Int, moving: Int) {
        var r = 0, c = 0, e = 0, m = 0
        for h in hours {
            switch of(h) {
            case .restored: r += 1
            case .calm: c += 1
            case .elevated: e += 1
            case .moving: m += 1
            case .noReading: break
            }
        }
        return (r, c, e, m)
    }
}
#endif
