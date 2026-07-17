# Loop 08 feasibility spike — on-device image generation (stable-diffusion.cpp)

**Verdict: FEASIBLE. The riskiest link works on this machine.** sd.cpp builds
and generates a real image on macOS/Metal in one loop. It is *not* a
multi-session native yak-shave for the engine itself — it shares ggml with our
existing llama.cpp toolchain. The remaining work is normal-loop sized (ffigen
binding + ImageGenService + owned isolate + UI), with the honest caveat that
Android/iOS device runs need on-device verification and a hard RAM gate.

Pin: `leejet/stable-diffusion.cpp` @ **`b290693`** (master-782, tag base of
2026-07-16 activity). ggml submodule @ `eced84c`.

---

## D1 — Build on macOS (PROVEN)

Exact invocation (see `build-macos.sh`, run against the pinned commit):

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp.git
cd stable-diffusion.cpp && git checkout b290693
git submodule update --init --recursive
cmake -B build -DSD_METAL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j8
```

- Toolchain: cmake 4.4.0, Apple clang 21, arm64, 8 cores, 16 GB RAM.
- Build time ~2 min. Only deprecation warnings, no errors.
- Outputs: `build/bin/sd-cli` (+ `sd-server`), `build/libstable-diffusion.a`,
  `build/ggml/src/libggml*.a`, `build/ggml/src/ggml-metal/libggml-metal.a`.
- Static by default. For a Flutter-loadable dylib add
  `-DSD_BUILD_SHARED_LIBS=ON` (mirrors the `.dev-native/macos` llama dylibs).

## D2 — Real txt2img (PROVEN)

Model: `v1-5-pruned-emaonly.safetensors` (SD 1.5), 4.27 GB, from the official
mirror `stable-diffusion-v1-5/stable-diffusion-v1-5` (runwayml repo was pulled).
No small GGUF quant repo resolved (second-state 404, city96/leejet 401) — used
the canonical safetensors; sd.cpp can quantize on load if we want smaller.

```bash
sd-cli -m v1-5-pruned-emaonly.safetensors \
  -p "a red apple on a table" \
  -W 384 -H 384 --steps 12 --cfg-scale 7 --seed 42 --sampling-method euler_a \
  -o apple.png -v
```

Evidence (`spike-evidence-apple-384.png`, committed):
- **384x384 PNG, 268 KB, valid PNG magic `89 50 4E 47`** (`sips` confirms dims).
- 268 KB rules out a blank frame; visually verified — a coherent red apple on a
  table, correct subject, photographic.
- `generate_image completed in 46.23s` (12 steps @ ~2.97 s/it on Metal + 3.7s
  VAE decode). Wall 55s incl. model load.
- **Peak memory footprint ~3.6 GB** (`/usr/bin/time -l` max RSS 3.58 GB) for
  SD 1.5 f16 at 384x384. This is the number that sets the device floor.

## D3 — FFI surface + ImageGenService sketch

sd.cpp's public C API (`include/stable-diffusion.h`) is **FFI-friendly, on par
with llama.h** — plain C, one opaque handle, default-initializers so the huge
param structs don't have to be filled field-by-field. ffigen will bind it the
same way we bind llama. Four calls carry the whole feature:

```c
void        sd_ctx_params_init(sd_ctx_params_t*);           // defaults
sd_ctx_t*   new_sd_ctx(const sd_ctx_params_t*);             // load model  -> BIG alloc
void        sd_img_gen_params_init(sd_img_gen_params_t*);   // defaults
bool        generate_image(sd_ctx_t*, const sd_img_gen_params_t*,
                           sd_image_t** out, int* n_out);   // txt2img
void        sd_cancel_generation(sd_ctx_t*, SD_CANCEL_ALL); // <-- built-in cancel
void        free_sd_images(sd_image_t*, int);               // free result
void        free_sd_ctx(sd_ctx_t*);                         // FREE PATH (big)
// + sd_set_progress_callback(cb, data) for step progress.
```

Two things this gives us that llama did *not*: a first-class
`sd_cancel_generation` (no isolate-kill hack needed) and a progress callback.
`sd_image_t` is `{w,h,channel,uint8_t* data}` — raw RGB; we PNG-encode in Dart
or via the CLI's stb path.

Watch-out: the param structs (`sd_ctx_params_t` ~30 fields,
`sd_img_gen_params_t` with nested guidance/sample/cache/hires structs) are large
and grow release-to-release, so the ffigen struct layout is **tightly coupled to
the pinned commit** — upgrades are a deliberate re-gen + re-verify PR, exactly
like ADR-001 says for llama.

EngineService-style abstraction (mirrors `engine_service.dart`; native glue in
its own isolate, free-path owned by us per the ADR discipline):

```dart
abstract class ImageGenService {
  Future<void> loadModel(String path, {int threads});      // new_sd_ctx (owned isolate)
  Stream<int>  generate({                                   // yields step progress
    required String prompt, String negativePrompt = '',
    int steps = 12, int width = 512, int height = 512,
    double cfgScale = 7, int seed = -1,
  });                                                       // completes with image bytes
  Future<void> cancel();                                    // sd_cancel_generation(ALL)
  Future<void> unload();                                    // free_sd_ctx -> free ctx THEN nothing leaks
  Future<void> dispose();                                   // kill isolate
}
```

Same owned-isolate pattern as `llama_engine_service.dart`: main isolate posts
commands, worker isolate holds the `sd_ctx_t*` and does the FFI. Free path is
`free_sd_images(result)` after copying bytes out, then `free_sd_ctx` on unload —
**and this matters more than for llama**: an SD ctx is a multi-GB resident
allocation, so unload-on-background and unload-before-loading-an-LLM are
mandatory, not optional. One model in memory at a time.

## D4 — Buildability verdict, RAM floor, Android/iOS

**Shippable in a normal loop, with an on-device-verification flag** — same
posture as voice (Loop 6) and vision (Loop 7). The native engine is not the hard
part; the honest risks are memory and mobile GPU backends, not compilation.

**Device RAM floor (the gate).** SD 1.5 f16 peaked ~3.6 GB at 384x384 on
desktop; 512x512 and larger climb from there. Phones can't spare that on top of
the OS. Realistic gate:
- **OFF below ~6 GB device RAM.** SD 1.5 needs ~2-4 GB working set; add headroom.
- Even at 6-8 GB, ship a **q8_0/q4 quant + small default size (384-512) + low
  steps**, and **force-unload any loaded LLM first** (can't hold a chat model and
  an SD ctx together). This is exactly the "flagged OFF below the RAM floor"
  the PLAN calls for. Most mid-range phones: feature hidden.

**Android/iOS native difficulty — LOW-to-MEDIUM, shares our toolchain.**
sd.cpp is built on the *same ggml* as llama.cpp, so the cross-compile story is
the one we already solved:
- **iOS:** `-DSD_METAL=ON` → same GGML_METAL path llama uses; Metal shaders
  already ship in our llama build. Expect it to slot into the same xcframework
  approach. Low risk.
- **Android arm64:** CPU via the NDK is the safe default (same as our llama AAR
  path). GPU is the wrinkle — sd.cpp has no Hexagon/NNAPI backend; Vulkan
  (`-DSD_VULKAN=ON`) is the only mobile GPU option and is the least-tested link.
  **Recommendation: ship Android CPU-only first** (slow but correct — minutes per
  image at small sizes), treat Vulkan as a later optimization PR. Medium risk,
  isolated to a perf knob, not a blocker.

Net: the binding + service + UI is one loop. Android/iOS *device* runs stay
`needs-on-device-verification` in RISKS.md (we proved macOS only here), and the
feature ships **gated OFF under the RAM floor** on day one.

## D5 — Spike artifacts

- `build-macos.sh` — pinned, reproducible macOS/Metal build.
- `spike-evidence-apple-384.png` — the generated proof image.
- `SPIKE.md` — this note.

Clone/model/build tree live in scratch (not committed): ~5 GB, reproducible via
`build-macos.sh` + the model URL above.
