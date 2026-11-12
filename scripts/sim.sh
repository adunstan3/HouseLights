#!/bin/bash
# Prints the id of the simulator the scripts use, creating and booting it if needed.
# It's a separate "House Lights Tests" watch so scripts never disturb the simulator
# you watch in DeviceHub. Override with SIM_NAME=... to use another.
# There's no first-gen Ultra simulator for the current SDK; the Ultra 4 (49mm) has the same screen size.
#   sim.sh --name      prints its name only
#   sim.sh --shutdown  shuts it down if it's booted (frees about 1 GB)
set -euo pipefail
SIM_NAME="${SIM_NAME:-House Lights Tests}"
if [ "${1:-}" = "--name" ]; then echo "$SIM_NAME"; exit 0; fi
source "$(dirname "$0")/lock.sh"
DEVICE_TYPE="${SIM_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-4-49mm}"
SIM_ID=$(xcrun simctl list devices available | grep -F "    $SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ "${1:-}" = "--shutdown" ]; then
  [ -z "$SIM_ID" ] || xcrun simctl shutdown "$SIM_ID" 2> /dev/null || true
  exit 0
fi
if [ -z "$SIM_ID" ]; then
  RUNTIME=$(xcrun simctl list runtimes | grep -o 'com.apple.CoreSimulator.SimRuntime.watchOS-[0-9-]*' | tail -1)
  SIM_ID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
echo "$SIM_ID"
