# Baseline — App Store submission checklist

In order. Each step says where the answer or the file comes from. Tick them off in a copy; this file
stays the template.

## 0. Before anything

- [ ] **Trademark pass.** No WHOOP wordmark, logo or three-ring look anywhere a reviewer or customer
      sees except the one nominative sentence in the description and the Bluetooth usage string:
      app name, subtitle, keywords, icon, screenshots, promotional text, What's New, review notes
      beyond "compatible hardware". The marketing set deliberately leaves out Welcome's pairing step
      and Settings › Devices, whose buttons name the strap models. No "Strain", "Recovery", "Sleep
      Coach" in any copy (see the research report's trademark section and BASELINE.md's rules).
- [ ] **Licence.** Baseline is free, no purchases, no ads: the PolyForm Noncommercial terms on NOOP's
      engine permit distribution for non-commercial purposes only, and the App Store listing must stay
      free for as long as the engine is NOOP's. LICENSE, NOTICE and ATTRIBUTION.md ship in the bundle
      (resources of the Baseline target) and are readable under Settings › About.
- [ ] **Disclaimers are in the build.** Welcome's footnote, Settings › About › Disclaimer and the
      privacy policy all say not affiliated and not medical advice (`SettingsLegalText`).

## 1. Apple Developer account

- [ ] Developer Program membership active for team `25RC553RGP`.
- [ ] Latest **Apple Developer Program License Agreement** and the **Paid Applications Agreement are
      not needed** (free app), but App Store Connect still requires the current developer agreement
      accepted under Business › Agreements before a build can be uploaded.
- [ ] Account Holder's tax and banking screens left alone (free app).

## 2. Identifiers and capabilities (developer.apple.com › Certificates, Identifiers & Profiles)

- [ ] App ID `com.patrickschmidt.baseline` (explicit), capabilities:
  - [ ] **HealthKit** (with Background Delivery; entitlement `com.apple.developer.healthkit` and
        `…healthkit.background-delivery` in `Baseline/Resources/Baseline.entitlements`).
  - [ ] **App Groups**: `group.com.patrickschmidt.baseline` (`APP_GROUP_ID` in `project.yml`).
  - [ ] **Background Modes** need no App ID capability; they are the `UIBackgroundModes` in
        `Info.plist` (`bluetooth-central`, `fetch`, `processing`, and `location`; resolve the
        `location` question in ReviewNotes.md § Resolve before submitting).
- [ ] Xcode's automatic signing registered these on the first device run; confirm they show on the
      App ID and that the App Store provisioning profile Xcode generates includes HealthKit and the
      App Group. The UI-test bundle `com.patrickschmidt.baseline.uitests` needs no profile for the store.

## 3. App Store Connect record

- [ ] New app: platform iOS, name **Baseline** (fallbacks in `AppStore.md`), primary language English
      (U.K. or U.S., then keep every text in that one), bundle ID `com.patrickschmidt.baseline`, SKU
      `baseline-ios`.
- [ ] Category Health & Fitness, no secondary.
- [ ] Price: Free, all territories. No in-app purchases.
- [ ] App Privacy: **Data Not Collected**, no tracking (`PrivacyNutrition.md`). Publish the answers.
- [ ] Age rating questionnaire answered as in `AppStore.md` (expected 4+).
- [ ] Content rights: "does not contain, show or access third-party content".
- [ ] Export compliance: already answered in the binary, `ITSAppUsesNonExemptEncryption = false` in
      `Info.plist`, so App Store Connect will not park the build on Missing Compliance. If it asks
      anyway, answer "No" to non-exempt encryption (only Apple's CommonCrypto / TLS; see the comment in
      `project.yml`'s Baseline block).

## 4. Version and build

- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` › targets › Baseline (1.0 /
      1 for the first upload; the build number must rise on every upload).
- [ ] `xcodegen generate`, then **Product › Archive from the `Baseline` scheme in Release** on a
      Generic iOS Device (not a simulator), signing Automatic, team `25RC553RGP`.
- [ ] Validate in Organizer (catches the missing-profile and missing-icon classes of error), then
      Distribute › App Store Connect › Upload.
- [ ] Icon: `BaselineIcon` (1024 px, no alpha, from `Baseline/scripts/render-icon.swift`); no
      third-party mark, no text.

## 5. TestFlight

- [ ] Internal build to the account's own testers first: install on a real iPhone, pair a strap, run
      one night, confirm the Release build (no `--demo-seed`) shows real data, Apple Health write-back
      works, the morning summary arrives when turned on, and Settings › About opens every sheet and link.
- [ ] Check the Release build's empty states look as the review notes describe them on a fresh install
      (delete the app first).
- [ ] TestFlight's "What to Test" can be one line; external testing is optional (it adds a Beta App
      Review step).

## 6. Screenshots and text

- [ ] **6.9-inch (required)**: six framed PNGs at 1320 × 2868 from
      `MARKETING_SIM=1 Baseline/scripts/ui-shots.sh` followed by
      `swift Baseline/scripts/frame-shots.swift <shots>/marketing <shots>/marketing/framed`
      (BASELINE.md › Marketing screenshots). Order 01 Today, 02 Progress, 03 Trends, 04 Sleep,
      05 Journal, 06 Workouts. Captions are the ones in the script's table.
- [ ] **6.5-inch (optional)**: App Store Connect scales the 6.9-inch set down for older devices unless
      a separate set is uploaded; upload one only if the scaled set looks wrong. (`ui-shots.sh` on an
      iPhone 11 Pro Max / XS Max class simulator would give 1242 × 2688 captures; `frame-shots.swift`
      would need a second canvas size, which is not written.)
- [ ] No iPad screenshots: the target is iPhone-only (`TARGETED_DEVICE_FAMILY 1`).
- [ ] Look at every frame once at thumbnail size: status bar shows 9:41 and a full battery (the
      script's override), no strap maker's name on screen, seeded numbers plausible.
- [ ] Name, subtitle, promotional text, description, keywords, support URL, marketing URL from
      `AppStore.md`; paste the description as plain text.
- [ ] Copyright line from `AppStore.md`.

## 7. Privacy policy

- [ ] Privacy Policy URL live in a browser (not only on GitHub signed-in): the blob URL in
      `SettingsAboutCard.privacyURL` at minimum, a static page preferably (`AppStore.md` › URLs).
- [ ] The URL in App Store Connect, the URL in the app (`SettingsAboutCard.privacyURL`) and the text
      in the app (`SettingsLegalText.privacy`) all say the same thing as `Baseline/PRIVACY.md`.

## 8. App Review information

- [ ] Notes from `ReviewNotes.md` (the fenced block), contact name, phone and email.
- [ ] Sign-in not required; demo account fields empty.
- [ ] Attachment (optional, helps): a 30-second screen recording of the Release build on a real iPhone
      with a paired strap, so the reviewer sees what the empty states turn into.
- [ ] Release: manual ("Manually release this version"), so the listing can be checked once approved
      before it goes live.

## 9. After approval

- [ ] Check the live listing's search result next to "baseline: a better journal"; adjust the subtitle
      if the two blur together (subtitle changes need a new version; promotional text does not).
- [ ] Tag the commit the archive was built from (`baseline-1.0`), so the store build maps to the fork.
- [ ] If a rights-holder complaint ever arrives through Apple's channel (the research report's 5.2.1
      risk), the DISCLAIMER's good-faith contact section is the reply template; keep it current.
