# What NOOP's engine already provides — an audit for Baseline's next features

*Read against the code on 1 October 2026 (HEAD `f5e7b121`). Every claim carries a `path:line` into the
repo; signatures are copied from the source, not paraphrased. Paths are relative to the repo root.
Vocabulary: Baseline's words in prose (Readiness, Effort, Steps, Calories, Stress, Sleep); NOOP's own
identifiers (`RecoveryScorer`, `DailyMetric.recovery`, `DailyMetric.strain`, "Charge", "Rest") appear
only as code names, because an audit has to cite them exactly.*

## Summary matrix

"Strap" = a WHOOP 4.0 / 5.0 / MG paired to Baseline, no imports. "CSV" = the official WHOOP export
(`physiological_cycles.csv`, `sleeps.csv`, `workouts.csv`). "Apple" = Apple Health, either the XML export
import or the live HealthKit sync. "Funnel" = whether `repo.baselineDays` / `baselineNights()` /
`baselineSeries(key:)` already carry it today.

| Feature | Engine has it | Strap | CSV | Apple | Funnel today |
|---|---|---|---|---|---|
| 1. Readiness composite 0–100 | Yes: `RecoveryScorer.recovery` → `DailyMetric.recovery`, driver rows, confidence tier, colour ramp | Yes (after 4 valid HRV nights) | Yes, WHOOP's own number verbatim | No (`recovery: nil`) | Field is carried; no screen reads it |
| 2. Effort 0–100 | Yes: `StrainScorer.strain` → `DailyMetric.strain`; per-workout `WorkoutRow.strain`; 0–21 display scale | Yes (≥10 min of HR) | Yes, `day_strain × 100/21` | No | Yes: Today, Trends, Workouts |
| 3. Steps | Yes, three sources: 5/MG counter, 4.0 estimate, phone | 5/MG: counted. 4.0: estimated only after phone calibration | No (export has no steps) | XML import: yes. Live sync: AppleDaily only | Field carried; strap + XML steps reach the table; live-sync steps, `steps_est` and the 30-day mean do not |
| 4. Calories | Yes: whole-day HR estimate `DailyMetric.activeKcalEst`; per-workout `energyKcal` | Yes | Day: series `energy_kcal` only. Workouts: yes | AppleDaily `activeKcal/basalKcal`; workouts yes | Field carried; workout kcal shown; no daily calories screen |
| 5. VO2 max / fitness age | Yes: weekly `fitness_age` + `vo2max_est` series (Nes 2011 / Uth 2004) | Yes (≥4 RHR nights in the week) | No | Apple `vo2Max` → AppleDaily + series `vo2max` | No (series keys, not daily columns) |
| 6. Daytime stress | Yes: hourly `DaytimeStress.analyze` from banked HR (+R-R, gravity); daily 0–3 proxy | Yes, when the strap banks daytime HR (4.0 record HR; 5/MG PPG-derived) | Daily proxy series `stress` only, no intraday | No | No |
| 7. Sleep timing | Partly: per-night onset/wake, habitual midsleep (circular mean), a bedtime-spread % and a duration-CV regularity proxy, a need/debt ledger. No true SRI, no "average bedtime / wake" | Yes | Onset/wake per night; WHOOP's consistency/need/debt verbatim | No bed/wake (minutes only) | Onset/wake per night + habitual midsleep yes; everything else no |

---

## 1. Readiness composite 0–100 (NOOP "Charge")

**Scorer.** `Packages/StrandAnalytics/Sources/StrandAnalytics/RecoveryScorer.swift:49` `public enum RecoveryScorer`.

```swift
// RecoveryScorer.swift:316-327
public static func recovery(hrv: Double, rhr: Double, resp: Double?,
                            hrvBaseline: DriverBaseline?, rhrBaseline: DriverBaseline?, respBaseline: DriverBaseline?,
                            sleepPerf: Double?, skinTempDev: Double? = nil, hrvBaselineUsable: Bool = true,
                            recoveryIndexSlope: Double? = nil, effortBaseline: DriverBaseline? = nil,
                            priorDayEffort: Double? = nil) -> Double?
// RecoveryScorer.swift:396-406  — BaselineState overload, gates on hrvBaseline.usable and drops an unusable RHR baseline
public static func recovery(hrv: Double, rhr: Double, resp: Double?, hrvBaseline: BaselineState,
                            rhrBaseline: BaselineState?, respBaseline: BaselineState?, sleepPerf: Double?,
                            skinTempDev: Double? = nil, recoveryIndexSlope: Double? = nil,
                            effortBaseline: BaselineState? = nil, priorDayEffort: Double? = nil) -> Double?
```

- Method (`:8-47`): robust z per term against the personal EWMA baseline (`zScore` `:277`, σ = 1.253·spread),
  weighted mean of z, logistic `100 / (1 + e^(−1.6·(z + 0.20)))` (`logisticScore` `:389-392`), so z = 0 → 58
  (WHOOP's published population mean, `populationMean` `:87`). Weights `:53-80`: HRV 0.55, resting HR 0.20,
  sleep ("Rest" composite ÷ 100, centred 0.85 ± 0.12, `:94-96`) 0.15, respiration 0.05, |skin-temp
  deviation| 0.05, plus two optional nil-default terms nobody wires yet (overnight HR-decline slope 0.05,
  prior-day Effort vs its baseline 0.05). Missing terms drop and the weights renormalise.
- Cold start: nil until the HRV baseline is `usable` (≥ `Baselines.minNightsSeed` = 4 valid nights).
  `calibrationNights(nightlyHrv:dayKeys:hasRecovery:seed:cfg:baselineEpoch:) -> Int?` `:247-260` gives the
  honest "N of 4" count.
- Bands NOOP uses: `bandRedMax = 34`, `bandYellowMax = 67` (`:90-91`), `band(_ score:) -> "red"|"yellow"|"green"`
  `:223-227`. Colour: `Packages/StrandDesign/Sources/StrandDesign/Palette.swift:366` `recoveryColor(_ score:)`
  samples a continuous gradient (`recoveryStops` `:203`), and `recoveryState(_:)` `:384-390` names five
  states: < 25 DEPLETED, < 50 LOW, < 70 MODERATE, < 88 PRIMED, else PEAK. Baseline would map these onto its
  own `good / accent / watch` tokens; the numbers are the reusable part.
- Confidence: `Packages/StrandAnalytics/Sources/StrandAnalytics/ScoreConfidence.swift:33`
  `public static func charge(recovery: Double?, hrvBaseline: BaselineState?) -> ScoreConfidence`
  (`.calibrating` no score / `.building` provisional baseline / `.solid` trusted).

**Driver rows ("what shaped it").** `Packages/StrandAnalytics/Sources/StrandAnalytics/ChargeDrivers.swift:28`
`public struct ChargeDriver { label, deltaPoints: Int, valueText, baselineText, verdict }`;

```swift
// ChargeDrivers.swift:122-129
public static func chargeDrivers(hrv: Double, rhr: Double, resp: Double?, hrvBaseline: BaselineState,
                                 rhrBaseline: BaselineState?, respBaseline: BaselineState?,
                                 sleepPerf: Double?, skinTempDev: Double? = nil) -> [ChargeDriver]
```
Each row's `deltaPoints` is `recovery(all) − recovery(without this term)`, sorted by |delta|; empty when
there is no score. `skinTempRelative(deviationC:) -> SkinTempRelative?` `:91` (tier at ±0.3 °C, `:86`).

**Wiring a screen can copy.** `Strand/Screens/ChargeBreakdownWiring.swift:32-57`
`static func breakdown(days: [DailyMetric], row: DailyMetric, sleepPerfPercent: Double?, hrvBaselineEpoch: Double = 0) -> (drivers: [ChargeDriver], confidence: ScoreConfidence)?`
folds HRV (epoch-aware), resting HR and respiration baselines from `days`, then calls `chargeDrivers`. It is
pure and takes `[DailyMetric]`, so it works verbatim over `repo.baselineDays`. The sheet it feeds is
`Strand/Screens/ChargeBreakdownFormat.swift:18` (`chipLabel`, `chipColor`, `tierTag`, `calibrationProgress`…).

**Where the stored number comes from.**
- Strap pass 1: `Packages/StrandAnalytics/Sources/StrandAnalytics/AnalyticsEngine.swift:885-905` scores the
  night from `avgHRVDaily`, `restingHRDaily`, `respRateDaily`, the Rest composite ÷ 100 and `skinTempDevC`,
  and builds the driver list beside it.
- Pass 2 (re-seeded baseline): `Strand/Data/IntelligenceEngine.swift:3279-3290`
  `private static func recomputeRecovery(_ daily: DailyMetric, _ baselines: AnalyticsEngine.ProfileBaselines) -> Double?`,
  Rest composite from `AnalyticsEngine.Rest.composite(daily:)` (`AnalyticsEngine.swift:1271`).
- Column: `Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift:92` `public let recovery: Double?`;
  `Repository.dailyColumn(key: "recovery", day:)` `Strand/Data/Repository.swift:2557`.

**Availability.**
- Strap only: yes, nil for the first 4 valid HRV nights, `.building` until 14 (`minNightsTrust`).
- CSV: `Strand/Data/WhoopImporter.swift:34` writes `recovery: c.recoveryScore` straight from the CSV column
  "Recovery score %" (`WhoopExportImporter.swift:268`); the series key `"recovery"` too (`WhoopImporter.swift:76`).
  Import-only days are NOT re-scored by NOOP (`IntelligenceEngine.swift:2456-2462` scores only
  `Repository.wearableImportSources` = Oura/Fitbit/Garmin/Health Connect, never `my-whoop`), so a CSV day
  shows WHOOP's model, a strap day shows NOOP's. The two are not on the same scale; a chart that mixes
  them needs a source caption.
- Apple: `Strand/Data/AppleHealthImport.swift:61` and `StrandiOS/Health/HealthKitBridge.swift:625` write
  `recovery: nil`. Apple rows DO carry HRV (SDNN, not RMSSD, `:62` / `:627`) and resting HR, so a NOOP score
  over Apple-only days would need the Apple SDNN folded against its own baseline; the engine never does this.

**Baseline today.** `BaselineDays.fill` carries `recovery` (`Baseline/Components/BaselineDays.swift:182`) and
`repo.baselineSeries(key: "recovery")` returns it, but no screen reads it. Baseline's Readiness is the
three-tier `HRVReadiness.evaluate(avgHrv:)` (`Baseline/Screens/Today/TodaySnapshot.swift:157`), a
seven-night HRV read, not a 0–100 composite. To show the number as "Readiness NN / 100 with a track bar":
read `row.recovery` from the funnel, caption it with `ScoreConfidence.charge`, and offer the
`ChargeBreakdownWiring.breakdown` rows as the "why". Nothing new to compute.

---

## 2. Effort 0–100 (NOOP `strain`)

**Scorer.** `Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift:32` `public enum StrainScorer`.

```swift
// StrainScorer.swift:393-404
public static func strain(_ hr: [HRSample], maxHR: Double? = nil, restingHR: Double = defaultRestingHR,
                          method: Method = .edwards, sex: String = "male", denominator: Double? = nil,
                          diag: ((String) -> Void)? = nil, day: String = "") -> Double?
```
TRIMP (Edwards zones, or Banister) over the day's HR, log-mapped to 0–100 (`maxStrain = 100`, `:51`).
nil under `minReadings = 600` samples AND `minSpanSeconds = 600` (`:37`, `:48`), or when HRmax ≤ resting HR.
`Method` `:149` `{ edwards, banister }`; `tanakaHRmax(age:)` `:154` = 208 − 0.7·age; `defaultRestingHR = 60` `:131`.

**Where the stored number comes from.** `AnalyticsEngine.swift:913-923` scores the CALENDAR day's HR
(`dayHr`), resting HR = that night's `restingHRDaily`, HRmax = profile override or Tanaka. When the
sleep-to-sleep day cycle is established, `Strand/Data/DayCycleIntelligenceIntegration.swift:228-236`
re-scores each cycle window (onset of one main sleep to the next) and `applying(_:to:)` `:345-361` writes
that value into `DailyMetric.strain` for the WAKE day, together with the cycle's steps and calories. So a
strap day's Effort, Steps and Calories all share the same physiological-day window.
Confidence: `ScoreConfidence.effort(strain:hrSampleCount:)` `ScoreConfidence.swift:54` (`.solid` ≥ 3600 samples).

**Display scale.** `Strand/Data/Units.swift:36-43` `enum EffortScale: String { case hundred, whoop }`,
key `UnitPrefs.effortScaleKey = "effort.scale"` `:93`, factor `UnitPrefs.currentEffortDisplayFactor()` `:113-116`
(1.0 or 0.21). Cosmetic only; stored values never change. Baseline prints `/ 100` only
(`BaselineReadouts.effortText` `Baseline/Components/BaselineReadouts.swift:116-122`).

**Load context already available.** `Packages/StrandAnalytics/Sources/StrandAnalytics/ReadinessEngine.swift:93`
`public static func evaluate(days: [DailyMetric], today: String? = nil) -> Readiness` returns `acwr`
(7-day vs 28-day Effort), `monotony` (Foster), `level`, `confidence` (`:60-71`). Baseline's overreaching
signal already uses it (`Baseline/Screens/Today/TodaySignals.swift:223`). `Baselines.strainCfg` exists for an
EWMA Effort baseline (ENGINE_MAP).

**Availability.**
- Strap: yes, nil until ~10 minutes of HR in the window.
- CSV: `Packages/StrandImport/Sources/StrandImport/WhoopExportImporter.swift:33`
  `public static let dayStrainToEffortScale = 100.0 / 21.0`, `effortFromImportedDayStrain(_:)` `:36-39`;
  written at `WhoopImporter.swift:36` (day) and `:177` (workout `activity_strain`, `WhoopExportImporter.swift:363`).
- Apple: `strain: nil` on days (`AppleHealthImport.swift:61`) and workouts (`:83`).

**Baseline today.** `TodaySnapshot.effort` (`TodaySnapshot.swift:112, 131`), Trends `effort: BarMetric`
(`Baseline/Screens/Trends/TrendsModel.swift:116`), Workouts list and detail (`WorkoutsScreen.swift:159`,
`WorkoutDetailScreen.swift:181`). A "Readiness against Effort" chart needs nothing new: both columns are on
every funnel row (`fill` `:182-183`).

---

## 3. Steps

**Column.** `MetricsCache.swift:101` `public let steps: Int?  // daily/file step total from the cumulative @57 counter or activity import`.

**Source A — WHOOP 5.0 / MG hardware counter.** `Packages/WhoopProtocol/Sources/WhoopProtocol/Streams.swift:345`
decodes `step_motion_counter@57`, the strap's cumulative u16 counter (not on 4.0,
`HistoricalStreams.swift:322`). `Packages/StrandAnalytics/Sources/StrandAnalytics/SleepAwareStepCounter.swift:5`
turns the samples into accepted gait ticks (`Count` `:11-20`: outside-sleep, awake-gap, rejected-in-sleep,
rejected-by-activity-class, rejected-implausible). `DayCycleIntelligenceIntegration.swift:320-322` scales
`totalTicks / max(ticksPerStep, 0.5)` and `applying` writes it to the wake day. The scale is a profile setting:
`Strand/Data/Profile.swift:40` `@Published var stepTicksPerStep: Double` (key `"profile.stepTicksPerStep"` `:91`,
default 1.0, clamped 0.5…30 `:132`). The day window comes from
`Packages/StrandAnalytics/Sources/StrandAnalytics/PhysiologicalSteps.swift:4`:
`classifyForCycle(_ blocks: [SleepBlock], offsetSec: Int, habitualMidsleepSec: Int?) -> [SleepBlock]` `:45`,
`cycleWindows(_ boundaries: [CycleBoundary], now: Int) -> [CycleWindow]` `:82`,
`ownerSegmentsFromCoverage(_ window:, coverage:, fallbackOwner:) -> [OwnerSegment]` `:95`. So "steps for a day"
on the strap means sleep-onset to sleep-onset, keyed to the morning you woke — the same key as HRV.

**Source B — WHOOP 4.0 estimate.** The 4.0 sends no step count. `Strand/Data/IntelligenceEngine.swift:2657-2680`
and `:2795-2820`: `StepsEstimateEngine.calibrate` fits the strap's daily gravity-motion volume against the
phone's real step count (Apple Health `steps`) over 60 days, then `estimate(motion:calibration:)` writes a
`"steps_est"` metric-series point under the computed `-noop` source for days the phone did not count
(`:2813`). It is inert without Apple Health steps or a manual coefficient (`profile.stepsManualOverride`).
It is a SERIES, never `DailyMetric.steps`.

**Source C — Apple Health.** XML import: `Strand/Data/AppleHealthImport.swift:66` writes `DailyMetric.steps`
under `"apple-health"` (and `AppleDaily.steps` `:43`, series `"steps"`). Live HealthKit sync:
`StrandiOS/Health/HealthKitBridge.swift:532-545` reads `.stepCount` (cumulative sum per day), but the
`DailyMetric` row it upserts (`:622-628`) has NO `steps`; the count lands only in `AppleDaily` (`:617`) and the
`"steps"` series. That asymmetry matters for Baseline (below).

**Source D — activity file.** `Repository.swift:715` `activityFileSource = "activity-file"`;
`mergeActivityFileSteps(into:_:)` `:1073-1110` fills `steps` where the merged row has none.

**Which wins in NOOP.** `repo.days` (`mergeDaily` `:1056-1072`): imported row wins field by field, computed
fills; then the activity file fills nil steps. Apple rows are NOT in `repo.days` at all (only in
`vitalRows`, `sourceRows` `:1130-1140`). NOOP's Today steps tile uses a separate resolver,
`Strand/Data/RollingStepsAverage.swift:37-49`
`func resolvedSteps(from: String, to: String) async -> MetricSeriesResolution`: measured strap series
`"steps"` → phone `"steps"` (apple-health) → strap `"steps_est"`, first non-nil per day.

**The average the user asked for.** `RollingStepsAverage.swift:7-33`
`struct RollingStepsAverage { let mean: Double?; let observedDays: Int }`,
`static func calculate(readings: [(day: String, value: Double)], ending day: String) -> Self` over a
30-CALENDAR-day window (`startDay(ending:)` `:11`), missing days excluded rather than zero-filled. It is a
pure value type and can be reused as is; the card around it (`RollingStepsAverageCard` `:53`) is NOOP UI.

**Availability.**
- Strap only: 5/MG yes (counted, after the first main sleep establishes a cycle). 4.0: nothing until the
  phone has supplied ≥ some calibration days; then an estimate series only.
- CSV: none. The WHOOP export carries no step column (`WhoopExportImporter.swift:268-301`).
- Apple: XML import → `DailyMetric.steps`; live sync → `AppleDaily` + series only.

**Baseline today.** `fill` carries `steps` (`BaselineDays.swift:188`); `dailyColumn("steps")`
(`Repository.swift:2569`) so `baselineSeries(key: "steps")` works; under `.strapFirst` the strap's counted
steps win and an XML-imported Apple count fills the rest. Nothing reads it. Gaps: (a) live-HealthKit steps
never reach the funnel because `AppleDaily` is not a `DailyMetric`; (b) `steps_est` is a series under the
computed id, which `BaselineDays.series` cannot see; (c) no 30-day mean. A Baseline steps card should read
`repo.resolvedSteps(from:to:)` (strap-first by construction, so it already matches the funnel's precedence)
and `RollingStepsAverage.calculate` for the average, and caption which source supplied the day
(`ResolvedMetricPoint.source`, `Repository.swift:28`).

---

## 4. Calories

**Daily column.** `MetricsCache.swift:102` `public let activeKcalEst: Double?  // whole-day HR-only calorie estimate (kcal)`.
Despite the name it is TOTAL kcal: `Packages/StrandAnalytics/Sources/StrandAnalytics/WorkoutDetector.swift:589-598`
`Calories.DayEnergyEstimate { restingKcal, activeKcal, observedSeconds; var totalKcal }` and
`public static func estimateDayCalories(_ hrSamples: [HRSample], profile: UserProfile, hrmax: Double?, restingHR: Double?) -> Double` `:849-855`
returns `totalKcal`. `estimateDayEnergy(...) -> DayEnergyEstimate` `:775-778` is the split. Method: Keytel 2005
HR→kcal, fitness-adjusted when a VO2 max is known (`vo2maxFor(hrmax:restingHR:)` `:679`, Uth 2004
15.3·HRmax/RHR); each sample credits at most ~60 s on a gappy day. The header says it plainly: "NOT
laboratory calorimetry, NOT Apple/WHOOP cloud parity".
Computed at `AnalyticsEngine.swift:1019-1021` for the calendar day, overridden per sleep-to-sleep cycle at
`DayCycleIntelligenceIntegration.swift:234-236` (same window as Effort and Steps).

**Per workout.** `WorkoutRow.energyKcal` (ENGINE_MAP). Strap-detected bouts use
`Calories.estimateBoutCalories(_:profile:hrmax:restingHR:) -> (Double, Double)` `:709-712` (kcal, kJ), elapsed-time
weighted; `IntelligenceEngine.swift:3203-3218` re-scores an under-scored manual row.

**Not calories, despite the names.** `ActivityCostEngine.swift:101`
`public static func evaluate(activityDaysBySport: [String: Set<String>], recoveryByDay: [String: Double]) -> [ActivityCost]` `:127`
is "how far does next-morning Readiness sit below your rest-day baseline after each sport, and how many
days to bounce back" (`ActivityCost { sport, delta, meanNextMorning, baselineMean, daysToBaseline, n, confidence }` `:51-67`).
`AdaptiveExpenditureEngine.swift:61` `public static func estimate(days: [AdaptiveExpenditureDay]) -> AdaptiveExpenditureEstimate?` `:82`
is a retrospective TDEE from logged calories-in + weigh-ins (≥ 21 days, ≥ 14 intake days at 70 % coverage,
≥ 6 weights, `:70-78`); it has no caller in `Strand/` and needs food logging Baseline does not have.

**Availability.**
- Strap: `activeKcalEst` yes (whenever the day has HR); workouts yes.
- CSV: the day's "Energy burned (cal)" goes to the metric series `"energy_kcal"` only
  (`WhoopImporter.swift:79`), NOT into `DailyMetric.activeKcalEst` (`:23-39` never sets it); workout
  `energy_burned_cal` → `WorkoutRow.energyKcal` (`:177`).
- Apple: `AppleDaily.activeKcal / basalKcal` (`AppleHealthImport.swift:44`, `HealthKitBridge.swift:547-553, 618`)
  plus series keys; `DailyMetric.activeKcalEst` stays nil on Apple rows. Workouts carry `energyKcal` (`AppleHealthImport.swift:81`).

**Baseline today.** `fill` carries `activeKcalEst` (`BaselineDays.swift:189`), `dailyColumn("active_kcal" | "energy_kcal")`
(`Repository.swift:2570`) so `baselineSeries(key: "active_kcal")` returns strap days. Workout detail shows
`energyKcal` (`WorkoutDetailScreen.swift:184`). No daily calories anywhere. Honest framing per
`METRIC_ACCURACY.md`: double-digit error, so show it as a rounded whole-day estimate against its own 30-day
mean, never to the kcal.

---

## 5. VO2 max and fitness age

**Engine.** `Packages/StrandAnalytics/Sources/StrandAnalytics/FitnessAgeEngine.swift:23` `public enum FitnessAgeEngine`
(Nes 2011 HUNT non-exercise model, waist variant; coefficients `:27-29`; `restingHRReference = 65` `:34`,
`paiReference = 5` `:36`, `displayBandYears = 5` `:41`, ages clamped 20–80 `:42`).

```swift
public static func estimateVO2max(age: Double, sex: String, waistCm: Double, ...) -> Double   // :61
public static func fitnessAge(age: Double, sex: String, restingHR: Double, paIndex: Double) -> Double   // :69
public static func physicalActivityIndexFromStrain(activeDaysPerWeek: Int, meanActiveStrain: Double) -> Double   // :115
public static func compute(age: Double, sex: String, restingHR: Double, paIndex: Double, waistCm: Double?) -> FitnessAgeResult?   // :133
public static func assessReadiness(hasAge: Bool, hasSex: Bool, rhrDays: Int, activityDays: Int,
                                   hasHeightWeight: Bool, hasWaist: Bool) -> FitnessAgeReadiness   // :215
public struct FitnessAgeResult { vo2max: Double?, fitnessAge, chronoAge, deltaYears, bandYears, lowerConfidence }   // :254-260
```
`minCoverageDays = 4` of 7 nights of resting HR (`:197`); `nightsUntilReady(rhrDays:)` `:205`.

**Weekly rows.** `Strand/Data/IntelligenceEngine.swift:575-605`
`static func fitnessAgeRows(gateDays: [DailyMetric], age: Int, sex: String, waistCm: Double, heightCm: Double, weightKg: Double, computedId: String, satKey: String) -> [MetricPoint]`:
RHR = median of the week's `restingHr`, PA index from days with `strain ≥ 30`, written as metric-series
`"fitness_age"` and `"vo2max_est"` under the computed `-noop` id, stamped on that week's Saturday. VO2 max is
Nes (needs waist) or else the Uth HR-ratio fallback (`:596-603`), tagged by `Vo2MaxEstimator` (`:617`).
Spec: `docs/FITNESS_AGE.md` (keys table `:70-75`; "a fitness comparison, not a biological age").
NOOP reads it with `repo.resolvedSeries(key: "vo2max_est", source: "my-whoop")` (`Strand/Screens/HealthView.swift:1016`;
`Repository.resolvedSeries(key:source:days:fullHistory:) -> MetricSeriesResolution` `Repository.swift:2255`).

**Apple VO2 max.** `HealthKitBridge.swift:555-558` reads `.vo2Max` (daily average, ml/kg·min) →
`AppleDaily.vo2max` (`:618`) and series `"vo2max"` under `"apple-health"`; XML import the same
(`AppleHealthImport.swift:44`). This is Apple Watch's own estimate, a different method; NOOP keeps it as a
separate series and never merges it into `vo2max_est`.

**Availability.** Strap: weekly, after ≥ 4 RHR nights in the week plus age and sex in the profile; the
explicit VO2 max needs waist for Nes, otherwise the rougher Uth value. CSV: none. Apple: Apple's number.

**Baseline today.** Nothing. Neither key is a daily column, so the funnel cannot carry it; a Baseline card
would read `repo.series(key: "vo2max_est", source: "my-whoop")` / `repo.series(key: "fitness_age", ...)` and
`repo.series(key: "vo2max", source: "apple-health")`, and `SettingsProfileForm` would need age, sex and
(optionally) waist. Per `METRIC_ACCURACY.md` VO2 max from HR alone carries SEE ≈ 5 ml/kg/min; show the
±5-year band and the word "estimate".

---

## 6. Daytime stress

**Daily 0–3 proxy (NOOP's "Stress Monitor").** `Strand/Screens/StressView.swift:15-37`: a stored series
`"stress"` under `"my-whoop"` wins (`repo.series(key: "stress", source: "my-whoop")` `:99`); otherwise
`StressModel.init?(days: [DailyMetric], stored:)` `:840-880` derives it from the newest day with a reading:
`z = (RHR − mean30)/sd30 + (mean30 − HRV)/sd30`, `stress = 3 / (1 + e^(−z))`, baseline = up to 30 prior days.
Bands 0–1 LOW · 1–2 MEDIUM · 2–3 HIGH (`:34`). Empty state `:689-691` "No stress history yet. Import your WHOOP
export…". The CSV import writes its own `"stress"` proxy (`WhoopImporter.swift:104-111`:
`0.6·z(RHR) − 0.6·z(HRV)` over the WHOLE export's mean/sd, `1.5 + z` clamped 0–3, not logistic), so an
imported day and a derived day are two formulas.

**Intraday (hour by hour).** `Packages/StrandAnalytics/Sources/StrandAnalytics/DaytimeStress.swift:29` `public enum DaytimeStress`.

```swift
// DaytimeStress.swift:345-349
public static func analyze(hr: [HRSample], rr: [RRInterval], gravity: [GravitySample] = [],
                           tzOffsetSeconds: Int = 0, mode: ScoringMode = .dayRelative,
                           includeTimeline: Bool = false) -> Result
public enum ScoringMode { case dayRelative; case baselineRelative(hr: BaselineState, rmssd: BaselineState?) }   // :132
public struct HourPoint { hour, startTs, level: Double?, meanHR: Double?, rmssd: Double?, maskedForActivity: Bool }   // :170
public struct Result { hours: [HourPoint], sustainedHigh, sustainedRun, dayMean: Double?, peak: HourPoint?, ... ; static let empty }   // :202, :261
```
Constants `:34-57`: `minHourHRSamples = 300` (≈ 5 min at 1 Hz) before an hour scores; `bucketSeconds = 3600`;
`timelineStepSeconds = 1800` (half-hour display step over full-hour windows); waking hours 06:00–22:00;
`highBandFloor = 2.0`; `sustainedHours = 3`. Motion gate `:77-97`: an hour with ≥ 30 % ambulatory gravity
samples is masked as exertion, and a post-exercise shadow of +8 bpm is applied. HR only:
`daytimeRMSSDScoringEnabled = false` `:113` because wrist daytime RMSSD swung 40→430 ms on real data; the
RMSSD column is reported, never scored. Default mode is day-relative (the day's own calm quartile is the
reference, so no history is needed). The Oura-style personal lens folds 30 past days through
`DaytimeBaselines.swift:120` `foldDaytimeBaselines(days: [DaytimeDayStreams]) -> (hr: BaselineState, rmssd: BaselineState?)`
(`dayDaytimeAggregate` `:68` = the 10th percentile of waking-hour mean HR, `Baselines.daytimeHRCfg`
`Baselines.swift:260`), chosen by `scoringMode(history:)` `:156`; it is opt-in in NOOP (Settings → Experimental).

**How the day's streams are read.** `Strand/Data/StressDayCurve.swift:56-58`
`static func today(repo: Repository, now: Date = Date(), calendar: Calendar = .current, personalBaseline: Bool = false) async -> (result: DaytimeStress.Result, day: Int)?`:
gates on `repo.hrFingerprint(from:to:)` (`Repository.swift:1242`, a COUNT + MAX over the HR index), then
`repo.hrSamples(from:to:limit: 200_000)` (`:1217`, union of every registered WHOOP id), `repo.rrIntervals(...)`
(`:1256`), `repo.gravitySamplesUnion(...)` (`:363`), and `DaytimeStressMode.selected(...)`
(`Strand/Data/DaytimeStressMode.swift`, memoised per day in `StressLensCache` `:27`). `StressView.loadDaytime()`
`:108-135` does the same for [local midnight, now] and sets `daytime = .empty` under 300 samples. The widget
trace is `StrandiOSShared/StressTrace.swift:13` `StressPoint { ts, level: Double?, moving }` and `:45`
`StressTrace.stats / segments / highPoints / movingSpans`, `domainMax = 3`.

**Where the intraday HR comes from, and how dense it is.** The strap's `HISTORICAL_DATA` store is the
source: a 14-day DSP record set re-offloaded about every 15 minutes while connected
(`docs/BLE_REVERSE_ENGINEERING.md:298-299`). WHOOP 4.0 (record v24) carries `heart_rate` and R-R per record
(`:304-312`), so daytime HR is roughly 1 Hz whenever the strap is worn and off the charger. WHOOP 5.0 / MG
record v25 has NO per-second HR field (`:440-443`); per-second HR is derived from the v26 24 Hz PPG bursts by
`PpgHr.derivePpgHr` (`Packages/WhoopProtocol/Sources/WhoopProtocol/HistoricalStreams.swift:267-272, 466-468`),
which is why `ScoreConfidence.effort` calls a PPG-backed day `.building`. Apple HR is never read here
(`rawPhysiologyReadIds` are WHOOP ids only, `Repository.swift:274-280`).

**A day with no daytime stream.** `analyze` returns `.empty` (no hours); `StressDayCurve.today` returns
`(.empty, day)` rather than nil, meaning "scored today, nothing to show" (`:113-117`); NOOP's Today card drops
the line and the Stress screen draws an empty timeline while the daily 0–3 proxy (from last night's RHR/HRV)
still renders. A day where the strap was on the charger for an hour simply has `level == nil` for that hour.

**Availability.** Strap: yes, while the strap banks daytime HR (4.0 directly, 5/MG via PPG derivation).
CSV: daily proxy series only. Apple: none.

**Baseline today.** Nothing beyond the journal "stress" habit chip (`TodaySignals.swift:206`). A Baseline
Stress card can call `StressDayCurve.today(repo:)` as is (strap-only data, so the funnel precedence does not
apply) and draw `result.hours` with a single-colour line and "N hours excluded, you were moving". Honest
labels matter: `METRIC_ACCURACY.md` finds no independent validation for daytime stress on any wearable; the
engine's own header says APPROXIMATE and non-clinical, and the HR-only lens is validated r ≈ 0.6 against
Oura on one subject (`DaytimeStress.swift:97-113`).

---

## 7. Sleep timing, regularity, need and debt

**Per night.** `Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift:14-54` `public struct CachedSleepSession`:
`startTs: Int` `:15` (immutable detected onset), `endTs: Int` `:16` (wake), `startTsAdjusted: Int?` `:28` and
`public var effectiveStartTs: Int { startTsAdjusted ?? startTs }` `:30` (the user's corrected onset),
`userEdited` `:25`, `stagingSparse: Bool?` `:37`, `deviceId: String?` `:54`. Bedtime and wake per night are
therefore `effectiveStartTs` / `endTs` of the day's main-night group (`SleepView.mainNightGroup(_:habitualMidsleepSec:)`,
which Baseline already calls at `Baseline/Screens/Sleep/SleepNight.swift:82`).

**Habitual midsleep.** `Strand/Data/Repository.swift:1507-1528` `func habitualMidsleepSec(days: Int = 4000) async -> Int?`
→ `Packages/StrandAnalytics/Sources/StrandAnalytics/SleepStageTotals.swift:788`
`public static func habitualMidsleepSec(_ history: [HistoryBlock], offsetSec: Int, ...) -> Int?`: the CIRCULAR
mean of the midpoint time-of-day of the longest block per local day; nil under `habitualMinDays = 14` `:779`.
It is a local-clock seconds value, so "your usual midsleep is 03:40" is one subtraction away, and bedtime /
wake follow from it: `NightStandDown.swift:44`
`public static func band(habitualMidsleepSec: Int?, typicalSleepHours: Double?, leadSeconds:, tailSeconds:) -> Band?`
uses `BatteryEstimator.bedtimeSec(midsleepSec:sleepHours:)` and `midsleep + halfNightSec`. There is NO
average-bedtime or average-wake-time function as such; the engine learns the midpoint and derives the edges.

**Consistency / regularity (three different things, none a true SRI).**
1. `Strand/Screens/SleepModel.swift:439-468` `static func consistencySeries(days: [DailyMetric], sleeps: [CachedSleepSession], importedSleep: [String: ImportedSleepFigures]) -> Metric`:
   WHOOP's imported `sleep_consistency` % when it covers the latest night; otherwise, per night, the SD of
   bedtime-of-day (`effectiveStartTs`, evening onsets wrapped past midnight) over the trailing 14 nights,
   scored `100·(1 − sd/120 min)`, clamped, ≥ 3 nights. This is the number NOOP's `ConsistencyCard`
   (`Strand/Screens/ConsistencyCard.swift:19`) and the Sleep tile show. It measures bedtime spread only, not wake.
2. `Packages/StrandAnalytics/Sources/StrandAnalytics/VitalityEngine.swift:102-110`
   `public static func sleepConsistency(nightlyHours: [Double]) -> Double?` = `1 − CV` of nightly DURATIONS
   (the file calls it "a rough but honest on-device proxy for the Sleep Regularity Index when we only have
   durations"). `IntelligenceEngine.swift:1004` feeds the last 28 nights of it into the Rest composite's
   0.10 "consistency" term (`AnalyticsEngine.swift:1160-1161`, `composite(tstSeconds:inBedSeconds:efficiency:restorativeSeconds:needHours:consistency:deepSeconds:)` `:1235-1242`).
3. `WeeklyDigest` `consistencySD` = SD of the week's Rest scores (`WeeklyDigest.swift:157`).
A grep for "regularity index", "SRI", "wake spread" finds nothing else: the engine never scores
epoch-by-epoch sleep/wake agreement between consecutive days, and never looks at wake-time spread.

**Need and debt.** `Repository.swift:11-16` `struct ImportedSleepFigures { performancePct, consistencyPct, needMin, debtMin }`,
published as `@Published var importedSleep: [String: ImportedSleepFigures]` `:190`, built from the metric-series
keys `sleep_performance / sleep_consistency / sleep_need_min / sleep_debt_min` (`:961-974`) that only the CSV
import writes (`WhoopImporter.swift:84-86`). The on-device ledger:
`Packages/StrandAnalytics/Sources/StrandAnalytics/SleepDebt.swift:143`
`public static func ledger(series: [(day: String, totalSleepMin: Double?)], needHours: Double = AnalyticsEngine.Rest.defaultNeedHours, window: Int = defaultWindowNights) -> SleepDebtLedger`,
`debtSeries(series:needHours:importedDebtMin:window:) -> [(day: String, value: Double)]` `:98-103`,
`creditedSleepMin(mainSleepMin:napSleepMin:) -> Double?` `:87`; constants `defaultWindowNights = 14` `:67`,
`debtCarryFactor = 0.55` `:70`, `minimumDebtMin = 10` `:73`. The need it measures against:
`SleepModel.debtNeedMin(days:)` `:385-389` → `AnalyticsEngine.Rest.personalizedNeedHours(nightlyHours: [Double], age: Int?) -> Double`
(`AnalyticsEngine.swift:1219`; upper-quartile of unrestricted nights, floored at the adult 8 h,
`defaultNeedHours = 8.0` `:1175`). The descriptive `sleepNeedMin(days:)` `:372` is `max(450, mean)`.
The card: `Strand/Screens/SleepDebtLedgerCard.swift:20` reads `model.sleepDebtLedger`.

**Availability.**
- Strap: onset / wake / midsleep yes (after the first main sleep; midsleep after 14 days); bedtime-spread
  consistency after 3 nights; need after enough nights (population default before); debt ledger immediately.
- CSV: `sleeps.csv` onset/wake → `CachedSleepSession(startTs:endTs:...)` (`WhoopImporter.swift:45-58`; naps
  skipped); WHOOP's `sleep_consistency`, `sleep_need_min`, `sleep_debt_min` verbatim per day.
- Apple: XML import writes sleep MINUTES into `DailyMetric` only (`AppleHealthImport.swift:55-69`); the live
  sync too (`HealthKitBridge.swift:591-595, 622-628`); neither writes a `CachedSleepSession`, so Apple nights have
  no bedtime, wake or midsleep.

**Baseline today.** `SleepNight.onsetTs / wakeTs` (`Baseline/Screens/Sleep/SleepNight.swift:20-22`) from
`SleepNightBuilder.nights(sessions:days:habitualMidsleepSec:)` `:58` over `repo.baselineNights()`
(`BaselineDays.swift:333`), with `repo.habitualMidsleepSec()` at `SleepScreen.swift:84`, `TodayScreen.swift:229`,
`ProgressScreen.swift:72`. So every night's bedtime and wake are already in Baseline's model; what is missing
is the arithmetic over them: the 30-night mean bedtime / wake (circular, like `habitualMidsleepSec`), a
consistent-window score (`METRIC_ACCURACY.md` recommends an SRI-style measure), and need / debt. The
`SleepDebt` ledger is pure and takes `(day, totalSleepMin)` pairs, so it runs over `SleepNight.asleepMin`
directly; `repo.importedSleep` is not routed through the funnel and is import-only, so a Baseline debt
figure should be the on-device ledger with the imported `debtMin` as a comparison caption at most.

---

## 8. What the Baseline funnel exposes today, and what it does not

**Entry points.** `Baseline/Components/BaselineDays.swift:270` `static func days(_ repo: Repository, mode: BaselineDataSource = .current()) -> [DailyMetric]`;
`:291` `static func nights(_ repo:, mode:, now:) async -> [CachedSleepSession]`;
`:306` `static func series(_ repo:, key: String, mode:) -> [(day: String, value: Double)]`;
shims `:313-343` (`repo.baselineDays`, `baselineToday`, `baselineWeek`, `baselineNights()`, `baselineSeries(key:)`,
`baselineReloadID(dataSourceRaw:)`). Pure engine `BaselineDays.days(vitalRows:merged:mode:)` `:117`,
`fill(_:from:)` `:167-196`, `nights(imported:computed:merged:mode:endDay:)` `:217`, `series(key:days:)` `:239`.

**Carried on every row (strap wins field by field, imports fill).** `fill` `:172-195` keeps `recovery`,
`strain`, `exerciseCount`, `steps`, `activeKcalEst`, the sleep block, the vitals. `Repository.dailyColumn`
(`Repository.swift:2555-2573`) maps the series keys `recovery, hrv, rhr, strain, resp_rate, spo2, skin_temp,
sleep_total_min, sleep_efficiency, sleep_deep_min, sleep_rem_min, sleep_light_min, sleep_performance (the
Rest composite), steps, active_kcal | energy_kcal`, so `baselineSeries` already answers 1, 2, 3 (strap +
XML-import steps) and 4 (strap days).

| Needed for | Where it lives in NOOP | Reaches the funnel? | What to add |
|---|---|---|---|
| Readiness number, driver rows | `DailyMetric.recovery`; `ChargeBreakdownWiring.breakdown(days:row:...)` | Yes | Read it; nothing new |
| Effort vs Readiness chart | `DailyMetric.strain` + `.recovery` | Yes | Nothing new |
| Steps (counted / XML) | `DailyMetric.steps` | Yes | A card + 30-day mean (`RollingStepsAverage.calculate`) |
| Steps (live HealthKit), 4.0 estimate | `AppleDaily.steps`; series `steps_est` (computed id) | No | Read `repo.resolvedSteps(from:to:)`, which already prefers the strap |
| Daily calories | `DailyMetric.activeKcalEst` (strap); series `energy_kcal` (CSV); `AppleDaily.activeKcal` | Strap only | Decide whether CSV/Apple kcal should fill; if so, read the series by source |
| VO2 max, fitness age | series `vo2max_est`, `fitness_age` (computed id); Apple series `vo2max` | No | `repo.series(key:source:)` reads, profile fields |
| Daytime stress | `StressDayCurve.today(repo:)`, `DaytimeStress.analyze` | n/a (raw strap streams, no precedence) | Call it directly |
| Daily stress proxy | series `stress` (CSV) or derive from RHR/HRV | No | Derive over `baselineDays` with Baseline's own band (the engine's z-logistic is in `StressView.swift:840-880`, not in a package) |
| Bedtime / wake per night | `CachedSleepSession.effectiveStartTs / endTs` | Yes (`SleepNight.onsetTs/wakeTs`) | Averages and a window score over `SleepNight` |
| Habitual midsleep | `repo.habitualMidsleepSec()` | Yes | Nothing new |
| Sleep need / debt | `SleepDebt.ledger / debtSeries`; `Rest.personalizedNeedHours`; `repo.importedSleep` | Ledger is pure (usable); `importedSleep` no | Run the ledger over `SleepNight.asleepMin` |
| Regularity | bedtime-spread % (`SleepModel.consistencySeries`, a screen-side function), duration-CV (`VitalityEngine.sleepConsistency`) | No | Both are small enough to re-implement in `BaselineReadouts` against `SleepNight`; neither is an SRI |

**Two precedence facts worth remembering.** (1) Under `.merged`, Apple-only days are absent, because NOOP's
`repo.days` merges `imported ∪ computed` only (`mergeDaily` `Repository.swift:1056-1072`) and Apple rows exist
solely in `vitalRows` (`sourceRows` `:1130-1140`); under `.strapFirst` and `.importOnly` Baseline's `fold`
(`BaselineDays.swift:138-159`) does include them, in `importOrder` WHOOP export → Apple → local cache. (2) A CSV
day's `recovery` is WHOOP's model and a strap day's is NOOP's; `fill` lets the strap win where it has a
value, so a mixed history silently changes formula at the import boundary. A Readiness chart over mixed
sources should caption the source per point (`repo.vitalRows` carries it).
