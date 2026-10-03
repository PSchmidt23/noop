#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// The behaviour a person may share with Friends, per local day, built from the SAME readouts Home shows
// (`Research/FRIENDS_SPEC.md` §3.4, the five behaviour metrics): the day's step count with its source,
// its credited Intensity minutes, whether it was an active day, and the night ending that morning against
// the person's own sleep goal and bedtime. Raw values, uncapped: the upload builder caps and flags them.
// Physiology (HRV, resting HR, Readiness), Calories and Stress are NOT here: physiology is shared only
// as a weekly change against the person's own baseline (the builder's trend rows), and Calories and
// Stress are never shared.

/// One local day's shareable behaviour. Every field is nil when the day has nothing to say for it.
struct FriendsDailyAggregate: Equatable, Sendable {
    let day: String
    /// The day's step count, only when the strap's counter or the iPhone counted it (`StepSource.isCounted`;
    /// an estimate or an import is never shared).
    let steps: Int?
    let stepsSource: StepSource?
    /// Credited Intensity minutes (moderate + 2 × vigorous), only on a day that is a reading
    /// (`IntradayDayRecord.recordedIntensity`).
    let intensity: Int?
    /// 1 when the day was active (credited ≥ 20 or a workout ≥ 20 min), 0 when not; nil when the day has
    /// neither an Intensity reading nor a workout.
    let active: Int?
    /// 1 when the night ending this morning reached the sleep goal (asleep minutes), else 0; nil without
    /// a night.
    let sleepGoal: Int?
    /// 1 when that night's bedtime was within `BaselineReadouts.friendsBedtimeToleranceMin` of the
    /// target bedtime, else 0; nil without a timed night.
    let bedtime: Int?
}

extension BaselineReadouts {

    /// The daily sleep goal Friends counts nights against, `baseline.sleepGoalMinutes` (asleep minutes):
    /// default 450 (7h 30m), 300–600 in steps of 15. The stepper is "Sleep goal" in Settings › Profile's
    /// Sleep window card (`SettingsSleepWindowCard`), and the value is printed wherever a night is judged
    /// against it (the consent row, the share line, the competition rule), never an unseen threshold.
    enum SleepGoal {
        static let key = "baseline.sleepGoalMinutes"
        static let defaultMinutes = 450
        static let range = 300...600
        static let step = 15

        static func minutes(_ defaults: UserDefaults = .standard) -> Int {
            guard let v = defaults.object(forKey: key) as? Int else { return defaultMinutes }
            return clamp(v)
        }

        /// `value` snapped to the stepper's grid and clamped to `range`.
        static func clamp(_ value: Int) -> Int {
            let snapped = Int((Double(value) / Double(step)).rounded()) * step
            return min(range.upperBound, max(range.lowerBound, snapped))
        }

        /// "7h 30m", "8h".
        static func text(_ minutes: Int) -> String {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
    }

    /// An active day: this many credited Intensity minutes, or a workout of this many minutes.
    static let friendsActiveMinutes = 20
    /// An on-time bedtime: within this many minutes of the target, either way.
    static let friendsBedtimeToleranceMin = 30.0

    /// One day's aggregate (pure). `steps` is the day's count and source as the Steps card resolved it
    /// (under the Data-source picker, as Home); `intensityRecord` the day's `IntradayDayStore` record; `workouts` the rows that
    /// started that local day; `night` the night ending that morning (asleep minutes and bedtime).
    static func friendsDailyAggregate(for day: String, steps: (value: Int, source: StepSource)?,
                                      intensityRecord: IntradayDayRecord?, workouts: [WorkoutRow],
                                      night: (asleepMinutes: Double, bed: Date?)?, sleepGoalMinutes: Int,
                                      targetBedMinutes: Int, calendar: Calendar = .current) -> FriendsDailyAggregate {
        var counted: (value: Int, source: StepSource)? = nil
        if let s = steps, s.source.isCounted, s.value >= 0 { counted = s }
        let intensity = intensityRecord.flatMap { $0.recordedIntensity ? $0.credited : nil }
        let longestWorkout = workouts.map { w -> Int in
            let seconds = w.durationS ?? Double(w.endTs - w.startTs)
            return Int((max(0, seconds) / 60).rounded(.down))
        }.max()
        var active: Int? = nil
        if intensity != nil || longestWorkout != nil {
            let byMinutes = (intensity ?? 0) >= friendsActiveMinutes
            let byWorkout = (longestWorkout ?? 0) >= friendsActiveMinutes
            active = byMinutes || byWorkout ? 1 : 0
        }
        let sleepGoal = night.map { $0.asleepMinutes >= Double(sleepGoalMinutes) ? 1 : 0 }
        let bedtime = night.flatMap { n in n.bed }.map { bed -> Int in
            clockDistance(minutesOfDay(bed, calendar: calendar), Double(targetBedMinutes)) <= friendsBedtimeToleranceMin ? 1 : 0
        }
        return FriendsDailyAggregate(day: day, steps: counted?.value, stepsSource: counted?.source, intensity: intensity,
                                     active: active, sleepGoal: sleepGoal, bedtime: bedtime)
    }

    /// The aggregates for `days` through the repository, every input read under `mode`, the Data-source
    /// picker Home reads under, so a shared day never says something Home does not show for it: the
    /// day's steps with their source (Home's Steps card; under imports-only the iPhone's count), the
    /// Intensity records `IntradayDayStore` keeps (so the two never re-score each other's days; the
    /// profile gate applies: a seeded profile scores no minutes, so `intensity` is nil until an age is
    /// entered), the workouts that started each day, and the nights (`SleepNightBuilder`, the Sleep tab's
    /// list) the sleep-goal and bedtime answers come from.
    @MainActor
    static func friendsDailyAggregates(for repo: Repository, days: [String], profile: ProfileStore?,
                                       mode: BaselineDataSource = .current(),
                                       entered: Bool = ProfileSet.current(),
                                       sleepGoalMinutes: Int = SleepGoal.minutes(),
                                       sleepWindow: SleepWindow = .stored(), calendar: Calendar = .current,
                                       now: Date = Date()) async -> [String: FriendsDailyAggregate] {
        let today = Repository.localDayKey(now)
        let wanted = days.filter { $0 <= today }.sorted()
        guard let first = wanted.first, let last = wanted.last else { return [:] }
        let sourced = await stepSourcedReadings(repo, from: first, to: last, mode: mode)
        var stepsByDay: [String: (value: Int, source: StepSource)] = [:]
        for r in sourced { stepsByDay[r.day] = (Int(r.value.rounded()), r.source) }
        let records = await IntradayDayStore.shared.records(repo, profile: profile, days: wanted, mode: mode,
                                                            entered: entered, computeStress: false,
                                                            calendar: calendar, now: now)
        let back = BaselineRangeSeries.dayCount(from: first, to: today) + 2
        let workoutRows = await repo.workoutRows(days: max(3, back))
        let funnel = BaselineReadouts.days(repo, mode: mode)
        let habitual = await repo.habitualMidsleepSec()
        let sessions = await BaselineReadouts.nights(repo, mode: mode, now: now)
        let nights = SleepNightBuilder.nights(sessions: sessions, days: funnel, habitualMidsleepSec: habitual)
        var nightByDay: [String: SleepNight] = [:]
        for n in nights where nightByDay[n.dayKey] == nil { nightByDay[n.dayKey] = n }
        var out: [String: FriendsDailyAggregate] = [:]
        for day in wanted {
            let night = nightByDay[day].map { (asleepMinutes: $0.asleepMin, bed: $0.onset) }
            out[day] = friendsDailyAggregate(for: day, steps: stepsByDay[day], intensityRecord: records[day],
                                             workouts: IntradayDayStore.workouts(startedOn: day, rows: workoutRows),
                                             night: night, sleepGoalMinutes: sleepGoalMinutes,
                                             targetBedMinutes: sleepWindow.bedMinutes, calendar: calendar)
        }
        return out
    }

    /// One day's aggregate through the repository (`friendsDailyAggregates(for:days:…)` for a single day).
    @MainActor
    static func friendsDailyAggregate(for repo: Repository, day: String, profile: ProfileStore?,
                                      mode: BaselineDataSource = .current(),
                                      entered: Bool = ProfileSet.current(),
                                      sleepGoalMinutes: Int = SleepGoal.minutes(),
                                      sleepWindow: SleepWindow = .stored(), calendar: Calendar = .current,
                                      now: Date = Date()) async -> FriendsDailyAggregate {
        let all = await friendsDailyAggregates(for: repo, days: [day], profile: profile, mode: mode, entered: entered,
                                               sleepGoalMinutes: sleepGoalMinutes, sleepWindow: sleepWindow,
                                               calendar: calendar, now: now)
        return all[day] ?? FriendsDailyAggregate(day: day, steps: nil, stepsSource: nil, intensity: nil,
                                                 active: nil, sleepGoal: nil, bedtime: nil)
    }
}
#endif
