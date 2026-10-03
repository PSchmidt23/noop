#!/bin/zsh
# Non-interactive pre-TestFlight check for Baseline: regenerates the project, builds the Release
# configuration for a real iPhone (generic/platform=iOS, code signing off, so no provisioning is
# touched) and inspects the produced bundle. Prints one PASS/FAIL/WARN line per check, exits 1 on any
# FAIL (a WARN is printed and counted but never fails the run).
# Usage: Baseline/scripts/release-check.sh [derivedDataPath]
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DD="${1:-$ROOT/.build-baseline-release}"
LOG="$DD/release-check.log"
cd "$ROOT"
mkdir -p "$DD"
FAILS=0
WARNS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
warn() { echo "WARN  $1"; WARNS=$((WARNS + 1)); }
check() { # check <description> <command...>: PASS when the command exits 0
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
jwt_role() { # jwt_role <token>: the payload's "role" claim, or nothing when the token is not a 3-part JWT
  [ "$(printf '%s' "$1" | awk -F. '{print NF}')" = "3" ] || return 0
  local p="${1#*.}"; p="${p%%.*}"
  p=$(printf '%s' "$p" | tr '_-' '/+')
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
  printf '%s' "$p" | base64 -D 2>/dev/null | sed -n 's/.*"role"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# 1. Project + Release device build -----------------------------------------------------------
if xcodegen generate >/dev/null 2>&1; then pass "xcodegen generate"; else fail "xcodegen generate"; fi
# XcodeGen rewrites NOOP's plist on every run; keep the upstream file untouched.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git checkout -- StrandiOS/Resources/Info.plist 2>/dev/null

# `clean build`: the embedded PlugIns/BaselineWidgets.appex is a copy made by the app target's embed
# phase, and an incremental build can leave it stale (a resource added to the extension showed up in
# the standalone .appex but not in the embedded one). A release check must look at a fresh bundle.
xcodebuild -project Strand.xcodeproj -scheme Baseline -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO clean build >"$LOG" 2>&1
if grep -q "BUILD SUCCEEDED" "$LOG"; then
  pass "Release build (generic iOS device, arm64)"
else
  fail "Release build (generic iOS device, arm64) — see $LOG"
  grep -E "error:" "$LOG" | sort -u | head -20
fi
WARN=$(grep -E "warning: .*Baseline" "$LOG" | sort -u | wc -l | tr -d ' ')
[ "$WARN" = "0" ] && pass "no compiler warnings in Baseline/ or BaselineWidgets/" \
                   || { fail "$WARN compiler warning(s) in Baseline/ or BaselineWidgets/"; grep -E "warning: .*Baseline" "$LOG" | sort -u | head -10; }

# 2. Bundle contents ---------------------------------------------------------------------------
APP="$DD/Build/Products/Release-iphoneos/Baseline.app"
if [ ! -d "$APP" ]; then
  fail "bundle present at $APP"
  echo "$FAILS check(s) failed"; exit 1
fi
PLIST="$APP/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

check "widget extension embedded (PlugIns/BaselineWidgets.appex)" test -d "$APP/PlugIns/BaselineWidgets.appex"
check "app binary is arm64" sh -c "lipo -info '$APP/Baseline' | grep -q arm64"
[ "$(plist CFBundleIdentifier)" = "com.patrickschmidt.baseline" ] && pass "CFBundleIdentifier com.patrickschmidt.baseline" || fail "CFBundleIdentifier is '$(plist CFBundleIdentifier)'"
[ "$(plist CFBundleShortVersionString)" = "1.0" ] && pass "CFBundleShortVersionString 1.0" || fail "CFBundleShortVersionString is '$(plist CFBundleShortVersionString)'"
WV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/PlugIns/BaselineWidgets.appex/Info.plist" 2>/dev/null)
[ "$WV" = "$(plist CFBundleShortVersionString)" ] && pass "widget version matches the app ($WV)" || fail "widget version '$WV' differs from the app"
[ "$(plist ITSAppUsesNonExemptEncryption)" = "false" ] && pass "ITSAppUsesNonExemptEncryption false" || fail "ITSAppUsesNonExemptEncryption is '$(plist ITSAppUsesNonExemptEncryption)'"
[ "$(plist UILaunchScreen:UIColorName)" = "LaunchBackground" ] && pass "UILaunchScreen uses LaunchBackground" || fail "UILaunchScreen color is '$(plist UILaunchScreen:UIColorName)'"
[ "$(plist AppGroupIdentifier)" = "group.com.patrickschmidt.baseline" ] && pass "AppGroupIdentifier group.com.patrickschmidt.baseline" || fail "AppGroupIdentifier is '$(plist AppGroupIdentifier)'"
check "URL scheme 'baseline' registered" sh -c "plutil -p '$PLIST' | grep -q '\"baseline\"'"
if plutil -p "$PLIST" | grep -qiE "noop|strand|coach|oura"; then
  fail "Info.plist carries NOOP-only keys/values:"; plutil -p "$PLIST" | grep -iE "noop|strand|coach|oura" | head -5
else
  pass "no NOOP-only keys in Info.plist"
fi

for f in PrivacyInfo.xcprivacy LICENSE NOTICE ATTRIBUTION.md Assets.car BaselineIcon60x60@2x.png; do
  check "bundle has $f" test -f "$APP/$f"
done
check "widget has PrivacyInfo.xcprivacy" test -f "$APP/PlugIns/BaselineWidgets.appex/PrivacyInfo.xcprivacy"
check "launch colour LaunchBackground compiled into Assets.car" sh -c "xcrun --sdk iphoneos assetutil --info '$APP/Assets.car' | grep -q LaunchBackground"

# Repo documents and scripts must never ship. ATTRIBUTION.md is the one Markdown file allowed.
STRAY=$(cd "$APP" && find . -maxdepth 1 \( -name "*.md" -o -name "*.sh" -o -name "*.swift" -o -name "*.patch" -o -name "*.yml" \) ! -name "ATTRIBUTION.md" | sed 's|^\./||')
[ -d "$APP/Store" ] && STRAY="$STRAY Store/"
[ -d "$APP/scripts" ] && STRAY="$STRAY scripts/"
[ -d "$APP/Research" ] && STRAY="$STRAY Research/"
[ -z "${STRAY// /}" ] && pass "no repo documents in the bundle (Store/, Research/, ENGINE_MAP.md, PRIVACY.md, DESIGN.md, scripts, patches)" \
                       || fail "repo documents leaked into the bundle: $(echo $STRAY | tr '\n' ' ')"

# Friends server (FRIENDS_SPEC.md §7.4, D13). Baseline/Backend/ (schema, Edge Function, tests, the example
# plist, SETUP.md) is excluded in project.yml and must never ship. The real config, Resources/Supabase.plist,
# IS bundled when present; FriendsConfig.isClientSafe refuses an unsafe key at runtime, but the file would still
# be in the IPA, so the same rule runs here on the bundled copy.
LEAK=$(cd "$APP" && find . \( -name Backend -o -name supabase -o -name "*.sql" -o -name Supabase.example.plist \
         -o -name config.toml -o -name delete-account -o -name SETUP.md \) | sed 's|^\./||' | tr '\n' ' ')
[ -z "${LEAK// /}" ] && pass "no Friends server files in the bundle (Backend/, *.sql, Supabase.example.plist, SETUP.md)" \
                     || fail "Friends server files leaked into the bundle: $LEAK"
check "Baseline/Backend/ is not bundled (no Backend/ directory in the app)" test ! -e "$APP/Backend"
# The client config ships only when the owner has put it in Baseline/Resources (git-ignored there). A
# bundled copy with no local file means a stale build product or a file that came from somewhere else.
# FriendsConfig.plist is the brief's older name for the same file; neither may appear unless present locally.
for CFG in Supabase.plist FriendsConfig.plist; do
  if [ -f "$APP/$CFG" ] && [ ! -f "$ROOT/Baseline/Resources/$CFG" ]; then
    fail "$CFG is in the bundle but not in Baseline/Resources (stale or foreign config)"
  elif [ -f "$APP/$CFG" ]; then
    pass "$CFG bundled from Baseline/Resources/$CFG (present locally, git-ignored)"
  elif [ -f "$ROOT/Baseline/Resources/$CFG" ] && [ "$CFG" = "Supabase.plist" ]; then
    fail "Baseline/Resources/Supabase.plist exists locally but is missing from the bundle"
  else
    pass "$CFG not in the bundle (not present locally)"
  fi
done
if git -C "$ROOT" ls-files --error-unmatch Baseline/Resources/Supabase.plist Baseline/Resources/FriendsConfig.plist >/dev/null 2>&1; then
  fail "a Friends client config (Supabase.plist / FriendsConfig.plist) is tracked by git"
else
  pass "no Friends client config tracked by git (only Backend/supabase/Supabase.example.plist)"
fi
SR=$(grep -rlF service_role "$APP" 2>/dev/null | sed "s|^$APP/||" | tr '\n' ' ')
[ -z "${SR// /}" ] && pass "no 'service_role' string anywhere in the bundle" \
                   || fail "'service_role' found in the bundle: $SR"
SBP="$APP/Supabase.plist"
if [ -f "$SBP" ]; then
  SBKEY=$(/usr/libexec/PlistBuddy -c "Print :SUPABASE_ANON_KEY" "$SBP" 2>/dev/null | tr -d '[:space:]')
  SBURL=$(/usr/libexec/PlistBuddy -c "Print :SUPABASE_URL" "$SBP" 2>/dev/null | tr -d '[:space:]')
  case "$SBKEY" in
    sb_secret_*)      fail "Supabase.plist holds an sb_secret_ key; only the anon or sb_publishable_ key may ship" ;;
    sb_publishable_*) pass "Supabase.plist key is a publishable key" ;;
    "")               fail "Supabase.plist has no SUPABASE_ANON_KEY" ;;
    *PASTE_*)         warn "Supabase.plist still holds the placeholder key: Friends offers only the demo preview" ;;
    *)
      ROLE=$(jwt_role "$SBKEY")
      if [ "$ROLE" = "anon" ]; then
        pass "Supabase.plist key is an anon JWT"
      else
        fail "Supabase.plist key is not client-safe (JWT role '${ROLE:-none}'); only the anon or sb_publishable_ key may ship"
      fi ;;
  esac
  case "$SBURL" in
    *YOUR-PROJECT*) warn "Supabase.plist still holds the placeholder URL: Friends offers only the demo preview" ;;
    https://*)      pass "Supabase.plist URL is https" ;;
    *)              warn "Supabase.plist URL '$SBURL' is not https: the app treats the file as missing" ;;
  esac
else
  warn "no Supabase.plist in the Release bundle: Friends offers only \"Preview with demo friends\" (fine for a build without the server)"
fi

# 3. Entitlements -----------------------------------------------------------------------------
# With CODE_SIGNING_ALLOWED=NO Xcode writes no .xcent for the device build, so the source files are
# checked, plus the resolved APP_GROUP_ID the build used.
ENT="$ROOT/Baseline/Resources/Baseline.entitlements"
WENT="$ROOT/BaselineWidgets/BaselineWidgets.entitlements"
check "app entitlements: HealthKit" sh -c "/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.healthkit' '$ENT' | grep -q true"
check "app entitlements: HealthKit background delivery" sh -c "/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.healthkit.background-delivery' '$ENT' | grep -q true"
check "app entitlements: App Group" sh -c "/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' '$ENT' | grep -q APP_GROUP_ID"
check "widget entitlements: App Group" sh -c "/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' '$WENT' | grep -q APP_GROUP_ID"
check "app entitlements: Sign in with Apple (com.apple.developer.applesignin = Default)" \
  sh -c "/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.applesignin:0' '$ENT' | grep -qx Default"
check "project.yml Baseline block carries the Sign in with Apple entitlement" \
  sh -c "grep -q 'com.apple.developer.applesignin' '$ROOT/project.yml'"
# Sign in with Apple means the Friends tab can upload, so the shipped privacy manifest must declare what it
# collects (Health, Fitness, Name, UserID; Store/PrivacyNutrition.md). The entitlement with an empty list is a
# false App Store label.
if /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.applesignin' "$ENT" >/dev/null 2>&1; then
  COLLECTED=$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$APP/PrivacyInfo.xcprivacy" 2>/dev/null)
  if [ -z "$COLLECTED" ] || [ "$COLLECTED" = "[]" ]; then
    fail "Sign in with Apple entitlement, but the bundled PrivacyInfo.xcprivacy declares no collected data types"
  else
    MISSING=""
    for t in Health Fitness Name UserID; do
      printf '%s' "$COLLECTED" | grep -q "\"NSPrivacyCollectedDataType$t\"" || MISSING="$MISSING $t"
    done
    [ -z "$MISSING" ] && pass "Sign in with Apple entitlement; manifest declares Health, Fitness, Name, UserID" \
                      || fail "Sign in with Apple entitlement; manifest is missing collected type(s):$MISSING"
  fi
fi
GROUP=$(xcodebuild -project Strand.xcodeproj -scheme Baseline -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ APP_GROUP_ID =/ {print $2; exit}')
[ "$GROUP" = "group.com.patrickschmidt.baseline" ] && pass "APP_GROUP_ID resolves to group.com.patrickschmidt.baseline" || fail "APP_GROUP_ID resolves to '$GROUP'"
XCENT=$(find "$DD/Build/Intermediates.noindex" -name "Baseline.app-Simulated.xcent" 2>/dev/null | head -1)
if [ -n "$XCENT" ]; then
  check "simulator .xcent lists HealthKit + App Group (from an earlier simulator Release build)" \
    sh -c "plutil -p '$XCENT' | grep -q healthkit && plutil -p '$XCENT' | grep -q group.com.patrickschmidt.baseline"
fi

echo
[ $WARNS -gt 0 ] && echo "$WARNS warning(s)"
if [ $FAILS -eq 0 ]; then echo "ALL CHECKS PASSED  ($APP)"; exit 0; else echo "$FAILS check(s) FAILED"; exit 1; fi
