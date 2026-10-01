#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import WhoopStore

/// One session, pushed from the Workouts list or Today's effort card: when it happened, duration and
/// heart rate, its effort, calories when recorded, the heart-rate zone split, and the heart-rate trace
/// over the session window.
///
/// The zone split prefers the row's imported percentages and otherwise bins the strap's own samples
/// with the profile's zones (`repo.workoutZoneMinutes`), as NOOP's `WorkoutDetailView` does, because
/// only a CSV import writes `zonesJSON`; the card is hidden only when neither exists.
///
/// Today does not hold the `WorkoutRow`, so `init(startTs:sport:)` resolves it from the same
/// `repo.workoutRows` query Today runs, keyed on start AND sport: a start alone is not unique in the
/// merged list (an import can carry two sports from one instant). The list already holds the row and
/// passes it with `init(row:)`.
struct WorkoutDetailScreen: View {
    private enum Source {
        case row(WorkoutRow)
        /// `sport` nil only for a caller that has no sport to pass; then the first row at that start wins.
        case lookup(startTs: Int, sport: String?)
    }

    private let source: Source
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var row: WorkoutRow?
    @State private var resolved = false
    @State private var zones: WorkoutZoneSplit?
    @State private var buckets: [HRBucket] = []
    @State private var traceLoaded = false

    /// Reload key: every changed refresh, plus the profile fields `hrZoneSet` reads, so a max-HR or
    /// zone change in Settings re-bins a derived split when the person comes back to this screen.
    private struct LoadKey: Hashable {
        let seq: Int
        let hrMax: Int
        let zoneThresholds: [Int]
    }

    init(row: WorkoutRow) {
        source = .row(row)
        _row = State(initialValue: row)
    }

    /// Today's entry: the row's start and its stored sport key (`WorkoutRow.sport`, not the display
    /// name). `sport` defaults to nil so an older call site still compiles, but every caller that has
    /// the sport should pass it; without it two sessions sharing a start resolve to the same detail.
    init(startTs: Int, sport: String? = nil) {
        source = .lookup(startTs: startTs, sport: sport)
    }

    var body: some View {
        // The sport is named once, in the header card; the title stays "Workout" so it is not said twice.
        BaselineScreen(title: "Workout") {
            if let row {
                let item = WorkoutItem(row: row)
                WorkoutHeaderCard(item: item)
                WorkoutSessionCard(item: item)
                if let zones {
                    WorkoutZonesCard(split: zones)
                }
                WorkoutTraceCard(item: item, buckets: buckets, loaded: traceLoaded)
            } else if resolved {
                BaselineCard {
                    BaselineEmptyState(icon: "figure.run",
                                       title: "Workout not found",
                                       message: "This session is no longer in the store. Pull down on Today to refresh.")
                }
            } else {
                // Until the row is resolved, the same spinner Trends and Progress show.
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, hrMax: profile.hrMax, zoneThresholds: profile.hrZoneThresholds)) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        if case .lookup(let ts, let sport) = source {
            // Today lists workouts started today from `workoutRows(days: 2)`; a day wider still finds
            // the row after midnight has passed while the detail was open.
            row = await repo.workoutRows(days: 3).first { $0.startTs == ts && (sport == nil || $0.sport == sport) }
        }
        resolved = true
        guard let row else { return }
        zones = await zoneSplit(for: row)
        buckets = await repo.workoutHrBuckets(from: row.startTs, to: row.endTs, source: row.source)
        traceLoaded = true
    }

    /// The imported split when the row carries one, else the strap's samples over the window binned
    /// with the profile's zones; nil when the window has no heart rate either, which hides the card.
    /// Reads the same device ids as `workoutHrBuckets`, so the split and the trace describe one strap.
    @MainActor
    private func zoneSplit(for row: WorkoutRow) async -> WorkoutZoneSplit? {
        if let imported = WorkoutsModel.zoneMinutes(row) {
            return WorkoutZoneSplit(minutes: imported, origin: .imported)
        }
        guard let derived = await repo.workoutZoneMinutes(from: row.startTs, to: row.endTs,
                                                          zoneSet: profile.hrZoneSet, source: row.source),
              derived.count == 5 else { return nil }
        let basis = WorkoutsModel.zoneBasis(hasCustomZones: profile.hasCustomHRZones,
                                            hrMaxOverride: profile.hrMaxOverride,
                                            hrMax: profile.hrMax)
        return WorkoutZoneSplit(minutes: derived, origin: .derived(basis))
    }
}

// MARK: - Cards

/// Sport, date and the session's time window, with the duration as the one hero numeral (`hero(36)`),
/// said here and nowhere else on the screen.
struct WorkoutHeaderCard: View {
    let item: WorkoutItem

    var body: some View {
        BaselineCard {
            HStack(spacing: 14) {
                Image(systemName: sportSymbol(item.row.sport))
                    .font(BaselineTheme.title)
                    .foregroundStyle(BaselineTheme.effort)
                    .frame(width: 44, height: 44)
                    .background(BaselineTheme.effort.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(WorkoutSource.displaySport(item.row.sport))
                        .font(BaselineTheme.headline)
                        .foregroundStyle(BaselineTheme.text)
                        .lineLimit(1)
                    Text("\(WorkoutsFormat.dayLabel(item.start)) · \(WorkoutsFormat.timeRange(item.start, item.end))")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(BaselineReadouts.durationText(seconds: item.durationS))
                    .font(BaselineTheme.hero(36))
                    .foregroundStyle(BaselineTheme.text)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("duration")
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Average and peak heart rate, effort out of 100, and calories when the row carries them (the
/// duration is the header's numeral). The "Session" title is the UI test's first-card anchor.
struct WorkoutSessionCard: View {
    let item: WorkoutItem

    var body: some View {
        BaselineCard(title: "Session") {
            HStack(alignment: .top, spacing: 12) {
                StatCell(label: "Avg HR", value: item.row.avgHr.map { "\($0)" } ?? "–",
                         unit: item.row.avgHr != nil ? "bpm" : nil, color: BaselineTheme.rhr)
                StatCell(label: "Max HR", value: item.row.maxHr.map { "\($0)" } ?? "–",
                         unit: item.row.maxHr != nil ? "bpm" : nil, color: BaselineTheme.rhr)
                StatCell(label: "Effort", value: BaselineReadouts.effortText(item.row.strain),
                         unit: BaselineReadouts.effortUnit, color: BaselineTheme.effort)
            }
            if let kcal = item.row.energyKcal, kcal > 0 {
                HStack(alignment: .top, spacing: 12) {
                    StatCell(label: "Calories", value: WorkoutsFormat.grouped(kcal), unit: "kcal")
                    Spacer().frame(maxWidth: .infinity)
                    Spacer().frame(maxWidth: .infinity)
                }
            }
            Text(item.row.strain == nil
                 ? "This session's contribution to the day's effort (0–100), as the strap recorded it. Not every source records one."
                 : "This session's contribution to the day's effort (0–100), as the strap recorded it.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Five-segment zone bar with a legend: share of the session and minutes in each zone, and a line
/// saying where the split came from (imported, or derived and approximate). The scale note is the
/// card's trailing caption.
struct WorkoutZonesCard: View {
    /// Minutes in Z1…Z5 and their origin (`WorkoutDetailScreen.zoneSplit`).
    let split: WorkoutZoneSplit

    private var minutes: [Double] { split.minutes }
    private var total: Double { minutes.reduce(0, +) }

    var body: some View {
        BaselineCard(title: "Heart-rate zones",
                     accessory: AnyView(Text("Z1 easy → Z5 maximal")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary))) {
            WorkoutZoneBar(minutes: minutes)
            BaselineFlowLayout(spacing: 12) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 5) {
                        Circle().fill(BaselineTheme.zoneColor(i + 1)).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(WorkoutsFormat.zoneLegend(zone: i + 1, minutes: minutes[i], total: total))
                            .font(BaselineTheme.caption)
                            .foregroundStyle(BaselineTheme.textSecondary)
                    }
                }
            }
            Text(WorkoutsModel.zoneCaption(split.origin))
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Heart-rate zones: " + (1...5).map {
            WorkoutsFormat.zoneLegend(zone: $0, minutes: minutes[$0 - 1], total: total)
        }.joined(separator: ", "))
    }
}

/// Slim proportional bar of Z1…Z5, the sleep card's stage bar in zone colours.
struct WorkoutZoneBar: View {
    let minutes: [Double]

    var body: some View {
        let total = minutes.reduce(0, +)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    if total > 0, minutes[i] > 0 {
                        RoundedRectangle(cornerRadius: BaselineChartStyle.barRadius, style: .continuous)
                            .fill(BaselineTheme.zoneColor(i + 1))
                            .frame(width: max(2, geo.size.width * minutes[i] / total - 2))
                    }
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// The strap's heart rate across the session as a small line, with the average as a dashed rule named
/// once in the caption under the chart. Axes and constants from `BaselineChartStyle`.
struct WorkoutTraceCard: View {
    let item: WorkoutItem
    /// `repo.workoutHrBuckets(from:to:source:)`: bucket means over the window, oldest first.
    let buckets: [HRBucket]
    let loaded: Bool

    var body: some View {
        BaselineCard(title: "Heart rate") {
            if buckets.count > 1 {
                chart
                Text(caption)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loaded {
                Text("No heart-rate samples were recorded over this session's window.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            } else {
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }
    }

    private var caption: String {
        var parts = ["Beats per minute across the session"]
        if let avg = item.row.avgHr { parts.append("the dashed line is your average, \(avg) bpm") }
        return parts.joined(separator: "; ") + "."
    }

    private var chart: some View {
        let values = buckets.map(\.bpm)
        let lo = max(0, (values.min() ?? 60) - 8)
        let hi = (values.max() ?? 180) + 8
        let points = buckets.map { (t: Date(timeIntervalSince1970: TimeInterval($0.ts)), bpm: $0.bpm) }
        return Chart {
            ForEach(points, id: \.t) { p in
                AreaMark(x: .value("Time", p.t), yStart: .value("Low", lo), yEnd: .value("bpm", p.bpm))
                    .foregroundStyle(BaselineTheme.rhr.opacity(BaselineChartStyle.bandOpacity))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.t), y: .value("bpm", p.bpm))
                    .foregroundStyle(BaselineTheme.rhr)
                    .lineStyle(StrokeStyle(lineWidth: BaselineChartStyle.lineWidth, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let avg = item.row.avgHr {
                RuleMark(y: .value("Average", Double(avg)))
                    .foregroundStyle(BaselineTheme.rhr.opacity(BaselineChartStyle.baselineOpacity))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: item.start...max(item.end, item.start.addingTimeInterval(60)))
        .chartYScale(domain: lo...hi)
        .chartYAxis { BaselineChartStyle.yAxis(desiredCount: 3) }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(BaselineTheme.textTertiary).font(BaselineTheme.caption)
            }
        }
        .chartPlotStyle { $0.background(.clear) }
        .chartLegend(.hidden)
        .frame(height: 140)
        // One element for VoiceOver: without `.ignore` every bucket's area and line mark stays
        // navigable and the summary below labels a container instead of replacing them.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate during \(WorkoutSource.displaySport(item.row.sport)), from \(Int((values.min() ?? 0).rounded())) to \(Int((values.max() ?? 0).rounded())) beats per minute")
    }
}
#endif
