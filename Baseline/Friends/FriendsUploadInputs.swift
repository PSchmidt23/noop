#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// Reads the person's own data for the Friends upload (FRIENDS_SPEC.md §5.2). Everything is read under the
/// Data-source picker (`baseline.dataSource`), the mode Home reads under. The behaviour half comes from ONE
/// readout, `BaselineReadouts.friendsDailyAggregates` (steps with their source, credited Intensity minutes, active
/// day, sleep goal, on-time bedtime: the same functions Home draws from), so an upload can never say something the
/// app itself does not. The physiology half is the funnel's valid nights and stored Readiness scores, which
/// `FriendsUploadBuilder` turns into clipped weekly changes against the person's own baseline. The pure half is
/// `FriendsUploadBuilder`.
extension FriendsUploadInputs {

    /// How far back physiology history is read: enough for a baseline folded before each of the 5 weeks.
    static let historyDays = 150

    /// `days` are the day keys the scheduler wants rows for (35 on a full upload). The per-day intraday store
    /// answers from its cache for any day it already computed.
    @MainActor
    static func load(_ repo: Repository, profile: ProfileStore?, days: [String], now: Date = Date(),
                     defaults: UserDefaults = .standard) async -> FriendsUploadInputs {
        let today = Repository.localDayKey(now)
        var inputs = FriendsUploadInputs(today: today)
        let sleepGoal = BaselineReadouts.SleepGoal.minutes(defaults)
        let window = BaselineReadouts.SleepWindow.stored(defaults)
        inputs.sleepGoalMinutes = sleepGoal
        inputs.targetBedMinutes = window.bedMinutes

        let mode = BaselineDataSource.current(defaults)
        let aggregates = await BaselineReadouts.friendsDailyAggregates(for: repo, days: days, profile: profile,
                                                                      mode: mode, sleepGoalMinutes: sleepGoal,
                                                                      sleepWindow: window, now: now)
        for (day, a) in aggregates {
            if let steps = a.steps, let source = a.stepsSource, source.isCounted {
                inputs.stepDays[day] = StepDay(value: steps, source: source.rawValue)
            }
            if let minutes = a.intensity { inputs.intensityDays[day] = minutes }
            if a.active != nil || a.sleepGoal != nil || a.bedtime != nil {
                inputs.dayFlags[day] = DayFlags(active: a.active, sleepGoal: a.sleepGoal, bedtime: a.bedtime)
            }
        }

        // Physiology: valid nights from the funnel Home reads, and the stored Readiness score (never recomputed).
        let historyFrom = FriendsDates.adding(-historyDays, to: today)
        for d in BaselineReadouts.days(repo, mode: mode) where d.day >= historyFrom && d.day <= today {
            if let hrv = d.avgHrv, hrv.isFinite, hrv > 0 { inputs.hrvNights[d.day] = hrv }
            if let rhr = d.restingHr, rhr > 0 { inputs.rhrNights[d.day] = Double(rhr) }
            if let score = d.recovery, score.isFinite { inputs.readinessByDay[d.day] = min(100, max(0, score)) }
        }
        inputs.hrvEpoch = Baselines.hrvBaselineEpoch()
        return inputs
    }
}
#endif
