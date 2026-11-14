#!/bin/bash
# Archives the app (Release, any watchOS device) and uploads it to App Store
# Connect for TestFlight (Internal Only). Shared by all three watch apps: this file
# is identical in Moondance, House Lights and Closing Time; per-app values live in
# scripts/app.env. If it needs changing, change all three copies.
#
# Steps:
#   1. Refuses to run with uncommitted or untracked changes.
#   2. Picks the build number. A git tag build-<N> marks build N as uploaded. If
#      CURRENT_PROJECT_VERSION is already tagged (or below the newest tag), every
#      target is bumped to the next number and the bump is committed ("Build N").
#   3. Runs the unit tests (and the UI tests with UI_TESTS=1); stops if they fail.
#   4. Archives to build/<APP_NAME>-<N>.xcarchive, checks the archived build number
#      and ITSAppUsesNonExemptEncryption = NO, and uploads.
#   5. Tags the commit build-<N>. Pushes the branch and the tag only with PUSH=1.
#
# Usage: scripts/release.sh
#   BUILD=N      upload as build N (must be above every build-* tag)
#   UI_TESTS=1   also run the UI tests first (slow)
#   PUSH=1       push the branch and the new tag to origin afterwards
# Full logs: build/archive.log and build/export.log.
# Uses the Apple ID signed in to Xcode (Settings › Accounts) for signing and upload.
set -euo pipefail
source "$(dirname "$0")/lock.sh"
cd "$(dirname "$0")/.."
# APP_NAME, PROJECT, PROJECT_FILE, SCHEME, UI_TEST_COMMAND (array)
source scripts/app.env

fail() { echo "release.sh: $*" >&2; exit 1; }

# 1. Clean tree, so the tag matches exactly what was uploaded.
[ -z "$(git status --porcelain)" ] || { git status --short; fail "uncommitted changes; commit them first"; }

# 2. Build number. Matches both project formats:
#    "CURRENT_PROJECT_VERSION": "4",   (Xcode 27 project.xcproj)
#    CURRENT_PROJECT_VERSION = 4;      (project.pbxproj)
VERSION_PATTERN='CURRENT_PROJECT_VERSION"?[ :=]+"?[0-9]+'
NUMBERS=$(grep -oE "$VERSION_PATTERN" "$PROJECT_FILE" | grep -oE '[0-9]+$' | sort -un || true)
[ -n "$NUMBERS" ] || fail "no CURRENT_PROJECT_VERSION in $PROJECT_FILE"
[ "$(printf '%s\n' "$NUMBERS" | wc -l | tr -d ' ')" = 1 ] \
  || fail "targets disagree on CURRENT_PROJECT_VERSION: $(echo $NUMBERS)"
CURRENT=$NUMBERS
LAST=$(git tag --list 'build-*' | sed 's/^build-//' | grep -E '^[0-9]+$' | sort -n | tail -1 || true)
LAST=${LAST:-0}
if [ -n "${BUILD:-}" ]; then
  [ "$BUILD" -gt "$LAST" ] || fail "BUILD=$BUILD, but build $LAST is already tagged as uploaded"
  NEW=$BUILD
elif [ "$CURRENT" -gt "$LAST" ]; then
  NEW=$CURRENT
else
  NEW=$((LAST + 1))
fi
if [ "$NEW" != "$CURRENT" ]; then
  sed -E -i '' "s/(CURRENT_PROJECT_VERSION\"?[ :=]+\"?)[0-9]+/\1$NEW/g" "$PROJECT_FILE"
  git add "$PROJECT_FILE"
  git commit -q -m "Build $NEW"
  echo "Bumped the build number $CURRENT → $NEW and committed it."
fi

# 3. Tests. They don't wait for the lock: this script already holds it.
mkdir -p build
echo "Running unit tests…"
scripts/test.sh > build/release-tests.log 2>&1 || { tail -30 build/release-tests.log; fail "unit tests failed (build/release-tests.log)"; }
if [ "${UI_TESTS:-0}" = 1 ]; then
  echo "Running UI tests…"
  "${UI_TEST_COMMAND[@]}" > build/release-uitests.log 2>&1 \
    || { tail -30 build/release-uitests.log; fail "UI tests failed (build/release-uitests.log)"; }
fi

# 4. Archive, check, upload.
ARCHIVE="build/$APP_NAME-$NEW.xcarchive"
rm -rf "$ARCHIVE" build/Export
echo "Archiving $APP_NAME build ${NEW}…"   # braces: bash 3.2 reads "…" as part of a bare name
if ! xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=watchOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates > build/archive.log 2>&1; then
  grep -E "error" build/archive.log | head -20
  fail "archive failed (build/archive.log)"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$ARCHIVE/Info.plist")
ARCHIVED=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE/Info.plist")
[ "$ARCHIVED" = "$NEW" ] || fail "the archive says build $ARCHIVED, expected $NEW"
while IFS= read -r plist; do
  value=$(/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$plist" 2> /dev/null || echo missing)
  [ "$value" = false ] || fail "ITSAppUsesNonExemptEncryption is $value in ${plist#$ARCHIVE/}; it must be NO"
done < <(find "$ARCHIVE/Products" -path "*.app/Info.plist")

echo "Archived $APP_NAME $VERSION ($NEW); uploading…"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/Export -allowProvisioningUpdates > build/export.log 2>&1; then
  grep -E "error|Error" build/export.log | head -20
  fail "upload failed (build/export.log)"
fi
grep -q "EXPORT SUCCEEDED" build/export.log && grep -q "Upload succeeded" build/export.log \
  || { tail -20 build/export.log; fail "xcodebuild finished, but the log doesn't say the upload succeeded (build/export.log)"; }

# 5. Tag, and push if asked.
git tag "build-$NEW"
echo "Uploaded $APP_NAME $VERSION ($NEW) and tagged it build-$NEW."
echo "It shows in App Store Connect › TestFlight after processing."
if [ "${PUSH:-0}" = 1 ]; then
  git push -q origin HEAD && git push -q origin "build-$NEW" && echo "Pushed the branch and build-$NEW."
else
  echo "Not pushed (PUSH=1 pushes the branch and the tag)."
fi
