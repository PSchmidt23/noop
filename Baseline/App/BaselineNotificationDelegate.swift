#if os(iOS)
import Foundation
import UserNotifications

/// Baseline's `UNUserNotificationCenterDelegate`: a thin shim in front of NOOP's `NotificationPresenter`.
///
/// `NotificationPresenter` exposes one tap hook (`onCoachBriefTapped`, for NOOP's coach brief) and no
/// way to chain another delegate, so Baseline registers THIS object as the center's delegate and
/// forwards both callbacks to `NotificationPresenter.shared` unchanged: foreground banners keep NOOP's
/// presentation options and NOOP's own categories keep their routing. The only addition is the evening
/// check-in: a tap on that category writes `pendingTabKey`, which `BaselineRoot` observes through
/// `@AppStorage` and consumes by switching to the Journal tab. A UserDefaults flag rather than a direct
/// call, because on a cold start the tap arrives before any view exists; the root picks the flag up
/// whenever it first reads it. Registered once in `BaselineApp.init`.
final class BaselineNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BaselineNotificationDelegate()

    /// The tab the root should open next, or absent. Values: `pendingTabJournal`.
    static let pendingTabKey = "baseline.pendingTab"
    static let pendingTabJournal = "journal"

    private let upstream = NotificationPresenter.shared

    private override init() { super.init() }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        upstream.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == EveningCheckInScheduler.categoryIdentifier {
            UserDefaults.standard.set(Self.pendingTabJournal, forKey: Self.pendingTabKey)
        }
        upstream.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}
#endif
