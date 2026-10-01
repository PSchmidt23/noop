#if os(iOS)
import Foundation
import WhoopStore
import StrandAnalytics

/// One night as the Sleep screen shows it. Keyed by the morning it ends on (`Repository.localDayKey`
/// of the wake time, the same convention NOOP's `SleepModel.navDays` uses to group blocks).
///
/// Two sources, one shape:
/// - `.session`: the day's main-night group of `CachedSleepSession` blocks, bridged into one onset → wake
///   span with stage totals, a stage timeline (absolute unix seconds) and the night's vitals.
/// - `.dailyMetric`: a day that has sleep in `DailyMetric` but no session (seeded, CSV- or Apple-Health-
///   imported data). Totals, efficiency and vitals only; no bed/wake times and no timeline.
struct SleepNight: Identifiable {
    enum Source { case session, dailyMetric }

    let dayKey: String
    let source: Source
    /// Bed / wake as unix seconds. nil for `.dailyMetric` nights.
    let onsetTs: Int?
    let wakeTs: Int?
    /// Minutes asleep (light + deep + REM), with fallbacks when the source carries no stage totals.
    let asleepMin: Double
    let deepMin: Double
    let remMin: Double
    let lightMin: Double
    let awakeMin: Double
    /// True when per-stage minutes are known (segments, imported totals, or the daily row's stage columns).
    let hasStageTotals: Bool
    /// 0–1 fraction.
    let efficiency: Double?
    let restingHr: Int?
    let avgHrv: Double?
    let respRateBpm: Double?
    let skinTempDevC: Double?
    /// On-device staging ran on sparse motion for at least one fragment of this night.
    let stagingSparse: Bool
    /// Stage timeline in absolute unix seconds, sorted by start. Empty when the night has no timeline.
    let segments: [StageSegment]

    var id: String { dayKey }
    /// Local midnight of the morning the night ended on. Drives labels, sorting and the bar chart for
    /// both sources, so a session night and a daily-row night render and order identically.
    var dayDate: Date { SleepFormat.dayDate(dayKey) }
    var onset: Date? { onsetTs.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var wake: Date? { wakeTs.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var hoursAsleep: Double { asleepMin / 60.0 }
    var hasTimeline: Bool { !segments.isEmpty && onsetTs != nil && wakeTs != nil }
    var hasVitals: Bool { restingHr != nil || avgHrv != nil || respRateBpm != nil || skinTempDevC != nil }
}

/// Pure derivation of `SleepNight`s from the repository's merged sleep blocks and daily rows.
enum SleepNightBuilder {

    /// Newest night first. Every day with a session group becomes a `.session` night; every other day whose
    /// `DailyMetric` carries sleep becomes a `.dailyMetric` night, so the hero, bars and list never go
    /// empty while the Today tab shows sleep from the same daily rows.
    static func nights(sessions: [CachedSleepSession], days: [DailyMetric], habitualMidsleepSec: Int?) -> [SleepNight] {
        let metricsByDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, newest in newest })
        let byDay = Dictionary(grouping: sessions) { s in
            Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        var out: [SleepNight] = byDay.compactMap { dayKey, blocks -> SleepNight? in
            build(dayKey: dayKey, blocks: blocks, metric: metricsByDay[dayKey], habitualMidsleepSec: habitualMidsleepSec)
        }
        let covered = Set(out.map(\.dayKey))
        for metric in days where !covered.contains(metric.day) {
            if let night = build(fromDaily: metric) { out.append(night) }
        }
        return out.sorted { $0.dayKey > $1.dayKey }
    }

    // MARK: Session-backed night

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

        // A session with no stage payload at all still gets the daily row's stage columns.
        if !hasTotals, let metric, let daily = dailyStageMinutes(metric) {
            totals = daily
            hasTotals = true
        }

        let spanMin = Double(wake - onset) / 60.0
        let sessionEff = normalizedEfficiency(main.efficiency) ?? normalizedEfficiency(metric?.efficiency)
        let efficiency: Double?
        if hasTotals, totals.inBed > 0, totals.awake > 0 || sessionEff == nil {
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
            source: .session,
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

    // MARK: Daily-row fallback night

    /// A night from a `DailyMetric` alone: totals from `totalSleepMin` / the stage columns, efficiency
    /// normalised, awake minutes derived from efficiency (in-bed − asleep) when possible. nil when the
    /// row carries no sleep at all.
    static func build(fromDaily metric: DailyMetric) -> SleepNight? {
        let stages = dailyStageMinutes(metric)
        let total = (metric.totalSleepMin ?? 0) > 0 ? metric.totalSleepMin! : (stages?.asleep ?? 0)
        guard total > 0 else { return nil }
        let efficiency = normalizedEfficiency(metric.efficiency)
        var totals = stages ?? SleepStageTotals.Minutes()
        if let e = efficiency, e > 0, e < 1 {
            totals.awake = max(0, total / e - total)
        }
        return SleepNight(
            dayKey: metric.day,
            source: .dailyMetric,
            onsetTs: nil,
            wakeTs: nil,
            asleepMin: total,
            deepMin: totals.deep,
            remMin: totals.rem,
            lightMin: totals.light,
            awakeMin: totals.awake,
            hasStageTotals: stages != nil,
            efficiency: efficiency,
            restingHr: metric.restingHr,
            avgHrv: metric.avgHrv,
            respRateBpm: metric.respRateBpm,
            skinTempDevC: metric.skinTempDevC,
            stagingSparse: false,
            segments: [])
    }

    /// The daily row's deep / REM / light columns as stage minutes, nil when all are absent or zero.
    private static func dailyStageMinutes(_ metric: DailyMetric) -> SleepStageTotals.Minutes? {
        let deep = metric.deepMin ?? 0, rem = metric.remMin ?? 0, light = metric.lightMin ?? 0
        guard deep + rem + light > 0 else { return nil }
        return SleepStageTotals.Minutes(awake: 0, light: light, deep: deep, rem: rem)
    }

    /// Efficiency arrives as a 0–1 fraction from the on-device pipeline and as a percent on import and
    /// seed paths; normalise to a fraction.
    private static func normalizedEfficiency(_ e: Double?) -> Double? {
        guard let e, e > 0 else { return nil }
        return e > 1.5 ? e / 100.0 : e
    }
}

// MARK: - Formatting shared by the Sleep screens

enum SleepFormat {
    private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Local midnight for a "yyyy-MM-dd" day key (today if the key does not parse).
    static func dayDate(_ key: String) -> Date {
        dayKeyParser.date(from: key) ?? Calendar.current.startOfDay(for: Date())
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

    /// "+32 min vs average" / "−1h 05m vs average" / "On your average". The number and the steady
    /// threshold are `BaselineReadouts.signedDurationText`'s, the ones Today's sleep card prints.
    static func deltaText(asleepMin: Double, average: Double) -> String {
        guard let delta = BaselineReadouts.signedDurationText(minutes: asleepMin - average) else {
            return "On your average"
        }
        return "\(delta) vs average"
    }
}
#endif
