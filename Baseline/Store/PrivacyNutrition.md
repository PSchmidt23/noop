# Baseline — App Privacy questionnaire ("nutrition label")

Answers for App Store Connect › App Privacy. They follow Apple's definitions: data is "collected"
when it is transmitted off the device in a way that is accessible to the developer or a third party.
Home, Trends, Sleep, the journal and Apple Health stay on the iPhone. The opt-in **Friends** tab is the
one exception: after Sign in with Apple it uploads only the values the person turns on, to Baseline's
server (Supabase, Frankfurt, EU), so the label is **Data Linked to You**, for **App Functionality**
only. The answers must agree with the privacy manifest that ships in the binary
(`Baseline/Resources/PrivacyInfo.xcprivacy`) and with the policy (`Baseline/PRIVACY.md`); all three are
reconciled below. The spec behind them is `Baseline/Research/FRIENDS_SPEC.md` §7.

## Questionnaire

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **Yes** |
| Data types | **Health & Fitness › Health**, **Health & Fitness › Fitness**, **Contact Info › Name**, **Identifiers › User ID** |
| For each type: is it used for tracking? | **No** |
| For each type: is it linked to the user's identity? | **Yes** (every row belongs to the Friends account) |
| For each type: purposes | **App Functionality** only (not Analytics, Product Personalization, Advertising, Developer's Advertising or Other) |
| Does this app use data to track the user (across apps and websites owned by other companies)? | **No** |
| Resulting label | **Data Linked to You**: Health & Fitness, Contact Info, Identifiers. **Data Used to Track You**: none |

Collection is optional in the app: nothing is sent unless the person signs in to Friends and turns a
metric on. The label has no "optional" variant that changes this, and Friends uploads automatically
while the app is open once sharing is on (not "infrequent"), so all four types are declared.

## Per type: what is sent, and why

| Apple type | What Baseline sends (exactly) | Why | Linked | Tracking |
|---|---|---|---|---|
| Health & Fitness › **Health** | HRV, resting HR and readiness as a weekly change against the person's own baseline (e.g. HRV +8 %, −2 bpm, +4), clipped and rounded, current week plus 4; 0/1 per night for "reached own sleep goal" and "bedtime within 30 min of own target". Never raw HRV, heart rate, readiness, sleep hours or clock times | Shown to friends the person accepts; the two night counts also score competitions they join | Yes | No |
| Health & Fitness › **Fitness** | Daily step count (capped at 60,000) with its source, strap or iPhone (Apple Health); daily intensity minutes (capped at 300); 0/1 "active day"; the step goal and weekly intensity goal | Shown to friends, or only inside competitions the person joins; competition scoring | Yes | No |
| Contact Info › **Name** | The display name the person types (2–24 characters). Apple's name is never requested | Shown to friends and co-competitors | Yes | No |
| Identifiers › **User ID** | The Supabase auth user ID created by Sign in with Apple (Apple supplies a per-app identifier; no email is requested) | Holding the account, friendships and competitions together | Yes | No |

Every other category, and why it is not collected:

| Category | In the app? | Collected? |
|---|---|---|
| Health & Fitness, everything else (heart rate, R-R, raw HRV/resting HR/readiness, sleep stages, effort, calories, stress, workouts, journal habits) | Yes, on the device (SQLite; Apple Health when allowed) | No, never sent |
| Contact info: email, phone, address, other | No. `AppleSignIn.requestedScopes` is empty | No |
| Identifiers: device ID | No. The strap's Bluetooth identity stays in the app's device registry on the phone | No |
| Location | Not used by any Baseline screen (the engine's GPS workout recorder is compiled in but never started; see ReviewNotes.md) | No |
| Sensitive info | No | No |
| Financial info, purchases | No; the app has no purchases | No |
| Contacts | No. Friends connect by an 8-character invite code, never the address book | No |
| User content (journal notes, custom habit names, photos, messages) | Journal on the device only; Friends has no chat, photos or free text. A report sends a fixed reason only | No |
| Browsing / search history | No | No |
| Usage data (product interaction, advertising data) | No analytics of any kind. The server keeps a `last_seen_at` time on the Friends profile only to delete accounts inactive for 13 months | No |
| Diagnostics (crash logs, performance data) | No crash reporter; Apple's own crash reports are governed by the user's iOS "Share With App Developers" setting, which Apple does not count here | No |
| Other data | No | No |

If the D20 fallback is ever switched on (`AppleSignIn.requestedScopes = [.email]`, used only if
Supabase refuses Apple users without an email), add **Contact Info › Email Address** (linked, not
tracking, App Functionality) here, in the manifest and in the policy in the same commit.

## Apple Health (HealthKit)

HealthKit data has its own rules (guideline 5.1.3) and they are met:

- The app reads sleep analysis, workouts, steps and heart-rate samples and writes HRV (SDNN), resting
  heart rate and sleep, only after the user grants access (`NSHealthShareUsageDescription` /
  `NSHealthUpdateUsageDescription` in `Info.plist`; entitlement `com.apple.developer.healthkit` with
  background delivery).
- The one HealthKit-derived value that can leave the device is the daily step count when the iPhone
  (Apple Health) counted it, and only when the person shares Steps in Friends, after the per-metric
  consent (FRIENDS_SPEC §7.2). It is labelled "iPhone" to friends. That is why Health and Fitness are
  on the label.
- Health data is used only to show the person their own metrics and, with their explicit consent, to
  show the values they chose to friends they accepted. Never for advertising, marketing, data mining or
  sale to a third party, and never written to iCloud (there is no iCloud entitlement).
- The usage strings say this: nothing leaves the iPhone unless the person turns on sharing in Friends,
  which sends only the daily totals and trends they choose.

## Tracking, third parties and the network

- `NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty in the manifest; the app asks
  for no App Tracking Transparency permission and links no ad or analytics SDK.
- Third-party code compiled into the binary: GRDB.swift (SQLite), ZIPFoundation (reading export
  archives), swift-markdown-ui with NetworkImage and swift-cmark. None of them phones home. GRDB ships
  its own privacy manifest inside the package; the others declare no required-reason APIs.
- The only network requests are Friends': HTTPS to Baseline's Supabase project (auth, the RPCs, the
  `delete-account` Edge Function), made only after the person signs in. Supabase (Supabase, Inc., EU
  region Frankfurt) is a processor under its DPA, not a third party that uses the data for itself. Its
  API logs keep request IP addresses for the hosting plan's short log window; they are never used to
  derive location or for anything else, so no Location type is declared (the policy discloses the
  logs). Sign in with Apple is Apple's own sheet. Links in Settings › About open Safari.
- A build with no `Baseline/Resources/Supabase.plist`, Sample data, UI tests and "Preview with demo
  friends" make no network request at all (`FriendsBackendFactory.choose`).

## Required-reason APIs (manifest, for reference)

The manifest lists the categories NOOP's engine calls, so a build never gets the "missing API
declaration" email:

| Category | Reason | Use |
|---|---|---|
| UserDefaults | CA92.1, 1C8F.1 | App settings; the App Group suite shared with widgets |
| File timestamp | C617.1 | Modification dates of files in the app's own container |
| System boot time | 35F9.1 | Spacing log publishes inside the app |

Re-check the manifest after every upstream merge of NOOP (the comment at the top of the file lists where
each call lives). The widget extension's own manifest (`BaselineWidgets/PrivacyInfo.xcprivacy`) stays
empty: the widget sends nothing.

## Consistency check

- Policy (`Baseline/PRIVACY.md`, mirrored in the app by `SettingsLegalText.privacy`): "Local first;
  Friends is optional", what Friends sends, where (Supabase, Frankfurt), who sees it, retention,
  withdrawal, deletion, 16+, "no analytics, ads or tracking". Matches Data Linked to You.
- Manifest: Health, Fitness, Name, UserID, each linked, not tracking, App Functionality; tracking false,
  no tracking domains. Matches.
- Info.plist: usage strings say nothing leaves the iPhone unless sharing is on in Friends; no
  `NSUserTrackingUsageDescription`, no ATS exemptions, no iCloud. Matches.
- `Baseline/scripts/release-check.sh` fails a build whose entitlements carry Sign in with Apple while
  the manifest declares no collected types.
- If any of the three is ever changed, change the other two in the same commit and re-answer the
  questionnaire in App Store Connect before the next submission.
