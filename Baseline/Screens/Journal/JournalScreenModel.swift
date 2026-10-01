#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// The outcome the effects feed is ranked against.
enum JournalOutcome: String, CaseIterable, Identifiable {
    case hrv, rhr
    var id: String { rawValue }
    /// `repo.series` key and `DailyMetric` fallback column.
    var key: String { rawValue }
    var label: String { self == .hrv ? "HRV" : "Resting HR" }
    var unit: String { self == .hrv ? "ms" : "bpm" }
    var higherIsBetter: Bool { self == .hrv }
    var color: Color { self == .hrv ? BaselineTheme.hrv : BaselineTheme.rhr }
}

/// One dose-response read, ready for a card.
///
/// Caffeine's prior is documented in HRV (ms), the unit Today and Trends show, so that card carries
/// the per-step shift. Alcohol's prior is documented in the engine's 0–100 overnight score ("Charge"
/// upstream), which no Baseline screen renders and which is not the three-tier Readiness label, so
/// that card names the morning as a whole and stays directional: no points, no per-drink figure.
struct JournalDose: Identifiable {
    let behavior: DosedBehavior
    let response: DoseResponse
    var id: String { behavior.rawValue }

    var title: String { behavior == .alcohol ? "Alcohol" : "Caffeine timing" }
    var icon: String { behavior == .alcohol ? "wineglass" : "cup.and.saucer" }
    var subtitle: String {
        "Dose response · \(behavior == .alcohol ? "the next morning overall" : "HRV next morning")"
    }

    /// The per-unit shift as a stat cell: caffeine only, in ms. Lower is worse.
    var perUnitStat: (label: String, unit: String, color: Color)? {
        guard behavior == .caffeine else { return nil }
        let color = response.perUnit < -0.05 ? BaselineTheme.watch : (response.perUnit > 0.05 ? BaselineTheme.good : BaselineTheme.textSecondary)
        return (label: "Per later step", unit: "ms", color: color)
    }

    /// One honest sentence in Baseline's voice. Says when it is still mostly the population prior.
    var sentence: String {
        let r = response
        let nights = r.nUser == 1 ? "1 night" : "\(r.nUser) nights"
        switch behavior {
        case .alcohol:
            if r.contradictsPrior {
                return "In your data so far, drinks don't bring the next morning down the way they usually do (\(nights))."
            }
            if r.priorDominated {
                let dir = r.priorSlope <= 0 ? "lower" : "higher"
                return "The more you drink, the \(dir) the next morning reads. That is the typical pattern, not yet yours (\(nights))."
            }
            let dir = r.perUnit <= 0 ? "lower" : "higher"
            return "The more you drink, the \(dir) the next morning reads for you (\(nights))."
        case .caffeine:
            if r.contradictsPrior {
                return "In your data so far, late caffeine doesn't move your HRV the way it usually does (\(nights))."
            }
            let mag = JournalLabels.magnitude(abs(r.perUnit))
            let dir = r.perUnit <= 0 ? "lower" : "higher"
            let base = "Each step later in the day you have caffeine lines up with about \(mag) ms \(dir) HRV the next morning"
            if r.priorDominated {
                return "\(base). That is the typical pattern, not yet yours (\(nights))."
            }
            return "\(base) for you (\(nights))."
        }
    }
}

/// Journal screen state: the selected day's answers, the journal's yes/no day sets, the outcome
/// series the effects are ranked against, and the ranked feed. Reads go through `Repository`;
/// writes are optimistic and then re-read so the chips never lag the store.
@MainActor
final class JournalScreenModel: ObservableObject {
    @Published private(set) var loaded = false
    /// Selected day, native rows only: question → answeredYes.
    @Published private(set) var answers: [String: Bool] = [:]
    /// Selected day, native rows only: question → numeric value.
    @Published private(set) var numeric: [String: Double] = [:]
    /// Distinct imported (WHOOP CSV) question strings, adopted into the catalog so logged and
    /// imported days group under one behaviour.
    @Published private(set) var importedQuestions: [String] = []
    /// Distinct days (imported ∪ native) carrying at least one answer in the last year.
    @Published private(set) var loggedDayCount = 0
    /// Days in the picker range with at least one native answer (for the strip's dots).
    @Published private(set) var loggedDayKeys: Set<String> = []
    /// Ranked for `outcome`: solid first, then by |delta|.
    @Published private(set) var effects: [RankedEffect] = []
    @Published private(set) var doses: [JournalDose] = []
    @Published var outcome: JournalOutcome = .hrv { didSet { rerank() } }

    /// Nights the effects card needs before it tries to find patterns.
    static let minLoggedDays = 5

    private var behaviours: [String: Set<String>] = [:]
    private var controls: [String: Set<String>] = [:]
    private var numericSeries: [String: [String: Double]] = [:]
    private var outcomeByKey: [String: [String: Double]] = [:]
    /// Bumped by every write, so a read that was in flight when the user tapped never lands on top
    /// of the optimistic update.
    private var writeSeq = 0
    /// Bumped whenever the chips' day changes, so a slower read for an older day (a full `load`
    /// started before the tap, or a write's re-read of the day it targeted) never lands under the
    /// newer day's caption.
    private var daySeq = 0

    private static let source = "my-whoop"
    /// hrv / rhr drive the feed; recovery backs the alcohol dose prior ("Charge" in the engine).
    private static let outcomeKeys = ["hrv", "rhr", "recovery"]

    // MARK: Load

    func load(repo: Repository, day: String) async {
        let gen = daySeq
        var byKey: [String: [String: Double]] = [:]
        for key in Self.outcomeKeys {
            var dict: [String: Double] = [:]
            for row in await repo.series(key: key, source: Self.source) { dict[row.day] = row.value }
            for d in repo.days where dict[d.day] == nil {
                if let v = Self.dailyOutcome(key: key, day: d) { dict[d.day] = v }
            }
            byKey[key] = dict
        }
        outcomeByKey = byKey

        var seen = Set<String>()
        var questions: [String] = []
        for e in await repo.importedJournalEntries() where seen.insert(JournalCatalogStore.norm(e.question)).inserted {
            questions.append(e.question)
        }
        importedQuestions = questions

        await reloadJournal(repo: repo)
        await readDay(repo: repo, day: day, gen: gen)   // skipped if a chip tap moved the day meanwhile
        loaded = true
    }

    /// Re-read the journal (yes/no day sets, numeric series, logged-day counts) and re-rank.
    func reloadJournal(repo: Repository) async {
        let entries = await repo.journalEntries(days: 365)
        var yes: [String: Set<String>] = [:]
        var no: [String: Set<String>] = [:]
        var days = Set<String>()
        for e in entries {
            days.insert(e.day)
            if e.answeredYes { yes[e.question, default: []].insert(e.day) }
            else { no[e.question, default: []].insert(e.day) }
        }
        behaviours = yes
        controls = no
        loggedDayCount = days.count
        numericSeries = await repo.numericJournalSeries()
        loggedDayKeys = await repo.nativeJournalDays(from: JournalDay.key(offset: JournalDay.offsets.first ?? 6),
                                                     to: JournalDay.key(offset: 0))
        rerank()
        redose()
    }

    /// The chips' day changed: read it, superseding any slower read still in flight for another day.
    func reloadDay(repo: Repository, day: String) async {
        daySeq += 1
        await readDay(repo: repo, day: day, gen: daySeq)
    }

    /// Read `day`'s rows into the chips, unless the day or a write moved on while the store answered.
    /// `gen` is the `daySeq` the caller saw when `day` was still the chips' day.
    private func readDay(repo: Repository, day: String, gen: Int) async {
        guard gen == daySeq else { return }   // the chips already show another day
        let seq = writeSeq
        let a = await repo.nativeJournalAnswers(day: day)
        let n = await repo.nativeJournalNumeric(day: day)
        guard gen == daySeq, seq == writeSeq else { return }   // a newer day or write already updated the chips
        answers = a
        numeric = n
    }

    // MARK: Writes (optimistic, then re-read)

    /// yes / no / nil (clear) for a yes-no item.
    func setAnswer(_ value: Bool?, question: String, day: String, repo: Repository) async {
        let gen = daySeq
        writeSeq += 1
        answers[question] = value
        numeric[question] = nil
        if let value {
            await repo.saveJournalAnswer(day: day, question: question, answeredYes: value)
        } else {
            await repo.clearJournalAnswer(day: day, question: question)
        }
        await afterWrite(repo: repo, day: day, gen: gen)
    }

    /// A numeric item's value (≥ 1). Zero is written as a "no" answer because the store records
    /// every numeric row as the behaviour having occurred.
    func setNumeric(_ value: Double, question: String, day: String, repo: Repository) async {
        guard value >= 1 else { await setAnswer(false, question: question, day: day, repo: repo); return }
        let gen = daySeq
        writeSeq += 1
        numeric[question] = value
        answers[question] = true
        await repo.saveJournalNumeric(day: day, question: question, value: value)
        await afterWrite(repo: repo, day: day, gen: gen)
    }

    /// Write "no" for every listed question that has no answer on `day`. This is what gives the
    /// effects engine its control nights: an unanswered day is neither yes nor no.
    func markRestNo(questions: [String], day: String, repo: Repository) async {
        let pending = questions.filter { answers[$0] == nil }
        guard !pending.isEmpty else { return }
        let gen = daySeq
        writeSeq += 1
        // Every optimistic mark before the first suspension: a chip tap mid-loop would otherwise
        // paint the rest of these over the newer day's rows.
        for q in pending { answers[q] = false }
        for q in pending {
            await repo.saveJournalAnswer(day: day, question: q, answeredYes: false)
        }
        await afterWrite(repo: repo, day: day, gen: gen)
    }

    /// Re-read the day the write targeted (only if the chips still show it), then the journal as a whole.
    private func afterWrite(repo: Repository, day: String, gen: Int) async {
        await readDay(repo: repo, day: day, gen: gen)
        await reloadJournal(repo: repo)
    }

    // MARK: Ranking

    private func rerank() {
        let ranked = EffectRanker.rank(behaviors: behaviours, controls: controls,
                                       outcomeByDay: outcomeByKey[outcome.key] ?? [:],
                                       outcome: outcome.label)
        effects = ranked.sorted { a, b in
            let sa = a.confidence == .solid, sb = b.confidence == .solid
            if sa != sb { return sa }
            let da = abs(a.effect.delta), db = abs(b.effect.delta)
            if da != db { return da > db }
            return a.behavior < b.behavior
        }
    }

    /// Dose per day for each dosed behaviour: a "no" night is dose 0, a plain "yes" is dose 1, and a
    /// numeric log overrides with its value. Only behaviours with at least one dosed night and one
    /// paired next-morning outcome get a card.
    private func redose() {
        var out: [JournalDose] = []
        for behavior in DosedBehavior.allCases {
            var doses: [String: Int] = [:]
            for (q, days) in controls where Self.matches(behavior, q) { for d in days { doses[d] = 0 } }
            for (q, days) in behaviours where Self.matches(behavior, q) { for d in days { doses[d] = max(doses[d] ?? 0, 1) } }
            for (q, series) in numericSeries where Self.matches(behavior, q) {
                for (d, v) in series { doses[d] = max(0, Int(v.rounded())) }
            }
            guard doses.values.contains(where: { $0 > 0 }) else { continue }
            let outcomeKey = behavior == .alcohol ? "recovery" : "hrv"
            guard let response = DoseResponseEngine.estimate(behavior: behavior, doseByDay: doses,
                                                             outcomeByDay: outcomeByKey[outcomeKey] ?? [:]),
                  response.nUser >= 1 else { continue }
            out.append(JournalDose(behavior: behavior, response: response))
        }
        doses = out
    }

    // MARK: Shaping

    private static func dailyOutcome(key: String, day d: DailyMetric) -> Double? {
        switch key {
        case "hrv": return d.avgHrv
        case "rhr": return d.restingHr.map(Double.init)
        case "recovery": return d.recovery
        default: return nil
        }
    }

    /// Whether a journal question is the dosed behaviour (its yes-nights back-fill dose 1).
    static func matches(_ behavior: DosedBehavior, _ question: String) -> Bool {
        let q = question.lowercased()
        switch behavior {
        case .alcohol: return q.contains("alcohol") || q.contains("drink")
        case .caffeine: return q.contains("caffeine") || q.contains("coffee")
        }
    }
}
#endif
