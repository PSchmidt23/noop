#if os(iOS)
import Foundation
import UserNotifications

/// Opt-in evening check-in: ONE repeating local notification a day, at a time the person picks in
/// Settings (default 21:30), asking them to log tonight's habits. The mirror of `MorningSummaryNotifier`
/// for the other end of the day, with the one difference the feature needs: the morning summary is
/// event-driven and never scheduled, this one is a `UNCalendarNotificationTrigger` that repeats daily
/// and is never event-driven.
///
/// House pattern: a fixed request identifier so the center holds at most one, authorization is only
/// CHECKED here (the Settings toggle asks for it through `MorningSummaryNotifier.requestAuthorization`),
/// and `sync` is idempotent so the app can call it on every activation: re-adding a request with the
/// same identifier replaces the pending one.
///
/// A tap opens the Journal tab: `BaselineNotificationDelegate` sees the category and raises
/// `BaselineNotificationDelegate.pendingTabKey`, which `BaselineRoot` consumes.
enum EveningCheckInScheduler {
    static let enabledKey = "baseline.eveningCheckIn.enabled"
    /// The chosen time as minutes since midnight (`0 ..< 1440`); absent means `defaultMinutes`.
    static let minutesKey = "baseline.eveningCheckIn.minutes"
    static let defaultMinutes = 21 * 60 + 30
    static let requestIdentifier = "baseline-evening-checkin"
    static let categoryIdentifier = "baseline-evening-checkin"
    static let title = "Evening check-in"
    static let body = "Log tonight's habits so Baseline can learn what moves your HRV."

    // MARK: Time (pure)

    static func clamp(_ minutes: Int) -> Int { min(max(minutes, 0), 24 * 60 - 1) }

    /// The stored time, or the default when none (or an invalid value) was saved.
    static func minutes(_ defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: minutesKey) != nil else { return defaultMinutes }
        return clamp(defaults.integer(forKey: minutesKey))
    }

    /// `hour` and `minute` only: a calendar trigger with no day fires every day at that time.
    static func components(minutesSinceMidnight: Int) -> DateComponents {
        let m = clamp(minutesSinceMidnight)
        var c = DateComponents()
        c.hour = m / 60
        c.minute = m % 60
        return c
    }

    /// Today at that time in the current calendar, for the Settings `DatePicker` (which edits a `Date`).
    static func date(minutesSinceMidnight: Int, calendar: Calendar = .current, now: Date = Date()) -> Date {
        let c = components(minutesSinceMidnight: minutesSinceMidnight)
        return calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: now) ?? now
    }

    /// The picker's `Date` back to minutes since midnight.
    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return clamp((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    // MARK: Request (pure)

    static func request(minutesSinceMidnight: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        let trigger = UNCalendarNotificationTrigger(dateMatching: components(minutesSinceMidnight: minutesSinceMidnight),
                                                    repeats: true)
        return UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
    }

    // MARK: Center

    /// Bring the center in line with the toggle: schedule (replacing any pending request) when the
    /// feature is on and notifications are allowed, else cancel. Safe to call on every activation.
    static func sync(defaults: UserDefaults = .standard) async {
        guard defaults.bool(forKey: enabledKey) else { cancel(); return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        try? await center.add(request(minutesSinceMidnight: minutes(defaults)))
    }

    /// Pull the pending request (and a delivered one still in the list) when the toggle goes off.
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
    }
}
#endif
