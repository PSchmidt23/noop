# Baseline — notes for App Review

Paste into App Store Connect › App Review Information › Notes (4,000 characters max; the block in
the fenced block is about 3,950, so trim before adding). The sections after it are for whoever submits: why the notes say
what they say, and what to resolve before the build goes in.

## The notes

```
Baseline is a free companion app for a heart-rate strap the user already owns (WHOOP 4.0, 5.0 and MG straps; the app is independent and not affiliated with the hardware maker). It reads the strap over Bluetooth and shows heart rate variability (HRV) and resting heart rate against the person's own baseline, plus sleep, a habits journal and workouts. It is open source (PolyForm Noncommercial 1.0.0) and built on the NOOP open-source project.

NO ACCOUNT, NO SERVER. There is nothing to sign in to and no demo credentials. The app makes no network connections at all: no analytics, no crash reporting, no backend. Everything it stores lives in the app's container on the device and, if the user allows it, in Apple Health.

WITHOUT A STRAP. Pairing needs the physical strap, which the review device will not have. Every screen is still reachable and shows its empty state, which describes what appears after the first synced night:
- Welcome (first launch): three pages. "Continue", then "Skip for now" on the pairing page, then "Not now" on the Apple Health page. No permission dialog is forced.
- Today: the strap status strip ("Not connected", with a Pair button that opens the pairing wizard) and the empty state "Your first night fills this in".
- Trends: the empty state for the HRV / resting heart rate / sleep / effort charts; the Progress button in the toolbar opens the Progress screen (baseline over months), also empty.
- Sleep: the empty state for last night's stages and the list of nights.
- Journal: the habit chips work without data (tap to mark a habit for today; they are stored locally); the "What moves your HRV" card explains that effects appear once enough nights are logged.
- Settings: Devices (pairing wizard), Apple Health, Data (Import of a strap-app or Apple Health export via the Files picker; Compare, the strap's nights against the import; Export CSV through the Files picker), Profile, Appearance, Notifications (opt-in morning summary and evening check-in) and About (privacy policy, licence, notices, disclaimer).
To see the app with data, import an Apple Health export (Health app › profile › Export All Health Data) through Settings › Import: sleep and workouts from the export then fill the screens.

PERMISSIONS. Bluetooth (NSBluetoothAlwaysUsageDescription) is requested when the user starts pairing a strap, and bluetooth-central background mode keeps a paired strap's sync running while the app is in the background. Apple Health read and write are requested only when the user taps "Allow" on the Welcome page or in Settings › Apple Health; the app reads sleep, workouts and heart-rate samples and writes back HRV, resting heart rate and sleep, on device. Notifications are requested only when the user turns on the morning summary or the evening check-in under Settings › Notifications; both are local notifications, each at most once a day (the summary after the first sync of the day, the check-in at the chosen time); there is no push.

The "fetch" and "processing" background modes run three BGTasks (healthwriteback, rescore, stalebattery) that finish an Apple Health write or a re-computation after a background sync and warn when the strap has not synced for days. The "location" mode is declared for the engine's outdoor-workout route recorder, which no screen in this build exposes; the app never reads or stores a location. No networking.

DATA. Nothing is collected or transmitted by the developer or any third party (App Privacy: "Data Not Collected"). No third-party SDKs beyond open-source packages compiled in (GRDB, ZIPFoundation, swift-markdown-ui). Health data never goes to iCloud.

HEALTH CLAIMS. The app computes wellness estimates (HRV, resting heart rate, a readiness tier, sleep stages, effort) from the strap's heart-rate and R-R interval stream and from Apple Health, using published methods that are documented in the open-source project. The app states in Welcome, in Settings › About › Disclaimer and in the store description that it is not a medical device and nothing it shows is medical advice.

TRADEMARK. The hardware maker's name appears only to identify compatible hardware (nominative use), with "Not affiliated" beside it. The app's name, icon, screenshots and keywords contain no third-party mark.

Contact for review questions: Patrick Schmidt, paddyr.schmidt@gmail.com.
```

## Why the notes assume empty states

`--demo-seed`, the launch argument the screenshot harness uses to fill 120 days of synthetic data, is
compiled only in DEBUG (`#if DEBUG` in `Baseline/App/BaselineRoot.swift`); a Release archive strips it,
and App Review installs the Release build from TestFlight. So the reviewer sees the empty states and the
notes describe what each screen does rather than ask them to look for data. Do not promise a demo mode
in the notes unless one ships in Release.

If a Release demo mode is ever wanted (a Settings › About switch that seeds the store, guarded so it
only fills an empty store and labels every screen "Demo data"), it has to be built in `Baseline/`
first; then the notes can say "turn on Demo data under Settings › About". Until then, the Apple Health
import route is the honest way to show the reviewer a filled screen, and it exercises the Health
permission flow on the way.

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
- **Today:** strap status strip; HRV and resting-heart-rate tiles with delta against baseline, band
  position and readiness tier; Progress row (one sentence about the baseline's direction); last night's
  sleep; today's effort and workouts; journal prompt chips.
- **Trends:** 7 / 30 / 90-day segments; HRV and resting heart rate lines with the baseline band; sleep
  duration bars; effort bars; tap for a day's numbers; "All workouts" link; Progress toolbar button.
- **Progress:** HRV baseline, resting-heart-rate baseline, sleep and sleep timing over months, each as a
  sentence and a chart, with a horizon picker.
- **Sleep:** last night's hypnogram and stages, efficiency, duration against the 30-day average, a list
  of nights; a night opens its detail.
- **Journal:** today's habit chips (catalogue plus custom); "What moves your HRV" ranked effects with
  sample size and confidence; alcohol and caffeine dose cards.
- **Workouts:** sessions with duration, average heart rate and zones; a session opens its detail.
- **Settings:** Devices, Apple Health, Import, Profile, Appearance, Notifications, About (version, NOOP
  and Baseline source links, privacy policy, licence, open-source notices, disclaimer).
