#!/usr/bin/env bash
# Play release via Shorebird (so Dart-only fixes can ship as patches).
# arm64-only on purpose: the llama.cpp AAR has no other ABI, and shorebird's
# default --target-platform ignores build.gradle's abiFilters, which would
# ship armv7/x86_64 slices that can't load a model.
# Needs ~/secrets/shorebird-token and app/android/key.properties (upload key).
# Output: app/build/app/outputs/bundle/release/app-release.aab
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../app"
SHOREBIRD_TOKEN="$(cat ~/secrets/shorebird-token)" ~/.shorebird/bin/shorebird \
  release android --flutter-version=3.41.2 --target-platform=android-arm64 --no-confirm
# Patch later (Dart-only changes):
#   shorebird patch --platforms=android --release-version=<version+build>
