#if os(iOS)
import SwiftUI
import Charts
import WhoopStore
import StrandAnalytics

// Home's way into the metric details: one tappable card shape (`TodayDetailCard`), one route table
// (`TodayDetail`: which `MetricDetailSpec` a card opens, with the custom 1D views Home owns), and ONE
// `navigationDestination(item:)` on the screen, so a card never nests a `NavigationLink` around the
// links it already holds (workout rows, "All workouts", the Progress chevron, an accuracy badge's
// popover). A card's tap is a plain gesture on the card; a control inside it keeps its own tap.

// MARK: - The tappable card

/// A `BaselineCard` whose header carries a trailing chevron and whose whole surface opens a detail
/// (`onOpen`). The header is the card's title in the same type `BaselineCard` draws, the accessory
/// (an `AccuracyBadge`, a date pill) beside the chevron. The title is ONE VoiceOver button ("Readiness,
/// button, Opens Readiness details"); the accessory and the content stay their own elements. With no
/// title (the ring tiles, whose `MetricRing` draws its own label) the chevron sits in the top trailing
/// corner as the button instead.
struct TodayDetailCard<Content: View>: View {
    var title: String? = nil
    var accessory: AnyView? = nil
    /// "Opens HRV details" (`TodayDetail.hint`).
    let hint: String
    var padding: CGFloat = BaselineTheme.cardPadding
    let onOpen: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        BaselineCard(padding: padding) {
            if let title {
                // Title, pill and chevron on one line while they fit; otherwise the pill drops under the
                // title (as `TrendsCardHeader` does), so a long title never truncates the pill
                // ("Intensity minutes" beside "Medium accuracy").
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleText(title).fixedSize()
                        Spacer(minLength: 8)
                        if let accessory { accessory.fixedSize() }
                        chevron.accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            titleText(title)
                            Spacer(minLength: 8)
                            chevron.accessibilityHidden(true)
                        }
                        if let accessory { accessory }
                    }
                }
            }
            content()
        }
        .overlay(alignment: .topTrailing) {
            if title == nil {
                chevron
                    .padding(padding)
                    .accessibilityLabel("Details")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(hint)
                    .accessibilityAction { onOpen() }
            }
        }
        .contentShape(BaselineTheme.cardShape)
        .onTapGesture { onOpen() }
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(BaselineTheme.label)
            .foregroundStyle(BaselineTheme.textSecondary)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint)
            .accessibilityAction { onOpen() }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(BaselineTheme.symbolSmall)
            .foregroundStyle(BaselineTheme.textTertiary)
    }
}

// MARK: - Routes

/// What each Home card opens. The screen holds the selected key and pushes `screen(_:day:)` through its
/// one `navigationDestination(item:)`; the cards only name the key.
enum TodayDetail {

    /// The VoiceOver hint on every card: "Opens HRV details".
    static func hint(_ key: MetricKey) -> String { "Opens \(key.name) details" }

    /// The range a detail opens on: the intraday keys open on the day they were tapped from, the daily
    /// columns on the week around it.
    static func initialRange(_ key: MetricKey) -> MetricRange {
        switch key {
        case .heartRate, .intensityMinutes, .stressAvg, .sleepDuration, .effort: return .day
        default: return .week
        }
    }

    /// The standard spec, with a 1D view where the day has more to show than one number: the night's
    /// stages and heart rate (sleep: the Sleep tab's own `SleepDetail.durationSpec`, so Home and the
    /// Sleep tab push one screen for a night), the day's workouts (effort), the Stress curve (stress),
    /// the week's seven bars against the goal (intensity minutes).
    static func spec(_ key: MetricKey) -> MetricDetailSpec {
        var spec = MetricDetailSpec.standard(key)
        switch key {
        case .sleepDuration:
            spec = SleepDetail.durationSpec()
        case .effort:
            spec.dayView = { day in AnyView(TodayWorkoutsDayView(day: day)) }
        case .stressAvg:
            spec.dayView = { day in AnyView(TodayStressDayView(day: day)) }
        case .intensityMinutes:
            spec.dayView = { day in AnyView(TodayIntensityWeekView(day: day)) }
        default:
            break
        }
        return spec
    }

    /// The day a card's detail ends on: the day the card's number belongs to. The nightly cards carry the
    /// newest night forward on a morning the strap has not synced yet ("Woke Thu, Oct 1" under today's
    /// HRV), so their detail ends on THAT morning; otherwise its 1D page would say "No HRV recorded" under
    /// the number Home just showed. Every other card shows the selected day itself.
    static func detailDay(_ key: MetricKey, selected: String, snapshot: TodaySnapshot?,
                          readiness: TodayReadinessScore) -> String {
        let shown: String?
        switch key {
        case .hrv: shown = snapshot?.hrv.flatMap { $0.value == nil ? nil : $0.day }
        case .rhr: shown = snapshot?.restingHr.flatMap { $0.value == nil ? nil : $0.day }
        case .sleepDuration, .sleepEfficiency: shown = snapshot?.sleep?.day
        case .readiness: shown = readiness.score?.day
        default: shown = nil
        }
        guard let shown, shown <= selected else { return selected }
        return shown
    }

    /// The pushed screen for `key`, its ranges ending on `day`.
    static func screen(_ key: MetricKey, day: String) -> some View {
        MetricDetailScreen(spec: spec(key), day: day, initialRange: initialRange(key))
    }

    /// Whether the Intensity classifier may use the profile: the person has entered a date of birth
    /// (`BaselineReadouts.ProfileSet`, the Fitness card's gate) or set a max heart rate by hand. Until
    /// then the seeded 30-year-old's Tanaka maximum is not used and the card asks for the age instead.
    /// Forwards to the one resolver in Components (`BaselineReadouts.intensityProfile`, over
    /// `IntensityMinutes.mayScore`), the predicate `IntradayDayStore` scores every day behind.
    @MainActor
    static func intensityProfile(_ profile: ProfileStore, entered: Bool = BaselineReadouts.ProfileSet.current()) -> ProfileStore? {
        BaselineReadouts.intensityProfile(profile, entered: entered)
    }
}

// MARK: - 1D: the day's workouts

/// The effort detail's day card: every workout started on `day` (each row opens its detail) and the
/// "All workouts" row, the list Home's Effort card shows the first three of.
struct TodayWorkoutsDayView: View {
    let day: String
    @EnvironmentObject private var repo: Repository
    @State private var rows: [WorkoutRow] = []
    @State private var loaded = false

    private struct LoadKey: Equatable {
        let seq: Int
        let day: String
    }

    var body: some View {
        BaselineCard(title: "Workouts") {
            if !loaded {
                ProgressView().tint(BaselineTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if rows.isEmpty {
                Text("No workouts recorded on this day.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(rows, id: \.startTs) { row in
                        NavigationLink {
                            WorkoutDetailScreen(row: row)
                        } label: {
                            TodayWorkoutRow(workout: TodayWorkout(row))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider().overlay(BaselineTheme.hairline)
            BaselineChevronRow(text: "All workouts", accessibilityHint: "Shows every recorded workout") { WorkoutsScreen() }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, day: day)) { await load() }
    }

    @MainActor
    private func load() async {
        let back = BaselineRangeSeries.dayCount(from: day, to: Repository.localDayKey(Date())) + 2
        let all = await repo.workoutRows(days: max(3, back))
        rows = all
            .filter { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) == day }
            .sorted { $0.startTs < $1.startTs }
        loaded = true
    }
}

// MARK: - 1D: the Stress curve

/// The stress detail's day card: the day's peak, curve and caption, what Home's Stress card draws
/// (`StressCardBody`) less its Average cell. The badge and the day's average ("This day … of 3") sit on
/// the detail's hero card, so neither is repeated here.
struct TodayStressDayView: View {
    let day: String
    @EnvironmentObject private var repo: Repository
    @State private var stress: BaselineReadouts.StressDayReadout?
    @State private var loaded = false

    private struct LoadKey: Equatable {
        let seq: Int
        let day: String
    }

    var body: some View {
        BaselineCard(title: "Through the day") {
            if !loaded {
                ProgressView().tint(BaselineTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                StressCardBody(stress: stress, isToday: day == Repository.localDayKey(Date()), showsAverage: false)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, day: day)) {
            stress = await BaselineReadouts.stressDay(repo, for: day)
            loaded = true
        }
    }
}

// MARK: - 1D: the Intensity-minutes week

/// The intensity detail's day card: the week `day` falls in as seven bars (credited minutes Monday →
/// Sunday, the days after `day` empty), the dashed goal pace (the weekly goal spread over seven days),
/// the week's track, the day's split and the basis the minutes were scored on. The badge and the caveat
/// sit on the detail's own cards, so neither is repeated here.
struct TodayIntensityWeekView: View {
    let day: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(BaselineDataSource.key) private var dataSourceRaw = ""
    @AppStorage(IntensityMinutes.goalKey) private var goal = IntensityMinutes.goalDefault
    @AppStorage(BaselineReadouts.ProfileSet.key) private var profileSet = false
    @State private var readout: BaselineReadouts.IntensityReadout?
    @State private var loaded = false

    private struct LoadKey: Equatable {
        let seq: Int
        let day: String
        let dataSource: String
        let goal: Int
        let hrMax: Int
        let entered: Bool
    }

    var body: some View {
        BaselineCard(title: "This week") {
            if !loaded {
                ProgressView().tint(BaselineTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if let r = readout, r.basis != .needsAge {
                TodayIntensityWeekChart(readout: r)
                IntensityTrack(readout: r)
                Text(Self.splitLine(r))
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.basis.caption)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(IntensityMinutes.Basis.needsAge.caption)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, day: day, dataSource: dataSourceRaw, goal: goal,
                          hrMax: profile.hrMax, entered: profileSet)) {
            readout = await BaselineReadouts.intensity(repo, profile: TodayDetail.intensityProfile(profile, entered: profileSet),
                                                       for: day, mode: BaselineDataSource.resolve(dataSourceRaw))
            loaded = true
        }
    }

    /// "Mon 28 Sep: 38 moderate · 37 vigorous (×2)" for the selected day, or that nothing was credited.
    static func splitLine(_ r: BaselineReadouts.IntensityReadout) -> String {
        let label = TodayFormat.dayLabel(r.day)
        guard r.creditedToday > 0 else { return "\(label): no minutes at moderate intensity or above" }
        return "\(label): \(r.splitText)"
    }
}

/// Seven bars for the readout's week (Monday first), the dashed goal pace across them. The bars after
/// the selected day are absent, never zero. One VoiceOver element.
struct TodayIntensityWeekChart: View {
    let readout: BaselineReadouts.IntensityReadout
    var height: CGFloat = 150

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let minutes: Int
    }

    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var bars: [Bar] {
        let keys = BaselineReadouts.dayKeys(from: readout.weekStart, to: readout.day)
        return zip(keys, readout.weekDays).enumerated().map { i, pair in
            Bar(id: pair.0, label: Self.weekdayLabels[min(i, 6)], minutes: pair.1)
        }
    }

    /// The weekly goal spread over seven days: the pace that reaches it.
    var goalPace: Double { Double(readout.weekGoal) / 7 }

    var body: some View {
        Chart {
            ForEach(bars) { b in
                BarMark(x: .value("Day", b.label), y: .value("Minutes", b.minutes))
                    .foregroundStyle(BaselineTheme.effort.opacity(BaselineChartStyle.barOpacity))
                    .cornerRadius(BaselineChartStyle.barRadius)
            }
            RuleMark(y: .value("Goal pace", goalPace))
                .foregroundStyle(BaselineTheme.effort.opacity(BaselineChartStyle.baselineOpacity))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("goal pace \(Int(goalPace.rounded())) a day")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                }
        }
        .chartXScale(domain: Self.weekdayLabels)
        .chartYScale(domain: 0...max(Double(readout.weekDays.max() ?? 0), goalPace) * 1.25)
        .chartYAxis { BaselineChartStyle.yAxis() }
        .chartXAxis {
            AxisMarks(values: Self.weekdayLabels) { _ in
                AxisValueLabel().foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartPlotStyle { $0.background(.clear) }
        .chartLegend(.hidden)
        .frame(height: height)
        .modifier(BaselineChartSummary(summary: summary))
    }

    /// "Intensity minutes this week: Mon 40, Tue 0, Wed 23; 63 of 150, goal pace 21 a day."
    private var summary: String {
        let days = bars.map { "\($0.label) \($0.minutes)" }.joined(separator: ", ")
        return "Intensity minutes this week: \(days); \(readout.weekCredited) of \(readout.weekGoal), goal pace \(Int(goalPace.rounded())) a day."
    }
}

/// The one horizontal track of the Intensity card (never a ring): a `ringTrack` capsule filled in
/// `effort` to the week's fraction of the goal, the label ("112 / 150 this week") above it. One
/// VoiceOver element that reads the label in words ("112 of 150 minutes this week"), never the slash.
struct IntensityTrack: View {
    /// 0…1.
    let fraction: Double
    let label: String
    /// What VoiceOver reads (`spokenLabel(_:)`).
    let spokenLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackHeight: CGFloat = 8

    init(readout r: BaselineReadouts.IntensityReadout) {
        fraction = r.weekFraction
        label = r.weekText
        spokenLabel = Self.spokenLabel(r)
    }

    /// "112 of 150 minutes this week": the visible "112 / 150" in words, as `ReadinessBar` says "72 of 100".
    static func spokenLabel(_ r: BaselineReadouts.IntensityReadout) -> String {
        "\(r.weekCredited) of \(r.weekGoal) minutes this week"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BaselineTheme.ringTrack)
                    Capsule()
                        .fill(BaselineTheme.effort)
                        .frame(width: max(Self.trackHeight, geo.size.width * min(1, max(0, fraction))))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.6), value: fraction)
                }
            }
            .frame(height: Self.trackHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}
#endif
