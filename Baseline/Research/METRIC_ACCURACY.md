# How accurate are strap and wrist wearables? A cited review for Baseline

*Scope: consumer PPG + accelerometer devices (WHOOP 4.0/5.0, wrist watches, rings) against laboratory references,
written to decide what Baseline should headline, caveat, or leave out. Paper titles are quoted verbatim; our own
prose uses Baseline's words (HRV, Resting HR, Readiness, Sleep, Effort, Steps, Calories, Stress). Checked October 2026.*

## The short version

The strap is excellent at one thing: measuring the heart at night. Nocturnal resting HR and nightly HRV from WHOOP
agree with ECG closely enough that change against a personal baseline is real signal. Everything downstream gets
softer: sleep/wake and total sleep time are good, sleep *timing* is good enough to build a regularity metric on,
sleep *stages* are coarse, steps are fine, calories and VO2 max carry double-digit percentage error, SpO2 and skin
temperature only mean something as deviations from baseline, and daytime stress and composite readiness scores have
no independent validation at all. Baseline's current emphasis (HRV and Resting HR against a personal band) is right.

## Metric by metric

### Resting heart rate (nightly) — **High**

Bellenger et al. validated WHOOP against ECG: HR bias ≤0.39% with limits of agreement ≤1.6% [1]. Miller, Sargent and
Roach (2022; 53 adults, six devices, PSG + ECG) found WHOOP under-reading HR by 0.3 bpm (absolute bias 0.7 bpm) [2].
Dial et al. (2025; five devices, 536 nights, ambulatory ECG) put Oura and WHOOP in acceptable agreement for nocturnal
RHR, Garmin and Polar lower [3]. During exercise most wrist devices stay within 5% but drift with walking, higher BMI
and darker skin [4].
**App:** headline it against the 30-night baseline and band; a 2–3 bpm shift is above the noise.

### Nightly HRV (RMSSD) — **High** as a trend, Medium as an absolute number

WHOOP's filtered lnRMSSD agreed with ECG within about 3% [1]; the 2024 WHOOP systematic review summarises HRV as a
4.5 ms under-read with ICC 0.99 [5]. Dial et al.: WHOOP 4.0 concordance 0.94, MAPE 8% (Oura Gen 4 0.99 / 6%; Garmin
0.87 / 11%; Polar 0.82 / 16%) [3]. Miller 2022 still flagged HRV as the weaker cardiac metric across devices [2], and
Bellenger measured natural week-to-week lnRMSSD variation at about 5%, the same order as device error, so single
nights should not be over-read [1]. Devices also compute "nightly HRV" over different windows, so absolute ms are not
comparable between brands [3].
**App:** keep it as the headline trend; always show the 7-night average against the personal band.

### Sleep duration (total sleep time, sleep/wake) — **Medium-High**

Miller et al. (2020): WHOOP over-read TST by 8 ± 33 min versus PSG, with 86–90% sleep/wake epoch agreement [6].
Chinoy et al. (2021; seven devices): sleep sensitivity 0.93–0.99 but wake specificity only 0.18–0.54; TST bias −0.3 to
+47 min; WASO under-read by 2–50 min [7]. Their 2022 at-home study found TST, efficiency, latency and WASO adequate on
most nights, best on consolidated nights [8]. Stone et al. (2020) found wide device-to-device spread, Oura and Fitbit
Ionic best [9]. Lee et al. (2025 meta-analysis; 24 studies, 798 participants) pooled TST −17 min, efficiency −4.7
points, WASO +13 min for wrist devices [10].
**App:** hours against the 30-night average, with ±30 min night-to-night noise implied; no efficiency to a tenth of a
percent and no alert on one short night.

### Sleep timing (bedtime / wake time) — **Medium-High**

Onset and final wake are long state changes, so wearables get them most right. Chinoy 2021: sleep-onset-latency bias
only −7.6 to +4.4 min across seven devices [7]. Robbins et al. (2024; Oura, Fitbit, Apple vs PSG): sleep sensitivity
≥95% for all, Oura's wake and stage durations not different from PSG [11]. For WHOOP, Miller 2020 reported auto
detection at 90% sleep / 60% wake sensitivity versus 97% / 45% with hand-entered bedtimes, so auto-detect trades a
little sleep sensitivity for better edge detection [6]. Onset and offset typically land within 10–15 min of PSG,
far below the 60–90 min night-to-night variability of most people's bedtimes.
**App:** this is the data Baseline is not yet using. Track average bedtime, average wake time and a consistent window,
each against its 30-night average.

### Sleep regularity (Sleep Regularity Index) — **High**, with the strongest outcome evidence of any sleep metric

The SRI (Phillips et al. 2017) is the probability that any two moments 24 h apart share a sleep/wake state, 0–100 [12].
It needs only sleep/wake, exactly what wearables do best; Fischer, Klerman and Phillips (2021) compared five
regularity metrics and favoured SRI for day-to-day change [13]. Why it matters: each 10-point SRI gain tracked +0.10
GPA and earlier circadian phase in students [12]; in 1,978 MESA adults irregularity tracked 10-year CVD risk, obesity,
hypertension, HbA1c and depression independent of duration [14]; in 60,977 UK Biobank adults with accelerometer SRI
the most regular quintile had 48% lower all-cause mortality (HR 0.52), and regularity out-predicted duration [15].
Lujan, Perez-Pozuelo and Grandner (2021) review how multi-sensor wearables get there [16].
**App:** build it. Compute SRI (or SD of bed and wake times) from strap nights and show the week's value against its
average. Highest-value sleep feature we can build on honest data.

### Sleep stages (4-class) — **Low**

Chinoy 2021: every device differed from PSG for light sleep; deep and REM epochs misclassified 30–50% of the time [7].
Miller 2022: WHOOP labelled 32% of N3 and 23% of REM as light; sleep/wake kappa 0.44 (Apple Watch 0.30) [2]. Stone
2020: no device quantified stages accurately [9]. Walch et al. (2019) show the ceiling for open accelerometer + PPG
algorithms: 90% sleep/wake, about 72% wake/NREM/REM [17]. The best ring result (Svensson et al. 2024; Oura Gen3, 96
participants) is 92% sleep/wake accuracy, 73% wake specificity, stage sensitivity 76–80%, REM slightly under-read [18].
**App:** stages stay a soft visual, never a number to optimise. One caveat line; no deep-sleep goal or stage trend.

### Steps — **Medium-High** on the wrist, Medium for a strap on the bicep or in clothing

Evenson et al. (2015): lab step correlations ≥0.80 [19]. Fuller et al. (2020; 158 papers): Fitbit, Apple Watch and
Samsung count steps accurately in the lab, worse free-living and at slow walking [20]. WHOOP added full step counting
with the 5.0 in 2025; no independent validation exists, and non-wrist placement will cost accuracy.
**App:** today's steps against the 7-day and 30-day average, rounded to the hundred; a self-consistent trend, not a count.

### Energy expenditure / Calories — **Low**

Shcherbina et al. (2017; seven wrist devices, calorimetry): HR within 5%, but no device within 20% for energy
expenditure, median errors 27–93% [4]. Fuller 2020: no brand accurate [20]. No peer-reviewed calorimetry validation of
WHOOP calories could be located (reseller pages assert one; it is not cited here).
**App:** relative to your average only, with a standing caveat; never a basis for intake advice.

### VO2 max estimates — **Low** (resting-based), Medium (GPS-run-based, population level)

Molina-Garcia et al. (2022; INTERLIVE meta-analysis, 14 studies): resting-based estimates significantly overestimate;
exercise-based ones have lower bias but large individual error [21]. Caserman et al. (2024): Apple Watch 7 under-read
lab VO2max by 4.5 mL/kg/min, MAPE 16%, ICC 0.47 [22]. Firstbeat's white paper claims 95% within 3.5 mL/kg/min with a
chest strap and running speed [23]; wrist-only Garmin results run near 5 mL/kg/min. WHOOP's 2025 estimate blends
HR-zone time, respiratory rate and GPS runs, unvalidated [24].
**App:** optional, labelled "estimate": a fitness band and the 3-month direction, not a decimal.

### SpO2 — **Low** absolute, Medium as a trend

Pipek et al. (2021; Apple Watch 6 vs clinical oximeters, 100 lung patients): r = 0.81 for SpO2 (0.995 for HR) [25].
Jiang et al. (2023): MAE 2.2% (Apple Watch 7) to 5.8% (Garmin Venu 2s), 11–30% of readings missing [26]. No
independent WHOOP SpO2 validation.
**App:** nightly average versus personal baseline only; no absolute threshold, no "low oxygen" alert.

### Skin temperature — **Medium** as a deviation only

Peripheral skin temperature is not core temperature and swings with room and blanket. Its value is as a baseline
deviation: Mason et al. (2022; TemPredict, Oura) detected COVID-19 2.75 days before testing, sensitivity 82%,
specificity 63%, with temperature adding 4.9% to AUC [27]. WHOOP reports a 7-day-baseline deviation for the same
reason; no independent accuracy study of its sensor exists.
**App:** already right — a confounder-aware illness signal over several nights, never a thermometer reading.

### Daytime stress from HRV — **Low**

HRV does respond to acute stress (Kim et al. 2018; 37-study meta-analysis) [28], but daytime PPG HRV is swamped by
movement, posture, caffeine and talking. Rosenbach et al. (2025; preregistered, n = 60): Garmin's stress score
correlated r = 0.84 with heart rate, −0.41 with RMSSD and −0.17 with perceived stress; plain HR predicted felt stress
better than the score [29, 30]. Firstbeat concedes positive and negative arousal look alike. Doherty et al. (2025)
note WHOOP's stress monitor has no published validation [31].
**App:** no stress score. At most, daytime HR above resting as "activation", with the Journal explaining tomorrow's HRV.

### Composite readiness scores — **Low** as a validated instrument

Doherty, Baldwin, Lambe, Burke and Altini (2025) catalogued 14 composite scores from 10 manufacturers: HRV (86%),
resting HR (79%), activity (71%) and sleep duration (71%) are the usual inputs, no formula is disclosed, and none has
independent validation against a clinical or performance outcome [31]. The WHOOP review (Khodr et al. 2024) likewise
found evidence only for component accuracy, not for the score's decisions [5].
**App:** Baseline's Readiness stays transparent: `HRVReadiness.evaluate`, a number on a horizontal track, inputs
visible, never a verdict on what to do today.

### Effort (HR-zone training load) — **Medium**

Zone load is only as good as exercise HR, which PPG handles well for running and cycling (within 5% [4]; Apple Watch and
Garmin best [20]) and poorly for resistance work and wrist-flexion sports; a bicep strap is less exposed. The 7:28-day
ratio behind the overreaching signal is a published convention, not a measurement.
**App:** today's load against the 7- and 28-day context; caveat strength sessions.

## What this means for the product

1. HRV and Resting HR stay the headline; they are the only High-tier measurements.
2. Keep Sleep for duration and timing, not stages. Build average bedtime, average wake time, a consistent window and
   SRI on what the strap already detects well.
3. Steps: today versus average is honest and cheap.
4. Calories, VO2 max, SpO2, stress: estimate-tier or worse; show as deviations with a caveat, or not at all.
5. No stress score, no three-ring composite; Readiness stays a transparent number plus track.

## Machine-readable summary

| metric_key | tier | one_line_caveat |
|---|---|---|
| hrv | High | Trend against your own 30-night band; single nights are noisy and absolute ms differ between devices. |
| restingHr | High | Nightly value within about 1 bpm of ECG; compare to your baseline, not to other people. |
| sleepDuration | Medium | Within about 30 min of lab sleep; wake inside the night is under-counted. |
| sleepTiming | Medium | Bed and wake times land within 10–15 min; auto-detection runs a little late. |
| sleepRegularity | High | Built on sleep/wake only, the part wearables get right; strongest health evidence of any sleep metric. |
| sleepStages | Low | Deep and REM misclassified 30–50% of the time; a visual, not a goal. |
| steps | Medium | Reliable as a self-consistent trend; strap placement and slow walking cost accuracy. |
| calories | Low | No consumer device within 20% of calorimetry; show relative to your average only. |
| vo2 | Low | Resting-based estimates overestimate; typical error 4–5 mL/kg/min; show a band and direction. |
| spo2 | Low | About 2–6% absolute error with missing readings; nightly deviation from baseline only. |
| skinTemp | Medium | Not core temperature; meaningful only as a multi-night deviation from baseline. |
| stress | Low | Daytime HRV scores track heart rate, not felt stress; no independent validation. |
| readiness | Low | No composite score has outcome validation; keep inputs visible and the number explainable. |
| effort | Medium | HR-zone load is good for running and cycling, poor for strength and wrist-flexion sports. |

## References

1. Bellenger CR, Miller DJ, Halson SL, Roach GD, Sargent C. Wrist-Based Photoplethysmography Assessment of Heart Rate and Heart Rate Variability: Validation of WHOOP. *Sensors* 2021;21(10):3571. doi:10.3390/s21103571
2. Miller DJ, Sargent C, Roach GD. A Validation of Six Wearable Devices for Estimating Sleep, Heart Rate and Heart Rate Variability in Healthy Adults. *Sensors* 2022;22(16):6317. doi:10.3390/s22166317
3. Dial MB, et al. Validation of nocturnal resting heart rate and heart rate variability in consumer wearables. *Physiological Reports* 2025;13:e70527. doi:10.14814/phy2.70527
4. Shcherbina A, Mattsson CM, Waggott D, et al. Accuracy in Wrist-Worn, Sensor-Based Measurements of Heart Rate and Energy Expenditure in a Diverse Cohort. *J Pers Med* 2017;7(2):3. doi:10.3390/jpm7020003
5. Khodr R, Kamal L, Minerbi A, Gupta G. Accuracy, Utility and Applicability of the WHOOP Wearable Monitoring Device in Health, Wellness and Performance – a systematic review. *medRxiv* 2024. doi:10.1101/2024.01.04.24300784 (preprint)
6. Miller DJ, Lastella M, Scanlan AT, Bellenger C, Halson SL, Roach GD, Sargent C. A validation study of the WHOOP strap against polysomnography to assess sleep. *J Sports Sci* 2020;38:2631–2636. doi:10.1080/02640414.2020.1797448
7. Chinoy ED, Cuellar JA, Huwa KE, et al. Performance of seven consumer sleep-tracking devices compared with polysomnography. *Sleep* 2021;44(5):zsaa291. doi:10.1093/sleep/zsaa291
8. Chinoy ED, Cuellar JA, Jameson JT, Markwald RR. Performance of Four Commercial Wearable Sleep-Tracking Devices Tested Under Unrestricted Conditions at Home in Healthy Young Adults. *Nat Sci Sleep* 2022;14:493–516. doi:10.2147/NSS.S348795
9. Stone JD, Rentz LE, Forsey J, et al. Evaluations of Commercial Sleep Technologies for Objective Monitoring During Routine Sleeping Conditions. *Nat Sci Sleep* 2020;12:821–842. doi:10.2147/NSS.S270705
10. Lee YJ, Lee JY, Cho JH, Kang YJ, Choi JH. Performance of consumer wrist-worn sleep tracking devices compared to polysomnography: a meta-analysis. *J Clin Sleep Med* 2025;21(3):573–582. doi:10.5664/jcsm.11460
11. Robbins R, et al. (35 adults, single-night inpatient PSG). Accuracy of Three Commercial Wearable Devices for Sleep Tracking in Healthy Adults. *Sensors* 2024;24(20):6532. doi:10.3390/s24206532
12. Phillips AJK, Clerx WM, O'Brien CS, et al. Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. *Sci Rep* 2017;7:3216. doi:10.1038/s41598-017-03171-4
13. Fischer D, Klerman EB, Phillips AJK. Measuring sleep regularity: theoretical properties and practical usage of existing metrics. *Sleep* 2021;44(10):zsab103. doi:10.1093/sleep/zsab103
14. Lunsford-Avery JR, Engelhard MM, Navar AM, Kollins SH. Validation of the Sleep Regularity Index in Older Adults and Associations with Cardiometabolic Risk. *Sci Rep* 2018;8:14158. doi:10.1038/s41598-018-32402-5
15. Windred DP, Burns AC, Lane JM, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration: a prospective cohort study. *Sleep* 2024;47(1):zsad253. doi:10.1093/sleep/zsad253
16. Lujan MR, Perez-Pozuelo I, Grandner MA. Past, Present, and Future of Multisensory Wearable Technology to Monitor Sleep and Circadian Rhythms. *Front Digit Health* 2021;3:721919. doi:10.3389/fdgth.2021.721919
17. Walch O, Huang Y, Forger D, Goldstein C. Sleep stage prediction with raw acceleration and photoplethysmography heart rate data derived from a consumer wearable device. *Sleep* 2019;42(12):zsz180. doi:10.1093/sleep/zsz180
18. Svensson T, Madhawa K, Hoang NT, Chung UI, Svensson AK. Validity and reliability of the Oura Ring Generation 3 (Gen3) with Oura sleep staging algorithm 2.0 (OSSA 2.0) when compared to multi-night ambulatory polysomnography. *Sleep Med* 2024;115:251–263. doi:10.1016/j.sleep.2024.01.020
19. Evenson KR, Goto MM, Furberg RD. Systematic review of the validity and reliability of consumer-wearable activity trackers. *Int J Behav Nutr Phys Act* 2015;12:159. doi:10.1186/s12966-015-0314-1
20. Fuller D, Colwell E, Low J, et al. Reliability and Validity of Commercially Available Wearable Devices for Measuring Steps, Energy Expenditure, and Heart Rate: Systematic Review. *JMIR mHealth uHealth* 2020;8(9):e18694. doi:10.2196/18694
21. Molina-Garcia P, Notbohm HL, Schumann M, et al. Validity of Estimating the Maximal Oxygen Consumption by Consumer Wearables: A Systematic Review with Meta-analysis and Expert Statement of the INTERLIVE Network. *Sports Med* 2022;52:1577–1597. doi:10.1007/s40279-021-01639-y
22. Caserman P, Yum S, Göbel S, Reif A, Matura S. Assessing the Accuracy of Smartwatch-Based Estimation of Maximum Oxygen Uptake Using the Apple Watch Series 7: Validation Study. *JMIR Biomed Eng* 2024;9:e59459. doi:10.2196/59459
23. Firstbeat Technologies. Automated Fitness Level (VO2max) Estimation with Heart Rate and Speed Data. White paper, 2014/2017. https://www.firstbeat.com/wp-content/uploads/2015/10/white_paper_VO2max_11-11-20142.pdf (vendor document)
24. WHOOP. How Accurate Is WHOOP VO2 Max? Inside the Algorithm. https://www.whoop.com/us/en/thelocker/how-accurate-is-whoop-vo2-max/ (vendor document)
25. Pipek LZ, Nascimento RFV, Acencio MMP, Teixeira LR. Comparison of SpO2 and heart rate values on Apple Watch and conventional commercial oximeters devices in patients with lung disease. *Sci Rep* 2021;11:18901. doi:10.1038/s41598-021-98453-3
26. Jiang Y, Spies C, Magin J, Bhosai SJ, Snyder L, Dunn J. Investigating the accuracy of blood oxygen saturation measurements in common consumer smartwatches. *PLOS Digit Health* 2023;2(7):e0000296. doi:10.1371/journal.pdig.0000296
27. Mason AE, Hecht FM, Davis SK, et al. Detection of COVID-19 using multimodal data from a wearable device: results from the first TemPredict Study. *Sci Rep* 2022;12:3463. doi:10.1038/s41598-022-07314-0
28. Kim HG, Cheon EJ, Bai DS, Lee YH, Koo BH. Stress and Heart Rate Variability: A Meta-Analysis and Review of the Literature. *Psychiatry Investig* 2018;15(3):235–245. doi:10.30773/pi.2017.08.17
29. Rosenbach H, Itzkovitch A, Gidron Y, Schonberg T. Assessing Stress Level Scores Against Wearables-Driven Physiological Measurements. *Stress and Health* 2025;41:e70125. doi:10.1002/smi.70125
30. Rosenbach H, et al. Assessing Garmin's Stress Level Score Against Heart Rate Variability Measurements. *bioRxiv* 2025. doi:10.1101/2025.01.06.630177 (preprint of [29])
31. Doherty C, Baldwin M, Lambe R, Burke D, Altini M. Readiness, recovery, and strain: an evaluation of composite health scores in consumer wearables. *Transl Exerc Biomed* 2025;2(2):128–144. doi:10.1515/teb-2025-0001
