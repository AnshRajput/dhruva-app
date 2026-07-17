#!/usr/bin/env bash
#
# Fetch + verify the llama.cpp Android AAR (native inference libs) for Dhruva.
#
# Provenance (why this exact artifact):
#   Source repo  : github.com/netdur/llama_cpp_dart
#   Release       : v0.9.0-dev.9  (asset: llama-cpp-dart.aar, CPU + mtmd, arm64-v8a)
#   Release commit: 1a8c7563cb5382e23bcd20dc5720fc8d8099ec58
#   Our engine pin: c6e37785835a189261fab28e53386e4e954f3e42  (ENGINE PIN, DECISIONS.md)
#   Relationship  : our pin is 2 commits AHEAD of the release tag; both are
#                   pure-Dart (worker.dart cancel fix #106, probe_cancel #105) and
#                   touch NO native code. The AAR contains only compiled .so, so it
#                   is native-identical to what our pin would build. => download,
#                   not rebuild. (Rebuild path: clone the pin, tool/build_android_aar.sh
#                   with Android NDK — only needed if a future pin bumps native code.)
#   Size          : 2.4 MB  (<50 MB => committed to the repo at app/android/app/libs/)
#   sha256        : 73ab5e755c57ae4c3e06fc728c9e649152e89db99e2b2deba99f3a5fcff41028
#   Contents      : jni/arm64-v8a/{libllama,libggml,libggml-base,libggml-cpu,libmtmd}.so
#
# The AAR is committed, so a normal checkout needs nothing. Run this only to
# re-fetch or to verify integrity of the committed copy. Idempotent.
#
# Usage: scripts/fetch-android-aar.sh [--verify-only]
set -euo pipefail

REPO="netdur/llama_cpp_dart"
TAG="v0.9.0-dev.9"
ASSET="llama-cpp-dart.aar"
SHA256="73ab5e755c57ae4c3e06fc728c9e649152e89db99e2b2deba99f3a5fcff41028"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS_DIR="$ROOT/app/android/app/libs"
AAR="$LIBS_DIR/$ASSET"

sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

if [[ "${1:-}" == "--verify-only" ]]; then
  [[ -f "$AAR" ]] || { echo "error: $AAR missing" >&2; exit 1; }
  [[ "$(sha_of "$AAR")" == "$SHA256" ]] || { echo "error: sha256 mismatch on $AAR" >&2; exit 1; }
  echo "AAR ok: $ASSET ($SHA256)"
  exit 0
fi

# Already present and correct? Nothing to do.
if [[ -f "$AAR" && "$(sha_of "$AAR")" == "$SHA256" ]]; then
  echo "AAR already present and verified: $ASSET"
  exit 0
fi

mkdir -p "$LIBS_DIR"
echo "downloading $ASSET from $REPO@$TAG ..."
gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$LIBS_DIR" --clobber

got="$(sha_of "$AAR")"
[[ "$got" == "$SHA256" ]] || { echo "error: sha256 mismatch (expected $SHA256, got $got)" >&2; exit 1; }
echo "AAR fetched + verified: $ASSET ($SHA256)"
