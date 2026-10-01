import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `TodaySignals.build`: the gating of Today's Signals card. Every fixture is judged through the same
/// `TodaySnapshot` the hero tiles draw, so a baseline named here is the one the tile prints. Day keys
/// are literals and the carry rule is UTC key math, so nothing depends on the machine's clock.
final class TodaySignalsTests: BaselineEngineTestCase {

    private let today = "2026-02-18"

    /// A row with the illness-watch columns too (`Fixtures.metric` stops at the hero columns).
    private func row(_ day: String, hrv: Double? = nil, rhr: Int? = nil, strain: Double? = nil,
                     skin: Double? = nil, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil, strain: strain,
                    exerciseCount: nil, skinTempDevC: skin, respRateBpm: resp)
    }

    /// `n` identical nights ending `endingDaysAgo` days before `today`, oldest first.
    private func nights(_ n: Int, endingDaysAgo: Int, hrv: Double, rhr: Int? = nil, strain: Double? = nil,
                        skin: Double? = nil) -> [DailyMetric] {
        (0..<n).reversed().map { row(Fixtures.key(today, minus: endingDaysAgo + $0), hrv: hrv, rhr: rhr,
                                     strain: strain, skin: skin) }
    }

    private func build(_ days: [DailyMetric], nights: [SleepNight] = [], journal: [JournalEntry] = []) -> TodaySignals {
        let snap = TodaySnapshot.build(days: days, nights: nights, todayKey: today)
        return TodaySignals.build(days: days, nights: nights, snapshot: snap, journal: journal)
    }

    private func sleepNight(_ day: String, minutes: Double) -> SleepNight {
        SleepNightBuilder.build(fromDaily: Fixtures.metric(day, sleepMin: minutes))!
    }

    /// Twenty settled nights (60 ms / 50 bpm) then three nights at 30 ms / 62 bpm. Both deviations are
    /// past the hard-outlier gate (5× the floor spread), so the baseline the tiles print stays exactly
    /// 60 ± 5 and 50 ± 2 and the card's numbers are exact.
    private var raisedFixture: [DailyMetric] {
        nights(20, endingDaysAgo: 3, hrv: 60, rhr: 50) + nights(3, endingDaysAgo: 0, hrv: 30, rhr: 62)
    }

    // MARK: Illness watch

    func testRaised_twoSignalsTogether_oneCalmSentence() throws {
        let signals = build(raisedFixture)
        XCTAssertEqual(signals.signals.map(\.kind), [.illnessWatch])
        let s = try XCTUnwrap(signals.signals.first)
        XCTAssertEqual(s.pill, "Watch")
        XCTAssertEqual(s.sentence,
                       "Resting HR is 12 bpm above your baseline for the third night and HRV is suppressed "
                       + "(50% below your baseline). This pattern often precedes feeling unwell; consider an easier day.")
        XCTAssertTrue(s.method.contains("not a diagnosis"))
        for word in ["illness", "infection", "fever", "sick", "Strain", "Recovery", "Coach", "WHOOP"] {
            XCTAssertFalse(s.sentence.contains(word), "\(word) leaked into the signals sentence")
        }
    }

    func testQuiet_normalNights_sayNothing() {
        let days = nights(20, endingDaysAgo: 3, hrv: 60, rhr: 50) + nights(3, endingDaysAgo: 0, hrv: 58, rhr: 51)
        XCTAssertTrue(build(days).isEmpty)
    }

    func testOneSignalAlone_isNotEnough() {
        // Resting HR up on its own (HRV steady): NOOP's corroboration gate needs two signals.
        let days = nights(20, endingDaysAgo: 3, hrv: 60, rhr: 50) + nights(3, endingDaysAgo: 0, hrv: 60, rhr: 62)
        XCTAssertTrue(build(days).isEmpty)
    }

    func testConfounder_alcoholLogged_explainsItAway() throws {
        let journal = [JournalEntry(day: today, question: "Did you drink any alcohol?", answeredYes: true, notes: nil)]
        let s = try XCTUnwrap(build(raisedFixture, journal: journal).signals.first)
        XCTAssertEqual(s.kind, .illnessWatch)
        XCTAssertTrue(s.sentence.hasSuffix("You logged alcohol that night, which usually explains it."), s.sentence)
        XCTAssertFalse(s.sentence.contains("precedes"))
    }

    func testConfounder_mustBeRecent() throws {
        // The same answer five days ago explains nothing about the last two nights.
        let journal = [JournalEntry(day: Fixtures.key(today, minus: 5), question: "Did you drink any alcohol?",
                                    answeredYes: true, notes: nil)]
        let s = try XCTUnwrap(build(raisedFixture, journal: journal).signals.first)
        XCTAssertTrue(s.sentence.contains("precedes"))
    }

    func testAlreadyUnwell_isHidden() {
        let journal = [JournalEntry(day: today, question: "Did you feel sick or ill?", answeredYes: true, notes: nil)]
        XCTAssertTrue(build(raisedFixture, journal: journal).isEmpty, "the person already knows; nothing to warn about")
    }

    func testCalibrating_isHidden() {
        // Thirteen HRV nights: readiness is calibrating, so the card stays away however loud the signals.
        let days = nights(10, endingDaysAgo: 3, hrv: 60, rhr: 50) + nights(3, endingDaysAgo: 0, hrv: 30, rhr: 62)
        if case .calibrating = TodaySnapshot.build(days: days, nights: [], todayKey: today).readiness {} else {
            XCTFail("fixture must be calibrating")
        }
        XCTAssertTrue(build(days).isEmpty)
    }

    func testStaleReadings_areHidden() {
        // Newest night ten days old (past Baselines.vitalCarryDays): the tiles blank it and so does the card.
        let days = nights(20, endingDaysAgo: 13, hrv: 60, rhr: 50) + nights(3, endingDaysAgo: 10, hrv: 30, rhr: 62)
        XCTAssertTrue(build(days).isEmpty)
    }

    func testSkinTemperatureDeviation_joinsTheSentence() throws {
        // A stored DEVIATION of +0.9 °C is three personal spreads (0.3 °C each): it fires alongside the others,
        // in the engine's fixed order (resting HR, skin temperature, HRV, breathing rate).
        let days = nights(20, endingDaysAgo: 3, hrv: 60, rhr: 50, skin: 0.0)
            + nights(3, endingDaysAgo: 0, hrv: 30, rhr: 62, skin: 0.9)
        let s = try XCTUnwrap(build(days).signals.first)
        XCTAssertTrue(s.sentence.hasPrefix("Resting HR is 12 bpm above your baseline for the third night, "
                                           + "skin temperature is up and HRV is suppressed"), s.sentence)
    }

    func testAbsoluteSkinTemperature_isJudgedAgainstItsOwnFold() throws {
        // A WHOOP CSV night stores an ABSOLUTE wrist °C. A flat 33.0 °C history is not "+33 °C over baseline":
        // it must not add a skin clause.
        let days = nights(20, endingDaysAgo: 3, hrv: 60, rhr: 50, skin: 33.0)
            + nights(3, endingDaysAgo: 0, hrv: 30, rhr: 62, skin: 33.0)
        let s = try XCTUnwrap(build(days).signals.first)
        XCTAssertFalse(s.sentence.contains("skin temperature"), s.sentence)
    }

    func testElevatedRun_countsConsecutiveNightsAboveOneSigma() {
        let state = Baselines.foldHistory(Array(repeating: 50.0, count: 20), cfg: Baselines.restingHRCfg)
        let days = nights(20, endingDaysAgo: 3, hrv: 60, rhr: 50) + nights(3, endingDaysAgo: 0, hrv: 60, rhr: 55)
        XCTAssertEqual(TodaySignals.elevatedRun(days, state: state), 3)
        XCTAssertEqual(TodaySignals.elevatedRun(nights(5, endingDaysAgo: 0, hrv: 60, rhr: 50), state: state), 0)
    }

    // MARK: Overreaching

    /// Twenty-one days at 20 then seven at 60: acute 60 against chronic 30, a 2.0 ratio.
    func testEffortSpike_namesTheRatio() throws {
        let days = nights(21, endingDaysAgo: 7, hrv: 60, strain: 20) + nights(7, endingDaysAgo: 0, hrv: 60, strain: 60)
        let signals = build(days)
        XCTAssertEqual(signals.signals.map(\.kind), [.overreaching])
        let s = try XCTUnwrap(signals.signals.first)
        XCTAssertEqual(s.pill, "Effort load")
        XCTAssertTrue(s.sentence.hasPrefix("Effort this week is 2.0× your four-week average."), s.sentence)
        XCTAssertFalse(s.sentence.contains("Strain"))
    }

    func testBuildingWithNoVariety_isAlsoFlagged() throws {
        // Acute 30 over chronic 22.5 (1.33, the building band) with a near-flat week (monotony ≫ 2).
        let week: [Double] = [30, 30, 30, 30, 30, 31, 29]
        let days = nights(21, endingDaysAgo: 7, hrv: 60, strain: 20)
            + week.enumerated().map { i, v in row(Fixtures.key(today, minus: 6 - i), hrv: 60, strain: v) }
        let s = try XCTUnwrap(build(days).signals.first)
        XCTAssertEqual(s.kind, .overreaching)
        XCTAssertTrue(s.sentence.hasPrefix("Effort this week is 1.3× your four-week average with little day-to-day variety."),
                      s.sentence)
    }

    func testSteadyLoad_saysNothing() {
        let days = nights(28, endingDaysAgo: 0, hrv: 60, strain: 40)
        XCTAssertTrue(build(days).isEmpty)
    }

    func testOldImport_doesNotReadAsThisWeek() {
        // The spike ended ten days ago: nothing is anchored on this week, so nothing is said.
        let days = nights(21, endingDaysAgo: 17, hrv: 60, strain: 20) + nights(7, endingDaysAgo: 10, hrv: 60, strain: 60)
        XCTAssertTrue(build(days).isEmpty)
    }

    // MARK: Short nights

    private var readinessDays: [DailyMetric] { nights(15, endingDaysAgo: 0, hrv: 60) }

    func testThreeShortNightsInARow() throws {
        // Ten nights of 7h 30m, then three of 6h 00m: each at least an hour under the average before it.
        var list = (0..<3).map { sleepNight(Fixtures.key(today, minus: $0), minutes: 360) }
        list += (3..<13).map { sleepNight(Fixtures.key(today, minus: $0), minutes: 450) }
        let signals = build(readinessDays, nights: list)
        XCTAssertEqual(signals.signals.map(\.kind), [.shortNights])
        let s = try XCTUnwrap(signals.signals.first)
        XCTAssertEqual(s.pill, "Short nights")
        XCTAssertEqual(s.sentence,
                       "Three nights in a row at least an hour under your 30-night average: 6h 00m a night against 7h 30m. "
                       + "Short sleep lowers HRV for most people; an earlier night tonight pays some of it back.")
    }

    func testTwoShortNights_areNotEnough() {
        var list = (0..<2).map { sleepNight(Fixtures.key(today, minus: $0), minutes: 360) }
        list += (2..<13).map { sleepNight(Fixtures.key(today, minus: $0), minutes: 450) }
        XCTAssertTrue(build(readinessDays, nights: list).isEmpty)
    }

    func testMissedNight_breaksTheRun() {
        // Short on today, yesterday and three days ago; no night two days ago. Not "in a row".
        var list = [0, 1, 3].map { sleepNight(Fixtures.key(today, minus: $0), minutes: 360) }
        list += (4..<14).map { sleepNight(Fixtures.key(today, minus: $0), minutes: 450) }
        XCTAssertTrue(build(readinessDays, nights: list).isEmpty)
    }

    func testShortNights_needAnAverageToBeShortAgainst() {
        // Three nights only: no 30-night average exists before any of them.
        let list = (0..<3).map { sleepNight(Fixtures.key(today, minus: $0), minutes: 300) }
        XCTAssertTrue(build(readinessDays, nights: list).isEmpty)
    }

    // MARK: Words

    func testWords() {
        XCTAssertEqual(TodaySignals.ordinal(2), "second")
        XCTAssertEqual(TodaySignals.ordinal(3), "third")
        XCTAssertEqual(TodaySignals.ordinal(9), "9th")
        XCTAssertEqual(TodaySignals.countWord(3), "Three")
        XCTAssertEqual(TodaySignals.countWord(12), "12")
        XCTAssertEqual(TodaySignals.joined(["a"]), "a")
        XCTAssertEqual(TodaySignals.joined(["a", "b"]), "a and b")
        XCTAssertEqual(TodaySignals.joined(["a", "b", "c"]), "a, b and c")
    }
}
