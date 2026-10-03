import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// Home's metrics-layer states, pure: the Readiness SCORE card's state (`TodayReadinessScore.build`:
/// the stored score, the 4-night calibration count, a carried score with its "Woke …" stamp, the HRV
/// carry cap, and nothing fresh), the week phrase the HRV tile appends, the Steps card's "no source"
/// state, and the cache entry's new fields. The activity cards' lines are pinned in `TodayActivityTests`.
final class TodayReadinessScoreTests: BaselineEngineTestCase {

    private let today = "2026-02-18"
    private let forbidden = ["strain", "recovery", "coach"]

    private func key(_ back: Int) -> String { Fixtures.key(today, minus: back) }

    /// Ten calm, scored nights before `today`.
    private func priorNights(_ n: Int = 10, recovery: Double? = 60) -> [DailyMetric] {
        (1...n).reversed().map { Fixtures.metric(key($0), hrv: 60, rhr: 50, recovery: recovery) }
    }

    // MARK: Readiness score state

    func testScoredMorning_readsTheStoredScoreUnstamped() throws {
        let days = priorNights() + [Fixtures.metric(today, hrv: 72, rhr: 55, recovery: 71)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        guard case .score(let r, let stamp) = TodayReadinessScore.build(for: today, days: days, readiness: snap.readiness) else {
            return XCTFail("expected a score")
        }
        XCTAssertEqual(r.day, today)
        XCTAssertEqual(r.score, 71)
        XCTAssertEqual(r.tone, .good)
        XCTAssertNil(stamp, "this morning's own score wears no date")
        let context = ReadinessCard.context(r, wokeStamp: stamp)
        XCTAssertTrue(context.hasPrefix("Lifted by heart rate variability"), context)
        for word in forbidden { XCTAssertFalse(context.lowercased().contains(word), context) }
    }

    /// The snapshot resolves the score once (Home's card, the morning summary and the widgets read that
    /// one), and `summaryLine` is its one-line spelling for a banner or a glance.
    func testSnapshot_resolvesTheScoreOnceAndSpellsTheSummaryLine() throws {
        let days = priorNights() + [Fixtures.metric(today, hrv: 72, rhr: 55, recovery: 71)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        guard case .score(let r, let stamp) = snap.readinessScore else { return XCTFail("expected a score") }
        XCTAssertEqual(r.score, 71)
        XCTAssertEqual(r.tone, .good)
        XCTAssertNil(stamp)
        XCTAssertEqual(snap.readinessScore.summaryLine, "Readiness 71 · Good")
        // A carried score keeps its number in the line; the stamp is Home's business.
        guard case .score(let carried, let carriedStamp) = TodaySnapshot.build(days: priorNights(), nights: [], todayKey: today).readinessScore else {
            return XCTFail("expected a carried score")
        }
        XCTAssertEqual(carried.day, key(1))
        XCTAssertNotNil(carriedStamp)
        XCTAssertEqual(TodayReadinessScore.score(carried, wokeStamp: carriedStamp).summaryLine, "Readiness 60 · Fair")
        // Every other state says nothing under the noun.
        XCTAssertNil(TodayReadinessScore.calibrating(nights: 2).summaryLine)
        XCTAssertNil(TodayReadinessScore.stale(lastDay: today).summaryLine)
        XCTAssertNil(TodayReadinessScore.missing.summaryLine)
        let low = BaselineReadouts.ReadinessScore(day: today, score: 28, tone: .low, confidence: .solid, drivers: [], driversSentence: nil)
        XCTAssertEqual(TodayReadinessScore.score(low, wokeStamp: nil).summaryLine, "Readiness 28 · Low")
        for word in forbidden { XCTAssertFalse("Readiness 28 · Low".lowercased().contains(word)) }
    }

    func testUnsyncedMorning_carriesTheNewestScoreWithItsStamp() throws {
        // Past the seed gate, no row for today: yesterday's score is carried and dated.
        let days = priorNights()
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        guard case .score(let r, let stamp) = TodayReadinessScore.build(for: today, days: days, readiness: snap.readiness) else {
            return XCTFail("expected a carried score")
        }
        XCTAssertEqual(r.day, key(1))
        XCTAssertEqual(r.score, 60)
        let s = try XCTUnwrap(stamp)
        XCTAssertTrue(s.hasPrefix("Woke "), s)
        XCTAssertEqual(s, TodayFormat.wokeStamp(day: key(1), todayKey: today))
        XCTAssertTrue(ReadinessCard.context(r, wokeStamp: stamp).hasPrefix(s + " · "))
    }

    func testFirstNights_countTowardsTheSeed() {
        let days = [Fixtures.metric(key(1), hrv: 60, rhr: 50), Fixtures.metric(today, hrv: 61, rhr: 50)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        guard case .calibrating(let n) = TodayReadinessScore.build(for: today, days: days, readiness: snap.readiness) else {
            return XCTFail("expected calibrating")
        }
        XCTAssertEqual(n, 2)
        XCTAssertEqual(BaselineReadouts.readinessSeedNights, 4)
        // The caption under the "Calibrating" pill keeps the count; the pill itself stays one word.
        XCTAssertEqual(ReadinessCard.calibratingLine(nights: n), "Readiness after 4 nights · 2 so far")
    }

    func testStaleHrv_pausesTheScore() {
        // The newest night is older than the carry cap: the HRV tile is stale, and so is the score.
        let days = (10...17).reversed().map { Fixtures.metric(key($0), hrv: 60, rhr: 50, recovery: 60) }
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        guard case .stale(let last) = snap.readiness else { return XCTFail("fixture: HRV should be stale") }
        guard case .stale(let day) = TodayReadinessScore.build(for: today, days: days, readiness: snap.readiness) else {
            return XCTFail("expected stale")
        }
        XCTAssertEqual(day, last)
        XCTAssertEqual(day, key(10))
    }

    func testPastSeedWithNothingScored_isMissing() {
        // Nights with HRV but never a score (a source without one): past the seed, nothing to carry.
        let days = priorNights(recovery: nil)
        guard case .missing = TodayReadinessScore.build(for: today, days: days, readiness: .tier(.normal)) else {
            return XCTFail("expected missing")
        }
        XCTAssertNil(TodayReadinessScore.missing.score)
    }

    func testCarryStopsAtTheRingsCap() {
        // A score eight days old is not carried even when the HRV path is told it is fine.
        let days = [Fixtures.metric(key(8), hrv: 60, rhr: 50, recovery: 60)]
            + (1...7).reversed().map { Fixtures.metric(key($0), hrv: 60, rhr: 50) }
        guard case .missing = TodayReadinessScore.build(for: today, days: days, readiness: .tier(.normal)) else {
            return XCTFail("expected missing")
        }
    }

    func testContextWithoutDrivers_namesTheInputsAndTheSettlingBaseline() {
        let building = BaselineReadouts.ReadinessScore(day: today, score: 55, tone: .watch, confidence: .building,
                                                       drivers: [], driversSentence: nil)
        XCTAssertEqual(ReadinessCard.context(building), "From that night's HRV, resting HR and sleep · baseline still settling")
        let solid = BaselineReadouts.ReadinessScore(day: today, score: 55, tone: .watch, confidence: .solid,
                                                    drivers: [], driversSentence: nil)
        XCTAssertEqual(ReadinessCard.context(solid, wokeStamp: "Woke Mon 16 Feb"),
                       "Woke Mon 16 Feb · From that night's HRV, resting HR and sleep")
        // The least-settled score (an export's first mornings) says so instead of wearing the plainest caption.
        let calibrating = BaselineReadouts.ReadinessScore(day: today, score: 55, tone: .watch, confidence: .calibrating,
                                                          drivers: [], driversSentence: nil)
        XCTAssertEqual(ReadinessCard.context(calibrating), "From that night's HRV, resting HR and sleep · baseline not yet usable")
    }

    // MARK: The week phrase on the HRV tile

    func testWeekPhrase_isShortAndOnlyForATier() {
        XCTAssertEqual(TodayReadiness.tier(.primed).weekPhrase, "Week primed")
        XCTAssertEqual(TodayReadiness.tier(.normal).weekPhrase, "Week on baseline")
        XCTAssertEqual(TodayReadiness.tier(.suppressed).weekPhrase, "Week below your range")
        XCTAssertNil(TodayReadiness.calibrating(nights: 3).weekPhrase)
        XCTAssertNil(TodayReadiness.stale(lastDay: today).weekPhrase)
        for tier in [ReadinessTier.primed, .normal, .suppressed] {
            let phrase = TodayReadiness.tier(tier).weekPhrase ?? ""
            for word in forbidden { XCTAssertFalse(phrase.lowercased().contains(word), phrase) }
        }
    }

    // MARK: Steps card source state

    func testStepsCard_noSourceState_onlyWhenNothingEverCounted() {
        let none = BaselineReadouts.steps(for: today, readings: [])
        XCTAssertFalse(none.hasRecordedSource)
        let yesterdayOnly = BaselineReadouts.steps(for: today, readings: [(day: key(1), value: 4_200)])
        XCTAssertTrue(yesterdayOnly.hasRecordedSource, "a recorded day in the week shows the card with a stub for today")
        XCTAssertNil(yesterdayOnly.steps)
        let old = BaselineReadouts.steps(for: today, readings: [(day: key(20), value: 4_200)])
        XCTAssertTrue(old.hasRecordedSource, "a count inside the 30-day window is a source")
        let todayOnly = BaselineReadouts.steps(for: today, readings: [(day: today, value: 8_412)])
        XCTAssertTrue(todayOnly.hasRecordedSource)
    }

    // MARK: Cache entry

    @MainActor
    func testCacheEntry_keepsTheMetrics_andTodaysUpdatesTouchOnlyTheirField() {
        let days = priorNights() + [Fixtures.metric(today, hrv: 72, rhr: 55, recovery: 71)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let cache = HomeDayCache()
        let k = HomeDayCache.Key(dayKey: today, logicalKey: today, refreshSeq: 1, dataSource: "", horizon: 90)
        let steps = BaselineReadouts.steps(for: today, readings: [(day: today, value: 8_412)])
        let entry = HomeDayCache.Entry(snapshot: snap, signals: nil, signalsJournalSeq: 0, workouts: [], progressHeadline: nil,
                                       readiness: TodayReadinessScore.build(for: today, days: days, readiness: snap.readiness),
                                       steps: steps, calories: nil, stress: nil)
        cache.store(entry, for: k)
        let hit = cache.entry(for: k)
        XCTAssertEqual(hit?.readiness.score?.score, 71)
        XCTAssertEqual(hit?.steps?.steps, 8_412)
        XCTAssertNil(hit?.calories)
        XCTAssertNil(hit?.stress)

        cache.updateStress(nil, for: k)
        cache.updateCalories(nil, for: k)
        XCTAssertEqual(cache.entry(for: k)?.steps?.steps, 8_412, "the rest of the entry is untouched")
        XCTAssertEqual(cache.entry(for: k)?.readiness.score?.score, 71)
        cache.updateCalories(nil, for: HomeDayCache.Key(dayKey: "2000-01-01", logicalKey: "2000-01-01", refreshSeq: 1,
                                                        dataSource: "", horizon: 90))
        XCTAssertEqual(cache.count, 1, "an unknown key is a no-op")
        XCTAssertNil(cache.entry(for: HomeDayCache.Key(dayKey: today, logicalKey: today, refreshSeq: 1, dataSource: "",
                                                       horizon: 90, profileStamp: "true|true|female|40|60|165")),
                     "a profile edit is a new key: the day's resting calories are read again")

        let defaults = HomeDayCache.Entry(snapshot: snap, signals: nil, signalsJournalSeq: 0, workouts: [], progressHeadline: nil)
        guard case .missing = defaults.readiness else { return XCTFail("the entry's default readiness is .missing") }
        XCTAssertNil(defaults.steps)
    }
}
