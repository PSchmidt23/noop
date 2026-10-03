#if os(iOS)
import Foundation
import StrandAnalytics

// The words Home's three activity cards (Steps, Calories, Stress) print, kept pure so the tests can
// pin them, plus the one place the screens reach the activity readouts' goal settings
// (`ActivityGoals`). Research and the rules behind every line: `Baseline/Research/ACTIVITY_METRICS.md`
// ("Implementable spec").

// MARK: - Goals (the screens' one door to the settings the readouts own)

/// The daily step goal and the profile's "height and weight entered" flag, as the screens read them.
/// The goal itself lives with the readouts (`StepGoal`, `baseline.stepGoal`: default 8,000, 3,000–30,000
/// in steps of 500, fixed, never auto-adjusted); Home, Trends, the Steps detail and Settings › Activity
/// goals all go through here, so one rename touches one file.
enum ActivityGoals {
    /// `UserDefaults` key of the daily step goal (`@AppStorage` in every view that draws it).
    static var stepKey: String { StepGoal.key }
    /// The goal when nothing is stored.
    static var stepDefault: Int { StepGoal.defaultGoal }
    /// The stepper's span and increment in Settings › Activity goals.
    static var stepRange: ClosedRange<Int> { StepGoal.range }
    static var stepIncrement: Int { StepGoal.step }

    /// The stored goal, clamped (a hand-edited or older value snaps into range).
    static func stepGoal(_ defaults: UserDefaults = .standard) -> Int { StepGoal.goal(defaults) }

    /// An `@AppStorage` value of `stepKey`, clamped the same way, for the views that bind the key
    /// directly: a goal an older build stored under the 3,000 floor (2,500) draws as 3,000 on Home and the
    /// Steps detail, the goal Friends counts (`FriendsScoring.storedStepGoal`), before Settings is opened.
    static func stepGoal(stored: Int) -> Int { StepGoal.clamp(stored) }

    /// `baseline.bodySet` (`BodySet.key`): true once Settings › Profile has had its height or weight
    /// entered or confirmed (NOOP seeds 178 cm / 75 kg and persists them, so the store alone cannot
    /// tell). Part of Home's reload key: flipping it drops the Calories card's "Using 178 cm · 75 kg" line.
    static var bodySetKey: String { BodySet.key }
}

// MARK: - Steps

/// The Steps card's lines (`StepsCard`): the goal status and the 7-day context joined into ONE line, the
/// source caption, the spoken hero, and the goal-day count under the week's bars.
enum StepsCardText {
    /// "1,760 to go" on today before the goal; "Goal met" on any day that reached it; nil on a finished
    /// day under the goal (the bar already shows how far it got; a past day is not scolded).
    static func goalStatus(steps: Int?, goal: Int, isToday: Bool) -> String? {
        guard let steps, goal > 0 else { return nil }
        if steps >= goal { return "Goal met" }
        guard isToday else { return nil }
        return BaselineReadouts.stepsText(goal - steps) + " to go"
    }

    /// The comparison with the 7 days before: a finished day against their average
    /// (`BaselineReadouts.stepsDeltaText`, ±5 % reads "On your 7‑day average"); today only names the
    /// average, never judges a partial count against whole days; "7‑day average after 2 more days" while
    /// fewer than `BaselineReadouts.averageMinDays` days are recorded.
    static func context(steps: Int?, average7: Double?, observed7: Int, isToday: Bool) -> String {
        let label = "7\u{2011}day"
        guard let average7 else {
            let n = max(1, BaselineReadouts.averageMinDays - observed7)
            return "\(label) average after \(n) more day\(n == 1 ? "" : "s")"
        }
        if isToday || steps == nil {
            return "\(label) average " + BaselineReadouts.stepsText(Int(average7.rounded()))
        }
        return BaselineReadouts.stepsDeltaText(steps: steps, average: average7, windowLabel: label)
            ?? "\(label) average " + BaselineReadouts.stepsText(Int(average7.rounded()))
    }

    /// The card's ONE line under the goal bar: "1,760 to go · 7‑day average 7,480", "Goal met · +1,240 vs
    /// your 7‑day average", or "No steps yet today · 7‑day average 7,480" for a day nothing has counted.
    static func line(steps: Int?, goal: Int, average7: Double?, observed7: Int, isToday: Bool) -> String {
        let lead: String? = steps == nil
            ? (isToday ? "No steps yet today" : "No steps recorded")
            : goalStatus(steps: steps, goal: goal, isToday: isToday)
        let ctx = context(steps: steps, average7: average7, observed7: observed7, isToday: isToday)
        return [lead, ctx].compactMap { $0 }.joined(separator: " · ")
    }

    /// The hero as VoiceOver hears it: "6,240 of 8,000 steps" (the visible "of 8,000" in words).
    static func spoken(steps: Int?, goal: Int) -> String {
        guard let steps else { return "No steps recorded, goal \(BaselineReadouts.stepsText(goal))" }
        return "\(BaselineReadouts.stepsText(steps)) of \(BaselineReadouts.stepsText(goal)) steps"
    }

    /// Days among `values` that reached the goal (nil days are not counted, and not held against it).
    /// (`StepsReadout.goalDays(goal:)` counts the readout's own week the same way.)
    static func goalDays(_ values: [Double?], goal: Int) -> Int {
        values.compactMap { $0 }.filter { $0 >= Double(goal) }.count
    }

    /// The week's bars as VoiceOver hears them: "Goal met on 4 of the last 7 days".
    static func weekSummary(_ values: [Double?], goal: Int) -> String {
        "Goal met on \(goalDays(values, goal: goal)) of the last \(values.count) days"
    }

    /// The first-run line on a day no source has ever counted (the strap on the bicep, no phone steps).
    static let noSourceToday = "No steps yet. The strap counts steps on the wrist only; allow Apple Health steps to use your iPhone's count."
}

// MARK: - Calories

/// The Calories card's lines (`CaloriesCard`). Every figure prints through `BaselineReadouts.caloriesText`
/// (rounded to 10: no consumer device is within 20 % of calorimetry).
enum CaloriesCardText {
    /// "Calories so far" / "Calories"; "Active calories" while no age and sex exist to estimate the
    /// resting part from.
    static func title(hasResting: Bool, isToday: Bool) -> String {
        let noun = hasResting ? "Calories" : "Active calories"
        return isToday ? "\(noun) so far" : noun
    }

    /// The split under the bar: "1,620 resting · 520 active", "· active from Apple Health" when the strap
    /// recorded no heart rate that day. Resting alone says why there is no active part.
    static func split(resting: Double?, active: Double?, activeFromAppleHealth: Bool, isToday: Bool) -> String? {
        switch (resting, active) {
        case let (r?, a?):
            let line = "\(BaselineReadouts.caloriesText(r)) resting · \(BaselineReadouts.caloriesText(a)) active"
            return activeFromAppleHealth ? line + " · active from Apple Health" : line
        case let (r?, nil):
            return isToday ? "\(BaselineReadouts.caloriesText(r)) resting · active adds up as the strap records heart rate"
                           : "\(BaselineReadouts.caloriesText(r)) resting · no heart rate recorded for an active estimate"
        case (nil, _?):
            return activeFromAppleHealth ? "From Apple Health" : nil
        case (nil, nil):
            return nil
        }
    }

    /// ONE context line, on the ACTIVE part only (resting is a formula and barely moves): "Active +180
    /// vs your 30‑day average" / "Active on your 30‑day average". Finished days only: today is partial.
    static func activeContext(active: Double?, average30: Double?, isToday: Bool) -> String? {
        guard !isToday, let delta = BaselineReadouts.caloriesDeltaText(kcal: active, average: average30) else { return nil }
        if delta.hasPrefix("On ") { return "Active on" + delta.dropFirst(2) }
        return "Active " + delta
    }

    /// While height and weight are NOOP's seeded defaults: "Using 178 cm · 75 kg. Edit in Profile".
    static func bodyLine(heightCm: Double, weightKg: Double) -> String {
        "Using \(Int(heightCm.rounded())) cm · \(Int(weightKg.rounded())) kg. Edit in Profile"
    }

    /// Without an age and sex there is no resting estimate; the chevron row asks for them.
    static let profileAsk = "Add your age and sex in Profile to include resting calories"

    /// The detail's caveat, and the popover of the header's accuracy badge (`CaloriesBadges`, Home and
    /// Trends), which is why the header carries no separate "Estimate" pill.
    static let caveat = "Heart-rate estimate; no wrist or strap device is within 20 % of lab measurement. Compare with your own days, not with food labels."

    /// The two-segment bar's active share, 0…1 (resting fills the rest).
    static func activeShare(resting: Double?, active: Double?) -> Double {
        guard let r = resting, let a = active, r + a > 0 else { return active == nil ? 0 : 1 }
        return min(1, max(0, a / (r + a)))
    }
}

// MARK: - Stress

/// The Stress card's lines (`StressCard`): hours, never a 0–3 number and never minutes (the scorer's
/// grain is one hour). Elevated = heart rate at least 15 bpm over the person's calm daytime floor while
/// still; calm = 3 to 15 bpm over it; restored = at the floor.
enum StressCardText {
    /// Fewest scored hours before a day is totalled.
    static var minScoredHours: Int { StressState.minTotalledHours }
    /// Days of daytime heart rate the personal lens needs (`Baselines.minNightsSeed`, NOOP's seed).
    static var learningDaysNeeded: Int { Baselines.minNightsSeed }
    /// From this hour on, today is compared with the typical day.
    static let compareFromHour = 18
    /// "About your typical" within this many hours either way.
    static let typicalTolerance = 1.0

    /// "2 h", "2.5 h".
    static func hoursText(_ h: Double) -> String {
        let r = (h * 2).rounded() / 2
        return r == r.rounded() ? "\(Int(r)) h" : String(format: "%.1f h", r)
    }

    /// "2 h elevated · 7 h calm · 2 h restored", "· 1 h moving" when hours were left out for movement.
    static func headline(elevated: Int, calm: Int, restored: Int, moving: Int) -> String {
        var parts = ["\(hoursText(Double(elevated))) elevated", "\(hoursText(Double(calm))) calm",
                     "\(hoursText(Double(restored))) restored"]
        if moving > 0 { parts.append("\(hoursText(Double(moving))) moving") }
        return parts.joined(separator: " · ")
    }

    /// Whether the day may be totalled: the personal lens is on and enough still hours were scored.
    static func showsTotals(learning: Bool, scoredHours: Int) -> Bool {
        !learning && scoredHours >= minScoredHours
    }

    /// The ONE sentence under the bar (or the curve, while the day cannot be totalled):
    /// - still learning: "Learning your daytime baseline · 2 of 4 days";
    /// - under three scored hours: "Only 2 h of still, daytime wear, too little to total";
    /// - today before 18:00: "So far today · elevated means 15 bpm or more over your calm heart rate";
    /// - no typical yet (under five qualifying days): "Your typical appears after 5 days of daytime wear";
    /// - otherwise elevated hours against the person's own 14-day typical (±1 h is "about").
    static func sentence(elevated: Int, scoredHours: Int, typical: Double?, learningDays: Int?,
                         isToday: Bool, hour: Int) -> String {
        if let n = learningDays {
            return "Learning your daytime baseline · \(min(n, learningDaysNeeded)) of \(learningDaysNeeded) days"
        }
        if scoredHours < minScoredHours {
            return "Only \(hoursText(Double(scoredHours))) of still, daytime wear, too little to total"
        }
        if isToday && hour < compareFromHour {
            return "So far today · elevated means 15 bpm or more over your calm heart rate"
        }
        guard let typical else { return "Your typical appears after 5 days of daytime wear" }
        let e = Double(elevated)
        if abs(e - typical) <= typicalTolerance { return "About your typical \(hoursText(typical)) elevated" }
        return e < typical ? "Less elevated time than your typical \(hoursText(typical))"
                           : "More elevated time than your typical \(hoursText(typical))"
    }

    /// The detail's lens line: "Against your daytime heart-rate floor: 64 bpm (30 days)".
    static func floorLine(_ floorBPM: Double) -> String {
        "Against your daytime heart-rate floor: \(Int(floorBPM.rounded())) bpm (30 days)"
    }

    /// The detail's peak line: "Most elevated 2:00–3:00 PM (+21 bpm over your floor)"; the bpm part only
    /// when the floor is known.
    static func peakLine(start: Date, overFloorBPM: Double?, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)
        let span = (start..<end).formatted(.interval.hour().minute())
        guard let over = overFloorBPM, over >= 0.5 else { return "Most elevated \(span)" }
        return "Most elevated \(span) (+\(Int(over.rounded())) bpm over your floor)"
    }

    /// The detail's caveat: what the hours are and are not.
    static let caveat = "Stress here is heart rate above your calm level while you're still. Excitement, caffeine, a big meal or heat look the same. Not a measure of how you feel."
}

extension BaselineReadouts.StressDayReadout {
    /// Days of daytime history so far while the lens is still learning; nil once it is personal.
    var learningDays: Int? {
        if case .learning(let n) = lens { return n }
        return nil
    }

    /// The day may be totalled (`StressCardText.showsTotals`).
    var showsTotals: Bool { StressCardText.showsTotals(learning: learningDays != nil, scoredHours: scoredHours) }
}
#endif
