# Architecture

← [Knowledge Base](README.md)

Full decision records live in [`adr/`](adr/); this is the working map.

## Layers (feature-first)

Dependency direction is one-way — `features → data → core` — with **no cross-feature
imports**. This keeps the [privacy contract](privacy.md) enforceable: only `data/`
touches the network.

```
app/lib/
  core/              theme, router, di, device_info, model tiers
  engine_bindings/   EngineService abstraction over llama_cpp_dart (FFI)
  data/              drift (SQLite), repositories, hf_api, downloads
  features/          onboarding, models_hub, chat, characters, voice,
                     vision, playground, settings
  main.dart
```

Rules of the road (see [ADR-002](adr/002-app-architecture.md)):

- No business logic in widgets — it lives in Riverpod notifiers.
- **Inference, downloads, and embeddings never run on the root isolate.**
- Every color and text style derives from `design-tokens.json`; hardcoded colors
  are treated as bugs.

## The engine

- [`llama_cpp_dart`](adr/001-inference-engine.md) as a git dependency pinned to an
  exact commit (not the stale pub.dev release), bound over FFI.
- **Vision** via `libmtmd` / `mmproj` projector files.
- Inference runs off the root isolate so the UI never blocks during generation.
- In-app navigation persistence: generation continues while you move between
  screens within the app. True background-while-minimised generation needs a native
  foreground service and is tracked in [`RISKS.md`](../orchestra/RISKS.md) (R12).

## State, persistence, navigation

| Concern | Choice |
|---------|--------|
| State | **Riverpod** (`AsyncNotifierProvider.autoDispose` + `KeepAliveLink`) |
| Persistence | **Drift** (SQLite) — conversations, characters, model registry |
| Navigation | **go_router** (`StatefulShellRoute` for the tab shell) |
| Models (data classes) | **freezed** |
| Downloads | **background_downloader** (Android WorkManager foreground service) |
| HTTP (HF API) | **dio** |
| Voice | **sherpa_onnx** (STT / TTS / Silero VAD) |

## Downloads on Android 14+

The download foreground service needs `FOREGROUND_SERVICE` +
`FOREGROUND_SERVICE_DATA_SYNC` permissions **and** the service must declare
`android:foregroundServiceType="dataSync"`. Both halves are required — permissions
alone still crash on API 34+. This was the v0.2.2 crash regression; the fix and its
lesson are recorded in [`../orchestra/VIDEO_FIXES.md`](../orchestra/VIDEO_FIXES.md)
and the [Development doc](development.md#test-on-device-before-every-deploy).

## Device tiers

`classifyModelTier(fileSizeBytes, totalRamBytes)` maps a model file + the device's
RAM to `comfortable` / `possible` / `notRecommended`, which drives the curated
catalog's "Runs great on your phone" vs. "Larger models" split. See
[Models](models.md#device-tiers).
