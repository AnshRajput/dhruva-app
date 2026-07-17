#!/usr/bin/env bash
# Loop 08 spike — build stable-diffusion.cpp for macOS (arm64, Metal).
# Mirrors the llama.cpp vendoring approach (ADR-001): pin an exact commit,
# build the native lib on the dev machine so image gen is verifiable here.
#
# Verified working on this machine (2026-07-18):
#   Apple M-series arm64, 16 GB RAM, cmake 4.4.0, Apple clang 21.
#   sd.cpp @ b290693 (master-782). Build ~2 min, 8 cores.
set -euo pipefail

SD_COMMIT="b290693"                                   # PIN. leejet/stable-diffusion.cpp
SD_REPO="https://github.com/leejet/stable-diffusion.cpp.git"
WORK="${1:-$PWD/sd-spike}"                             # scratch clone dir (NOT committed)

mkdir -p "$WORK" && cd "$WORK"
if [ ! -d stable-diffusion.cpp ]; then
  git clone --recursive "$SD_REPO"
fi
cd stable-diffusion.cpp
git checkout "$SD_COMMIT"
git submodule update --init --recursive              # ggml lives here (shared with llama.cpp)

# Metal backend (device release targets iOS Metal / Android arm64 later).
# For a CPU-only reference build swap: -DSD_METAL=OFF
cmake -B build -DSD_METAL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j"$(sysctl -n hw.ncpu)"

echo "Built: $WORK/stable-diffusion.cpp/build/bin/sd-cli"
echo "Lib:   $WORK/stable-diffusion.cpp/build/libstable-diffusion.a (+ ggml/*.a)"
echo "For a Flutter-loadable dylib add -DSD_BUILD_SHARED_LIBS=ON (mirrors .dev-native/macos)."
