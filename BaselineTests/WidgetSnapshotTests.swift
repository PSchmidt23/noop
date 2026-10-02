import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// `BaselineWidgetSnapshot.make(from:)`: the widget's glance is the `TodaySnapshot` Home draws, flattened.
/// For one fixture every number must equal the snapshot's, every phrase must be the funnel's, and the JSON
/// the App Group carries must round-trip. Day keys are literals (UTC key math), nothing here touches the
/// store, the App Group container or WidgetKit.
final class WidgetSnapshotTests: BaselineEngineTestCase {

    private let today = "2026-02-18"
    private let now = Date(timeIntervalSince1970: 1_771_400_000)

    private func priorNights(_ n: Int, hrv: Double, rhr: Int? = nil) -> [DailyMetric] {
        (1...n).reversed().map { Fixtures.metric(Fixtures.key(today, minus: $0), hrv: hrv, rhr: rhr) }
    }

    private func fixture() throws -> (TodaySnapshot, BaselineWidgetSnapshot) {
        let days = priorNights(20, hrv: 60, rhr: 50) + [Fixtures.metric(today, hrv: 61, rhr: 52)]
        let n0 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(today, sleepMin: 480, efficiency: 0.89)))
        let n1 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 1), sleepMin: 420)))
        let n2 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 2), sleepMin: 450)))
        let n3 = try XCTUnwrap(SleepNightBuilder.build(fromDaily: Fixtures.metric(Fixtures.key(today, minus: 3), sleepMin: 390)))
        let snap = TodaySnapshot.build(days: days, nights: [n0, n1, n2, n3], todayKey: today)
        let widget = BaselineWidgetSnapshot.make(from: snap, lastSyncedAt: now.addingTimeInterval(-600), generatedAt: now)
        return (snap, widget)
    }

    // MARK: Same numbers as Home

    func testHrvMatchesTodaySnapshot() throws {
        let (snap, w) = try fixture()
        let hrv = try XCTUnwrap(snap.hrv)
        XCTAssertEqual(w.dayKey, today)
        XCTAssertEqual(w.hrvMs, 61)
        XCTAssertEqual(w.hrvDay, today)
        XCTAssertEqual(try XCTUnwrap(w.hrvBaselineMs), try XCTUnwrap(hrv.baseline), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(w.hrvBandLowMs), try XCTUnwrap(hrv.bandLow), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(w.hrvBandHighMs), try XCTUnwrap(hrv.bandHigh), accuracy: 1e-9)
        XCTAssertEqual(w.hrvBandPosition, "inside")
        // The arc is Home's: MetricRingScale over the tile's domain.
        let domain = try XCTUnwrap(MetricRingScale.domain(state: hrv.state, cfg: Baselines.hrvCfg))
        XCTAssertEqual(try XCTUnwrap(w.hrvRingFraction), MetricRingScale.fraction(61, in: domain), accuracy: 1e-9)
        // The tile's context sentence, word for word.
        XCTAssertEqual(w.hrvDeltaText, "+1 ms vs baseline · inside your band")
    }

    func testRestingHrAndSleepMatchTodaySnapshot() throws {
        let (snap, w) = try fixture()
        let rhr = try XCTUnwrap(snap.restingHr)
        XCTAssertEqual(w.rhrBpm, 52)
        XCTAssertEqual(try XCTUnwrap(w.rhrBaselineBpm), try XCTUnwrap(rhr.baseline), accuracy: 1e-9)
        XCTAssertEqual(w.rhrBandPosition, "inside")
        XCTAssertEqual(w.rhrDeltaText, "+2 bpm vs baseline · inside your band")

        let sleep = try XCTUnwrap(snap.sleep)
        XCTAssertEqual(w.sleepMinutes, 480)
        XCTAssertEqual(w.sleepDay, today)
        XCTAssertEqual(try XCTUnwrap(w.sleepAverageMinutes), try XCTUnwrap(sleep.avg30Min), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(w.sleepAverageMinutes), 420, accuracy: 1e-9, "the three nights before, never last night itself")
        XCTAssertEqual(w.lastSyncedAt, now.addingTimeInterval(-600))
        XCTAssertEqual(w.generatedAt, now)
        XCTAssertFalse(w.isEmpty)
    }

    func testReadinessTierCarriesHomeLabelAndColourName() throws {
        let (snap, w) = try fixture()
        guard case .tier(let tier) = snap.readiness else { return XCTFail("20 nights must score a tier") }
        XCTAssertEqual(w.readinessLabel, tier.baselineLabel)
        XCTAssertEqual(w.readinessColorName, BaselineWidgetSnapshot.colorName(tier))
        XCTAssertNil(w.readinessCalibratingNights)
    }

    func testCalibratingReadinessCarriesTheCount() throws {
        let days = priorNights(5, hrv: 60) + [Fixtures.metric(today, hrv: 61)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let w = BaselineWidgetSnapshot.make(from: snap, lastSyncedAt: nil, generatedAt: now)
        XCTAssertNil(w.readinessLabel)
        XCTAssertEqual(w.readinessCalibratingNights, 6)
        XCTAssertEqual(w.hrvMs, 61)
        XCTAssertNil(w.sleepMinutes)
    }

    func testOnBaselineWording() throws {
        // Ten identical nights fold to 60; a 60 ms night is "On your baseline", as the tile says.
        let days = priorNights(10, hrv: 60) + [Fixtures.metric(today, hrv: 60)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let w = BaselineWidgetSnapshot.make(from: snap, lastSyncedAt: nil, generatedAt: now)
        XCTAssertEqual(w.hrvDeltaText, "On your baseline · inside your band")
    }

    func testCalibratingBaselineWording() throws {
        let days = [Fixtures.metric(Fixtures.key(today, minus: 1), hrv: 60), Fixtures.metric(today, hrv: 61)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let w = BaselineWidgetSnapshot.make(from: snap, lastSyncedAt: nil, generatedAt: now)
        XCTAssertEqual(w.hrvDeltaText, "Baseline after \(Baselines.minNightsSeed) nights · 1 so far")
        XCTAssertNil(w.hrvRingFraction, "track only while calibrating, as Home")
        XCTAssertNil(w.hrvBaselineMs)
        XCTAssertNil(w.hrvBandPosition)
    }

    func testStaleNightBlanksTheNumberAndNamesTheDay() throws {
        let lastNight = Fixtures.key(today, minus: Baselines.vitalCarryDays + 1)
        let days = (1...10).reversed().map { Fixtures.metric(Fixtures.key(lastNight, minus: $0), hrv: 60) }
            + [Fixtures.metric(lastNight, hrv: 61)]
        let snap = TodaySnapshot.build(days: days, nights: [], todayKey: today)
        let w = BaselineWidgetSnapshot.make(from: snap, lastSyncedAt: nil, generatedAt: now)
        XCTAssertNil(w.hrvMs)
        XCTAssertEqual(w.hrvDay, lastNight)
        XCTAssertNil(w.hrvRingFraction)
        XCTAssertEqual(w.hrvDeltaText, "No night since \(TodayFormat.dayLabel(lastNight))")
        XCTAssertNil(w.readinessLabel)
        XCTAssertNil(w.readinessCalibratingNights)
    }

    func testEmptyStoreIsEmptyGlance() {
        let snap = TodaySnapshot.build(days: [], nights: [], todayKey: today)
        let w = BaselineWidgetSnapshot.make(from: snap, lastSyncedAt: nil, generatedAt: now)
        XCTAssertTrue(w.isEmpty)
        XCTAssertEqual(w.hrvDeltaText, "Waiting for the first night")
        XCTAssertEqual(w.rhrDeltaText, "Waiting for the first night")
    }

    // MARK: Transport

    func testJSONRoundTripAndVersion() throws {
        let (_, w) = try fixture()
        let data = try BaselineWidgetStore.encode(w)
        let back = try BaselineWidgetStore.decode(data)
        XCTAssertEqual(back.version, BaselineWidgetSnapshot.currentVersion)
        XCTAssertTrue(back.rendersSame(as: w))
        XCTAssertEqual(back.hrvMs, w.hrvMs)
        XCTAssertEqual(back.sleepAverageMinutes, w.sleepAverageMinutes)
        // ISO-8601 dates survive to the second.
        XCTAssertEqual(try XCTUnwrap(back.lastSyncedAt).timeIntervalSince1970,
                       try XCTUnwrap(w.lastSyncedAt).timeIntervalSince1970, accuracy: 1)
    }

    func testOlderSnapshotWithoutNewKeysStillDecodes() throws {
        let json = #"{"version":1,"dayKey":"2026-02-18","generatedAt":"2026-02-18T07:00:00Z"}"#
        let back = try BaselineWidgetStore.decode(Data(json.utf8))
        XCTAssertEqual(back.dayKey, "2026-02-18")
        XCTAssertTrue(back.isEmpty)
    }

    func testRendersSameIgnoresOnlyTheClock() throws {
        let (_, w) = try fixture()
        var later = w
        later.generatedAt = now.addingTimeInterval(3600)
        XCTAssertTrue(w.rendersSame(as: later), "a fresh timestamp alone must not trigger a publish")
        var changed = w
        changed.hrvMs = 70
        XCTAssertFalse(w.rendersSame(as: changed))
    }

    func testAppGroupResolution() {
        XCTAssertEqual(BaselineWidgetStore.resolveAppGroupID(infoDictionary: ["AppGroupIdentifier": " group.x "]), "group.x")
        XCTAssertEqual(BaselineWidgetStore.resolveAppGroupID(infoDictionary: [:]), BaselineWidgetStore.fallbackGroup)
        XCTAssertEqual(BaselineWidgetStore.resolveAppGroupID(infoDictionary: ["AppGroupIdentifier": ""]),
                       BaselineWidgetStore.fallbackGroup)
    }

    // MARK: Deep link

    func testDeepLinkDestinations() throws {
        XCTAssertEqual(BaselineDeepLink.destination(for: BaselineDeepLink.home), .home)
        XCTAssertEqual(BaselineDeepLink.destination(for: try XCTUnwrap(URL(string: "baseline://trends"))), .trends)
        XCTAssertEqual(BaselineDeepLink.destination(for: try XCTUnwrap(URL(string: "BASELINE://Sleep"))), .sleep)
        XCTAssertNil(BaselineDeepLink.destination(for: try XCTUnwrap(URL(string: "noop://import-health"))))
        XCTAssertNil(BaselineDeepLink.destination(for: try XCTUnwrap(URL(string: "baseline://settings"))))
    }
}
