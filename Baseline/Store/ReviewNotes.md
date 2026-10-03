# Baseline — notes for App Review

Paste into App Store Connect › App Review Information › Notes (4,000 characters max; the fenced
block is about 3,950, so trim before adding). The sections after it are for whoever submits: why the notes say
what they say, and what to resolve before the build goes in.

## The notes

```
Baseline is a free companion app for a heart-rate strap the user owns (WHOOP 4.0, 5.0 and MG; independent, not affiliated with the hardware maker). It reads the strap over Bluetooth and shows HRV and resting heart rate against the person's own baseline, plus sleep, a habits journal and workouts. Open source (PolyForm Noncommercial 1.0.0), built on the NOOP project.

LOCAL FIRST. Everything except Friends needs no account and makes no network connection; no analytics, crash reporting or ads. Data stays in the app's container and, if allowed, Apple Health.

FRIENDS (OPTIONAL 4TH TAB). Sign in with Apple (no name or email requested), a display name and a 16+ confirmation; every metric is Off until turned on with explicit consent. Only derived values leave the device, to the developer's Supabase server (Frankfurt, EU): daily steps, intensity minutes, 0/1 active days, sleep-goal nights and on-time bedtimes, and HRV / resting HR / readiness only as a weekly change against the person's own baseline, never ranked. Never sent: heart rate, raw HRV, sleep times, calories, stress, journal, location. No chat or free text. TO TRY IT WITHOUT AN ACCOUNT: turn on Sample data (below); Friends then shows made-up friends and competitions on the device and sends nothing (a build without the server offers the same as "Preview with demo friends" on the Friends tab). Or sign in with your own Apple ID. Account deletion: Settings › Friends & sharing › "Delete account and shared data" (deletes every server row, revokes Sign in with Apple). Report and Block are on every friend and request; reports (a fixed reason, no text) are reviewed weekly.

WITHOUT A STRAP: Settings (gear, top right) › About › Sample data › "Show sample data". Sixty made-up nights fill every tab and detail, Friends included. Home shows a "Sample data" pill; the same switch removes it. With it off, every screen shows an empty state:
- Welcome (first launch): three skippable pages; no dialog is forced.
- Home: strap pill ("Pair" opens pairing), a "Pair strap" empty state, the floating "Journal" button.
- Trends and Sleep: empty states. Friends: what can be shared, then Sign in with Apple.
- Settings: Devices, Apple Health, Data (Import, Export CSV), Profile, Sleep window, Activity goals, Notifications, Friends & sharing, About (privacy policy, licence, notices, disclaimer, "How accurate is this?", Sample data).

PERMISSIONS. Bluetooth when pairing starts; bluetooth-central keeps a paired strap syncing. Apple Health only on "Allow" in Welcome or Settings › Apple Health; reads sleep, workouts, steps and heart rate, writes HRV, resting heart rate and sleep. Notifications only when the morning summary or evening check-in is turned on; local, at most once a day each; no push.

"fetch" and "processing" run three BGTasks: an Apple Health write or re-computation after a background sync, and a warning when the strap has not synced for days. "location" is declared for the engine's outdoor-workout route recorder, which no screen exposes; no location is read or stored.

DATA. App Privacy: Data Linked to You (Health, Fitness, Name, User ID), App Functionality only, no tracking, all from Friends. No third-party SDKs; open-source packages only (GRDB, ZIPFoundation, swift-markdown-ui). Health data never goes to iCloud.

HEALTH CLAIMS. Wellness estimates (HRV, resting heart rate, 0–100 readiness, sleep, effort, steps, calories, intensity minutes, hourly stress) by published methods, each shown against the person's own baseline, average or goal, never a clinical threshold; no alert or diagnosis. Settings › About › "How accurate is this?" lists each metric's evidence tier with the studies linked. Welcome, About and the store copy say it is not a medical device or advice.

TRADEMARK. The hardware maker's name appears only to identify compatible hardware (nominative use), with "Not affiliated" beside it.

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
captures `sample-home-0`. The same switch is the reviewer's way into Friends: while sample data is on,
`FriendsBackendFactory.choose` picks the in-memory demo backend (`LocalDemoFriendsBackend`, signed in,
seeded friends and competitions) even when the build carries `Supabase.plist`, so nothing is uploaded and
no Apple ID is needed. Check the switch on the TestFlight build before submitting: it is the one thing
the notes promise.

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
5. **Review device:** the app needs no sign-in, and Friends uses Sign in with Apple (the reviewer's own
   Apple ID; no demo credentials exist or are needed). Leave the demo-account fields empty and tick
   "Sign-in not required".
6. **Friends and guideline 5.1.1(ix).** Sensitive health data on a server is expected from an
   organisation account. Check the membership type of team `25RC553RGP` (FRIENDS_SPEC §11 step 1). On an
   Individual account, either ship Release without `Baseline/Resources/Supabase.plist` (release-check
   WARNs; the tab then offers "Preview with demo friends" only and nothing is uploaded) or accept the
   risk knowingly.
7. **App Privacy and age rating** must be re-answered before this build: `PrivacyNutrition.md` (Data
   Linked to You) and the age-rating table in `AppStore.md` (display names are user-generated content,
   with report and block). The privacy policy page must show the Friends version of `PRIVACY.md`.
8. **Reports:** check the `reports` table in the Supabase dashboard at least weekly (the notes promise
   it); act by blocking or deleting the profile there.

## What each screen does (reference for answering a reviewer's question)

- **Welcome:** intro (what the app shows, the compatibility line, "everything stays on your iPhone",
  "not medical advice"; true before Friends is ever opened, and Friends asks again for every metric), pair strap (opens NOOP's pairing wizard for a 4.0 or a 5.0/MG; skippable),
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
- **Friends (optional fourth tab):** signed out, one card says what can be shared (steps, intensity
  minutes, active days, nights at sleep goal, on-time bedtimes; HRV, resting HR and readiness only as a
  change against the person's own baseline) and what never is, then Sign in with Apple, or "Preview with
  demo friends" in a build without a server. After sign-in: a display name and "I'm 16 or older", then
  each metric Off / Only in competitions / Friends with an explicit "I agree". Signed in: a leaderboard
  of behaviour metrics scored as % of each person's own goal (Competitive view can turn places off),
  physiology listed alphabetically and never ranked, invite by an 8-character code, friend requests,
  competitions (steps, intensity minutes, active days, sleep-goal nights, on-time bedtimes; up to 9
  friends, up to 31 days), a friend's page with Hide, Remove, Block and Report.
- **Settings (gear on every tab):** Devices, Apple Health, Data (Import, Compare, Export, Data source),
  Profile (date of birth, sex, units, weight, height, max heart rate) and Sleep window (bedtime and wake
  time pickers; defaults 11:00 PM to 7:00 AM; stored on the device only) and Intensity goal (a weekly stepper,
  60–600 in steps of 10, default 150, with one line on the heart-rate basis), Notifications, Friends &
  sharing (name, Competitive view, what you share, "See what's on the server" with a JSON export, Sign
  out, "Delete account and shared data"), About (version,
  NOOP and Baseline source links, privacy policy, licence, open-source notices, disclaimer, "How accurate
  is this?": every metric's evidence tier with its caveat and the validation studies as links, Intensity minutes
  and Heart rate rated by a second review, plus links to both cited reviews on GitHub; Sample data).
