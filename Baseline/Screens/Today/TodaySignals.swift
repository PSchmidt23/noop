#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// Pure derivations for Today's Signals card: the few early-warning patterns worth a sentence, built
// from `repo.baselineDays`, the Sleep tab's `SleepNight` list, the `TodaySnapshot` the hero tiles draw and the
// recent native journal. Nothing here touches the store or SwiftUI; unit-tested in `TodaySignalsTests`.

/// One thing worth saying this morning. `sentence` is the calm, non-medical line the card prints;
/// `method` is the matching entry under "How this is computed".
struct TodaySignal: Identifiable, Equatable {
    enum Kind: String {
        /// Resting HR up, HRV down, skin temperature or breathing rate up, together, over the last
        /// two nights (NOOP's `IllnessSignalEngine`, with its confounder suppression).
        case illnessWatch
        /// Effort over the last 7 days spiking against the last 28, or climbing with no variety
        /// (`ReadinessEngine`'s acute:chronic ratio and Foster monotony).
        case overreaching
        /// Several consecutive nights well under the person's own 30-night average.
        case shortNights
    }

    let kind: Kind
    /// The pill's label ("Watch", "Effort load", "Short nights"); always in the watch colour.
    let pill: String
    let sentence: String
    let method: String
    var id: String { kind.rawValue }
}

struct TodaySignals: Equatable {
    let signals: [TodaySignal]
    var isEmpty: Bool { signals.isEmpty }
    static let empty = TodaySignals(signals: [])

    // MARK: Tunables (named so the gating is auditable)

    /// Nights averaged for the illness-watch read (NOOP's `AppModel.applyIllnessSignal` window).
    static let illnessRecentNights = 2
    /// One personal spread of a stored skin-temperature DEVIATION (°C), the `skin_temp` floor spread;
    /// NOOP z-scores a deviation night as `value / 0.3` rather than folding a separate baseline.
    static let skinTempDeviationSpreadC = 0.3
    /// Acute:chronic effort ratio at which the week reads as a spike (`ReadinessEngine`'s "bad" band).
    static let acwrSpike = 1.5
    /// Acute:chronic ratio from which the week is "building fast" (`ReadinessEngine`'s "watch" band).
    static let acwrBuilding = 1.3
    /// Foster monotony (weekly mean ÷ SD of effort) at or above which variety is low.
    static let monotonyLow = 2.0
    /// A night is short when it falls at least this many minutes under the 30-night average before it.
    static let shortNightShortfallMin = 60.0
    /// Consecutive short nights before the card says so.
    static let shortNightsMinRun = 3

    // MARK: Build

    /// `days` is `repo.baselineDays` (oldest → newest); `nights` is `SleepNightBuilder.nights(…)` (newest
    /// first), the Sleep tab's list; `snapshot` is the `TodaySnapshot` built for the same inputs, so the
    /// baselines judged here are the ones the hero tiles print; `journal` is the recent native journal
    /// (`repo.journalEntries(days: 7)`), read only for the confounders NOOP's engine rules out.
    ///
    /// Empty while readiness is calibrating (`TodayReadiness.calibrating`, under 14 HRV nights): a
    /// warning off a cold-start baseline is the one thing the engine refuses to give.
    static func build(days: [DailyMetric], nights: [SleepNight], snapshot: TodaySnapshot,
                      journal: [JournalEntry] = []) -> TodaySignals {
        if case .calibrating = snapshot.readiness { return .empty }
        let todayKey = snapshot.todayKey
        let scoped = days.filter { $0.day <= todayKey }
        var out: [TodaySignal] = []
        if let s = illnessWatch(scoped, snapshot: snapshot, journal: journal) { out.append(s) }
        if let s = overreaching(scoped, todayKey: todayKey) { out.append(s) }
        if let s = shortNights(nights.filter { $0.dayKey <= todayKey }, todayKey: todayKey) { out.append(s) }
        return TodaySignals(signals: out)
    }

    // MARK: Illness watch

    /// NOOP's own gate, re-fed from Baseline's funnels: the mean of the last two nights of resting HR,
    /// HRV, skin temperature and breathing rate, each z-scored against the person's baseline (resting
    /// HR and HRV against the SAME `BaselineState` the hero tiles print), handed to
    /// `IllnessSignalEngine.evaluate`. Two signals must clear z = 2 together and the composite must reach
    /// `mildThreshold`; a night with alcohol, stress, a sauna or a hard workout in the journal is
    /// explained away (`.suppressed`) rather than raised. Silent unless the resting-HR or HRV baseline
    /// is trusted (≥ 14 nights), unless both readings are fresh, and for `.alreadyUnwell` (the person
    /// already knows; there is nothing to warn about).
    private static func illnessWatch(_ scoped: [DailyMetric], snapshot: TodaySnapshot,
                                     journal: [JournalEntry]) -> TodaySignal? {
        guard scoped.count >= Baselines.minNightsTrust,
              let rhr = snapshot.restingHr, !rhr.isStale,
              let hrv = snapshot.hrv, !hrv.isStale,
              rhr.state.usable, hrv.state.usable,
              rhr.state.trusted || hrv.state.trusted else { return nil }

        let recent = scoped.suffix(illnessRecentNights)
        func recentMean(_ value: (DailyMetric) -> Double?) -> Double? {
            let vals = recent.compactMap(value)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        guard let rhrMean = recentMean({ $0.restingHr.map(Double.init) }),
              let hrvMean = recentMean({ $0.avgHrv }) else { return nil }
        let rhrDev = Baselines.deviation(rhrMean, state: rhr.state)
        let hrvDev = Baselines.deviation(hrvMean, state: hrv.state)

        var inputs = IllnessSignalEngine.Inputs(
            restingHR: .init(zIllnessward: rhrDev.z),
            hrv: .init(zIllnessward: -hrvDev.z))   // an HRV drop is illness-ward

        // Breathing rate: its own fold through the hero funnel, present only once usable.
        if let respMean = recentMean({ $0.respRateBpm }) {
            let state = BaselineReadouts.latestNight(upToToday: scoped, cfg: Baselines.respCfg) { $0.respRateBpm }.state
            if state.usable {
                inputs.respiration = .init(zIllnessward: Baselines.deviation(respMean, state: state).z)
            }
        }
        // Skin temperature is bimodal in the store (#111/#622): a WHOOP CSV night is an ABSOLUTE wrist °C,
        // a strap night a signed DEVIATION. Judge the recent nights in the kind of the newest one only.
        if let newestSkin = recent.reversed().compactMap(\.skinTempDevC).first {
            let absolute = VitalBands.isAbsoluteSkinTemp(newestSkin)
            let sameKind: (DailyMetric) -> Double? = { d in
                d.skinTempDevC.flatMap { VitalBands.isAbsoluteSkinTemp($0) == absolute ? $0 : nil }
            }
            if let skinMean = recentMean(sameKind) {
                if absolute, let cfg = Baselines.metricCfg["skin_temp"] {
                    let state = BaselineReadouts.latestNight(upToToday: scoped, cfg: cfg, value: sameKind).state
                    if state.usable {
                        inputs.skinTemp = .init(zIllnessward: Baselines.deviation(skinMean, state: state).z)
                    }
                } else {
                    inputs.skinTemp = .init(zIllnessward: skinMean / skinTempDeviationSpreadC)
                }
            }
        }

        let context = confounders(journal, recentDays: Set(recent.map(\.day)).union([snapshot.todayKey]),
                                  baselineTrusted: rhr.state.trusted || hrv.state.trusted)
        // The engine returns the labels of the signals that fired; handing it the keys gets the keys back.
        let keys = ["restingHR", "skinTemp", "hrv", "respiration"]
        let result = IllnessSignalEngine.evaluate(inputs, context: context,
                                                  firedLabels: Dictionary(uniqueKeysWithValues: keys.map { ($0, $0) }))

        let tail: String
        switch result.level {
        case .raised:
            tail = "This pattern often precedes feeling unwell; consider an easier day."
        case .mild:
            tail = "Mild so far; a calmer day is a reasonable choice."
        case .suppressed:
            // `suppressedBy` is the engine's own phrasing ("alcohol", "a hard or late workout", "travel").
            tail = "You logged \(joined(result.suppressedBy)) that night, which usually explains it."
        case .quiet, .alreadyUnwell:
            return nil
        }

        var clauses: [String] = []
        for key in result.firedSignals {
            switch key {
            case "restingHR":
                let bpm = Int(rhrDev.delta.rounded())
                let streak = elevatedRun(scoped, state: rhr.state)
                var clause = "Resting HR is \(bpm) bpm above your baseline"
                if streak >= 2 { clause += " for the \(ordinal(streak)) night" }
                clauses.append(clause)
            case "hrv":
                let pct = Int((-hrvDev.ratio * 100).rounded())
                clauses.append("HRV is suppressed (\(pct)% below your baseline)")
            case "skinTemp":
                clauses.append("skin temperature is up")
            case "respiration":
                clauses.append("breathing rate is up")
            default:
                break
            }
        }
        guard !clauses.isEmpty else { return nil }
        let sentence = capitalized(joined(clauses)) + ". " + tail

        return TodaySignal(
            kind: .illnessWatch, pill: "Watch", sentence: sentence,
            method: "Resting HR, HRV, skin temperature and breathing rate averaged over the last two nights, each "
                + "against your own baseline (the one the tiles above use). At least two have to move together, "
                + "by two standard deviations or more, before anything is said, and a night you logged alcohol, "
                + "stress, a sauna or a hard workout is explained away first. An estimate from your own data, "
                + "not a diagnosis.")
    }

    /// Consecutive nights, newest first, whose resting HR sits more than one sigma above `state`.
    static func elevatedRun(_ scoped: [DailyMetric], state: BaselineState) -> Int {
        var n = 0
        for d in scoped.reversed() {
            guard let v = d.restingHr.map(Double.init) else { continue }
            guard Baselines.deviation(v, state: state).z > 1 else { break }
            n += 1
        }
        return n
    }

    /// NOOP's keyword rule (`AppModel.evaluateIllness`) over the "yes" answers of the recent days: the
    /// canonical question text is the key, so a renamed chip still counts.
    static func confounders(_ journal: [JournalEntry], recentDays: Set<String>,
                            baselineTrusted: Bool) -> IllnessSignalEngine.Context {
        var ctx = IllnessSignalEngine.Context(baselineTrusted: baselineTrusted)
        for e in journal where e.answeredYes && recentDays.contains(e.day) {
            let q = e.question.lowercased()
            if q.contains("alcohol") || q.contains("drink") { ctx.alcohol = true }
            if q.contains("stress") { ctx.stress = true }
            if q.contains("sauna") { ctx.sauna = true }
            if q.contains("workout") || q.contains("train") || q.contains("exercise") { ctx.hardOrLateWorkout = true }
            if q.contains("sick") || q.contains("unwell") || q.contains(" ill") { ctx.alreadyUnwell = true }
        }
        return ctx
    }

    // MARK: Overreaching

    /// `ReadinessEngine.evaluate` anchored on the newest row, which must be within `Baselines.vitalCarryDays`
    /// of today (a months-old import must not read as this week). Says something when the acute:chronic
    /// effort ratio reaches `acwrSpike`, or sits in the building band with monotony at `monotonyLow` or
    /// more. Both numbers come straight from the engine; nothing is recomputed here.
    private static func overreaching(_ scoped: [DailyMetric], todayKey: String) -> TodaySignal? {
        guard let anchor = scoped.last?.day,
              anchor >= Baselines.cutoffKey(todayKey: todayKey) else { return nil }
        let r = ReadinessEngine.evaluate(days: scoped, today: anchor)
        guard let acwr = r.acwr else { return nil }
        let ratio = String(format: "%.1f", acwr)
        let sentence: String
        if acwr >= acwrSpike {
            sentence = "Effort this week is \(ratio)× your four-week average. A jump this steep is usually followed "
                + "by fatigue; an easier day or two lets the body catch up."
        } else if acwr >= acwrBuilding, let mono = r.monotony, mono >= monotonyLow {
            sentence = "Effort this week is \(ratio)× your four-week average with little day-to-day variety. "
                + "A lighter day keeps the climb sustainable."
        } else {
            return nil
        }
        return TodaySignal(
            kind: .overreaching, pill: "Effort load", sentence: sentence,
            method: "Effort over the last 7 days against the last 28 (the acute:chronic ratio; 0.8–1.3 is the "
                + "steady range, 1.5 and above a spike) and how varied those 7 days were (monotony, the weekly "
                + "mean divided by its spread; 2.0 and up is low variety).")
    }

    // MARK: Short nights

    /// `nights` is newest first and already cut to `dayKey <= todayKey`. The run starts at the newest
    /// night, which must be within `Baselines.vitalCarryDays` of today, and continues through nights on
    /// CONSECUTIVE days (a missed night breaks "in a row") that each fall `shortNightShortfallMin` or more
    /// under `BaselineReadouts.sleepAverage30(before:in:)`, the Sleep tab's own average. Needs
    /// `shortNightsMinRun`.
    private static func shortNights(_ nights: [SleepNight], todayKey: String) -> TodaySignal? {
        guard let newest = nights.first,
              newest.dayKey >= Baselines.cutoffKey(todayKey: todayKey) else { return nil }
        var run: [SleepNight] = []
        var previous: SleepNight?
        for night in nights {
            if let p = previous, Baselines.cutoffKey(todayKey: p.dayKey, carryDays: 1) != night.dayKey { break }
            guard let avg = BaselineReadouts.sleepAverage30(before: night.dayKey, in: nights),
                  night.asleepMin <= avg - shortNightShortfallMin else { break }
            run.append(night)
            previous = night
        }
        guard run.count >= shortNightsMinRun, let oldest = run.last,
              let before = BaselineReadouts.sleepAverage30(before: oldest.dayKey, in: nights) else { return nil }
        let mean = run.reduce(0) { $0 + $1.asleepMin } / Double(run.count)
        let sentence = "\(countWord(run.count)) nights in a row at least an hour under your 30-night average: "
            + "\(BaselineReadouts.durationText(minutes: mean)) a night against "
            + "\(BaselineReadouts.durationText(minutes: before)). Short sleep lowers HRV for most people; "
            + "an earlier night tonight pays some of it back."
        return TodaySignal(
            kind: .shortNights, pill: "Short nights", sentence: sentence,
            method: "Each night against the average of the 30 recorded nights before it, the Sleep tab's "
                + "average. A night counts as short when it falls at least an hour under that average, and "
                + "three or more short nights on consecutive days are reported here.")
    }

    // MARK: Words

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        case 6: return "sixth"
        case 7: return "seventh"
        default: return "\(n)th"
        }
    }

    static func countWord(_ n: Int) -> String {
        switch n {
        case 3: return "Three"
        case 4: return "Four"
        case 5: return "Five"
        case 6: return "Six"
        case 7: return "Seven"
        default: return "\(n)"
        }
    }

    /// "a", "a and b", "a, b and c".
    static func joined(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    private static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
#endif
