#!/bin/bash
# Builds the app and opens it on YOUR simulator, the one you watch in DeviceHub,
# with no debugger attached.
# Usage: scripts/open.sh [--no-launch] [launch args…]   (USER_SIM_NAME=... for another watch)
#   --no-launch  only build and install, so the watch keeps showing whatever is in
#                front. Run it this way at the end of every turn that changes the app.
#                (If this app is open on the watch, installing closes it.)
set -euo pipefail
source "$(dirname "$0")/lock.sh"
cd "$(dirname "$0")/.."

LAUNCH=1
if [ "${1:-}" = "--no-launch" ]; then LAUNCH=0; shift; fi

DERIVED="${DERIVED:-build/DerivedData}"
BUNDLE_ID="com.andrewdunstan.HouseLights.watchkitapp"
USER_SIM_NAME="${USER_SIM_NAME:-Apple Watch Ultra 4 (49mm)}"
SIM_ID=$(xcrun simctl list devices available | grep -F "    $USER_SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
[ -n "$SIM_ID" ] || { echo "No available simulator named \"$USER_SIM_NAME\"" >&2; exit 1; }

# The test watch isn't needed for this; free its memory.
scripts/sim.sh --shutdown
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
xcodebuild build -project "House Lights.xcodeproj" -scheme "House Lights Watch App" \
  -destination "id=$SIM_ID" -derivedDataPath "$DERIVED" -quiet
xcrun simctl install "$SIM_ID" "$DERIVED/Build/Products/Debug-watchsimulator/House Lights Watch App.app"
if [ "$LAUNCH" = 0 ]; then
  echo "Installed House Lights on $USER_SIM_NAME (not launched)"
  exit 0
fi
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" "$@" > /dev/null
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
echo "Opened House Lights on $USER_SIM_NAME"
