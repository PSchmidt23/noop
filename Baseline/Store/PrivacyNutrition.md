# Baseline — App Privacy questionnaire ("nutrition label")

Answers for App Store Connect › App Privacy. They follow Apple's definitions: data is "collected"
when it is transmitted off the device in a way that is accessible to the developer or a third party.
Baseline transmits nothing, so the label is **Data Not Collected**. The answers must agree with the
privacy manifest that ships in the binary (`Baseline/Resources/PrivacyInfo.xcprivacy`) and with the
policy (`Baseline/PRIVACY.md`); all three are reconciled below.

## Questionnaire

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |
| Resulting label | **Data Not Collected** |
| Does this app use data to track the user (across apps and websites owned by other companies)? | **No** |

That is the whole questionnaire. App Store Connect asks nothing more once the first answer is No.

## Why "No" is correct for each data category

Apple's category list, and what Baseline does with each kind of data. None of it leaves the device, so
none is "collected" in Apple's sense; it is listed so that the answer is a considered one.

| Category | In the app? | Where it lives | Collected? |
|---|---|---|---|
| Health & Fitness — health (heart rate, HRV, resting heart rate, sleep, readiness, effort, journal habits) | Yes | SQLite in the app container; Apple Health when allowed | No |
| Health & Fitness — fitness (workouts, heart-rate zones) | Yes | same | No |
| Contact info (name, email, phone, address) | No | — | No |
| Identifiers (user ID, device ID) | No. There is no account; the strap's Bluetooth identity stays in the app's device registry on the phone | app container | No |
| Location | Not used by any Baseline screen (the engine's GPS workout recorder is compiled in but never started; see ReviewNotes.md) | — | No |
| Sensitive info | No | — | No |
| Financial info, purchases | No; the app has no purchases | — | No |
| User content (journal notes, custom habit names) | Yes, local only | app container | No |
| Browsing / search history | No | — | No |
| Usage data (product interaction, advertising data) | No analytics of any kind | — | No |
| Diagnostics (crash logs, performance data) | No crash reporter; Apple's own crash reports are governed by the user's iOS "Share With App Developers" setting, which Apple does not count here | — | No |
| Other data | No | — | No |

## Apple Health (HealthKit)

HealthKit data has its own rules (guideline 5.1.3) and they are met:

- The app reads sleep analysis, workouts and heart-rate samples and writes HRV (SDNN), resting heart
  rate and sleep, only after the user grants access (`NSHealthShareUsageDescription` /
  `NSHealthUpdateUsageDescription` in `Info.plist`; entitlement `com.apple.developer.healthkit` with
  background delivery).
- Health data is used only to show the user their own metrics, never for advertising, marketing, data
  mining or sale to a third party, and is never written to iCloud (there is no iCloud entitlement).
- Because it never leaves the device, HealthKit data is not "collected" and does not appear on the
  label. If a future version ever sent health data anywhere, the label, the policy and the manifest
  would all have to change together.

## Tracking and third parties

- `NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty in the manifest; the app asks
  for no App Tracking Transparency permission and links no ad or analytics SDK.
- Third-party code compiled into the binary: GRDB.swift (SQLite), ZIPFoundation (reading export
  archives), swift-markdown-ui with NetworkImage and swift-cmark. None of them phones home. GRDB ships
  its own privacy manifest inside the package; the others declare no required-reason APIs.
- The app makes no network requests at all. Links in Settings › About open Safari.

## Required-reason APIs (manifest, for reference)

The manifest lists the categories NOOP's engine calls, so a build never gets the "missing API
declaration" email:

| Category | Reason | Use |
|---|---|---|
| UserDefaults | CA92.1, 1C8F.1 | App settings; the App Group suite shared with widgets |
| File timestamp | C617.1 | Modification dates of files in the app's own container |
| System boot time | 35F9.1 | Spacing log publishes inside the app |

Re-check the manifest after every upstream merge of NOOP (the comment at the top of the file lists where
each call lives).

## Consistency check

- Policy (`Baseline/PRIVACY.md`, also in the app): "no analytics, ads or tracking", "makes no network
  connections", Apple Health exchange "on your iPhone only". Matches Data Not Collected.
- Manifest: no collected data types, tracking false, no tracking domains. Matches.
- Info.plist: no `NSUserTrackingUsageDescription`, no ATS exemptions, no iCloud. Matches.
- If any of the three is ever changed, change the other two in the same commit and re-answer the
  questionnaire in App Store Connect before the next submission.
