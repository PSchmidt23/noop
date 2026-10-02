import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `BaselineSampleData`: the Release-safe sample dataset behind Settings › About › "Show sample data".
/// The generator is pure and is checked for determinism, counts, ranges and internal consistency; the
/// store round-trip runs against an in-memory `WhoopStore` through the same public upserts and the same
/// `deleteAllData` the app uses, then through NOOP's `Repository` read spine so the rows provably reach
/// `repo.baselineDays`, the nights, the workouts and the journal, and provably leave again.
final class SampleDataTests: XCTestCase {

    private var noon: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }

    // MARK: Generator

    func testGenerate_isDeterministicForOneAnchor() {
        let a = BaselineSampleData.generate(anchor: noon)
        let b = BaselineSampleData.generate(anchor: noon)
        XCTAssertEqual(a, b)
        // The anchor's clock does not matter, only its local day.
        let evening = Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: Date())!
        XCTAssertEqual(a, BaselineSampleData.generate(anchor: evening))
    }

    func testGenerate_countsAndDayKeys() {
        let data = BaselineSampleData.generate(anchor: noon)
        XCTAssertEqual(data.days.count, BaselineSampleData.nights)
        XCTAssertEqual(data.sleeps.count, BaselineSampleData.nights, "one night per day")
        XCTAssertEqual(data.days.last?.day, Fixtures.dayKey(noon), "the newest night is the anchor's day")
        XCTAssertEqual(data.days.first?.day, Fixtures.dayKey(noon, minus: BaselineSampleData.nights - 1))
        XCTAssertEqual(Set(data.days.map(\.day)).count, data.days.count, "no duplicate day")
        XCTAssertEqual(data.days.map(\.day), data.days.map(\.day).sorted(), "oldest → newest")

        XCTAssertGreaterThan(data.workouts.count, 10, "a few workouts a week")
        XCTAssertLessThan(data.workouts.count, BaselineSampleData.nights)
        XCTAssertEqual(data.journal.count, BaselineSampleData.journalNights * 3, "three answers for each of the last 30 days")
        let questions = Set(data.journal.map(\.question))
        XCTAssertEqual(questions, [BaselineSampleData.alcoholQuestion, BaselineSampleData.caffeineQuestion,
                                   BaselineSampleData.stressQuestion])
        XCTAssertTrue(data.journal.contains { $0.answeredYes }, "a handful of yes answers")
        XCTAssertTrue(data.journal.contains { !$0.answeredYes })
    }

    func testGenerate_valuesAreInRange() throws {
        let data = BaselineSampleData.generate(anchor: noon)
        let hrvCfg = Baselines.hrvCfg, rhrCfg = Baselines.restingHRCfg
        for d in data.days {
            let hrv = try XCTUnwrap(d.avgHrv, d.day)
            let rhr = try XCTUnwrap(d.restingHr, d.day)
            let sleep = try XCTUnwrap(d.totalSleepMin, d.day)
            XCTAssertTrue((30...140).contains(hrv), "\(d.day) hrv \(hrv)")
            XCTAssertTrue((hrvCfg.minVal...hrvCfg.maxVal).contains(hrv), "inside the engine's HRV bounds")
            XCTAssertTrue((44...72).contains(rhr), "\(d.day) rhr \(rhr)")
            XCTAssertTrue((rhrCfg.minVal...rhrCfg.maxVal).contains(Double(rhr)), "inside the engine's RHR bounds")
            XCTAssertTrue((360...480).contains(sleep), "\(d.day) sleep \(sleep) min (6–8 h)")
            let efficiency = try XCTUnwrap(d.efficiency)
            XCTAssertTrue((80...97).contains(efficiency), "\(d.day) efficiency \(efficiency)")
            let deep = try XCTUnwrap(d.deepMin), rem = try XCTUnwrap(d.remMin), light = try XCTUnwrap(d.lightMin)
            XCTAssertGreaterThan(deep, 0); XCTAssertGreaterThan(rem, 0); XCTAssertGreaterThan(light, 0)
            XCTAssertEqual(deep + rem + light, sleep, accuracy: 0.31, "\(d.day) stages sum to the night")
            let strain = try XCTUnwrap(d.strain)
            XCTAssertTrue((0...100).contains(strain), "\(d.day) effort \(strain)")
            XCTAssertTrue((1...12).contains(try XCTUnwrap(d.disturbances)))
            XCTAssertTrue((10...98).contains(try XCTUnwrap(d.recovery)))
            let steps = try XCTUnwrap(d.steps, "\(d.day) has no step count")
            XCTAssertTrue((2_000...19_000).contains(steps), "\(d.day) steps \(steps)")
            let kcal = try XCTUnwrap(d.activeKcalEst, "\(d.day) has no calorie estimate")
            XCTAssertTrue((1_500...4_000).contains(kcal), "\(d.day) calories \(kcal)")
        }
        for w in data.workouts {
            let minutes = Double(w.endTs - w.startTs) / 60
            XCTAssertTrue((25...75).contains(minutes), "workout \(minutes) min")
            XCTAssertEqual(try XCTUnwrap(w.durationS), Double(w.endTs - w.startTs), accuracy: 0.11)
            XCTAssertLessThan(try XCTUnwrap(w.avgHr), try XCTUnwrap(w.maxHr))
            XCTAssertTrue((10...95).contains(try XCTUnwrap(w.strain)))
            XCTAssertEqual(w.source, BaselineSampleData.deviceId)
            XCTAssertNotNil(w.zonesJSON)
        }
    }

    /// Resting HR falls as HRV rises: the inverse relation a reader expects between the two rings.
    func testGenerate_hrvAndRestingHrMoveInOppositeDirections() {
        let data = BaselineSampleData.generate(anchor: noon)
        let hrv = data.days.compactMap(\.avgHrv)
        let rhr = data.days.compactMap { $0.restingHr.map(Double.init) }
        XCTAssertEqual(hrv.count, rhr.count)
        XCTAssertLessThan(pearson(hrv, rhr), -0.3, "HRV ↔ RHR should be clearly negatively correlated")
        // And the slow baseline rise is there: the last 20 nights average above the first 20.
        let first = hrv.prefix(20).reduce(0, +) / 20, last = hrv.suffix(20).reduce(0, +) / 20
        XCTAssertGreaterThan(last, first)
    }

    /// Workouts raise effort and (slightly) lower HRV, so Effort, Workouts and the rings agree on a day.
    func testGenerate_workoutsDriveEffort() {
        let data = BaselineSampleData.generate(anchor: noon)
        let trained = data.days.filter { ($0.exerciseCount ?? 0) > 0 }
        let rested = data.days.filter { ($0.exerciseCount ?? 0) == 0 }
        XCTAssertFalse(trained.isEmpty); XCTAssertFalse(rested.isEmpty)
        let effort = { (rows: [DailyMetric]) in rows.compactMap(\.strain).reduce(0, +) / Double(rows.count) }
        XCTAssertGreaterThan(effort(trained), effort(rested) + 15)
        // Every workout sits on a day whose row counts it, and vice versa.
        let byDay = Dictionary(grouping: data.workouts) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) }
        for d in data.days { XCTAssertEqual(byDay[d.day]?.count ?? 0, d.exerciseCount ?? 0, d.day) }
    }

    /// Training days carry more steps, and the whole-day calorie estimate never undercuts the day's own
    /// workouts, so Steps, Calories and Workouts agree on a day.
    func testGenerate_stepsAndCaloriesFollowTheDay() throws {
        let data = BaselineSampleData.generate(anchor: noon)
        let trained = data.days.filter { ($0.exerciseCount ?? 0) > 0 }
        let rested = data.days.filter { ($0.exerciseCount ?? 0) == 0 }
        XCTAssertFalse(trained.isEmpty); XCTAssertFalse(rested.isEmpty)
        let meanSteps = { (rows: [DailyMetric]) in Double(rows.compactMap(\.steps).reduce(0, +)) / Double(rows.count) }
        XCTAssertGreaterThan(meanSteps(trained), meanSteps(rested) + 1_000)
        let byDay = Dictionary(grouping: data.workouts) { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) }
        for d in data.days {
            let workoutKcal = (byDay[d.day] ?? []).compactMap(\.energyKcal).reduce(0, +)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(d.activeKcalEst), workoutKcal, d.day)
        }
    }

    /// Each session ends on the morning of its daily row's day (how `BaselineDays.endDay` and
    /// `SleepNightBuilder.nights` group a night) and its stage timeline decodes to the same minutes.
    func testGenerate_sleepSessionsBelongToTheirDay() throws {
        let data = BaselineSampleData.generate(anchor: noon)
        for (row, s) in zip(data.days, data.sleeps) {
            XCTAssertEqual(Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs))), row.day)
            XCTAssertLessThan(s.startTs, s.endTs)
            let segments = AnalyticsEngine.decodeStages(s.stagesJSON)
            XCTAssertFalse(segments.isEmpty, row.day)
            XCTAssertEqual(segments.first?.start, s.startTs)
            let minutes = { (stage: String) in
                Double(segments.filter { $0.stage == stage }.reduce(0) { $0 + ($1.end - $1.start) }) / 60 }
            // Each stage is split over two or three whole-minute blocks: at most ±0.5 min per block.
            XCTAssertEqual(minutes("deep"), try XCTUnwrap(row.deepMin), accuracy: 1.1, row.day)
            XCTAssertEqual(minutes("rem"), try XCTUnwrap(row.remMin), accuracy: 1.1, row.day)
            XCTAssertEqual(minutes("light"), try XCTUnwrap(row.lightMin), accuracy: 1.6, row.day)
            XCTAssertEqual(segments.last?.end, s.endTs, "the session ends where its timeline ends")
        }
    }

    // MARK: Store round-trip

    /// Insert writes exactly under the two sample ids; remove leaves nothing under them and leaves every
    /// other device's rows alone.
    @MainActor
    func testInsertThenRemove_leavesNothingUnderTheSampleIds() async throws {
        let store = try await WhoopStore.inMemory()
        // A real strap night that must survive the sample's removal.
        let strapDay = Fixtures.dayKey(noon, minus: 3)
        _ = try await store.upsertDailyMetrics([Fixtures.metric(strapDay, hrv: 60, rhr: 50)], deviceId: "my-whoop-noop")
        _ = try await store.upsertJournal([JournalEntry(day: strapDay, question: BaselineSampleData.alcoholQuestion,
                                                        answeredYes: true, notes: nil)], deviceId: "noop-journal")

        let before = await BaselineSampleData.storedRowCount(in: store)
        XCTAssertEqual(before, 0)
        try await BaselineSampleData.insert(into: store, anchor: noon)
        let data = BaselineSampleData.generate(anchor: noon)
        let expected = data.days.count + data.sleeps.count + data.workouts.count + data.journal.count
        let afterInsert = await BaselineSampleData.storedRowCount(in: store)
        XCTAssertEqual(afterInsert, expected)
        // Idempotent: a second insert for the same anchor rewrites the same rows.
        try await BaselineSampleData.insert(into: store, anchor: noon)
        let afterSecondInsert = await BaselineSampleData.storedRowCount(in: store)
        XCTAssertEqual(afterSecondInsert, expected)
        // Nothing landed under the strap's or the journal's ids.
        let strapRows = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: "0000-01-01", to: "9999-12-31")
        XCTAssertEqual(strapRows.count, 1)
        let imported = try await store.dailyMetrics(deviceId: "my-whoop", from: "0000-01-01", to: "9999-12-31")
        XCTAssertTrue(imported.isEmpty, "the sample never writes under the import id")

        try await BaselineSampleData.remove(from: store)
        let afterRemove = await BaselineSampleData.storedRowCount(in: store)
        XCTAssertEqual(afterRemove, 0)
        let far = 4_102_444_800
        let sleepsUnderRawId = try await store.sleepSessions(deviceId: BaselineSampleData.deviceId, from: 0, to: far, limit: 100)
        XCTAssertTrue(sleepsUnderRawId.isEmpty)
        let workoutsUnderComputedId = try await store.workouts(deviceId: BaselineSampleData.computedDeviceId, from: 0, to: far, limit: 100)
        XCTAssertTrue(workoutsUnderComputedId.isEmpty)
        // The strap's night and the native journal answer are untouched.
        let strapAfter = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: "0000-01-01", to: "9999-12-31")
        XCTAssertEqual(strapAfter.count, 1)
        let nativeJournal = try await store.journalEntries(deviceId: "noop-journal", from: "0000-01-01", to: "9999-12-31")
        XCTAssertEqual(nativeJournal.count, 1)
    }

    /// Through NOOP's read spine: once the repository's read id is the sample's, the 60 nights arrive in
    /// `repo.baselineDays` as the strap's own (`.noopComputed`) rows, with the nights, workouts and journal;
    /// after removal and a refresh, nothing is left.
    @MainActor
    func testReadSpine_surfacesTheSampleAndForgetsItAfterRemoval() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "my-whoop", mac: nil, name: "WHOOP")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)

        try await BaselineSampleData.insert(into: store, anchor: noon)
        await repo.refresh()
        XCTAssertTrue(repo.loaded)
        XCTAssertTrue(repo.days.isEmpty, "precondition: a dedicated id is invisible until the read id points at it")

        XCTAssertTrue(repo.adoptActiveDeviceId(BaselineSampleData.deviceId))
        await repo.refresh()
        let days = BaselineReadouts.days(repo, mode: .strapFirst)
        XCTAssertEqual(days.count, BaselineSampleData.nights)
        XCTAssertEqual(days.last?.day, Fixtures.dayKey(noon))
        XCTAssertTrue(repo.vitalRows.allSatisfy { $0.source == .noopComputed }, "the sample reads as the strap's own nights")
        XCTAssertTrue(days.allSatisfy { $0.steps != nil && $0.activeKcalEst != nil }, "steps and calories survive the funnel")
        // Home's Steps card and Calories cell, through the same readouts the screen calls.
        let todayKey = Fixtures.dayKey(noon)
        let steps = await BaselineReadouts.steps(repo, for: todayKey, mode: .strapFirst)
        XCTAssertTrue(steps.hasRecordedSource)
        XCTAssertEqual(steps.steps, days.last?.steps, "the anchor day's count, as the sample wrote it")
        XCTAssertNotNil(steps.average7)
        XCTAssertNotNil(steps.average30)
        let calories = BaselineReadouts.calories(for: todayKey, days: days)
        XCTAssertEqual(calories.kcal, days.last?.activeKcalEst)
        XCTAssertNotNil(calories.average30)
        let nowTs = Int(noon.timeIntervalSince1970)
        let computedNights = await repo.computedSleepSessions(from: nowTs - 100 * 86_400, to: nowTs + 86_400, limit: 1000)
        XCTAssertEqual(computedNights.count, BaselineSampleData.nights)
        let funnelNights = await BaselineReadouts.nights(repo, mode: .strapFirst, now: noon)
        XCTAssertEqual(funnelNights.count, BaselineSampleData.nights)
        let workouts = await repo.workoutRows(days: 90)
        XCTAssertEqual(workouts.count, BaselineSampleData.generate(anchor: noon).workouts.count)
        let journal = await repo.journalEntries(days: 90)
        XCTAssertEqual(journal.count, BaselineSampleData.journalNights * 3)

        try await BaselineSampleData.remove(from: store)
        await repo.refresh()
        XCTAssertTrue(BaselineReadouts.days(repo, mode: .strapFirst).isEmpty)
        let workoutsAfter = await repo.workoutRows(days: 90)
        XCTAssertTrue(workoutsAfter.isEmpty)
        let journalAfter = await repo.journalEntries(days: 90)
        XCTAssertTrue(journalAfter.isEmpty)
        let nightsAfter = await repo.computedSleepSessions(from: nowTs - 100 * 86_400, to: nowTs + 86_400, limit: 1000)
        XCTAssertTrue(nightsAfter.isEmpty)
    }

    /// The flag gates the read-spine re-point, and nothing else reads it.
    @MainActor
    func testApplyReadSpine_followsTheFlag() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: BaselineSampleData.activeKey)
        defer {
            if let saved { defaults.set(saved, forKey: BaselineSampleData.activeKey) }
            else { defaults.removeObject(forKey: BaselineSampleData.activeKey) }
        }
        let repo = Repository(deviceId: "my-whoop")
        defaults.set(false, forKey: BaselineSampleData.activeKey)
        XCTAssertFalse(BaselineSampleData.isActive)
        XCTAssertFalse(BaselineSampleData.applyReadSpine(repo))
        XCTAssertEqual(repo.deviceId, "my-whoop")
        defaults.set(true, forKey: BaselineSampleData.activeKey)
        XCTAssertTrue(BaselineSampleData.applyReadSpine(repo), "moves the read id once")
        XCTAssertEqual(repo.deviceId, BaselineSampleData.deviceId)
        XCTAssertFalse(BaselineSampleData.applyReadSpine(repo), "and is then a no-op, so Home's re-apply loop settles")
    }

    // MARK: Helpers

    private func pearson(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) { sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx); syy += (y - my) * (y - my) }
        return sxy / (sxx * syy).squareRoot()
    }
}
