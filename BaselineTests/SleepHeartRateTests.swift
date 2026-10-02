import XCTest
import WhoopStore
@testable import Baseline

/// `SleepHeartRateBuilder.trace`: the night's one-minute means clipped to onset → wake, their low /
/// average / high, coverage, the PPG-derived flag, downsampling, and the two sentences the card prints.
/// Times are local wall-clock instants in February 2026 (no DST edge).
final class SleepHeartRateTests: XCTestCase {

    private let bed = Fixtures.local(2026, 2, 17, hour: 23, minute: 0)
    private let wake = Fixtures.local(2026, 2, 18, hour: 7, minute: 0)

    private func night(onset: Date? = nil, wake: Date? = nil, source: SleepNight.Source = .session) -> SleepNight {
        SleepNight(dayKey: "2026-02-18", source: source,
                   onsetTs: onset.map { Int($0.timeIntervalSince1970) }, wakeTs: wake.map { Int($0.timeIntervalSince1970) },
                   asleepMin: 440, deepMin: 90, remMin: 100, lightMin: 250, awakeMin: 25, hasStageTotals: true,
                   efficiency: 0.95, restingHr: 52, avgHrv: 64, respRateBpm: nil, skinTempDevC: nil,
                   stagingSparse: false, segments: [])
    }

    /// One 60-second bucket per minute from `start` for `minutes`, `bpm` from the closure.
    private func buckets(from start: Date, minutes: Int, bpm: (Int) -> Double, conf: (Int) -> Double = { _ in 1 }) -> [HRBucket] {
        let t0 = Int(start.timeIntervalSince1970)
        return (0..<minutes).map { i in
            let v = bpm(i)
            return HRBucket(ts: t0 + i * 60, bpm: v, minBpm: v - 3, maxBpm: v + 3, conf: conf(i))
        }
    }

    func testTrace_clipsToTheNightAndReadsOneMinuteMeans() throws {
        // Buckets from an hour before bed to an hour after wake; inside the night 50 bpm except one
        // minute at 44 and one at 80. The hour either side is 120 bpm and must not count.
        let start = bed.addingTimeInterval(-3_600)
        let all = buckets(from: start, minutes: 60 + 8 * 60 + 60) { i in
            let m = i - 60
            if m < 0 || m >= 8 * 60 { return 120 }
            if m == 100 { return 44 }
            if m == 300 { return 80 }
            return 50
        }
        let t = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: all))
        XCTAssertEqual(t.points.count, 480, "every minute of the eight-hour night, nothing from outside it")
        XCTAssertEqual(t.lowBpm, 44)
        XCTAssertEqual(t.highBpm, 80)
        XCTAssertEqual(t.averageBpm, (478 * 50 + 44 + 80) / 480, accuracy: 1e-9)
        XCTAssertEqual(t.coveredMinutes, 480)
        XCTAssertEqual(t.spanMinutes, 480)
        XCTAssertEqual(t.coverage, 1, accuracy: 1e-9)
        XCTAssertFalse(t.partial)
        XCTAssertFalse(t.hasDerivedStretch)
        XCTAssertEqual(t.onset, bed)
        XCTAssertEqual(t.wake, wake)
        XCTAssertEqual(t.dayKey, "2026-02-18")
    }

    func testTrace_isNilWithoutTimesOrBuckets() {
        let some = buckets(from: bed, minutes: 30) { _ in 50 }
        XCTAssertNil(SleepHeartRateBuilder.trace(night: night(source: .dailyMetric), buckets: some), "a daily-row night has no times")
        XCTAssertNil(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: []))
        let outside = buckets(from: wake.addingTimeInterval(600), minutes: 30) { _ in 50 }
        XCTAssertNil(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: outside), "nothing inside the night")
        let zeros = buckets(from: bed, minutes: 30) { _ in 0 }
        XCTAssertNil(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: zeros), "empty buckets are not readings")
    }

    func testTrace_partialNightAndDerivedStretch() throws {
        // Only the first three hours recorded (37.5% of eight), the last hour of them PPG-derived.
        let some = buckets(from: bed, minutes: 180, bpm: { _ in 55 }, conf: { $0 >= 120 ? 0.7 : 1 })
        let t = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: some))
        XCTAssertEqual(t.coveredMinutes, 180)
        XCTAssertEqual(t.coverage, 0.375, accuracy: 1e-9)
        XCTAssertTrue(t.partial)
        XCTAssertTrue(t.hasDerivedStretch)
        XCTAssertEqual(t.points.filter { $0.conf < 1 }.count, 60)

        let caption = SleepHeartRateBuilder.caption(t)
        XCTAssertTrue(caption.contains("partial night: 3h 00m recorded"), caption)
        XCTAssertTrue(caption.contains("optical estimate"), caption)
        XCTAssertTrue(caption.hasPrefix("One-minute means"), caption)

        let summary = SleepHeartRateBuilder.summary(t)
        XCTAssertTrue(summary.hasPrefix("Heart rate while asleep: lowest 55, average 55, highest 55 bpm, from "), summary)
        XCTAssertTrue(summary.contains("recorded for 3h 00m of the night"), summary)
        XCTAssertTrue(summary.hasSuffix("."), summary)
    }

    func testTrace_downsamplesLongNightsButKeepsTheExtremes() throws {
        // A fourteen-hour span at one bucket a minute: 840 rows, more than `maxPoints` (720).
        let longWake = bed.addingTimeInterval(14 * 3_600)
        let all = buckets(from: bed, minutes: 14 * 60) { i in i == 500 ? 42 : 58 }
        let t = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: longWake), buckets: all))
        XCTAssertLessThanOrEqual(t.points.count, SleepHeartRate.maxPoints)
        XCTAssertEqual(t.lowBpm, 42, "the low is read before downsampling")
        XCTAssertEqual(t.coveredMinutes, 840)
        XCTAssertEqual(t.points.first?.id, Int(bed.timeIntervalSince1970))

        // A cap of 10 keeps the whole span in order.
        let few = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: longWake), buckets: all, maxPoints: 10))
        XCTAssertEqual(few.points.count, 10)
        XCTAssertEqual(few.points.map(\.id), few.points.map(\.id).sorted())
    }

    func testTrace_unsortedBucketsAreOrdered() throws {
        let some = buckets(from: bed, minutes: 20) { Double(50 + $0) }.reversed()
        let t = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: Array(some)))
        XCTAssertEqual(t.points.map(\.bpm), (0..<20).map { Double(50 + $0) })
    }

    func testCaption_defaultSaysWhatAPointIs() throws {
        let some = buckets(from: bed, minutes: 480) { _ in 50 }
        let t = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: some))
        XCTAssertEqual(SleepHeartRateBuilder.caption(t), "One-minute means while the strap was worn.")
        XCTAssertEqual(SleepHeartRate.partialCoverage, 0.75)
    }

    func testVocabulary_neverTheBannedWords() throws {
        let some = buckets(from: bed, minutes: 480) { _ in 50 }
        let t = try XCTUnwrap(SleepHeartRateBuilder.trace(night: night(onset: bed, wake: wake), buckets: some))
        for text in [SleepHeartRateBuilder.caption(t), SleepHeartRateBuilder.summary(t)] {
            for banned in ["Strain", "Recovery", "Coach"] {
                XCTAssertFalse(text.contains(banned), "\(banned) in \(text)")
            }
        }
    }
}
