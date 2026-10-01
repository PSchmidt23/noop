#if os(iOS)
import SwiftUI
import StrandDesign
import UserNotifications

/// Baseline's entry point. Mirrors the required parts of NOOP's `StrandiOSApp` (which is excluded from
/// this target) so the engine behaves identically: strap pairing, overnight offload, re-scoring and
/// Apple Health write-back. Deliberately left out: widgets, watch, Live Activities, the Lift Log banner,
/// Coach briefs, debug export and the update checker. Baseline's own notifications: the morning summary
/// (`MorningSummaryNotifier`) and the evening check-in (`EveningCheckInScheduler`).
@main
struct BaselineApp: App {
    @StateObject private var model: AppModel
    @StateObject private var health: HealthKitBridge
    @StateObject private var router: NavRouter
    /// Only because a few NOOP screens we may host (Lift Log) declare it as an environment object.
    @StateObject private var liftSession: LiftSessionController
    /// The one journal catalog for the app. The store is UserDefaults-backed with no cross-instance
    /// notification, so Today and Journal must share this instance or an edit on one tab reaches the
    /// other only at the next launch.
    @StateObject private var journalCatalog = JournalCatalogStore()
    /// Opt-in morning summary notification; observes `model.repo` for the life of the process.
    @StateObject private var morningSummary: MorningSummaryNotifier
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ChartStyle.storageKey) private var chartStyleRaw = ChartStyle.titanium.rawValue
    @AppStorage(AccentColor.storageKey) private var accentRaw = AccentColor.mint.rawValue
    @AppStorage(AccentColor.customHexKey) private var accentCustomHex = AccentColor.defaultCustomHex

    init() {
        PuffinExperiment.migrateContinuousHrvOvernightDefault()
        // Baseline's shim forwards to NOOP's `NotificationPresenter` and adds the evening check-in's tap route.
        UNUserNotificationCenter.current().delegate = BaselineNotificationDelegate.shared
        let router = NavRouter()
        _router = StateObject(wrappedValue: router)
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        SyncKeepAwake.shared.attach(to: model.live)
        let liftSession = LiftSessionController(
            buzz: { [weak model] loops in model?.buzz(loops: loops, gate: HapticPrefs.liftRest) },
            setStrapHandler: { [weak model] handler in model?.strapDoubleTapOverride = handler },
            log: { [weak model] line in model?.live.append(log: AppModel.stamped(line)) })
        _liftSession = StateObject(wrappedValue: liftSession)
        RescoreBackgroundScheduler.register(perform: { [weak model] in
            await model?.runDeferredRescoreIfOwed()
        }, onExpire: { [weak model] in
            model?.live.append(log: "re-score: background processing time expired before the pass finished")
        })
        StaleBatteryBackgroundScheduler.register(perform: { [weak model] in
            await model?.checkStrapNotSeen()
        })
        StaleBatteryBackgroundScheduler.schedule()
        let bridge = HealthKitBridge(repo: model.repo, appleDeviceId: model.appleDeviceId, noopDeviceId: model.deviceId)
        _health = StateObject(wrappedValue: bridge)
        HealthWritebackBackgroundScheduler.register { [weak bridge] in
            guard let bridge else { return false }
            let succeeded = await bridge.writeBackAfterNewData()
            if bridge.auth != .authorized { HealthWritebackBackgroundScheduler.cancel() }
            return succeeded
        }
        model.healthWriteBack = { [weak bridge] in _ = await bridge?.writeBackAfterNewData() }
        let morningSummary = MorningSummaryNotifier(repo: model.repo)
        morningSummary.attach()
        _morningSummary = StateObject(wrappedValue: morningSummary)
    }

    var body: some Scene {
        WindowGroup {
            BaselineRoot()
                .environmentObject(model)
                .environmentObject(model.ble)
                .environmentObject(model.live)
                .environmentObject(model.repo)
                .environmentObject(model.profile)
                .environmentObject(model.behavior)
                .environmentObject(model.intelligence)
                .environmentObject(model.coach)
                .environmentObject(health)
                .environmentObject(router)
                .environmentObject(UpdateStore.shared)
                .environmentObject(liftSession)
                .environmentObject(journalCatalog)
                .environment(\.stressNudgeCenter, model.stressNudgeCenter)
                .environment(\.locale, AppLanguage.activeLocale)
                .chartStyle(chartStyleRaw)
                .noopAccent(accentRaw, customHex: accentCustomHex)
                .preferredColorScheme(.dark)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .onChange(of: health.auth) { _, auth in
                    HealthWritebackBackgroundScheduler.updateSchedule(isAuthorized: auth == .authorized)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.applySmartAlarm()
                model.ble.requestSync(.foreground)
                Task { await model.runDeferredRescoreIfOwed() }
                // Idempotent: keeps the one daily check-in pending while the toggle is on, cancels it when off.
                Task { await EveningCheckInScheduler.sync() }
                Task {
                    health.refreshAuthIfPreviouslyGranted()
                    HealthWritebackBackgroundScheduler.updateSchedule(isAuthorized: health.auth == .authorized)
                    await HealthSyncRefreshCoordinator.run(
                        sync: { await health.sync() },
                        refresh: { await model.refreshAfterAppleHealthSync(authorized: health.auth == .authorized) })
                }
            } else if phase == .background {
                HealthWritebackBackgroundScheduler.updateSchedule(isAuthorized: health.auth == .authorized)
                if RescoreBackgroundScheduler.isRescoreOwed { RescoreBackgroundScheduler.schedule() }
            }
        }
    }
}
#endif
