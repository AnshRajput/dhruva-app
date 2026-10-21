#!/usr/bin/env bash
# Builds a signed App Store archive and uploads it to App Store Connect
# (TestFlight). Needs: Xcode signed in to the GLOBAL SYNAPSE team (9AA3ASU85Q)
# and an App Store Connect app record for bundle id app.dhruva.mobile —
# without the record, export fails with missingApp(bundleId:).
#
# Usage: scripts/upload-testflight.sh [path/to/existing.xcarchive]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"
ARCHIVE="${1:-build/ios/archive/Dhruva.xcarchive}"

if [[ $# -eq 0 ]]; then
  flutter build ipa --release --no-codesign   # pods + Flutter build settings
  rm -rf "$ARCHIVE"
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration Release -destination generic/platform=iOS \
    -archivePath "$ARCHIVE" archive -allowProvisioningUpdates
fi

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ios/ExportOptions-AppStore.plist \
  -exportPath build/ios/upload -allowProvisioningUpdates
echo "Uploaded. Build appears in App Store Connect → TestFlight after processing."
