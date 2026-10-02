import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `HomeDayCache`: Home's per-day memo. A day built under one store state is served again for the same
/// key, a new `refreshSeq` drops everything (entries and the shared night list), the data-source setting
/// and the logical day are part of the key, a journal edit refreshes only today's signals, and the memo
/// never grows past its limit (oldest-touched goes first).
@MainActor
final class HomeDayCacheTests: XCTestCase {

    private let today = "2026-02-18"

    private func snapshot(_ day: String) -> TodaySnapshot {
        let days = (1...10).reversed().map { Fixtures.metric(Fixtures.key(day, minus: $0), hrv: 60) }
            + [Fixtures.metric(day, hrv: 61)]
        return TodaySnapshot.build(days: days, nights: [], todayKey: day)
    }

    private func key(_ day: String, logical: String? = nil, seq: Int = 1, source: String = "",
                     horizon: Int = 90) -> HomeDayCache.Key {
        HomeDayCache.Key(dayKey: day, logicalKey: logical ?? day, refreshSeq: seq, dataSource: source, horizon: horizon)
    }

    private func entry(_ day: String, signals: TodaySignals? = nil, journalSeq: Int = 0,
                       headline: String? = nil) -> HomeDayCache.Entry {
        HomeDayCache.Entry(snapshot: snapshot(day), signals: signals, signalsJournalSeq: journalSeq,
                           workouts: [], progressHeadline: headline)
    }

    // MARK: Hits and misses

    func testMissUntilStoredThenHitForTheSameKey() {
        let cache = HomeDayCache()
        let k = key(today)
        XCTAssertNil(cache.entry(for: k))
        cache.store(entry(today, headline: "HRV is up"), for: k)
        let hit = cache.entry(for: k)
        XCTAssertEqual(hit?.snapshot.todayKey, today)
        XCTAssertEqual(hit?.progressHeadline, "HRV is up")
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.refreshSeq, 1)
    }

    func testEveryPartOfTheKeyMatters() {
        let cache = HomeDayCache()
        cache.store(entry(today), for: key(today))
        XCTAssertNotNil(cache.entry(for: key(today)))
        XCTAssertNil(cache.entry(for: key(Fixtures.key(today, minus: 1))), "another day")
        XCTAssertNil(cache.entry(for: key(today, logical: Fixtures.key(today, minus: 1))), "the small-hours effort row")
        XCTAssertNil(cache.entry(for: key(today, source: "merged")), "Settings → Data changed")
        XCTAssertNil(cache.entry(for: key(today, horizon: 365)), "the readiness chevron's horizon changed")
    }

    func testSwipingBackAndForthServesBothDaysWithoutRebuilding() {
        let cache = HomeDayCache()
        let yesterday = Fixtures.key(today, minus: 1)
        cache.store(entry(today), for: key(today))
        cache.store(entry(yesterday), for: key(yesterday))
        for _ in 0..<3 {
            XCTAssertEqual(cache.entry(for: key(today))?.snapshot.todayKey, today)
            XCTAssertEqual(cache.entry(for: key(yesterday))?.snapshot.todayKey, yesterday)
        }
        XCTAssertEqual(cache.count, 2)
    }

    // MARK: Invalidation

    func testNewRefreshSeqDropsEveryEntryAndTheNights() {
        let cache = HomeDayCache()
        let yesterday = Fixtures.key(today, minus: 1)
        cache.storeNights([], refreshSeq: 1, dataSource: "")
        cache.store(entry(today), for: key(today, seq: 1))
        cache.store(entry(yesterday), for: key(yesterday, seq: 1))
        XCTAssertNotNil(cache.nights(refreshSeq: 1, dataSource: ""))

        cache.store(entry(today), for: key(today, seq: 2))

        XCTAssertEqual(cache.count, 1, "only the entry built under the new seq survives")
        XCTAssertNil(cache.entry(for: key(today, seq: 1)))
        XCTAssertNil(cache.entry(for: key(yesterday, seq: 1)))
        XCTAssertNotNil(cache.entry(for: key(today, seq: 2)))
        XCTAssertNil(cache.nights(refreshSeq: 1, dataSource: ""), "the night list was folded from the old table")
        XCTAssertEqual(cache.refreshSeq, 2)
    }

    func testStoringNightsUnderANewSeqAlsoInvalidates() {
        let cache = HomeDayCache()
        cache.store(entry(today), for: key(today, seq: 1))
        cache.storeNights([], refreshSeq: 2, dataSource: "")
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.nights(refreshSeq: 1, dataSource: ""))
        XCTAssertNotNil(cache.nights(refreshSeq: 2, dataSource: ""))
    }

    func testNightsAreKeyedByDataSourceToo() {
        let cache = HomeDayCache()
        cache.storeNights([], refreshSeq: 1, dataSource: "strapFirst")
        XCTAssertNotNil(cache.nights(refreshSeq: 1, dataSource: "strapFirst"))
        XCTAssertNil(cache.nights(refreshSeq: 1, dataSource: "importOnly"))
    }

    func testInvalidateEmptiesEverything() {
        let cache = HomeDayCache()
        cache.storeNights([], refreshSeq: 1, dataSource: "")
        cache.store(entry(today), for: key(today))
        cache.invalidate()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.refreshSeq)
        XCTAssertNil(cache.nights(refreshSeq: 1, dataSource: ""))
        XCTAssertNil(cache.entry(for: key(today)))
    }

    // MARK: Signals after a journal edit

    func testJournalEditRefreshesOnlyTodaysSignals() {
        let cache = HomeDayCache()
        let k = key(today)
        cache.store(entry(today, signals: nil, journalSeq: 0, headline: "steady"), for: k)
        XCTAssertEqual(cache.entry(for: k)?.signalsJournalSeq, 0)

        cache.updateSignals(.empty, journalSeq: 1, for: k)

        let hit = cache.entry(for: k)
        XCTAssertEqual(hit?.signalsJournalSeq, 1)
        XCTAssertEqual(hit?.signals, .empty)
        XCTAssertEqual(hit?.progressHeadline, "steady", "the rest of the entry is untouched")
        XCTAssertEqual(cache.count, 1)
    }

    func testUpdatingSignalsOfAnUnknownKeyIsANoOp() {
        let cache = HomeDayCache()
        cache.updateSignals(.empty, journalSeq: 1, for: key(today))
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.entry(for: key(today)))
    }

    // MARK: Bound

    func testEvictsTheOldestTouchedEntryPastTheLimit() {
        let cache = HomeDayCache(limit: 2)
        let d1 = Fixtures.key(today, minus: 1), d2 = Fixtures.key(today, minus: 2)
        cache.store(entry(today), for: key(today))
        cache.store(entry(d1), for: key(d1))
        _ = cache.entry(for: key(today))          // today is now the most recently touched
        cache.store(entry(d2), for: key(d2))      // evicts d1, the oldest-touched

        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.entry(for: key(today)))
        XCTAssertNil(cache.entry(for: key(d1)))
        XCTAssertNotNil(cache.entry(for: key(d2)))
    }

    func testReplacingAnEntryDoesNotGrowTheCache() {
        let cache = HomeDayCache(limit: 2)
        cache.store(entry(today, headline: "a"), for: key(today))
        cache.store(entry(today, headline: "b"), for: key(today))
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.entry(for: key(today))?.progressHeadline, "b")
    }
}
