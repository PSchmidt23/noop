#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// One night as the Sleep screen shows it: the main-night group of a wake day, bridged into a single
/// onset → wake span, with stage totals, a stage timeline (absolute unix seconds) and the night's vitals.
/// A night belongs to the morning it ends on (`Repository.localDayKey` of its wake time), the same
/// convention NOOP's `SleepModel.navDays` uses to group blocks.
struct SleepNight: Identifiable {
    let dayKey: String
    let onsetTs: Int
    let wakeTs: Int
    /// Minutes asleep (light + deep + REM). Falls back to the day's total or the in-bed span when the
    /// night carries no stage totals.
    let asleepMin: Double
    let deepMin: Double
    let remMin: Double
    let lightMin: Double
    let awakeMin: Double
    /// True when per-stage minutes came from the session (segments or imported totals).
    let hasStageTotals: Bool
    /// 0–1 fraction.
    let efficiency: Double?
    let restingHr: Int?
    let avgHrv: Double?
    let respRateBpm: Double?
    let skinTempDevC: Double?
    /// On-device staging ran on sparse motion for at least one fragment of this night.
    let stagingSparse: Bool
    /// Stage timeline in absolute unix seconds, sorted by start. Empty for imported nights (totals only).
    let segments: [StageSegment]

    var id: String { dayKey }
    var onset: Date { Date(timeIntervalSince1970: TimeInterval(onsetTs)) }
    var wake: Date { Date(timeIntervalSince1970: TimeInterval(wakeTs)) }
    var inBedMin: Double { Double(wakeTs - onsetTs) / 60.0 }
    var hoursAsleep: Double { asleepMin / 60.0 }
    var hasVitals: Bool { restingHr != nil || avgHrv != nil || respRateBpm != nil || skinTempDevC != nil }
}

/// Pure derivation of `SleepNight`s from the repository's merged sleep blocks and daily rows.
enum SleepNightBuilder {

    /// Newest night first.
    static func nights(sessions: [CachedSleepSession], days: [DailyMetric], habitualMidsleepSec: Int?) -> [SleepNight] {
        let metricsByDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, newest in newest })
        let byDay = Dictionary(grouping: sessions) { s in
            Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        return byDay.compactMap { dayKey, blocks -> SleepNight? in
            build(dayKey: dayKey, blocks: blocks, metric: metricsByDay[dayKey], habitualMidsleepSec: habitualMidsleepSec)
        }
        .sorted { $0.wakeTs > $1.wakeTs }
    }

    private static func build(dayKey: String, blocks: [CachedSleepSession], metric: DailyMetric?,
                              habitualMidsleepSec: Int?) -> SleepNight? {
        let sorted = blocks.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
        guard !sorted.isEmpty else { return nil }

        // The same main-night selector NOOP's Sleep tab uses, so a biphasic night bridges and a nap
        // stays out. Fall back to the longest block if the selector yields nothing.
        var group = SleepView.mainNightGroup(sorted, habitualMidsleepSec: habitualMidsleepSec)
        if group.isEmpty, let longest = sorted.max(by: { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) }) {
            group = [longest]
        }
        guard !group.isEmpty else { return nil }
        let main = SleepView.mainNightSession(sorted, habitualMidsleepSec: habitualMidsleepSec)
            ?? group.max(by: { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) })
            ?? group[0]

        let onset = SleepModel.nightOnsetTs(group)
        let fragments = group.filter { $0.effectiveStartTs >= onset }
        guard let wake = fragments.map(\.endTs).max(), wake > onset else { return nil }

        var totals = SleepStageTotals.Minutes()
        var hasTotals = false
        var segments: [StageSegment] = []
        for frag in fragments {
            let decoded = AnalyticsEngine.decodeStages(frag.stagesJSON)
            if !decoded.isEmpty {
                for seg in decoded {
                    // Trim to the effective onset like NOOP does (#259) so an edited bedtime never
                    // draws bars before the night began.
                    let start = max(seg.start, frag.effectiveStartTs)
                    guard seg.end > start else { continue }
                    let mins = Double(seg.end - start) / 60.0
                    switch seg.stage.lowercased() {
                    case "wake", "awake": totals.awake += mins
                    case "light": totals.light += mins
                    case "deep": totals.deep += mins
                    case "rem": totals.rem += mins
                    default: continue
                    }
                    hasTotals = true
                    segments.append(StageSegment(start: start, end: seg.end, stage: seg.stage))
                }
            } else if let m = SleepStageTotals.minutes(fromStagesJSON: frag.stagesJSON) {
                totals.awake += m.awake; totals.light += m.light
                totals.deep += m.deep; totals.rem += m.rem
                hasTotals = true
            }
        }
        // Gaps between bridged fragments are time awake on the timeline (not added to the totals,
        // matching NOOP's merge).
        for (prev, next) in zip(fragments, fragments.dropFirst()) where next.effectiveStartTs > prev.endTs {
            segments.append(StageSegment(start: prev.endTs, end: next.effectiveStartTs, stage: "wake"))
        }
        segments.sort { $0.start < $1.start }

        let spanMin = Double(wake - onset) / 60.0
        let sessionEff = normalizedEfficiency(main.efficiency) ?? normalizedEfficiency(metric?.efficiency)
        let efficiency: Double?
        if hasTotals, totals.inBed > 0 {
            efficiency = totals.asleep / totals.inBed
        } else {
            efficiency = sessionEff
        }
        let asleep: Double
        if hasTotals, totals.asleep > 0 {
            asleep = totals.asleep
        } else if let t = metric?.totalSleepMin, t > 0 {
            asleep = t
        } else if let e = sessionEff {
            asleep = spanMin * e
        } else {
            asleep = spanMin
        }

        return SleepNight(
            dayKey: dayKey,
            onsetTs: onset,
            wakeTs: wake,
            asleepMin: asleep,
            deepMin: totals.deep,
            remMin: totals.rem,
            lightMin: totals.light,
            awakeMin: totals.awake,
            hasStageTotals: hasTotals,
            efficiency: efficiency,
            restingHr: main.restingHr ?? fragments.compactMap(\.restingHr).first ?? metric?.restingHr,
            avgHrv: main.avgHrv ?? fragments.compactMap(\.avgHrv).first ?? metric?.avgHrv,
            respRateBpm: metric?.respRateBpm,
            skinTempDevC: metric?.skinTempDevC,
            stagingSparse: fragments.contains { $0.stagingSparse == true },
            segments: segments)
    }

    /// Efficiency arrives as a 0–1 fraction from the on-device pipeline and as a percent on some import
    /// paths; normalise to a fraction.
    private static func normalizedEfficiency(_ e: Double?) -> Double? {
        guard let e, e > 0 else { return nil }
        return e > 1.5 ? e / 100.0 : e
    }
}

// MARK: - Formatting shared by the Sleep screens

enum SleepFormat {
    /// "7:24" for 444 minutes.
    static func hhmm(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// "11:42 PM" / "23:42" in the device locale.
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Mon, Sep 29" for the morning the night ended on.
    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func percent(_ fraction: Double?) -> String? {
        guard let fraction else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// "+32 min vs average" / "−18 min vs average" / "On your average".
    static func deltaText(asleepMin: Double, average: Double) -> String {
        let delta = Int((asleepMin - average).rounded())
        if abs(delta) < 5 { return "On your average" }
        let sign = delta > 0 ? "+" : "\u{2212}"
        return "\(sign)\(abs(delta)) min vs average"
    }
}
#endif
