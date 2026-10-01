import XCTest
import WhoopStore
import StrandAnalytics
@testable import Baseline

/// Fixture helpers shared by the Baseline builder tests. Everything here is a value builder; no test
/// touches the store, Bluetooth or SwiftUI.
enum Fixtures {
    /// A `DailyMetric` with only the columns the builders read; every other column stays nil.
    static func metric(_ day: String, hrv: Double? = nil, rhr: Int? = nil, sleepMin: Double? = nil,
                       efficiency: Double? = nil, deep: Double? = nil, rem: Double? = nil,
                       light: Double? = nil, strain: Double? = nil, recovery: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleepMin, efficiency: efficiency, deepMin: deep, remMin: rem,
                    lightMin: light, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: strain, exerciseCount: nil)
    }

    /// The "yyyy-MM-dd" key `days` before `anchor`, as pure UTC key arithmetic (`Baselines.cutoffKey`
    /// pins its calendar to UTC), so a literal anchor never shifts under the machine's zone.
    static func key(_ anchor: String, minus days: Int) -> String {
        Baselines.cutoffKey(todayKey: anchor, carryDays: days)
    }

    /// A wall-clock instant in the machine's own calendar and zone. `TrendsSeries.build` and
    /// `SleepNightBuilder.nights` key days through `Repository.localDayKey` (local zone), so fixtures
    /// built from local components round-trip to the literal date regardless of where the test runs.
    static func local(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    /// Local day key `days` calendar days before `date` (noon-anchored dates never straddle a DST edge).
    static func dayKey(_ date: Date, minus days: Int = 0) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -days, to: date)!
        return Repository.localDayKey(d)
    }

    /// The segment-array form of `stagesJSON` that `AnalyticsEngine.decodeStages` reads.
    static func stagesJSON(_ segments: [StageSegment]) -> String {
        String(data: try! JSONEncoder().encode(segments), encoding: .utf8)!
    }
}

/// Base class for tests that fold baselines. `BaselineReadouts.latestNight` / `nightlyStates` and
/// `TrendsSeries.build` honour the recalibration epochs in `UserDefaults.standard` (the HRV epoch for HRV,
/// the recovery epoch for resting HR); the test host is the app, so a recalibration left behind on the
/// simulator would silently drop every fixture night. Clear both for the test and put them back afterwards.
class BaselineEngineTestCase: XCTestCase {
    private var savedHrvEpoch: Double = 0
    private var savedRecoveryEpoch: Double = 0

    override func setUp() {
        super.setUp()
        savedHrvEpoch = Baselines.hrvBaselineEpoch()
        savedRecoveryEpoch = Baselines.recoveryBaselineEpoch()
        UserDefaults.standard.removeObject(forKey: Baselines.hrvBaselineEpochKey)
        UserDefaults.standard.removeObject(forKey: Baselines.recoveryBaselineEpochKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Baselines.hrvBaselineEpochKey)
        UserDefaults.standard.removeObject(forKey: Baselines.recoveryBaselineEpochKey)
        if savedHrvEpoch > 0 {
            UserDefaults.standard.set(savedHrvEpoch, forKey: Baselines.hrvBaselineEpochKey)
        }
        if savedRecoveryEpoch > 0 {
            UserDefaults.standard.set(savedRecoveryEpoch, forKey: Baselines.recoveryBaselineEpochKey)
        }
        super.tearDown()
    }
}
