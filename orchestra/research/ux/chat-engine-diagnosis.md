# Chat-engine diagnosis — "can't start a convo" / "chat not replying"

Scope: shipped `v0.1.0-alpha` (tag `92e5b12`, versionName `1.0.0+1`, distributed
to internal testers via Firebase App Distribution). Investigated on branch
`loop/ux-hardening` off main = the exact shipped code. READ-ONLY on `lib/`.

## What I verified (so we stop suspecting the wrong things)

- **Desktop path works end-to-end.** Ran the real-engine chat test against the
  real `LlamaEngineService` + real SmolLM2-135M GGUF on macOS
  (`flutter test test/features/chat/state/chat_controller_real_engine_test.dart`
  with `LLAMA_CPP_DART_LIB`/`DHRUVA_TEST_MODEL` pointing at `.dev-native/`) →
  **model loads, tokens stream, `All tests passed`.** So `ChatController` →
  `engine.generate` → stream → UI is functionally correct. The break is NOT in
  the controller or the streaming machinery.
- **The AAR is wired and the .so ARE in the shipped APK.** Built
  `flutter build apk --release` from the tagged code (148.8 MB). Unzipped:
  `lib/arm64-v8a/{libllama,libggml,libggml-base,libggml-cpu,libmtmd}.so` are all
  present. So `implementation(files("libs/llama-cpp-dart.aar"))` DID merge the
  native libs (the classic `files(aar)` gotcha did NOT bite here). R10's ".so in
  APK proven" holds.
- **The .so dependency chain is self-contained.** Parsed DT_NEEDED of every
  AAR `.so`: they only need each other + `libm/libdl/libc` (no `libc++_shared`,
  no `libomp`). So on an arm64 device dlopen-by-basename should resolve the whole
  chain from the app's native lib dir. `LlamaLibrary.load(path:'libllama.so')`
  (basename mode) is correctly implemented for Android
  (`.pub-cache/.../ffi/library_loader.dart:90-170`).
- **INTERNET permission is present** in the shipped main manifest (hotfix `#5`,
  `55da421`), so model downloads can reach Hugging Face.
- **Errors ARE surfaced, not swallowed.** `_onError`
  (`chat_controller.dart:832`) finalizes the message as `MessageStatus.error`
  and the thread renders a `ChatErrorCard`; model-load failures render a card
  too (`chat_thread_screen.dart:252`). A load failure would show an error, not
  silence.

---

## ROOT CAUSE #1 (functional bug, explains "not able to start a convo") — HIGH confidence

**`installedModelsProvider` is a plain `FutureProvider` that is NEVER invalidated
after a model download completes, so a freshly-downloaded model is invisible to
the entire chat flow until the app is force-restarted.**

Evidence:
- `lib/features/chat/state/installed_models_provider.dart:12` — declared as a
  bare `FutureProvider` (NOT `.autoDispose`). Once first read it is cached for
  the whole app session and never recomputed.
- Repo-wide grep for `invalidate(installedModelsProvider)` /
  `refresh(installedModelsProvider)` → **zero hits.** Nothing invalidates it.
- Download completion writes the DB row (`download_manager.dart:393`
  `_db.upsertInstalledModel(...)`) but does **not** touch the provider.
- Every chat entry point reads this stale provider:
  - `conversation_list_screen.dart:53` `_startNewChat` →
    `ref.read(installedModelsProvider.future)` → sees empty → `if (models.isEmpty) context.push('/models')` (bounces the user back to the model browser).
  - `conversation_list_screen.dart:75` decides the empty-state (`New chat` vs
    `Browse models`).
  - `model_picker_sheet.dart:57` `ref.watch(installedModelsProvider)` — the
    picker shows an empty list too.
- The Models-hub Storage screen uses a DIFFERENT, fresh provider
  (`storage_controller.dart:32/49`, its own `AsyncNotifier` reading
  `manager.listInstalledModels()`). **So the hub shows the model as "installed"
  while chat insists there are none** — the exact "I have a model but I can't
  start a chat" report.

Repro (matches the user, no device needed):
1. Fresh install → open app (Chats tab watches `installedModelsProvider` → caches
   empty).
2. Go to Models hub, download a model → completes, DB row written, Storage screen
   shows it installed.
3. Back to Chats → tap the `+` FAB (New chat) → silently bounced to `/models`
   again. Tap a draft's model chip → picker is empty. Composer stays hidden
   (`chat_thread_screen.dart:301` gates the composer on `state.model != null`).
4. User is stuck in a loop. **Only a full app kill + relaunch** (which rebuilds
   the provider from the DB) makes the model appear.

Minimal fix (ponytail): invalidate the provider when a download completes. One
line at the completion site — after `upsertInstalledModel` in
`download_manager.dart`, have whatever Riverpod-scoped code observes
`DownloadState.complete` call `ref.invalidate(installedModelsProvider)`. Cleanest
seam: the models-hub download-actions controller already reacts to completion —
add `ref.invalidate(installedModelsProvider)` there. Belt-and-suspenders (and
even lazier): also mark the provider `.autoDispose` so it re-reads the DB each
time the chat screen re-subscribes — but autoDispose alone does NOT fix the case
where the chat screen stays mounted, so the invalidate-on-complete is the real
fix.

How to test: widget/integration test — seed zero models, watch
`installedModelsProvider` (empty), simulate a `DownloadState.complete` that
upserts a row, assert `installedModelsProvider` now returns the model WITHOUT a
container restart. On device: download a model, tap New chat, confirm the picker
lists it without killing the app.

---

## ROOT CAUSE #2 (Android-only, explains "chat not replying" post-restart) — the R10 residual, UNVERIFIABLE here

Once a model is actually selectable (i.e. after the app restart that works around
#1), the reply depends on the on-device engine path, which has **never been
exercised on a physical device** (R10 residual: "real dlopen+inference with a
downloaded GGUF on physical device UNVERIFIED"). Two concrete sub-risks:

### 2a. ABI packaging defect — the llama engine ships arm64-v8a ONLY, but the APK is a universal multi-ABI APK.
- APK contains `lib/arm64-v8a/`, `lib/armeabi-v7a/`, `lib/x86_64/`
  (the 32-bit + x86 ABIs come from `sherpa_onnx`/voice, which ship all three).
- The llama `.so` exist under **`arm64-v8a` only** (that's all the AAR carries).
- Android extracts native libs for the device's single primary ABI at install.
  On a device/emulator whose primary ABI resolves to `armeabi-v7a` or
  `x86_64`, `DynamicLibrary.open('libllama.so')` throws (no libllama for that
  ABI) → `EngineLoadFailure` → error card, never a reply.
- Modern arm64 phones are FINE (primary ABI = arm64-v8a → libllama present).
  This bites **x86_64 emulators** (common QA path — "emulator install smoke
  green" but dlopen never tried there) and **32-bit-only devices**. If the
  tester used an emulator or a budget 32-bit phone, this is the direct cause.
- Fix (ponytail): pin `ndk { abiFilters += "arm64-v8a" }` in
  `android/app/build.gradle.kts` so the APK is arm64-only — the app then only
  installs where the engine can actually run, and the dead 32-bit/x86 sherpa
  libs stop bloating the APK. (Proper long-term: per-ABI split / app bundle so
  Play delivers the right slice, plus arm64 is the only ABI the engine supports
  anyway.) Test: `unzip -l app-release.apk | grep lib/` shows only arm64-v8a;
  install on the target device and confirm.

### 2b. Genuine on-device load/inference has not been proven on real ARM hardware.
Static analysis says it should work (chain is self-contained, basename dlopen is
correct, `ggml_backend_load_all()` is the right call on the basename path). But
"should" is not "does". Two failure shapes to watch for on device:
- **Load throws** → surfaces as a `ChatErrorCard` (visible error, the user might
  describe as "not replying").
- **Silent no-reply** → if `session.generate` yields zero tokens (bad/absent
  chat template for the specific GGUF, immediate EOG) or hangs, the UI sits on
  `awaitingFirstToken == true` forever showing the typing indicator, or renders
  an empty assistant bubble after an empty completion. **This is the true
  "chat not replying" with no error.** Not reproducible without the device +
  the actual GGUF the tester downloaded.

How to test (REQUIRES the physical device): install the arm64 build, download a
small GGUF (SmolLM2-135M), send a message, and capture `adb logcat` for the
`dhruva.engine.worker` isolate — look for the llama.cpp load banner + whether
tokens flow or a `_ErrorMsg` crosses the isolate boundary. This is the one item
that genuinely cannot be closed from this machine.

---

## Secondary / UX polish (not the headline, but worsens "can't start")

- **First-run has no onboarding + a misleading empty state.**
  `conversation_list_screen.dart:76` `hasAnyModel = modelsAsync.value?.isNotEmpty
  ?? true` defaults to `true` while the provider loads, so the first paint shows
  "Start your first conversation / New chat" even with zero models. Tapping
  New chat then silently bounces to `/models` with no toast/explanation. Even
  independent of bug #1, a first-time user sent to download a several-hundred-MB
  model with no framing reads as "I can't start a conversation." Recommend a
  one-line explanatory snackbar on the bounce ("Download a model first to start
  chatting") and/or defaulting `hasAnyModel` to `false` while loading so the
  correct "No model installed → Browse models" CTA shows first.

## Ranking summary
1. **`installedModelsProvider` stale cache (never invalidated)** — definite bug,
   trivial fix, directly = "downloaded a model, still can't start a convo."
2. **ABI: arm64-only engine in a universal APK** — definite defect, bites
   non-arm64 devices/emulators = "chat not replying" (load failure). One-line
   gradle fix.
3. **On-device dlopen/inference unverified (R10 residual)** — cannot close
   without the physical device; silent-no-reply is the shape to hunt in logcat.
4. First-run UX friction — makes #1 feel worse; low-effort copy fix.
