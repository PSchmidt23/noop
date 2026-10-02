#if os(iOS)
import Foundation
import WhoopStore

/// Heart rate while asleep: the strap's one-minute means over a night's onset → wake, as the night
/// detail and the Home 1D sleep view draw them under the hypnogram. Strap-only: a `.dailyMetric` night
/// (CSV / Apple Health) has no times and no trace, so the builder returns nil and the card stays away.
/// The numbers are ONE-MINUTE MEANS (`repo.hrBuckets(from:to:bucketSeconds: 60)`, measured seconds first,
/// PPG-derived seconds filling the rest; `Research/INTRADAY_AND_RANGES.md` §1.4), never single samples:
/// a one-second low is noise, a one-minute low is a reading.
struct SleepHeartRate: Equatable {
    struct Point: Identifiable, Equatable {
        /// Bucket start, unix seconds.
        let id: Int
        let date: Date
        /// The minute's mean, low and high (`HRBucket.bpm` / `minBpm` / `maxBpm`).
        let bpm: Double
        let minBpm: Double
        let maxBpm: Double
        /// The weakest signal confidence in the minute: 1 for measured seconds, under 1 for a PPG-derived
        /// stretch on a WHOOP 5.0 / MG (drawn lighter, never another colour).
        let conf: Double
    }

    /// The night's key (the morning it ended on, `SleepNight.dayKey`).
    let dayKey: String
    let onset: Date
    let wake: Date
    /// Oldest first, at most `maxPoints`.
    let points: [Point]
    /// Lowest and highest one-minute mean and the mean over every recorded minute, before downsampling.
    let lowBpm: Double
    let highBpm: Double
    let averageBpm: Double
    /// Minutes of the night with a recorded heart rate, and minutes the night spans.
    let coveredMinutes: Int
    let spanMinutes: Int

    /// Share of the night with a recorded heart rate (0…1).
    var coverage: Double { spanMinutes > 0 ? min(1, Double(coveredMinutes) / Double(spanMinutes)) : 0 }
    /// Under `partialCoverage` of the night recorded: the card says so.
    var partial: Bool { coverage < Self.partialCoverage }
    /// Any PPG-derived minute (WHOOP 5.0 / MG): the chart draws it lighter and the caption names it.
    var hasDerivedStretch: Bool { points.contains { $0.conf < 1 } }

    /// A chart holds at most this many points (one per minute of a twelve-hour night).
    static let maxPoints = 720
    /// Coverage under which a night is captioned "partial".
    static let partialCoverage = 0.75
}

/// Pure derivation of `SleepHeartRate` from a night and its store buckets, plus the sentences the card
/// prints. `SleepHeartRateTests` pins the numbers.
enum SleepHeartRateBuilder {

    /// The trace for `night` from `buckets` (60-second store buckets by default; `bucketSeconds` says
    /// what one row spans). Rows outside onset → wake are dropped (a read may reach past either edge).
    /// nil for a night without times (`.dailyMetric`) or without a single bucket inside it.
    static func trace(night: SleepNight, buckets: [HRBucket], bucketSeconds: Int = 60,
                      maxPoints: Int = SleepHeartRate.maxPoints) -> SleepHeartRate? {
        guard let onsetTs = night.onsetTs, let wakeTs = night.wakeTs, wakeTs > onsetTs else { return nil }
        let inside = buckets
            .filter { $0.ts >= onsetTs && $0.ts < wakeTs && $0.bpm > 0 && $0.bpm.isFinite }
            .sorted { $0.ts < $1.ts }
        guard !inside.isEmpty else { return nil }

        let means = inside.map(\.bpm)
        let low = means.min() ?? 0
        let high = means.max() ?? 0
        let avg = means.reduce(0, +) / Double(means.count)
        let covered = inside.count * max(1, bucketSeconds) / 60

        let points = BaselineReadouts.downsample(inside, to: maxPoints).map { b in
            SleepHeartRate.Point(id: b.ts, date: Date(timeIntervalSince1970: TimeInterval(b.ts)),
                                 bpm: b.bpm, minBpm: b.minBpm, maxBpm: b.maxBpm, conf: b.conf)
        }
        return SleepHeartRate(dayKey: night.dayKey,
                              onset: Date(timeIntervalSince1970: TimeInterval(onsetTs)),
                              wake: Date(timeIntervalSince1970: TimeInterval(wakeTs)),
                              points: points, lowBpm: low, highBpm: high, averageBpm: avg,
                              coveredMinutes: covered, spanMinutes: (wakeTs - onsetTs) / 60)
    }

    /// The chart's ONE VoiceOver sentence: "Heart rate while asleep: lowest 46, average 52, highest
    /// 71 bpm, from 11:20 PM to 7:05 AM." plus the partial-night span when the strap missed part of it.
    static func summary(_ t: SleepHeartRate) -> String {
        var s = "Heart rate while asleep: lowest \(whole(t.lowBpm)), average \(whole(t.averageBpm)), "
            + "highest \(whole(t.highBpm)) bpm, from \(SleepFormat.clock(t.onset)) to \(SleepFormat.clock(t.wake))"
        if t.partial {
            s += ", recorded for \(BaselineReadouts.durationText(minutes: Double(t.coveredMinutes))) of the night"
        }
        return s + "."
    }

    /// The caption under the chart, the one place the trace's provenance is said: what a point is, how
    /// much of the night was recorded when that is not all of it, and that a lighter stretch is an
    /// optical estimate (WHOOP 5.0 / MG) when there is one.
    static func caption(_ t: SleepHeartRate) -> String {
        var parts: [String] = ["One-minute means while the strap was worn"]
        if t.partial {
            parts.append("partial night: \(BaselineReadouts.durationText(minutes: Double(t.coveredMinutes))) recorded")
        }
        if t.hasDerivedStretch {
            parts.append("the lighter stretch is an optical estimate")
        }
        return parts.joined(separator: " \u{00B7} ") + "."
    }

    private static func whole(_ v: Double) -> String { "\(Int(v.rounded()))" }

    /// The trace through the repository: `repo.hrBuckets` at 60 s over onset → wake (≤ ~600 rows for a
    /// ten-hour night; strap-only, the data-source precedence does not apply to intraday reads). nil for a
    /// night without times or when the strap banked no heart rate inside it.
    @MainActor
    static func trace(_ repo: Repository, night: SleepNight,
                      maxPoints: Int = SleepHeartRate.maxPoints) async -> SleepHeartRate? {
        guard let onset = night.onsetTs, let wake = night.wakeTs, wake > onset else { return nil }
        let buckets = await repo.hrBuckets(from: onset, to: wake, bucketSeconds: 60)
        return trace(night: night, buckets: buckets, bucketSeconds: 60, maxPoints: maxPoints)
    }
}
#endif
