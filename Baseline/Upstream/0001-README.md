# 0001 — defer `allowsBackgroundLocationUpdates` until a route records

Upstream PR against `ryanbr/noop`. The patch is `0001-defer-background-location-flag.patch`
(`git am`-able, one file: `Strand/App/GpsWorkoutRecorder.swift`, +26/−7).

## PR title

`ios: arm allowsBackgroundLocationUpdates only while a route records`

## PR body

**Problem.** `GpsWorkoutRecorder.init` sets `manager.allowsBackgroundLocationUpdates = true`.
CoreLocation asserts (`!stayUp || CLClientIsBackgroundable`) the moment that property is set to
`true` in a process whose `Info.plist` does not declare the `location` `UIBackgroundMode`.
`AppModel` constructs the recorder unconditionally at launch, so any host that embeds the engine
without that background mode crashes before its first screen, even if it never records a route.
NOOPiOS itself is unaffected because `project.yml` declares the mode.

**Fix.** The flag is now armed in `beginUpdates()`, which only runs once a workout with a route
has started and location is authorised, and cleared in a new `endUpdates()` that every stop path
goes through (`stop`, `pause`, a `restore` into the paused state, a mid-session permission revoke
in `locationManagerDidChangeAuthorization`). On NOOPiOS the behaviour is the same background
capture as before; the flag is simply true for exactly the span updates stream, instead of for
the process lifetime. `pausesLocationUpdatesAutomatically` and `activityType` stay in `init`
(they do not trap). No Android change: the Android recorder uses a foreground service, there is
no equivalent flag.

**How tested.** Fill in before opening:
- [ ] `xcodegen generate && xcodebuild test -scheme Strand -destination 'platform=macOS'`
      (`StrandTests`; the macOS leg CI runs) — green.
- [ ] `NOOPiOS` compiles (`xcodebuild -scheme NOOPiOS -destination 'generic/platform=iOS Simulator' build`).
- [ ] On a NOOPiOS build: start a GPS workout, lock the screen for a few minutes, the route keeps
      accruing (`isRecording`/`pointCount` on the active-workout card), end it, the route saves.
- [ ] On a host without the `location` background mode (Baseline): launches, no CoreLocation assert.

Refs: the `!stayUp || CLClientIsBackgroundable` crash reproduces on any iOS target that compiles
`GpsWorkoutRecorder` without the `location` background mode. (Use `Refs #N` if an upstream issue
exists; do not use closing keywords, per AGENTS.md.)

## Commands (from this fork, `origin` = PSchmidt23/noop, `upstream` = ryanbr/noop)

```sh
cd /Users/patrickschmidt/Documents/Noop.health/baseline
git fetch upstream
git worktree add ../noop-pr-0001 upstream/main          # keep the Baseline tree untouched
cd ../noop-pr-0001
git switch -c ios/defer-background-location-flag
git am /Users/patrickschmidt/Documents/Noop.health/baseline/Baseline/Upstream/0001-defer-background-location-flag.patch
xcodegen generate && xcodebuild test -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
git push -u origin ios/defer-background-location-flag
gh pr create --repo ryanbr/noop --base main --head PSchmidt23:ios/defer-background-location-flag \
  --title "ios: arm allowsBackgroundLocationUpdates only while a route records" --body-file - <<'BODY'
<paste the PR body above, with the test checklist filled in>
BODY
cd .. && git worktree remove noop-pr-0001                 # after the PR is open
```

Re-check applicability against a newer upstream with
`git -C ../noop-pr-0001 apply --check <patch>` (the patch was generated against upstream/main
`7f396e98`, 2026-09-30).

## Baseline note

Until this lands upstream, Baseline keeps `location` in its `UIBackgroundModes` (`project.yml`, the
Baseline target; see BASELINE.md around line 190) purely so `GpsWorkoutRecorder.init` does not trap,
even though no Baseline screen records a route. Once merged, `git merge upstream/main` picks the fix
up and that mode (plus its App Store review explanation in `Baseline/Store/ReviewNotes.md`) can go.
