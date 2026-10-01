#if os(iOS)
import Foundation
import WhoopStore

// Pure derivations for the Workouts screens. Everything here is a value type built from
// `repo.workoutRows(days:)`; nothing touches the store or SwiftUI.

/// One session as the list and the detail show it. `WorkoutRow` is neither `Identifiable` nor `Hashable`,
/// so this wrapper gives it a stable list identity (the merged list is deduped per source, so start +
/// source + sport is unique).
struct WorkoutItem: Identifiable {
    let row: WorkoutRow

    var id: String { "\(row.startTs)|\(row.source)|\(row.sport)" }
    var start: Date { Date(timeIntervalSince1970: TimeInterval(row.startTs)) }
    var end: Date { Date(timeIntervalSince1970: TimeInterval(row.endTs)) }
    /// Seconds of activity: the stored duration, else the window.
    var durationS: Double {
        if let d = row.durationS, d > 0 { return d }
        return Double(max(0, row.endTs - row.startTs))
    }
}

/// One calendar week of sessions, newest first. `start` is the week's first local midnight and `end` the
/// next week's, so `start ..< end` is the whole week.
struct WorkoutWeek: Identifiable {
    let start: Date
    let end: Date
    let items: [WorkoutItem]

    var id: Int { Int(start.timeIntervalSince1970) }
    var count: Int { items.count }
    var totalDurationS: Double { items.reduce(0) { $0 + $1.durationS } }
}

/// Where a session's zone split came from: the row's own imported per-workout percentages, or the
/// strap's heart-rate samples binned on this iPhone with the profile's zones (`repo.workoutZoneMinutes`).
/// Only a CSV import writes `zonesJSON`; a strap-recorded, manual or Apple Health session relies on the
/// derived split, which the card labels as approximate.
enum WorkoutZoneOrigin: Equatable {
    case imported
    case derived(WorkoutZoneBasis)
}

/// What a derived split's zones rest on, so its caption can name the number: custom boundaries, a max
/// heart rate set by hand, or the age estimate. Same precedence as `ProfileStore.hrZoneSet`.
enum WorkoutZoneBasis: Equatable {
    case customBoundaries
    case manualMaxHR(Int)
    case ageEstimate(maxHR: Int)
}

/// Minutes in Z1…Z5 together with where they came from; what `WorkoutZonesCard` shows.
struct WorkoutZoneSplit: Equatable {
    let minutes: [Double]
    let origin: WorkoutZoneOrigin
}

/// How far back the Workouts list reads. First paint is bounded to a year (the list re-reads on every
/// refresh, and a long import would re-sort its whole history each time); "Show earlier" widens it to
/// everything in the store. The screen states the window so "All workouts" and the list cannot disagree.
enum WorkoutsWindow: Equatable {
    case lastYear
    case all

    /// The `repo.workoutRows(days:)` argument; nil means the engine's default read, the whole store.
    var days: Int? { self == .lastYear ? 365 : nil }

    /// Caption under the title naming the span the list covers.
    var caption: String { self == .lastYear ? "Last 12 months" : "Every stored workout" }

    var emptyTitle: String { self == .lastYear ? "No workouts in the last year" : "No workouts yet" }

    var emptyMessage: String {
        let base = "Sessions your strap records, and any you import, appear here by week with their duration, heart rate and effort."
        return self == .lastYear ? base + " Older sessions are a tap away." : base
    }
}

enum WorkoutsModel {

    /// Weeks newest first, each with its sessions newest first. Grouped on the calendar's own week
    /// (`firstWeekday` and zone), the same week a person sees in the system calendar.
    static func weeks(_ rows: [WorkoutRow], calendar: Calendar = .current) -> [WorkoutWeek] {
        let items = rows.map(WorkoutItem.init).sorted { $0.row.startTs > $1.row.startTs }
        var order: [Date] = []
        var byStart: [Date: (end: Date, items: [WorkoutItem])] = [:]
        for item in items {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: item.start) else { continue }
            if byStart[interval.start] == nil {
                order.append(interval.start)
                byStart[interval.start] = (interval.end, [])
            }
            byStart[interval.start]?.items.append(item)
        }
        return order.compactMap { start in
            byStart[start].map { WorkoutWeek(start: start, end: $0.end, items: $0.items) }
        }
    }

    /// "This week" / "Last week", else the week's span: "Feb 2 – Feb 8", with the year once the week
    /// began in a different year from `now` ("Dec 29 – Jan 4, 2025").
    static func weekLabel(start: Date, now: Date = Date(), calendar: Calendar = .current,
                          locale: Locale = .current) -> String {
        if let current = calendar.dateInterval(of: .weekOfYear, for: now) {
            if start == current.start { return "This week" }
            if let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: current.start),
               start == previous {
                return "Last week"
            }
        }
        let last = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let style = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
        let span = "\(start.formatted(style)) – \(last.formatted(style))"
        let startYear = calendar.component(.year, from: start)
        return startYear == calendar.component(.year, from: now) ? span : "\(span), \(startYear)"
    }

    /// Minutes in each of Z1–Z5 for one session, duration-weighted from the row's imported zone
    /// percentages (`WorkoutZones.percents`); nil when the row carries no zone split or no duration.
    static func zoneMinutes(_ row: WorkoutRow) -> [Double]? {
        guard let pct = WorkoutZones.percents(row.zonesJSON) else { return nil }
        let durMin = WorkoutItem(row: row).durationS / 60.0
        guard durMin > 0 else { return nil }
        return pct.map { durMin * $0 / 100.0 }
    }

    /// The basis of a derived split from the profile's fields, in the order `ProfileStore.hrZoneSet`
    /// applies them: custom boundaries win, then a manual max HR, else the age estimate.
    static func zoneBasis(hasCustomZones: Bool, hrMaxOverride: Int, hrMax: Int) -> WorkoutZoneBasis {
        if hasCustomZones { return .customBoundaries }
        if hrMaxOverride > 0 { return .manualMaxHR(hrMaxOverride) }
        return .ageEstimate(maxHR: hrMax)
    }

    /// The sentence under the zone bar that says where the split came from. A derived split is always
    /// called approximate and names the max heart rate (or boundaries) its zones rest on.
    static func zoneCaption(_ origin: WorkoutZoneOrigin) -> String {
        switch origin {
        case .imported:
            return "Zone split imported with this session."
        case .derived(let basis):
            let zones: String
            switch basis {
            case .customBoundaries:
                zones = "your custom zone boundaries"
            case .manualMaxHR(let bpm):
                zones = "zones from your max HR of \(bpm) bpm (Settings → Profile)"
            case .ageEstimate(let bpm):
                zones = "zones from your age, max HR estimated at \(bpm) bpm (Settings → Profile)"
            }
            return "Approximate: the strap's heart rate over this window, binned into \(zones)."
        }
    }
}

// MARK: - Formatting shared by the Workouts screens

enum WorkoutsFormat {
    /// "Mon 28 Sep" for a session's start.
    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "7:02 – 7:48 AM" in the device locale; just the start when the window is empty.
    static func timeRange(_ start: Date, _ end: Date) -> String {
        end > start ? "\(SleepFormat.clock(start)) – \(SleepFormat.clock(end))" : SleepFormat.clock(start)
    }

    /// "3 workouts · 2h 40m" for a week's card subtitle.
    static func weekSummary(count: Int, totalDurationS: Double) -> String {
        let n = "\(count) workout\(count == 1 ? "" : "s")"
        return totalDurationS > 0 ? "\(n) · \(BaselineReadouts.durationText(seconds: totalDurationS))" : n
    }

    /// "1,240" for a calorie count.
    static func grouped(_ value: Double) -> String {
        let n = Int(value.rounded())
        return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    /// "Z3 34% · 18 min" legend entry; a zone under half a minute shows its share only.
    static func zoneLegend(zone: Int, minutes: Double, total: Double) -> String {
        guard total > 0 else { return "Z\(zone)" }
        let pct = Int((minutes / total * 100).rounded())
        guard minutes >= 0.5 else { return "Z\(zone) \(pct)%" }
        return "Z\(zone) \(pct)% · \(BaselineReadouts.durationText(minutes: minutes))"
    }
}
#endif
