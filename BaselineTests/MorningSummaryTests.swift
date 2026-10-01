import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `MorningSummaryText.build`: the notification body is assembled from the same `TodaySnapshot` the Today
/// tab draws, so every number here is checked against what that tab would print for the same fixtures.
/// Day keys are literals and the carry rule is UTC key math, so nothing depends on the machine's clock.
final class MorningSummaryTests: BaselineEngineTestCase {

    private let today = "2026-02-18"

    /// `n` nights of the same values ending the day before `today`, oldest first.
    private func priorNights(_ n: Int, hrv: Double, rhr: Int? = nil) -> [DailyMetric] {
        (1...n).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: hrv, rhr: rhr) }
    }

    private func night(_ day: String, sleepMin: Double) -> SleepNight {
        SleepNightBuilder.build(fromDaily: Fixtures.metric(day, sleepMin: sleepMin))!
    }

    // MARK: Body

    func testFullMorning_insideBand() throws {
        // Ten flat nights: HRV band 60 ± 1.253·5, resting HR band 50 ± 1.253·2. The three nights BEFORE
        // last night (420 / 450 / 420) average 430 min, so last night (402) reads −28 min against it.
        let days = priorNights(10, hrv: 60, rhr: 50) + [Fixtures.metric(today, hrv: 61, rhr: 52)]
        let nights = [night(today, sleepMin: 402),
                      night(Fixtures.key(today, minus: 1), sleepMin: 420),
                      night(Fixtures.key(today, minus: 2), sleepMin: 450),
                      night(Fixtures.key(today, minus: 3), sleepMin: 420)]
        let summary = try XCTUnwrap(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: nights, todayKey: today)))

        XCTAssertEqual(summary.day, today)
        XCTAssertEqual(summary.body,
                       "HRV 61 ms · inside your band · Resting HR 52 bpm · inside your band · Slept 6h 42m · \u{2212}28 min vs average")
        XCTAssertNil(summary.subtitle, "readiness needs 14 nights; ten must not fabricate a tier")
    }

    func testBandWords_matchTodaysHeroTile() throws {
        let days = priorNights(10, hrv: 60, rhr: 50) + [Fixtures.metric(today, hrv: 90, rhr: 44)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let summary = try XCTUnwrap(MorningSummaryText.build(snap))

        XCTAssertEqual(snap.hrv?.band, .above)
        XCTAssertEqual(snap.restingHr?.band, .below)
        XCTAssertEqual(summary.body, "HRV 90 ms · above your band · Resting HR 44 bpm · below your band")
        // The phrase is the one funnel for the words; the body must carry it verbatim.
        XCTAssertTrue(summary.body.contains(BaselineBand.above.positionPhrase!))
        XCTAssertTrue(summary.body.contains(BaselineBand.below.positionPhrase!))
    }

    func testCalibrating_namesTheCount() throws {
        // Two prior nights < Baselines.minNightsSeed (4): the value shows with the honest count, no band.
        let days = priorNights(2, hrv: 60) + [Fixtures.metric(today, hrv: 61)]
        let summary = try XCTUnwrap(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: [], todayKey: today)))
        XCTAssertEqual(summary.body, "HRV 61 ms · baseline after \(Baselines.minNightsSeed) nights, 2 so far")
        XCTAssertNil(summary.subtitle)
    }

    /// The tier never appears without its noun: "Readiness · On baseline", the pill's label after the one
    /// word Today, Trends and the banner share.
    func testReadinessTier_becomesSubtitle() throws {
        let days = priorNights(14, hrv: 60) + [Fixtures.metric(today, hrv: 60)]
        let summary = try XCTUnwrap(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: [], todayKey: today)))
        XCTAssertEqual(summary.subtitle, ReadinessTier.normal.baselineNotificationSubtitle)
        XCTAssertEqual(summary.subtitle, "Readiness · " + ReadinessTier.normal.baselineLabel)
        XCTAssertEqual(summary.subtitle, "Readiness · On baseline")
    }

    /// Today's sentence under the pill speaks of the week (the seven-night tier), so it cannot read as
    /// contradicting a one-night "+35 ms · above your band" on the HRV tile beneath it.
    func testWeekSentences_nameTheWeekAndNeverWhoopVocabulary() {
        for tier in [ReadinessTier.primed, .normal, .suppressed] {
            let sentence = tier.baselineWeekSentence
            XCTAssertTrue(sentence.hasPrefix("Your week is "), sentence)
            for word in ["Strain", "Recovery", "Coach", "WHOOP"] {
                XCTAssertFalse(sentence.contains(word), "\(word) leaked into the readiness sentence")
            }
        }
        XCTAssertTrue(ReadinessTier.normal.baselineWeekSentence.hasPrefix("Your week is on baseline."))
        XCTAssertTrue(ReadinessTier.primed.baselineWeekSentence.hasPrefix("Your week is primed."))
        XCTAssertTrue(ReadinessTier.suppressed.baselineWeekSentence.hasPrefix("Your week is below your normal range."))
    }

    func testSleepWithoutAverage_hasNoDelta() throws {
        let days = priorNights(10, hrv: 60) + [Fixtures.metric(today, hrv: 61)]
        let nights = [night(today, sleepMin: 50)]
        let summary = try XCTUnwrap(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: nights, todayKey: today)))
        XCTAssertEqual(summary.body, "HRV 61 ms · inside your band · Slept 50 min")
    }

    // MARK: Day gate

    func testDay_isTheNewestFactsMorning() throws {
        // HRV last landed yesterday, sleep this morning: the summary is dated today, so the notifier
        // (which requires `day == todayKey`) posts; HRV is still carried, as the Today hero carries it.
        let yesterday = Fixtures.key(today, minus: 1)
        let days = priorNights(10, hrv: 60) + [Fixtures.metric(yesterday, hrv: 61)]
        let withSleep = try XCTUnwrap(MorningSummaryText.build(
            TodaySnapshot.build(days: days, nights: [night(today, sleepMin: 400)], todayKey: today)))
        XCTAssertEqual(withSleep.day, today)
        XCTAssertTrue(withSleep.body.hasPrefix("HRV 61 ms"))

        let hrvOnly = try XCTUnwrap(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: [], todayKey: today)))
        XCTAssertEqual(hrvOnly.day, yesterday, "nothing is dated today, so the notifier must stay quiet")
    }

    func testStaleReading_isLeftOut() throws {
        // Newest HRV night is 10 days old, past Baselines.vitalCarryDays (7): the tile blanks it and so
        // does the summary. With only sleep today the body is sleep alone.
        let days = (10...19).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 60) }
        let snap = TodaySnapshot.build(days: days, nights: [night(today, sleepMin: 431)], todayKey: today)
        XCTAssertTrue(try XCTUnwrap(snap.hrv).isStale)
        let summary = try XCTUnwrap(MorningSummaryText.build(snap))
        XCTAssertEqual(summary.day, today)
        XCTAssertEqual(summary.body, "Slept 7h 11m")
        XCTAssertNil(summary.subtitle, "a stale night must not present a tier")
    }

    func testNothingFresh_isNil() {
        let days = (10...19).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: 60) }
        XCTAssertNil(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: [], todayKey: today)))
        XCTAssertNil(MorningSummaryText.build(TodaySnapshot.build(days: [], nights: [], todayKey: today)))
    }

    // MARK: Formatting

    /// The banner's "Slept …" is `BaselineReadouts.durationText`, the spelling Today, Sleep, Trends and
    /// Progress print, so a tap from the notification lands on the same number spelled the same way.
    func testSleepTotal_isTheSharedDurationSpelling() throws {
        let days = priorNights(10, hrv: 60) + [Fixtures.metric(today, hrv: 61)]
        for minutes in [402.0, 480.0, 59.4] {
            let nights = [night(today, sleepMin: minutes)]
            let summary = try XCTUnwrap(MorningSummaryText.build(TodaySnapshot.build(days: days, nights: nights, todayKey: today)))
            XCTAssertTrue(summary.body.hasSuffix("Slept " + BaselineReadouts.durationText(minutes: minutes)), summary.body)
        }
    }
}
