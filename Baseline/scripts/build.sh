#!/bin/zsh
# Regenerate the Xcode project (serialized via a lock) and build the Baseline scheme for the simulator.
# Usage: Baseline/scripts/build.sh [derivedDataPath]
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DD="${1:-$ROOT/.build-baseline}"
LOCK="/tmp/baseline-xcodegen.lock"
cd "$ROOT"
for i in {1..120}; do mkdir "$LOCK" 2>/dev/null && break; sleep 1; done
xcodegen generate >/dev/null 2>&1; GEN=$?
rmdir "$LOCK" 2>/dev/null
[ $GEN -ne 0 ] && { echo "xcodegen failed"; exit 1; }
xcodebuild -project Strand.xcodeproj -scheme Baseline \
  -destination "platform=iOS Simulator,id=149DD9EE-8D7D-4CC2-B5E8-07DBA768C046" \
  -configuration Debug -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E "error:|warning: .*Baseline/|BUILD (SUCCEEDED|FAILED)" | sort -u
