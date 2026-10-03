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
  Do NOT use `dailyMetrics(fromDay:toDay:)` (imported rows only). A Baseline screen reads `repo.baselineDays`
  (`Baseline/Components/BaselineDays.swift`: the same table under the persisted `baseline.dataSource`
  precedence, strap first by default; see DESIGN.md "Data funnel"), never `days` itself. Import's
  stored-history count is the one deliberate read of `days`.
- `@Published var vitalRows: [SourcedDailyMetric { metric: DailyMetric, source: DailyMetricSource }]` — the same
  nights BEFORE the merge, one row per source (`.whoopImport`, `.noopComputed` = the strap's own, `.appleHealth`,
  `.localCache`), published on every refresh. This is what Compare pairs night by night; `days` has already
  let the higher-priority source win (`DailyMetricSource.vitalPriority`).
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
- `IllnessSignalEngine.evaluate(_ inputs: Inputs, context: Context, …)` (Packages/StrandAnalytics): the composite
  "watch" read over the last two nights (RHR up, HRV down, skin temp / resp rate up) with confounder
  suppression from the journal. Baseline's Today Signals card feeds it (`Baseline/Screens/Today/TodaySignals.swift`).
- Recipe:
  ```swift
  let hist = repo.baselineDays.filter { $0.day < todayKey }   // the funnel, never repo.days
  let s = Baselines.foldHistory(hist.map(\.avgHrv), dayKeys: hist.map(\.day), cfg: Baselines.hrvCfg)
  guard s.usable else { /* calibrating */ }
  let d = Baselines.deviation(todayHrv, state: s)  // d.delta ms, d.ratio, band = s.baseline ± Baselines.sigma(s)
  ```

## Baseline readouts over the engine (Baseline/Components/BaselineReadoutsMetrics.swift)
Every screen reads these through `BaselineReadouts` (pure, tested; `@MainActor` wrappers take the `Repository`
and go through the funnel). The NOOP entry point behind each is listed so nobody recomputes it.
- Readiness: `readinessScore(for:days:epoch:strapScores:) -> ReadinessScore? { score, tone (good/watch/low:
  "Good"/"Fair"/"Low"), confidence, drivers, driversSentence }` reads `DailyMetric.recovery` as stored (NOOP's
  `RecoveryScorer`, bands `RecoveryScorer.bandRedMax` / `bandYellowMax`), drivers from
  `ChargeBreakdownWiring.breakdown` folded over the nights before the day, only for a strap-scored day
  (`strapScores(repo.vitalRows)`). `readinessCalibrationNights` / `readinessSeedNights` (4, `Baselines.minNightsSeed`).
  `TodayReadinessScore.build` (Today) adds the carry rule for an unsynced morning.
- Steps: `steps(_ repo:for:mode:) -> StepsReadout { steps, average7, average30, observed7/30, recent, source,
  sources, state }` (Baseline/Components/BaselineActivityReadouts.swift: `StepSource` .strap / .phone /
  .estimate / .imported, one source per day, never summed); `stepReadings(_ repo:from:to:mode:)` =
  `repo.resolvedSteps(from:to:)` (strap counter → phone → strap estimate; `.importOnly` keeps the apple-health /
  health-connect points only) with the funnel's `steps` column filling the gaps; `stepSourcedReadings` attaches
  the day's source. `windowAverage(before:window:readings:)` needs `averageMinDays` (3) observed days.
  `StepGoal` (`baseline.stepGoal`, default 8,000, 3,000–30,000 step 500) drives `goalFraction` / `goalDays`.
- Calories: `calories(_ repo:profile:for:mode:entered:bodySet:calendar:now:) async -> CaloriesReadout { totalKcal,
  restingKcal, activeKcal, activeSource, activeAverage30, bodyAssumed, heightCm, weightKg, isPartialDay }`.
  Resting = Mifflin–St Jeor BMR (`bmrMifflin`, clamped 800–4,000) × `dayFraction` (so noon is BMR / 2); active =
  NOOP's `Calories.estimateDayEnergy` activeKcal over the day's heart rate (persisted per day by
  `IntradayDayStore`, version 3), else Apple Health's `active_kcal`, never both. `calorieReadings` is the one
  per-day series the card, the detail and Trends read. NOOP's own `active_kcal` column (resting + active) is
  no longer read by any screen.
- Stress: `stressDay(_ repo:for:now:calendar:includeTypical:) -> StressDayReadout? { points (hourly 0–3, never
  printed), lens (.personal(floorBPM:) / .learning(daysOfHistory:)), restoredHours, calmHours, elevatedHours,
  movingHours, typicalElevatedHours, peakHour, sustainedFrom, floorBPM }`: today via NOOP's
  `StressDayCurve.today(personalBaseline: true)` (cached per day by NOOP's `StressLensCache`), past days via
  `StressDayStore` (Application Support/Baseline/stress-days.json), which folds the 30 days before a day with
  NOOP's `dayDaytimeAggregate` / `scoringModeFromAggregates` / `foldAggregates` and follows
  `DaytimeStressMode.selected`. Hour states `StressState` (elevated ≥ 2.0 = floor + 15 bpm while still, calm
  1.6–2.0, restored < 1.6); a day is totalled from 3 scored hours; typical = median of 14 prior qualifying days
  (needs 5). Hours only on screen, never a 0–100 score.
- Friends aggregate (Baseline/Components/BaselineFriendsAggregate.swift): `friendsDailyAggregates(for repo:
  days:profile:mode:...) -> [FriendsDailyAggregate { day, steps, stepsSource, intensity, active, sleepGoal,
  bedtime }]`, the behaviour values the Friends upload sends (steps only from strap or phone, recorded-only
  Intensity, 0/1 flags); `SleepGoal` = `baseline.sleepGoalMinutes` (default 450). Physiology goes up only as
  the weekly change against the person's own `Baselines` state (`FriendsUploadBuilder`).
- Sleep timing: `sleepTiming(for:nights:window:calendar:) -> SleepTiming { nights (session nights only),
  averageBedMinutes / averageWakeMinutes (circular mean, ≥ 3 nights), regularity (SRI-like over consecutive
  nights, ≥ `regularityMinPairs` = 5 pairs of the last 14), target: SleepWindow, nightsInWindow }`.
  `SleepWindow.stored()` / `save()` are the `baseline.sleepWindow.*` defaults (± `toleranceMin` 30).
  Helpers: `minutesOfDay`, `circularMeanMinutes`, `clockText` / `hourText` (device clock style), `noonInterval`, `median`.
- Fitness: `fitness(_ repo:profile:for:mode:entered:) -> FitnessReadout? { result: FitnessAgeResult, vo2max,
  vo2IsFallback, restingHr (week median), rhrNights, activeDays }` over NOOP's `FitnessAgeEngine` (Nes 2011 with
  a waist, else the Uth `15.3·HRmax/RHR` fallback), gated like `IntelligenceEngine.fitnessAgeRows` but on a
  calendar week (not NOOP's last seven rows). `ProfileSet.current()` (`baseline.profileSet`) says whether age
  and sex were entered; until then they pass as nil and the Progress card asks for them.
- Accuracy: `MetricAccuracy.all` (Baseline/Components/MetricAccuracy.swift, 14 rows verbatim from
  `Baseline/Research/METRIC_ACCURACY.md`, tiers high / medium / low), drawn as `AccuracyBadge(metric:)`; the
  citations are `AccuracyCitations` (Baseline/Screens/Settings/AccuracyScreen.swift).

## Metric details, daytime heart rate, Intensity minutes (Baseline/Components)
- Ranges (`BaselineReadoutsRanges.swift`): `MetricRange` (1D / 7D / 4W / 1Y), `MetricKey` (hrv, rhr, readiness,
  sleepDuration, sleepEfficiency, bedtime, wake, steps, effort, calories, stressAvg, intensityMinutes,
  heartRate), `metricReadings(key:days:nights:stepReadings:intraday:)` → `[MetricDayValue]`, the pure
  `metricSeries(key:range:endKey:readings:bands:intraday:)` → `MetricSeries { points: [RangePoint], stats:
  MetricStats }` and the `@MainActor metricSeries(_ repo:profile:key:range:endDay:nights:mode:entered:…)` over
  the funnel. 1Y buckets are ISO weeks (`BaselineRangeSeries.isoCalendar()`), keyed by the Monday; stats are
  always over daily values; the change compares with the previous window of the same length (≥ 3 days each
  side). HRV / Resting HR bands come from `Baselines` per night (`metricBands`). The screen is
  `MetricDetailScreen(spec: MetricDetailSpec, day:initialRange:)` (`MetricDetail.swift`); the route table
  Home and Trends share is `TodayDetail.spec(_:)`.
- Daytime heart rate (`BaselineReadoutsIntraday.swift`): `intradayHeartRate(_ repo:for:nights:mode:)` over
  `repo.hrBuckets(from:to:bucketSeconds: 60)` (Strand/Data/Repository.swift: measured `hrSample` ∪ PPG-derived
  `ppgHrSample`, SQL-aggregated) for the local day, with sleep spans from the nights and workout spans from
  `repo.workoutRows`; `IntradayHeartRate { points, sleep, workouts, minBpm, avgBpm, maxBpm, coveredMinutes,
  partial }`, `intradayContext`, `intradaySummary`. Sleep's night trace is `SleepHeartRateBuilder.trace(_ repo:night:)`.
- Intensity minutes (`IntensityMinutes.swift`): `Thresholds.karvonen(restingHr:hrMax:)` (40 / 60 % of heart-rate
  reserve; max HR from `ProfileStore.effortHRmax` / the override, resting reference = median of the last 7
  nights, `RestingReferences` for many days at once), `Thresholds.hrMax(zoneSet:)` fallback, `minutes(samples:)`
  (≥ 20 samples a minute, median) / `minutes(buckets:)`, `bouts(_:thresholds:rule:)` (≥ 3 min, 1-min gap),
  `credit(day:minutes:thresholds:)` → `DayResult { moderateMin, vigorousMin, credited = m + 2v }`,
  `creditFromWorkouts(day:rows:)` from `WorkoutZones` when a day has no heart rate. `mayScore(entered:hrMaxOverride:)`
  is the one gate (nothing is scored before an age or a manual max HR). Goal: `goal()` / `saveGoal(_:)` on
  `baseline.intensityGoalMinutes`. Readout: `BaselineReadouts.intensity(_ repo:profile:for:mode:)` →
  `IntensityReadout { moderateMin, vigorousMin, weekDays, weekGoal, basis; weekText, splitText }`; its week,
  Trends' weeks and the detail's 7D / 4W / 1Y totals all come from `BaselineRangeSeries.weekTotals`.
- Per-day cache (`IntradayDayStore.swift`): `IntradayDayStore.shared.records(_ repo:profile:days:mode:entered:…)`
  → `[String: IntradayDayRecord]` (Intensity minutes, heart-rate low / mean / high, Stress day mean), persisted
  at `<Application Support>/Baseline/intraday-days.json`; `reset()` is Settings › Data › "Recompute heart-rate
  days". `BaselineReadouts.intradayValues(_:)` lifts records into the range series. Accuracy for both keys comes
  from `MetricDetailSpec.standard(key).accuracy` (Medium), listed on the Accuracy screen by `AccuracyExtras`
  with `AccuracyCitations.intensityReferences` (`Baseline/Research/INTENSITY_MINUTES.md`).

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
  Baseline's `JournalScreenModel` reads `repo.baselineSeries(key:)` instead (the strap-first funnel over
  `Repository.dailyColumn`; `repo.series` is NOOP's import-wins cache).

## Design system (Packages/StrandDesign)
- Tokens: `StrandPalette` (surface/text/hairline, `accent`, score colours, sleep-stage colours), `StrandFont`.
- Components: `StrandCard`, `ChartCard`, `StatTile`, `InsightCard`, `SectionHeader`, `SegmentedPillControl`, `StatePill`,
  `ConnectionDot`, `TrendChip`, `TypicalRangeBar(value:typical:color:)`.
- Charts (Swift Charts): `TrendChart(points: [TrendPoint(date:value:segment:)], gradient:, baselineValue: Double?, …)`
  draws a dashed baseline rule, no band. `Sparkline(values:)`, `Hypnogram` + `SleepInterval`/`SleepStage`, `RecoveryRing`.
  For a baseline band write a Swift Charts view with `AreaMark(x:yStart:yEnd:)` + `LineMark`.
- `SceneHeroBackground` loads `scene1…scene10` from the main bundle (StrandiOS assets are compiled into Baseline).

## Export + notifications (Strand/Data/CsvExport.swift, Strand/System)
- `CsvExport.run(repo:) async -> ExportResult { .exported(URL) | .cancelled | .failure(String) }` builds the CSV
  zip off the main actor (`WhoopCsvExporter`, Packages/StrandImport) and ends in `DocumentPicker.export(_:) async
  -> URL?` (the system picker). Baseline's Export screen wraps it; the files it describes mirror the exporter.
- `NotificationPresenter.shared` (`UNUserNotificationCenterDelegate`) is NOOP's one delegate with no chaining
  hook; `BaselineNotificationDelegate` is registered instead and forwards both callbacks to it, adding only the
  evening check-in category → `baseline.pendingTab`. `MorningSummaryNotifier.requestAuthorization` is the single
  authorization ask both Settings toggles go through.

## Reusable NOOP screens
`OnboardingWizard(onFinished:)`, `AddDeviceWizard(live:onClose:startAt:)` (the only one Baseline uses),
`SettingsView()`, `BackupSyncView()`. They say "NOOP" in their copy. Baseline replaced `DevicesView`,
`DataSourcesView` and `AppleHealthView` with its own screens in `Baseline/Screens/Devices` and
`Baseline/Screens/Data`, which call the same engine entry points: `model.importWhoop(url:)`,
`model.importAppleHealth(url:)`, `health.requestAuthorization()`.

## Identity / wiring notes
- UserDefaults keys are `noop.*` in `.standard` (own domain per app, no collision). Baseline's own are
  `baseline.*` (table in BASELINE.md). Baseline type names must not collide with NOOP's module-level ones
  (same module), and must not shadow a type an imported package exports either, or NOOP's own files in the
  Baseline target stop compiling: e.g. `CompareRange` is NOOP's (`Strand/Screens/CompareView.swift`), ours is
  `BaselineCompareRange`; WhoopStore's `MetricPoint` and StrandAnalytics' `DayValue` are why the range layer
  says `RangePoint` and `MetricDayValue`.
- Store lives in the app sandbox (`<AppSupport>/OpenWhoop/whoop.sqlite`); Baseline starts empty.
- A strap bonds to ONE central: never run NOOP and Baseline against the same strap.
- BG task ids derive from `Bundle.main.bundleIdentifier` (listed in project.yml).
- Friends (Baseline/Friends/) uses no NOOP API beyond the readouts above: it talks to its own Supabase project
  (or the in-memory demo backend) through `FriendsBackend`, and never touches the WhoopStore schema. The only
  network code Baseline adds is `SupabaseREST` (URLSession) plus the Sign in with Apple id_token exchange.
