#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

// One day of the strap's continuous heart rate, as the 1D detail draws it: 60-second store buckets
// (`repo.hrBuckets(from:to:bucketSeconds: 60)`, measured samples first, PPG-derived seconds filling the
// rest; `INTRADAY_AND_RANGES.md` §1.4) over the LOCAL calendar day, downsampled to at most `maxPoints`,
// with the night(s) and workouts that overlap the day as shaded spans. Strap-only: an imported day has
// no trace and the readout is nil (the data-source precedence does not apply to intraday reads).

extension BaselineReadouts {

    struct IntradayHeartRate: Equatable {
        struct Point: Identifiable, Equatable {
            /// Bucket start, unix seconds.
            let id: Int
            let date: Date
            /// The bucket's mean, low and high (`HRBucket.bpm` / `minBpm` / `maxBpm`).
            let bpm: Double
            let minBpm: Double
            let maxBpm: Double
            /// The weakest signal confidence in the bucket: 1 for measured seconds, under 1 for a
            /// PPG-derived stretch on a WHOOP 5.0 / MG (drawn lighter, never a different colour).
            let conf: Double
        }

        struct Span: Identifiable, Equatable {
            enum Kind: Equatable { case sleep, workout }
            let id: String
            let kind: Kind
            /// Clipped to the day.
            let start: Date
            let end: Date
            /// "Asleep", or the workout's sport.
            let label: String
        }

        let day: String
        /// Local midnight of `day` and of the day after: the chart's x domain.
        let dayStart: Date
        let dayEnd: Date
        /// Oldest first, at most `maxPoints`.
        let points: [Point]
        let sleep: [Span]
        let workouts: [Span]
        /// Over every bucket of the day before downsampling: lowest low, highest high, minute-weighted mean.
        let minBpm: Double
        let maxBpm: Double
        let avgBpm: Double
        /// Minutes of the day with a recorded heart rate.
        let coveredMinutes: Int

        /// Under four hours of heart rate: the day is captioned "partial day".
        var partial: Bool { coveredMinutes < IntensityMinutes.partialDayMinutes }

        /// A chart holds at most this many points (one per minute of a day).
        static let maxPoints = 1440
    }

    /// The trace for `day` from its 60-second `buckets` (`bucketSeconds` says what one row spans), the
    /// nights (`SleepNightBuilder.nights`, any order) and the workout rows that may overlap the day.
    /// nil when `buckets` is empty or the day key does not parse.
    static func intradayHeartRate(day: String, buckets: [HRBucket], bucketSeconds: Int = 60,
                                  nights: [SleepNight] = [], workouts: [WorkoutRow] = [],
                                  maxPoints: Int = IntradayHeartRate.maxPoints,
                                  calendar: Calendar = .current) -> IntradayHeartRate? {
        guard let start = localMidnight(of: day),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let sorted = buckets.filter { $0.bpm > 0 && $0.bpm.isFinite }.sorted { $0.ts < $1.ts }
        guard !sorted.isEmpty else { return nil }

        let lo = sorted.map(\.minBpm).min() ?? 0
        let hi = sorted.map(\.maxBpm).max() ?? 0
        let avg = sorted.map(\.bpm).reduce(0, +) / Double(sorted.count)
        let covered = sorted.count * max(1, bucketSeconds) / 60

        let points = downsample(sorted, to: maxPoints).map { b in
            IntradayHeartRate.Point(id: b.ts, date: Date(timeIntervalSince1970: TimeInterval(b.ts)),
                                    bpm: b.bpm, minBpm: b.minBpm, maxBpm: b.maxBpm, conf: b.conf)
        }

        func clip(_ a: Int, _ b: Int) -> (Date, Date)? {
            let s = max(a, Int(start.timeIntervalSince1970)), e = min(b, Int(end.timeIntervalSince1970))
            guard e > s else { return nil }
            return (Date(timeIntervalSince1970: TimeInterval(s)), Date(timeIntervalSince1970: TimeInterval(e)))
        }

        let sleepSpans: [IntradayHeartRate.Span] = nights.compactMap { n in
            guard let onset = n.onsetTs, let wake = n.wakeTs, let span = clip(onset, wake) else { return nil }
            return IntradayHeartRate.Span(id: "sleep|\(n.dayKey)", kind: .sleep, start: span.0, end: span.1, label: "Asleep")
        }.sorted { $0.start < $1.start }

        let workoutSpans: [IntradayHeartRate.Span] = workouts.compactMap { w in
            guard let span = clip(w.startTs, w.endTs) else { return nil }
            return IntradayHeartRate.Span(id: "workout|\(w.startTs)|\(w.sport)", kind: .workout, start: span.0, end: span.1,
                                          label: WorkoutSource.displaySport(w.sport))
        }.sorted { $0.start < $1.start }

        return IntradayHeartRate(day: day, dayStart: start, dayEnd: end, points: points, sleep: sleepSpans,
                                 workouts: workoutSpans, minBpm: lo, maxBpm: hi, avgBpm: avg, coveredMinutes: covered)
    }

    /// Consecutive buckets merged in groups so at most `maxPoints` remain: each group keeps its first
    /// start, the mean of means, the lowest low, the highest high and the weakest confidence. Returns
    /// the input when it already fits.
    static func downsample(_ buckets: [HRBucket], to maxPoints: Int) -> [HRBucket] {
        guard maxPoints > 0, buckets.count > maxPoints else { return buckets }
        let group = Int((Double(buckets.count) / Double(maxPoints)).rounded(.up))
        var out: [HRBucket] = []
        out.reserveCapacity(buckets.count / group + 1)
        var i = 0
        while i < buckets.count {
            let slice = buckets[i..<min(i + group, buckets.count)]
            let mean = slice.map(\.bpm).reduce(0, +) / Double(slice.count)
            out.append(HRBucket(ts: slice.first!.ts, bpm: mean,
                                minBpm: slice.map(\.minBpm).min() ?? mean,
                                maxBpm: slice.map(\.maxBpm).max() ?? mean,
                                conf: slice.map(\.conf).min() ?? 1))
            i += group
        }
        return out
    }

    /// The one VoiceOver sentence for a day's trace: "Heart rate on this day: 48 to 162 bpm, average 71;
    /// asleep 11:20 PM to 7:05 AM; one workout, Running." — the spans named so nothing shaded is lost.
    static func intradaySummary(_ t: IntradayHeartRate) -> String {
        var s = "Heart rate: \(Int(t.minBpm.rounded())) to \(Int(t.maxBpm.rounded())) bpm, average \(Int(t.avgBpm.rounded()))"
        if t.partial { s += " over \(durationText(minutes: Double(t.coveredMinutes))) of the day" }
        for n in t.sleep {
            s += "; asleep \(n.start.formatted(date: .omitted, time: .shortened)) to \(n.end.formatted(date: .omitted, time: .shortened))"
        }
        if !t.workouts.isEmpty {
            let names = t.workouts.map(\.label)
            s += "; \(t.workouts.count == 1 ? "one workout" : "\(t.workouts.count) workouts"), " + names.joined(separator: ", ")
        }
        return s + "."
    }

    /// The visible sentence under the 1D detail's Latest / Average / Low / High cells: only what those
    /// cells cannot say, the day's coverage and its spans, each once. "Partial day: 3h 10m of heart
    /// rate · asleep 11:20 PM–7:05 AM · one workout, Running." The low, mean and high stay in the cells
    /// (and in `intradaySummary`, the chart's VoiceOver sentence), never repeated beside them.
    static func intradayContext(_ t: IntradayHeartRate) -> String {
        let covered = durationText(minutes: Double(t.coveredMinutes))
        var parts = [t.partial ? "Partial day: \(covered) of heart rate" : "\(covered) of heart rate"]
        // One "asleep" clause for every span of the day: the night clipped at midnight reads "until",
        // the one starting that evening "from" ("asleep until 6:02 AM and from 11:13 PM").
        let spans = t.sleep.map { n -> String in
            let start = n.start.formatted(date: .omitted, time: .shortened)
            let end = n.end.formatted(date: .omitted, time: .shortened)
            if n.start <= t.dayStart { return "until \(end)" }
            if n.end >= t.dayEnd.addingTimeInterval(-60) { return "from \(start)" }
            return "\(start)–\(end)"
        }
        if !spans.isEmpty { parts.append("asleep " + spans.joined(separator: " and ")) }
        if !t.workouts.isEmpty {
            parts.append("\(t.workouts.count == 1 ? "one workout" : "\(t.workouts.count) workouts"), "
                         + t.workouts.map(\.label).joined(separator: ", "))
        }
        return parts.joined(separator: " · ") + "."
    }

    /// The trace for `day` through the repository: `repo.hrBuckets` at 60 s over the local day (strap
    /// only), the nights built from the funnel when `nights` is not passed, and the workout rows that
    /// reach back to the day. nil when the strap banked no heart rate for the day (DEBUG: unless
    /// `DemoHeartRate.enabled`, when a day the store has no trace for gets a synthetic one).
    @MainActor
    static func intradayHeartRate(_ repo: Repository, for day: String, nights: [SleepNight]? = nil,
                                  mode: BaselineDataSource = .current(), calendar: Calendar = .current,
                                  now: Date = Date()) async -> IntradayHeartRate? {
        guard let start = localMidnight(of: day),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let from = Int(start.timeIntervalSince1970), to = Int(end.timeIntervalSince1970) - 1
        let stored = await repo.hrBuckets(from: from, to: to, bucketSeconds: 60)
        let demo = stored.isEmpty && DemoHeartRate.enabled
        guard !stored.isEmpty || demo else { return nil }
        let nightList: [SleepNight]
        if let nights {
            nightList = nights
        } else {
            let habitual = await repo.habitualMidsleepSec()
            let sessions = await self.nights(repo, mode: mode, now: now)
            nightList = SleepNightBuilder.nights(sessions: sessions, days: days(repo, mode: mode), habitualMidsleepSec: habitual)
        }
        // Only the night ending on this morning and the one starting tonight can overlap the day.
        let nextKey = Baselines.cutoffKey(todayKey: day, carryDays: -1)
        let near = nightList.filter { $0.dayKey == day || $0.dayKey == nextKey }
        let back = BaselineRangeSeries.dayCount(from: day, to: Repository.localDayKey(now)) + 2
        let rows = await repo.workoutRows(days: max(3, back))
        let buckets = demo
            ? DemoHeartRate.buckets(from: from, to: min(to, Int(now.timeIntervalSince1970)), nights: near, workouts: rows)
            : stored
        return intradayHeartRate(day: day, buckets: buckets, nights: near, workouts: rows, calendar: calendar)
    }

    /// DEBUG-only screenshot aid: `-baseline.demoHeartRate YES` (UserDefaults' argument domain, like
    /// `-baseline.marketing`) gives a day with no stored heart rate a synthetic 60-second trace, so the
    /// UI tests can capture the Heart rate card and its 1D detail under `--demo-seed`, which seeds no
    /// heart-rate samples. Presentation only: nothing is written to the store, and the per-day records
    /// (`IntradayDayStore`: Intensity minutes, the heart-rate range series) never see it. Off, and the
    /// generator empty, in Release.
    enum DemoHeartRate {
        static let key = "baseline.demoHeartRate"

        static var enabled: Bool {
            #if DEBUG
            return UserDefaults.standard.bool(forKey: key)
            #else
            return false
            #endif
        }

        /// One bucket per minute over `[from, to]`: about 55 bpm inside the stored nights (00:00–06:45
        /// and from 23:15 when the day has none), a rise and fall to about 145 bpm across each workout,
        /// a slow daytime curve around 70 bpm otherwise, each with a small deterministic wobble.
        static func buckets(from: Int, to: Int, nights: [SleepNight], workouts: [WorkoutRow]) -> [HRBucket] {
            #if DEBUG
            guard to > from else { return [] }
            var asleep = nights.compactMap { n -> ClosedRange<Int>? in
                guard let onset = n.onsetTs, let wake = n.wakeTs, wake > onset else { return nil }
                return onset...wake
            }
            if asleep.isEmpty { asleep = [from...(from + 405 * 60), (from + 1395 * 60)...(from + 1440 * 60)] }
            let sessions = workouts.compactMap { w -> ClosedRange<Int>? in w.endTs > w.startTs ? w.startTs...w.endTs : nil }
            var out: [HRBucket] = []
            out.reserveCapacity((to - from) / 60 + 1)
            var ts = from - from % 60
            while ts <= to {
                let i = Double((ts - from) / 60)
                let wobble = 2.5 * sin(i / 7) + 1.5 * sin(i / 2.3)
                let bpm: Double
                if let w = sessions.first(where: { $0.contains(ts) }) {
                    let progress = Double(ts - w.lowerBound) / Double(max(1, w.upperBound - w.lowerBound))
                    bpm = 100 + 45 * sin(progress * .pi) + wobble
                } else if asleep.contains(where: { $0.contains(ts) }) {
                    bpm = 55 + wobble * 0.6
                } else {
                    let hour = i / 60
                    bpm = 64 + 10 * sin(max(0, min(1, (hour - 7) / 15)) * .pi) + wobble
                }
                out.append(HRBucket(ts: ts, bpm: bpm, minBpm: bpm - 3, maxBpm: bpm + 4))
                ts += 60
            }
            return out
            #else
            return []
            #endif
        }
    }
}
#endif
