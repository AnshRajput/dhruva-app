#!/usr/bin/env bash
# Store screenshots from a simulator: runs integration_test/store_screenshots_test.dart
# and grabs a frame whenever the test prints `SHOT <name>`.
# Usage: scripts/capture-store-shots.sh <simulator-udid> <model.gguf> <out-dir>
set -euo pipefail
UDID="$1"
mkdir -p "$3"
# Absolute paths: the script cd's into app/ below.
MODEL="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; OUT="$(cd "$3" && pwd)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
cd "$(dirname "${BASH_SOURCE[0]}")/../app"
flutter test integration_test/store_screenshots_test.dart -d "$UDID" \
  --dart-define=SHOT_MODEL="$MODEL" 2>&1 | while IFS= read -r line; do
  echo "$line"
  if [[ "$line" =~ SHOT\ ([A-Za-z0-9_]+) ]]; then
    xcrun simctl io "$UDID" screenshot "$OUT/${BASH_REMATCH[1]}.png" >/dev/null 2>&1 &&
      echo "captured ${BASH_REMATCH[1]}"
  fi
done
