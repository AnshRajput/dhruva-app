# Building the stable-diffusion.cpp native libs (Loop 8)

Vendored source: `engine/sd/vendor/stable-diffusion.cpp` — a git submodule
pinned to **`b290693`** (ggml submodule `eced84c`). Bump = a deliberate re-gen
PR: rebuild the libs, re-run `dart run ffigen --config app/ffigen_sd.yaml`
(the `sd_ctx_params_t` / `sd_img_gen_params_t` layout is tightly coupled to the
pinned commit), and re-run the real-gen + RSS tests. Never an incidental bump.

The Dart FFI (`app/lib/imagine_engine/`) loads ONE shared lib,
`libstable-diffusion.*` — ggml is statically linked into it, so there are no
sidecar `libggml*` files to ship (unlike the llama AAR).

Clone the submodule after a fresh checkout:

```bash
git submodule update --init --recursive engine/sd/vendor/stable-diffusion.cpp
```

---

## macOS (dev — PROVEN on this machine)

The only target actually built + verified here. Produces the dylib the Dart FFI
tests load from `app/.dev-native/macos-sd/` (gitignored, like the llama dylibs).

```bash
cd engine/sd/vendor/stable-diffusion.cpp
cmake -B build-shared -DSD_BUILD_SHARED_LIBS=ON -DSD_METAL=ON \
      -DCMAKE_BUILD_TYPE=Release -DSD_BUILD_EXAMPLES=OFF
cmake --build build-shared --config Release -j"$(sysctl -n hw.ncpu)"
cp build-shared/bin/libstable-diffusion.dylib ../../../../app/.dev-native/macos-sd/
```

Verified: single self-contained 56 MB dylib (Accelerate + Metal frameworks
only), real 384×384 txt2img in ~30 s, ~3.6 GB peak. See `SPIKE.md`.

---

## iOS (Metal) — needs-on-device-build

Same ggml/Metal path llama.cpp already ships, so low risk — but NOT built or
run here; flag `needs-on-device-build` (like the llama xcframework). Build a
static lib per arch and wrap as an `.xcframework`, statically linked into the
Runner (so the Dart FFI resolves symbols from the process — `libraryPath: null`
in `imageGenServiceProvider` on iOS).

```bash
cd engine/sd/vendor/stable-diffusion.cpp
cmake -B build-ios -G Xcode \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DSD_METAL=ON -DSD_BUILD_SHARED_LIBS=OFF \
      -DSD_BUILD_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-ios --config Release -- -sdk iphoneos
# then: xcodebuild -create-xcframework -library <arch libs>.a -output \
#   stable-diffusion.xcframework   (bundle the ggml default.metallib too)
```

Open item: confirm the Metal shader library (`default.metallib`) is embedded /
loadable on-device. Tracked in orchestra/RISKS.md as on-device verification.

---

## Android (arm64, CPU-first) — needs-on-device-build

Recommendation from the spike: **ship CPU-only first** (correct but slow —
minutes per image at small sizes). sd.cpp has no Hexagon/NNAPI backend; Vulkan
(`-DSD_VULKAN=ON`) is the only mobile GPU option and the least-tested link, so
it's a later optimization PR, not a blocker. NOT built here —
`needs-on-device-build` (like the llama AAR).

Produces `libstable-diffusion.so`, dropped into the Android app so it's
`dlopen`ed by basename (`libraryPath: 'libstable-diffusion.so'` in
`imageGenServiceProvider` on Android).

```bash
cd engine/sd/vendor/stable-diffusion.cpp
cmake -B build-android \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-26 \
      -DSD_BUILD_SHARED_LIBS=ON \
      -DSD_METAL=OFF -DSD_VULKAN=OFF \
      -DSD_BUILD_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-android -j"$(nproc)"
# → build-android/bin/libstable-diffusion.so  (bundle under jniLibs/arm64-v8a/)
```

Gate: the Imagine feature stays HIDDEN below
`SdImageGenService.recommendedMinRamBytes` (~6 GB) — most mid-range phones won't
see it. See RISKS.md.
