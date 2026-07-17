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

# UX-hardening A3: arm64-only. The llama.cpp engine ships arm64-v8a native
# libs ONLY, so an APK carrying a Flutter engine for armeabi-v7a/x86_64 would
# install on those ABIs and then fail to dlopen libllama → no reply. A fat
# `flutter build apk` ignores the gradle abiFilters for the engine .so, so pin
# the target platform here to ship an arm64-only engine.
# Stamp a UNIQUE, monotonic versionCode per ship (git commit count). A static
# versionCode (every prior build shipped 1.0.0+1) makes Android refuse to
# cleanly reinstall over the installed APK, so the tester keeps running the OLD
# binary — the real reason a shipped fix "still fails on device".
BUILD_NUMBER="$(git rev-list --count HEAD)"
BUILD_NAME="$(grep -m1 '^version:' app/pubspec.yaml | sed 's/version: *//; s/+.*//')"
echo "==> version $BUILD_NAME+$BUILD_NUMBER — flutter build apk --release --target-platform android-arm64 ($BRANCH @ $SHA)"
flutter build apk --release --target-platform android-arm64 \
  --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"

APK="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || { echo "APK not found at $APK"; exit 1; }
echo "==> Uploading $(du -h "$APK" | cut -f1 | tr -d ' ') APK to App Distribution ($GROUPS_ARG)"

firebase appdistribution:distribute "$APK" \
  --app "$ANDROID_APP_ID" \
  --project "$FIREBASE_PROJECT" \
  --groups "$GROUPS_ARG" \
  --release-notes "$NOTES"

echo "==> Done. Testers in '$GROUPS_ARG' will get the email."
