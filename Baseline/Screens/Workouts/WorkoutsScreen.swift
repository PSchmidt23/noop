#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Every workout, newest first, one card per week. Each row pushes `WorkoutDetailScreen`.
/// Reads `repo.workoutRows(days:)` (strap, imported and Apple Health sessions, merged and deduped)
/// over `WorkoutsWindow`: the last year on first paint, with the window named under the title and a
/// "Show earlier" link that widens it to the whole store, so sessions older than a year stay reachable
/// and a store holding only older imports never reads as empty. Reloads on `repo.refreshSeq`.
struct WorkoutsScreen: View {
    @EnvironmentObject private var repo: Repository
    @State private var weeks: [WorkoutWeek] = []
    @State private var loaded = false
    /// The window the next read covers; "Show earlier" moves it to `.all`.
    @State private var window: WorkoutsWindow = .lastYear
    /// The window the rows on screen were read with, so the caption never runs ahead of the list.
    @State private var shown: WorkoutsWindow = .lastYear

    /// Reload key: `refreshSeq` for every changed refresh, `loaded` so the first publish is never
    /// missed if the store finishes loading between two sequence values, and the window so widening it
    /// re-reads.
    private struct LoadKey: Hashable {
        let seq: Int
        let loaded: Bool
        let allTime: Bool
    }

    var body: some View {
        BaselineScreen(title: "Workouts") {
            if loaded && repo.loaded {
                Text(shown.caption)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            if !weeks.isEmpty {
                ForEach(weeks) { week in
                    WorkoutWeekCard(week: week)
                }
                if shown == .lastYear {
                    earlierLink.padding(.horizontal, 4)
                }
            } else if loaded && repo.loaded {
                BaselineCard {
                    BaselineEmptyState(icon: "figure.run",
                                       title: shown.emptyTitle,
                                       message: shown.emptyMessage)
                    if shown == .lastYear {
                        earlierLink.frame(maxWidth: .infinity)
                    }
                }
            } else {
                // Until the store's first refresh lands, the same spinner Trends and Progress show.
                ProgressView()
                    .tint(BaselineTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        }
        .task(id: LoadKey(seq: repo.refreshSeq, loaded: repo.loaded, allTime: window == .all)) { await reload() }
    }

    /// Quiet accent link, the style of Today's "All workouts", that widens the read to the whole store.
    private var earlierLink: some View {
        Button {
            window = .all
        } label: {
            HStack(spacing: 4) {
                Text("Show earlier workouts")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(BaselineTheme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Loads sessions older than a year")
    }

    @MainActor
    private func reload() async {
        let target = window
        let rows: [WorkoutRow]
        if let days = target.days {
            rows = await repo.workoutRows(days: days)
        } else {
            rows = await repo.workoutRows()
        }
        weeks = WorkoutsModel.weeks(rows)
        shown = target
        loaded = true
    }
}

/// One week: its label and totals in the header, its sessions as rows.
struct WorkoutWeekCard: View {
    let week: WorkoutWeek

    var body: some View {
        BaselineCard(title: WorkoutsModel.weekLabel(start: week.start),
                     subtitle: WorkoutsFormat.weekSummary(count: week.count, totalDurationS: week.totalDurationS)) {
            VStack(spacing: 0) {
                ForEach(week.items) { item in
                    NavigationLink {
                        WorkoutDetailScreen(row: item.row)
                    } label: {
                        WorkoutListRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != week.items.last?.id {
                        Rectangle().fill(BaselineTheme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }
}

/// Sport and date on the left; effort and average heart rate on the right, each with its unit.
struct WorkoutListRow: View {
    let item: WorkoutItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sportSymbol(item.row.sport))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BaselineTheme.effort)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutSource.displaySport(item.row.sport))
                    .font(BaselineTheme.label)
                    .foregroundStyle(BaselineTheme.text)
                    .lineLimit(1)
                Text("\(WorkoutsFormat.dayLabel(item.start)) · \(BaselineReadouts.durationText(seconds: item.durationS))")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(BaselineReadouts.effortText(item.row.strain))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(item.row.strain == nil ? BaselineTheme.textTertiary : BaselineTheme.text)
                    Text(BaselineReadouts.effortUnit)
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textTertiary)
                }
                if let hr = item.row.avgHr {
                    Text("\(hr) bpm")
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.rhr)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BaselineTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(WorkoutSource.displaySport(item.row.sport)), \(WorkoutsFormat.dayLabel(item.start))",
                     BaselineReadouts.durationText(seconds: item.durationS)]
        if let s = item.row.strain { parts.append("effort \(BaselineReadouts.effortText(s)) of 100") }
        if let hr = item.row.avgHr { parts.append("average \(hr) beats per minute") }
        return parts.joined(separator: ", ")
    }
}
#endif
