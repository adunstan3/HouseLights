#!/bin/bash
# Prints the id of the simulator the scripts use, creating and booting it if needed.
# It's a separate "House Lights Tests" watch so scripts never disturb the simulator
# you run from Xcode. Override with SIM_NAME=... to use another.
# There's no first-gen Ultra simulator for the current SDK; the Ultra 4 (49mm) has the same screen size.
set -euo pipefail
SIM_NAME="${SIM_NAME:-House Lights Tests}"
DEVICE_TYPE="${SIM_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-4-49mm}"
SIM_ID=$(xcrun simctl list devices available | grep -F "    $SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -z "$SIM_ID" ]; then
  RUNTIME=$(xcrun simctl list runtimes | grep -o 'com.apple.CoreSimulator.SimRuntime.watchOS-[0-9-]*' | tail -1)
  SIM_ID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
echo "$SIM_ID"
