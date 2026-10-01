import XCTest
import WhoopStore
@testable import Baseline

/// `WorkoutsModel` and `WorkoutsFormat`: sessions group into calendar weeks newest first, the week label
/// names this week and last week and spans the rest, zone minutes are duration-weighted from the row's
/// percentages, and the formatting helpers print what the rows show. Instants are local wall-clock
/// (`Fixtures.local`) and the calendar is pinned to a Monday week start, so the grouping holds on any
/// machine and under any region setting.
final class WorkoutsModelTests: XCTestCase {

    /// Monday-first week in the machine's zone, the zone `Fixtures.local` builds instants in.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Calendar.current.timeZone
        c.firstWeekday = 2
        return c
    }

    /// Wednesday 18 Feb 2026 at noon.
    private let now = Fixtures.local(2026, 2, 18, hour: 12)

    private func row(_ start: Date, minutes: Int, sport: String = "Running", source: String = "whoop",
                     durationS: Double? = nil, strain: Double? = nil, avgHr: Int? = nil,
                     kcal: Double? = nil, zonesJSON: String? = nil) -> WorkoutRow {
        let s = Int(start.timeIntervalSince1970)
        return WorkoutRow(startTs: s, endTs: s + minutes * 60, sport: sport, source: source,
                          durationS: durationS, energyKcal: kcal, avgHr: avgHr, maxHr: nil, strain: strain,
                          distanceM: nil, zonesJSON: zonesJSON, notes: nil, steps: nil)
    }

    // MARK: Grouping

    func testWeeks_groupOnTheCalendarWeekNewestFirst() throws {
        let mon16 = Fixtures.local(2026, 2, 16, hour: 7)       // this week
        let wed18 = Fixtures.local(2026, 2, 18, hour: 18)
        let sun15 = Fixtures.local(2026, 2, 15, hour: 9)       // last week (Monday start)
        let sun1 = Fixtures.local(2026, 2, 1, hour: 9)         // week of 26 Jan – 1 Feb
        let rows = [row(mon16, minutes: 40), row(sun1, minutes: 30), row(wed18, minutes: 20), row(sun15, minutes: 50)]

        let weeks = WorkoutsModel.weeks(rows, calendar: calendar)
        XCTAssertEqual(weeks.count, 3)

        XCTAssertEqual(weeks[0].start, calendar.startOfDay(for: mon16))
        XCTAssertEqual(weeks[0].items.map(\.start), [wed18, mon16], "sessions newest first inside a week")
        XCTAssertEqual(weeks[0].count, 2)
        XCTAssertEqual(weeks[0].totalDurationS, 60 * 60, accuracy: 1e-9)

        XCTAssertEqual(weeks[1].start, calendar.startOfDay(for: Fixtures.local(2026, 2, 9, hour: 0)))
        XCTAssertEqual(weeks[1].items.map(\.start), [sun15], "a Sunday belongs to the week that began on Monday")
        XCTAssertEqual(weeks[1].end, weeks[0].start, "weeks tile: one week's end is the next week's start")

        XCTAssertEqual(weeks[2].start, calendar.startOfDay(for: Fixtures.local(2026, 1, 26, hour: 0)))
        XCTAssertEqual(weeks[2].items.map(\.start), [sun1])
    }

    func testWeeks_emptyInput() {
        XCTAssertTrue(WorkoutsModel.weeks([], calendar: calendar).isEmpty)
    }

    func testItemIdentity_andDurationFallback() {
        let start = Fixtures.local(2026, 2, 16, hour: 7)
        let stored = WorkoutItem(row: row(start, minutes: 40, durationS: 1_800))
        XCTAssertEqual(stored.durationS, 1_800, "the stored duration wins over the window")
        let window = WorkoutItem(row: row(start, minutes: 40))
        XCTAssertEqual(window.durationS, 2_400, "no stored duration: the window")
        let apple = WorkoutItem(row: row(start, minutes: 40, source: "apple"))
        XCTAssertNotEqual(stored.id, apple.id, "the same start from two sources stays two rows")
        let cycling = WorkoutItem(row: row(start, minutes: 40, sport: "Cycling"))
        XCTAssertNotEqual(window.id, cycling.id, "two sports from one instant stay two rows")
        let longer = WorkoutItem(row: row(start, minutes: 55))
        XCTAssertNotEqual(window.id, longer.id, "the same start, source and sport with another end is another session")
        XCTAssertEqual(window.id, WorkoutItem(row: row(start, minutes: 40)).id, "identity is a pure function of the row")
    }

    // MARK: Week label

    func testWeekLabel_thisWeekLastWeekAndSpans() {
        let posix = Locale(identifier: "en_US_POSIX")
        let thisWeek = calendar.startOfDay(for: Fixtures.local(2026, 2, 16, hour: 0))
        let lastWeek = calendar.startOfDay(for: Fixtures.local(2026, 2, 9, hour: 0))
        let twoBack = calendar.startOfDay(for: Fixtures.local(2026, 2, 2, hour: 0))
        let crossMonth = calendar.startOfDay(for: Fixtures.local(2026, 1, 26, hour: 0))
        let lastYear = calendar.startOfDay(for: Fixtures.local(2025, 12, 29, hour: 0))

        XCTAssertEqual(WorkoutsModel.weekLabel(start: thisWeek, now: now, calendar: calendar, locale: posix), "This week")
        XCTAssertEqual(WorkoutsModel.weekLabel(start: lastWeek, now: now, calendar: calendar, locale: posix), "Last week")
        XCTAssertEqual(WorkoutsModel.weekLabel(start: twoBack, now: now, calendar: calendar, locale: posix), "Feb 2 – Feb 8")
        XCTAssertEqual(WorkoutsModel.weekLabel(start: crossMonth, now: now, calendar: calendar, locale: posix), "Jan 26 – Feb 1")
        XCTAssertEqual(WorkoutsModel.weekLabel(start: lastYear, now: now, calendar: calendar, locale: posix),
                       "Dec 29 – Jan 4, 2025", "a week that began last year carries its year")
    }

    // MARK: Zones

    func testZoneMinutes_durationWeightedFromPercents() throws {
        let start = Fixtures.local(2026, 2, 16, hour: 7)
        let json = #"{"z1":10,"z2":20,"z3":40,"z4":20,"z5":10}"#
        let minutes = try XCTUnwrap(WorkoutsModel.zoneMinutes(row(start, minutes: 60, durationS: 3_000, zonesJSON: json)))
        XCTAssertEqual(minutes.count, 5)
        XCTAssertEqual(minutes, [5, 10, 20, 10, 5].map { Double($0) }, "50 stored minutes split by the percentages")

        XCTAssertNil(WorkoutsModel.zoneMinutes(row(start, minutes: 60)), "no zone payload")
        XCTAssertNil(WorkoutsModel.zoneMinutes(row(start, minutes: 0, zonesJSON: json)), "no duration to weight")
    }

    func testZoneBasis_followsTheProfilesPrecedence() {
        XCTAssertEqual(WorkoutsModel.zoneBasis(hasCustomZones: true, hrMaxOverride: 190, hrMax: 190),
                       .customBoundaries, "custom boundaries win over any max HR")
        XCTAssertEqual(WorkoutsModel.zoneBasis(hasCustomZones: false, hrMaxOverride: 190, hrMax: 190),
                       .manualMaxHR(190))
        XCTAssertEqual(WorkoutsModel.zoneBasis(hasCustomZones: false, hrMaxOverride: 0, hrMax: 181),
                       .ageEstimate(maxHR: 181), "no override: the age estimate, with the number it produced")
    }

    func testZoneCaption_namesTheSplitsOriginAndCallsDerivedApproximate() {
        XCTAssertEqual(WorkoutsModel.zoneCaption(.imported), "Zone split imported with this session.")

        let age = WorkoutsModel.zoneCaption(.derived(.ageEstimate(maxHR: 181)))
        XCTAssertTrue(age.hasPrefix("Approximate:"), "a derived split is labelled approximate")
        XCTAssertTrue(age.contains("your age") && age.contains("181 bpm"), "names the estimate it rests on")

        let manual = WorkoutsModel.zoneCaption(.derived(.manualMaxHR(190)))
        XCTAssertTrue(manual.hasPrefix("Approximate:"))
        XCTAssertTrue(manual.contains("190 bpm"))
        XCTAssertFalse(manual.contains("your age"), "a max HR set by hand is not age-derived")

        let custom = WorkoutsModel.zoneCaption(.derived(.customBoundaries))
        XCTAssertTrue(custom.hasPrefix("Approximate:"))
        XCTAssertTrue(custom.contains("custom zone boundaries"))
        XCTAssertFalse(custom.contains("bpm"), "custom boundaries are not described by one max HR")

        for origin in [WorkoutZoneOrigin.imported, .derived(.ageEstimate(maxHR: 181))] {
            let text = WorkoutsModel.zoneCaption(origin)
            XCTAssertFalse(text.contains("WHOOP") || text.contains("Strain") || text.contains("Recovery"),
                           "no WHOOP vocabulary in the caption: \(text)")
        }
    }

    // MARK: List window

    func testWorkoutsWindow_statesItsSpanAndEmptyCopy() {
        XCTAssertEqual(WorkoutsWindow.lastYear.days, 365)
        XCTAssertNil(WorkoutsWindow.all.days, "the whole store is the engine's default read")

        XCTAssertEqual(WorkoutsWindow.lastYear.caption, "Last 12 months")
        XCTAssertEqual(WorkoutsWindow.all.caption, "Every stored workout")

        XCTAssertEqual(WorkoutsWindow.lastYear.emptyTitle, "No workouts in the last year",
                       "a bounded read that finds nothing must not claim the store is empty")
        XCTAssertEqual(WorkoutsWindow.all.emptyTitle, "No workouts yet")
        XCTAssertTrue(WorkoutsWindow.lastYear.emptyMessage.contains("Older sessions"),
                      "the bounded empty state points at the path to older sessions")
        XCTAssertFalse(WorkoutsWindow.all.emptyMessage.contains("Older sessions"),
                       "after widening there is nowhere further to look")
    }

    // MARK: Formatting

    func testEffortText_matchesTodayRendering() {
        XCTAssertEqual(BaselineReadouts.effortText(nil), "–")
        XCTAssertEqual(BaselineReadouts.effortText(0), "0")
        XCTAssertEqual(BaselineReadouts.effortText(37.4), "37")
        XCTAssertEqual(BaselineReadouts.effortText(37.5), "38")
        XCTAssertEqual(BaselineReadouts.effortUnit, "/ 100")
    }

    func testWeekSummary_andZoneLegend() {
        XCTAssertEqual(WorkoutsFormat.weekSummary(count: 1, totalDurationS: 45 * 60), "1 workout · 45 min")
        XCTAssertEqual(WorkoutsFormat.weekSummary(count: 3, totalDurationS: 160 * 60), "3 workouts · 2h 40m")
        XCTAssertEqual(WorkoutsFormat.weekSummary(count: 2, totalDurationS: 0), "2 workouts")

        XCTAssertEqual(WorkoutsFormat.zoneLegend(zone: 3, minutes: 18, total: 50), "Z3 36% · 18 min")
        XCTAssertEqual(WorkoutsFormat.zoneLegend(zone: 5, minutes: 0.2, total: 50), "Z5 0%")
        XCTAssertEqual(WorkoutsFormat.zoneLegend(zone: 1, minutes: 0, total: 0), "Z1")
    }
}
