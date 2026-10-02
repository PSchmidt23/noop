# Baseline — notes for App Review

Paste into App Store Connect › App Review Information › Notes (4,000 characters max; the fenced
block is just under 4,000, so trim before adding). The sections after it are for whoever submits: why the notes say
what they say, and what to resolve before the build goes in.

## The notes

```
Baseline is a free companion app for a heart-rate strap the user owns (WHOOP 4.0, 5.0 and MG; independent, not affiliated with the hardware maker). It reads the strap over Bluetooth and shows heart rate variability (HRV) and resting heart rate against the person's own baseline, plus sleep, a habits journal and workouts. Open source (PolyForm Noncommercial 1.0.0), built on the NOOP project.

NO ACCOUNT, NO SERVER. No sign-in, no demo credentials, no network connections, no analytics, crash reporting or backend. Everything lives in the app's container on the device and, if allowed, in Apple Health.

WITHOUT A STRAP. Pairing needs the physical strap, which the review device lacks. TO SEE EVERY SCREEN WITH DATA: Settings (the gear top-right on any tab) › About › "Sample data" › turn on "Show sample data". Sixty made-up nights (HRV, resting heart rate, readiness, sleep, steps, calories, workouts, journal) then fill Home, Trends, Sleep, Workouts and the details; only the stress curve and the heart-rate day trace need a strap. Home shows a "Sample data" pill; the same switch removes it. Synthetic, on the device only. With it off, every screen shows an empty state saying what appears after the first synced night:
- Welcome (first launch): three pages; "Continue", "Skip for now" (pairing), "Not now" (Apple Health). No dialog is forced.
- Home: the strap pill ("Pair" opens the pairing wizard), a "Pair strap" empty state, and the floating "Journal" button (habit chips work without data, stored locally).
- Trends (charts, Progress, Habits) and Sleep: empty states.
- Settings: Devices (pairing wizard), Apple Health, Data (Import of a strap-app or Apple Health export and Export CSV via the Files picker; Compare; Data source), Profile, Sleep window and Intensity goal, Notifications (opt-in morning summary and evening check-in), About (privacy policy, licence, notices, disclaimer, "How accurate is this?", Sample data).

PERMISSIONS. Bluetooth is requested when the user starts pairing a strap; the bluetooth-central background mode keeps a paired strap's sync running. Apple Health read and write are requested only on "Allow" in Welcome or Settings › Apple Health; the app reads sleep, workouts and heart-rate samples and writes back HRV, resting heart rate and sleep. Notifications are requested only when the user turns on the morning summary or evening check-in; local, at most once a day each; no push.

The "fetch" and "processing" modes run three BGTasks: an Apple Health write or re-computation after a background sync, and a warning when the strap has not synced for days. The "location" mode is declared for the engine's outdoor-workout route recorder, which no screen in this build exposes; no location is read or stored.

DATA. Nothing is collected or transmitted by the developer or any third party (App Privacy: "Data Not Collected"). No third-party SDKs beyond compiled-in open-source packages (GRDB, ZIPFoundation, swift-markdown-ui). Health data never goes to iCloud.

HEALTH CLAIMS. The app computes wellness estimates (HRV, resting heart rate, a 0–100 readiness score, sleep stages and timing, effort, steps, calories, intensity minutes, an hourly stress estimate) from the strap's heart-rate, R-R and motion streams and from Apple Health, using published methods documented in the open-source project. Every number is shown against the person's own baseline, average or goal, never a clinical threshold; no alert or diagnosis is raised. Settings › About › "How accurate is this?" lists each metric's evidence tier from published validation studies, with the studies linked. Welcome, About › Disclaimer and the store description all say it is not a medical device and nothing it shows is medical advice.

TRADEMARK. The hardware maker's name appears only to identify compatible hardware (nominative use), with "Not affiliated" beside it. Name, icon, screenshots and keywords carry no third-party mark.

Contact: Patrick Schmidt, paddyr.schmidt@gmail.com.
```

## Why the notes point at the Sample data switch

`--demo-seed`, the launch argument the screenshot harness uses to fill 120 days of synthetic data, is
compiled only in DEBUG (`#if DEBUG` in NOOP's `AppleDemoSeeder`); a Release archive strips it, and App
Review installs the Release build from TestFlight. The Release stand-in is Settings › About › "Sample
data" › "Show sample data" (`Baseline/Screens/Sample/BaselineSampleData.swift`, the card in
`Baseline/Screens/Settings/SettingsSampleData.swift`): 60 deterministic nights written through
WhoopStore's public upserts under the dedicated ids `baseline-sample` (workouts, journal) and
`baseline-sample-noop` (daily rows, sleep sessions), surfaced by pointing NOOP's repository read id at
the sample, and removed with `deleteAllData` for exactly those two ids. Every daily row carries a step
count and a whole-day calorie estimate, so the Steps card, the Calories cell and Trends' Steps card fill
in too, and the sample workouts carry zone minutes, so Intensity minutes fill "from workouts only"; the Stress
curve and the day's heart-rate trace are the two the sample cannot fill (they need the strap's daytime heart
rate). Home wears a "Sample data" pill while it is on. It never touches a strap's, an import's or Apple Health's rows, and nothing from it is
written back to Apple Health (the write-back reads the strap's fixed ids). `SampleDataTests` covers the
generator and the store round-trip; `ScreenshotTests/testSampleData` walks the reviewer's path and
captures `sample-home-0`. Check the switch on the TestFlight build before submitting: it is the one
thing the notes promise.

## Resolve before submitting (things the reviewer will see)

1. **Background modes the app does not use.** `Baseline/Resources/Info.plist` declares the `location`
   background mode and the location, motion, microphone and speech usage strings, because NOOP's
   engine compiles in `GpsWorkoutRecorder` and `WorkoutPedometer` and a missing usage string crashes the
   moment that code runs. No Baseline screen starts a GPS workout, so under guideline 2.5.4 (background
   modes must be used) App Review may ask why `location` is declared. Removing it is NOT an option
   today: `GpsWorkoutRecorder.init` sets `allowsBackgroundLocationUpdates = true` and `AppModel` builds
   the recorder at launch, so without the mode CoreLocation throws on every start (tried; the app never
   reaches its first screen). Until an upstream change defers that assignment to the moment a route is
   recorded, add a sentence to the notes: the mode is declared for the engine's workout route recorder,
   which no screen in this build exposes; no location is read or stored. The microphone and speech
   strings already say the app "does not currently use" them, which is fine as long as the review build
   never shows those prompts.
2. **The Bluetooth usage string names the hardware maker** ("your WHOOP strap"). That is nominative
   and matches the one mention in the description; leave it, but do not add the mark anywhere else.
3. **Privacy policy URL** must open in a browser before the build is submitted (see `AppStore.md`).
4. **Version and build numbers** in `project.yml`'s Baseline block (`MARKETING_VERSION`,
   `CURRENT_PROJECT_VERSION`) must be higher than any build already uploaded.
5. **Review device:** no sign-in, so leave the demo-account fields empty and tick "Sign-in not required".

## What each screen does (reference for answering a reviewer's question)

- **Welcome:** intro (what the app shows, the compatibility line, "everything stays on your iPhone",
  "not medical advice"), pair strap (opens NOOP's pairing wizard for a 4.0 or a 5.0/MG; skippable),
  Apple Health (requests read/write; skippable). Can be re-run from Settings.
- **Home:** one day at a time (a day switcher under the bar walks back through stored days, never
  forward past today); strap pill in the bar; readiness as a 0–100 score on a horizontal track with a
  Good / Fair / Low pill and one sentence naming what lifted or held it back (opens Progress; "after
  4 nights" until the engine has them); HRV and resting-heart-rate rings with delta against baseline and
  band position; that night's sleep; that day's effort and workouts ("All workouts" opens the list);
  steps against the 7-day and 30-day average; intensity minutes for the day (moderate ×1, vigorous ×2, judged
  against the profile's max heart rate and the nightly resting heart rate) with one track for the week against
  the goal set under Settings › Profile; calories against the 30-day average, rounded to ten;
  a stress curve of the waking hours estimated from heart rate (empty until the strap has banked daytime
  heart rate; the sample data has none); a floating "Journal" button opens the journal sheet for the
  day: habit chips (catalogue plus custom), "Add habit", Done. The Readiness, Steps, Intensity minutes, Stress
  and Calories figures carry a small "High / Medium / Low accuracy" pill (the HRV and resting-heart-rate tiles and the
  sleep card do not on Home; the Sleep tab's cards have their own); tapping it shows the one-line caveat
  behind the tier. A card's number opens its detail: 1D / 7D / 4W / 1Y segments, latest / average / low / high,
  one context sentence, the same accuracy pill and, for heart rate, the day traced hour by hour with sleep and
  workouts shaded (a strap's daytime heart rate; the sample has none).
- **Trends:** a segmented control over three sections. Trends: 7 / 30 / 90-day segments; HRV and
  resting heart rate lines with the baseline band; sleep duration bars; effort bars; tap for a day's
  numbers; "All workouts" link. Progress: HRV baseline, resting-heart-rate baseline, sleep and sleep
  timing over months, each as a sentence and a chart, with a horizon picker. Habits: "What moves your
  HRV / Resting HR" ranked effects with sample size and confidence; alcohol and caffeine dose rows.
- **Sleep:** last night's ring against the 30-night average, hypnogram and stages, efficiency; sleep
  timing: a strip of the last 14 nights (bed to wake) over the sleep window set under Settings › Profile,
  average bedtime, average wake time and a 0–100 regularity score built from sleep/wake timing only; a
  list of nights; a night opens its detail.
- **Workouts:** sessions with duration, average heart rate and zones; a session opens its detail.
- **Settings (gear on every tab):** Devices, Apple Health, Data (Import, Compare, Export, Data source),
  Profile (date of birth, sex, units, weight, height, max heart rate) and Sleep window (bedtime and wake
  time pickers; defaults 11:00 PM to 7:00 AM; stored on the device only) and Intensity goal (a weekly stepper,
  60–600 in steps of 10, default 150, with one line on the heart-rate basis), Notifications, About (version,
  NOOP and Baseline source links, privacy policy, licence, open-source notices, disclaimer, "How accurate
  is this?": every metric's evidence tier with its caveat and the validation studies as links, Intensity minutes
  and Heart rate rated by a second review, plus links to both cited reviews on GitHub; Sample data).
