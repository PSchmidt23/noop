#if os(iOS)
import Foundation

/// Home's day-by-day navigation, pure and testable: which calendar day the screen shows, how far back
/// it may go, and the keys the funnels are asked for. Every date here is a `startOfDay` in `calendar`.
/// Rules: never a future day; never a day before the first stored night (`earliest`); with no stored
/// night at all only today is reachable; at midnight a selection that was "today" follows the new day,
/// any other day stays put. `TodayDaySelectionTests`.
struct TodayDaySelection: Equatable {
    /// The selected day.
    private(set) var day: Date
    /// Today at the last `roll(now:)`.
    private(set) var today: Date
    /// The earliest selectable day (the first stored night); nil until the store has one.
    private(set) var earliest: Date?
    let calendar: Calendar

    init(now: Date = Date(), earliest: Date? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        self.today = today
        self.day = today
        self.earliest = nil
        setEarliest(earliest)
    }

    // MARK: Facts

    var isToday: Bool { day == today }

    /// Days before today (0 = today, 1 = yesterday, …).
    var offset: Int { calendar.dateComponents([.day], from: day, to: today).day ?? 0 }

    /// The lowest reachable day: the first stored night, or today while the store is empty.
    var lowerBound: Date { earliest ?? today }

    var canGoBack: Bool { day > lowerBound }

    var canGoForward: Bool { day < today }

    /// The engine's "yyyy-MM-dd" for the selected day: the journal's key, the morning every night is
    /// dated to, and the `todayKey` every Today funnel scopes to.
    var key: String { Repository.localDayKey(day) }

    /// NOOP's 04:00-rollover day for the effort row (`TodaySnapshot.build(logicalKey:)`): today reads the
    /// logical day the caller resolved from the clock (the small hours still show the day being lived); a
    /// past day is its own key.
    func logicalKey(todayLogicalKey: String) -> String { isToday ? todayLogicalKey : key }

    /// How many days back `repo.workoutRows(days:)` must reach to include the selected day: the offset,
    /// the day itself, and one more so a session that started before midnight in UTC terms is never cut.
    var workoutWindowDays: Int { offset + 2 }

    /// The navigation title: "Today" / "Yesterday" / "Wednesday 1 October" (`BaselineDaySwitcher.title`).
    var title: String { BaselineDaySwitcher.title(for: day, now: today) }

    /// The day switcher's centre text, the short date for every day ("Wed 1 Oct"), so the pinned control
    /// and the title never say the same word twice on today and yesterday.
    var shortDate: String { day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }

    // MARK: Moves (every one clamped to `earliest…today`)

    mutating func step(_ days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = calendar.startOfDay(for: next)
        clamp()
    }

    /// The day switcher's binding setter.
    mutating func select(_ date: Date) {
        day = calendar.startOfDay(for: date)
        clamp()
    }

    /// The calendar day changed (`.NSCalendarDayChanged`, or the app came back after midnight). A
    /// selection that was today moves with it; an older day stays, still clamped.
    mutating func roll(now: Date) {
        let wasToday = isToday
        today = calendar.startOfDay(for: now)
        if wasToday { day = today }
        clamp()
    }

    /// The first stored night, from the funnel's oldest day key; nil clears the bound (today only).
    mutating func setEarliest(_ date: Date?) {
        earliest = date.map { min(calendar.startOfDay(for: $0), today) }
        clamp()
    }

    private mutating func clamp() {
        if day > today { day = today }
        if day < lowerBound { day = lowerBound }
    }
}
#endif
