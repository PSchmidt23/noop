#if os(iOS) && DEBUG
import Foundation
import WhoopStore

// DEBUG only: what NOOP's `--demo-seed` leaves empty, written beside it so the screenshot harness and the
// UI tests see every Home card (`Research/ACTIVITY_AUDIT.md` §5).
//
// ONLY OVER NOOP'S OWN DEMO STORE. NOOP's seeder seeds only a store with no "my-whoop" daily rows, and
// `--demo-seed` reaches a store that holds real data too (a DEBUG build on someone's phone). Nothing
// below runs unless the seeder seeded THIS store (`seededByNOOP`): its proof is the device-row name it
// writes just before its rows ("WHOOP (demo)"), which only it ever writes and which the repository
// re-stamps on every later launch (BLE start-up on a phone may re-stamp it sooner; the gate then fails
// closed), so the launch that sees it writes down its own marker (one point under
// `markerDeviceId`, an id nothing reads or deletes, dated on the seeded history's first day). A store the
// seeder skipped is left exactly as it was: no streams, no phone series, no read-id move. A demo store
// seeded before this check existed carries no marker, so it is skipped until the app is reinstalled once.
//
// NOOP's seeder (`AppleDemoSeeder`, run by `AppModel` at launch) writes daily rows, sessions, workouts and
// Apple Health day rows under "my-whoop" and "apple-health", but no heart-rate seconds, no motion and no
// step series. So Heart rate, Stress and the active part of Calories had nothing to read, Intensity
// minutes fell back to "from workouts only", and Steps (which reads NOOP's step resolver, never the
// `appleDaily` table) was empty. This augmentation, once the seeder has finished:
//   • writes the sample generator's streams (`BaselineSampleStreams`) for the last `days` days, planned
//     from the DEMO's own rows (each night's resting heart rate, its sessions, its workouts' average and
//     maximum), under `BaselineSampleData.deviceId`: NOT under "my-whoop", because NOOP's engine re-scores
//     raw seconds for registered straps and the canonical id, and its computed rows would then win the
//     demo's days field by field under strap-first and change the screenshots;
//   • copies the demo's Apple Health day rows into the `metricSeries` points HealthKit sync writes beside
//     them ("steps", "active_kcal" under "apple-health"), the series NOOP's resolver reads, so Steps reads
//     as the iPhone's count, as it would for a WHOOP 4.0 wearer with Apple Health on. They are the same
//     store's seeded "apple-health" rows restated (NOOP's resolver reads only that id for the phone), so
//     the gate above is what keeps them off real data; `BaselineSampleData.remove` must never delete
//     "apple-health" points, which in Release are the person's own HealthKit steps;
//   • points the read id at the sample id (`BaselineSampleData.applyReadSpine`, re-applied on every
//     activation), so the streams are read while the demo's own rows stay in the union beneath.
// Deterministic (the plans are seeded per day key) and idempotent (every write is keyed). Release builds
// compile none of it.
enum BaselineDemoAugmentation {

    /// Days of streams written, ending today (the 30-day Stress lens plus a few).
    static let days = 35
    /// Seed for the demo's stream plans (mixed with each day key).
    static let seed: UInt64 = 0xDE30_5EED
    /// How long to wait for NOOP's seeder to land its rows.
    static let seederWaitSeconds = 30
    /// The name NOOP's seeder gives the "my-whoop" device row, written only in the launch that seeded
    /// (the literal inside `AppleDemoSeeder.seed`; if NOOP renames it, the gate fails closed).
    static let seededDeviceName = "WHOOP (demo)"
    /// Where the proof is written down once seen: an id no read spine, registry or removal touches.
    static let markerDeviceId = "baseline-demo"
    static let markerKey = "noop_demo_seeded"

    static var requested: Bool { AppleDemoSeeder.requested }

    @MainActor private(set) static var isReady = false
    @MainActor private static var started = false

    /// Starts the augmentation once per process (no-op when not requested). When it has written, the
    /// read id moves onto the sample id and the repository refreshes.
    @MainActor
    static func startIfNeeded(_ repo: Repository) {
        guard requested, !started else { return }
        started = true
        Task { @MainActor in
            guard let store = await repo.storeHandle() else { return }
            var waited = 0
            while waited < seederWaitSeconds {
                let landed = (try? await store.dailyMetrics(deviceId: AppleDemoSeeder.whoop, from: "0000-01-01",
                                                            to: "9999-12-31"))?.isEmpty == false
                if landed { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited += 1
            }
            guard await seededByNOOP(store) else {
                NSLog("BaselineDemoAugmentation: skipped — NOOP's seeder did not seed this store, so it is left untouched")
                return
            }
            do {
                try await augment(store: store, anchor: Date())
            } catch {
                NSLog("BaselineDemoAugmentation: write failed — \(error)")
                return
            }
            isReady = true
            if repo.adoptActiveDeviceId(BaselineSampleData.deviceId) { await repo.refresh() }
        }
    }

    /// True when NOOP's seeder seeded `store` (see the header): its marker matches the "my-whoop" history's
    /// first day, or, in the launch that seeded, the device row still carries the seeder's name, and the
    /// marker is then written. False for a store with no "my-whoop" rows, one the seeder skipped, and one
    /// whose history was wiped and refilled since (its first day moved).
    static func seededByNOOP(_ store: WhoopStore) async -> Bool {
        let rows = (try? await store.dailyMetrics(deviceId: AppleDemoSeeder.whoop, from: "0000-01-01",
                                                  to: "9999-12-31")) ?? []
        guard let first = rows.map(\.day).min() else { return false }
        let marker = (try? await store.metricSeries(deviceId: markerDeviceId, key: markerKey, from: "0000-01-01",
                                                    to: "9999-12-31")) ?? []
        if marker.contains(where: { $0.day == first }) { return true }
        guard (try? await store.deviceRowForTest(id: AppleDemoSeeder.whoop))?.name == seededDeviceName else { return false }
        _ = try? await store.deleteMetricSeries(deviceId: markerDeviceId, key: markerKey)
        _ = try? await store.upsertMetricSeries([MetricPoint(day: first, key: markerKey, value: 1)], deviceId: markerDeviceId)
        return true
    }

    /// The writes (see the header). Reads the demo's rows back from `store`. Callers check `seededByNOOP`
    /// first: this writes under "apple-health" too.
    static func augment(store: WhoopStore, anchor: Date, calendar: Calendar = .current) async throws {
        let today = calendar.startOfDay(for: anchor)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return }
        let fromKey = Repository.localDayKey(first)
        let toKey = Repository.localDayKey(anchor)
        let from = Int(first.timeIntervalSince1970) - 86_400, to = Int(anchor.timeIntervalSince1970) + 86_400

        let rows = try await store.dailyMetrics(deviceId: AppleDemoSeeder.whoop, from: fromKey, to: toKey)
        let sleeps = try await store.sleepSessions(deviceId: AppleDemoSeeder.whoop, from: from, to: to, limit: 1_000)
        let workouts = try await store.workouts(deviceId: AppleDemoSeeder.whoop, from: from, to: to, limit: 1_000)
        var plans = BaselineSampleStreams.plans(days: rows, sleeps: sleeps, workouts: workouts, anchor: anchor,
                                                seed: seed, calendar: calendar)
        // A relaunch over a store that already carries the streams writes only today's (keyed upserts make a
        // full rewrite harmless, but it costs seconds on every launch).
        let existing = try? await store.hrFingerprint(deviceId: BaselineSampleData.deviceId,
                                                      from: Int(first.timeIntervalSince1970), to: Int(today.timeIntervalSince1970) - 1)
        if let existing, existing.count > 0 { plans = plans.filter { $0.day == toKey } }
        try await BaselineSampleStreams.insert(plans, into: store, deviceId: BaselineSampleData.deviceId,
                                               until: Int(anchor.timeIntervalSince1970))

        // The phone's day totals as the series HealthKit sync writes beside `appleDaily`.
        let apple = try await store.appleDaily(deviceId: AppleDemoSeeder.apple, from: "0000-01-01", to: toKey)
        var points: [MetricPoint] = []
        // Today "so far", like the sample's own anchor day (the seeder writes a whole day's count).
        let stepsShare = BaselineSampleData.wakingFraction(anchor, calendar: calendar)
        let dayShare = BaselineReadouts.dayFraction(anchor, calendar: calendar)
        for d in apple {
            let isToday = d.day == toKey
            if let steps = d.steps {
                let value = isToday ? (Double(steps) * stepsShare).rounded() : Double(steps)
                points.append(MetricPoint(day: d.day, key: "steps", value: value))
            }
            if let kcal = d.activeKcal {
                points.append(MetricPoint(day: d.day, key: "active_kcal", value: isToday ? kcal * dayShare : kcal))
            }
        }
        if !points.isEmpty { _ = try await store.upsertMetricSeries(points, deviceId: Repository.appleHealthSource) }
    }
}
#endif
