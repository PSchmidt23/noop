# Activity audit: Steps, Calories, Intensity minutes, Stress, sample data, Friends backend

*Read-only audit, 2 Oct 2026. Every claim cites `file:line` in this repo (NOOP's files read, never edited)
or in the Sayner reference project (`/Users/patrickschmidt/Documents/00_AI Projects/Archive`, read-only;
its `*.p8` key was not opened). Screenshots referred to are the last harness run in
`/private/tmp/baseline-shots` (`home-0..2.png` under `--demo-seed`, `sample-home-0.png` under sample data).*

**What Patrick asked:** "What happened to steps, intensity minutes, calories burned, stress?" The short answer:
nothing was removed from the code. Every card is still in `TodayScreen`. Each one is **hidden when its
data source is empty**, and the two ways of filling the app without a strap fill very different
sources:

| Card | `--demo-seed` (UI tests, marketing) | Sample data (Settings › About) | Real WHOOP 5.0 / MG | Real WHOOP 4.0 + Apple Health | Real WHOOP 4.0, no Apple Health |
|---|---|---|---|---|---|
| Steps | **hidden** | shown (whole-day count even at 9:41) | shown (strap counter) | shown (iPhone steps) | **hidden** (no source) |
| Calories (cell in Effort) | **hidden** | shown | shown (HR estimate) | shown (HR estimate) | shown (HR estimate) |
| Intensity minutes | shown, workouts-only credit | shown, workouts-only credit | shown once age entered | shown once age entered | shown once age entered |
| Stress | **hidden** | **hidden** | shown (if HR/PPG banked) | shown | shown |
| Heart rate card | hidden (unless `-baseline.demoHeartRate YES`) | **hidden** | shown | shown | shown |

So the screens Patrick has been looking at (demo seed and sample data) are exactly the ones where these
cards cannot appear. The fixes are mostly in the demo data and in a few readouts. None needs a NOOP edit.

---

## 1. Why Home hides Steps

**The gate.** `Baseline/Screens/Today/TodayScreen.swift:191` draws `StepsCard` only
`if let steps, steps.hasRecordedSource`. `hasRecordedSource` (`Baseline/Screens/Today/TodaySnapshot.swift:171`)
is `steps != nil || observed30 > 0 || recent.contains { $0.value != nil }`: false when nothing in the 31 days
ending on the day recorded a count.

**The resolver.** `BaselineReadouts.steps(_:for:mode:)` (`Baseline/Components/BaselineReadoutsMetrics.swift:651`)
calls `stepReadings` (`:636-647`). Under strap-first or merged that is NOOP's
`repo.resolvedSteps(from:to:)` (`Strand/Data/RollingStepsAverage.swift:37-49`), which tries three series in
order, first value per day wins:

1. `resolvedSeries(key: "steps", source: "my-whoop")` (the strap's counted steps),
2. `resolvedSeries(key: "steps", source: "apple-health")` (the phone),
3. `resolvedSeries(key: "steps_est", source: "my-whoop")` (the WHOOP 4.0 estimate).

Each `resolvedSeries` (`Strand/Data/Repository.swift:2265`) walks `sourceCandidates`
(`:2356`; for the strap: active id, `my-whoop`, `<active>-noop`, `my-whoop-noop`) and reads, per candidate,
**only** `metricSeries(deviceId:key:)` plus the `DailyMetric` column via `dailyColumn`
(`resolvedRows`, `:2334`; the column map at `:2570` gives `"steps" → d.steps`). It never reads the
`appleDaily` table. Under imports-only only the `apple-health` series is read (`BaselineReadoutsMetrics.swift:641`).
Days the resolver has no point for fall back to the funnel table's `steps` column (`:619-627`).

**What `--demo-seed` writes** (`Strand/Data/AppleDemoSeeder.swift`, DEBUG only):
- `DailyMetric` rows under `my-whoop` with **no `steps` and no `activeKcalEst`** (`:123-127`; the init omits both).
- The day's step count only in an **`AppleDaily`** row under `apple-health` (`:159-166`, upsert at `:228`),
  never as a `metricSeries` "steps" point, never on a `DailyMetric`.
- No `steps_est` series, no gravity (so NOOP's estimator cannot run), no heart-rate samples.

So all three resolver series are empty and the funnel's `steps` column is nil: **Steps is hidden under the
demo seed.** (NOOP's own Today screen shows steps there because it reads `repo.appleDailyRows()` directly;
Baseline's resolver does not.) Confirmed by `home-1.png` / `home-2.png`: no Steps card.

**What sample data writes** (`Baseline/Screens/Sample/BaselineSampleData.swift`): `DailyMetric.steps` and
`activeKcalEst` on every day (`:137-138`, `:179-188`) under `baseline-sample-noop`. After `applyReadSpine`
the repo's active id is `baseline-sample`, so candidate 3 of the strap list (`<active>-noop`) is
`baseline-sample-noop` and its daily column resolves. **Steps does show under sample data**: the Steps card
is the fifth card, below the fold (`sample-home-0.png`: "Steps so far 15,0xx"), and
`BaselineTests/SampleDataTests.swift:213` asserts `hasRecordedSource`. Two real defects there:
- **Today gets a whole day's count**: at 9:41 it reads ~15,000 "so far". The generator should scale the
  anchor day's steps (and calories) by the fraction of the day elapsed.
- It sits under readiness, both rings and nothing else above the fold, so it reads as "missing".

**What a real wearer sees.**
- *WHOOP 5.0 / MG:* the strap's `@57` motion counter becomes `DailyMetric.steps` on `my-whoop-noop`
  (`Packages/StrandAnalytics/Sources/StrandAnalytics/AnalyticsEngine.swift:991`, written at `:1040`), scaled by
  `ProfileStore.stepTicksPerStep` because the counter overcounts. Candidate 1 resolves. Card shows.
- *WHOOP 4.0 with Apple Health:* the strap sends no step count. The iPhone's steps arrive through
  HealthKit (section 2), candidate 2 resolves, card shows. Days the phone did not count get NOOP's
  calibrated `steps_est` (`Strand/Data/IntelligenceEngine.swift:2656-2813`: strap motion volume × a personal
  coefficient fitted on days that have both; inert until enough overlap days).
- *WHOOP 4.0 without Apple Health:* no counter, no phone steps, and `steps_est` cannot calibrate without
  phone steps (only a manual coefficient in NOOP's Settings, which Baseline does not show). **Card hidden.**

## 2. Does Baseline read the iPhone's own step count today?

**Yes, via Apple Health only, and it reaches `resolvedSteps`.** Chain:
- `Baseline/App/BaselineApp.swift:55` builds NOOP's `HealthKitBridge`; `:126-130` runs `health.sync()` on scene
  activation when authorized (plus HealthKit observer wakes).
- `StrandiOS/Health/HealthKitBridge.swift:532-545`: `.stepCount` cumulative sum per day into `byDay[...].steps`
  (a failed steps read holds back the whole write).
- `:596` builds `AppleDaily` rows; `:659` `AppleHealthAggregator.metricPoints(aggregates)` flattens them into
  `metricSeries` points, including `"steps"`, `"active_kcal"`, `"basal_kcal"`
  (`Packages/StrandImport/Sources/StrandImport/AppleHealthAggregator.swift:285-287`);
  `:674-676` upserts `appleDaily` **and** `metricSeries` under `apple-health`.
- `resolvedSteps` candidate 2 reads that `metricSeries` "steps" (`Repository.swift:2334-2346`). Reaches Home,
  Trends and the Steps detail.

So a 4.0 user who granted Health sees phone steps today. What is missing:
1. **No ask on Home.** A 4.0 user who skipped the Health step has no Steps card and no prompt. The
   coordinator's decision ("Steps always present") needs a no-source state: "Steps come from your iPhone.
   Allow Apple Health" (or Motion & Fitness), opening the permission.
2. **Phone steps without Apple Health: CoreMotion.** `CMPedometer.queryPedometerData(from:to:)` returns
   the iPhone's own count for the last 7 days with only the Motion & Fitness permission. NOOP uses it for
   workouts only (`Strand/Data/WorkoutPedometer.swift`). `NSMotionUsageDescription` is already in the
   Baseline Info.plist (`project.yml:522`), but its wording ("for a walking or running workout") would need
   to cover daily steps. Baseline would keep those counts in its own small store (a `baseline.*` JSON file,
   or `metricSeries` under a Baseline-owned id such as `baseline-phone`) and `stepReadings` would add it
   as a fourth candidate after `steps_est`. Recommendation: Apple Health first (it already works and
   back-fills history), CoreMotion as the fallback for people who decline Health.
3. **Demo/sample parity** (section 5).

## 3. Calories

**Where the number comes from.** `DailyMetric.activeKcalEst` is NOOP's HR-only **whole-day total**
(resting + active), despite the name: `AnalyticsEngine.swift:1019-1021` →
`Calories.estimateDayCalories` → `estimateDayEnergy(...).totalKcal`
(`Packages/StrandAnalytics/Sources/StrandAnalytics/WorkoutDetector.swift:589-597`, `:849-855`). The model is
revised Harris–Benedict BMR for the resting part plus Keytel 2005 above a 50 % heart-rate-reserve gate
(`dayActiveHRRFraction`, the "calories too high" fix). Caveat: resting energy is integrated only over
**observed** seconds (gaps capped at 60 s, `dayMaxObservedGapS`), so a day the strap spent on the charger
under-reports its BMR. `estimateDayEnergy` is `public` and returns `restingKcal`, `activeKcal` and
`observedSeconds`, so Baseline can show the split without an engine change (it needs the day's HR samples,
one read like Stress) or approximate it as `resting = BMR × observedSeconds/86 400`, `active = total − resting`.

**Profile inputs** (`Strand/Data/Profile.swift`): `dateOfBirth` (default: age 30, persisted on first read,
`:110-123`), `sex` (default `"male"`, `:124`), `weightKg` 75 (`:125`), `heightCm` 178 (`:126`). The engine's
own fallbacks when a value is 0 are 70 kg / 170 cm / 30 years (`WorkoutDetector.swift:713-716`). Baseline's
`baseline.profileSet` flag already says whether age and sex were entered (`BaselineReadoutsMetrics.swift:689-698`),
but NOOP computes calories with the seeded defaults regardless. The Calories card should say "Estimated
with default body size; set yours in Profile" until `profileSet` is true and weight/height were changed.

**Apple Health's figures.** HealthKit sync also stores `active_kcal` and `basal_kcal` per day
(`HealthKitBridge.swift:547-554` reads them; `AppleHealthAggregator.swift:286-287` series). Baseline's
`calories(for:days:logicalKey:)` (`BaselineReadoutsMetrics.swift:242-248`) reads only `activeKcalEst` from the
funnel, so a phone/Watch total is never used. Proposed source order for the new Calories card, mirroring
steps: strap estimate → Apple Health (`active_kcal + basal_kcal`, labelled with its split) → nothing.

**Why it became a cell in EffortCard.** A design choice, not a data problem: commit `9bf844b6` ("the Effort
card gains the whole-day calorie estimate with its 30-day delta and badge"), recorded in
`Baseline/Components/DESIGN.md:21` ("Calories is a cell beside Effort ... there is no separate Calories
card") to keep Home at most nine rows (`TodayCards.swift:578-616`). Under the demo seed the cell is
absent because `activeKcalEst` is nil (`AppleDemoSeeder.swift:123-127`), which is why it "disappeared";
`home-2.png` shows Effort with no Calories cell.

## 4. Stress

**What NOOP needs.** `DaytimeStress.analyze`
(`Packages/StrandAnalytics/Sources/StrandAnalytics/DaytimeStress.swift:345`):
- **Heart-rate samples** (`hrSample`; `repo.hrSamples` unions the active strap, registered WHOOPs and
  `my-whoop`, `Strand/Data/Repository.swift:1217`, `:274-280`). An hour is scored only with
  **≥ 300 samples** (`minHourHRSamples`, `:34`; ≈ 5 min at 1 Hz), and only waking hours 06:00–22:00
  (`:56-57`). Baseline also refuses a past day with under 300 samples in total
  (`BaselineReadoutsMetrics.swift:674`).
- **R-R intervals: optional.** Each hour's RMSSD joins the HR z-score when present; without R-R the score
  is HR-only.
- **Gravity: optional** but important: hours where ≥ 30 % of motion records clear the walking floor are
  masked as movement, not stress (`activityMaskFraction`), plus a post-exercise shadow.
- Two modes: `.dayRelative` (the day's own calm hours are the reference; what Baseline uses today,
  `BaselineReadoutsMetrics.swift:678-679`) and `.baselineRelative` (Oura-style: each hour against a
  30-day personal daytime-HR baseline, `Strand/Data/DaytimeStressMode.swift`; HR-only by default because
  `daytimeRMSSDScoringEnabled = false`). Today goes through `StressDayCurve.today(repo:personalBaseline:)`
  (`Strand/Data/StressDayCurve.swift`), which already accepts `personalBaseline: true`.
- WHOOP 5.0 / MG: `hrSamples` is the measured stream only; PPG-derived seconds live in `ppgHrSample`
  (bucketed reads include them, `hrSamples` does not), so a 5.0 day can have a heart-rate trace and still
  no Stress until measured HR is banked.

**What Baseline shows now.** `StressCard` (`TodayCards.swift:357-420`): the hourly 0–3 curve, average and
peak with Low / Medium / High words, Low-accuracy badge. Shown when a day scored, or on today with a paired
strap as the single "No daytime data yet" card (`TodayScreen.swift:200`).

**Why hidden under the demo seed and sample data:** neither writes a single heart-rate sample, and the
seeded store is not a paired strap (`home-0.png` shows "Pair"), so `stress == nil` and `isPaired == false`.

**Coordinator's direction (feasible with NOOP as is):** keep Stress, drop the 0–3 number from the card, use
`.baselineRelative` and report **time**: "Calm 6h 10m · Elevated 1h 20m against your usual daytime heart rate",
hours masked for movement said as "moving", the curve as a two-tone band, shown only when the strap
banked that day, never on the hero. Past days need Baseline's own `.baselineRelative` fold (the same
`DaytimeStress.dayDaytimeAggregate` / `scoringModeFromAggregates` calls `DaytimeStressMode` makes, over the
30 days before the day). Doable; the main cost is reading 30 days of HR once per day shown, which
`IntradayDayStore` already caches per day (it keeps a Stress mean today).

## 5. Sample data and demo seed: what to write so every card shows

**Public write APIs** (all callable from Baseline, no NOOP edit):
- `WhoopStore.insert(_ streams: Streams, deviceId:)`, **public**
  (`Packages/WhoopStore/Sources/WhoopStore/StreamStore.swift:159`). `Streams` has a public memberwise init
  (`Packages/WhoopProtocol/Sources/WhoopProtocol/Streams.swift:750`) with `hr: [HRSample]`
  (`HRSample(ts:bpm:)`, `:10`), `rr: [RRInterval]` (`RRInterval(ts:rrMs:)`, `:107`), `gravity`
  (`GravitySample(ts:x:y:z:)`, `:338`), `steps` (`StepSample(ts:counter:)`, `:356`), `ppgHr`.
  Insert is idempotent on `(deviceId, ts)`.
- `upsertMetricSeries` (`MetricSeriesStore.swift:31`), `upsertAppleDaily` (`JournalWorkoutAppleCache.swift:198`),
  `upsertDailyMetrics` (`MetricsCache.swift:531`), all public.
- `WhoopStore.deleteAllData(deviceId:)` clears `hrSample`, `rrInterval`, `gravitySample`, `stepSample`,
  `ppgHrSample`, `appleDaily`, `metricSeries` among others (`DeviceRegistryStore.swift:134-148`), so the sample's
  existing `remove(from:)` already cleans streams written under its ids.

**Where to write streams, and why it matters.** NOOP's `IntelligenceEngine` scores raw streams only for the
day owner it resolves from the **device registry** or the fallback `my-whoop`
(`Strand/Data/IntelligenceEngine.swift:3089-3120`; engine id fixed at launch, `Strand/App/AppModel.swift:259`).
- Sample data: write streams under `BaselineSampleData.deviceId` (`baseline-sample`). Not registered, so
  the engine never re-scores them (the sample's own daily rows stay authoritative), and while the read
  spine is on the sample, `rawPhysiologyReadIds` puts `baseline-sample` first (`Repository.swift:321-328`),
  so `hrSamples`, `hrBuckets`, `rrIntervals` and `gravitySamplesUnion` all see them. Safe and Release-legal.
- `--demo-seed`: **do not** write streams under `my-whoop`. The engine would score those days and write
  `my-whoop-noop` rows, which strap-first lets win field by field over the demo's numbers
  (`Baseline/Components/BaselineDays.swift`, `fold`/`fill`), changing Effort, resting HR and readiness in the
  screenshots. Better: a DEBUG-only `BaselineDemoAugmentation` that runs after NOOP's seeder (AppModel seeds
  before its first refresh, `AppModel.swift:465-470`) and **reuses the sample generator's stream writer under
  the sample id with the same read-spine re-point**, or simply has the UI tests launch with the sample
  toggled on instead of `--demo-seed`. Either way one generator feeds both.

**Exact list to write (per day of the dataset, sample ids):**

| Card | Write | Read by |
|---|---|---|
| Steps | already `DailyMetric.steps` (keep); **today scaled by elapsed fraction of the day** | `stepReadings` → `<active>-noop` daily column |
| Calories | already `activeKcalEst` = total (keep, scale today); optionally `metricSeries` keys Baseline owns for the split (or compute the split from BMR, section 3) | `calories(for:days:)` |
| Heart rate 1D | `hrSample` over the waking day + the night (≈ 50–60 bpm asleep, 65–85 desk, workout rises matching `WorkoutRow.avgHr/maxHr`) | `repo.hrBuckets(…, 60)` (`BaselineReadoutsIntraday.swift:175`) |
| Heart rate 7D / 4W / 1Y | same samples on every day of the 60 | `IntradayDayStore` per day (`IntradayDayStore.swift:375`) |
| Intensity minutes (scored, not "from workouts only") | in the last 14 days ≥ 20 samples per minute (1 Hz or 1 per 2 s) so `minutes(samples:)` counts them (`IntensityMinutes.swift:178`, window `IntradayDayStore.swift:159`); older days any density (bucket means); `-baseline.profileSet YES` or an age | `IntensityMinutes` |
| Stress | ≥ 300 HR samples in each waking hour (1 per 10 s is enough outside the 14-day window), a few calm and tense hours; optional `rrInterval` for RMSSD; optional `gravitySample` with walking hours to exercise the motion mask | `stressDay` / `StressDayCurve.today` |

Size: 1 Hz for the last 14 days ≈ 1.2 M rows; 1 per 10 s for the other 46 days ≈ 0.4 M. Keep R-R to the last
7 days, waking hours, or skip it (HR-only Stress is valid). Write in daily batches off the main actor; the
About toggle already shows progress text. Delete `-baseline.demoHeartRate` once real samples exist.

Also needed for the Stress card on today: it requires `isPaired` or a scored day (`TodayScreen.swift:200`);
with samples it scores, so no registry change is needed.

## 6. Sayner backend patterns (for Friends)

Files (read-only reference; the config plist values and the `.p8` key were not printed or opened):

| Concern | File |
|---|---|
| Config (URL + anon key in one plist, never literals) | `Archive/Utilities/AppConfig.swift`, `Archive/Config/Supabase.plist` (keys `SUPABASE_URL`, `SUPABASE_ANON_KEY`) |
| One shared client | `Archive/Services/SupabaseService.swift` |
| Sign in with Apple → Supabase | `Archive/Views/SignInView.swift` (random nonce, SHA-256 in the request, `requestedScopes [.fullName, .email]`), `Archive/Services/AuthService.swift` (`signInWithIdToken(OpenIDConnectCredentials(provider: .apple, idToken:, nonce:))`, full name saved on first sign-in with a pending-retry in UserDefaults, `authStateChanges` loop) |
| Profile row on first sign-in | `schema.sql:20-48` (`public.users`, `handle_new_user` security-definer trigger on `auth.users`) |
| Invite codes | `Archive/Utilities/InviteCode.swift` (8 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`), DB check `code = upper(code) and code !~ '[0O1Il]'` (`schema.sql:110-124`), redeem via `redeem_invite(p_code)` RPC (`schema.sql:519-551`: `for update`, expiry, `max_uses`, `use_count`), client trims + uppercases (`ArchiveService.swift:129-137`) |
| Atomic multi-row create | `create_archive` RPC (`schema.sql:560-588`) |
| RLS helpers | `is_member`, `member_role_in`, `stable security definer set search_path = public` (`schema.sql:332-350`) to avoid self-referencing policy recursion |
| Account deletion | `delete_account()` RPC deletes `auth.users` row for `auth.uid()` (`schema.sql:597-609`); `handle_deleted_user` trigger anonymizes the profile and removes memberships (`:51-72`); client signs out and wipes every local cache (`AuthService.swift:59-77`) |
| Report / block | tables `reports`, `blocks` (`schema.sql:290-305`), RLS "create reports" / "manage own blocks" (`:506-511`), `Archive/Services/ModerationService.swift` (upsert block on conflict, insert report) |
| Rules | never ship or use the service-role key; fix RLS with policies/RPCs (`CLAUDE.md`) |
| Entitlement | `com.apple.developer.applesignin: [Default]` (`Archive/Archive.entitlements`) |

What changes for Baseline: Sayner's `"read any profile"` policy (`schema.sql:365`) is too open for a health
app: profiles should be readable only by accepted friends (a `are_friends(a, b)` security-definer helper).
Account deletion should **hard-delete** shared health summaries (Sayner preserves content; Baseline must not
keep someone's health data after they leave). Health data never goes to iCloud/CloudKit (guideline
5.1.3(ii)); a third-party backend is allowed only with explicit, per-metric consent, which matches
"nothing shared by default".

## 7. project.yml: supabase-swift vs a dependency-free client

**supabase-swift (SPM).** Sayner pins `https://github.com/supabase/supabase-swift`, `upToNextMajorVersion`
from 2.0.0 (`Archive.xcodeproj/project.pbxproj:353-358`). For Baseline it would mean:
- an entry under the **top-level `packages:`** block (`project.yml:43-77`), which is **outside** the Baseline
  blocks the fork rules allow us to edit, plus a `- package: Supabase` line under the Baseline target
  dependencies (`project.yml:556-571`), and a change to the shared
  `Strand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, so every upstream merge
  touches a NOOP-owned section;
- NOOP's supply-chain rule pins every remote package **exactly** (`project.yml:72-74`); supabase-swift pulls
  swift-crypto, swift-http-types, swift-concurrency-extras, swift-clocks and xctest-dynamic-overlay
  transitively, each to be pinned and audited;
- every Baseline build (and `release-check.sh`'s clean Release build) resolves the graph.

**Dependency-free REST client (recommended).** Supabase is plain HTTPS: GoTrue
`POST /auth/v1/token?grant_type=id_token` with `{provider: "apple", id_token, nonce}` returns the session
(access + refresh token); `POST /auth/v1/token?grant_type=refresh_token` refreshes; PostgREST
`/rest/v1/<table>` and `/rest/v1/rpc/<fn>` with `apikey` and `Authorization: Bearer <access_token>`. A
`URLSession` client of a few hundred lines in `Baseline/Friends/` covers sign-in, refresh (tokens in the
Keychain), select/insert/upsert/RPC and errors, with no new package, no `packages:` edit, and testable
against `URLProtocol` stubs. It sits behind the `FriendsBackend` protocol next to the in-memory demo
implementation used in DEBUG, sample data and UI tests.

**Sign in with Apple entitlement:** add `com.apple.developer.applesignin: [Default]` to the Baseline target's
`entitlements.properties` (`project.yml:529-537`, inside the Baseline block, allowed); register the capability
on the `com.patrickschmidt.baseline` App ID (Xcode automatic signing does this on the first device build);
in Supabase, enable the Apple provider with the bundle id as client id for native sign-in (the Services ID,
Key ID, Team ID and `.p8` are only needed for web/OAuth flows and the secret rotation). Also update:
`release-check.sh:82-93` (add the entitlement check), `Baseline/Resources/PrivacyInfo.xcprivacy`
(`NSPrivacyCollectedDataTypes` is empty today, `:27-28`; Friends collects name, user id, and the health and
fitness summaries a person chooses to share, linked to them, not for tracking), `Baseline/PRIVACY.md`,
`Baseline/Store/PrivacyNutrition.md`, `ReviewNotes.md` (a demo account or the in-memory demo for review), and
`BASELINE.md`'s "Local only. No accounts, no sign-in, no backend." rule (`BASELINE.md:26-27`), which
becomes "local by default; Friends is opt-in".

## How other apps do it (for the build)

From public product documentation; names are for reference only and stay out of the UI copy.
- **Steps:** Apple Health uses the iPhone's motion coprocessor and the Watch, deduplicated; Oura, WHOOP 5.0
  and Garmin count from the wearable's accelerometer. Daily goal plus a 7-day average is universal.
  Baseline: strap counter → iPhone (Health, then CoreMotion) → estimate, with a goal.
- **Calories:** Apple shows Active + Resting energy; Oura shows total burn with active calories; WHOOP shows
  one total from heart rate. All are estimates; the honest form is a rounded total with the split and an
  "estimate" badge, which is what the coordinator chose.
- **Intensity minutes:** Fitbit, Garmin and Google count heart-rate-zone minutes, vigorous counting double,
  against the WHO 150 min/week guideline. Baseline already does this (`INTENSITY_MINUTES.md`).
- **Stress:** WHOOP shows a 0–3 scale, Garmin a 0–100 number from HRV, Oura **minutes** of stressed vs
  restored time against the person's own daytime baseline. The Oura model is the most honest for HR-only
  data and is the coordinator's choice.
- **Friends / competitions:** Apple's activity sharing scores competitions as a **percentage of each
  person's own goals**; Fitbit and Garmin run step challenges and leaderboards on raw counts; WHOOP teams
  share scores, not raw physiology. So Patrick is right: head-to-head only on behaviour (steps, intensity
  minutes, sleep duration, bedtime consistency, active days), physiology only as each person's change
  against their own baseline ("HRV +8 % vs own baseline", "resting HR −2 bpm vs 30 days ago").

## Recommendations, in order

1. **Demo/sample data** (fixes what Patrick saw): one generator writes daily rows **and** streams under the
   sample ids (section 5); UI tests use it; today's steps and calories scale by the time of day.
2. **Steps card always present** with a daily goal (`baseline.stepsGoal`, default 8,000) and a no-source state
   that asks for Apple Health; CoreMotion fallback.
3. **Calories card** of its own: total, active/resting split, estimate badge, strap → Apple Health order,
   "set your height and weight" while the profile is default. Remove the cell from EffortCard.
4. **Stress** redone as calm vs elevated time, `.baselineRelative`, strap days only, off the hero.
5. **Friends tab** (fourth tab, opt-in): `FriendsBackend` protocol, in-memory demo implementation, REST
   Supabase implementation, Sign in with Apple, invite codes, per-metric sharing toggles off by default,
   step/intensity/sleep competitions, physiology only as change vs own baseline, report/block, account
   deletion that removes shared data.
