#!/bin/bash
# The shared build lock for the watch apps (Moondance, House Lights, Closing Time).
#
# This Mac has 8 GB of RAM, so only one agent may build, test, archive or drive a
# simulator at a time. Every script here that does any of that starts with
#   source "$(dirname "$0")/lock.sh"
# which waits its turn (it can take many minutes; that's normal, don't work around
# it) and holds the lock until the script exits. The lock is one file shared by all
# the apps; macOS drops it by itself if the script dies, so it never goes stale.
#
# Never call xcodebuild or `xcrun simctl` directly. If no script does what you
# need, run it through scripts/locked.sh.
#
# The same file lives in each app's scripts/ folder; keep the copies identical.
WATCHAPPS_LOCK_FILE="${WATCHAPPS_LOCK_FILE:-$HOME/Library/Caches/watchapps-build.lock}"
_lock_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${WATCHAPPS_LOCK_HELD:-}" in
  "")
    # Not held yet: say so if someone else has it, then run this script again under the lock.
    if ! /usr/bin/lockf -k -s -t 0 "$WATCHAPPS_LOCK_FILE" true; then
      echo "Waiting for the shared build lock. Held by: $(cat "$WATCHAPPS_LOCK_FILE.owner" 2> /dev/null || echo "another script")" >&2
    fi
    export WATCHAPPS_LOCK_HELD=outer
    exec /usr/bin/lockf -k "$WATCHAPPS_LOCK_FILE" /bin/bash "$0" "$@"
    ;;
  outer)
    # We hold it. Scripts we call (sim.sh and so on) see 1 and carry straight on.
    export WATCHAPPS_LOCK_HELD=1
    echo "$(basename "$(dirname "$_lock_scripts")") · $(basename "$0") · pid $$ · since $(date +%H:%M:%S)" > "$WATCHAPPS_LOCK_FILE.owner"
    trap 'rm -f "$WATCHAPPS_LOCK_FILE.owner"' EXIT
    # Only one test simulator stays booted: shut down the other apps' "… Tests"
    # watches to free memory. Never touches the simulator you watch in DeviceHub.
    _lock_keep="$("$_lock_scripts/sim.sh" --name)"
    xcrun simctl list devices booted \
      | sed -nE 's/^ +(.* Tests) \(([0-9A-F-]{36})\) \(Booted\).*/\2 \1/p' \
      | while read -r _lock_id _lock_name; do
          if [ "$_lock_name" != "$_lock_keep" ]; then
            echo "Shutting down \"$_lock_name\" to free memory" >&2
            xcrun simctl shutdown "$_lock_id" || true
          fi
        done
    # Run the script itself as a child and pass on its exit status. The EXIT trap
    # alone can't: after an error such as "unbound variable", bash 3.2 runs the trap
    # with $? = 0 and the script exits 0, so a crashed script would look like it passed.
    /bin/bash "$0" "$@" && _lock_status=0 || _lock_status=$?
    exit "$_lock_status"
    ;;
esac
