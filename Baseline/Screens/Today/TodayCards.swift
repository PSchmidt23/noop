#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Every card on Home opens its metric's detail (`TodayDetailCard`: a chevron in the header, the whole
// card tappable, `TodayDetail.hint` as the VoiceOver hint). A card names the key it opens through
// `onOpen`; the screen pushes the detail through its one `navigationDestination(item:)`.

// MARK: - Readiness

/// The first card of the day: the Readiness SCORE (NOOP's 0–100 composite for that morning) as a number
/// on a horizontal track (`ReadinessBar`), its tone, ONE drivers sentence from the readout, the accuracy
/// badge and the Progress chevron row once the HRV baseline has settled. A number and a bar, never a
/// ring. The week's HRV tier no longer lives here: it is the short phrase on the HRV ring tile
/// (`TodayReadiness.weekPhrase`), so two readiness ideas never compete on one card. The card opens the
/// Readiness detail; the Progress row keeps its own destination.
struct ReadinessCard: View {
    let readiness: TodayReadinessScore
    /// `ProgressSnapshot.hrvHeadline`, the sentence Progress prints for the persisted horizon; nil hides the row.
    let progressHeadline: String?
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    var body: some View {
        TodayDetailCard(title: "Readiness", accessory: accessory, hint: TodayDetail.hint(.readiness), onOpen: onOpen) {
            switch readiness {
            case .score(let r, let stamp):
                ReadinessBar(score: r.score, tone: r.tone, label: r.tone.label, context: Self.context(r, wokeStamp: stamp))
            case .calibrating(let n):
                // A short pill and a wrapping caption: the count is a sentence, never ellipsised in a
                // pill at accessibility sizes (the pattern the ring tiles and Progress use).
                BaselinePill(text: "Calibrating", color: BaselineTheme.textTertiary)
                Text(Self.calibratingLine(nights: n))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .stale(let day):
                BaselinePill(text: "Paused", color: BaselineTheme.textTertiary)
                Text("No HRV since \(TodayFormat.dayLabel(day)). Readiness returns with the next synced night.")
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            case .missing:
                Text(isToday ? "This morning's score arrives with the next sync." : "No score for this morning.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            if let progressHeadline {
                Divider().overlay(BaselineTheme.hairline)
                BaselineChevronRow(text: progressHeadline, systemImage: "chart.line.uptrend.xyaxis",
                                   accessibilityHint: "Opens Progress") { ProgressScreen() }
            }
        }
    }

    /// The literature's tier for a composite score, only once there is a score to qualify.
    private var accessory: AnyView? {
        guard readiness.score != nil, let badge = AccuracyBadge(metric: "readiness") else { return nil }
        return AnyView(badge)
    }

    /// "Readiness after 4 nights · 2 so far": the caption under the Calibrating pill.
    static func calibratingLine(nights n: Int) -> String {
        "Readiness after \(BaselineReadouts.readinessSeedNights) nights · \(n) so far"
    }

    /// The ONE context line under the bar: the readout's drivers sentence ("Lifted by heart rate
    /// variability (+6), held back by resting heart rate (−3).") when the night can be broken down,
    /// else what the score was read from and how settled its baseline is: "not yet usable" for the
    /// least-settled score (`.calibrating`: an export's first mornings, before four HRV nights), "still
    /// settling" while it builds, nothing more once it is trusted. A carried score is dated first
    /// ("Woke Mon 28 Sep · …"), the stamp every carried value on Home wears.
    static func context(_ r: BaselineReadouts.ReadinessScore, wokeStamp: String? = nil) -> String {
        let text: String
        if let s = r.driversSentence {
            text = s
        } else if r.confidence == .calibrating {
            text = "From that night's HRV, resting HR and sleep · baseline not yet usable"
        } else if r.confidence == .building {
            text = "From that night's HRV, resting HR and sleep · baseline still settling"
        } else {
            text = "From that night's HRV, resting HR and sleep"
        }
        guard let wokeStamp else { return text }
        return "\(wokeStamp) · \(text)"
    }
}

// MARK: - Rings

/// HRV or resting HR as one `MetricRing` in its own tile: the night's value on a gauge whose domain is
/// the funnel's baseline ± 3σ (`MetricRingScale.domain`), the band as a translucent arc, a baseline tick,
/// and ONE context sentence. A value carried from an earlier morning wears its date ("Woke Mon 28 Sep ·
/// …"); past `Baselines.vitalCarryDays` the numeral is "–", the ring is a bare track and the sentence
/// names the last night instead. Nothing here computes a baseline: `reading.state` is the funnel's.
/// The tile opens the metric's detail (the chevron sits in its top corner: the ring draws the label).
struct TodayRingTile: View {
    let title: String
    let unit: String
    let color: Color
    let cfg: MetricCfg
    let higherIsBetter: Bool
    let reading: TodayMetricReading?
    /// The selected day's key: a reading dated earlier is a carried value.
    let dayKey: String
    /// The week's HRV tier in short form (`TodayReadiness.weekPhrase`, HRV tile only), appended to the
    /// one context line so the seven-night reading sits beside the one-night delta it qualifies.
    var weekLine: String? = nil
    /// The VoiceOver hint of the tile's button ("Opens HRV details").
    var hint: String = ""
    var onOpen: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TodayDetailCard(hint: hint, padding: 16, onOpen: onOpen) {
            // The tiles stack at accessibility sizes (`TodayScreen.rings`), so the ring can take the
            // width the scaled numeral needs.
            MetricRing(value: reading?.value, domain: domain, color: color, label: title, unit: unit,
                       context: contextText, band: band, baseline: baseline, tone: tone,
                       size: dynamicTypeSize.isAccessibilitySize ? 168 : BaselineTheme.ringSize)
        }
    }

    /// The gauge's span; nil (track only) while the baseline is calibrating or the value is stale.
    private var domain: ClosedRange<Double>? {
        guard let r = reading, !r.isStale else { return nil }
        return MetricRingScale.domain(state: r.state, cfg: cfg)
    }

    private var band: ClosedRange<Double>? {
        guard let r = reading, !r.isStale, let low = r.bandLow, let high = r.bandHigh, low <= high else { return nil }
        return low...high
    }

    private var baseline: Double? {
        guard let r = reading, !r.isStale else { return nil }
        return r.baseline
    }

    /// The widget's exact sentence, plus the week phrase when the tile carries one (the widget never does).
    private var contextText: String {
        let text = Self.contextText(reading, unit: unit, dayKey: dayKey)
        guard let weekLine, let r = reading, !r.isStale else { return text }
        return "\(text) · \(weekLine)"
    }

    /// The ONE context sentence under a ring. Static so the widget publisher
    /// (`BaselineWidgetPublisher.contextText`) prints exactly these words and can never drift.
    static func contextText(_ r: TodayMetricReading?, unit: String, dayKey: String) -> String {
        guard let r else { return "Waiting for the first night" }
        if r.isStale { return "No night since \(TodayFormat.dayLabel(r.day))" }
        let text: String
        if r.state.usable, let d = r.deviation {
            let delta = abs(d.delta) < 0.5 ? "On your baseline"
                                           : "\(TodayFormat.signed(d.delta, unit: unit)) vs baseline"
            // `BaselineBand.positionPhrase`: the same words Trends and the morning summary use.
            text = r.band.positionPhrase.map { "\(delta) · \($0)" } ?? delta
        } else {
            text = "Baseline after \(Baselines.minNightsSeed) nights · \(r.state.nValid) so far"
        }
        // A carried (still fresh) value from an earlier morning is dated first.
        guard let stamp = TodayFormat.wokeStamp(day: r.day, todayKey: dayKey) else { return text }
        return "\(stamp) · \(text)"
    }

    /// inside → good; above / below → good or watch by the metric's direction; calibrating → tertiary.
    private var tone: Color {
        guard let r = reading, !r.isStale else { return BaselineTheme.textTertiary }
        switch r.band {
        case .inside: return BaselineTheme.good
        case .calibrating: return BaselineTheme.textTertiary
        case .above: return higherIsBetter ? BaselineTheme.good : BaselineTheme.watch
        case .below: return higherIsBetter ? BaselineTheme.watch : BaselineTheme.good
        }
    }
}

// MARK: - Heart rate

/// The day's continuous heart rate under the rings: the latest reading (the last one on a past day),
/// the day's low and high as three cells, the intraday trace as a compact sparkline
/// (`IntradayHRChart` without its sleep and workout shading, which the detail draws) and ONE caption
/// carrying the average and how much of the day it covers. Today's latest reading wears its clock time
/// ("Latest · 2:10 PM"), so a strap that has been off the wrist since the afternoon is never read as
/// current. Opens the Heart rate detail on its 1D view. A day without a trace (today before anything is
/// banked included) shows no card (`TodayScreen.content`): the overnight trace fills it from midnight.
struct HeartRateCard: View {
    let trace: BaselineReadouts.IntradayHeartRate
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    /// The sparkline's height; the detail draws the full 180pt chart.
    static let compactHeight: CGFloat = 72
    /// At most this many points on the sparkline.
    static let compactPoints = 360

    var body: some View {
        TodayDetailCard(title: "Heart rate", accessory: MetricDetailSpec.standard(.heartRate).badge.map { AnyView($0) },
                        hint: TodayDetail.hint(.heartRate), onOpen: onOpen) {
            BaselineStatRow {
                StatCell(label: Self.latestLabel(trace, isToday: isToday), value: Self.bpm(trace.points.last?.bpm ?? trace.avgBpm),
                         unit: "bpm", color: BaselineTheme.rhr)
                StatCell(label: "Low", value: Self.bpm(trace.minBpm), unit: "bpm")
                StatCell(label: "High", value: Self.bpm(trace.maxBpm), unit: "bpm")
            }
            IntradayHRChart(trace: Self.compact(trace), color: BaselineTheme.rhr, height: Self.compactHeight,
                            accessibilitySummary: BaselineReadouts.intradaySummary(trace))
            Text(Self.caption(trace, isToday: isToday))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func bpm(_ v: Double) -> String { "\(Int(v.rounded()))" }

    /// The first cell's label: "Latest · 2:10 PM" on today (the newest one-minute bucket's clock time,
    /// which can be hours old while the strap charges), "Last" on a past day, whose last reading is the
    /// end of that day.
    static func latestLabel(_ t: BaselineReadouts.IntradayHeartRate, isToday: Bool) -> String {
        guard isToday else { return "Last" }
        guard let last = t.points.last else { return "Latest" }
        return "Latest · " + last.date.formatted(date: .omitted, time: .shortened)
    }

    /// ONE line: the average, and the day's coverage when the strap recorded under four hours
    /// ("Average 71 bpm over 3h 10m of heart rate so far" / "Average 71 bpm through the day").
    static func caption(_ t: BaselineReadouts.IntradayHeartRate, isToday: Bool) -> String {
        let avg = "Average \(bpm(t.avgBpm)) bpm"
        guard t.partial else { return "\(avg) through the day" }
        let covered = BaselineReadouts.durationText(minutes: Double(t.coveredMinutes))
        return "\(avg) over \(covered) of heart rate" + (isToday ? " so far" : "")
    }

    /// The sparkline's trace: the same day window and extremes, the points thinned to `compactPoints`
    /// (consecutive runs averaged) and the sleep / workout spans dropped, so the small chart is one line.
    static func compact(_ t: BaselineReadouts.IntradayHeartRate, maxPoints: Int = compactPoints) -> BaselineReadouts.IntradayHeartRate {
        var points = t.points
        if points.count > maxPoints, maxPoints > 0 {
            let group = Int((Double(points.count) / Double(maxPoints)).rounded(.up))
            var thinned: [BaselineReadouts.IntradayHeartRate.Point] = []
            thinned.reserveCapacity(points.count / group + 1)
            var i = 0
            while i < points.count {
                let slice = points[i..<min(i + group, points.count)]
                let first = slice.first!
                thinned.append(.init(id: first.id, date: first.date,
                                     bpm: slice.map(\.bpm).reduce(0, +) / Double(slice.count),
                                     minBpm: slice.map(\.minBpm).min() ?? first.minBpm,
                                     maxBpm: slice.map(\.maxBpm).max() ?? first.maxBpm,
                                     conf: slice.map(\.conf).min() ?? first.conf))
                i += group
            }
            points = thinned
        }
        return .init(day: t.day, dayStart: t.dayStart, dayEnd: t.dayEnd, points: points, sleep: [], workouts: [],
                     minBpm: t.minBpm, maxBpm: t.maxBpm, avgBpm: t.avgBpm, coveredMinutes: t.coveredMinutes)
    }
}

// MARK: - Intensity minutes

/// The day's Intensity minutes under Steps: the credited minutes as the hero ("23 min" · "today"), ONE
/// horizontal track for the week against the goal ("112 / 150 this week", never a ring) and ONE caption
/// with the day's split or why there is none. Opens the Intensity minutes detail on its week view.
/// Without an age or a max heart rate nothing is scored: the card says so and its row opens Settings
/// instead of a detail (there is no reading to detail).
struct IntensityCard: View {
    let readout: BaselineReadouts.IntensityReadout?
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    var body: some View {
        if let r = readout, r.basis != .needsAge {
            TodayDetailCard(title: "Intensity minutes", accessory: MetricDetailSpec.standard(.intensityMinutes).badge.map { AnyView($0) },
                            hint: TodayDetail.hint(.intensityMinutes), onOpen: onOpen) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(r.creditedToday) min")
                        .font(BaselineTheme.hero(36))
                        .foregroundStyle(BaselineTheme.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(isToday ? "today" : "this day")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                IntensityTrack(readout: r)
                Text(Self.caption(r, isToday: isToday))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            BaselineCard(title: "Intensity minutes") {
                Text("Minutes at moderate and vigorous intensity count toward a weekly goal once your max heart rate is known.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(BaselineTheme.hairline)
                BaselineChevronRow(text: IntensityMinutes.Basis.needsAge.caption, systemImage: "person",
                                   accessibilityHint: "Opens Settings") { SettingsScreen() }
            }
        }
    }

    /// ONE caption under the track: the day's split ("15 moderate · 8 vigorous, counted double"), "from workouts
    /// only" for an imported day, "partial day" when the strap recorded under four hours of a past day,
    /// or why nothing was credited.
    static func caption(_ r: BaselineReadouts.IntensityReadout, isToday: Bool) -> String {
        if r.creditedToday > 0 {
            var line = r.splitText
            if r.basis == .workoutsOnly { line += " · from workouts only" }
            else if r.partialDay, !isToday { line += " · partial day" }
            return line
        }
        if isToday { return "Builds through the day as the strap records moderate and vigorous minutes." }
        if r.scoredMinutes == 0 { return "No heart rate recorded on this day." }
        if r.partialDay { return "No minutes at moderate intensity or above · partial day" }
        return "No minutes at moderate intensity or above."
    }
}

// MARK: - Signals

/// The early-warning card, directly under Readiness and only on today, when `TodaySignals.build` found
/// something to say: one calm sentence per signal under a watch-coloured pill, and a single "How this
/// is computed" disclosure listing each signal's method. The screen omits the card entirely when the
/// list is empty, so a quiet morning shows no "all clear" either. The one card on Home with no detail.
struct SignalsCard: View {
    let signals: TodaySignals
    @State private var showMethod = false

    var body: some View {
        BaselineCard(title: "Signals") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(signals.signals) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        BaselinePill(text: s.pill, color: BaselineTheme.watch)
                        Text(s.sentence)
                            .font(BaselineTheme.body)
                            .foregroundStyle(BaselineTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                DisclosureGroup(isExpanded: $showMethod) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(signals.signals) { s in
                            Text(s.method)
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("How this is computed")
                        .font(BaselineTheme.caption.weight(.semibold))
                        .foregroundStyle(BaselineTheme.accent)
                }
                .tint(BaselineTheme.textTertiary)
            }
        }
    }
}

// MARK: - The night

/// The night leading into the selected morning: the duration numeral, the efficiency cell, the stage
/// bar and one line against the 30-night average. "Last night" on today, "Night" on an earlier day. A
/// night older than the selected morning wears its date as the accessory pill. A flat numeral and a bar,
/// never a ring: the sleep ring lives on the Sleep tab. Opens the Sleep detail on the night (its stages
/// and heart rate asleep).
struct LastNightCard: View {
    let sleep: TodaySleepReading?
    /// The selected day's key.
    let dayKey: String
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    var body: some View {
        TodayDetailCard(title: isToday ? "Last night" : "Night", accessory: accessory,
                        hint: TodayDetail.hint(.sleepDuration), onOpen: onOpen) {
            if let s = sleep {
                // One element: "6h 42m asleep, Efficiency, 92 %" instead of three swipes. The
                // efficiency cell trails the numeral while the row fits; at larger type it drops under it,
                // so "6h 49m" never breaks across two lines.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        durationLine(s)
                        Spacer(minLength: 8)
                        efficiencyCell(s)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) { durationLine(s) }
                        efficiencyCell(s)
                    }
                }
                .accessibilityElement(children: .combine)
                if s.hasStages {
                    TodayStageBar(stages: s.stages)
                }
                Text(averageLine(s))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(isToday ? "No night recorded yet." : "No night recorded.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
        }
    }

    @ViewBuilder private func durationLine(_ s: TodaySleepReading) -> some View {
        Text(BaselineReadouts.durationText(minutes: s.totalMin))
            .font(BaselineTheme.hero(36))
            .foregroundStyle(BaselineTheme.text)
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
        Text("asleep")
            .font(BaselineTheme.headline)
            .foregroundStyle(BaselineTheme.textSecondary)
    }

    @ViewBuilder private func efficiencyCell(_ s: TodaySleepReading) -> some View {
        if let e = s.efficiencyPct {
            StatCell(label: "Efficiency", value: "\(Int(e.rounded()))%")
                .fixedSize()
        }
    }

    /// Only when the night is older than the selected morning, so a carried night says so.
    private var accessory: AnyView? {
        guard let s = sleep, let stamp = TodayFormat.wokeStamp(day: s.day, todayKey: dayKey) else { return nil }
        return AnyView(BaselinePill(text: stamp, color: BaselineTheme.textTertiary))
    }

    /// The Sleep tab's average and wording: `BaselineReadouts.sleepAverage30(before:in:)`, "30-night average".
    private func averageLine(_ s: TodaySleepReading) -> String {
        guard let avg = s.avg30Min else {
            return "Your 30\u{2011}night average appears after \(BaselineReadouts.sleepAverageMinNights) nights"
        }
        if let delta = BaselineReadouts.signedDurationText(minutes: s.totalMin - avg) {
            return "\(delta) vs your 30\u{2011}night average"
        }
        return "On your 30\u{2011}night average"
    }
}

/// Slim proportional bar of deep / REM / light / awake. Keeps its explicit height: the card stack is lazy
/// and the bar measures itself with a `GeometryReader`.
struct TodayStageBar: View {
    let stages: [TodayStage]

    var body: some View {
        let total = stages.reduce(0) { $0 + $1.minutes }
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(stages) { s in
                    if total > 0, s.minutes > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BaselineTheme.stageColor(s.id))
                            .frame(width: max(2, geo.size.width * s.minutes / total - 2))
                    }
                }
            }
        }
        .frame(height: 10)
        // The split exists only as colour; VoiceOver gets it as "Sleep stages: Deep 1h 12m, REM 1h 40m, ...".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
        .accessibilityValue(stages.filter { $0.minutes > 0 }
            .map { "\(BaselineTheme.stageName($0.id)) \(BaselineReadouts.durationText(minutes: $0.minutes))" }
            .joined(separator: ", "))
    }
}

// MARK: - Effort

/// The day's effort and its workouts (at most three rows; the chevron row opens the whole list). Each
/// workout row pushes `WorkoutDetailScreen` (resolved by the row's start, the only key `TodayWorkout`
/// carries). The effort number is `BaselineReadouts.effortText`, the same rendering the Workouts screens
/// use. Calories have their own card (`CaloriesCard`), so no energy figure is printed here. "All
/// workouts" is the visible label of the last chevron row (a UI-test anchor). The card opens the Effort
/// detail (its 1D view is the day's workouts).
struct EffortCard: View {
    let effort: Double?
    let workouts: [TodayWorkout]
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    /// Rows shown inline before the list takes over.
    static let maxRows = 3

    var body: some View {
        TodayDetailCard(title: "Effort", hint: TodayDetail.hint(.effort), onOpen: onOpen) {
            BaselineStatRow {
                StatCell(label: isToday ? "Effort so far" : "Effort", value: BaselineReadouts.effortText(effort),
                         unit: BaselineReadouts.effortUnit, color: BaselineTheme.effort)
                // The sentence below already says when there are none; a "Workouts 0" cell would say it twice.
                if !workouts.isEmpty {
                    StatCell(label: "Workouts", value: "\(workouts.count)")
                }
            }
            if workouts.isEmpty {
                Text(emptyLine)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts.prefix(Self.maxRows)) { w in
                        NavigationLink {
                            WorkoutDetailScreen(startTs: w.id, sport: w.sport)
                        } label: {
                            TodayWorkoutRow(workout: w)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if workouts.count > Self.maxRows {
                    Text("\(workouts.count - Self.maxRows) more in All workouts")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                }
            }
            Divider().overlay(BaselineTheme.hairline)
            BaselineChevronRow(text: "All workouts", accessibilityHint: "Shows every recorded workout") { WorkoutsScreen() }
        }
    }

    private var emptyLine: String {
        if effort == nil {
            return isToday ? "Builds through the day as the strap records." : "Nothing recorded on this day."
        }
        return isToday ? "No workouts recorded yet today." : "No workouts recorded."
    }
}

struct TodayWorkoutRow: View {
    let workout: TodayWorkout

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sportSymbol(workout.sport))
                .font(BaselineTheme.symbol)
                .foregroundStyle(BaselineTheme.effort)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(WorkoutSource.displaySport(workout.sport))
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.text)
                .lineLimit(1)
            Spacer()
            Text(BaselineReadouts.durationText(seconds: workout.durationS))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
            if let hr = workout.avgHr {
                Text("\(hr) bpm")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.rhr)
            }
            Image(systemName: "chevron.right")
                .font(BaselineTheme.symbolSmall)
                .foregroundStyle(BaselineTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
#endif
