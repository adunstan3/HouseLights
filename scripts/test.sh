#!/bin/bash
# Runs the unit tests on a warm watch simulator (never shuts it down).
# Usage: scripts/test.sh [extra xcodebuild args, e.g. -only-testing:...]
set -euo pipefail
source "$(dirname "$0")/lock.sh"
cd "$(dirname "$0")/.."

DERIVED="${DERIVED:-build/DerivedData}"
SIM_ID=$("$(dirname "$0")/sim.sh")

COMMON=(-project "House Lights.xcodeproj" -scheme "House Lights Watch App" -destination "id=$SIM_ID" -derivedDataPath "$DERIVED")
xcodebuild build-for-testing "${COMMON[@]}" -quiet
xcodebuild test-without-building "${COMMON[@]}" -only-testing:"House Lights Watch AppTests" "$@"
