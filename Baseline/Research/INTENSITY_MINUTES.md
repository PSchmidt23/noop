# Intensity minutes: what Garmin, the guidelines and the evidence say, and what Baseline will do

*Written 1 October 2026 against NOOP HEAD (`Packages/StrandAnalytics/.../HRZones.swift`, `StrainScorer.swift`,
`Strand/Data/WorkoutZones.swift`, `Strand/Data/Profile.swift`). Vendor claims come from the vendors' own manuals
and help pages, fetched that day; where the only source is a user forum it is labelled as such. Every paper
below was checked against Europe PMC (title, authors, journal, volume, pages, DOI) before it was cited.
Vocabulary is Baseline's (Intensity minutes, Effort, Resting HR); vendor terms appear only when naming the
vendor's own feature.*

## The short version

"Intensity minutes" is one idea wearing four brand names: count the minutes of the week spent at moderate
aerobic intensity, count vigorous minutes twice, and compare the total with the 150-minute weekly target that
WHO, the US Department of Health and Human Services, the AHA and ACSM all publish. Garmin calls it Intensity
Minutes, Fitbit calls it Active Zone Minutes, Apple folds a one-times version into its Exercise ring, and WHOOP
has no minutes metric at all (its load number is a TRIMP-style score). The vendors agree on the ×1 / ×2
weighting and the 150 default, and differ on three things: where "moderate" starts (a heart-rate-reserve
fraction, a max-HR fraction, or an undocumented resting-HR ratio), whether a 10-minute bout is required (Garmin
yes on paper, the 2018 US and 2020 WHO guidelines no), and when the week turns over (Garmin: Monday, fixed).

Baseline's definition (last section) uses the Karvonen heart-rate reserve with the ACSM cut-offs
(moderate ≥ 40 % HRR, vigorous ≥ 60 % HRR), NOOP's %HRmax zones as the fallback when no resting HR exists,
bouts of any length over a 3-minute noise floor, a Monday-to-Sunday local-time week, a 150-minute goal with
vigorous counted twice, and a Home line of the form "23 min today · 112 / 150 this week".

## 1. How Garmin computes Intensity Minutes

**What the manuals say.** Garmin's owner's manuals (vívoactive 5, vívoactive 6, fēnix 7) carry the same
paragraph: the watch "monitors your activity intensity and tracks your time spent participating in moderate to
vigorous intensity activities (heart rate data is required to quantify vigorous intensity)", it "adds the amount
of moderate activity minutes with the amount of vigorous activity minutes", and "your total vigorous intensity
minutes are doubled when added" [G1, G2]. Under *Earning Intensity Minutes*: the watch "calculates intensity
minutes by comparing your heart rate data to your average resting heart rate", "if heart rate is turned off, the
watch calculates moderate intensity minutes by analyzing your steps per minute", and users should "start a timed
activity for the most accurate calculation" and wear the watch continuously so the resting HR is accurate [G1,
G2, G3]. The weekly goal defaults to 150 and is editable ("Weekly Intensity Minutes" in Garmin Connect). The
manuals cite the WHO figures (150 moderate / 75 vigorous per week) as the reason for the feature [G1].

**Which heart-rate thresholds define moderate and vigorous.** Two modes exist:

- *Default algorithm ("Auto").* The manuals only say HR is compared with the average resting HR [G1-G3]; Garmin
  publishes no ratio or percentage. Forum posters (not Garmin staff) describe it as a ratio of all-day HR to the
  7-day average resting HR [G7]; that is unverified. Several threads report that Auto rarely or never awards
  vigorous minutes and that daytime HR spikes without exercise are sometimes credited [G5, G8].
- *Zone mode.* On newer watches the setting "allows you to set a heart rate zone for moderate intensity minutes
  and a higher heart rate zone for vigorous intensity minutes. You can also use the default algorithm" [G4]
  (Garmin Connect → device → Health & Wellness → Weekly Intensity Minutes → Use heart rate zones [G6]). The zone
  you pick is the floor: everything in that zone or above counts. Users commonly pick Zone 3 moderate /
  Zone 4 vigorous [G5, G6]. Garmin's zones default to %Max HR with HRmax = 220 − age: Z1 50–60 %, Z2 60–70 %,
  Z3 70–80 %, Z4 80–90 %, Z5 90–100 % [G9, G10]; the "Based On" setting can switch them to %HRR ("maximum heart
  rate minus resting heart rate"), %LTHR or BPM [G11]. So Garmin's answer to "%max HR vs %HRR vs zones" is
  "whatever your zones are based on", and in the default state that is %max HR with Z3 as moderate.

**The 10-consecutive-minute rule.** Older manuals (vívoactive HR, fēnix 6 user guide) state it outright:
"Exercise for at least 10 consecutive minutes at a moderate or vigorous intensity level" [G3, G8]. The current
vívoactive 5 / 6 and fēnix 7 pages no longer contain that sentence [G1, G2]; Garmin has not said whether the
rule was dropped or merely removed from the text, and forum reports of short walks earning minutes suggest it is
no longer strict [G8]. Garmin does not document whether a dip below threshold inside a bout resets the counter;
on the written rule ("consecutive") it does. Treat the 10-minute rule as Garmin's inheritance from the 2010
guidelines, not as physiology (section 2).

**Does all-day HR count, or only recorded activities?** Both. The feature reads the all-day heart-rate graph, so
a brisk walk without pressing Start earns minutes, and Move IQ auto-detected activities earn them too [G7, G8];
Garmin nonetheless recommends a timed activity "for the most accurate calculation" [G1-G3]. With HR off, only
moderate minutes are credited, from cadence [G1].

**How the week resets.** Monday 00:00 to Sunday 23:59, fixed. Garmin support, in the forums: "The First Day of
the Week setting only applies to your calendar and related features. This setting will not change the
calculation of Intensity Minutes, Weekly Steps Challenge start dates, or how data is displayed in reports; this
data will display a start day of Monday" [G12].

**"Intensity Minutes" vs "Active Minutes".** Garmin has no "Active Minutes" metric; its term is Intensity
Minutes (and the per-day moderate / vigorous split in Garmin Connect). "Active Minutes" is Fitbit's older,
accelerometer-based metric: minutes at ≥ 3 METs in bouts of ≥ 10 minutes, replaced on new devices by Active Zone
Minutes from the Charge 4 (2020) onward [F1, F3]. Apple's equivalent is "Exercise minutes" (section 3).

## 2. The guideline the feature mirrors

- **WHO 2020** (Bull et al. [1]): "All adults should undertake 150–300 min of moderate-intensity, or 75–150 min
  of vigorous-intensity physical activity, or some equivalent combination … per week." And explicitly:
  "MVPA bouts of any duration now count towards these recommendations, reflecting new evidence to support the
  value of total physical activity volume, regardless of bout length. This recommendation differs from the
  requirement of bouts of at least 10 min in the previous WHO 2010 guidelines." WHO defines moderate as 3–5.9
  METs on an absolute scale, vigorous as ≥ 6 METs, and on the relative scale a 5–6 / 7–8 on a 0–10 perceived
  exertion scale [1].
- **US HHS 2018** (Piercy et al. [2]): the same 150 / 75 targets, and the first major guideline to drop the
  10-minute bout: moderate-to-vigorous activity "of any duration may be included in the daily accumulated
  total" [2].
- **AHA** restates HHS: "at least 150 minutes per week of moderate-intensity aerobic activity or 75 minutes per
  week of vigorous aerobic activity, or a combination of both, preferably spread throughout the week" [3].
- **ACSM's relative-intensity table** (Garber et al. 2011 [4]) is where the heart-rate numbers come from:
  moderate = 40–59 % HRR (≈ 64–76 % HRmax), vigorous = 60–89 % HRR (≈ 77–95 % HRmax). %HRR is the Karvonen
  reserve [5]; Swain and Leutholtz showed %HRR tracks %VO2 reserve one-to-one, whereas %HRmax does not [6, 7],
  which is why prescriptions use HRR when a resting HR is known. The ×2 weighting is the guideline's own
  "75 vigorous ≡ 150 moderate" equivalence.

Nothing in the guidelines asks for a 10-minute bout anymore; the only reason to smooth short runs is sensor
noise, not health science.

## 3. The same idea on Apple, Fitbit and WHOOP

**Apple (Exercise ring).** "Every full minute of movement that equals or exceeds the intensity of a brisk walk
counts toward your daily Exercise and Move goals. Your cardio fitness levels are used to determine what is brisk
for you"; "heart rate is one of many factors" [A1]. Daily goal, default 30 minutes, ×1 only; no vigorous
doubling and no weekly total in the ring. Warner et al. (2025) measured where the native app starts crediting
"exercise": at a walking speed where mean %VO2R was 33 % (95 % HDI 31–36), below the 40 % relative-intensity
floor for moderate; a bespoke %HRR app landed at 43 % [12]. Apple's minute is therefore a little more generous
than ACSM's moderate.

**Fitbit (Active Zone Minutes).** Zones are HRR-based with HRmax = 220 − age: below 40 % HRR light, 40–59 %
"fat burn" (moderate), 60–84 % "cardio" (vigorous), ≥ 85 % "peak" [F2]. "1 minute in the fat burn zone" = 1 AZM,
"1 minute in the cardio or peak zone" = 2 AZM [F1, F3]. Default goal 150 per week (shown as 22 per day) [F1]. No
bout rule: credit is immediate, which was the advertised change from the old 10-minute Active Minutes [F1, F3].
Swims earn 1 per minute without HR [F1]. This is the closest published analogue to Baseline's definition.

**WHOOP.** No intensity, exercise or active minutes. Its load number (branded "Strain", 0–21) is a weighted
time-in-zone accumulation over the day, with zones computed on heart-rate reserve [W1, W2]; the WHOOP blog also
describes weekly time-in-zone targets by age [W2], but there is no guideline-style minute count in the app.
NOOP's `StrainScorer` reproduces the same Edwards-zone TRIMP on %HRR (50/60/70/80/90 % HRR), which is why
Baseline's Effort already has the Karvonen plumbing it needs.

| | Garmin | Fitbit | Apple | WHOOP | Baseline (section 5) |
|---|---|---|---|---|---|
| Moderate floor | Auto: undisclosed vs resting HR; zone mode: your zone (default %HRmax, Z3 = 70 %) | 40 % HRR | "brisk walk", ≈ 33 % VO2R measured | none | 40 % HRR (fallback Z3 = 70 % HRmax) |
| Vigorous floor | zone mode: your zone (Z4 = 80 % HRmax) | 60 % HRR | none | none | 60 % HRR (fallback Z4 = 80 % HRmax) |
| Weighting | ×1 / ×2 | ×1 / ×2 | ×1 | n/a | ×1 / ×2 |
| Bout rule | 10 min consecutive (older manuals) | none | full minute | n/a | ≥ 3 qualifying min, 1-min gaps tolerated |
| All-day HR counts | yes | yes | yes | n/a | yes |
| Goal | 150 / week | 150 / week (22 / day) | 30 / day | n/a | 150 / week |
| Week | Mon–Sun fixed | weekly total in app (start day not documented) | day only | n/a | Mon–Sun, local time |

## 4. Validation evidence for HR-based intensity classification on the wrist and arm

The question for Baseline is not "is the HR right to the beat" but "does the device put a minute on the right
side of the 40 % and 60 % HRR lines". The evidence, all against ECG or a chest strap:

- **Ho, Yang and Li (2022)** is the one study that tests exactly this: 30 adults, Apple Watch Series 6 and
  Garmin Forerunner 945 against ECG at the Karvonen thresholds HR40, HR60 and HR89 (ACSM moderate / vigorous
  bounds). MAE 1.16–1.48 bpm (Apple) and 1.35–2.25 bpm (Garmin), MAPE < 1 % and 1.2–1.4 %, concordance > 0.95 at
  every bound except Garmin at HR89 (0.936); Bland–Altman showed no systematic error. Conclusion: "high validity
  of exercise prescriptions based on the heart rate measured by the two devices" [8].
- **Dooley, Golaszewski and Bartholomew (2017)**: 62 adults, Apple Watch, Fitbit Charge HR, Garmin Forerunner
  225 vs chest strap at light, moderate and vigorous treadmill stages. Apple Watch HR MAPE 1.14–6.70 %, with
  significant under-reading at light and moderate intensity and none at vigorous; Fitbit and Garmin were less
  accurate [9]. Under-reading at moderate intensity pushes borderline minutes below the moderate line, i.e.
  wrist devices tend to under-count, not over-count.
- **Reddy et al. (2018)**: Fitbit Charge 2 and Garmin vívosmart HR+ vs Polar chest strap across a VO2max test,
  resistance circuit, intervals and daily living (20 adults). Mean relative error −3.3 % (Garmin) and −4.7 %
  (Fitbit) overall, worst on high-intensity cycling (−11 to −14 %) and when the exercise mode was not started,
  best on treadmill intervals (−0.5 to −1.7 %) [10].
- **Wallen et al. (2016)**: four wrist devices vs ECG at rest, walking, running and cycling: HR error 1–9 %,
  all under-estimating; correlations 0.67–0.95 [11].
- **Boudreaux et al. (2018)**: eight monitors during graded cycling and resistance exercise; only the Polar
  chest strap and an in-ear sensor were valid (MAPE ≤ 10 %) in both modes; wrist devices failed the 10 % bar
  during resistance exercise [13]. Bai et al. (2018) likewise put Fitbit Charge HR HR MAPE at 7–10 % [14].
- **Arm vs wrist.** Schweizer and Gilgen-Ammann (2025): an upper-arm optical sensor (Polar Verity Sense)
  reached MAPE 1.35 %, CCC 1.00 across nine activities from lying to HIIT, while the wrist watch (Vantage V2)
  managed MAPE 6.8 %, CCC 0.92 with wide swings by activity [15]. This is directly relevant to a WHOOP strap worn
  on the bicep: the arm is the better site. Bellenger et al. validated WHOOP's own HR against ECG with bias
  ≤ 0.39 % (see METRIC_ACCURACY.md [1]).
- **Minutes, not beats.** Briggs et al. (2021): Garmin vívosmart HR MVPA minutes vs a hip ActiGraph in 35 older
  adults over free-living days. Garmin over-counted against the population cut-point (50 vs 7 min/day,
  p < 0.001) but was close to the age-appropriate cut-point (50 vs 32, p = 0.35), with poor day-to-day
  reliability (ICC 0.16–0.35) [16]. Warner et al. (2025) showed Apple's native "exercise" minute starts below
  40 % HRR [12]. There is no published validation of Garmin's Auto Intensity Minutes or of Fitbit AZM as such.

What this means: HR measured at the arm during steady aerobic work is accurate to a few percent, so a minute that
is clearly above 40 % HRR is classified correctly; the risk sits in (a) borderline minutes, where a 3–5 % bias
flips the class, (b) resistance training and cycling, where optical HR lags and under-reads, and (c) daytime
HR rises without movement (stress, caffeine, heat), which an HR-only rule credits as activity. Baseline's
answer is a Medium accuracy tier with the caveat "minutes near the moderate line and strength sessions are
uncertain", a short bout floor to damp (a) and (c), and no attempt to show the number to better than whole
minutes.

## 5. DEFINITION for Baseline

Everything below is implementable with the engine as it stands; no NOOP file changes.

**Inputs.**
- HR stream: `repo.hrSamples(from:to:limit: 200_000)` over [local midnight, local midnight + 24 h) for each
  day of the week (WHOOP ids only, ~1 Hz when worn; WHOOP 5.0 / MG per-second HR is PPG-derived, so
  `ScoreConfidence.effort` style ".building" applies).
- *As shipped (`IntradayDayStore`, amended October 2026).* Each day is computed once and cached per day key
  on a witness taken from its 60-second buckets (`repo.hrBuckets(from:to:bucketSeconds: 60)`, measured ∪
  PPG-derived), NOT on `repo.hrFingerprint(from:to:)`, which counts the measured `hrSample` table only and
  so read a PPG-only day (WHOOP 4.0 on v25 firmware, most of a 5.0 / MG day) as empty. A day inside the
  14-day verify window is classified from the raw samples above under the rule below; an older day the
  cache computes for the first time (a long range opened after install, a restored back-catalogue) is
  classified from its 60-second bucket MEANS instead, one minute per bucket with no sample floor (a bucket
  carries no sample count), so for those days the 3-minute bout floor is the only noise filter.
- HRmax: `profile.effortHRmax` (manual override, else Tanaka 208 − 0.7·age [17]). Nil (no age entered) → the
  card asks for age exactly as the Fitness card does; nothing is computed on a guessed age.
- Resting HR reference `RHRref`: median of the last 7 nights' `restingHr` in `repo.baselineDays` ending the
  night before the day (≥ 3 nights required); else that day's own `restingHr`; else none. This is the
  strap-first funnel, never `repo.days`.

**Thresholds (Karvonen %HRR, ACSM cut-offs [4, 5]).**
- `HRR = HRmax − RHRref`; `pctHRR(bpm) = (bpm − RHRref) / HRR × 100`.
- moderate: `pctHRR ≥ 40`; vigorous: `pctHRR ≥ 60`. No upper bound (peak is vigorous).
- Fallback when `RHRref` is nil: NOOP's %HRmax zones through `profile.hrZoneSet.zoneNumber(forBPM:)`
  (`HRZones.zoneEdges` 50/60/70/80/90 % HRmax, custom bounds honoured): moderate = Zone 3 or above
  (≥ 70 % HRmax), vigorous = Zone 4 or above (≥ 80 % HRmax). This is Garmin's zone-mode convention; it is a
  little stricter than ACSM's 64 / 77 % HRmax, which is the safer direction for a fallback. The readout carries
  `basis: .hrr | .hrMax` so the card can say "from your resting HR" or "from max HR only".
- Defaults are constants, not settings; the only user settings are the weekly goal and the profile fields NOOP
  already has (age, HRmax override, custom zones).

**Minute classification.**
- Bucket samples into local-clock minutes. A minute is scored only if it holds ≥ 20 samples (≈ 20 s at 1 Hz);
  its HR is the median bpm of its samples (robust to a single artefact).
- Class per minute: vigorous / moderate / below. Minutes with < 20 samples are "unscored" and never count,
  toward credit or toward the 240-minute "partial day" line (as shipped: every day inside the 14-day
  verify window; see Inputs for the bucket-mean days, where every 60-second bucket is one scored minute).

**Bout rule (WHO 2020 / HHS 2018: any duration counts; the floor below is a noise filter, not a guideline).**
- A bout is a maximal run of moderate-or-above minutes in which gaps of at most 1 consecutive below/unscored
  minute are tolerated (the gap minute itself earns nothing and does not break the bout). A gap of ≥ 2 minutes
  ends the bout.
- A bout counts only if it contains ≥ 3 qualifying minutes. There is no 10-minute requirement.
- Credit: each moderate minute in a counted bout = 1, each vigorous minute = 2.

**Day and week.**
- Day = local calendar day (`Repository.localDayKey`), not the sleep-cycle "logical" day: intensity is a
  waking-hours quantity and the week must add up from calendar days. DST days are whatever length the clock
  makes them.
- Week = Monday 00:00 local to the following Monday 00:00 local (`Calendar` with `firstWeekday = 2`
  regardless of locale, matching Garmin and ISO 8601). Identified by its Monday's day key. The week total is
  the sum of the credited minutes of its days up to and including today; past weeks are complete.
- Goal: `baseline.intensityWeeklyGoal`, default 150, editable 60–600 in steps of 10 (Settings → Profile).
  Vigorous is already doubled inside the day numbers, so the goal is compared to the credited total.

**Readout.**
```swift
struct IntensityReadout {
    let day: String                 // "yyyy-MM-dd"
    let moderateMin: Int            // raw minutes ≥ 40 % HRR and < 60 % inside counted bouts
    let vigorousMin: Int            // raw minutes ≥ 60 % HRR inside counted bouts
    var creditedToday: Int { moderateMin + 2 * vigorousMin }
    let weekStart: String           // the Monday's day key
    let weekDays: [Int]             // credited minutes Mon…today (length 1–7)
    var weekCredited: Int { weekDays.reduce(0, +) }
    let weekGoal: Int               // default 150
    let basis: Basis                // .hrr(rhr: Int, hrMax: Int) | .hrMax(hrMax: Int) | .needsAge
    let scoredMinutes: Int          // scored minutes (≥ 20 samples) today; < 240 → "partial day" caption
}
```
`BaselineReadouts.intensity(_ repo:profile:for:calendar:) async -> IntensityReadout?` (main-actor wrapper over
a pure `IntensityMinutes.classify(samples:thresholds:calendar:)` + `IntensityMinutes.credit(_:)` in
`Baseline/Components/`, with tests on synthetic 1 Hz streams: a 25-minute walk at 45 % HRR → 25; a 20-minute
run at 70 % → 40; two 2-minute spikes → 0; a 12-minute bout with one 1-minute dip → 11; DST Sunday week
sums; Monday rollover at 00:00 local).

**Imported data without an HR stream.** A WHOOP CSV workout carries only zone percentages; for a day with no
strap HR but with such rows, `WorkoutZones.summary` gives Z1–Z5 minutes on %HRmax zones: moderate = Z3,
vigorous = Z4 + Z5, bout rule not applicable, `basis: .workoutsOnly`, caption "from workouts only". Apple
Health "exercise minutes" are not read in v1 (×1 only, different threshold; would mix bases).

**What Home shows (one line, context once).**
`IntensityCard` under the Steps card: title "Intensity minutes", hero `"23 min"` with caption `"today"`, and a
single horizontal track (never a ring; Readiness and the two metric rings already own the screen's budget)
labelled `"112 / 150 this week"`, Monday ticks on the track. Tapping opens the week: seven bars (credited
minutes, `effort` colour at `barOpacity`, vigorous share at full opacity), the split "38 moderate · 37 vigorous
(×2)", the basis line "40 % / 60 % of your heart-rate reserve (resting 52, max 182)", the `AccuracyBadge`
(Medium) and the one caveat: "Minutes near the moderate line and strength sessions are uncertain." No
"Active Zone Minutes", "Exercise ring" or "Strain" anywhere in copy; "Intensity minutes" is the generic term.

## References

Peer-reviewed (verified in Europe PMC, 1 October 2026)

1. Bull FC, Al-Ansari SS, Biddle S, et al. World Health Organization 2020 guidelines on physical activity and
   sedentary behaviour. *Br J Sports Med* 2020;54(24):1451–1462. doi:10.1136/bjsports-2020-102955
2. Piercy KL, Troiano RP, Ballard RM, et al. The Physical Activity Guidelines for Americans. *JAMA*
   2018;320(19):2020–2028. doi:10.1001/jama.2018.14854
3. American Heart Association. American Heart Association Recommendations for Physical Activity in Adults and
   Kids. https://www.heart.org/en/healthy-living/fitness/fitness-basics/aha-recs-for-physical-activity-in-adults
   (web page, read 1 Oct 2026)
4. Garber CE, Blissmer B, Deschenes MR, et al. American College of Sports Medicine position stand. Quantity and
   quality of exercise for developing and maintaining cardiorespiratory, musculoskeletal, and neuromotor fitness
   in apparently healthy adults: guidance for prescribing exercise. *Med Sci Sports Exerc* 2011;43(7):1334–1359.
   doi:10.1249/MSS.0b013e318213fefb
5. Karvonen MJ, Kentala E, Mustala O. The effects of training on heart rate; a longitudinal study. *Ann Med Exp
   Biol Fenn* 1957;35(3):307–315. PMID 13470504
6. Swain DP, Leutholtz BC. Heart rate reserve is equivalent to %VO2 reserve, not to %VO2max. *Med Sci Sports
   Exerc* 1997;29(3):410–414. doi:10.1097/00005768-199703000-00018
7. Swain DP, Leutholtz BC, King ME, Haas LA, Branch JD. Relationship between % heart rate reserve and % VO2
   reserve in treadmill exercise. *Med Sci Sports Exerc* 1998;30(2):318–321. doi:10.1097/00005768-199802000-00022
8. Ho WT, Yang YJ, Li TC. Accuracy of wrist-worn wearable devices for determining exercise intensity. *Digit
   Health* 2022;8:20552076221124393. doi:10.1177/20552076221124393
9. Dooley EE, Golaszewski NM, Bartholomew JB. Estimating Accuracy at Exercise Intensities: A Comparative Study of
   Self-Monitoring Heart Rate and Physical Activity Wearable Devices. *JMIR Mhealth Uhealth* 2017;5(3):e34.
   doi:10.2196/mhealth.7043
10. Reddy RK, Pooni R, Zaharieva DP, et al. Accuracy of Wrist-Worn Activity Monitors During Common Daily Physical
    Activities and Types of Structured Exercise: Evaluation Study. *JMIR Mhealth Uhealth* 2018;6(12):e10338.
    doi:10.2196/10338
11. Wallen MP, Gomersall SR, Keating SE, Wisløff U, Coombes JS. Accuracy of Heart Rate Watches: Implications for
    Weight Management. *PLoS One* 2016;11(5):e0154420. doi:10.1371/journal.pone.0154420
12. Warner A, Vanicek N, Benson A, Myers T, Abt G. Criterion validity of a newly developed Apple Watch app ('MVPA')
    compared to the native Apple Watch 'activity' app for measuring criterion moderate intensity physical activity.
    *Digit Health* 2025;11:20552076251326225. doi:10.1177/20552076251326225
13. Boudreaux BD, Hebert EP, Hollander DB, et al. Validity of Wearable Activity Monitors during Cycling and
    Resistance Exercise. *Med Sci Sports Exerc* 2018;50(3):624–633. doi:10.1249/MSS.0000000000001471
14. Bai Y, Hibbing P, Mantis C, Welk GJ. Comparative evaluation of heart rate-based monitors: Apple Watch vs Fitbit
    Charge HR. *J Sports Sci* 2018;36(15):1734–1741. doi:10.1080/02640414.2017.1412235
15. Schweizer T, Gilgen-Ammann R. Wrist-Worn and Arm-Worn Wearables for Monitoring Heart Rate During Sedentary and
    Light-to-Vigorous Physical Activities: Device Validation Study. *JMIR Cardio* 2025;9:e67110. doi:10.2196/67110
16. Briggs BC, Hall KS, Jain C, Macrea M, Morey MC, Oursler KK. Assessing Moderate to Vigorous Physical Activity in
    Older Adults: Validity of a Commercial Activity Tracker. *Front Sports Act Living* 2021;3:766317.
    doi:10.3389/fspor.2021.766317
17. Tanaka H, Monahan KD, Seals DR. Age-predicted maximal heart rate revisited. *J Am Coll Cardiol*
    2001;37(1):153–156. doi:10.1016/S0735-1097(00)01054-8

Garmin (manuals and support, read 1 Oct 2026)

- G1. vívoactive 5 Owner's Manual, "Intensity Minutes" / "Earning Intensity Minutes".
  https://www8.garmin.com/manuals/webhelp/GUID-5D183A14-BB43-4A9B-B441-5F824214CE40/EN-US/GUID-63522E07-AD5E-4D2D-B680-3129A2300238.html
- G2. fēnix 7 Series Owner's Manual, "Intensity Minutes".
  https://www8.garmin.com/manuals-apac/webhelp/fenix7series/EN-SG/GUID-F12860E3-1A1E-4767-90EA-7938504EBF0D-6457.html
  and vívoactive 6 Owner's Manual, "Intensity Minutes".
  https://www8.garmin.com/manuals-apac/webhelp/vivoactive6/EN-SG/GUID-10B6C796-1DAE-498F-8D51-E34800135B8D-8553.html
- G3. vívoactive HR Owner's Manual, "Earning Intensity Minutes" (the 10-consecutive-minute sentence).
  https://www8.garmin.com/manuals/webhelp/vivoactivehr/EN-GB/GUID-02D2D4E7-4CEE-44C7-831C-2E5F58613B60.html
- G4. vívoactive 4/4S Owner's Manual, "Activity Tracking Settings" (Intensity Minutes zone setting).
  https://www8.garmin.com/manuals/webhelp/vivoactive4_4S/EN-US/GUID-018B4A1D-17C8-4F7C-8D10-1521D9D8FC9C.html
- G5. Garmin Forums, "What is 'vigorous'" (user reports on Auto mode). https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/140685/what-is-vigorous
- G6. Garmin Forums, "Garmin Connect calculating moderate and vigorous intensity minutes very strangely when set
  to zones" (setting path, Z3 / Z4). https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/377125/
- G7. Garmin Forums, "intensity minutes calculation" (user description of the 7-day resting-HR ratio; unverified).
  https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/277504/intensity-minutes-calculation
- G8. Garmin Forums, "Intensity minutes - during an activity vs normal walk" (all-day credit, 10-minute quote from
  the fēnix 6 guide). https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-6-series/195840/
- G9. Garmin blog, "How you can train by heart rate zones using Garmin" (default %Max HR zones, 220 − age).
  https://www.garmin.com/en-US/blog/fitness/how-you-can-train-by-heart-rate-zones-using-garmin/
- G10. Forerunner 265 Owner's Manual, "Heart Rate Zone Calculations".
  https://www8.garmin.com/manuals/webhelp/GUID-F41EAFB3-6CC9-42DE-9C6C-9E358DBB0671/EN-US/GUID-A8716C0B-B267-4C42-B45F-B9C7928BCA19.html
- G11. Forerunner 265 Owner's Manual, "Setting Your Heart Rate Zones" (Based On: BPM / %Max. HR / %HRR / %LTHR).
  https://www8.garmin.com/manuals/webhelp/GUID-F41EAFB3-6CC9-42DE-9C6C-9E358DBB0671/EN-US/GUID-30C91919-943C-44E9-8048-901AC0881AEA.html
- G12. Garmin Forums (Garmin support reply), "Why do weekly Intensity minutes start from Monday when I set my
  'week start' to Sunday?". https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-7-series/323806/

Fitbit, Apple, WHOOP (vendor pages, read 1 Oct 2026)

- F1. Google / Fitbit Help, "Track Active Zone Minutes or active minutes on your Fitbit device and Pixel Watch".
  https://support.google.com/fitbit/answer/14236509
- F2. Google / Fitbit Help, "Track your heart rate with your Pixel Watch or Fitbit device" (zone definitions in
  %HRR, 220 − age). https://support.google.com/fitbit/answer/14237938
- F3. Fitabase Knowledge Base, "Active Zone Minutes". https://www.fitabase.com/resources/knowledge-base/learn-about-fitbit-data/active-zone-minutes/
- A1. Apple Support, "Get the most accurate measurements using your Apple Watch" (Exercise minute definition).
  https://support.apple.com/en-us/105002
- W1. WHOOP, "Why WHOOP Uses Heart Rate Reserve, Not Max Heart Rate". https://www.whoop.com/us/en/thelocker/why-whoop-uses-heart-rate-reserve-not-max-heart-rate/
  (title confirmed; page body not retrievable by script, so no figures are quoted from it)
- W2. WHOOP, "WHOOP Heart Rate Zones Guide". https://www.whoop.com/us/en/thelocker/more-personalized-heart-rate-zones-with-whoop/
  (same caveat)
