# Steps, Calories and Stress: how six apps present them, what the evidence says, and what Baseline will do

*Written 2 October 2026 against NOOP HEAD (`Packages/StrandAnalytics/.../DaytimeStress.swift`,
`DaytimeBaselines.swift`, `Baselines.swift`, `WorkoutDetector.swift` (`enum Calories`), `Strand/Data/StressDayCurve.swift`,
`DaytimeStressMode.swift`, `Profile.swift`, `StrandiOS/Health/HealthKitBridge.swift`) and Baseline HEAD
(`Components/BaselineReadoutsMetrics.swift`, `Screens/Today/TodayScreen.swift`). Vendor behaviour comes from the vendors'
own manuals and help pages fetched that day. Where a vendor page could not be fetched (WHOOP and Apple block automated
reads) the claim is marked "(search summary)" or "(community source)". Every paper was checked against Europe PMC
(title, authors, journal, volume, pages, DOI) before it was cited. Vendor feature names appear only to say what a
vendor calls its own feature. Baseline's copy never uses them (see the vocabulary rules in `BASELINE.md`).*

## The short version

- **Steps.** Every app shows the day's count against a daily goal. Defaults differ: Fitbit 10,000, Garmin 7,500
  that then adjusts itself, Samsung 6,000 (community source). WHOOP and Oura let you set your own. The
  evidence points lower than 10,000. Mortality benefit flattens at about 6,000–8,000 steps a day over age 60 and
  8,000–10,000 under 60 (Paluch 2022). Most outcomes flatten at 5,000–7,000 (Ding 2025). **Baseline default: 8,000, editable, fixed
  (not auto-adjusting), with the iPhone's Apple Health count as the fallback when the strap counted none.**
- **Calories.** Everyone reports *total = resting + active*. The resting part is a profile equation (age, sex,
  height, weight) and is credited for the whole day whether or not the device was worn. Fitbit, Garmin, WHOOP and
  Samsung say so; Apple and Oura report the same split. No consumer device is within 20% of calorimetry
  (Shcherbina 2017). **Baseline: its own Calories card. It shows the total with the resting/active split, resting from
  Mifflin–St Jeor over the whole day, active from the strap's heart rate (NOOP's Keytel model), an estimate badge,
  and a comparison with the person's own average only.**
- **Stress.** Garmin and Samsung use Firstbeat-style HRV (0–100). WHOOP shows a 0–3 number against a 14-day
  baseline. Oura shows time in four states against a personal baseline and gives no score. Fitbit/Google add skin
  conductance (EDA) and report a 1–100 resilience-style score and "body responses". None has independent
  validation that it tracks *felt* stress. The best study found plain heart rate did better than Garmin's score
  (Rosenbach 2025). **Baseline: Oura-style hours of calm vs elevated time against the person's own daytime
  heart-rate floor. It is shown only on days the strap recorded, never as a 0–100 score, and never in the hero.**
- **Intensity minutes** are already specified in `INTENSITY_MINUTES.md` (Karvonen 40/60 % HRR, vigorous ×2,
  150/week, Monday week).

### Why they "disappeared" from Home (diagnosis, Baseline HEAD)

All three are computed today, but Home hides them under conditions that are easy to miss:
- **Steps:** `TodayScreen` draws `StepsCard` only when `steps.hasRecordedSource`. If the strap is on the bicep or
  body, WHOOP counts no steps; WHOOP says Steps is enabled only when the device is worn on the wrist (search
  summary). If Apple Health steps aren't authorised or synced, the card vanishes.
- **Intensity minutes:** the card is drawn only once there are credited minutes, or on today as the one prompt
  for an age (`showsIntensity`).
- **Calories:** there is no card. It is a cell inside `EffortCard`.
- **Stress:** the card is drawn only when an hour was scored, or on today with a paired strap. Past days are
  scored *day-relative* (`.dayRelative`): the day's own calm hours are its baseline, which hides a day that was
  elevated from start to finish.

---

## (a) Steps

### How each app presents steps

| App | Default daily goal | Auto-adjusts? | Phone fallback when the wearable can't count | What the card shows |
|---|---|---|---|---|
| **Garmin** | 7,500 ("Your device begins with a default goal of 7,500 steps per day") [V1] | Yes, by default ("creates a daily step goal automatically, based on your previous activity levels"); can be switched to a fixed goal in Garmin Connect [V1]. The exact formula is not published; forum posts describe small daily steps toward recent activity (community source). | No: steps come from the watch | Count, goal progress, distance, floors; the week's bars against the goal |
| **Fitbit / Google** | 10,000 ("The default goal is to take 10,000 steps per day") (search summary of Fitbit help) | No; user-set | Yes: the Google Health/Fitbit app can count steps on the phone (help-centre topic "Track your steps with Google Health on your phone") [V2] | Count against the goal, distance, active-zone time; hourly bars |
| **Apple (Health / Fitness)** | Health has no step goal. Fitness rings use active calories, exercise minutes and standing time. | Move-goal suggestions are weekly; steps have no goal | The iPhone *is* the fallback: "When you carry your iPhone… motion sensors track your steps, distance, and flights climbed" (Apple Support, search summary). Health de-duplicates by source priority: manual entry first, then iPhone/iPad/Watch, then apps and devices; the top source wins where sources overlap [V3] | Count, distance, daily average, highlights against your own average; Fitness Trends compare recent activity with your longer average [V4] |
| **Oura** | Calorie target by default; since May 2025 members can pick a step target instead and can hide calories [V5] | The daily goal moves with Readiness: above the chosen baseline goal when Readiness is ≥ 85, below it when < 70 (search summary of Oura help) | No documented phone-steps fallback; the 2025 update imports partner heart rate (e.g. Apple Health) for activity analysis [V5]. The same update changed step detection to "more like a pedometer", with "an average decrease in step count of 20%" [V5] | Steps, total burn and active burn, goal progress |
| **WHOOP** | No fixed default: the member sets a target in the app (search summary) | No | No: steps come only from the strap, worn on the wrist (search summary). Added by app update for WHOOP 4.0 in October 2024 [V6] | Count on the main dashboard; weekly, monthly and six-month trends (search summary). WHOOP justified the feature with the ~8,200-steps finding of Master 2022 [6] |
| **Samsung Health** | 6,000 (community source) | No | The phone and the watch count separately; "All steps" combines all connected devices into one count, or one source can be picked [V7] | Count against the target; hourly/daily/weekly/monthly graphs [V7] |

**Patterns worth copying.** (1) The count is always visible, even when it's zero. (2) There is one goal, shown
as a bar or fraction. (3) One device's count wins on a given day: Apple's source priority and Samsung's
source picker both avoid adding watch and phone together. (4) Goal adjustments are explained (Oura: "because
Readiness was high"). **Pattern to avoid:** a goal that drifts without the person changing it (Garmin's automatic
goal) makes "met my goal" mean something different every week. Baseline already shows the 7-day average as context,
so the goal can stay fixed.

### Evidence for a default goal

- **Paluch et al. 2022** (15 cohorts, 47,471 adults, 3,013 deaths): quartile medians 3,553 / 5,801 / 7,842 /
  10,901 steps; mortality HR 0.60, 0.55 and 0.47 for Q2–Q4 vs Q1. Mortality risk fell with more steps until
  **6,000–8,000/day at age ≥ 60** and **8,000–10,000/day under 60**. Stepping *rate* added little once steps were
  accounted for [1].
- **Saint-Maurice et al. 2020** (NHANES, 4,840 adults ≥ 40, ~10 years follow-up): **8,000 vs 4,000 steps/day,
  HR 0.49**; 12,000 vs 4,000, HR 0.35. Step intensity was not associated with mortality after adjusting for total
  steps [2].
- **Ding et al. 2025** (57 studies / 35 cohorts): non-linear curves with inflection points around **5,000–7,000
  steps/day** for all-cause mortality, CVD incidence, dementia and falls; **7,000 vs 2,000** steps meant 47% lower
  all-cause mortality (HR 0.53) [3].
- **Banach et al. 2023** (17 cohorts, 226,889 people): each extra 1,000 steps meant 15% lower all-cause mortality (HR
  0.85). Benefit started around 3,867 steps/day [4].
- **Tudor-Locke et al. 2011** (adult review): about 7,000–8,000 steps/day matches the 150-minute guideline;
  the 10,000 figure is a convention, not a threshold [5]. **Master et al. 2022** (All of Us): about 8,200
  steps/day was associated with lower risk of several chronic diseases [6].

**Recommendation: 8,000 steps a day by default.** It sits at the top of Ding's inflection range, at the start of
Paluch's under-60 plateau, inside the over-60 plateau, and is the exact contrast Saint-Maurice tested. A WHOOP strap
counts fewer steps than a wrist watch does (`METRIC_ACCURACY.md`, steps = Medium), so 10,000 would be harder to
reach for no extra health benefit. The goal is editable and does not adjust itself.

---

## (b) Calories

### Total, active and resting

All six apps agree on the arithmetic: **total = resting (BMR or RMR) + active**.

| App | Resting part | Active part | What the card shows |
|---|---|---|---|
| **Apple** | "Resting Energy" in Health. Apple does not publish the equation. | "Active Energy" (the calorie ring in Fitness) from motion + HR | Active is the headline; total = active + resting is something you add up yourself [V4] |
| **Garmin** | "Resting calories" are an RMR estimate "based on your age, height, weight and gender"; Garmin uses RMR rather than BMR and does not publish the equation (Garmin forum moderators, community source) | Active calories from HR/motion and activities | Total, resting and active, with the split |
| **Fitbit / Google** | BMR "based on… height, weight, sex, and age"; credited all day whether the device is worn or not [V2] | From activity + HR | One total ("calories burned"), which already contains BMR |
| **WHOOP** | BMR "using widely accepted formulas based on height, weight and gender" (search summary of WHOOP support; the page blocks automated reads) | BMR plus a function of heart rate | Calories inside the daily load view |
| **Oura** | Part of "total burn" | "Active burn"; heart rate during exercise counted since May 2025 [V5] | Total burn and active burn; calories can be hidden [V5] |
| **Samsung** | Resting calories from the Health profile | Activity calories | "Total burned" ≥ "activity calories" (Samsung community) |

**How BMR is estimated.** The two common equations are **revised Harris–Benedict** (Roza & Shizgal 1984) [7]
and **Mifflin–St Jeor** (1990) [8]. The Academy of Nutrition and Dietetics review compared Harris–Benedict,
Mifflin–St Jeor, Owen and WHO/FAO/UNU and found Mifflin–St Jeor "the most reliable". It predicted RMR to within
10% of measured values in more non-obese and obese people than any other equation and had the narrowest error
range, though older adults and minority groups were under-represented [9].
**NOOP uses revised Harris–Benedict** for resting energy and **Keytel 2005** [10] for active energy above 50 %
heart-rate reserve (`Calories.estimateDayEnergy`, the day-path gate `dayActiveHRRFraction = 0.50`). It integrates
resting energy **only over the seconds the strap observed** (60 s gap cap). The value it persists,
`DailyMetric.activeKcalEst`, is actually the *total* (resting + active), and on a day the strap spent on the
charger the resting part is under-counted. That is why the number Baseline shows today reads low and jumpy.

**Accuracy.** Shcherbina et al. (2017; 60 adults, seven wrist devices against indirect calorimetry): HR error
under 5% for most devices on the bike, but "No device achieved an error in EE below 20 percent" [11]. Fuller et
al. (2020; 158 studies): no brand measured energy expenditure accurately [12]. `METRIC_ACCURACY.md` rates
calories **Low**: "No consumer device within 20% of calorimetry; show relative to your average only." The
resting equation has its own error: Mifflin–St Jeor is within 10% for most adults but can miss individuals by
more [9].

**Patterns worth copying.** Credit resting energy for the whole day, as Fitbit and Garmin do, so calories don't
drop when the strap charges. Show the resting/active split so the person can see that most of the number is a
formula. Round the numbers. Let people hide calories, as Oura does.

---

## (c) Stress

### How each app does it

| App | What is shown | Inputs | Baseline | Data needed |
|---|---|---|---|---|
| **Garmin** (Firstbeat) | 0–100 level: 0–25 rest, 26–50 low, 51–75 medium, 76–100 high [V8]. A separate 5–100 "reserve energy" gauge is built from "heart rate variability, stress level, sleep quality, and activity data" [V9] | HRV while inactive ("analyzes your heart rate variability while you are inactive") [V8] | Firstbeat's model of the person built from their own beat-to-beat data [V10] | Continuous HRV-grade beat data; activity periods are shown as activity, not stress |
| **WHOOP** | 0–3 in real time: about 0–1 calm, 1–2 alert, 2–3 highly activated (search summary of WHOOP's launch article and support page) | HR and HRV, adjusted for motion | The **last 14 days'** HRV plus the person's typical resting HR (search summary) | Continuous HR + R-R from the strap |
| **Oura** | **No score.** Four states: Stressed, Engaged, Relaxed, Restored. The day shows **"Stressed" and "Restored" totals** and a colour-banded curve [V11] | "Heart rate, HRV, motion, and average body temperature" [V11, V12] | "compared against your personal baseline, which is recalibrated daily" [V11] | Updated "every 15 minutes during periods when you're awake, wearing your ring, and relatively inactive". It skips activity, sleep, poor signal and big movement. It needs "at least five days of continuous wear (day and night)" first [V11] |
| **Fitbit / Google** | A 1–100 score from three parts (responsiveness 30, exertion balance 40, sleep 30), now presented as resilience levels ("Optimal / Balanced / Low"), plus "body responses" alerts [V13, V14] | "Heart-rate, heart-rate variability, and electrodermal activity or EDA data, if available". Continuous EDA only on Sense 2 / Pixel Watch 2+ [V13] | Not documented [V13] | Continuous EDA sensor for body responses; HR/HRV/sleep for the score |
| **Samsung** | Stress level, green (low) to red (high), on demand (1–2 min, sitting still) or continuous [V15]. Press reports describe the 0–100 scale as Firstbeat's (search summary) | HRV ("heart rate variability (HRV) to estimate stress levels") [V15] | Not documented | Still wrist, snug fit [V15] |

### Validation evidence

- **Kim et al. 2018** (37-study meta-analysis): HRV falls in response to acute laboratory stress, so the
  direction of the signal is real [13].
- **Rosenbach et al. 2025** (preregistered, n = 60, Garmin vívosmart 4 vs Polar H10 ECG during rest and
  mental-stress tasks): Garmin's score separated stress from rest and correlated with HR and RMSSD. But "heart rate showed
  the strongest association with self-reported stress", and the Garmin score had "only marginal predictive
  value for subjective stress" [14]. (`METRIC_ACCURACY.md` reports its correlation figures from the preprint.)
- **van der Mee et al. 2024/2025** (preprint; 95 students, 28 days of momentary mood reports): Garmin's score was
  linked to high- and moderate-intensity *positive* mood and inversely to "calm"/"relaxed". It was *not* linked to
  high-arousal negative mood, and the authors call the name "Stress Score" "incorrect and misleading" [15].
- **Martinez et al. 2022** (657 office workers, 14,695 momentary stress ratings, Garmin): HRV features explained
  on average **about 1% of the variance** in perceived stress (2.2% at best, using work hours) [16].
- **Föhr et al. 2015** (n = 221, Firstbeat HRV over work days): subjective stress was only weakly linked to
  HRV-measured stress (P = 0.047) [17].
- **Ronca et al. 2023** (n = 12): Fitbit Sense EDA correlated with research devices but was significantly less
  reliable [18]. No peer-reviewed validation of Fitbit's body responses, Oura's daytime stress or WHOOP's 0–3 score
  was found. Doherty et al. (2025) note the lack of validation for these composite scores
  (`METRIC_ACCURACY.md` [31]).
- **NOOP's own check** (code comment, not peer-reviewed): an HR-only personal-baseline read correlated r ≈ 0.6
  with Oura's own stress signal over 26 days. A day-relative read scored worse (r 0.43–0.53)
  (`DaytimeStress.baselineRelativeHighMarginBPM`). NOOP leaves daytime RMSSD **out** of the live score because wrist
  daytime RMSSD is dominated by artefact (`daytimeRMSSDScoringEnabled = false`).

**What this means.** Today's stress tools measure *arousal* (heart rate above your calm level while you aren't
moving), not felt stress. Excitement, caffeine, a meal or a hot room read the same as a tense meeting. A 0–100
number suggests precision that isn't there. Oura's time-in-states presentation against a personal baseline is the
most honest of the five, and it maps onto what NOOP already computes.

### Recommended Baseline presentation (per the coordinator's decision)

Hours of **calm vs elevated** time against the person's **own daytime heart-rate floor**. No score, nothing on the
hero, shown only on days the strap recorded daytime heart rate, and a Low accuracy badge. Exact states and
thresholds are in the spec below.

---

## (d) Intensity minutes

See `INTENSITY_MINUTES.md` §5. It uses Karvonen %HRR (moderate ≥ 40 %, vigorous ≥ 60 %), NOOP's %HRmax zones
as the fallback, a 3-minute bout floor with no 10-minute rule, vigorous counted twice, a Monday–Sunday local week
and a 150-minute goal (`baseline.intensityGoalMinutes`, 60–600). It is already built (`IntensityMinutes.swift`,
`IntradayDayStore`). Considered and reverted at integration: forcing the card on every paired morning ("0 min today ·
0 / 150 this week"). Home keeps the old rule: the card shows once the day or the week so far has minutes, a past
day once its heart rate was scored, and on today as the one ask for an age.

---

## Implementable spec

All reads go through `BaselineReadouts` / `BaselineDays` (strap-first funnel). No NOOP file changes.

### 1. Steps card (`StepsCard`, always present on Home)

**Visibility.** Shown on every Home day, including days with no count. Zero is not a placeholder, but if *no
source* recorded anything the card says so (state 3 below). This replaces `if let steps, steps.hasRecordedSource`.

**Data.** `BaselineReadouts.steps(repo, for: day)` (existing). Per day, precedence stays as now: the strap's counted
steps → the iPhone's Apple Health steps (`Repository.appleHealthSource`) → the strap's calibrated estimate →
the funnel's `steps` column. One source per day, **never summed**. Add `source: StepSource`
(`.strap | .phone | .estimate | .imported`) to `StepsReadout`, from the winning resolved point's `source`.

**Goal setting.** `@AppStorage("baseline.stepGoal")`, default **8,000**, range 3,000–30,000 in steps of 500 (the floor is Friends' server floor, so Home and Friends
judge a day against the same goal).
`StepGoal.goal(defaults:)` / `set(_:)` clamp, mirroring `IntensityMinutes.goal()`. Settings → Profile gets a "Step
goal" stepper card beside "Intensity goal". It never adjusts itself.

**Fields** (top to bottom; each number's context appears once):
1. Title: "Steps" (past day) / "Steps so far" (today) + `AccuracyBadge(metric: "steps")` (Medium).
2. Hero: count, `hero(36)`, `stepsText` ("6,240").
3. Goal track: one horizontal capsule (never a ring) filled to `min(count / goal, 1)`, label "6,240 / 8,000".
   When met: "Goal met" in the `steps` tone. Today before met: "1,760 to go".
4. Context line (unchanged rule): past day "+1,240 vs your 7‑day average" / "On your 7‑day average" (±5 %);
   today "7‑day average 7,480" (no judgement of a partial day); "7‑day average after 3 days" while building.
5. Source caption (only when not the strap): "From iPhone (Apple Health)" / "Estimated from the strap".
6. Seven-bar week sparkline (existing `StepsTile` bars), with a goal tick line at `goal`.

**States.** (1) counted: as above. (2) zero but a source exists: hero "0", track empty, context line as usual.
(3) no source at all for the day: hero "–", one line: "No steps yet. The strap counts steps on the wrist only;
allow Apple Health steps to use your iPhone's count." The line includes a `BaselineChevronRow` to Settings → Apple
Health. Only on today; past days in state 3 show "No steps recorded".

**Detail (`.steps`).** Week bars against the goal, "Goal met 4 of 7 days", 7- and 30-day averages, the source per
day, and the accuracy caveat. No distance in v1: the strap has no GPS, and a stride estimate would be a second estimate
stacked on the first.

**Friends hook.** The day's steps and goal-met boolean are what Friends may share for step competitions
(behaviour metric, head-to-head allowed).

### 2. Calories card (`CaloriesCard`, its own card; Effort loses its calorie cell)

**Placement.** Its own card after `EffortCard`. Shown on every day with any active-energy source or a usable
profile. If neither exists, it is left out.

**Formula.**
- **Resting (BMR), Mifflin–St Jeor** [8], kcal/day, W = kg, H = cm, A = years:
  - `sex == "male"`: `10·W + 6.25·H − 5·A + 5`
  - `sex == "female"`: `10·W + 6.25·H − 5·A − 161`
  - `"nonbinary"` / anything else: `10·W + 6.25·H − 5·A − 78` (the male/female midpoint, the same convention
    NOOP's `Calories.nonbinary` uses)
  - Clamp to 800–4,000 kcal/day.
  - Past day: the full BMR. Today: `BMR × secondsSinceLocalMidnight / 86 400` ("so far").
  - Credited whether or not the strap was worn (the Fitbit/Garmin convention).
- **Active:** strap first. `Calories.estimateDayEnergy(hr, profile:, hrmax:, restingHR:).activeKcal` over the
  local calendar day's HR, computed in the same `IntradayDayStore` pass that scores Intensity minutes and cached
  per day key on the same witness. Use `profile.effortHRmax` and the same RHRref as Intensity. Take **only**
  `.activeKcal`: NOOP's resting part covers observed seconds only, and Mifflin replaces it. Fallback when the strap
  banked no HR that day: Apple Health `active_kcal` (`resolvedSeries(key: "active_kcal", source: appleHealthSource)`),
  labelled "Active from Apple Health". In imports-only mode, only the Apple value. Never add strap and Apple together.
- **Total** = resting + active.

**Inputs from `ProfileStore`, and what happens when they're missing.**
- Age (`dateOfBirth` → `age`) and sex are trusted only when `BaselineReadouts.ProfileSet.current()` is true. NOOP
  seeds 30 / "male" and persists them, so the store alone can't tell a default from a real entry.
- Height and weight: NOOP seeds 178 cm / 75 kg and persists those too. Add `baseline.bodySet` (Bool), written by
  Settings → Profile when height or weight is edited or confirmed. For weight, prefer the latest Apple Health
  `weight` point within 90 days, then `profile.weightKg` when `bodySet`.
- **Missing age or sex** (`ProfileSet == false`): resting and total are hidden. The hero is the active figure
  alone, titled "Active calories", with one line: "Add your age and sex in Profile to include resting calories"
  (chevron to Settings → Profile).
- **Age and sex present, height/weight not confirmed**: compute with the stored values and add the caption "Using
  178 cm · 75 kg. Edit in Profile". Stays until `bodySet`.
- **No active source that day and no profile**: card left out.

**Fields.**
1. Title "Calories" (today "Calories so far") + `AccuracyBadge(metric: "calories")` (Low), whose popover carries the card's caveat ("Heart-rate estimate; …"); no separate "Estimate" pill.
2. Hero: total, `caloriesText` (rounded to 10), unit "kcal".
3. Split line: "1,620 resting · 520 active" (each rounded to 10). Optionally a two-segment flat bar, resting in
   `ringTrack` and active in the calories tone. A bar, not a ring.
4. Context (once), on **active** only, because resting is a formula and nearly constant: "+180 active vs your
   30‑day average" / "On your 30‑day average" (±5 %), past days only, ≥ 7 observed days. Today: no judgement.
5. Caveat in the detail and the badge popover: "Heart-rate estimate; no wrist or strap device is within 20 % of
   lab measurement. Compare with your own days, not with food labels."

**Readout.**
```swift
struct CaloriesReadout {
    let day: String
    let restingKcal: Double?       // nil when ProfileSet == false
    let activeKcal: Double?        // strap Keytel active, else Apple Health active_kcal
    var totalKcal: Double? { restingKcal.flatMap { r in activeKcal.map { r + $0 } } ?? nil }
    let activeSource: Source       // .strap | .appleHealth
    let activeAverage30: Double?   // mean active over the 30 days before `day`, ≥ 7 observed
    let bodyAssumed: Bool          // true while height/weight are NOOP's seeded defaults
    let isPartialDay: Bool         // today
}
static func bmrMifflin(sex: String, weightKg: Double, heightCm: Double, age: Double) -> Double
```
Tests: male 75 kg / 178 cm / 30 y → 1,717.5; female 60 / 165 / 40 → 1,270.25; nonbinary midpoint; clamping;
today's proration at 12:00 = BMR / 2; missing profile → resting nil; strap and Apple never summed.

### 3. Stress (Home `StressCard` + the `.stressAvg` detail)

**Engine and lens.** Use the **personal-baseline lens** everywhere Baseline draws Stress:
- Today: `StressDayCurve.today(repo:, personalBaseline: true)`.
- Past days: `DaytimeStressMode.selected(repo:, startOfToday: <that day's midnight>, personalBaseline: true)`, then
  `DaytimeStress.analyze(..., mode: mode)`. Note that `StressLensCache` has one slot, so a past-day read evicts
  today's lens. Cache Baseline's past-day readouts per day key in `HomeDayCache` so that cost is paid once.

The mode is `.baselineRelative(hr:, rmssd: nil)` once the daytime-HR baseline is `.usable`, which needs
`Baselines.minNightsSeed` = 4 days with a daytime aggregate in the 30 days before the day. Until then NOOP returns
`.dayRelative`.

**What the levels mean under `.baselineRelative`** (HR-only, because RMSSD is gated off):
`floor` = the person's daytime-HR baseline, an EWMA of each day's 10th-percentile waking-hour mean HR (≈ "how low
my HR runs when calm and awake"). `σ = 15 / ln 2 ≈ 21.6 bpm` (`marginToSigma(15, atBand: 2.0)`), so an hour's
`level = 3 / (1 + e^(−(meanHR − floor)/21.6))`:
- `meanHR = floor` → 1.50
- `floor + 3 bpm` → 1.60
- `floor + 15 bpm` → 2.00 (NOOP's HIGH band, `highBandFloor`)
- `floor − 15 bpm` → 1.00

**Hour states** (one per non-overlapping `Result.hours` entry, waking hours 06:00–22:00, one hour each):

| State | Rule | Meaning in bpm (baseline lens) | Copy |
|---|---|---|---|
| **Elevated** | `level ≥ 2.0` (= `DaytimeStress.highBandFloor`) | mean HR ≥ floor + 15 bpm while not moving | "Elevated" |
| **Calm** | `1.6 ≤ level < 2.0` | floor + 3 to + 15 bpm | "Calm" |
| **Restored** | `level < 1.6` | at or below the floor, within its 3 bpm `floorSpread` | "Restored" |
| Moving | `maskedForActivity == true` | ≥ 30 % of the hour ambulatory, or the one-hour post-exercise shadow | "Moving", hatched, not counted |
| No reading | `level == nil && !maskedForActivity` | < 300 HR samples in the hour | gap, not counted |

The constants live in Baseline: `StressStates.elevatedFloor = DaytimeStress.highBandFloor`, `restoredCeiling = 1.6`.
Totals are hour counts, because the scorer's grain is one hour: "2 h", never minutes, so we don't imply more
precision than the data has. `elevatedHours × 60` equals NOOP's `highStressMinutes`; assert this in a test.

**Gating.**
- **No card** on a day with no scored hour (`StressDayReadout == nil`). The exception is today with a paired strap:
  keep the one "No daytime data yet" card.
- **Under 3 scored hours:** curve only, the line "Only 2 h of still, daytime wear, too little to total", no totals.
- **Lens still `.dayRelative`** (fewer than 4 days of daytime history): curve only, coloured by the same thresholds
  but **no Calm/Elevated/Restored totals**, and the line "Learning your daytime baseline · 2 of 4 days". A day
  measured against itself can't say whether it was a stressful day.
- **Lens `.baselineRelative`:** totals shown.

**Home card fields** (placed after Sleep, never in the hero, never a ring, never a 0–100 number):
1. Title "Stress" + `AccuracyBadge(metric: "stress")` (Low).
2. Headline row: "**2 h** elevated · **7 h** calm · **2 h** restored" (bold numerals, `hero` not used).
3. One flat stacked bar of scored hours (restored / calm / elevated in three tones of the stress colour, moving
   hours as a hatched grey stub at the end, labelled "1 h moving").
4. Context (once): elevated hours compared with the person's own **14-day typical**, the median `elevatedHours`
   over the 14 days before the day, using days with ≥ 3 scored hours, and needing ≥ 5 such days (the Oura convention):
   "Less elevated time than your typical 3 h" / "About your typical 2 h" (±1 h) / "More elevated time than your
   typical 1 h". Before 5 days: "Your typical appears after 5 days of daytime wear". Today shows "so far" and makes
   no comparison before 18:00.
5. The existing curve (`StressCardBody` / `BaselineStressChart`) with the y-axis **unlabelled numerically**. Bands are
   shaded Restored / Calm / Elevated; the 0–3 values never print. Change `stressSummary` and VoiceOver from
   "Stress averaged 1.4 of 3 (Medium)" to "2 hours elevated, 7 calm, 2 restored, 1 hour moving". Keep
   `stressLevelText` for tests only.

**Detail page (1D) additions.**
- Lens line: "Against your daytime heart-rate floor: 64 bpm (30 days)". `floor` comes from the resolved mode's
  `hr.baseline`, so expose it on `StressDayReadout` as `floorBPM: Double?`.
- Peak hour: "Most elevated 14:00–15:00 (+21 bpm over your floor)".
- Caveat: "Stress here is heart rate above your calm level while you're still. Excitement, caffeine, a big meal or
  heat look the same. Not a measure of how you feel." No breathing prompts, no notifications.
- `sustainedHigh` (3 elevated hours in a row) appears only as a fact in the detail ("3 elevated hours in a row from
  13:00"). It is never an alert.

**Readout changes** (`BaselineReadoutsMetrics.swift`):
```swift
struct StressDayReadout {          // existing fields kept
    ...
    let lens: Lens                 // .personal(floorBPM: Double) | .learning(daysOfHistory: Int)
    let restoredHours: Int, calmHours: Int, elevatedHours: Int, movingHours: Int
    var scoredHours: Int { restoredHours + calmHours + elevatedHours }
    let typicalElevatedHours: Double?   // 14-day median, nil until 5 qualifying days
}
enum StressState { case restored, calm, elevated, moving, noReading
    static func of(_ p: DaytimeStress.HourPoint) -> StressState }
```
Tests: the bpm↔level table above (floor 64: 64 → calm/restored boundary at 67, elevated at 79); `.dayRelative`
gives no totals; under 3 scored hours gives no totals; moving hours are excluded; `elevatedHours × 60 ==
highStressMinutes`; the 14-day typical needs 5 days.

**Friends.** Stress is physiology. If shared at all, it is only as the person's own change ("elevated time −1 h vs
own 14-day typical"), off by default, and never ranked head to head.

### 4. Intensity minutes

Unchanged from `INTENSITY_MINUTES.md` §5. One change: show `IntensityCard` on today whenever a strap is paired
(including "0 min today"), so all three activity cards are present on a normal day.

---

## References

1. Paluch AE, Bajpai S, Bassett DR, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. *Lancet Public Health* 2022;7(3):e219–e228. doi:10.1016/S2468-2667(21)00302-9
2. Saint-Maurice PF, Troiano RP, Bassett DR, et al. Association of Daily Step Count and Step Intensity With Mortality Among US Adults. *JAMA* 2020;323(12):1151–1160. doi:10.1001/jama.2020.1382
3. Ding D, Nguyen B, Nau T, et al. Daily steps and health outcomes in adults: a systematic review and dose-response meta-analysis. *Lancet Public Health* 2025;10:e668–e681. doi:10.1016/S2468-2667(25)00164-1
4. Banach M, Lewek J, Surma S, et al. The association between daily step count and all-cause and cardiovascular mortality: a meta-analysis. *Eur J Prev Cardiol* 2023;30(18):1975–1985. doi:10.1093/eurjpc/zwad229
5. Tudor-Locke C, Craig CL, Brown WJ, et al. How many steps/day are enough? For adults. *Int J Behav Nutr Phys Act* 2011;8:79. doi:10.1186/1479-5868-8-79
6. Master H, Annis J, Huang S, et al. Association of step counts over time with the risk of chronic disease in the All of Us Research Program. *Nat Med* 2022;28:2301–2308. doi:10.1038/s41591-022-02012-w
7. Roza AM, Shizgal HM. The Harris Benedict equation reevaluated: resting energy requirements and the body cell mass. *Am J Clin Nutr* 1984;40(1):168–182. doi:10.1093/ajcn/40.1.168
8. Mifflin MD, St Jeor ST, Hill LA, Scott BJ, Daugherty SA, Koh YO. A new predictive equation for resting energy expenditure in healthy individuals. *Am J Clin Nutr* 1990;51(2):241–247. doi:10.1093/ajcn/51.2.241
9. Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive equations for resting metabolic rate in healthy nonobese and obese adults: a systematic review. *J Am Diet Assoc* 2005;105(5):775–789. doi:10.1016/j.jada.2005.02.005
10. Keytel LR, Goedecke JH, Noakes TD, et al. Prediction of energy expenditure from heart rate monitoring during submaximal exercise. *J Sports Sci* 2005;23(3):289–297. doi:10.1080/02640410470001730089
11. Shcherbina A, Mattsson CM, Waggott D, et al. Accuracy in Wrist-Worn, Sensor-Based Measurements of Heart Rate and Energy Expenditure in a Diverse Cohort. *J Pers Med* 2017;7(2):3. doi:10.3390/jpm7020003
12. Fuller D, Colwell E, Low J, et al. Reliability and Validity of Commercially Available Wearable Devices for Measuring Steps, Energy Expenditure, and Heart Rate: Systematic Review. *JMIR mHealth uHealth* 2020;8(9):e18694. doi:10.2196/18694
13. Kim HG, Cheon EJ, Bai DS, Lee YH, Koo BH. Stress and Heart Rate Variability: A Meta-Analysis and Review of the Literature. *Psychiatry Investig* 2018;15(3):235–245. doi:10.30773/pi.2017.08.17
14. Rosenbach H, Itzkovitch A, Gidron Y, Schonberg T. Assessing Stress Level Scores Against Wearables-Driven Physiological Measurements. *Stress and Health* 2025;41:e70125. doi:10.1002/smi.70125
15. van der Mee DJ, Koyuncu Z, Lemmers-Jansen I. Are you stressed or just excited? What the Garmin Stress Score can say about your mood. Preprint, PsyArXiv 2025. doi:10.31234/osf.io/97pzb_v1 (earlier version: Authorea 2024, doi:10.22541/au.173450365.53734709/v1)
16. Martinez GJ, Grover T, Mattingly SM, et al. Alignment Between Heart Rate Variability From Fitness Trackers and Perceived Stress: Perspectives From a Large-Scale In Situ Longitudinal Study of Information Workers. *JMIR Hum Factors* 2022;9(3):e33754. doi:10.2196/33754
17. Föhr T, Tolvanen A, Myllymäki T, et al. Subjective stress, objective heart rate variability-based stress, and recovery on workdays among overweight and psychologically distressed individuals: a cross-sectional study. *J Occup Med Toxicol* 2015;10:39. doi:10.1186/s12995-015-0081-6
18. Ronca V, Martinez-Levy AC, Vozzi A, et al. Wearable Technologies for Electrodermal and Cardiac Activity Measurements: A Comparison between Fitbit Sense, Empatica E4 and Shimmer GSR3+. *Sensors* 2023;23(13):5847. doi:10.3390/s23135847

### Vendor sources (fetched 2 October 2026 unless marked)

- V1. Garmin vívosmart 4 Owner's Manual, "Step Goal". https://www8.garmin.com/manuals/webhelp/vivosmart4/EN-US/GUID-5AC1A1BC-EFB3-40EC-9C18-2BF1D6218E69.html
- V2. Google Health Help, "How does my Fitbit device calculate my daily activity?" https://support.google.com/googlehealth/answer/14237111
- V3. Apple Support, "Manage Health data on your iPhone, iPad, or Apple Watch" (source priority; search summary). https://support.apple.com/en-us/108779
- V4. Apple Support, Apple Watch User Guide, "Track daily activity with Apple Watch". https://support.apple.com/guide/watch/track-daily-activity-apd3bf6d85a6/watchos
- V5. Oura, "All-New Updates to Oura's Activity Features", 21 May 2025. https://ouraring.com/blog/activity-improvements/
- V6. Android Authority, "WHOOP fitness trackers are finally getting step counting", October 2024. https://www.androidauthority.com/whoop-step-counting-3489245/
- V7. Samsung US Support, "View your step count in Samsung Health". https://www.samsung.com/us/support/answer/ANS10001370/
- V8. Garmin vívosmart 3 Owner's Manual, "Heart Rate Variability and Stress Level". https://www8.garmin.com/manuals/webhelp/vivosmart3/EN-US/GUID-9282196F-D969-404D-B678-F48A13D8D0CB.html
- V9. Garmin vívoactive 5 Owner's Manual, reserve-energy page. https://www8.garmin.com/manuals/webhelp/GUID-5D183A14-BB43-4A9B-B441-5F824214CE40/EN-US/GUID-87E1392B-2C55-40B7-A1FF-3AB9252DA0A0.html
- V10. Firstbeat Technologies. Stress and Recovery Analysis Method Based on 24-hour Heart Rate Variability. White paper (vendor document). https://assets.firstbeat.com/firstbeat/uploads/2015/11/Stress-and-recovery_white-paper_20145.pdf
- V11. Oura Member Care, "Daytime Stress". https://support.ouraring.com/hc/en-us/articles/21205822135315
- V12. Oura Member Care, "Resilience". https://support.ouraring.com/hc/en-us/articles/25358829055251-Resilience
- V13. Google Health Help, "How do I track & manage stress with my Fitbit device?" https://support.google.com/googlehealth/answer/14237928
- V14. Google, "7 ways Fitbit can help you stress less" (score components; search summary). https://blog.google/products/fitbit/manage-stress-fitbit/
- V15. Samsung UAE Support, "How do I measure stress on my Galaxy Watch5?" https://www.samsung.com/ae/support/mobile-devices/how-can-i-use-stress-level-feature-on-samsung-watch-5/
- WHOOP stress feature and calories: WHOOP's launch article (https://www.whoop.com/us/en/thelocker/introducing-stress-monitor-a-new-way-to-monitor-manage-stress/), its support page "Get to Know the Stress Monitor" and "How does WHOOP calculate calories burned?" (https://support.whoop.com/hc/en-us/articles/360033775513). All three returned 401/403 to automated reads, so their content is cited from search summaries only. Re-check by hand before quoting in app copy.
