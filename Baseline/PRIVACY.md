# Baseline privacy policy

*Effective 2 October 2026. Also shown in the app under Settings › About.*

Baseline is a free iPhone app for WHOOP 4.0, 5.0 and MG straps, made by Patrick Schmidt as a
personal, non-commercial project on NOOP's open-source engine.

## Local first; Friends is optional

Everything in Baseline works without an account, and nothing you do in Home, Trends, Sleep or the
journal is sent anywhere. The one exception is **Friends**, an optional tab. Only if you
sign in to it with Apple and turn a metric on does Baseline send that metric, in a reduced form, to
Baseline's server so friends you accept can see it. Every metric is off until you turn it on.

## What stays on your iPhone

Baseline stores what it reads from your strap over Bluetooth (heart rate, R-R intervals, battery and
sensor records), the numbers it computes from that (HRV, resting heart rate, readiness, sleep and
effort), your journal, your profile and any WHOOP or Apple Health export you choose to import. All of it lives in the app's own storage on your iPhone,
protected by iOS, and is included in your normal iPhone backups. The developer never sees it.

## Apple Health

Only if you allow it, Baseline reads sleep, workouts, steps and heart data from Apple Health and
writes back the metrics it computes. That exchange happens on your iPhone. Baseline never sends Apple
Health data anywhere, with one exception you control: if you share Steps in Friends and your iPhone
counted the day's steps, that daily total is sent, marked "iPhone". Apple Health data is never used
for advertising or marketing and never sold. You can change or withdraw access at any time in the
Health app under your profile › Apps › Baseline.

## Bluetooth

Baseline talks only to a strap you own, directly over Bluetooth. It does not contact WHOOP's servers
or your WHOOP account.

## Friends (optional)

**Signing in.** Friends uses Sign in with Apple. Baseline asks Apple for no name and no email; Apple
shares only an identifier unique to Baseline's developer, and the server gives you a user ID. You then type a
display name (2 to 24 characters; the only thing about you friends see besides what you share) and
confirm you are 16 or older. Your daily step goal and weekly intensity goal are stored with it, so
friends and competitions can score against your own goal.

**What is sent, and only what you turn on.** Each metric is Off, Only in competitions, or Friends;
Off is the default. When you turn one on, you agree to it on that screen.

- Steps: your daily step count and whether the strap or iPhone counted it.
- Intensity minutes: your daily minutes, counted against your own heart rate.
- Active days: whether a day had 20+ intensity minutes or a 20-minute workout.
- Nights at sleep goal: whether a night reached your own sleep goal; never hours or times.
- On-time bedtimes: whether bedtime was within 30 minutes of your target; never the time.
- HRV trend: weekly HRV change against your own baseline, for example +8 %; never your HRV.
- Resting HR trend: weekly change against your own baseline, for example −2 bpm; never your heart rate.
- Readiness trend: this week against your month, for example +4; never your score.

**Never sent:** heart rate, R-R intervals, your HRV, resting heart rate or readiness values, sleep
hours, stages or clock times, calories, stress, effort, workouts, the journal, location, your email,
contacts or photos. Friends has no chat and no free text.

**Why.** Only to show what you chose to the friends you accept, or only inside competitions you join,
and to score those competitions. For health data, the legal basis is your explicit consent (EU GDPR
Art. 9(2)(a)), given per metric and never pre-ticked; for your account (user ID, name, goals), it is
providing the Friends service you asked for (Art. 6(1)(b)).

**Where.** Baseline's server runs on Supabase (Supabase, Inc.) in its Frankfurt, EU region. Supabase
processes it for Baseline under its data processing agreement, which covers any access from outside
the EU with the EU Standard Contractual Clauses. Everything travels over HTTPS. Your sign-in session is
kept in your iPhone's Keychain, on this device only, never in iCloud.

**Who sees it.** Friends you accept see your name, your goals and what you share with Friends, except
friends you hide your data from (they are not told). A pending friend request shows your name. People in a competition you join see your name and
your score in that competition only. Someone holding an invite code you made sees your name before
connecting. HRV, resting HR and readiness are only ever shown as your change against your own baseline,
listed alphabetically, never ranked and never in a competition. The developer can open the server's
tables to run Friends and act on reports, and does so only for that. Nothing is sold or shared with
anyone else.

**How long it is kept.**

- Daily values: 35 days.
- HRV, resting HR and readiness trends: the current week plus 4 previous weeks.
- Invite codes: 7 days (deleted a day after they expire).
- Competitions and their results: 90 days after the competition ends.
- Reports: 12 months.
- Accounts not used for 13 months are deleted with everything in them.
- The record of what you agreed to and withdrew: until you delete your account.
- Supabase's API logs record the IP address of each request and keep it only for the hosting plan's
  short log window (days, not months). Baseline does not use it.

**Withdrawing.** Turn any metric Off in Settings › Friends & sharing: its values are deleted from the
server at once, and friends and competitions stop seeing it. Signing out stops uploads; friends keep
seeing what you last shared until it ages out after 35 days or you stop sharing.

**Seeing and exporting your data.** Settings › Friends & sharing › "See what's on the server" shows
everything the server holds for you, as stored, and exports it as JSON.

**Deleting your account.** Settings › Friends & sharing › "Delete account and shared data" deletes
your account and every row about you on the server at once, and revokes Baseline's Sign in with Apple
when Apple allows it (otherwise the app tells you how: iPhone Settings › your name › Sign in with
Apple › Baseline › Stop Using). Deleting the app does not delete your Friends account; delete the account first.

**Reports and blocking.** Every friend can be reported or blocked. A report sends the developer only a
fixed reason (name, cheating, harassment or other), never text you write. Reports are reviewed at
least weekly; the developer may block or delete a profile. Blocking removes the friendship both ways.

**Age.** Friends is for people 16 and older.

**The demo preview.** "Preview with demo friends", sample data and the screenshots use made-up friends
on your iPhone and send nothing.

## No analytics, ads or tracking

Baseline contains no analytics, crash reporting, advertising, tracking or other telemetry. Its only
network connections are Friends' requests to Baseline's server, and only after you sign in to Friends.
It asks only for Bluetooth and, if you choose, Apple Health; it does not ask for your location, motion
data, microphone or camera.

## Deleting your data

Delete the app and everything it stored on your iPhone is gone. Metrics written to Apple Health stay
there until you remove them in the Health app. A paired strap can be forgotten under Settings ›
Devices. If you used Friends, delete your account in Settings › Friends & sharing before deleting the
app: the account and what you shared stay on the server otherwise (until they age out as above), and
iOS may keep the sign-in session in the Keychain.

## Your rights

Wherever you live, you can see, export, correct (your name, in Settings › Friends & sharing) and
delete what the server holds about you, and withdraw any consent, all in the app. If EU or UK data
protection law applies to you, you also have the rights to object and to restrict processing, and you
can complain to the data protection authority where you live or work. For anything else, write to the
contact below.

## Record of processing and risk assessment (outline)

- Controller: Patrick Schmidt (contact below). Processor: Supabase, Inc. (DPA signed; EU region
  Frankfurt).
- Purpose: showing chosen activity and trend values to accepted friends and scoring friendly
  competitions. No other purpose; no profiling, advertising or sale.
- People: Baseline users 16 and older who sign in to Friends.
- Data: user ID, display name, goals, the per-metric values listed above, friendships, hides, blocks,
  invites, competitions and results, reports, the consent record, API IP logs.
- Retention: as listed above, enforced by a daily server job and on every upload.
- Risks and measures: health data (Art. 9) is reduced before it leaves the phone (daily counts, 0/1
  nights, clipped weekly changes against the person's own baseline) and is off by default, per metric,
  with explicit consent and withdrawal that deletes. Comparing bodies is avoided: physiology is never
  ranked or in a competition. Wrong-audience exposure is limited by one server-side visibility rule on
  every health table and writes only through checked server functions. Account misuse: Sign in with
  Apple only, sessions on this device only, no secret key in the app. Social harm: no free text, 16+,
  report and block on every friend, a name filter.

## Changes

If what Baseline stores or sends changes, this policy changes with it. The current version is always
in the app and at the page linked from Settings › About.

## Contact

Patrick Schmidt, paddyr.schmidt@gmail.com (also for reports and data requests)

## About Baseline

Baseline is not affiliated with, endorsed by or connected to WHOOP, Inc.; "WHOOP" only names the
hardware it works with. Baseline is not a medical device and nothing it shows is medical advice: every
number is an estimate from published methods. Talk to a professional about health decisions.
