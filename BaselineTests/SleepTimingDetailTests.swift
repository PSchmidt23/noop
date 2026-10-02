import XCTest
@testable import Baseline

/// `SleepTimingDetail`: the bedtime / wake detail's ranges, its noon-to-noon axis, the rows the chart
/// draws, the hero averages, the one context sentence and the chart's VoiceOver sentence. Nights are
/// local wall-clock instants in February 2026 (no DST edge).
final class SleepTimingDetailTests: XCTestCase {

    private typealias Window = BaselineReadouts.SleepWindow

    /// A session night going to bed on `day` February 2026 at `bedHour:bedMinute` (hours past 24 roll into
    /// the next morning), up at `wakeHour:wakeMinute` the next morning. Keyed by the morning it ends on.
    private func night(_ day: Int, bedHour: Int, bedMinute: Int = 0, wakeHour: Int = 7, wakeMinute: Int = 0) -> SleepNight {
        let bed = Fixtures.local(2026, 2, day, hour: bedHour, minute: bedMinute)
        let wake = Fixtures.local(2026, 2, day + 1, hour: wakeHour, minute: wakeMinute)
        return SleepNight(dayKey: Fixtures.dayKey(wake), source: .session,
                          onsetTs: Int(bed.timeIntervalSince1970), wakeTs: Int(wake.timeIntervalSince1970),
                          asleepMin: 440, deepMin: 90, remMin: 100, lightMin: 250, awakeMin: 25, hasStageTotals: true,
                          efficiency: 0.95, restingHr: 52, avgHrv: 64, respRateBpm: nil, skinTempDevC: nil,
                          stagingSparse: false, segments: [])
    }

    /// Seven nights at 23:00 → 07:00 (Feb 1–7), then seven at 23:30 → 07:00 (Feb 8–14); the window ends
    /// on the morning of Feb 15.
    private var fourteen: [SleepNight] {
        (1...7).map { night($0, bedHour: 23) } + (8...14).map { night($0, bedHour: 23, bedMinute: 30) }
    }
    private let endDay = Fixtures.dayKey(Fixtures.local(2026, 2, 15, hour: 12))

    func testRange_mapsOntoMetricRanges() {
        XCTAssertEqual(SleepTimingRange.allCases.map(\.label), ["7D", "4W", "1Y"], "no 1D: a day's bedtime is a cell, not a chart")
        XCTAssertEqual(SleepTimingRange.allCases.map(\.metricRange), [.week, .fourWeeks, .year])
        XCTAssertEqual(SleepTimingRange.week.subtitle, MetricRange.week.subtitle)
        XCTAssertEqual(SleepTimingRange.fourWeeks.shortLabel, "4W")
        XCTAssertEqual(SleepTimingRange.week.shortLabel, "7D", "the detail ranges keep their unit at every type size")
    }

    func testNoonAxis_roundTrips() {
        XCTAssertEqual(SleepTimingDetail.noonAxis(bedMinutes: 23 * 60), 660)
        XCTAssertEqual(SleepTimingDetail.noonAxis(bedMinutes: 30), 750, "12:30 AM sits after 11:00 PM on the axis")
        XCTAssertEqual(SleepTimingDetail.noonAxis(wakeMinutes: 7 * 60), 1_140)
        XCTAssertEqual(SleepTimingDetail.clockMinutes(noonAxis: 1_140), 7 * 60)
        XCTAssertEqual(SleepTimingDetail.clockMinutes(noonAxis: 660), 23 * 60)
    }

    func testBuild_week_rowsAveragesAndTarget() {
        let d = SleepTimingDetail.build(day: endDay, nights: fourteen, range: .week, window: .default)
        XCTAssertEqual(d.range, .week)
        XCTAssertEqual(d.rows.count, 7, "one row per night of the last 7 days")
        XCTAssertEqual(d.rows.map(\.id), d.rows.map(\.id).sorted(), "oldest first")
        for r in d.rows {
            XCTAssertEqual(try XCTUnwrap(r.bed), 11 * 60 + 30, accuracy: 1e-6, "23:30 is 690 minutes after noon")
            XCTAssertEqual(try XCTUnwrap(r.wake), 1_140, accuracy: 1e-6, "07:00 is 1140 on the noon axis")
            XCTAssertNil(r.bedLow, "a single night carries no envelope")
            XCTAssertEqual(r.n, 1)
        }
        XCTAssertEqual(d.nightCount, 7)
        XCTAssertEqual(d.averageBedText, BaselineReadouts.clockText(minutes: 23 * 60 + 30))
        XCTAssertEqual(d.averageWakeText, BaselineReadouts.clockText(minutes: 7 * 60))
        XCTAssertEqual(d.targetBand, 660...1_140, "23:00 → 07:00 on the noon axis")
        XCTAssertEqual(d.targetText, "\(BaselineReadouts.clockText(minutes: 23 * 60))\u{2013}\(BaselineReadouts.clockText(minutes: 7 * 60))")
        XCTAssertTrue(d.yDomain.contains(d.targetBand.lowerBound) && d.yDomain.contains(d.targetBand.upperBound))
        XCTAssertEqual(d.yDomain, 600...1_200, "an hour of air either side of the band and the lines")
        XCTAssertEqual(d.axisTicks(), [720, 900, 1_080], "whole hours every three inside the domain")
        XCTAssertFalse(d.bed.lastBucketPartial)
    }

    func testContextText_saysTheShiftOnce() {
        let d = SleepTimingDetail.build(day: endDay, nights: fourteen, range: .week, window: .default)
        let bed = BaselineReadouts.clockText(minutes: 23 * 60 + 30), wake = BaselineReadouts.clockText(minutes: 7 * 60)
        XCTAssertEqual(d.contextText,
                       "Bedtime averaged \(bed) and wake \(wake) over the last 7 days; bedtime 30 min later than and wake about the same as the 7 days before.")
        XCTAssertEqual(SleepTimingDetail.shiftWords(nil), nil)
        XCTAssertEqual(SleepTimingDetail.shiftWords(4), "about the same as")
        XCTAssertEqual(SleepTimingDetail.shiftWords(-75), "1h 15m earlier than")
        XCTAssertEqual(SleepTimingDetail.beforeWords(.fourWeeks), "the 4 weeks before")

        let none = SleepTimingDetail.build(day: endDay, nights: [], range: .fourWeeks, window: .default)
        XCTAssertEqual(none.contextText, "No nights with bed and wake times in the last 4 weeks.")
        XCTAssertEqual(none.averageBedText, "\u{2014}")
        XCTAssertTrue(none.rows.isEmpty)
        XCTAssertEqual(none.chartSummary, "Bedtime and wake, last 4 weeks: no nights recorded.")
    }

    func testChartSummary_namesBothLinesAndTheTarget() {
        let d = SleepTimingDetail.build(day: endDay, nights: fourteen, range: .week, window: .default)
        let bed = BaselineReadouts.clockText(minutes: 23 * 60 + 30), wake = BaselineReadouts.clockText(minutes: 7 * 60)
        XCTAssertEqual(d.chartSummary,
                       "Bedtime and wake, last 7 days: 7 nights, bedtime from \(bed) to \(bed), wake from \(wake) to \(wake); target window \(d.targetText).")
    }

    func testScrubText_dayAndWeek() throws {
        let week = SleepTimingDetail.build(day: endDay, nights: fourteen, range: .week, window: .default)
        let row = try XCTUnwrap(week.rows.last)
        let bed = BaselineReadouts.clockText(minutes: 23 * 60 + 30), wake = BaselineReadouts.clockText(minutes: 7 * 60)
        XCTAssertEqual(week.scrubText(row), "\(TrendsFormat.shortDate(row.date)) \u{00B7} bed \(bed) \u{00B7} wake \(wake)")

        let year = SleepTimingDetail.build(day: endDay, nights: fourteen, range: .year, window: .default)
        XCTAssertEqual(year.range.bucket, .week)
        let weekRow = try XCTUnwrap(year.rows.last)
        XCTAssertTrue(year.scrubText(weekRow).hasPrefix("Week of "), year.scrubText(weekRow))
        XCTAssertTrue(year.scrubText(weekRow).contains("over \(weekRow.n) night"), year.scrubText(weekRow))
        XCTAssertGreaterThan(year.rows.count, 1, "the fourteen nights span more than one ISO week")
        XCTAssertEqual(year.rows.map(\.n).reduce(0, +), 14)
        // A week that mixes 23:00 and 23:30 bedtimes carries both as its envelope.
        if let mixed = year.rows.first(where: { ($0.bedHigh ?? 0) - ($0.bedLow ?? 0) > 1 }) {
            XCTAssertEqual(mixed.bedLow ?? 0, 660, accuracy: 1e-6)
            XCTAssertEqual(mixed.bedHigh ?? 0, 690, accuracy: 1e-6)
        }
    }

    func testRows_keepANightWithOnlyOneLine() throws {
        // A wake point without a bed point still gets a row (both series share ids, so this is synthetic).
        let date = BaselineReadouts.localMidnight(of: "2026-02-10")!
        let wakeOnly = MetricSeries(key: .wake, range: .week, startKey: "2026-02-04", endKey: "2026-02-10",
                                    points: [RangePoint(id: "2026-02-10", date: date, value: 420, min: nil, max: nil, n: 1)],
                                    stats: .empty, lastBucketPartial: false)
        let noBed = MetricSeries(key: .bedtime, range: .week, startKey: "2026-02-04", endKey: "2026-02-10",
                                 points: [], stats: .empty, lastBucketPartial: false)
        let rows = SleepTimingDetail.rows(bed: noBed, wake: wakeOnly)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].bed)
        XCTAssertEqual(try XCTUnwrap(rows[0].wake), 1_140, accuracy: 1e-6)
    }

    func testVocabulary_neverTheBannedWords() {
        let d = SleepTimingDetail.build(day: endDay, nights: fourteen, range: .week, window: .default)
        for text in [d.contextText, d.chartSummary, d.targetText] {
            for banned in ["Strain", "Recovery", "Coach"] {
                XCTAssertFalse(text.contains(banned), "\(banned) in \(text)")
            }
        }
    }
}
