# Baseline — App Store Connect listing

Copy for the App Store Connect product page. Every field below is sized to Apple's limit (noted in
brackets) and keeps to the fork's rules: the WHOOP mark appears in one nominative sentence in the
description and nowhere else (not in the name, subtitle, keywords, screenshots or icon; App Review guideline 4.1(c)
and 5.2.1); no "Strain", "Recovery" or "Sleep Coach"; Baseline's vocabulary is HRV, Resting HR,
Readiness, Sleep, Effort, Steps, Calories, Stress, Journal. Store copy mirrors what the app says in
Welcome and Settings › About, and claims no more for a number than Settings › About › "How accurate is
this?" does.

## Name [30]

**Baseline**

An app called "baseline: a better journal" is already on the App Store (a journaling app). App Store
Connect only refuses a name that is identical to an existing one, so "Baseline" on its own should be
accepted, but the two will sit next to each other in search. The subtitle is what tells them apart, so
it should say what Baseline measures rather than what it feels like. If "Baseline" is rejected as taken,
fall back to "Baseline HRV" (12) or "Baseline: HRV Trends" (20); never a name with a strap maker in it.

## Subtitle [30]

Three options, recommended first:

1. **HRV & resting HR trends** (23) — says the two headline numbers and nothing else.
2. **Your HRV, against your norm** (27) — the product idea in one line.
3. **HRV, sleep & effort, offline** (28) — leads with the privacy stance.

## Promotional text [170]

Can be changed without a new build. Current:

> Free and local-only. Every morning: HRV and resting heart rate against your own baseline, last night's sleep, and a journal that learns what moves your HRV.

(156 characters)

## Description [4000]

Plain text; App Store Connect keeps line breaks but no formatting.

```
Baseline answers one question every morning: am I trending toward the healthiest version of myself?

It reads your strap over Bluetooth and shows heart rate variability (HRV) and resting heart rate against your own baseline, with a band for your typical range, so a number means something at first glance. Sleep, a habits journal and your workouts support that story. Nothing clutters it.

Works with WHOOP 4.0, 5.0 and MG straps. Not affiliated with WHOOP.

TODAY
Readiness first: a score from 0 to 100 on a track, with the inputs that lifted or held it back written out, never a verdict. Then HRV and resting heart rate as large tiles: today's value, the difference from your baseline and whether it sits inside your band. Then steps against your 7-day average, intensity minutes against your weekly goal (vigorous minutes count double), last night's sleep, an hour-by-hour stress curve estimated from heart rate and labelled as an estimate, and today's effort, calories against your 30-day average and workouts. Tap a card for its detail: a day, a week, four weeks or a year, the day's heart rate traced hour by hour with sleep and workouts shaded.

TRENDS
Seven, thirty or ninety days of HRV and resting heart rate with your baseline band drawn in, effort under the readiness line, sleep and steps as bars. Tap any point for that day's numbers.

PROGRESS
Is your baseline itself moving? Months at a glance for HRV, resting heart rate, sleep, sleep timing and an estimated VO2 max, in a sentence and a chart.

SLEEP
Last night stage by stage: a hypnogram, time in each stage, efficiency, duration against your thirty-day average, and every night in a list. Timing too: average bedtime, average wake time and a regularity score, drawn night by night against the sleep window you set, built on sleep and wake only, the part a strap gets right.

JOURNAL
Tap the habits that applied today (alcohol, caffeine, late meal, your own) and Baseline ranks what moves your HRV, with the sample size and confidence behind each effect. Dose cards show what alcohol or caffeine costs you.

WORKOUTS
Effort for the day, heart-rate zones per session and the sessions themselves.

APPLE HEALTH
If you allow it, Baseline reads sleep, workouts and heart data from Apple Health and writes back what it computes, on this iPhone only.

IMPORT
Bring your history: an export from your strap's app or from Apple Health lands in the same local store, so Trends and Progress reach back as far as it does. Your strap's nights stay the record and the import fills the gaps, unless you choose otherwise under Settings › Data. Compare the two night by night, and export everything as CSV.

HOW ACCURATE IS THIS?
Settings › About lists every metric with the tier published validation studies give it, its caveat and the studies. Nightly HRV and resting heart rate are the high-tier readings; sleep duration, timing, steps, intensity minutes and daytime heart rate are honest as trends; calories, stress and any composite score are estimates and shown as such.

FREE, PRIVATE, OPEN
Free, with no account, no sign-in, no subscription, no ads and no in-app purchases. There is no server: your data lives in the app on your iPhone and, when you allow it, in Apple Health. No analytics, crash reporting, tracking or network connections. Delete the app and the data is gone.

Open source under the PolyForm Noncommercial License 1.0.0, built on NOOP, the open-source, local-only strap engine by ryanbr and contributors, kept unchanged under Baseline's own screens. Read, run or fork it on GitHub (link in Settings › About).

Two optional local notifications, off until you turn them on: a morning summary when the first sync of the day lands, and an evening check-in at a time you pick, a reminder to log tonight's habits.

Baseline is not a medical device and nothing it shows is medical advice. Every number is an estimate from published methods, documented in the open-source project. Talk to a professional about health decisions.
```

(about 3,998 characters; keep under 4,000 after edits)

## Keywords [100]

Comma-separated, no spaces after commas (Apple counts every character), no strap maker's name, no
words already in the name or subtitle (Apple indexes those on its own):

```
heart rate variability,resting heart rate,readiness,sleep stages,journal,strap,wearable,biometrics
```

(98 characters)

## URLs

- **Support URL:** `https://github.com/PSchmidt23/noop/issues` (the fork's issue tracker; NOOP's own
  SUPPORT.md points at ryanbr/noop and is not Baseline's channel).
- **Marketing URL (optional):** `https://github.com/PSchmidt23/noop`.
- **Privacy Policy URL:** must be a page a reviewer and a customer can open in a browser. The text is
  `Baseline/PRIVACY.md` in the fork, reachable as:
  - `https://github.com/PSchmidt23/noop/blob/main/Baseline/PRIVACY.md` — GitHub renders the Markdown.
    This is the URL the app itself links from Settings › About › Privacy policy
    (`SettingsAboutCard.privacyURL`), so use the same one here and the two stay in step.
  - `https://raw.githubusercontent.com/PSchmidt23/noop/main/Baseline/PRIVACY.md` — the raw file, plain
    text in the browser. Works, but reads like source.

  Better: host the policy as a plain page under a domain or a GitHub Pages site (one static HTML file,
  no scripts, the style of the small one-page privacy policies indie apps use), and point both App Store
  Connect and `SettingsAboutCard.privacyURL` at it. GitHub's rendered view carries the repository chrome,
  a sign-in prompt and GitHub's own cookie banner around the policy, which is not what App Review
  expects to land on; and a repository URL breaks if the file moves. Until a page exists the blob URL
  is acceptable; App Review has accepted GitHub-hosted policies for open-source apps.

## Category

- **Primary:** Health & Fitness.
- **Secondary:** none (Medical would be wrong: the app disclaims medical use, and the category invites
  the 1.4.1 accuracy questions).

`LSApplicationCategoryType` in the Info.plist is already `public.app-category.healthcare-fitness`.

## Age rating

App Store Connect's questionnaire (the 2025 version with the 4+ / 9+ / 13+ / 16+ / 18+ tiers). Answers:

| Question | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | |
| Realistic violence | None | |
| Prolonged graphic or sadistic realistic violence | None | |
| Profanity or crude humor | None | |
| Mature or suggestive themes | None | |
| Horror or fear themes | None | |
| Medical or treatment information | None | The app shows wellness measurements and says in Welcome, About and the store copy that nothing is medical advice; it gives no diagnosis or treatment. If the reviewer disagrees, "Infrequent/Mild" moves the rating to 13+ and nothing else changes. |
| Alcohol, tobacco or drug use or references | None | The journal lets a person record that they drank alcohol or caffeine and shows the effect on their HRV. That is self-tracking of a health input, not a depiction or promotion. Should Apple read it as a reference, the honest alternative is "Infrequent/Mild" (13+). |
| Sexual content or nudity | None | |
| Graphic sexual content and nudity | None | |
| Simulated gambling | None | |
| Contests | No | |
| Gambling (real money) | No | |
| Unrestricted web access | No | The app opens no web view; its three links open Safari. |
| User-generated content or social features | No | Journal entries stay on the device and are never shared. |
| Messaging, chat or user communication | No | |
| Loot boxes / in-app purchases / advertising | No | The app has none. |
| Parental controls / age assurance | No | |
| Made for Kids | No | |

Expected rating: **4+**. If any question in the live questionnaire is not in the table, answer it from
the same facts: no content, no purchases, no network, no sharing.

## Copyright [line shown on the product page]

```
© 2026 Patrick Schmidt. Built on NOOP © 2026 NoopApp and contributors, PolyForm Noncommercial 1.0.0.
```

## Other fields

- **Price:** Free, every territory. No in-app purchases, ever (fork rule, and the PolyForm Noncommercial
  licence on NOOP's engine permits only non-commercial distribution).
- **Licence agreement:** leave Apple's standard EULA. The PolyForm terms, NOTICE and ATTRIBUTION ship in
  the binary and are shown under Settings › About, which is what the licence requires.
- **Version:** `MARKETING_VERSION` 1.0, build `CURRENT_PROJECT_VERSION` 1, set in the Baseline target's
  block of `project.yml`, separate from NOOP's 11.x numbering.
- **What's New (first version):** "First release." A later version lists changes in Baseline's own words,
  never NOOP's changelog verbatim.
- **Screenshots:** the six framed 6.9-inch PNGs from `Baseline/scripts/frame-shots.swift`; see
  `Checklist.md` and BASELINE.md. No strap maker's mark anywhere in them (the Welcome pairing step and
  Settings › Devices are not in the marketing set for that reason).
