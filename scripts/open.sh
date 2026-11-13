#!/bin/bash
# Builds the app and opens it on YOUR simulator, the one you watch in DeviceHub,
# with no debugger attached.
# Usage: scripts/open.sh [--no-launch] [launch args…]   (USER_SIM_NAME=... for another watch)
#   --no-launch  build and install without bringing the app to the front, so the
#                watch keeps showing whatever app is open. If this app was the one
#                in front, installing closes it, so it is launched again. Run it this
#                way at the end of every turn that changes the app.
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

# True if this app is the one in front on the watch: it is running, and the
# last state the simulator logged for it is the user-facing ("focal") role.
# (Output is captured before grepping: under pipefail, grep -q closing the pipe
# early makes the pipeline fail.)
in_front() {
  local jobs states
  jobs=$(xcrun simctl spawn "$SIM_ID" launchctl list 2> /dev/null || true)
  case "$jobs" in *"UIKitApplication:$BUNDLE_ID["*) ;; *) return 1 ;; esac
  states=$(xcrun simctl spawn "$SIM_ID" log show --last 24h --style compact \
    --predicate "process == \"runningboardd\" AND eventMessage CONTAINS \"Calculated state for app<$BUNDLE_ID(\"" 2> /dev/null || true)
  case "$(printf '%s\n' "$states" | grep -F "Calculated state for app<$BUNDLE_ID(" | tail -1)" in
    *UserInteractiveFocal*) return 0 ;;
  esac
  return 1
}

# The test watch isn't needed for this; free its memory.
scripts/sim.sh --shutdown
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
xcodebuild build -project "House Lights.xcodeproj" -scheme "House Lights Watch App" \
  -destination "id=$SIM_ID" -derivedDataPath "$DERIVED" -quiet
WAS_IN_FRONT=0
if [ "$LAUNCH" = 0 ] && in_front; then WAS_IN_FRONT=1; fi
xcrun simctl install "$SIM_ID" "$DERIVED/Build/Products/Debug-watchsimulator/House Lights Watch App.app"
if [ "$LAUNCH" = 0 ]; then
  if [ "$WAS_IN_FRONT" = 1 ]; then
    # Right after an install watchOS can refuse a launch ("Scene update
    # failed"), so try for a few seconds.
    for try in 1 2 3 4 5 6 7 8 9 10; do
      if xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" "$@" > /dev/null 2>&1; then
        echo "Installed House Lights on $USER_SIM_NAME and relaunched it (it was in front)"
        exit 0
      fi
      sleep 1
    done
    echo "Installed House Lights on $USER_SIM_NAME, but couldn't relaunch it; open it from the app list" >&2
  else
    echo "Installed House Lights on $USER_SIM_NAME (not launched)"
  fi
  exit 0
fi
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" "$@" > /dev/null
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
echo "Opened House Lights on $USER_SIM_NAME"
