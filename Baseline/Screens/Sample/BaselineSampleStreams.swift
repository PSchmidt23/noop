#if os(iOS)
import Foundation
import WhoopStore
import WhoopProtocol

// The intraday streams behind sample data (and the DEBUG demo augmentation): a heart-rate trace for every
// day and wrist motion for the hours the person was walking or training, so the cards that read the
// strap's raw seconds fill in: Heart rate (1D and the per-day ranges), Intensity minutes (scored, not
// "from workouts only"), Stress (calm / elevated / restored hours on the personal lens) and the active
// part of Calories. Pure and deterministic (a SplitMix64 seeded per day); nothing here is real
// biometric data. `Research/ACTIVITY_AUDIT.md` §5 lists what each card needs.
//
// The day's shape, relative to that night's resting heart rate (`DayPlan.restingHr`):
//   • asleep (inside a sleep session): resting + 3, a slow swing of ±2 and ±1 jitter, so the night's low
//     sits on the row's resting HR;
//   • awake, by local hour: 06–08 and 20–22 at resting + 11 (the calm floor: "restored"), the working
//     day at resting + 16–17 ("calm", 5–6 bpm over the floor), a few TENSE hours a weekday at resting + 34
//     (≥ 15 bpm over the floor while still: "elevated"), the hour after a workout a little raised;
//   • a workout (the dataset's own rows): a five-minute ramp to its average heart rate, swinging toward
//     its maximum, with wrist motion, so Stress masks it as "moving" and Intensity credits it;
//   • a lunchtime brisk walk on days without a workout (resting + 50, with motion): moderate minutes,
//     and another "moving" hour.
// Density: inside the Intensity verify window (`denseDays`, the last 14 days) one reading every 3 s while
// awake (20 a minute, exactly the classifier's floor) and every 30 s asleep; older days every 11 s awake
// (327 an hour, over Stress's 300) and every 60 s asleep. Motion: one record every 5 s inside a walk or a
// workout, alternating 0.3 g on one axis (NOOP's walking floor is 0.20 g of change per record).
enum BaselineSampleStreams {

    /// One workout as the trace follows it.
    struct Workout: Equatable, Sendable {
        let start: Int
        let end: Int
        let avgHr: Int
        let maxHr: Int
    }

    /// Everything one day's trace is drawn from.
    struct DayPlan: Equatable, Sendable {
        let day: String
        /// Local midnight and the next local midnight (unix seconds).
        let dayStart: Int
        let dayEnd: Int
        let restingHr: Int
        /// Sleep sessions overlapping the day, as half-open `[start, end)` spans.
        let sleeps: [Range<Int>]
        let workouts: [Workout]
        /// Weekend days get fewer tense hours.
        let weekend: Bool
        /// One reading every 3 s awake (the Intensity verify window) instead of every 11 s.
        let dense: Bool
        let seed: UInt64
    }

    /// Days back from the anchor (inclusive of the anchor day) written at the dense rate.
    static let denseDays = 14
    static let denseAwakeStep = 3
    static let denseAsleepStep = 30
    static let sparseAwakeStep = 11
    static let sparseAsleepStep = 60
    static let motionStep = 5
    /// XORed into the sample seed for the stream generator, so the daily rows stay byte-identical.
    static let streamSeedSalt: UInt64 = 0x5EED_0F_4EA7

    /// The local hours a tense hour may fall on.
    static let tenseCandidates = [9, 10, 11, 14, 15, 16, 17]

    // MARK: Plans

    /// The plans for a sample dataset (`BaselineSampleData.generate`): one per day row, its night's
    /// resting heart rate, its sessions and its workouts. Pure.
    static func plans(for data: BaselineSampleData.Dataset, anchor: Date, calendar: Calendar = .current) -> [DayPlan] {
        plans(days: data.days, sleeps: data.sleeps, workouts: data.workouts, anchor: anchor,
              seed: BaselineSampleData.seed ^ streamSeedSalt, calendar: calendar)
    }

    /// The plans for any rows (the demo augmentation hands it NOOP's demo-seeded rows). Days without a
    /// resting heart rate are skipped; `seed` is mixed with each day key, so a day's trace does not depend
    /// on which other days were planned.
    static func plans(days: [DailyMetric], sleeps: [CachedSleepSession], workouts: [WorkoutRow], anchor: Date,
                      seed: UInt64, calendar: Calendar = .current) -> [DayPlan] {
        let anchorDay = calendar.startOfDay(for: anchor)
        let denseFrom = calendar.date(byAdding: .day, value: -(denseDays - 1), to: anchorDay) ?? anchorDay
        return days.compactMap { row -> DayPlan? in
            guard let rhr = row.restingHr, rhr > 0, let start = BaselineReadouts.localMidnight(of: row.day),
                  let next = calendar.date(byAdding: .day, value: 1, to: start).map({ calendar.startOfDay(for: $0) }) else { return nil }
            let from = Int(start.timeIntervalSince1970), to = Int(next.timeIntervalSince1970)
            let spans = sleeps.filter { $0.endTs > from && $0.startTs < to }.map { $0.startTs..<max($0.startTs, $0.endTs) }
            let rows = workouts.filter { $0.startTs >= from && $0.startTs < to }.map {
                Workout(start: $0.startTs, end: $0.endTs, avgHr: $0.avgHr ?? rhr + 70, maxHr: $0.maxHr ?? rhr + 95)
            }
            let weekday = calendar.component(.weekday, from: start)
            return DayPlan(day: row.day, dayStart: from, dayEnd: to, restingHr: rhr, sleeps: spans, workouts: rows,
                           weekend: weekday == 1 || weekday == 7, dense: start >= denseFrom,
                           seed: seed ^ fnv1a(row.day))
        }
    }

    /// FNV-1a over the key's UTF-8 bytes: a platform-neutral per-day seed (never `hashValue`).
    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01B3 }
        return h
    }

    // MARK: Streams

    /// The local hours of `plan` that are tense (deterministic from its seed): none to three on a
    /// weekday, at most one at the weekend.
    static func tenseHours(_ plan: DayPlan) -> Set<Int> {
        var rng = BaselineSampleRNG(seed: plan.seed ^ 0x7E45)
        let counts = plan.weekend ? [0, 0, 1] : [0, 1, 1, 2, 2, 3]
        let n = counts[rng.nextInt(0, counts.count)]
        var pool = tenseCandidates
        var out: Set<Int> = []
        for _ in 0..<n where !pool.isEmpty {
            out.insert(pool.remove(at: rng.nextInt(0, pool.count)))
        }
        return out
    }

    /// The day's lunchtime walk (12:10–12:45 local) on a day without a workout; nil otherwise.
    static func walk(_ plan: DayPlan) -> Range<Int>? {
        guard plan.workouts.isEmpty else { return nil }
        let start = plan.dayStart + 12 * 3_600 + 10 * 60
        return start..<(start + 35 * 60)
    }

    /// The day's heart rate and motion, every reading at or before `until` (nil = the whole day).
    static func streams(for plan: DayPlan, until: Int? = nil) -> (hr: [HRSample], gravity: [GravitySample]) {
        let end = min(plan.dayEnd, (until ?? plan.dayEnd) + 1)
        guard end > plan.dayStart else { return ([], []) }
        var rng = BaselineSampleRNG(seed: plan.seed)
        let tense = Self.tenseHours(plan)
        let lunchWalk = Self.walk(plan)
        let rhr = Double(plan.restingHr)
        let awakeStep = plan.dense ? denseAwakeStep : sparseAwakeStep
        let asleepStep = plan.dense ? denseAsleepStep : sparseAsleepStep
        let lastWorkoutEnd: (Int) -> Int? = { t in plan.workouts.filter { $0.end <= t }.map(\.end).max() }

        var hr: [HRSample] = []
        hr.reserveCapacity((end - plan.dayStart) / awakeStep + 8)
        var t = plan.dayStart
        while t < end {
            let asleep = plan.sleeps.contains { $0.contains(t) }
            let jitter = rng.nextDouble() * 2 - 1
            let bpm: Double
            if asleep {
                bpm = rhr + 3 + 2 * sin(Double(t) / 5_400 * 2 * .pi) + jitter
            } else if let w = plan.workouts.first(where: { t >= $0.start && t < $0.end }) {
                let ramp = min(1, Double(t - w.start) / 300)
                let swing = Double(w.maxHr - w.avgHr) * 0.6 * sin(Double(t - w.start) / 420 * 2 * .pi)
                let target = Double(w.avgHr) + swing
                bpm = min(Double(w.maxHr), (rhr + 30) + (target - (rhr + 30)) * ramp + 2 * jitter)
            } else if let lunchWalk, lunchWalk.contains(t) {
                bpm = rhr + 50 + 3 * jitter
            } else {
                let hour = (t - plan.dayStart) / 3_600
                var offset: Double
                switch hour {
                case 0..<6: offset = 9
                case 6..<8: offset = 11
                case 8..<12: offset = 16
                case 12..<18: offset = 17
                case 18..<20: offset = 15
                case 20..<22: offset = 11
                default: offset = 10
                }
                if tense.contains(hour) { offset = 34 }
                if let after = lastWorkoutEnd(t), t - after < 3_600 { offset = max(offset, 22 - Double(t - after) / 3_600 * 6) }
                bpm = rhr + offset + 2 * sin(Double(t) / 1_500 * 2 * .pi) + 2.5 * jitter
            }
            hr.append(HRSample(ts: t, bpm: Int(bpm.rounded())))
            t += asleep ? asleepStep : awakeStep
        }

        var gravity: [GravitySample] = []
        var spans = plan.workouts.map { $0.start..<max($0.start, $0.end) }
        if let lunchWalk { spans.append(lunchWalk) }
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            var g = span.lowerBound
            var flip = false
            while g < min(span.upperBound, end) {
                gravity.append(GravitySample(ts: g, x: flip ? 0.3 : 0.0, y: 0.05, z: 0.95))
                flip.toggle()
                g += motionStep
            }
        }
        return (hr, gravity)
    }

    // MARK: Store

    /// Writes the streams for `plans` under `deviceId` (one `WhoopStore.insert` per day, idempotent on
    /// `(deviceId, ts)`), every reading at or before `until`. Returns the heart-rate rows written.
    @discardableResult
    static func insert(_ plans: [DayPlan], into store: WhoopStore, deviceId: String, until: Int) async throws -> Int {
        var written = 0
        for plan in plans where plan.dayStart <= until {
            let s = streams(for: plan, until: until)
            guard !s.hr.isEmpty else { continue }
            try await store.insert(Streams(hr: s.hr, gravity: s.gravity), deviceId: deviceId)
            written += s.hr.count
        }
        return written
    }
}
#endif
