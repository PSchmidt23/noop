# NOOP engine → Baseline: API map
Paths relative to the repo root. Read-only reference for anyone writing Baseline screens.

## Concurrency patterns
- `AppModel`, `LiveState`, `Repository`, `IntelligenceEngine`, `ProfileStore`, `DeviceRegistry`,
  `HealthKitBridge`, `JournalCatalogStore`, `NavRouter` are `@MainActor ObservableObject` with `@Published`.
- `Repository` read facades are `async` main-actor functions over `public actor WhoopStore` (GRDB).
- Analytics are pure `public enum` namespaces with static functions.
- Views reload with `.task(id: repo.refreshSeq)` — `refreshSeq` bumps on every changed refresh.

## Environment objects every hosted NOOP screen may expect
`AppModel, BLEManager (model.ble), LiveState (model.live), Repository (model.repo), ProfileStore,
BehaviorStore, IntelligenceEngine, AICoachEngine, HealthKitBridge, NavRouter, UpdateStore.shared,
LiftSessionController` — all injected in `Baseline/App/BaselineApp.swift`.
If you host `TodayView`/`TrendsView` add `.tabRouteDestinations()` (Strand/App/TabRoute.swift) once per stack.

## Core models (Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift, JournalWorkoutAppleCache.swift)
- `DailyMetric`: `day` ("yyyy-MM-dd"), `totalSleepMin`, `efficiency`, `deepMin`, `remMin`, `lightMin`,
  `disturbances`, `restingHr: Int?`, `avgHrv: Double?` (RMSSD ms), `recovery` (0–100), `strain` (0–100),
  `exerciseCount`, `spo2Pct`, `skinTempDevC`, `skinTempC`, `respRateBpm`, `steps`, `activeKcalEst`, `avgSdnn`.
- `CachedSleepSession`: `startTs`, `endTs`, `efficiency`, `restingHr`, `avgHrv`, `stagesJSON`, `userEdited`,
  `effectiveStartTs`, `stagingSparse`, `deviceId`.
- `WorkoutRow`: `startTs`, `endTs`, `sport`, `source`, `durationS`, `energyKcal`, `avgHr`, `maxHr`, `strain`,
  `distanceM`, `zonesJSON`, `notes`, `steps`.

## Daily data (Strand/Data/Repository.swift)
- `@Published var days: [DailyMetric]` — merged (imported ∪ computed ∪ steps), oldest→newest. Filter by day key.
  Do NOT use `dailyMetrics(fromDay:toDay:)` (imported rows only).
- `@Published var sleeps: [CachedSleepSession]`, `loaded`, `freshness`. `var today: DailyMetric?`, `var week`.
- Day keys: `Repository.localDayKey(_:)`, `logicalDayKey(_:)`, `dayString(_:)`. `lastHrvDay`, `lastRestingHrDay`.
- `func refresh(days: Int = 4000) async`.
- Sleep-performance ("Rest") score: `await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")`
  → `[(day: String, value: Double)]`.
- `series(key:source:days:fullHistory:) async` keys: `recovery, hrv, rhr, strain, resp_rate, spo2, skin_temp, sleep_*, steps`.
- Sleep stages: `AnalyticsEngine.decodeStages(_ json: String?) -> [StageSegment]` (`start`, `end`, `stage`
  = "wake"/"light"/"deep"/"rem"); `repo.allSleepSessions(days:)`, `repo.sleepSessions(from:to:limit:)`.

## Baselines (Packages/StrandAnalytics/Sources/StrandAnalytics/Baselines.swift)
- Winsorized EWMA, half-lives 14/21 nights; `minNightsSeed = 4` → `.provisional`, `minNightsTrust = 14` → `.trusted`.
- `Baselines.foldHistory(_ values: [Double?], cfg: MetricCfg, rejectHardOutliers: Bool = true) -> BaselineState`
- `Baselines.foldHistory(_:dayKeys:cfg:baselineEpoch:)` honours the recalibrate epoch (`"noop.hrvBaselineEpoch"`).
- `Baselines.update(_ state: BaselineState?, value:cfg:)` one step per night (time-varying band).
- `Baselines.rollingMeanSD(_:cfg:window: Int = 30)`.
- `Baselines.deviation(_ value: Double, state:) -> Deviation { z, delta, ratio, inNormalRange }` (|z| ≤ 1).
- `Baselines.sigma(state) = 1.253·spread`. Configs: `Baselines.hrvCfg, .restingHRCfg, .respCfg, .strainCfg`.
- `BaselineState { baseline, spread, nValid, nightsSinceUpdate, status, usable, trusted }`.
- `VitalBands.band(value:history:populationRange:cfg:) -> Result { band, basis, nights }` (personal ±2σ once trusted).
- `HRVReadiness.evaluate(avgHrv: [Double?]) -> HRVReadinessResult?` → `tier` (primed/normal/suppressed),
  `baseline7Ms`, `normalLowMs`, `normalHighMs`, `overreachingWatch`. Needs ≥14 nights.
- `ReadinessEngine.evaluate(days: [DailyMetric], today: String?) -> Readiness { level, signals, acwr, monotony, confidence }`.
- Recipe:
  ```swift
  let hist = repo.days.filter { $0.day < todayKey }
  let s = Baselines.foldHistory(hist.map(\.avgHrv), dayKeys: hist.map(\.day), cfg: Baselines.hrvCfg)
  guard s.usable else { /* calibrating */ }
  let d = Baselines.deviation(todayHrv, state: s)  // d.delta ms, d.ratio, band = s.baseline ± Baselines.sigma(s)
  ```

## Workouts
- `repo.workoutRows(days: Int = 4000) async -> [WorkoutRow]` (merged, deduped).
- `WorkoutZones.percents(_ zonesJSON: String?) -> [Double]?` (Z1–Z5), `WorkoutZones.summary(from:)`.
- `repo.workoutZoneMinutes(from:to:zoneSet: profile.hrZoneSet, source:) async -> [Double]?`.
- Effort stored 0–100; display scale `EffortScale` (`UnitPrefs.effortScaleKey`). Reference: `WorkoutsView`, `WorkoutDetailView`.

## Live + status (Strand/BLE/LiveState.swift, AppModel)
- `model.bpm: Int?` (smoothed; display this). `live.heartRate`, `live.rr`, `live.streamingLiveHR`.
- `model.startRealtimeHR()` / `stopRealtimeHR()`.
- `live.connected, bonded, encryptedBond, historyReady, backfilling, historyPendingSync, lastSyncedAt: TimeInterval?,
  lastSyncError, batteryPct: Double?, charging: Bool?, worn, strapFirmware, activeIsWhoop`.
- `repo.latestBattery() async -> (ts, soc, charging)?`. Sync: `model.ble.syncNow()`, `model.ble.requestSync(.foreground)`.
- Devices: `model.deviceRegistry?.devices: [PairedDevice]`, `.activeDeviceId`; `model.presentWhoopScan(model: .whoop4|.whoop5mg)`,
  `model.discoveredWhoops`, `model.registerDevice(_:makeActive:)`.

## Journal + effects
- `JournalEntry { day, question, answeredYes: Bool, notes: String?, numericValue: Double? }`. Native device id
  `Repository.journalDeviceId = "noop-journal"`. `question` is the canonical English key.
- Day convention: an answer on day D describes the night/day leading into morning D.
- `JournalCatalogStore` (Strand/Data/JournalCatalog.swift): `@Published items: [JournalCatalogItem { canonical,
  displayName?, kind: JournalKind(.bool | .numeric(unitLabel:)), group: JournalGroup, sortIndex, hidden, custom }]`,
  `starterQuestions`, `resolvedItems(imported:includeHidden:)`, `addCustom(_:kind:group:)`, `displayName(for:)`.
- Repository: `saveJournalAnswer(day:question:answeredYes:notes:) async`, `saveJournalNumeric(day:question:value:notes:) async`,
  `clearJournalAnswer(day:question:) async`, `journalEntries(days:) async -> [JournalEntry]`,
  `nativeJournalAnswers(day:) -> [String: Bool]`, `nativeJournalDays(from:to:)`.
- `EffectRanker.rank(behaviors: [String: Set<String>], controls: [String: Set<String>], outcomeByDay: [String: Double],
  outcome: String) -> [RankedEffect { behavior, outcome, lag, effect: BehaviorEffect, confidence: ScoreConfidence
  (.calibrating <5 / .building / .solid ≥10), leadLagText, sentence() }]`. `EffectRanker.bestLag(...)` searches lags 0/+1/+2.
- `BehaviorInsights.effect(behaviorDays:controlDays:outcomeByDay:behavior:outcome:) -> BehaviorEffect? { meanWith,
  meanWithout, delta, pctChange?, nWith, nWithout, cohensD, pApprox, significant }`.
- `DoseResponseEngine.estimate(behavior: DosedBehavior(.alcohol|.caffeine), outcome:, doseByDay: [String: Int],
  outcomeByDay:) -> DoseResponse?`.
- Template view-model: `InsightsHubViewModel` (Strand/Screens/InsightsHubView.swift ~line 490):
  outcome map = `repo.series(key: "recovery"|"hrv"|"rhr"|"sleep_performance", source: "my-whoop")`.

## Design system (Packages/StrandDesign)
- Tokens: `StrandPalette` (surface/text/hairline, `accent`, score colours, sleep-stage colours), `StrandFont`.
- Components: `StrandCard`, `ChartCard`, `StatTile`, `InsightCard`, `SectionHeader`, `SegmentedPillControl`, `StatePill`,
  `ConnectionDot`, `TrendChip`, `TypicalRangeBar(value:typical:color:)`.
- Charts (Swift Charts): `TrendChart(points: [TrendPoint(date:value:segment:)], gradient:, baselineValue: Double?, …)`
  draws a dashed baseline rule, no band. `Sparkline(values:)`, `Hypnogram` + `SleepInterval`/`SleepStage`, `RecoveryRing`.
  For a baseline band write a Swift Charts view with `AreaMark(x:yStart:yEnd:)` + `LineMark`.
- `SceneHeroBackground` loads `scene1…scene10` from the main bundle (StrandiOS assets are compiled into Baseline).

## Reusable NOOP screens
`OnboardingWizard(onFinished:)`, `AddDeviceWizard(live:onClose:startAt:)` (the only one Baseline uses),
`SettingsView()`, `BackupSyncView()`. They say "NOOP" in their copy. Baseline replaced `DevicesView`,
`DataSourcesView` and `AppleHealthView` with its own screens in `Baseline/Screens/Devices` and
`Baseline/Screens/Data`, which call the same engine entry points: `model.importWhoop(url:)`,
`model.importAppleHealth(url:)`, `health.requestAuthorization()`.

## Identity / wiring notes
- UserDefaults keys are `noop.*` in `.standard` (own domain per app, no collision).
- Store lives in the app sandbox (`<AppSupport>/OpenWhoop/whoop.sqlite`); Baseline starts empty.
- A strap bonds to ONE central: never run NOOP and Baseline against the same strap.
- BG task ids derive from `Bundle.main.bundleIdentifier` (listed in project.yml).
