#!/bin/bash
# Runs any command under the shared build lock (see lock.sh), from the repo folder.
# For the rare xcodebuild or simctl command no other script covers.
# Usage: scripts/locked.sh xcodebuild -project … build
set -euo pipefail
source "$(dirname "$0")/lock.sh"
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || { echo "Usage: scripts/locked.sh command [args…]" >&2; exit 2; }
"$@"
