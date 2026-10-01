#if os(iOS)
import Foundation
import Combine
import UIKit
import UserNotifications
import WhoopStore
import StrandAnalytics

// MARK: - Text (pure)

/// The one-line morning summary, built from the same `TodaySnapshot` the Home tab draws (the notifier
/// reads it through the same strap-first funnel, `MorningSummaryNotifier.summary`), so the notification
/// and the screen behind it print one HRV, one resting HR, one band position and one sleep total for the
/// night. Pure and synchronous; unit-tested in `MorningSummaryTests`.
struct MorningSummary: Equatable {
    /// The newest morning any of the three facts is dated to (`TodaySnapshot`'s own day keys). The
    /// notifier only posts when this is today's key.
    let day: String
    /// `ReadinessTier.baselineNotificationSubtitle` ("Readiness · On baseline"), nil while calibrating or stale.
    let subtitle: String?
    /// e.g. "HRV 89 ms · inside your band · Resting HR 57 bpm · inside your band · Slept 6h 42m · +18 min vs average"
    let body: String
}

enum MorningSummaryText {
    static let separator = " · "

    /// nil when the snapshot carries nothing fresh to say (no HRV, no resting HR, no night).
    static func build(_ s: TodaySnapshot) -> MorningSummary? {
        var parts: [String] = []
        var days: [String] = []

        if let hrv = s.hrv, let line = metricLine(hrv, name: "HRV", unit: "ms") {
            parts.append(line)
            days.append(hrv.day)
        }
        if let rhr = s.restingHr, let line = metricLine(rhr, name: "Resting HR", unit: "bpm") {
            parts.append(line)
            days.append(rhr.day)
        }
        if let sleep = s.sleep {
            var line = "Slept \(BaselineReadouts.durationText(minutes: sleep.totalMin))"
            if let avg = sleep.avg30Min {
                line += separator + SleepFormat.deltaText(asleepMin: sleep.totalMin, average: avg)
            }
            parts.append(line)
            days.append(sleep.day)
        }
        guard let day = days.max(), !parts.isEmpty else { return nil }

        var subtitle: String?
        if case .tier(let tier) = s.readiness { subtitle = tier.baselineNotificationSubtitle }
        return MorningSummary(day: day, subtitle: subtitle, body: parts.joined(separator: separator))
    }

    /// "HRV 89 ms · inside your band", or the calibrating count in Today's words while the baseline is
    /// still forming. nil for a stale reading: a week-old number must not read as this morning's.
    static func metricLine(_ r: TodayMetricReading, name: String, unit: String) -> String? {
        guard let v = r.value else { return nil }
        let value = "\(name) \(Int(v.rounded())) \(unit)"
        if let position = r.band.positionPhrase { return value + separator + position }
        return value + separator + "baseline after \(Baselines.minNightsSeed) nights, \(r.state.nValid) so far"
    }
}

// MARK: - Notifier

/// Opt-in morning summary: ONE local notification the first time a sync lands the night that ends on
/// today's morning. Event-driven on `Repository.refreshSeq` (the same signal every tab reloads on);
/// never scheduled and never repeating. Owned by `BaselineApp` for the life of the process.
///
/// House pattern (`BatteryNotifier`, `IllnessNotifier`): a fixed request identifier so the center holds
/// at most one, authorization is only CHECKED here (the Settings toggle asks for it at a predictable
/// moment), and a persisted day gate keeps it to one post per morning across process restarts.
@MainActor
final class MorningSummaryNotifier: ObservableObject {
    static let enabledKey = "baseline.morningSummary.enabled"
    static let lastDayKey = "baseline.morningSummary.lastDay"
    static let requestIdentifier = "baseline-morning-summary"
    /// Not routed by `NotificationPresenter` (it only routes NOOP's coach brief), so a tap just opens the
    /// app where it was.
    static let categoryIdentifier = "baseline-morning-summary"

    private let repo: Repository
    private let defaults: UserDefaults
    private let now: () -> Date
    private let isAppActive: @MainActor () -> Bool
    private var subscription: AnyCancellable?
    private var checking = false
    private var checkAgain = false

    /// `isAppActive` defaults to the real application state; injectable so the foreground rule is testable.
    init(repo: Repository, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         isAppActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.repo = repo
        self.defaults = defaults
        self.now = now
        self.isAppActive = isAppActive
    }

    /// Start observing. `combineLatest` also replays the current pair, so a store that is already
    /// loaded (or loads before the first bump) is judged at once.
    func attach() {
        guard subscription == nil else { return }
        subscription = repo.$refreshSeq
            .combineLatest(repo.$loaded)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, loaded in
                guard loaded else { return }
                self?.evaluate()
            }
    }

    /// Judge the current store once. Coalesces: a bump that lands mid-check queues exactly one more pass.
    func evaluate() {
        if checking { checkAgain = true; return }
        checking = true
        Task { [weak self] in
            await self?.check()
            guard let self else { return }
            self.checking = false
            if self.checkAgain {
                self.checkAgain = false
                self.evaluate()
            }
        }
    }

    private func check() async {
        guard defaults.bool(forKey: Self.enabledKey), repo.loaded else { return }
        let clock = now()
        let todayKey = Repository.localDayKey(clock)
        guard defaults.string(forKey: Self.lastDayKey) != todayKey else { return }

        guard let summary = await Self.summary(repo: repo, todayKey: todayKey,
                                               logicalKey: Repository.logicalDayKey(clock)),
              summary.day == todayKey else { return }

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        // Re-check after the awaits: a second pass may have posted meanwhile.
        guard defaults.string(forKey: Self.lastDayKey) != todayKey else { return }
        // Mark before adding (IllnessNotifier's discipline) so a slow or deferred delivery cannot re-post.
        defaults.set(todayKey, forKey: Self.lastDayKey)

        // The night that lands while the person is already looking at Today needs no banner and no sound
        // over the screen that shows it: the morning is marked as summarised, nothing is posted.
        guard !isAppActive() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your morning"
        if let subtitle = summary.subtitle { content.subtitle = subtitle }
        content.body = summary.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        // trigger: nil = deliver now. Never a calendar or interval trigger.
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// THE resolver for the banner's figures: the same night list and `TodaySnapshot` the Home tab builds,
    /// read through the strap-first funnel (`BaselineReadouts.days` / `nights`, what `repo.baselineDays` and
    /// `repo.baselineNights()` return), never NOOP's import-wins `repo.days` / `repo.sleeps`. With a WHOOP
    /// export overlapping last night the two tables disagree on HRV, resting HR and the night under
    /// `.strapFirst` (the default); routing both readouts through this one funnel is what keeps the
    /// notification and the ring behind it on one number. `mode` is injectable for the tests only; the
    /// notifier passes the persisted setting. `logicalKey` mirrors Home's effort row (unused by the text).
    static func summary(repo: Repository, todayKey: String, logicalKey: String? = nil,
                        mode: BaselineDataSource = .current()) async -> MorningSummary? {
        let habitual = await repo.habitualMidsleepSec()
        let days = BaselineReadouts.days(repo, mode: mode)
        let sessions = await BaselineReadouts.nights(repo, mode: mode)
        let nights = SleepNightBuilder.nights(sessions: sessions, days: days, habitualMidsleepSec: habitual)
        let snapshot = TodaySnapshot.build(days: days, nights: nights, todayKey: todayKey, logicalKey: logicalKey)
        return MorningSummaryText.build(snapshot)
    }

    /// Ask once, at the moment the toggle goes on, and report where that left us. Only `.notDetermined`
    /// shows the system dialog; a denied status is returned as is so Settings can point at iOS Settings.
    static func requestAuthorization() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        return await center.notificationSettings().authorizationStatus
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Pull a delivered summary when the person turns the feature off.
    static func removeDelivered() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }
}
#endif
