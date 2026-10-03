# Friends: how other apps do social fitness, what the evidence says, and the rules Baseline must follow

*Written 2 October 2026 for the Friends tab. Vendor behaviour comes from each vendor's own help pages, fetched that
day, unless a line says otherwise: WHOOP's support site and Locker pages refuse scripted reads (HTTP 401 / 403), so
WHOOP facts come from WHOOP's own pages as indexed by search and are labelled [W*, indexed]; Garmin's weekly step
challenge has no fetchable Garmin page, so those lines are labelled as forum reports. Every paper was checked against
Europe PMC (authors, title, journal, volume, pages, DOI) before it was cited. App Store text is quoted from the App
Store Review Guidelines as published (last updated 8 June 2026) and from Apple's App Privacy Details page. GDPR text
is quoted from the regulation. Vendor feature names appear only when naming the vendor's own feature; none of them
may appear in Baseline's copy (list in section 6).*

## The short version

Every big platform that lets friends compete does it on **behaviour** (steps, minutes, workouts, rings closed), and
the ones that do it well **normalise to the person**: Apple scores a competition as *percent of your own goals*,
Garmin puts weekly step contestants into groups of similar walkers, Fitbit's challenges were raw step races. The one
vendor that puts physiology on a leaderboard (WHOOP Teams: recovery score, HRV, resting HR) is the outlier, and the
physiology argues against it: between-person HRV differs by orders of magnitude for reasons that have nothing to do
with effort or health [R5]. Oura's Circles shares only its three high-level scores and has no leaderboard or
competition at all [O1, O2].

The trials agree that comparison and competition raise step counts more than support alone, and that competition was
the only arm whose effect survived after the game ended [R1, R2], but that comparison helps some people and does
nothing (or harm) for others [R3, R4], and that targets which feel reachable work better than ones pegged to the top
of the group [R6]. Sleep is the case for caution: a competitive sleep metric invites the perfectionism clinicians
call orthosomnia [R7].

For Baseline that means: head-to-head only on behaviour; default scoring as **percent of each person's own goal**;
physiology only as **each person's change against their own baseline**, computed on the phone, never ranked; nothing
shared until the person turns a metric on; Sign in with Apple only; Supabase in the EU region; hard delete on account
deletion with Apple token revocation; report, block and a fixed reaction set instead of chat. The details are in
RECOMMENDATIONS (section 7).

## 1. How the big apps handle friends

### Apple Fitness (Activity sharing and competitions) [A1]

- **Connection.** Invite a friend from the Fitness app; once accepted, each sees the other's "daily stats and ring
  progress" (Apple's wording).
- **Privacy controls, per friend.** Three: *Mute Notifications*, *Hide my Activity* (they stop seeing you; you stay
  friends), *Remove Friend*. No per-metric control: sharing is all of your activity or none.
- **Competition.** A 7-day duel between two people, started by invitation and accepted by the other. Scoring: "a
  point for every percent you add to your rings each day", up to 600 points a day (three rings at up to 200 % each),
  a "maximum of 4,200 points for the week"; the person with more points wins. Alerts tell you whether you are ahead
  or behind, with the score.
- **Normalisation.** This is the key design choice: because each ring goal is the person's own (Move calories,
  Exercise minutes, Stand hours, all editable), a 4,200-point week means "you hit double your own goals every day",
  not "you burned the most calories". A sedentary person with a 300 kcal Move goal can beat a marathoner with a
  1,000 kcal goal. The 200 %-per-ring cap stops one huge day from deciding the week.
- **Anti-cheat.** Apple documents none publicly. The structural protection is that only two consenting friends see
  the result and nothing is won.

### Fitbit (now Google Health) [F1–F4]

- **Friends leaderboard.** Fitbit's long-standing friends list was "listed in order, based on their 7-day step
  total" (search-indexed Fitbit Help text, [F2]). The current Google Health page says friends are "listed in order,
  based on their weekly step or cardio load total", and a person toggles "Steps" and "Cardio load" as leaderboard
  metrics individually [F1]. What a friend sees: Google account name and photo, email, and "your weekly step count or
  cardio load, depending on your sharing settings" [F1]. Older privacy settings let you hide birthday, sex, height,
  weight, location, friends, badges, lifetime totals and average daily steps [F2].
- **Challenges (2017–2023).** Four built-in formats, all raw step races [F3]: *Goal Day* (race to your step goal;
  everyone who reaches it wins), *Daily Showdown* (most steps in 24 hours, starting in the initiator's time zone),
  *Workweek Hustle* (most steps Monday to Friday), *Weekend Warrior* (most steps Saturday and Sunday). Google removed
  Challenges, Adventures, open groups and trophies on 27 March 2023 [F4]. Note the asymmetry: *Goal Day* was the only
  format normalised to the person (your own goal), and the only one where several people could win.
- **2026.** "Starting May 12, 2026, social experiences in the Fitbit app are paused" while users move to the Google
  Health app, which promises "a new social experience with more leaderboard options"; "Kids will no longer be able
  to add or have friends" [F1].
- **Normalisation.** None on the raw step leaderboard; cardio load is an HR-based personal score.

### Garmin Connect [G1–G4]

- **Connections.** Mutual connections; activity privacy per activity and as a default for new activities, with
  "Only Me" ("Activity will be visible only to you") and "My Connections" options (Garmin Connect's own UI strings,
  [G2]). Users report that step counts appear on the connections leaderboard only when shared with connections [G3,
  forum].
- **Challenges.** User-created challenges among connections for steps, distance, elevation and similar totals [G1],
  plus Garmin-run monthly *badge challenges* you opt into [G4]. Badges are the reward; there are no prizes.
- **Weekly step challenge (forum reports, not a Garmin page).** Each week a new challenge starts Sunday night to Monday
  noon local time; you are ranked against 7–12 other participants; groups are formed from people with similar
  average weekly steps, and winners appear to move up into stronger groups (users describe promotion and
  relegation); a person who has not synced in over 24 hours has the leaderboard hidden until they sync; weekly step
  challenges award no badge [G3]. This "league" design is Garmin's answer to normalisation: compete raw, but only
  against people who walk about as much as you.
- **Privacy default.** Garmin's own product team described the experience as private by default, with step totals
  treated as less sensitive and shown to challenge members once a person accepts a challenge (secondary source
  [G5]).

### WHOOP Teams [W1–W3, indexed]

- **What is shared.** Team leaderboards on three pillars, each with daily, weekly and monthly views (weekly and monthly
  show averages): *Strain* (activity strain, day strain, calories), *Recovery* (recovery score, **HRV and RHR**),
  *Sleep* (sleep performance, hours slept). A team average sits at the top of each pillar [W1, W2].
- **Who decides.** The team owner picks the leaderboard metrics when creating the team and they "cannot be changed
  after team creation"; members are told to check what they will share before joining [W1]. Profile searchability
  for invitations is a setting; joining by team code works either way [W1].
- **Community.** Team chat for each team, with screenshots and encouragement [W3].
- **Normalisation.** WHOOP presents its recovery score as a percentage relative to the member's own baselines, so ranking
  it is closer to fair than ranking raw HRV; but the same pillar also ranks raw HRV and resting HR, which are not
  comparable between people (section 2). Strain is WHOOP's 0–21 cardiovascular load score.
- **Lesson.** The owner-chosen, unchangeable metric set is the opposite of what Baseline wants: sharing should be the
  sharer's choice, per metric, revocable.

### Oura Circles [O1, O2]

- **What is shared.** Only "high-level data (Readiness, Sleep, and Activity Scores)" over a two-week window, as
  daily scores or weekly averages, chosen per circle; colour-coded bars. Up to 10 circles, up to 20 members each.
- **Invites.** Single-use links valid for seven days ("you will have to generate a new link for each person").
- **Interaction.** Preset emoji reactions only, which last 24 hours. No chat, no comments, no leaderboard, no
  competition.
- **Why no leaderboard.** Oura has not published a reason. Its launch post frames Circles around connection and
  support ("social support can predict health outcomes") and accountability, not ranking [O2]. The likely reading,
  consistent with section 2: Oura's three scores are already personal-baseline scores, and ranking sleep and readiness
  would push the orthosomnia problem [R7].
- **Lesson for Baseline.** The fixed reaction set and per-circle sharing are good, cheap patterns; the absence of any
  moderation surface beyond leaving a circle works because there is no free text.

### Strava [S1–S4]

- **Privacy model.** Profile visible to "Everyone" or "Followers"; each activity "Everyone", "Followers" or "Only
  You", with defaults for new uploads; follower approval; blocking; map visibility controls that hide an address, the
  start and end of every activity, or the whole map [S1]. Group-activity visibility is a separate global setting.
- **Why it matters.** In January 2018 Strava's Global Heatmap exposed the outlines and patrol routes of military bases
  because aggregated "anonymous" activity was public by default [S4]. It is the standard example of aggregate fitness
  data leaking more than any single upload.
- **Segments and anti-cheat.** Segment leaderboards are raw, global rankings, so Strava has the most developed
  cheat handling: athletes flag activities recorded with vehicle help, with erratic GPS, or under the wrong sport;
  flagged activities leave the leaderboard [S2]. Automatic detection uses speed, heart rate, power and cadence with
  supervised models trained on years of community flags; Strava reports removing 6.5 million anomalous activities
  (December 2024), 4.45 million from run leaderboards (May 2025) and 3.9 million from ride leaderboards (January
  2026) [S3].
- **Lesson.** Raw global rankings need industrial anti-cheat. Small friend groups with no prizes need only
  plausibility caps and the ability to report, which is what Baseline should build.

### Summary table

| | What friends compare | Normalised to the person? | Physiology shared? | Default privacy |
|---|---|---|---|---|
| Apple Fitness | % of own ring goals, 7-day duel | Yes (own goals, 200 % cap) | No | Share all or hide per friend |
| Fitbit / Google Health | 7-day / weekly steps, cardio load | No (raw); Goal Day was | No | Per-metric toggles (2026) |
| Garmin Connect | Steps, distance, elevation totals | Weekly challenge: similar-walker groups | No | Private by default |
| WHOOP Teams | Strain, recovery, sleep pillars | Recovery % yes; HRV / RHR raw | **Yes, raw HRV and RHR** | Owner picks metrics |
| Oura Circles | Readiness, Sleep, Activity scores | Scores are personal | Only as scores | Per-circle choice |
| Strava | Segment times, club totals | No | No (HR on activities) | Per-activity visibility, map privacy |

## 2. Why physiology is not compared person to person

Patrick's instinct is right, and the literature says so plainly:

- **HRV.** Nunan, Sandercock and Brodie's review of 44 studies and 21,438 healthy adults found "large interindividual
  variations (up to 260,000%)" in short-term HRV, particularly for spectral measures [R5]. Age, sex, genetics,
  breathing pattern and device dominate the absolute number. Two healthy people of the same age can sit 40 ms apart
  for life. The useful signal is within-person change: Plews et al. argue for monitoring an athlete's own HRV with
  rolling averages and the smallest worthwhile change against their own baseline [R8]. Baseline's own accuracy review
  rates nightly HRV "High as a trend, Medium as an absolute number" (`METRIC_ACCURACY.md`).
- **Resting HR.** Lower is not simply better between people (endurance training, beta blockers, thyroid status and
  genetics all move it). A 2–3 bpm change within one person, on the other hand, is above the strap's noise
  (`METRIC_ACCURACY.md`, Resting HR).
- **Readiness.** Baseline's 0–100 score is NOOP's stored composite and has no independent validation
  (`METRIC_ACCURACY.md`, composite readiness: Low). Ranking it would rank an unvalidated number.
- **Even change scores should not be ranked.** A competition on "biggest HRV improvement" rewards regression to the
  mean (whoever had the worst baseline month "improves" most), illness recovery, measurement artefacts and deliberate
  undertraining before the contest. So physiology belongs on Friends as a **trend card per person** ("HRV +8 % vs own
  baseline"), never as a ranking or a competition.
- **Health inference.** Some signals reveal health status that friends should not learn: illness watch, skin
  temperature (cycle and pregnancy), SpO2, breathing rate. These are never shareable.

## 3. What the research says about comparison and motivation

All four studies below were verified in Europe PMC.

1. **STEP UP (Patel et al., JAMA Intern Med 2019) [R1].** 602 adults with BMI ≥ 25, wearable step tracking, each
   person set a goal relative to their *own* baseline, then a 24-week game with points and levels for hitting it.
   Versus control, daily steps rose by 920 (competition), 689 (support) and 637 (collaboration). In the 12-week
   follow-up with no game, only the competition arm stayed significantly above control (+569 steps). Note that the
   competition was over goal attainment against individual baselines, not raw totals.
   A secondary analysis (Chen et al., PLoS One 2020 [R1b]) split participants into phenotypes: "extroverted and
   motivated" people responded only to competition (and not durably), "less active and less social" people responded
   to all three designs with sustained effects, and "less motivated and at-risk" people responded to none. One format
   does not fit everyone; offering both competitive and cooperative formats is better than either alone.
2. **Support or competition? (Zhang et al., Prev Med Rep 2016) [R2].** 790 students in a 4-arm RCT; mean weekly
   exercise-class attendance was 35.7 (competitive comparison networks), 38.5 (teams that could compare against other
   teams), 20.3 (control) and 16.8 (support-only teams). Comparison raised attendance about 90 % over the no-comparison
   conditions; support alone did not help.
3. **Comparison targets (Patel et al., Am J Health Promot 2016) [R6].** 286 adults, team feedback against the 50th or
   75th percentile, with or without lottery incentives; only comparison to the 50th percentile plus incentives beat
   the 75th-percentile control (0.45 vs 0.27 of days at 7,000 steps). Comparing against an attainable reference
   worked better than comparing against the top; feedback alone, without stakes, did little.
4. **Social comparison in PA apps (Arigo et al., J Med Internet Res 2020) [R3].** A meta-review of 26 reviews: few
   apps or reviews specify *what* users compare or *how* (leaderboards, message boards), and none tailored comparison
   to the person, although the comparison literature shows effects depend on the direction (upward or downward) and
   on individual differences. Comparison "may motivate PA for some people under some circumstances".

Caution on sleep: Baron et al. (J Clin Sleep Med 2017) describe patients whose pursuit of perfect tracker sleep
became its own problem, "a perfectionistic quest for the ideal sleep" [R7]. A "most hours slept" contest is a direct
invitation; consistency within a person's own window is not.

And on step goals: Paluch et al.'s meta-analysis of 15 cohorts (47,471 adults) found mortality risk falling until
about 6,000–8,000 steps a day in adults 60 and over and 8,000–10,000 in younger adults [R9]. That makes a personal
step goal around 8,000 a sound default and argues for capping credit well above the goal: steps past 200 % of goal
buy competition points, not health.

What this means for design:

- Competition works, but over **personal goals**, with **attainable** references, and in **small groups of friends**.
- Offer a **cooperative** format next to the head-to-head ones (STEP UP phenotypes; Oura's model).
- **No stakes beyond pride.** No prizes, no streak-loss shaming, no notifications that someone overtook you more than
  once a day.
- **Opt-out without friction**: leave a competition, hide from a friend, pause sharing.

## 4. App Store rules that apply once Baseline has accounts, a server and friends

Quoted from the App Store Review Guidelines (updated 8 June 2026) [AS1] unless noted.

### 5.1.1 Data Collection and Storage

- **(i) Privacy policy** in App Store Connect and in the app, identifying "what data, if any, the app/service
  collects, how it collects that data, and all uses of that data", that third parties (Supabase as processor)
  provide equal protection, and the retention / deletion policy and "how a user can revoke consent and/or request
  deletion". Baseline's `PRIVACY.md` currently says local-only; it must be rewritten for Friends.
- **(ii) Permission.** Consent for collection, and "an easily accessible and understandable way to withdraw consent".
  GDPR legitimate-interest processing must comply with GDPR in full (Baseline should use explicit consent instead,
  section 5).
- **(iii) Data minimisation.** "Only collect and use data that is required": upload daily aggregates and deltas, not
  heart-rate streams.
- **(v) Account sign-in.** "If your app doesn't include significant account-based features, let people use it
  without a login." Baseline already satisfies this: everything except Friends works with no account. "If your app
  supports account creation, you must also offer account deletion within the app." Apple's account-deletion page
  adds: offer "to delete the entire account record, along with associated personal data", deactivation alone "is
  insufficient", and "Apps that support Sign in with Apple should use the Sign in with Apple REST API to revoke user
  tokens" [AS3]. Token revocation needs the Sign in with Apple client secret, so it must run server-side (a Supabase
  Edge Function with the key in Supabase secrets, never in the app or the repo). Patrick's Sayner app calls
  `delete_account()` only and does not revoke tokens; Baseline should not copy that gap.
- **(ix)** "Apps that provide services in highly regulated fields (such as … healthcare …) or that require sensitive
  user information should be submitted by a legal entity that provides the services, and not by an individual
  developer." Baseline is a wellness app, not a healthcare service, but a reviewer could read server-side health
  data as "sensitive user information". If the team `25RC553RGP` is an individual account, this is the main review
  risk of adding Friends; keep the server footprint minimal (deltas, aggregates) and say so in review notes.
- **(x)** Name and email may be requested only if optional and features are not conditional on them: the display
  name must be editable and may be anything; never require an email.

### 4.8 Login Services

4.8 applies to apps that "use a third-party or social login service (such as Facebook Login, Google Sign-In …)",
which must then also offer an equivalent privacy-preserving option. **An app whose only sign-in is Sign in with Apple
does not trigger 4.8.** If Google or email sign-in is ever added, Sign in with Apple is already the required
equivalent. Apple shares the name only on the first authorization (Sayner's `AuthService` pattern of persisting it
immediately, with a retry stash, applies).

### 5.1.2 Data Use and Sharing

- **(i)** "You may not use, transmit, or share someone's personal data without first obtaining their permission",
  with disclosure of "how and where the data will be used". Sharing with friends is sharing with other users, so the
  per-metric opt-in is the permission; it must be specific (which metric, with whom: all friends, or the members of a
  competition).
- **(ii)** "Data collected for one purpose may not be repurposed without further consent": Friends data is used for
  Friends only (no analytics, no research, no product personalisation).
- **(iv) / (v)** No Contacts access to find friends; invites go through a share sheet or an 8-character code, which
  avoids these clauses entirely.
- **(vi)** HealthKit data (the iPhone-steps fallback) "may not be used for marketing, advertising or use-based data
  mining, including by third parties".

### 5.1.3 Health and Health Research

- **(i)** Health and fitness data may not be used or disclosed to third parties "for advertising, marketing, or other
  use-based data mining purposes other than improving health management". "You must disclose the specific health
  data that you are collecting from the device": the consent screen and privacy policy list each shared metric.
- **(ii)** Apps "may not store personal health information in iCloud". This rules out CloudKit, iCloud Drive and
  `NSUbiquitousKeyValueStore` for any Friends data; Supabase is permitted.

### 1.2 User-Generated Content

Apps "with user-generated content or social networking services must include" [AS1]:

1. "A method for filtering objectionable material from being posted": the only free text is display names and
   competition titles; run both through a word filter on the client and in a database check, and keep titles
   optional (default titles are generated: "Steps · 6–12 Oct").
2. "A mechanism to report offensive content and timely responses to concerns": report a person or a competition
   title; reports land in a `reports` table with a notification to Patrick (Edge Function email) so response is
   timely.
3. "The ability to block abusive users from the service": block removes the friendship both ways, removes the person
   from shared competitions' views and prevents re-invites.
4. "Published contact information so users can easily reach you": an email in Settings › Friends › Help and in the
   App Store listing.

Apps used for "bullying" or "objectification of real people" are removed: a fixed reaction set (no free-text
comments, no chat in v1) keeps that surface near zero, as Oura does.

### App Privacy "nutrition label" and privacy manifest

Today Baseline declares nothing collected (`Baseline/Resources/PrivacyInfo.xcprivacy`: `NSPrivacyCollectedDataTypes`
empty), which is correct because data "processed only on device is not 'collected'" [AS2]. The same page says "If
you derive anything from that data and send it off device, the resulting data should be considered separately", so
uploading "+8 % HRV" is collecting Health data even though raw HRV stays on the phone. Once Friends ships, the label
changes from *Data Not Collected* to *Data Linked to You*, all for **App Functionality** only, **not used to track**:

| Apple category | Data type | Why |
|---|---|---|
| Health & Fitness | Health | HRV / resting HR / readiness change vs own baseline, sleep duration and timing (only if the person shares them) |
| Health & Fitness | Fitness | Steps, intensity minutes, active days, workouts count |
| Contact Info | Name | Display name |
| Contact Info | Email Address | Supabase Auth stores the Apple-provided (often private-relay) email |
| Identifiers | User ID | Supabase user id, friend codes |
| User Content | Other User Content | Competition titles, report text |

Optional-disclosure does not apply because Friends is core functionality of that tab, not an infrequent optional
submission [AS2]. The manifest's `NSPrivacyCollectedDataTypes` gets the matching entries
(`NSPrivacyCollectedDataTypeHealth`, `…Fitness`, `…Name`, `…EmailAddress`, `…UserID`, `…OtherUserContent`, each
`Linked = true`, `Tracking = false`, purpose `…AppFunctionality`); the widget extension's manifest is unchanged. Check
whether the Supabase Swift packages ship their own manifests. `BASELINE.md`'s "Local only. No accounts" rule becomes
"local by default; Friends is an opt-in account". Re-answer the age-rating questionnaire for user-generated content
and social features.

## 5. GDPR basics (Patrick in Germany, EU users)

- **Health data is special-category data.** Art. 4(15): "'data concerning health' means personal data related to the
  physical or mental health of a natural person … which reveal information about his or her health status". HRV,
  resting-HR change, readiness and sleep fall in it; steps and intensity minutes arguably do in the context of a
  health app. Treat every shared Friends value as special-category.
- **Legal basis: explicit consent.** Art. 9(1) prohibits processing "data concerning health" unless an exception
  applies; Art. 9(2)(a) is "the data subject has given explicit consent to the processing of those personal data for
  one or more specified purposes". Explicit means an affirmative act on a screen that names the data and the purpose
  (a switch per metric with the sentence "Share my weekly steps with my Baseline friends"), separate from accepting
  the terms, not pre-ticked.
- **Withdrawal.** Art. 7(3): the right "to withdraw his or her consent at any time … It shall be as easy to withdraw
  as to give consent." Turning a metric off must delete its server rows, not just hide them.
- **Privacy by default.** Art. 25(2): "by default personal data are not made accessible without the individual's
  intervention to an indefinite number of natural persons". Nothing shared until chosen; no public profiles, no
  search by name, invites only.
- **Children.** Art. 8(1) sets 16 as the age for information-society consent unless a member state lowers it;
  Germany has not. Gate Friends at 16+ (a date-of-birth check against Settings › Profile, or a self-declaration).
- **Rights.** Access and portability (Art. 15, 20: an in-app "Download my Friends data" JSON), erasure (Art. 17:
  account deletion is a hard delete of every Friends row, not Sayner's anonymise-and-keep, which suited shared family
  memories but not health data), information at collection (Art. 13: the consent screen plus the privacy policy).
- **Processor and transfers.** Supabase acts as processor (Art. 28): accept its DPA; create the project in Central EU
  (Frankfurt), which Supabase offers as a region [SB1], so data does not leave the EU.
- **DPIA.** Art. 35(3)(b) makes an impact assessment mandatory for processing "on a large scale of special
  categories"; a friends feature for a free hobby app is not large-scale at launch, but a one-page DPIA note is cheap
  and worth keeping with the privacy policy.
- **Not legal advice.** This is a reading of the texts for engineering decisions; Patrick should have the privacy
  policy checked before a public (non-TestFlight) release.

## 6. Names Baseline must not use

Vendor feature names to keep out of Baseline's copy: Activity rings, Activity sharing (as a feature title), Circles,
Workweek Hustle, Weekend Warrior, Goal Day, Daily Showdown, Adventures, Segments, KOM / QOM, Strain, Recovery,
Teams (as WHOOP's product term), Active Zone Minutes, Body Battery, Stress Monitor, cardio load. Plain descriptive
names instead: "Weekday steps", "Weekend steps", "Week of steps", "Goal days", "Intensity week", "Group goal",
"Bedtime week". Leaderboards are rows and bars, never rings (the three-ring guardrail holds on Friends too).

## 7. RECOMMENDATIONS

### 7.1 What competes head-to-head (behaviour only)

| Metric | Head-to-head? | Source rule | Daily cap for scoring |
|---|---|---|---|
| Steps | Yes (default metric) | `BaselineReadouts.stepReadings` strap-first, iPhone Health fallback; manual Health entries excluded (`HKMetadataKeyWasUserEntered`); CSV imports never count | 60,000 steps / day; % scoring capped at 200 % of goal |
| Intensity minutes | Yes | `BaselineReadouts.intensity` (already personal: Karvonen against own resting and max HR) | 300 credited min / day; % scoring capped at 200 % of weekly goal |
| Active days / workouts | Yes | a day with ≥ 20 credited intensity minutes or a logged workout ≥ 20 min | 1 per day |
| Sleep duration | Only as "nights at or above own goal" | `baselineNights()` | no credit above own goal (orthosomnia) |
| Bedtime consistency | Yes, as "nights within ±30 min of own target bedtime" | `sleepTiming` / `SleepWindow` | 1 per night |
| Calories | No | Low accuracy tier; between-person totals mostly reflect body size | – |
| Stress | No | Low accuracy tier | – |
| HRV, Resting HR, Readiness | **Never**; trend card per person only | see 7.2 | – |

### 7.2 How physiology is shown: each person against their own baseline

Computed on the phone from the same functions Home uses; only the rounded result is uploaded:

- **HRV:** `delta% = round((mean HRV of the last 7 nights / personal baseline − 1) × 100)`, the baseline from
  `Baselines.foldHistory` (the band Home draws). Copy: "HRV +8 % vs own baseline". Plus a band word from
  `Baselines.deviation`: within usual range (|z| < 1), above usual, below usual.
- **Resting HR:** `delta = round(mean RHR last 7 nights − personal baseline)` in bpm. Copy: "Resting HR −2 bpm vs own
  baseline" (or "vs 30 days ago" if that reference is chosen; pick one and use it everywhere).
- **Readiness:** `delta = round(7-day mean score − 30-day mean score)`, copy "Readiness +4 vs own month"; never the
  0–100 score itself.
- **Gates:** shown only after 14 valid nights in the last 30 ("Calibrating" before); display clipped at ±30 % / ±10
  bpm ("more than +30 %"), which hides illness-scale swings from friends; values recomputed once a morning.
- **Presentation:** one row per friend, alphabetical, no crowns, no ordering by value, no competitions, no
  notifications about anyone's physiology.
- **Never shareable:** absolute HRV or resting HR, illness watch / signals, skin temperature, SpO2, breathing rate,
  journal answers, workouts' heart-rate traces, location.

### 7.3 Competition types and scoring

All competitions run over **calendar dates in each participant's own time zone** (a 6–12 October competition is each
person's local 6th to 12th), are 1-on-1 or up to 10 people, invite-only among friends, and freeze results 48 hours
after the last day so late syncs count and later edits do not. Goals and baselines are **locked at the start**.

1. **Goal percent (default for steps and intensity minutes).** Apple-style normalisation.
   - Steps, per day: `points_d = min(steps_d / goal, 2.0) × 100`; total = Σ over the days (7-day max 1,400).
   - Intensity minutes, per week: `points = min(credited_week / weekly_goal, 2.0) × 100` (prorated per day for
     windows shorter than a week: `goal × days / 7`).
   - The step goal is the person's own (default 8,000 per [R9]; floor 3,000 so a tiny goal cannot be used to win).
2. **Total (opt-in "raw" mode).** `score = Σ min(steps_d, 60,000)`. Each row shows its source (strap, iPhone) because
   a bicep strap and a phone count differently (`METRIC_ACCURACY.md`, Steps).
3. **Improvement vs own 4-week average.**
   - `baseline = max(mean daily steps over the 28 days before the start, 0.8 × mean over the 90 days before, 3,000)`
     (the 90-day term and the floor blunt sandbagging the month before).
   - `score = round(Σ window steps / (baseline × window days) × 100)`, capped at 200; needs ≥ 14 of the 28 days with
     data, otherwise the person joins in Goal-percent mode.
4. **Goal days (cooperative-friendly).** Count of days at or above own step goal; everyone who hits every day "wins".
   Ties are expected and fine.
5. **Group goal (cooperative).** The group's summed steps or intensity minutes against a shared target set at start
   (default: Σ each member's goal × days). For the "less active, less social" people for whom support worked as well
   as competition [R1b].
6. **Weekday steps / Weekend steps / Week of steps.** Fixed windows (Mon–Fri, Sat–Sun, Mon–Sun) over any of the
   scoring modes above.
7. **Bedtime week.** Nights within ±30 min of own target bedtime and at or above own sleep goal; max 7. No hours
   leaderboard.

Notifications: at most one "competition update" a day (evening), plus start and result. No "X just passed you".

### 7.4 Anti-cheat (proportionate to friends with no prizes)

- Upload daily aggregates from the strap-first funnel only (one source per day, no strap + phone double count);
  exclude HealthKit samples marked user-entered; imports never count.
- Caps above; a day flagged implausible (e.g. > 60,000 steps, or steps with almost no worn time) scores the cap and
  shows a small "capped" mark.
- Server checks on upsert (a Postgres check constraint and an RPC that recomputes scores; clients never write
  scores).
- Report a result; the competition creator can remove a participant.
- Accept that a shaken phone can still add steps: the defence is small groups, personal-goal scoring and no stakes.

### 7.5 Privacy defaults

- Friends tab works only after Sign in with Apple; the rest of the app never requires an account.
- After sign-in, **every metric toggle is off**; the consent screen lists each metric, its exact shared form ("weekly
  steps", "HRV change vs your own baseline, never your HRV"), who sees it, and that it can be withdrawn any time.
- Joining a competition asks for that metric's share for that competition only if the global toggle is off.
- Per friend: hide my data, mute, remove, block, report (Apple's three controls plus 1.2's two).
- Display name only; no photos, no email shown, no search, no contacts import; invites by 8-character code (uppercase,
  no 0 / O / 1 / I / l, Sayner's rule) or share-sheet link, single use, 7-day expiry (Oura's pattern).
- Fixed reaction set, no chat in v1.
- Server keeps a rolling 35 days of daily values plus final competition results; turning a metric off deletes its
  rows; account deletion hard-deletes everything and revokes the Apple token server-side.
- Supabase project in Central EU (Frankfurt), RLS on every table, anon key in the app, service-role key never in the
  app. No PHI in iCloud; the demo / UI-test backend is in-memory only.

### 7.6 Schema shape that makes per-metric RLS easy

Store shared values one row per person, day and metric (`daily_values(user_id, day, metric, value, source)`) rather
than one wide row, so a single RLS policy can say "visible to my friends when the owner shares this metric":
`using (user_id = auth.uid() or (public.are_friends(user_id) and public.shares(user_id, metric)) and not
public.is_blocked(user_id))`, with `are_friends`, `shares` and `is_blocked` as `security definer` helpers (Sayner's
`is_member` pattern, which avoids policy recursion). Other tables: `profiles`, `invites` (+ `redeem_invite(code)` RPC),
`friendships`, `share_settings`, `competitions`, `competition_members` (+ a `competition_scores(id)` RPC that applies
7.3 server-side), `reports`, `blocks`. `delete_account()` cascades, then an Edge Function revokes the Apple token.

## References

Research (all verified in Europe PMC, 2 October 2026)

- R1. Patel MS, Small DS, Harrison JD, et al. Effectiveness of Behaviorally Designed Gamification Interventions With
  Social Incentives for Increasing Physical Activity Among Overweight and Obese Adults Across the United States: The
  STEP UP Randomized Clinical Trial. *JAMA Intern Med* 2019;179(12):1624–1632. doi:10.1001/jamainternmed.2019.3505.
  PMID 31498375
- R1b. Chen XS, Changolkar S, Navathe AS, et al. Association between behavioral phenotypes and response to a physical
  activity intervention using gamification and social incentives: Secondary analysis of the STEP UP randomized
  clinical trial. *PLoS One* 2020;15(10):e0239288. doi:10.1371/journal.pone.0239288. PMID 33052906
- R2. Zhang J, Brackbill D, Yang S, Becker J, Herbert N, Centola D. Support or competition? How online social networks
  increase physical activity: A randomized controlled trial. *Prev Med Rep* 2016;4:453–458.
  doi:10.1016/j.pmedr.2016.08.008. PMID 27617191
- R3. Arigo D, Brown MM, Pasko K, Suls J. Social Comparison Features in Physical Activity Promotion Apps: Scoping
  Meta-Review. *J Med Internet Res* 2020;22(3):e15642. doi:10.2196/15642. PMID 32217499
- R5. Nunan D, Sandercock GR, Brodie DA. A quantitative systematic review of normal values for short-term heart rate
  variability in healthy adults. *Pacing Clin Electrophysiol* 2010;33(11):1407–1417.
  doi:10.1111/j.1540-8159.2010.02841.x. PMID 20663071
- R6. Patel MS, Volpp KG, Rosin R, et al. A Randomized Trial of Social Comparison Feedback and Financial Incentives to
  Increase Physical Activity. *Am J Health Promot* 2016;30(6):416–424. doi:10.1177/0890117116658195. PMID 27422252
- R7. Baron KG, Abbott S, Jao N, Manalo N, Mullen R. Orthosomnia: Are Some Patients Taking the Quantified Self Too
  Far? *J Clin Sleep Med* 2017;13(2):351–354. doi:10.5664/jcsm.6472. PMID 27855740
- R8. Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation and heart rate variability in
  elite endurance athletes: opening the door to effective monitoring. *Sports Med* 2013;43(9):773–781.
  doi:10.1007/s40279-013-0071-8. PMID 23852425
- R9. Paluch AE, Bajpai S, Bassett DR, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international
  cohorts. *Lancet Public Health* 2022;7(3):e219–e228. doi:10.1016/S2468-2667(21)00302-9. PMID 35247352

Apple

- A1. Apple Watch User Guide, "Share your activity from Apple Watch". https://support.apple.com/en-me/guide/watch/apd68a69f5c7/watchos
- AS1. App Store Review Guidelines (last updated 8 June 2026): 1.2, 4.8, 5.1.1, 5.1.2, 5.1.3.
  https://developer.apple.com/app-store/review/guidelines/
- AS2. App Privacy Details on the App Store. https://developer.apple.com/app-store/app-privacy-details/
- AS3. Offering account deletion in your app. https://developer.apple.com/support/offering-account-deletion-in-your-app/

Fitbit / Google

- F1. Google Health Help, "Connect with friends" (current; May 2026 pause notice, leaderboard metrics).
  https://support.google.com/fitbit/answer/14237026
- F2. Fitbit Help, "How do I connect with friends on Fitbit?" (earlier text: 7-day step total, privacy fields), as
  indexed by search on 2 October 2026; the live page now shows F1's text.
- F3. iMore, "How to use Challenges in Fitbit for iPhone and iPad" (the four challenge formats).
  https://www.imore.com/how-use-challenges-fitbit-iphone-and-ipad
- F4. 9to5Google, "Fitbit Challenges and open groups are no longer available as Google pulls the plug", 27 March 2023.
  https://9to5google.com/2023/03/27/fitbit-challenges-groups-removed/

Garmin

- G1. Garmin blog, "Creating and Joining Garmin Connect Challenges" (22 February 2019).
  https://www.garmin.com/en-US/blog/fitness/creating-connect-challenges/
- G2. Garmin Connect UI strings, `privacy_alert.properties` ("Only Me", "My Connections").
  https://connect.garmin.com/web-translations/privacy_alert/privacy_alert.properties
- G3. Garmin Forums (user reports, not Garmin statements): weekly step challenge groups, promotion, sync rule, badges.
  https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/126718/weekly-step-challenge and
  https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/436306/weekly-steps-badge
- G4. Garmin blog, "Introducing Garmin Connect Challenges" (badge challenges).
  https://www.garmin.com/en-US/blog/general/garmin-connect-challenges/
- G5. "Project Spotlight: Challenges" (a Garmin Connect Challenges designer's write-up; secondary).
  https://medium.com/@pancakefeed/project-spotlight-challenges-475af405b055

WHOOP (pages refuse scripted reads; facts as indexed by search on 2 October 2026)

- W1. WHOOP Support, "Creating or Joining a WHOOP Team". https://support.whoop.com/s/article/Joining-a-WHOOP-Team?language=en_US
- W2. WHOOP Support, "WHOOP Team Averages". https://support.whoop.com/hc/en-us/articles/360044455174-WHOOP-Team-Averages
- W3. WHOOP, "New Community Feature in the App: Team Chat". https://www.whoop.com/us/en/thelocker/community-feature-app-team-chat/

Oura

- O1. Oura Support, "Oura Circles". https://support.ouraring.com/hc/en-us/articles/15958088640147-Oura-Circles
- O2. Oura, "Introducing Oura Circles" (The Pulse blog). https://ouraring.com/blog/introducing-oura-circles/

Strava

- S1. Strava Support, "Privacy Controls". https://support.strava.com/en-us/articles/15401951-privacy-controls
- S2. Strava Support, "The Activity Flag: Remove an Activity's Segment Results from the Leaderboard".
  https://support.strava.com/en-us/articles/15402000-the-activity-flag-remove-an-activity-s-segment-results-from-the-leaderboard
- S3. Strava Stories, "Keeping Strava's Segment Leaderboards Fair: An Engineer's Perspective".
  https://stories.strava.com/articles/keeping-stravas-segment-leaderboards-fair-an-engineers-perspective
- S4. ABC News (Australia), "Strava has published details about secret military bases …", 29 January 2018.
  https://www.abc.net.au/news/science/2018-01-29/strava-heat-map-shows-military-bases-and-supply-routes/9369490

Law and infrastructure

- GDPR (Regulation (EU) 2016/679), Art. 4(15), 7(3), 8(1), 9(1)–(2)(a), 13, 15, 17, 20, 25(2), 28, 35(3)(b).
  https://gdpr-info.eu/
- SB1. Supabase, "Available regions" (Central EU, Frankfurt). https://supabase.com/docs/guides/platform/regions
