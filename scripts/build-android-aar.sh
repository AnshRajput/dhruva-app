#!/usr/bin/env bash
# Rebuilds app/android/app/libs/llama-cpp-dart.aar from source with 16 KB
# ELF page alignment (Google Play requirement for Android 15+ devices).
#
# Why not the release asset: netdur/llama_cpp_dart v0.9.0-dev.9's prebuilt
# AAR links with 4 KB pages (LOAD align 0x1000), which Play rejects. This
# script reproduces upstream's own tool/build_android_aar.sh flags at the
# same tag (llama.cpp d6d0ce8215a1c324e8de04b52f9dd65c5edc129f) and adds
# -z max-page-size=16384. C API is unchanged: every llama_/mtmd_/ggml_/gguf_
# export of the original is present in the rebuild.
#
# Needs: Android NDK r28+ (ANDROID_NDK or ~/Library/Android/sdk/ndk/28.*),
# cmake, ninja, git. Usage: scripts/build-android-aar.sh
set -euo pipefail

TAG="v0.9.0-dev.9"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AAR="$ROOT/app/android/app/libs/llama-cpp-dart.aar"
NDK="${ANDROID_NDK:-$(ls -d "$HOME"/Library/Android/sdk/ndk/28.* 2>/dev/null | tail -1)}"
[[ -d "$NDK" ]] || { echo "error: set ANDROID_NDK to an NDK r28+ install" >&2; exit 1; }
BIN="$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin | head -1)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone -q --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules \
  https://github.com/netdur/llama_cpp_dart "$WORK/src"

cmake -G Ninja -B "$WORK/build" -S "$WORK/src/src/llama.cpp" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WORK/install" \
  -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TOOLS=ON -DMTMD_VIDEO=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_APP=OFF -DLLAMA_CURL=OFF -DGGML_OPENMP=OFF \
  -DGGML_LLAMAFILE=OFF -DGGML_NATIVE=OFF \
  -DCMAKE_CXX_FLAGS="-O3 -DNDEBUG" \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
cmake --build "$WORK/build" --parallel
cmake --install "$WORK/build" >/dev/null

# Repack: keep the existing AAR's manifest/classes.jar/R.txt, swap the .so set.
mkdir "$WORK/stage"
(cd "$WORK/stage" && unzip -q "$AAR")
for so in libggml-base libggml-cpu libggml libllama libmtmd; do
  cp "$WORK/install/lib/$so.so" "$WORK/stage/jni/arm64-v8a/"
  "$BIN/llvm-strip" --strip-unneeded "$WORK/stage/jni/arm64-v8a/$so.so"
  if "$BIN/llvm-readelf" -l "$WORK/stage/jni/arm64-v8a/$so.so" | grep LOAD | grep -qv 0x4000; then
    echo "error: $so.so is not 16 KB aligned" >&2; exit 1
  fi
done
rm -f "$AAR"
(cd "$WORK/stage" && zip -q -r -X "$AAR" AndroidManifest.xml classes.jar jni R.txt)
(cd "$(dirname "$AAR")" && shasum -a 256 "$(basename "$AAR")" | tee "$(basename "$AAR").sha256")
echo "Rebuilt $AAR (16 KB aligned). Update SHA256 in scripts/fetch-android-aar.sh."
