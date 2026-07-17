#!/usr/bin/env bash
# Build the Android APK and upload it to Firebase App Distribution.
#
# Usage:
#   scripts/distribute.sh [release-notes] [groups]
#
# Defaults: notes auto-generated from git, groups "internal-testers".
# Requires: flutter, firebase CLI authenticated to the dhruvaai-68a00 project.
# CI later reuses this same script with a token (Loop 13 / checkpoint H3).
set -euo pipefail

FIREBASE_PROJECT="dhruvaai-68a00"
ANDROID_APP_ID="1:792596873288:android:2bcb808b7abf3b737bd87d"
GROUPS_ARG="${2:-internal-testers}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/app"

SHA="$(git rev-parse --short HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
NOTES="${1:-Dev build from $BRANCH @ $SHA — $(git log -1 --pretty=%s)}"

echo "==> flutter build apk --release ($BRANCH @ $SHA)"
flutter build apk --release

APK="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || { echo "APK not found at $APK"; exit 1; }
echo "==> Uploading $(du -h "$APK" | cut -f1 | tr -d ' ') APK to App Distribution ($GROUPS_ARG)"

firebase appdistribution:distribute "$APK" \
  --app "$ANDROID_APP_ID" \
  --project "$FIREBASE_PROJECT" \
  --groups "$GROUPS_ARG" \
  --release-notes "$NOTES"

echo "==> Done. Testers in '$GROUPS_ARG' will get the email."
