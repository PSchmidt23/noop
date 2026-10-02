# 0002 — opt-in "computed wins" precedence in `Repository.mergeDaily`

Upstream PR against `ryanbr/noop`. The patch is `0002-source-precedence-option.patch`
(`git am`-able: `Strand/Data/Repository.swift` +21/−2, new `StrandTests/ComputedWinsMergeTests.swift`).

## PR title

`repository: opt-in computed-wins precedence for overlapping daily rows`

## PR body

**Problem.** `Repository.mergeDaily` lets an imported WHOOP/Apple row win field by field over the
on-device computed row for the same day; the computed row only fills the import's nil fields.
That is the right default when the user's history is an export. But a strap worn continuously
alongside a one-off import stops reporting its own nights for every day the import also covers,
and there is no way to prefer the strap short of deleting the import.

**Fix.** `mergeDaily(imported:computed:userEditedDays:computedWins:)` gains `computedWins: Bool = false`.
- `false` (default): byte-for-byte the existing merge; `EditMergePrecedenceTests` and the new
  default-path test guard it.
- `true`: on an overlapping day the computed row wins field by field and the import fills only
  its nil fields. Days covered by one source only are returned as-is either way. The H5 (#509)
  edited-night rule still applies on top (an edited day keeps the computed sleep fields, including
  a deleted night's nil).
- `refresh()` reads the flag once, on the actor, from a new UserDefaults key
  `Repository.computedWinsDailyMergeDefaultsKey` (`"daily.computedWinsMerge"`) and hands the
  detached merge a plain `Bool`. No shipped UI sets the key, so nothing changes for NOOP users;
  a host (or a later Settings toggle) can opt in without forking the merge.
- `sourceRows` / `vitalRows` are untouched: the per-source rows already let a consumer resolve
  precedence itself, this only changes the merged `days` table.

**Shape note for the maintainer.** This is deliberately the smallest cut: one `Bool` on the pure
function plus one key. If NOOP would rather expose it as a `DailyMergePrecedence` enum
(`importsWin` / `computedWins` / per-field), a Settings → Data toggle, or extend `mergeSleep`
the same way, that is fine; the test file is written so the enum variant is a one-line change.
It is also reasonable to decline it. Baseline keeps its own `BaselineDays` funnel
(strap-first / merged / imports-only over `vitalRows`) regardless of what happens here, so this
PR is offered because the default-off hook is small and keeps the two code paths from drifting.

**How tested.** Fill in before opening:
- [ ] `xcodegen generate && xcodebuild test -scheme Strand -destination 'platform=macOS'`:
      `ComputedWinsMergeTests` (4 cases) and `EditMergePrecedenceTests` green (already run once on 2026-10-01 against upstream `7f396e98`: 10/10 passed).
- [ ] `NOOPiOS` compiles (shared file).
- [ ] Manual: with an imported WHOOP export overlapping strap nights,
      `defaults write <bundle id> daily.computedWinsMerge -bool true`, relaunch, the overlapping days
      show the strap's HRV/RHR/sleep; `-bool false` restores the import's values.

No Android twin in this PR: the Kotlin `mergeDaily` equivalent would take the same flag; say so
in the PR and offer to follow up if the maintainer wants the shape.

## Commands

```sh
cd /Users/patrickschmidt/Documents/Noop.health/baseline
git fetch upstream
git worktree add ../noop-pr-0002 upstream/main
cd ../noop-pr-0002
git switch -c repository/computed-wins-precedence
git am /Users/patrickschmidt/Documents/Noop.health/baseline/Baseline/Upstream/0002-source-precedence-option.patch
xcodegen generate && xcodebuild test -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:StrandTests/ComputedWinsMergeTests -only-testing:StrandTests/EditMergePrecedenceTests
git push -u origin repository/computed-wins-precedence
gh pr create --repo ryanbr/noop --base main --head PSchmidt23:repository/computed-wins-precedence \
  --title "repository: opt-in computed-wins precedence for overlapping daily rows" --body-file - <<'BODY'
<paste the PR body above, with the test checklist filled in>
BODY
cd .. && git worktree remove noop-pr-0002
```

The two patches are independent (disjoint files); open them as two PRs ("one concern per PR").
Generated against upstream/main `7f396e98` (2026-09-30).
