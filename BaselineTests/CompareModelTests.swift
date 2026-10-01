import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// The Compare model: pairing the strap's nights with an import's by day key, the mean / absolute
/// differences and Pearson r over the pairs, the sentence, the window, and the empty paths. Day keys
/// are literals; nothing depends on the machine's zone or clock.
final class CompareModelTests: XCTestCase {

    private let today = "2026-02-18"
    private func key(_ daysAgo: Int) -> String { Fixtures.key(today, minus: daysAgo) }

    private func stats(nights: Int, mean: Double, abs: Double? = nil, r: Double?) -> CompareStats {
        CompareStats(nights: nights, meanDifference: mean, meanAbsoluteDifference: abs ?? Swift.abs(mean), r: r)
    }

    // MARK: Pairing

    func testPairsInnerJoinByDayAndSortOldestFirst() {
        let strap = [Fixtures.metric(key(1), hrv: 62), Fixtures.metric(key(3), hrv: 58), Fixtures.metric(key(5), hrv: 70)]
        let export = [Fixtures.metric(key(3), hrv: 55), Fixtures.metric(key(1), hrv: 60), Fixtures.metric(key(2), hrv: 90)]
        let pairs = CompareModel.pairs(baseline: strap, other: export, metric: .hrv)
        XCTAssertEqual(pairs.map(\.id), [key(3), key(1)])
        XCTAssertEqual(pairs.map(\.baseline), [58, 62])
        XCTAssertEqual(pairs.map(\.other), [55, 60])
        XCTAssertEqual(pairs.map(\.difference), [3, 2], "Baseline minus the import")
    }

    func testPairsNeedAValidValueOnBothSides() {
        let strap = [Fixtures.metric(key(1), hrv: 62, rhr: 52, sleepMin: 0, efficiency: 0.91),
                     Fixtures.metric(key(2), hrv: nil, rhr: 50, sleepMin: 420, efficiency: 1.4),
                     Fixtures.metric(key(3), hrv: 9_999, rhr: 49, sleepMin: 400, efficiency: 0.88)]
        let export = [Fixtures.metric(key(1), hrv: 60, rhr: nil, sleepMin: 430, efficiency: 0.90),
                      Fixtures.metric(key(2), hrv: 61, rhr: 51, sleepMin: 425, efficiency: 0.93),
                      Fixtures.metric(key(3), hrv: 59, rhr: 48, sleepMin: 395, efficiency: 0.86)]
        XCTAssertEqual(CompareModel.pairs(baseline: strap, other: export, metric: .hrv).map(\.id), [key(1)],
                       "nil and out-of-range HRV never pair")
        XCTAssertEqual(CompareModel.pairs(baseline: strap, other: export, metric: .restingHr).map(\.id), [key(3), key(2)])
        XCTAssertEqual(CompareModel.pairs(baseline: strap, other: export, metric: .sleep).map(\.id), [key(3), key(2)],
                       "a zero-minute night is not a night")
        let eff = CompareModel.pairs(baseline: strap, other: export, metric: .efficiency)
        XCTAssertEqual(eff.map(\.id), [key(3), key(1)], "an efficiency above 1 is not a fraction")
        XCTAssertEqual(eff.count, 2)
        XCTAssertEqual(eff[0].baseline, 88, accuracy: 1e-9, "stored fractions pair as percentages")
        XCTAssertEqual(eff[1].baseline, 91, accuracy: 1e-9)
        XCTAssertEqual(eff[1].other, 90, accuracy: 1e-9)
    }

    func testPairsEmptyWhenEitherSideIsEmpty() {
        let strap = [Fixtures.metric(key(1), hrv: 62)]
        XCTAssertTrue(CompareModel.pairs(baseline: strap, other: [], metric: .hrv).isEmpty)
        XCTAssertTrue(CompareModel.pairs(baseline: [], other: strap, metric: .hrv).isEmpty)
    }

    // MARK: Stats

    func testStatsMeanDifferenceAbsoluteDifferenceAndPearsonR() throws {
        // Baseline 51…55 against the classic (1,2),(2,4),(3,5),(4,4),(5,5) shape shifted by 50: r = 6/√60.
        let strap = (1...5).map { Fixtures.metric(key(6 - $0), hrv: 50 + Double($0)) }
        let export = zip(1...5, [2.0, 4, 5, 4, 5]).map { Fixtures.metric(key(6 - $0), hrv: 50 + $1) }
        let pairs = CompareModel.pairs(baseline: strap, other: export, metric: .hrv)
        let s = try XCTUnwrap(CompareModel.stats(pairs))
        XCTAssertEqual(s.nights, 5)
        XCTAssertEqual(s.meanDifference, -1, accuracy: 1e-9)
        XCTAssertEqual(s.meanAbsoluteDifference, 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.r), 6 / 60.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.r), try XCTUnwrap(CorrelationEngine.pearson(pairs.map { ($0.baseline, $0.other) })).r,
                       "r is the engine's Pearson over the same pairs")
    }

    func testStatsAbsoluteDifferenceIsNotTheAbsoluteOfTheMean() throws {
        let strap = [Fixtures.metric(key(1), rhr: 50), Fixtures.metric(key(2), rhr: 50)]
        let export = [Fixtures.metric(key(1), rhr: 53), Fixtures.metric(key(2), rhr: 47)]
        let s = try XCTUnwrap(CompareModel.stats(CompareModel.pairs(baseline: strap, other: export, metric: .restingHr)))
        XCTAssertEqual(s.meanDifference, 0, accuracy: 1e-9)
        XCTAssertEqual(s.meanAbsoluteDifference, 3, accuracy: 1e-9)
    }

    func testStatsRIsNilUnderThreeNightsOrWithoutVariance() throws {
        let two = (1...2).map { ComparePair(id: key($0), date: Date(), baseline: Double(60 + $0), other: Double(58 + $0)) }
        XCTAssertNil(try XCTUnwrap(CompareModel.stats(two)).r)
        let flat = (1...5).map { ComparePair(id: key($0), date: Date(), baseline: 60, other: Double(55 + $0)) }
        XCTAssertNil(try XCTUnwrap(CompareModel.stats(flat)).r, "a side that never varies has no r")
        XCTAssertNil(CompareModel.stats([]))
    }

    // MARK: Sentence

    func testSentenceAboveAndMovingTogether() {
        XCTAssertEqual(
            CompareModel.sentence(metric: .hrv, stats: stats(nights: 41, mean: 4.2, r: 0.86), source: .whoopExport),
            "On 41 nights Baseline\u{2019}s HRV ran 4 ms above WHOOP\u{2019}s and moved with it (r = 0.86).")
    }

    func testSentenceBelowLooselyFollowingAndNotTracking() {
        XCTAssertEqual(
            CompareModel.sentence(metric: .restingHr, stats: stats(nights: 12, mean: -2.6, r: 0.52), source: .whoopExport),
            "On 12 nights Baseline\u{2019}s resting HR ran 3 bpm below WHOOP\u{2019}s and loosely followed it (r = 0.52).")
        XCTAssertEqual(
            CompareModel.sentence(metric: .efficiency, stats: stats(nights: 8, mean: 1.3, r: 0.12), source: .whoopExport),
            "On 8 nights Baseline\u{2019}s sleep efficiency ran 1 point above WHOOP\u{2019}s but did not track it (r = 0.12).")
        XCTAssertEqual(
            CompareModel.sentence(metric: .hrv, stats: stats(nights: 20, mean: 6, r: -0.3), source: .whoopExport),
            "On 20 nights Baseline\u{2019}s HRV ran 6 ms above WHOOP\u{2019}s but did not track it (r = \u{2212}0.30).")
    }

    func testSentenceSleepDurationsMatchedAndSingular() {
        XCTAssertEqual(
            CompareModel.sentence(metric: .sleep, stats: stats(nights: 30, mean: 22, r: 0.9), source: .whoopExport),
            "On 30 nights Baseline\u{2019}s sleep ran 22 min longer than WHOOP\u{2019}s and moved with it (r = 0.90).")
        XCTAssertEqual(
            CompareModel.sentence(metric: .sleep, stats: stats(nights: 30, mean: -65, r: nil), source: .appleHealth),
            "On 30 nights Baseline\u{2019}s sleep ran 1h 05m shorter than Apple Health\u{2019}s.")
        XCTAssertEqual(
            CompareModel.sentence(metric: .hrv, stats: stats(nights: 1, mean: 0.3, r: nil), source: .whoopExport),
            "On 1 night Baseline\u{2019}s HRV matched WHOOP\u{2019}s on average.")
    }

    // MARK: Formatting

    func testDifferenceAndValueText() {
        XCTAssertEqual(CompareMetric.hrv.differenceText(3.6), "+4 ms")
        XCTAssertEqual(CompareMetric.restingHr.differenceText(-2), "\u{2212}2 bpm")
        XCTAssertEqual(CompareMetric.hrv.differenceText(0.2), "0 ms")
        XCTAssertEqual(CompareMetric.sleep.differenceText(-65), "\u{2212}1h 05m")
        XCTAssertEqual(CompareMetric.sleep.differenceText(22), "+22 min")
        XCTAssertEqual(CompareMetric.efficiency.differenceText(2.4), "+2 pts")
        XCTAssertEqual(CompareMetric.sleep.valueText(432), "7h 12m")
        XCTAssertEqual(CompareMetric.efficiency.valueText(91.4), "91")
        XCTAssertEqual(CompareModel.rText(nil), "\u{2014}")
        XCTAssertEqual(CompareModel.rText(-0.123), "\u{2212}0.12")
    }

    // MARK: Window and axis

    func testWindowKeepsTodayAndTheDaysBeforeIt() {
        let pairs = (0...40).reversed().map { ComparePair(id: key($0), date: Date(), baseline: 60, other: 60) }
        XCTAssertEqual(CompareModel.window(pairs, range: .month, todayKey: today).count, 30)
        XCTAssertEqual(CompareModel.window(pairs, range: .month, todayKey: today).first?.id, key(29))
        XCTAssertEqual(CompareModel.window(pairs, range: .quarter, todayKey: today).count, 41)
        XCTAssertEqual(CompareModel.window(pairs, range: .all, todayKey: today).count, 41)
    }

    func testYDomainPadsAndSnapsOutwardAndSleepIsDrawnInHours() {
        XCTAssertEqual(CompareModel.yDomain([52, 58, 61], step: 5), 50...65)
        XCTAssertEqual(CompareModel.yDomain([], step: 5), 0...5)
        XCTAssertEqual(CompareMetric.sleep.chartValue(450), 7.5)
        XCTAssertEqual(CompareMetric.hrv.chartValue(62), 62)
    }

    // MARK: Sources and snapshot

    func testSplitAndAvailableSourcesNeedAnOverlappingNight() {
        let strap = SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 62), source: .noopComputed)
        let exportSame = SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 60), source: .whoopImport)
        let exportOther = SourcedDailyMetric(metric: Fixtures.metric(key(9), hrv: 60), source: .whoopImport)
        let appleSleep = SourcedDailyMetric(metric: Fixtures.metric(key(1), sleepMin: 400), source: .appleHealth)
        let cache = SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 1), source: .localCache)

        XCTAssertEqual(CompareModel.availableSources(CompareModel.split([strap])), [])
        XCTAssertEqual(CompareModel.availableSources(CompareModel.split([strap, exportOther])), [],
                       "an import with no shared night offers nothing")
        XCTAssertEqual(CompareModel.availableSources(CompareModel.split([strap, exportSame])), [.whoopExport])
        XCTAssertEqual(CompareModel.availableSources(CompareModel.split([strap, appleSleep])), [],
                       "the strap night carries no sleep, so Apple's sleep has nothing to pair with")
        let strapSleep = SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 62, sleepMin: 410), source: .noopComputed)
        XCTAssertEqual(CompareModel.availableSources(CompareModel.split([strapSleep, exportSame, appleSleep, cache])),
                       [.whoopExport, .appleHealth])
        XCTAssertTrue(CompareModel.split([cache]).baseline.isEmpty, "preview rows are not a source")
    }

    func testSnapshotFallsBackToTheFirstAvailableSourceAndDropsFutureDays() throws {
        let rows = [
            SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 62), source: .noopComputed),
            SourcedDailyMetric(metric: Fixtures.metric(key(0), hrv: 64), source: .noopComputed),
            SourcedDailyMetric(metric: Fixtures.metric(Fixtures.key(today, minus: -1), hrv: 70), source: .noopComputed),
            SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 60), source: .appleHealth),
            SourcedDailyMetric(metric: Fixtures.metric(key(0), hrv: 61), source: .appleHealth),
            SourcedDailyMetric(metric: Fixtures.metric(Fixtures.key(today, minus: -1), hrv: 71), source: .appleHealth),
        ]
        let s = CompareSnapshot.build(rows: rows, source: .whoopExport, metric: .hrv, range: .month, todayKey: today)
        XCTAssertEqual(s.source, .appleHealth, "no WHOOP export: the only overlapping source is compared")
        XCTAssertEqual(s.availableSources, [.appleHealth])
        XCTAssertEqual(s.pairs.map(\.id), [key(1), key(0)], "a row dated after today is not a night yet")
        XCTAssertEqual(try XCTUnwrap(s.stats).nights, 2)
        XCTAssertNil(try XCTUnwrap(s.stats).r)
        XCTAssertEqual(s.sentence, "On 2 nights Baseline\u{2019}s HRV ran 3 ms above Apple Health\u{2019}s.")
        XCTAssertEqual(s.recentNights.map(\.id), [key(0), key(1)], "newest first")
        XCTAssertEqual(s.windowed.count, 2)
        XCTAssertNotNil(s.source.caveat(for: .hrv), "Apple's HRV is a different statistic")
        XCTAssertNil(CompareSource.whoopExport.caveat(for: .hrv))
    }

    func testSnapshotEmptyWhenNothingOverlaps() {
        let rows = [SourcedDailyMetric(metric: Fixtures.metric(key(1), hrv: 62), source: .noopComputed)]
        let s = CompareSnapshot.build(rows: rows, source: .whoopExport, metric: .hrv, range: .all, todayKey: today)
        XCTAssertTrue(s.availableSources.isEmpty)
        XCTAssertTrue(s.pairs.isEmpty)
        XCTAssertNil(s.stats)
        XCTAssertNil(s.sentence)
        XCTAssertTrue(s.recentNights.isEmpty)
    }

    func testRecentNightsAreTheLastThirty() {
        let strap = (0...45).map { Fixtures.metric(key($0), rhr: 50) }
        let export = (0...45).map { Fixtures.metric(key($0), rhr: 52) }
        let rows = strap.map { SourcedDailyMetric(metric: $0, source: .noopComputed) }
            + export.map { SourcedDailyMetric(metric: $0, source: .whoopImport) }
        let s = CompareSnapshot.build(rows: rows, source: .whoopExport, metric: .restingHr, range: .month, todayKey: today)
        XCTAssertEqual(s.pairs.count, 46)
        XCTAssertEqual(s.recentNights.count, 30)
        XCTAssertEqual(s.recentNights.first?.id, key(0))
        XCTAssertEqual(s.recentNights.last?.id, key(29))
        XCTAssertEqual(s.windowed.count, 30)
    }
}
