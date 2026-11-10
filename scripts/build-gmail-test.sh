#!/usr/bin/env bash
# Builds a DEBUG-signed Android APK with the Gmail OAuth client ids baked in, so
# the owner can test Google sign-in on a phone. The Android OAuth client in the
# `dhruva-ai` Google Cloud project matches the debug keystore's SHA-1, so this
# only signs in when the APK is signed with that debug keystore (the default of
# `flutter build apk --debug`).
#
# For testing only: do NOT distribute this APK. Client ids are public, but a
# debug build is not a release.
#
# Usage: scripts/build-gmail-test.sh   (from anywhere in the repo)
# Output: app/build/app/outputs/flutter-apk/app-debug.apk
set -euo pipefail

cd "$(dirname "$0")/../app"

flutter build apk --debug \
  --dart-define=GMAIL_SERVER_CLIENT_ID=262319606227-hl5s6bmnc5durlotl0dfpbv59puv54dl.apps.googleusercontent.com \
  --dart-define=GMAIL_IOS_CLIENT_ID=262319606227-ahgl3kqr0jo0jo4sj18tcg74oaerqhib.apps.googleusercontent.com

echo
echo "Built app/build/app/outputs/flutter-apk/app-debug.apk (debug-signed, Gmail enabled)."
echo "Test build for the owner only. Do not distribute."
