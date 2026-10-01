#!/bin/zsh
# Runs the Baseline UI screenshot suite with a clean, fixed status bar (9:41, charged, full bars).
#
#   Baseline/scripts/ui-shots.sh [shots dir]                 # whole BaselineUITests suite on the Baseline iPhone
#   ONLY=ScreenshotTests/testTrends Baseline/scripts/ui-shots.sh   # one test (anything after -only-testing:BaselineUITests/)
#   MARKETING_SIM=1 Baseline/scripts/ui-shots.sh [shots dir] # only MarketingShots/testMarketingSet, on a 6.9-inch
#                                                             # "Baseline Marketing" simulator (created if missing)
#
# Steps: (1) boot the simulator, (2) `simctl status_bar override`, (3) `xcodebuild test` with
# TEST_RUNNER_BASELINE_SHOTS_DIR, (4) clear the override, (5) shut the simulator down. The override is cleared
# and the simulator shut down even when the suite fails. XCUITest cannot call simctl from inside the
# simulator, which is why the override lives here and not in the test's setUp.
#
# The script touches only two simulators, ever: $SIM_UDID (default: the Baseline iPhone) and, with
# MARKETING_SIM set, the one named "Baseline Marketing" that it creates itself. It never boots, erases or
# deletes anything else. It does not run xcodegen; regenerate the project first (Baseline/scripts/build.sh)
# when project.yml changed.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHOTS="${1:-/private/tmp/baseline-shots}"
SIM_UDID="${SIM_UDID:-149DD9EE-8D7D-4CC2-B5E8-07DBA768C046}"
DD="${DERIVED_DATA:-$ROOT/.build-baseline}"
MARKETING_NAME="Baseline Marketing"
MARKETING_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
ONLY="${ONLY:-}"
cd "$ROOT"

log() { print -u2 -- "ui-shots: $*"; }

# --- Which simulator ----------------------------------------------------------------------------------------

UDID="$SIM_UDID"
CREATED=""
if [[ -n "${MARKETING_SIM:-}" ]]; then
  # Newest available iOS runtime (simctl prints them oldest first; sort by version to be safe).
  RUNTIME="$(xcrun simctl list runtimes available | awk '/^iOS /{print $2, $NF}' | sort -V | tail -1 | awk '{print $2}')"
  [[ -z "$RUNTIME" ]] && { log "no iOS runtime available"; exit 1; }
  # Reuse an existing "Baseline Marketing" of the right device type; create it otherwise.
  UDID="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name, dtype = sys.argv[1], sys.argv[2]
for runtime, devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d.get("name") == name and d.get("deviceTypeIdentifier") == dtype and d.get("isAvailable", True):
            print(d["udid"]); sys.exit(0)
' "$MARKETING_NAME" "$MARKETING_TYPE")"
  if [[ -z "$UDID" ]]; then
    UDID="$(xcrun simctl create "$MARKETING_NAME" "$MARKETING_TYPE" "$RUNTIME")" || { log "simctl create failed"; exit 1; }
    CREATED="$UDID"
    log "created \"$MARKETING_NAME\" ($UDID) on $RUNTIME"
  else
    log "using \"$MARKETING_NAME\" ($UDID)"
  fi
  ONLY="MarketingShots/testMarketingSet"
fi

# --- Boot + status bar ---------------------------------------------------------------------------------------

cleanup() {
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  log "status bar cleared, $UDID shut down"
}
trap cleanup EXIT INT TERM

STATE="$(xcrun simctl list devices -j | python3 -c '
import json, sys
u = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["udid"] == u: print(d["state"]); sys.exit(0)
print("Missing")' "$UDID")"
[[ "$STATE" == "Missing" ]] && { log "simulator $UDID not found"; exit 1; }
if [[ "$STATE" != "Booted" ]]; then
  xcrun simctl boot "$UDID" || { log "boot failed"; exit 1; }
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
# Baseline is light-only (`.preferredColorScheme(.light)`); the system sheets and alerts it presents
# follow the simulator's appearance, so pin it to light for the captures.
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || log "could not set light appearance on $UDID"

xcrun simctl status_bar "$UDID" override \
  --time 9:41 \
  --batteryState charged --batteryLevel 100 \
  --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --dataNetwork wifi \
  --operatorName '' \
  || { log "status_bar override failed"; exit 1; }
log "status bar: 9:41, charged, full bars on $UDID"

# --- Test ----------------------------------------------------------------------------------------------------

mkdir -p "$SHOTS"
ONLY_ARG="-only-testing:BaselineUITests"
[[ -n "$ONLY" ]] && ONLY_ARG="-only-testing:BaselineUITests/$ONLY"
log "shots → $SHOTS  ($ONLY_ARG)"

TEST_RUNNER_BASELINE_SHOTS_DIR="$SHOTS" xcodebuild -project Strand.xcodeproj -scheme Baseline \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  "$ONLY_ARG" test 2>&1 \
  | grep -E "error:|Test Case .* (passed|failed)|marketing:|\*\* TEST .*\*\*" | sort -u
STATUS=${pipestatus[1]}

if [[ -n "${MARKETING_SIM:-}" ]]; then
  log "marketing frames in $SHOTS/marketing; frame them with: swift Baseline/scripts/frame-shots.swift $SHOTS/marketing $SHOTS/marketing/framed"
fi
[[ -n "$CREATED" ]] && log "\"$MARKETING_NAME\" was created and kept; delete it with: xcrun simctl delete $CREATED"
exit $STATUS
