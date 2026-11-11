#!/bin/bash
# Screenshots of the app in various states, for checking layouts against mockups/.
# Usage: scripts/shots.sh <out-dir> name "launch args" [name "launch args" …]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; shift
mkdir -p "$OUT"
DERIVED="${DERIVED:-build/DerivedData}"
BUNDLE_ID="com.andrewdunstan.HouseLights.watchkitapp"
SIM_ID=$("$(dirname "$0")/sim.sh")
xcodebuild build -project "House Lights.xcodeproj" -scheme "House Lights Watch App" \
  -destination "id=$SIM_ID" -derivedDataPath "$DERIVED" -quiet
xcrun simctl install "$SIM_ID" "$DERIVED/Build/Products/Debug-watchsimulator/House Lights Watch App.app"
while [ $# -ge 2 ]; do
  NAME="$1"; ARGS="$2"; shift 2
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2> /dev/null || true
  # shellcheck disable=SC2086
  xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" $ARGS > /dev/null
  sleep "${SHOT_DELAY:-7}"
  xcrun simctl io "$SIM_ID" screenshot "$OUT/$NAME.png" > /dev/null 2>&1
  echo "$OUT/$NAME.png"
done
