# Dhruva — agent context

Open-source Flutter app (Android + iOS) that runs AI models 100% on-device:
chat, characters, vision, image generation, voice, document RAG, one-tap
toolbox. Zero telemetry; the ONLY permitted network calls are user-initiated
model downloads from Hugging Face. Apache-2.0. Creator: Appu Inside
Engineering. Display name: "Dhruva AI".

## Non-negotiables

- 100% local inference. No cloud path, no fallback, no analytics SDKs, ever.
  Firebase is used ONLY for distributing builds — never inside the app.
- Real over fake: nothing is "done" until `flutter analyze` is clean, tests
  pass, and QA signs off on the blackboard. Unverifiable-on-this-machine
  behavior goes to orchestra/RISKS.md as "needs on-device verification".
- Every agent reads orchestra/BLACKBOARD.md, orchestra/DECISIONS.md, and this
  file before working, and posts a typed report to the blackboard after
  (format: orchestra/PROTOCOL.md).

## Locked stack (see orchestra/DECISIONS.md + docs/adr/)

- Engine: `llama_cpp_dart` as a git dependency pinned to an exact commit
  (ADR-001). NOT the stale pub.dev release. Vision via libmtmd/mmproj.
  Fallback if surface blocks us: vendored llama.cpp + ffigen.
- Architecture: feature-first (ADR-002). `lib/`: core/ (theme, router, di,
  device_info), engine_bindings/ (behind abstract EngineService), data/
  (drift, repositories, hf_api, downloads), features/ (onboarding,
  models_hub, chat, characters, voice, vision, toolbox, imagine, docs_chat).
  Dependency direction: features → data → core, one-way, no cross-feature
  imports. Inference/downloads/embeddings never on the root isolate.
- State: Riverpod (no logic in widgets) · Persistence: Drift · Nav:
  go_router · Downloads: background_downloader · Models: freezed.
- Theme: every color/text style derives from design-tokens.json (repo root).
  Hardcoded colors are bugs.
- Device floor: minSdk 26, iOS 14+. Model tiers: 1B → 4GB+ RAM, 3-4B → 6GB+.
- Voice: whisper.cpp/sherpa-onnx STT, sherpa-onnx TTS (verify in Loop 6).
- Image gen: stable-diffusion.cpp (verify in Loop 8).

## Commands

- `make verify` — full local gate (analyze + format check + tests). Run
  before every HANDOFF. (Wired in Loop 1.)
- `flutter test --coverage` — coverage floor 70% on lib/.
- Work happens in `app/` (Flutter project root).

## Process

Loops: PLAN → BUILD → TEST → REVIEW → REFLECT → COMMIT (orchestra/PROTOCOL.md).
Branch `loop/<nn>-<slug>`, PR, reviewer verdict on blackboard, squash-merge.
Conventional commits. CI green before merge, no exceptions.

## Current status

Loops 0–3 CLOSED: engine online (EngineService over pinned llama_cpp_dart,
proven free paths), model manager + HF hub shipped (browse/verdicts/resumable
verified downloads/import). Real site live at anshrajput.github.io/
dhruva-website (Loop 12 build-ahead). Firebase project dhruvaai-68a00 staged.
SCOPE AMENDMENT 1: Loop 10.5 (model playground + opt-in AI news), designer
gate BLOCKING from Loop 4. Loop 4 IN PROGRESS: chat experience (MVP-closer) —
markdown+code rendering, streaming with tok/s, drift history, folders/search,
system-prompt editor, sampling settings, regenerate/edit, export, reasoning-
token transparency. iOS floor 14.0 (build config matches DECISIONS).
