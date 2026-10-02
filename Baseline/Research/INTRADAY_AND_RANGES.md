# Intraday heart rate, HR zones, range aggregates and the one-night view — an engine audit

*Read against the code on 1 October 2026 (HEAD `dbdb2171`). Every claim carries a `path:line`; signatures
are copied from the source. Paths are relative to the repo root. Prose uses Baseline's words (HRV, Resting
HR, Readiness, Sleep, Effort, Steps, Calories, Stress, Intensity minutes); NOOP's identifiers
(`strain`, `recovery`, `hrSample`, …) appear only as code names. Companion to `ENGINE_CAPABILITIES.md`,
which already covers Readiness, Effort, Steps, Calories, VO2 max, Stress and sleep timing; nothing there
is repeated here except where a line number is needed.*

## Summary

| Question | Answer | Where |
|---|---|---|
| Does NOOP keep the strap's continuous HR? | Yes, every second the strap recorded, in `hrSample` (measured) and `ppgHrSample` (5/MG PPG-derived), **never pruned, never downsampled** | §1.1, §1.3 |
| Resolution | 1 Hz on a WHOOP 4.0 (v24 record); 5.0 / MG: per-second HR derived from 24 Hz PPG bursts plus live standard HR about every 30 s | §1.2 |
| "HR between two timestamps" API | `repo.hrSamples(from:to:limit:)` raw, `repo.hrBuckets(from:to:bucketSeconds:)` SQL-aggregated min / mean / max per bucket | §1.4 |
| R-R / intraday HRV | `repo.rrIntervals(from:to:limit:)` + `HRVAnalyzer.rollingRmssd`; hourly `rmssd` in `DaytimeStress.HourPoint` (reported, never scored) | §1.5 |
| Do imports bring intraday HR? | No. CSV: daily / per-workout avg and max only. Apple Health (XML or HealthKit): daily mean / max, per-workout avg / max; raw samples are never stored | §1.6 |
| HR zones | `%HRmax` display zones (`HRZones`, `ProfileStore.hrZoneSet`); Karvonen `%HRR` exists only inside `StrainScorer` as internal helpers | §2 |
| Range aggregates | Every daily metric is a column on the funnel's rows; no weekly / monthly bucketing exists anywhere; Stress and Intensity minutes are intraday-derived and must be memoised per day | §3 |
| Sleep one-night view | Hypnogram, stage totals and vitals exist (`SleepNightCards`); HR during sleep does **not** exist in Baseline yet (NOOP reads `hrBuckets` at 60 s over the session) | §4 |

---

## 1. Intraday heart rate

### 1.1 Tables

`Packages/WhoopStore/Sources/WhoopStore/Database.swift`:

```swift
// :15-20  v1
try db.create(table: "hrSample") { t in
    t.column("deviceId", .text).notNull(); t.column("ts", .integer).notNull(); t.column("bpm", .integer).notNull()
    t.primaryKey(["deviceId", "ts"]) }
// :21-26  v1
try db.create(table: "rrInterval") { … "ts", "rrMs" … primaryKey(["deviceId", "ts", "rrMs"]) }   // + seq/ord/srcChannel/tsSuspect later
// :81-88  v3
try db.create(table: "gravitySample") { … "x", "y", "z" … }
// :245-251  v12 (#156) PPG-derived per-second HR, its OWN table so the measured `hr` is never conflated
try db.create(table: "ppgHrSample") { … "bpm" (.double), "conf" (.double) … primaryKey(["deviceId", "ts"]) }
// :221-227  v10  stepSample (5/MG cumulative counter)
```

One row per second per device, keyed `(deviceId, ts)` in wall-clock unix seconds. `HRSample { ts: Int,
bpm: Int }` (`Packages/WhoopProtocol/Sources/WhoopProtocol/Streams.swift:7-11`); `RRInterval { ts, rrMs,
srcChannel: RRSourceChannel?, ord, seq }` (`:88-100`).

### 1.2 Writers and resolution

- History offload and live stream both land in the same tables: `StreamStore.insert` writes `hrSample`
  with `ON CONFLICT(deviceId, ts) DO NOTHING` (`Packages/WhoopStore/Sources/WhoopStore/StreamStore.swift:199-205`),
  `rrInterval` (`:209-212`), `ppgHrSample` keeping the FIRST estimate for a second (`:391-398`).
  `Strand/Collect/Collector.swift:250` (decoded history batches) and `:351` (`Streams(hr: hr, rr: rr, events:
  contact)` from the realtime stream) are the two call sites, so the live 1 Hz HR you see on Home is banked
  into the same table the history fills.
- WHOOP 4.0: the type-47 `HISTORICAL_DATA` record v24 carries `heart_rate` (u8) and R-R per record, one
  record per second (`docs/BLE_REVERSE_ENGINEERING.md:298-312`); the 14-day store is re-offloaded about every
  15 minutes while connected (`:298-299`). Firmware v25 records carry timestamp + gravity only, no HR
  (`:440-445`).
- WHOOP 5.0 / MG: no per-second HR field; per-second HR is derived from the v26 24 Hz PPG bursts by
  `PpgHr.derivePpgHr` (`Packages/WhoopProtocol/Sources/WhoopProtocol/HistoricalStreams.swift:268, 468`) into
  `ppgHrSample` with a 0–1 autocorrelation `conf`. Live standard BLE HR arrives only about every 30 s
  (`Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift:40-43`), so a 5/MG day is PPG-dense
  only in optical windows (~28,800 rows/day, `Database.swift:550-551`) and sparse otherwise.
  `ScoreConfidence.effort(strain:hrSampleCount:)` (`ScoreConfidence.swift:52`) calls such a day `.building`.

### 1.3 Retention: nothing is downsampled, nothing is dropped

- `Database.swift:546-549`: the v27 waveform table "is the ONE exception to 'no durable per-second table is
  pruned' (`hrSample`, `spo2Sample`, … are still never pruned)". The only caps are newest-N on
  `ppgWaveformSample` (`StreamStore.swift:94`, 604,800 rows) and `v18AuxSample` (`:129`); `PrunePolicy`
  governs `rawBatch` alone (`Database.swift:552-553`; `Strand/Collect/PrunePolicy.swift:7`).
- The strap trims acked history and will not re-send it (`Database.swift:218-220`), so NOOP's SQLite is the
  only durable copy. Consequence for Baseline: continuous HR exists at full resolution for every day since
  the strap was first synced to **this** install (NOOP's store starts empty in Baseline's sandbox,
  `BASELINE.md`), and only for hours the strap was worn and off the charger. A day imported from CSV or
  Apple Health has no intraday HR at all (§1.6). Days older than the pairing are simply absent.
- Downsampling happens only at read time (`hrBuckets`, below). "Does NOOP downsample old days?" — no.

### 1.4 Read APIs

Store level (`Packages/WhoopStore/Sources/WhoopStore/Reads.swift`), all `async throws` on `actor WhoopStore`:

```swift
public struct HRBucket { ts: Int; bpm: Double; minBpm: Double; maxBpm: Double; conf: Double }      // :9-36
public func hrSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [HRSample]   // :61
public func hrFingerprint(deviceId: String, from: Int, to: Int) async throws -> (count: Int, maxTs: Int)   // :104
public func hasHrInWindow(deviceId: String, from: Int, to: Int) async throws -> Bool                 // :133
public func hrWindowStats(primaryId: String, secondaryId: String, from: Int, to: Int) async throws -> HRWindowStats  // :343  { n, avg, max }
public func hrBuckets(deviceId: String, from: Int, to: Int, bucketSeconds: Int) async throws -> [HRBucket]   // :381
public func rrIntervals(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [RRInterval]   // :457
public func latestHRSampleTs(deviceId: String) async throws -> Int?                                  // :864
```

`hrSamples` and `hrBuckets` COALESCE measured `hrSample` with `ppgHrSample` by an anti-join, so a measured
second always wins and a PPG second fills only where nothing was measured (`:56-60`, `:377-380`). `hrBuckets`
groups by `floor(ts / bucket) * bucket`, returns `AVG`, `MIN`, `MAX` and `MIN(conf)` per bucket (`:388-409`):
a 24 h window at 60 s is ≤ 1,440 rows instead of ~86,400 (`:7-8`). The doc at `:12-18` warns that a Min / Max
taken from the bucket **means** describes the calmest five minutes, not the day; use `minBpm` / `maxBpm`.

Repository facades (`Strand/Data/Repository.swift`, `@MainActor`, union over every registered WHOOP id,
active strap first, canonical `"my-whoop"` last; `rawPhysiologyReadIds` `:274-280`, `rawWhoopSourceIds` `:321-328`):

```swift
func hrSamples(from: Int, to: Int, limit: Int = 8000) async -> [HRSample]                         // :1217
func hrSamples(deviceIds: [String], from: Int, to: Int, limit: Int = 8000) async -> [HRSample]    // :1169
func hrFingerprint(from: Int, to: Int) async -> (count: Int, maxTs: Int)?                         // :1242
func hrFingerprintUnion(from: Int, to: Int) async -> String                                       // :1207
func rrIntervals(from: Int, to: Int, limit: Int = 8000) async -> [RRInterval]                     // :1256
func hrBuckets(from: Int, to: Int, bucketSeconds: Int = 300) async -> [HRBucket]                  // :1302
func hrBuckets(deviceIds: [String], from: Int, to: Int, bucketSeconds: Int = 300) async -> [HRBucket]   // :1286
func workoutHrBuckets(from: Int, to: Int, source: String = "") async -> [HRBucket]                // :3327  bucket = clamp(span/120, 15…300 s)
func gravitySamplesUnion(from: Int, to: Int, limit: Int = 200_000) async -> [GravitySample]       // :363
func timelineSeries(metric: TimelineMetric, from: Int, to: Int, targetPoints: Int = 600, source: String? = nil) async -> TimelineSeries   // :1987
nonisolated static func timelineBucketSeconds(spanSeconds: Int, targetPoints: Int) -> Int          // :1913  snaps to 2/5/10/15/30/60/120/300/600/1800/3600
```

Three facts a Baseline screen must respect:

1. **The 8,000 default limit truncates a day.** `hrSamples` is `ORDER BY ts ASC LIMIT`, so a whole-day read
   with the default drops the **newest** rows silently (`Strand/Screens/TodayView.swift:5045-5052`, the bug
   NOOP fixed by passing `limit: 200_000`). Every whole-window consumer passes `200_000`:
   `StressDayCurve.swift:75`, `Baseline/Components/BaselineReadoutsMetrics.swift:673-676`,
   `DayCycleIntelligenceIntegration.swift:225-226`, `Repository.swift:2005`.
2. **Prefer `hrBuckets` for anything drawn or binned per minute.** NOOP's own day chart reads 300 s buckets
   (`TodayView.swift:5004`), the night HR chart 60 s (`Strand/Screens/StagesCard.swift:141-145`,
   `SleepView.swift:915-917`), the circadian fit 3,600 s over 14 days (`Strand/App/AppModel.swift:2239`),
   the HealthKit write-back 60 s (`StrandiOS/Health/HealthKitBridge.swift:1134-1135`). Only Effort,
   Calories and Stress integrate raw seconds.
3. **Hop off the main actor for raw work.** `Repository` is `@MainActor`; the Deep Timeline dedups and sorts
   up to 200k rows inside `Task.detached(priority: .utility)` (`Repository.swift:2000-2010`) and
   `StressDayCurve.today` scores inside `runUnescalated` (`Strand/Data/StressDayCurve.swift:107-111`).
   `hrFingerprint` (one `COUNT` + `MAX` per id over the index, no rows) is the change detector to memoise
   against (`Repository.swift:1235-1241`; used by `StressDayCurve.swift:64-73`).

### 1.5 R-R and intraday HRV

- `rrInterval` holds every beat the strap reported (~100,000 rows/day, `Database.swift:551`), filtered at read
  by `rrIntervals` (one transport per window, suspect-timestamp and duplicate handling, `Reads.swift:412-456`);
  `rawRrIntervals` (`:581`) is the unfiltered diagnostic read. `repo.rrIntervals` merges ids by identity
  (`Repository.swift:1256-1270`). Default `limit: 8000` is again too small for a night; pass `200_000`.
- Windowed RMSSD over a span is pure and public:
  `HRVAnalyzer.rollingRmssd(rr: [RRInterval], windowSec: Int, stepSec: Int = 0, minBeatsPerWindow: Int = 8) -> [RollingRmssdPoint { ts, rmssd }]`
  (`Packages/StrandAnalytics/Sources/StrandAnalytics/HRVAnalyzer.swift:348-351`, `:326-332`), with the
  Task Force RMSSD and Malik cleaning (`:1-25`). NOOP's Deep Timeline picks the window from the span,
  `Repository.hrvRollingWindowSec(spanSeconds:)` = clamp(span / 30, 120…600 s) (`Repository.swift:1928-1931`),
  and labels the series "Windowed rMSSD", never "HRV" (`:1877`).
- Daytime hourly RMSSD exists as `DaytimeStress.HourPoint.rmssd` (`DaytimeStress.swift:170-185`) but is
  reported only, never scored (`daytimeRMSSDScoringEnabled = false`, `:113`), because wrist daytime RMSSD
  swung 40→430 ms on real data. The stored nightly `DailyMetric.avgHrv` is one number per night.
  Baseline should keep intraday HRV off the detail screens except, at most, a night-time rMSSD trace labelled
  as such (§4).

### 1.6 Imports provide no intraday HR

- **WHOOP CSV**: `Strand/Data/WhoopImporter.swift:32, 77, 80` write daily `restingHr`, series `rhr`, `hrv`,
  `avg_hr`, `max_hr`; workouts carry `avgHr` / `maxHr` (`:178-179`). `physiological_cycles.csv` has no
  per-second rows (`Packages/StrandImport/Sources/StrandImport/WhoopExportImporter.swift:269-285`).
- **Apple Health XML**: `AppleHealthAggregator` folds every `HeartRate` record into a per-day mean and
  running max (`Packages/StrandImport/Sources/StrandImport/AppleHealthAggregator.swift:336, 388-392`);
  a workout's `HeartRate` statistics become `avgHr` / `maxHr` (`AppleHealthImporter.swift:562-564`).
  Nothing is written to `hrSample`.
- **HealthKit live sync**: reads `.heartRate` as per-day `discreteAverage` / `discreteMax` only
  (`StrandiOS/Health/HealthKitBridge.swift:512-519`); per-workout HR samples are fetched
  (`fetchWorkoutHeartRate` `:1771-1794`) solely to score an imported workout's Effort, mean and peak
  (`:1687-1695, 1706-1710`) and are discarded. `rawPhysiologyReadIds` lists WHOOP ids only, so Apple HR
  can never reach `hrSamples` / `hrBuckets`. The bridge does the reverse: it **writes** the strap's HR into
  Health as 60 s buckets (`writeHeartRate` `:1129-1180`), an output, not an input.
- So: an intraday HR detail, an Intensity-minutes figure and the Stress curve are strap-only facts. On a
  CSV- or Apple-only day the screen shows the night's / day's aggregates and says "No heart-rate trace for
  this day". The data-source precedence (`baseline.dataSource`) does not apply to these reads
  (`BaselineReadoutsMetrics.swift:659-662` states the same for Stress).

### 1.7 Which "day" a trace belongs to

Three windows exist and they differ:

| Window | Definition | Used by |
|---|---|---|
| Local calendar day | `calendar.startOfDay` … +24 h; key `Repository.localDayKey(_:)` (`Repository.swift:730`) | Home's day switcher (`TodayDaySelection.key` `Baseline/Screens/Today/TodayDaySelection.swift:43`), Baseline's Stress read (`BaselineReadoutsMetrics.swift:666-673`), NOOP's Stress (`StressDayCurve.swift:59-62`) |
| Logical day | rolls at 04:00 local, `logicalDayKey` / `logicalDayStart` (`Repository.swift:738-760`) | which row is "today" (`resolveToday` `:580-585`), the Effort cell's row (`TodaySnapshot.build` `TodaySnapshot.swift:198-211`), NOOP's Today HR window start |
| Sleep-to-sleep cycle | onset of one main sleep to the next (`DayCycleResolver`, `Packages/StrandAnalytics/Sources/StrandAnalytics/DayCycle.swift:28-60`) | the stored Effort, Steps and Calories of a strap day (`Strand/Data/DayCycleIntelligenceIntegration.swift:222-240`: `store.hrSamples(deviceId: owner, from: window.onset, to: hrEndInclusive, limit: 200_000)` → `StrainScorer.strain` / `Calories.estimateDayCalories`) |

Recommendation: the HR detail and Intensity minutes use the **local calendar day** the switcher names
(what the person reads as "Wednesday"), the same window Stress already uses; the caption under Effort keeps
saying it is a sleep-to-sleep figure. Mixing the two silently on one card would make "max HR today" and
"Effort today" describe different hours.

---

## 2. HR zones and what a Karvonen (%HRR) classifier needs

### 2.1 The profile

`Strand/Data/Profile.swift`, `final class ProfileStore: ObservableObject` (`:9`, `@MainActor`, injected app-wide):

```swift
@Published var hrMaxOverride: Int                 // :29   0 = auto (Tanaka); key "profile.hrMaxOverride" :89
@Published var hrZoneThresholds: [Int]            // :31   five inclusive zone starts in bpm, [] = conventional; key "profile.hrZoneThresholds" :90
var age: Int                                      // :176  derived from `dateOfBirth` (#146)
var effortHRmax: Double?                          // :210-212  override, else Tanaka 208 − 0.7·age, else nil (age-less profile)
var hrMax: Int                                    // :215  override, else Tanaka rounded (208 for an age-less profile)
var customHRZoneLowerBounds: [Double]?            // :218-221
var hrZoneSet: HRZoneSet                          // :224-226  HRZones.zones(maxHR: Double(hrMax), customLowerBounds: customHRZoneLowerBounds)
var hasCustomHRZones: Bool                        // :228
```

`effortHRmax` is the number every Effort score is computed against (manual override first, `:195-212`);
`hrMax` is the display model's. Baseline's `ProfileSet.current()` (`BaselineReadoutsMetrics.swift:689`)
says whether age was entered; until then `age` is the seeded 30.

### 2.2 The engine's zone models

**Display zones, `%HRmax`** (`Packages/StrandAnalytics/Sources/StrandAnalytics/HRZones.swift`):

```swift
public struct HRZone { number, lower, upper, lowerPct, upperPct }                                   // :23-42
public struct HRZoneSet { zones: [HRZone], maxHR: Double, source: String; func zoneNumber(forBPM:) -> Int }   // :46-73  (0 below Z1)
public struct TimeInZone { seconds: [Double] (z1…z5), belowZone1: Double; total; seconds(inZone:) }  // :76-96
public static let zoneEdges: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90, 1.00]                        // :99
public static func zones(age: Double, maxHROverride: Double? = nil, customLowerBounds: [Double]? = nil) -> HRZoneSet   // :115
public static func zones(maxHR: Double, source: String = "manual", customLowerBounds: [Double]? = nil) -> HRZoneSet   // :133
public static func defaultLowerBounds(maxHR: Double) -> [Int]                                       // :157
public static func timeInZone(_ hr: [HRSample], zoneSet: HRZoneSet) -> TimeInZone                   // :179-209  hold-until-next, gaps capped at the median interval
```

The file says it plainly (`:16-20`): this is the simpler age-only `%HRmax` model; Karvonen `%HRR` zones are
in `StrainScorer`.

**Karvonen `%HRR`, internal to the package** (`StrainScorer.swift`): the pipeline doc (`:17-18`) defines
HRR = HRmax − RHR and %HRR = (HR − RHR) / HRR × 100; Edwards cut-offs 50 / 60 / 70 / 80 / 90 %HRR
(`:141-144`); `static func pctHRR(_ bpm: Double, restingHR: Double, hrReserve: Double) -> Double` (`:189-194`)
and `static func zoneMinutes(_ hr:restingHR:hrReserve:durations:) -> [Double]` (`:301-308`) are **not
`public`**, so the app module cannot call them. `public static let defaultRestingHR: Double = 60` (`:131`)
and `tanakaHRmax(age:)` (`:154`) are public.

**How NOOP resolves resting HR for a day's %HRR**: the night's `restingHRDaily` else 60
(`AnalyticsEngine.swift:921`: `let restForStrain = restingHRDaily.map(Double.init) ?? StrainScorer.defaultRestingHR`;
the live Today path does the same with `displayDay?.restingHr`, `TodayView.swift:5058`).

### 2.3 What Baseline already does with zones

Workout detail derives a split from the strap's samples with the profile's `%HRmax` zones:
`repo.workoutZoneMinutes(from:to:zoneSet: profile.hrZoneSet, source:)` (`Repository.swift:3346-3356`, binning
with `HRZones.timeInZone`), captioned by `WorkoutsModel.zoneBasis(hasCustomZones:hrMaxOverride:hrMax:)`
(`Baseline/Screens/Workouts/WorkoutsModel.swift:131-133`) and read at
`Baseline/Screens/Workouts/WorkoutDetailScreen.swift:103-114`. Zone colours: `BaselineTheme.zoneColor(_:)`
(`BaselineTheme.swift:100`).

### 2.4 Exactly what a per-day Karvonen classifier needs

Per local day D:

1. **HR series**: `repo.hrBuckets(from: midnight(D), to: midnight(D+1) − 1, bucketSeconds: 60)` → ≤ 1,440
   `HRBucket`s with `bpm` (mean), `minBpm`, `maxBpm`, `conf`. One minute per bucket, so minutes-in-zone =
   count of buckets whose mean falls in the zone; no `timeInZone` duration arithmetic needed. (Raw
   `hrSamples(limit: 200_000)` + `HRZones.timeInZone` gives the same answer to the second at 60× the rows;
   reserve it for a workout window.)
2. **HRmax**: `profile.effortHRmax` (nil until age or an override is entered → the card asks for the profile
   like the Fitness card does), never the 208 default.
3. **Resting HR**: the funnel row for D, `DailyMetric.restingHr` (the night that ended on morning D),
   falling back to the resting-HR baseline going into D
   (`BaselineReadouts.latestNight(upToToday:cfg: Baselines.restingHRCfg)` `.state.baseline` when `usable`),
   then `StrainScorer.defaultRestingHR` with a "using 60 bpm" caption. Nights come from the funnel, so an
   imported night's RHR can serve a strap day's classifier; say which.
4. **Reserve guard**: `hrReserve = HRmax − RHR > 0` (the engine refuses otherwise, `StrainScorer.swift:297-300`).
5. **The formula**, re-implemented in `BaselineReadouts` (one line, tested): `pctHRR = clamp((bpm − RHR) / reserve × 100, 0, 100)`.
   Or express the bands as an `HRZoneSet` and reuse the engine's classifier: lower bound in bpm for a %HRR
   edge p is `RHR + p · reserve`; pass the five values as `customLowerBounds` to
   `HRZones.zones(maxHR:source:customLowerBounds:)` (`HRZones.swift:133`), and `zoneNumber(forBPM:)` /
   `timeInZone` work unchanged (`source` becomes `"custom"`, `:152`).
6. **Intensity bands**: Baseline's own choice, stated once in the card's "How this is computed":
   moderate 40–59 %HRR, vigorous ≥ 60 %HRR (ACSM / Garber 2011), vigorous minutes counted twice toward a
   weekly 150-minute figure (WHO 2020). The engine stores no such number: NOOP's only "Intensity Minutes"
   is the Xiaomi import's `intensity_min` series (`Strand/Data/MetricCatalog.swift:209`,
   `Strand/Data/XiaomiImporter.swift:85`), which Baseline does not read.
7. **Motion gate (optional)**: `repo.gravitySamplesUnion` as `DaytimeStress` uses it (`:59-97`) can mark an
   ambulatory minute; not needed for a minutes-in-zone count, which already asks only "how high".
8. **Confidence**: a day whose buckets are mostly PPG-derived (`conf < 1`) or with fewer than ~600 HR
   seconds gets the `.building` caption (`ScoreConfidence.effort`, `.solid` ≥ 3,600 samples).

---

## 3. Range aggregates (7-day daily, 4-week daily / weekly, 1-year weekly / monthly)

### 3.1 What the funnel exposes per day today

`repo.baselineDays` (`Baseline/Components/BaselineDays.swift:315` → `BaselineReadouts.days(_:mode:)`
`:270-283`, memoised per `(repo, refreshSeq, mode, counts)` `:252-267`) is one `DailyMetric` per day, oldest
→ newest. `repo.baselineSeries(key:)` (`:337`) maps a key through `Repository.dailyColumn(key:day:)`
(`Repository.swift:2555-2573`).

| Metric | Per-day source on the funnel | Readout that already exists |
|---|---|---|
| HRV | `avgHrv` (`hrv`) | `BaselineReadouts.nightlyStates` / `latestNight` (`BaselineReadouts.swift:41-85`); Trends band (`TrendsModel.swift:284-309`) |
| Resting HR | `restingHr` (`rhr`) | same walk with `Baselines.restingHRCfg` |
| Readiness | `recovery` | `readinessScore(for:days:…)`; Effort-and-Readiness points (`TrendsModel.swift:214-240`) |
| Sleep duration | `totalSleepMin` (`sleep_total_min`) | Trends bars (`TrendsModel.swift:178-186`); `sleepAverage30` over `SleepNight` (`BaselineReadouts.swift:93-109`) |
| Sleep efficiency | `efficiency` (`sleep_efficiency`, 0–1 or %, normalised in `SleepNightBuilder` `SleepNight.swift:218-220`) | `SleepNight.efficiency` |
| Sleep timing | **not a column**: `SleepNight.onsetTs` / `wakeTs` from the main-night group (`SleepNight.swift:58-70`), `.dailyMetric` nights have none | `sleepTiming(for:nights:…)` (30 nights), `ProgressSleep.reading` (`ProgressModel.swift:315-325`) |
| Steps | `steps` column, or better `BaselineReadouts.stepReadings(repo, from:to:)` (strap counter → phone → estimate) | `steps(_:for:)`, Trends bars (`TrendsModel.swift:258-280`) |
| Effort | `strain` | Trends bars (`:188-195`) |
| Calories | `activeKcalEst` (`active_kcal`) | `calories(for:days:logicalKey:)` |
| Stress peak / avg | **not a column**: `StressDayReadout { dayMean, peak, highMinutes, … }` from the intraday read (`BaselineReadoutsMetrics.swift:664-680`) | per day only, memoised on Home (`HomeDayCache.updateStress`) |
| Intensity minutes | **nothing stored**: per-day `hrBuckets` + §2.4 | — |
| Readiness drivers, VO2 max | drivers per day (`ChargeBreakdownWiring.breakdown`); VO2 max per week (`ProgressFitness.points` `ProgressModel.swift:546-565`, `Baselines.cutoffKey(carryDays: 7)` steps) | — |

Existing range builders, all pure over `[DailyMetric]` / `[SleepNight]` and computed once per load:
`TrendsSeries.build(days:range:stepReadings:now:)` for 7 / 30 / 90 daily (`TrendsModel.swift:159-212`,
window `:148-151`), `ProgressMetric.build` for 90 / 180 / 365 / all as a trajectory of baselines, not raw
averages (`ProgressModel.swift:191-220`), `ProgressSleep.reading` 30-night windows (`:315-346`),
`ProgressFitness` weekly points (`:546-565`). The `BaselineRangePicker` carries any `BaselineRangeOption`
(`BaselineRangePicker.swift:85-119`; `TrendsRange` `TrendsModel.swift:7-20`, `ProgressHorizon` `ProgressModel.swift:25-70`).

### 3.2 How far back history goes

`Repository.refresh(days: 4000)` publishes rows from `now − 4000 days` (`Repository.swift:939-947`, about
eleven years) — the window, not the span. The real first day is `repo.days.first?.day`, the one deliberate
`repo.days` read (`Baseline/Screens/Data/ExportScreen.swift:73-75`, `ExportFacts.storedLine`). Nights: the
funnel reads sessions over the same 4000-day window with `limit: 4000` per source (`BaselineDays.swift:296-297`).
Day keys are local `yyyy-MM-dd` (`Repository.swift:730`); key arithmetic is `Baselines.cutoffKey(todayKey:carryDays:)`
(`Baselines.swift:130-135`, UTC, pure) and `TrendsDayKey.date(_:)` for an axis `Date` (`TrendsModel.swift:43`).
Rows are sparse: a day the strap was off has no row (`ProgressModel.swift:197`), so a bucket's `n` must be
counted, never assumed.

### 3.3 What is missing: one bucketing engine

No weekly or monthly min / avg / max exists anywhere in NOOP or Baseline. The nearest pieces are
`WorkoutsModel.weeks` (groups on `calendar.dateInterval(of: .weekOfYear, for:)`, `WorkoutsModel.swift:85-98`),
`ProgressFitness`'s seven-day stepping (`ProgressModel.swift:550-562`, weeks ending on today's weekday, not
calendar weeks) and `RollingStepsAverage.calculate` (30 calendar days, missing days excluded, not zero-filled,
`Strand/Data/RollingStepsAverage.swift:7-33`).

Build one pure `BaselineRangeSeries` in `Baseline/Components/` and route every range through it:

```swift
enum RangeBucket { case day, week, month }                       // week = calendar week (firstWeekday honoured), month = calendar month
struct RangeBucketValue: Identifiable { id: String (first day key); start: Date; end: Date; min: Double; avg: Double; max: Double; n: Int }
static func buckets(_ series: [(day: String, value: Double)], from startKey: String, to todayKey: String,
                    bucket: RangeBucket, calendar: Calendar = .current) -> [RangeBucketValue]
```

Rules it should carry (tested): missing days excluded (`n` says how many), a bucket with `n == 0` is absent
(a chart gap, never a zero), the newest bucket is partial and captioned so, `min`/`max` are of the daily
values (for HR that is the night's resting HR, not an intraday extreme), and the 1-year view uses the same
function with `.week` or `.month`. Range → bucket: 7 d → `.day`; 4 w → `.day` (chart) + `.week` (cells);
1 y → `.week` (chart) + `.month` (cells). Context sentence per `DESIGN.md`: one caption with the window's
average and the baseline, said once.

### 3.4 Performance notes

- Daily-column metrics are already in memory (`repo.days`, ≤ ~4,000 rows): bucketing is a few linear passes,
  fine on the main actor once per `(refreshSeq, dataSource, metric, range)`. Memoise exactly as Home does:
  `HomeDayCache` keys entries by `(dayKey, logicalKey, refreshSeq, dataSource, horizon)` and drops everything
  on a new `refreshSeq` (`Baseline/Screens/Today/HomeDayCache.swift:12-20, 71-82`); `BaselineDaysMemo` does
  the same for the table (`BaselineDays.swift:252-267`). A `.task(id: repo.baselineReloadID(dataSourceRaw:))`
  rebuild (`BaselineDays.swift:341-343`) is the trigger.
- Intraday-derived metrics (Stress peak / mean, Intensity minutes, day max HR) cost **one store read per day**:
  `hrBuckets(60 s)` ≈ 1,440 rows, SQL-aggregated. A 7-day range is 7 reads, 4 weeks 28, a year 365 — the year
  must not be read on demand. Precompute per day into a `@MainActor` memo keyed by `(dayKey, hrFingerprint(from:to) )`
  like `StressDayCurve.memos` (`StressDayCurve.swift:43, 64-73`): a past day's fingerprint never changes
  after its last offload, so it is read once per install session; only today's window is re-read, and only
  when `hrFingerprint` moves. Intraday HR lands **without** a `refreshSeq` bump (`HomeDayCache.swift:35`),
  so today's entry re-asks on scene-active and after a sync, as Home's Stress does (`updateStress`).
  *Amended (as shipped in `IntradayDayStore`):* `hrFingerprint` counts the measured `hrSample` table only,
  so it cannot witness a PPG-only day (§1.2: WHOOP 5.0 / MG, and a 4.0 on v25 firmware) or PPG rows landing
  later; the store witnesses each day on its 60-second buckets (measured ∪ PPG: count, last start and a
  checksum) instead, and never serves today from its per-`refreshSeq` memo.
  Read ranges in the background with `Task.detached(priority: .utility)` for the arithmetic and show the
  daily-column cards first.
- Do not derive ranges from raw `hrSamples`: ~86k rows/day × 28 days is the "#1 risk" NOOP's Deep Timeline
  exists to avoid (`Repository.swift:1859-1861`). `hrWindowStats` (`Reads.swift:343`) gives a window's `n / avg / max`
  without materialising rows but has no Repository facade (only `Repository.swift:2889` uses it internally);
  `maxBpm` from `hrBuckets` answers "day max" at no extra cost.
- Sleep timing and regularity are over `SleepNight`s (already built once per `(seq, source)`,
  `HomeDayCache.storeNights`), so a 1-year timing series is a pass over ≤ 4,000 nights.

---

## 4. The one-night Sleep view

Already in Baseline (`Baseline/Screens/Sleep/`):

- `SleepNight` (`SleepNight.swift:14-49`): `onsetTs` / `wakeTs`, `asleepMin`, stage minutes, `efficiency`,
  `restingHr`, `avgHrv`, `respRateBpm`, `skinTempDevC`, `stagingSparse`, `segments: [StageSegment]` in absolute
  seconds; `.dailyMetric` nights (CSV / Apple) carry no times and no timeline (`:12-13`). Built by
  `SleepNightBuilder.nights(sessions:days:habitualMidsleepSec:)` (`:58-70`) over `repo.baselineNights()` and
  `repo.habitualMidsleepSec()` (`SleepScreen.swift:100-103`), stages via `AnalyticsEngine.decodeStages`
  (`AnalyticsEngine.swift:247`; `StageSegment` `SleepStager.swift:33`), trimmed to the edited onset (`:102-105`).
- Cards (`SleepNightCards.swift`): `SleepHeroCard` (ring vs the 30-night average, bedtime / wake / efficiency
  cells, `:14-125`), `SleepHypnogramCard` + `BaselineHypnogram` (`:127-250`, Swift Charts `RectangleMark`
  lanes Awake / REM / Light / Deep over `onset…wake`), `SleepVitalsCard` (`:252-278`), `SleepNightRow`.
  `NightDetailScreen` (`NightDetailScreen.swift:6-20`) shows hero + hypnogram + vitals and is pushed from the
  Nights list with `sleepAverage30(before:in:)` (`SleepScreen.swift:86`).

**Not yet in Baseline: heart rate during the night.** No Baseline file reads `hrBuckets` outside
`WorkoutDetailScreen` (grep). NOOP draws it from
`repo.hrBuckets(from: night.session.startTs, to: night.session.endTs, bucketSeconds: 60)`
(`Strand/Screens/StagesCard.swift:139-145`, `SleepView.swift:915-917`) under the stage timeline. For
Baseline: `repo.hrBuckets(from: night.onsetTs, to: night.wakeTs, bucketSeconds: 60)` → ≤ ~600 rows for a
10-hour night, strap-only, nil for a `.dailyMetric` night (hide the lane, no caption needed beyond the
existing "Stage timeline not available"). Draw it as one `LineMark` in `BaselineTheme.rhr` on the hypnogram's
x-axis (same `onset…wake` domain) with `minBpm` as the night's floor in a `StatCell` beside Resting HR, so the
card keeps one context: "lowest 5-minute 48 bpm · resting HR 52 bpm". `HRBucket.conf < 1` marks a PPG-derived
stretch on a 5/MG night; draw it at `bandOpacity` rather than a different colour.

Optional, honest only with its label: a night rMSSD trace from
`repo.rrIntervals(from: onsetTs, to: wakeTs, limit: 200_000)` + `HRVAnalyzer.rollingRmssd(rr:, windowSec: 300, stepSec: 300)`,
titled "Windowed rMSSD" as NOOP does (`Repository.swift:1877`); the stored `avgHrv` stays the one HRV
number on the card. Given `METRIC_ACCURACY.md` (HRV High as a trend, single windows noisy), this belongs
behind the hypnogram's "How this is computed" at most, not as a second ring or a judged number.

Stage coverage: NOOP captions a night whose device hypnogram arrived only partly
(`HypnogramCoverage.minCoverage`, `StagesCard.swift:129-131`); Baseline shows `stagingSparse` only. Worth
carrying across when the night detail gains the HR lane, since both are per-night facts the accuracy badge
does not state.

---

## 5. Checklist for the builders

1. Intraday reads are **strap-only**, read with `repo.hrBuckets(from:to:bucketSeconds: 60)` (never the 8,000-row
   `hrSamples` default), memoised per day on `hrFingerprint`, and never through the data-source precedence.
2. A day's HR detail uses the local calendar day; Effort / Steps / Calories keep their sleep-to-sleep caption.
3. Intensity minutes = minutes of 60 s buckets at ≥ 40 %HRR (moderate) and ≥ 60 %HRR (vigorous), with
   HRmax = `profile.effortHRmax` (ask for the profile when nil) and RHR = the funnel row's `restingHr`
   (baseline, then 60 bpm, each captioned). "Intensity minutes" is the generic term; never a trademarked name.
4. Ranges go through one pure bucketing function over `[(day, value)]` with `n` per bucket; daily-column
   metrics are cheap, intraday-derived ones are precomputed per day.
5. The night view adds one HR lane under the existing hypnogram from the same `hrBuckets` read; no new ring.
