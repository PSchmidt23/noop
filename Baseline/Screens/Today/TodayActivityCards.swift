#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

// Home's activity cards: Steps (always present), Calories (its own card after Last night) and Stress
// (hours, never a score). Each is a `TodayDetailCard` that opens its metric's detail; the words come
// from `TodayActivity.swift` (pure, tested). Bars and tracks only: never a ring.

// MARK: - Steps

/// The day's steps against the daily goal: the count as the hero with "of 8,000" beside it, ONE
/// horizontal goal track (never a ring), ONE line joining the goal status and the 7-day context
/// ("1,760 to go · 7‑day average 7,480"), the week's seven bars with the goal as a dashed tick, and the
/// source only when the count did not come from the strap ("From iPhone (Apple Health)"). Shown on every
/// day: a day nothing counted reads "–"; a history no source has ever counted (a WHOOP 4.0 on the bicep
/// without phone steps) says why and links to Settings › Apple Health instead. Opens the Steps detail.
struct StepsCard: View {
    let readout: BaselineReadouts.StepsReadout
    /// The daily goal (`ActivityGoals.stepGoal()`, Settings › Activity goals).
    let goal: Int
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    var body: some View {
        TodayDetailCard(title: StepsTile.title(isToday: isToday), accessory: AccuracyBadge(metric: "steps").map { AnyView($0) },
                        hint: TodayDetail.hint(.steps), onOpen: onOpen) {
            if readout.steps == nil && !readout.hasRecordedSource {
                noSource
            } else {
                StepsCardBody(readout: readout, goal: goal, isToday: isToday)
            }
        }
    }

    /// Nothing has ever counted a step: the dash, why, and (today) the way to the phone's count.
    @ViewBuilder private var noSource: some View {
        Text("–")
            .font(BaselineTheme.hero(36))
            .foregroundStyle(BaselineTheme.text)
            .accessibilityLabel("No steps recorded")
        Text(isToday ? StepsCardText.noSourceToday : "No steps recorded.")
            .font(BaselineTheme.caption)
            .foregroundStyle(BaselineTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if isToday {
            Divider().overlay(BaselineTheme.hairline)
            BaselineChevronRow(text: "Apple Health", systemImage: "heart.text.square",
                               accessibilityHint: "Opens Apple Health settings") { AppleHealthScreen() }
        }
    }
}

/// The Steps card's content, shared with the detail's 1D week view (`TodayStepsWeekView`).
struct StepsCardBody: View {
    let readout: BaselineReadouts.StepsReadout
    let goal: Int
    var isToday: Bool = true
    /// The ONE line under the track; off in the detail, whose own lines name the averages.
    var showsLine: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(BaselineReadouts.stepsText(readout.steps))
                    .font(BaselineTheme.hero(36))
                    .foregroundStyle(BaselineTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("of " + BaselineReadouts.stepsText(goal))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StepsCardText.spoken(steps: readout.steps, goal: goal))
            GoalTrack(fraction: readout.goalFraction(goal: goal), color: BaselineTheme.steps)
            if showsLine {
                Text(StepsCardText.line(steps: readout.steps, goal: goal, average7: readout.average7,
                                        observed7: readout.observed7, isToday: isToday))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StepsWeekBars(bars: readout.recent.map { StepsWeekBars.Bar(id: $0.day, value: $0.value) }, goal: goal)
            if readout.steps != nil, let source = Self.sourceCaption(readout) {
                Text(source)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where the count came from, only when it was not the strap's own counter (one source per day,
    /// never summed: strap → iPhone (Apple Health) → the strap's estimate → an import).
    static func sourceCaption(_ r: BaselineReadouts.StepsReadout) -> String? {
        switch r.source {
        case .phone: return "From iPhone (Apple Health)"
        case .estimate: return "Estimated from the strap's movement"
        case .imported: return "From an import"
        default: return nil
        }
    }
}

/// One flat horizontal track toward a goal (Steps): a `ringTrack` capsule filled in `color` to
/// `fraction`. Never a ring. Hidden from VoiceOver: the hero beside it already says "6,240 of 8,000".
struct GoalTrack: View {
    /// 0…1.
    let fraction: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BaselineTheme.ringTrack)
                if fraction > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(Self.height, geo.size.width * min(1, max(0, fraction))))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.6), value: fraction)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

/// The week ending on the day as seven small bars against the goal: a day at or over the goal in
/// `steps`, a day under it muted, a day with nothing counted an empty stub, and the goal as a dashed
/// hairline across them. One VoiceOver element: "Goal met on 4 of the last 7 days".
struct StepsWeekBars: View {
    struct Bar: Identifiable, Equatable {
        let id: String
        let value: Double?
    }

    let bars: [Bar]
    let goal: Int
    var height: CGFloat = 32
    /// The detail's week card spreads the seven bars across the card; Home's card keeps them compact.
    var fillsWidth = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bars' scale: the week's highest count or the goal, whichever is higher, so the tick is always
    /// inside the frame.
    private var top: Double { max(Double(goal), bars.compactMap(\.value).max() ?? 0, 1) }

    private func barHeight(_ b: Bar) -> CGFloat {
        guard let v = b.value, v > 0 else { return 4 }
        return max(4, height * CGFloat(v / top))
    }

    var body: some View {
        if fillsWidth { wide } else { compact }
    }

    /// Full-width bars (equal columns, 8pt apart) under a dashed goal rule across the card.
    private var wide: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(bars) { b in
                    let h = barHeight(b)
                    RoundedRectangle(cornerRadius: BaselineChartStyle.barRadius, style: .continuous)
                        .fill(fill(b))
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.5), value: h)
                }
            }
            Rectangle()
                .fill(.clear)
                .frame(height: 1)
                .overlay(
                    Line().stroke(BaselineTheme.steps.opacity(BaselineChartStyle.baselineOpacity),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
                .offset(y: -height * CGFloat(Double(goal) / top))
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StepsCardText.weekSummary(bars.map(\.value), goal: goal))
    }

    /// A horizontal hairline across its frame.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }

    private var compact: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(bars) { b in
                    let h = barHeight(b)
                    Capsule()
                        .fill(fill(b))
                        .frame(width: 10, height: h)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.5), value: h)
                }
            }
            // The goal tick: a dashed hairline at the goal's height across the bars.
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: CGFloat(bars.count) * 16 - 6, y: 0))
            }
            .stroke(BaselineTheme.steps.opacity(BaselineChartStyle.baselineOpacity),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: CGFloat(bars.count) * 16 - 6, height: 1)
            .offset(y: -height * CGFloat(Double(goal) / top))
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StepsCardText.weekSummary(bars.map(\.value), goal: goal))
    }

    private func fill(_ b: Bar) -> Color {
        guard let v = b.value else { return BaselineTheme.ringTrack }
        return v >= Double(goal) ? BaselineTheme.steps : BaselineTheme.steps.opacity(BaselineChartStyle.mutedBarOpacity)
    }
}

// MARK: - Calories

/// The day's energy as its own card: total = resting (Mifflin–St Jeor from the profile, credited all day
/// whether or not the strap was worn; today prorated to the clock) + active (the strap's heart-rate
/// estimate, else Apple Health's, never both). The total as the hero, one flat two-segment bar (resting
/// in `ringTrack`, active in `effort`), the split line, ONE context line on the active part against the
/// 30-day average (finished days only), and the line that asks for what is missing. The Low accuracy
/// badge in the header (its popover says it is an estimate). Opens the Calories detail.
struct CaloriesCard: View {
    let readout: BaselineReadouts.CaloriesReadout
    var isToday: Bool = true
    var onOpen: () -> Void = {}

    var body: some View {
        TodayDetailCard(title: CaloriesCardText.title(hasResting: readout.restingKcal != nil, isToday: isToday),
                        accessory: AnyView(CaloriesBadges()), hint: TodayDetail.hint(.calories), onOpen: onOpen) {
            CaloriesCardBody(readout: readout, isToday: isToday)
        }
    }

    /// Whether the card has anything to show: some active estimate, or a resting one from the profile.
    static func shows(_ r: BaselineReadouts.CaloriesReadout?) -> Bool { r?.hasFigure ?? false }
}

/// The Calories header's one pill, on Home's card and Trends' card alike: the accuracy badge, its tier
/// and name from `MetricAccuracy` ("calories", Low), its popover the card's own caveat ("Heart-rate
/// estimate; …", `CaloriesCardText.caveat`). The popover says it is an estimate, so no second "Estimate"
/// pill says it again (two pills stacked taller than the title at narrow widths and accessibility sizes).
struct CaloriesBadges: View {
    var body: some View {
        if let row = MetricAccuracy.lookup("calories") {
            AccuracyBadge(tier: row.tier, caveat: CaloriesCardText.caveat, name: row.name)
        }
    }
}

/// The Calories card's content, shared with the detail's 1D view (`TodayCaloriesDayView`).
struct CaloriesCardBody: View {
    let readout: BaselineReadouts.CaloriesReadout
    var isToday: Bool = true

    private var hero: Double? { readout.totalKcal ?? readout.activeKcal ?? readout.restingKcal }
    private var activeFromApple: Bool {
        switch readout.activeSource {
        case .appleHealth: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(BaselineReadouts.caloriesText(hero))
                    .font(BaselineTheme.hero(36))
                    .foregroundStyle(BaselineTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            if readout.restingKcal != nil, readout.activeKcal != nil {
                CaloriesSplitBar(activeShare: CaloriesCardText.activeShare(resting: readout.restingKcal,
                                                                           active: readout.activeKcal))
            }
            if let split = CaloriesCardText.split(resting: readout.restingKcal, active: readout.activeKcal,
                                                  activeFromAppleHealth: activeFromApple, isToday: isToday) {
                Text(split)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ctx = CaloriesCardText.activeContext(active: readout.activeKcal, average30: readout.activeAverage30,
                                                        isToday: isToday) {
                Text(ctx)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if readout.restingKcal == nil {
                Divider().overlay(BaselineTheme.hairline)
                BaselineChevronRow(text: CaloriesCardText.profileAsk, systemImage: "person",
                                   accessibilityHint: "Opens Profile") { SettingsProfileForm() }
            } else if readout.bodyAssumed, let height = readout.heightCm, let weight = readout.weightKg {
                Divider().overlay(BaselineTheme.hairline)
                BaselineChevronRow(text: CaloriesCardText.bodyLine(heightCm: height, weightKg: weight),
                                   systemImage: "person", accessibilityHint: "Opens Profile") { SettingsProfileForm() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Resting and active as one flat bar (resting in `ringTrack`, active in `effort`). Never a ring.
/// Hidden from VoiceOver: the split line under it says the same in words.
struct CaloriesSplitBar: View {
    /// Active's share of the total, 0…1.
    let activeShare: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let active = activeShare > 0 ? max(GoalTrack.height, w * activeShare) : 0
            HStack(spacing: 2) {
                Capsule().fill(BaselineTheme.ringTrack).frame(width: max(0, w - active - (active > 0 ? 2 : 0)))
                if active > 0 { Capsule().fill(BaselineTheme.effort).frame(width: active) }
            }
        }
        .frame(height: GoalTrack.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Stress

/// The day's Stress as time, never a score: "2 h elevated · 7 h calm · 2 h restored" (hours, the
/// scorer's grain), one flat stacked bar of those hours (moving hours a hatched stub at its end) and ONE
/// sentence against the person's own typical day. Judged against the person's calm daytime heart rate
/// (the personal lens); while that lens is still learning, or under three still hours were scored, the
/// day is not totalled: the curve and the one sentence say why. A day with no scored hour has no card
/// (`TodayScreen.content`). Low accuracy. Opens the Stress detail (curve, floor, peak, caveat).
struct StressCard: View {
    let stress: BaselineReadouts.StressDayReadout
    var isToday: Bool = true
    var now: Date = Date()
    var onOpen: () -> Void = {}

    var body: some View {
        TodayDetailCard(title: "Stress", accessory: AccuracyBadge(metric: "stress").map { AnyView($0) },
                        hint: TodayDetail.hint(.stressAvg), onOpen: onOpen) {
            StressHoursBody(stress: stress, isToday: isToday, now: now, showsCurveWhenUntotalled: true)
        }
    }
}

/// Headline, bar and sentence (or the curve and the sentence while the day cannot be totalled). Shared
/// by Home's card and the detail's 1D view.
struct StressHoursBody: View {
    let stress: BaselineReadouts.StressDayReadout
    var isToday: Bool = true
    var now: Date = Date()
    /// Draws the curve when the day is not totalled (Home); the detail always draws it itself.
    var showsCurveWhenUntotalled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stress.showsTotals {
                headline
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(StressCardText.headline(elevated: stress.elevatedHours, calm: stress.calmHours,
                                                                restored: stress.restoredHours, moving: stress.movingHours))
                StressHoursBar(restored: stress.restoredHours, calm: stress.calmHours,
                               elevated: stress.elevatedHours, moving: stress.movingHours)
            } else if showsCurveWhenUntotalled {
                StressCurveChart(points: stress.points, height: 100,
                                 accessibilitySummary: BaselineReadouts.stressSummary(stress))
            }
            Text(StressCardText.sentence(elevated: stress.elevatedHours, scoredHours: stress.scoredHours,
                                         typical: stress.typicalElevatedHours, learningDays: stress.learningDays,
                                         isToday: isToday, hour: Calendar.current.component(.hour, from: now)))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "**2 h** elevated · **7 h** calm · **2 h** restored · 1 h moving": the hour counts in semibold.
    /// Each "2 h elevated" is glued with no-break spaces, so a wrap falls only at a " · " and never
    /// leaves a lone "h" at the start of a line.
    private var headline: Text {
        let nbsp = "\u{00A0}"
        func hours(_ h: Int) -> String { StressCardText.hoursText(Double(h)).replacingOccurrences(of: " ", with: nbsp) }
        func bold(_ h: Int) -> Text { Text(hours(h)).fontWeight(.semibold) }
        let moving = stress.movingHours > 0 ? " · \(hours(stress.movingHours))\(nbsp)moving" : ""
        return Text("\(bold(stress.elevatedHours))\(nbsp)elevated · \(bold(stress.calmHours))\(nbsp)calm · \(bold(stress.restoredHours))\(nbsp)restored\(moving)")
    }
}

/// The scored hours as one flat stacked bar: restored, calm and elevated in three tones of `stress`
/// (light to full), the hours left out while moving as a hatched grey stub at the end. Hidden from
/// VoiceOver: the headline above it reads the same hours.
struct StressHoursBar: View {
    let restored: Int
    let calm: Int
    let elevated: Int
    let moving: Int

    /// The three state tones, light → full: restored, calm, elevated (the zone ramp's opacities).
    static let restoredTone = BaselineTheme.stress.opacity(0.30)
    static let calmTone = BaselineTheme.stress.opacity(0.60)
    static let elevatedTone = BaselineTheme.stress

    static let height: CGFloat = 12

    var body: some View {
        let segments: [(hours: Int, color: Color?)] = [(restored, Self.restoredTone), (calm, Self.calmTone),
                                                       (elevated, Self.elevatedTone), (moving, nil)]
        let total = segments.reduce(0) { $0 + $1.hours }
        GeometryReader { geo in
            let gaps = CGFloat(max(0, segments.filter { $0.hours > 0 }.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    if total > 0, s.hours > 0 {
                        let w = max(4, (geo.size.width - gaps) * CGFloat(s.hours) / CGFloat(total))
                        if let color = s.color {
                            RoundedRectangle(cornerRadius: BaselineChartStyle.barRadius, style: .continuous).fill(color).frame(width: w)
                        } else {
                            Hatch()
                                .stroke(BaselineTheme.inactive, lineWidth: 1)
                                .background(BaselineTheme.fill)
                                .clipShape(RoundedRectangle(cornerRadius: BaselineChartStyle.barRadius, style: .continuous))
                                .frame(width: w)
                        }
                    }
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    /// Diagonal hatching for the moving stub.
    private struct Hatch: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += 4
            }
            return p
        }
    }
}
#endif
