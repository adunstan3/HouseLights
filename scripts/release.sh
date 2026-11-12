#!/bin/bash
# Archives the app (Release, any watchOS device) and uploads it to App Store
# Connect for TestFlight (Internal Only). Bump CURRENT_PROJECT_VERSION on every
# target first: App Store Connect rejects a build number it has already seen.
# Uses the Apple ID signed in to Xcode (Settings › Accounts) for signing and upload.
# Usage: scripts/release.sh   (full logs in build/archive.log and build/export.log)
set -euo pipefail
source "$(dirname "$0")/lock.sh"
cd "$(dirname "$0")/.."

ARCHIVE=build/HouseLights.xcarchive
rm -rf "$ARCHIVE" build/Export
mkdir -p build
if ! xcodebuild archive -project "House Lights.xcodeproj" -scheme "House Lights Watch App" -configuration Release \
  -destination 'generic/platform=watchOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates > build/archive.log 2>&1; then
  grep -E "error" build/archive.log | head -20
  echo "Archive failed (see build/archive.log)"; exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$ARCHIVE/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE/Info.plist")
echo "Archived House Lights $VERSION ($BUILD); uploading…"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/Export -allowProvisioningUpdates > build/export.log 2>&1; then
  grep -E "error|Error" build/export.log | head -20
  echo "Upload failed (see build/export.log)"; exit 1
fi
grep -E "Upload succeeded|EXPORT SUCCEEDED" build/export.log || true
echo "Uploaded $VERSION ($BUILD). It shows in App Store Connect › TestFlight after processing."
