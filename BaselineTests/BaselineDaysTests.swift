import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `BaselineDays`: the strap-first precedence behind `BaselineReadouts.days(_:)` / `nights(_:)`. The
/// strap's own row wins field by field on an overlapping day, imports fill only the days and fields it
/// did not record, `.merged` is NOOP's table verbatim, `.importOnly` drops the strap, and the sleep-session
/// list follows the same rule per end-day. Plus the persisted setting's resolve / write-through.
final class BaselineDaysTests: XCTestCase {

    private func row(_ m: DailyMetric, _ s: DailyMetricSource) -> SourcedDailyMetric {
        SourcedDailyMetric(metric: m, source: s)
    }

    private let d1 = "2026-02-10"
    private let d2 = "2026-02-11"
    private let d3 = "2026-02-12"
    private let d4 = "2026-02-13"

    // MARK: Daily rows: strap first

    func testStrapFirst_strapWinsFieldByFieldOnAnOverlappingDay() throws {
        let strap = Fixtures.metric(d1, hrv: 55, rhr: nil, sleepMin: 420)
        let whoop = Fixtures.metric(d1, hrv: 60, rhr: 52, sleepMin: 400, recovery: 70)
        let merged = Repository.mergeDaily(imported: [whoop], computed: [strap])

        let out = BaselineDays.days(vitalRows: [row(whoop, .whoopImport), row(strap, .noopComputed)],
                                    merged: merged, mode: .strapFirst)
        XCTAssertEqual(out.count, 1)
        let d = try XCTUnwrap(out.first)
        XCTAssertEqual(d.avgHrv, 55, "the strap's HRV, not the export's")
        XCTAssertEqual(d.totalSleepMin, 420, "the strap's night, not the export's")
        XCTAssertEqual(d.restingHr, 52, "the export fills a field the strap did not record")
        XCTAssertEqual(d.recovery, 70, "the export fills a field the strap did not record")
        // NOOP's own merge let the export win; this is the contrast the setting exists for.
        XCTAssertEqual(merged.first?.avgHrv, 60)
    }

    func testStrapFirst_importsFillDaysTheStrapDidNotRecord_whoopBeforeApple() throws {
        let strap = Fixtures.metric(d2, hrv: 50)
        let whoopOnly = Fixtures.metric(d1, hrv: 61, rhr: 55)
        let appleOnly = Fixtures.metric(d4, hrv: 40, rhr: 58)
        let whoopD3 = Fixtures.metric(d3, hrv: 62)
        let appleD3 = Fixtures.metric(d3, hrv: 41, rhr: 57)
        let rows = [row(appleD3, .appleHealth), row(whoopD3, .whoopImport), row(strap, .noopComputed),
                    row(appleOnly, .appleHealth), row(whoopOnly, .whoopImport)]

        let out = BaselineDays.days(vitalRows: rows, merged: [], mode: .strapFirst)
        XCTAssertEqual(out.map(\.day), [d1, d2, d3, d4], "oldest → newest, every day present once")
        XCTAssertEqual(out[0].avgHrv, 61)
        XCTAssertEqual(out[1].avgHrv, 50)
        XCTAssertEqual(out[2].avgHrv, 62, "the WHOOP export outranks Apple Health on a day without the strap")
        XCTAssertEqual(out[2].restingHr, 57, "Apple Health fills what the export left nil")
        XCTAssertEqual(out[3].avgHrv, 40)
    }

    func testStrapFirst_sleepBlockMovesAsAGroup() throws {
        // The strap recorded a total but no stage minutes; the export has stages. The export's stages must
        // not sit beside the strap's total.
        let strap = Fixtures.metric(d1, sleepMin: 420)
        let whoop = Fixtures.metric(d1, sleepMin: 400, efficiency: 0.9, deep: 90, rem: 80, light: 230)
        let out = BaselineDays.days(vitalRows: [row(whoop, .whoopImport), row(strap, .noopComputed)],
                                    merged: [], mode: .strapFirst)
        let d = try XCTUnwrap(out.first)
        XCTAssertEqual(d.totalSleepMin, 420)
        XCTAssertNil(d.deepMin)
        XCTAssertNil(d.efficiency)

        // No strap sleep at all: the whole block comes from the export.
        let strapNoSleep = Fixtures.metric(d1, hrv: 55)
        let out2 = BaselineDays.days(vitalRows: [row(whoop, .whoopImport), row(strapNoSleep, .noopComputed)],
                                     merged: [], mode: .strapFirst)
        let e = try XCTUnwrap(out2.first)
        XCTAssertEqual(e.totalSleepMin, 400)
        XCTAssertEqual(e.deepMin, 90)
        XCTAssertEqual(e.avgHrv, 55)
    }

    func testStrapFirst_mergedTableSuppliesStepsAndDaysWithNoVitalRow() throws {
        let strap = Fixtures.metric(d1, hrv: 55)
        let whoop = Fixtures.metric(d1, hrv: 60)
        // NOOP's merged row for d1 (export won) plus activity-file steps, and a steps-only day d3.
        let mergedD1 = DailyMetric(day: d1, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                                   lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: 60, recovery: nil,
                                   strain: nil, exerciseCount: nil, steps: 8_000)
        let mergedD3 = DailyMetric(day: d3, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                                   lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                                   strain: nil, exerciseCount: nil, steps: 4_000)
        let out = BaselineDays.days(vitalRows: [row(whoop, .whoopImport), row(strap, .noopComputed)],
                                    merged: [mergedD1, mergedD3], mode: .strapFirst)
        XCTAssertEqual(out.map(\.day), [d1, d3])
        XCTAssertEqual(out[0].avgHrv, 55, "the merged row never overrides the strap")
        XCTAssertEqual(out[0].steps, 8_000, "but it supplies what no vital row carries")
        XCTAssertEqual(out[1].steps, 4_000)
    }

    func testStrapFirst_emptyVitalRowsIsTheMergedTable() {
        let merged = [Fixtures.metric(d1, hrv: 60), Fixtures.metric(d2, hrv: 61)]
        XCTAssertEqual(BaselineDays.days(vitalRows: [], merged: merged, mode: .strapFirst), merged)
    }

    func testStrapFirst_importWonMergedRowNeverLeaksStagesOrVitalsIntoTheStrapsNight() throws {
        // The strap banked a total only; the export staged the night and NOOP's merge let the export win,
        // so the merged row carries the export's stages, HRV and resting HR. Under strap-first the strap's
        // total stands alone (the sleep block moves whole) and its HRV is its own; the merged row may
        // supply only what no vital row carries (steps).
        let strap = Fixtures.metric(d1, hrv: 55, sleepMin: 420)
        let whoop = Fixtures.metric(d1, hrv: 60, rhr: 52, sleepMin: 400, efficiency: 0.9, deep: 90, rem: 80, light: 230)
        let mergedRow = Repository.mergeDaily(imported: [whoop], computed: [strap])
        let mergedWithSteps = Repository.mergeActivityFileSteps(into: mergedRow, [
            DailyMetric(day: d1, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                        disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil,
                        exerciseCount: nil, steps: 9_000)])
        XCTAssertEqual(mergedWithSteps.first?.deepMin, 90, "precondition: NOOP's row carries the export's stages")

        let out = BaselineDays.days(vitalRows: [row(whoop, .whoopImport), row(strap, .noopComputed)],
                                    merged: mergedWithSteps, mode: .strapFirst)
        let d = try XCTUnwrap(out.first)
        XCTAssertEqual(d.avgHrv, 55)
        XCTAssertEqual(d.totalSleepMin, 420)
        XCTAssertNil(d.deepMin, "the export's stages never sit beside the strap's total")
        XCTAssertNil(d.efficiency)
        XCTAssertEqual(d.restingHr, 52, "a field the strap has no value for is filled")
        XCTAssertEqual(d.steps, 9_000, "activity-file steps reach the row through the merged table")
    }

    // MARK: Funnel over a Repository

    @MainActor
    func testFunnel_beforeAnyRefreshIsRepoDays_andHonoursTheModeArgument() {
        // Previews and tests assign `days` directly; `vitalRows` stays empty until a real refresh.
        let repo = Repository(deviceId: "my-whoop")
        repo.days = [Fixtures.metric(d1, hrv: 60), Fixtures.metric(d2, hrv: 61)]
        XCTAssertEqual(BaselineReadouts.days(repo, mode: .strapFirst), repo.days)
        XCTAssertEqual(BaselineReadouts.days(repo, mode: .merged), repo.days)
        XCTAssertTrue(BaselineReadouts.days(repo, mode: .importOnly).isEmpty)
        XCTAssertEqual(BaselineReadouts.series(repo, key: "hrv", mode: .strapFirst).map(\.value), [60, 61])
        XCTAssertEqual(repo.baselineReloadID(dataSourceRaw: "importOnly"), "\(repo.refreshSeq)|importOnly")

        // The shims read the persisted mode; the test host is the app, so put back whatever was stored.
        let saved = UserDefaults.standard.string(forKey: BaselineDataSource.key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: BaselineDataSource.key) }
            else { UserDefaults.standard.removeObject(forKey: BaselineDataSource.key) }
        }
        UserDefaults.standard.set(BaselineDataSource.strapFirst.rawValue, forKey: BaselineDataSource.key)
        XCTAssertEqual(repo.baselineDays, repo.days)
        XCTAssertEqual(repo.baselineSeries(key: "hrv").map(\.day), [d1, d2])
        UserDefaults.standard.set(BaselineDataSource.importOnly.rawValue, forKey: BaselineDataSource.key)
        XCTAssertTrue(repo.baselineDays.isEmpty)
        XCTAssertNil(repo.baselineToday)
        XCTAssertTrue(repo.baselineWeek.isEmpty)
    }

    // MARK: Daily rows: merged and import only

    func testMerged_isRepoDaysVerbatim() {
        let strap = Fixtures.metric(d1, hrv: 55)
        let whoop = Fixtures.metric(d1, hrv: 60)
        let merged = Repository.mergeDaily(imported: [whoop], computed: [strap])
        let out = BaselineDays.days(vitalRows: [row(whoop, .whoopImport), row(strap, .noopComputed)],
                                    merged: merged, mode: .merged)
        XCTAssertEqual(out, merged)
        XCTAssertEqual(out.first?.avgHrv, 60, "NOOP's precedence: the import wins")
    }

    func testImportOnly_dropsTheStrapEntirely() throws {
        let strapOnly = Fixtures.metric(d1, hrv: 55)
        let strapD2 = Fixtures.metric(d2, hrv: 56, rhr: 50)
        let whoopD2 = Fixtures.metric(d2, hrv: 60)
        let appleD2 = Fixtures.metric(d2, hrv: 42, rhr: 58)
        let merged = Repository.mergeDaily(imported: [whoopD2], computed: [strapOnly, strapD2])
        let rows = [row(strapOnly, .noopComputed), row(strapD2, .noopComputed),
                    row(whoopD2, .whoopImport), row(appleD2, .appleHealth)]

        let out = BaselineDays.days(vitalRows: rows, merged: merged, mode: .importOnly)
        XCTAssertEqual(out.map(\.day), [d2], "a strap-only day is left out")
        let d = try XCTUnwrap(out.first)
        XCTAssertEqual(d.avgHrv, 60, "the export over Apple Health")
        XCTAssertEqual(d.restingHr, 58, "Apple Health fills; the strap's 50 is never consulted")
        XCTAssertTrue(BaselineDays.days(vitalRows: [], merged: merged, mode: .importOnly).isEmpty)
    }

    // MARK: fill

    func testFill_keepsAMeasuredZeroAndTheRawSpo2Pair() {
        let winner = DailyMetric(day: d1, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                                 lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                                 strain: 0, exerciseCount: nil, spo2Red: nil, spo2Ir: nil, avgSdnn: 48)
        let filler = DailyMetric(day: d1, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                                 lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                                 strain: 12, exerciseCount: nil, spo2Red: 100, spo2Ir: 200, avgSdnn: 70)
        let out = BaselineDays.fill(winner, from: filler)
        XCTAssertEqual(out.strain, 0, "a measured zero is a reading")
        XCTAssertEqual(out.spo2Red, 100)
        XCTAssertEqual(out.spo2Ir, 200)
        XCTAssertEqual(out.avgSdnn, 48)
    }

    // MARK: Sleep sessions

    private func session(_ start: Date, hours: Double, deviceId: String) -> CachedSleepSession {
        let s = Int(start.timeIntervalSince1970)
        return CachedSleepSession(startTs: s, endTs: s + Int(hours * 3_600), efficiency: nil, restingHr: nil,
                                  avgHrv: nil, stagesJSON: nil, deviceId: deviceId)
    }

    func testNights_strapFirst_strapDayKeepsItsSessions_importFillsTheOthers() {
        // Night A (ends Feb 18) recorded by both; a strap nap the same afternoon; night B (ends Feb 19)
        // only in the export.
        let strapNight = session(Fixtures.local(2026, 2, 17, hour: 23), hours: 8, deviceId: "my-whoop-noop")
        let strapNap = session(Fixtures.local(2026, 2, 18, hour: 14), hours: 1, deviceId: "my-whoop-noop")
        let importNightA = session(Fixtures.local(2026, 2, 17, hour: 23, minute: 10), hours: 7.5, deviceId: "my-whoop")
        let importNightB = session(Fixtures.local(2026, 2, 18, hour: 23), hours: 8, deviceId: "my-whoop")
        let merged = [importNightA, importNightB]   // NOOP: the import took night A

        let out = BaselineDays.nights(imported: [importNightB, importNightA], computed: [strapNap, strapNight],
                                      merged: merged, mode: .strapFirst)
        XCTAssertEqual(out.map(\.startTs), [strapNight.startTs, strapNap.startTs, importNightB.startTs],
                       "the strap's night and nap, then the export's night B, oldest first")
        XCTAssertEqual(out.map(\.deviceId), ["my-whoop-noop", "my-whoop-noop", "my-whoop"])

        XCTAssertEqual(BaselineDays.nights(imported: [importNightB, importNightA], computed: [strapNap, strapNight],
                                           merged: merged, mode: .merged).map(\.startTs),
                       merged.map(\.startTs), "merged: NOOP's list verbatim")
        XCTAssertEqual(BaselineDays.nights(imported: [importNightB, importNightA], computed: [strapNap, strapNight],
                                           merged: merged, mode: .importOnly).map(\.startTs),
                       [importNightA.startTs, importNightB.startTs], "import only, sorted by onset")
    }

    func testNights_endDayIsTheLocalDayTheSessionEndsOn() {
        let s = session(Fixtures.local(2026, 2, 17, hour: 23), hours: 8, deviceId: "x")
        XCTAssertEqual(BaselineDays.endDay(s), "2026-02-18")
    }

    // MARK: Series

    func testSeries_mapsDailyColumnsAndSkipsMissingDays() {
        let days = [Fixtures.metric(d1, hrv: 55, rhr: 50, recovery: 70), Fixtures.metric(d2, rhr: 52),
                    Fixtures.metric(d3, hrv: 58)]
        XCTAssertEqual(BaselineDays.series(key: "hrv", days: days).map(\.day), [d1, d3])
        XCTAssertEqual(BaselineDays.series(key: "hrv", days: days).map(\.value), [55, 58])
        XCTAssertEqual(BaselineDays.series(key: "rhr", days: days).map(\.value), [50, 52])
        XCTAssertEqual(BaselineDays.series(key: "recovery", days: days).map(\.value), [70])
        XCTAssertTrue(BaselineDays.series(key: "no-such-key", days: days).isEmpty)
    }

    // MARK: Setting

    func testDataSource_resolveDefaultsToStrapFirst() {
        XCTAssertEqual(BaselineDataSource.resolve(nil), .strapFirst)
        XCTAssertEqual(BaselineDataSource.resolve("garbage"), .strapFirst)
        XCTAssertEqual(BaselineDataSource.resolve("merged"), .merged)
        XCTAssertEqual(BaselineDataSource.resolve("importOnly"), .importOnly)
        XCTAssertEqual(BaselineDataSource.key, "baseline.dataSource")
        XCTAssertEqual(BaselineDataSource.reloadID(refreshSeq: 7, raw: "importOnly"), "7|importOnly")
        XCTAssertEqual(BaselineDataSource.reloadID(refreshSeq: 7, raw: ""), "7|strapFirst")
    }

    /// The sentence Import and Compare both print (`shownOnTabs`): it carries the picker's own label, and
    /// says "the default" exactly once, for the default mode only, so a person whose numbers moved can
    /// see why without being told it twice.
    func testDataSource_shownOnTabs_namesTheDefaultOnce() {
        for mode in BaselineDataSource.allCases {
            let sentence = mode.shownOnTabs
            XCTAssertTrue(sentence.contains("Data source: \(mode.label)"), sentence)
            XCTAssertEqual(sentence.components(separatedBy: "the default").count - 1,
                           mode == BaselineDataSource.default ? 1 : 0, sentence)
            XCTAssertTrue(sentence.hasSuffix("."), sentence)
        }
        XCTAssertTrue(BaselineDataSource.strapFirst.shownOnTabs.contains("your strap"))
        XCTAssertTrue(BaselineDataSource.merged.shownOnTabs.contains("the import"))
        XCTAssertTrue(BaselineDataSource.importOnly.shownOnTabs.contains("imports alone"))
    }

    @MainActor
    func testSetting_writesThroughAndReloads() throws {
        let suite = "BaselineDaysTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let setting = BaselineDataSourceSetting(defaults: defaults)
        XCTAssertEqual(setting.selection, .strapFirst, "nothing stored: the default")
        setting.selection = .importOnly
        XCTAssertEqual(defaults.string(forKey: BaselineDataSource.key), "importOnly")
        XCTAssertEqual(BaselineDataSource.current(defaults), .importOnly)

        defaults.set("merged", forKey: BaselineDataSource.key)
        setting.reload()
        XCTAssertEqual(setting.selection, .merged)
        XCTAssertEqual(BaselineDataSourceSetting.options, BaselineDataSource.allCases)
    }
}
