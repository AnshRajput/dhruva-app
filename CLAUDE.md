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
- **Real value, not a playground.** This is a product a human relies on, not a
  demo. The whole point is that it solves a real problem / use case and delivers
  value — that value must be made explicit both ON THE WEBSITE and INSIDE THE
  APP, not just implied. Every core path (download → install → chat, voice,
  vision, imagine) must work end-to-end on a real device, not just in unit
  tests. A feature that only passes tests but crashes or dead-ends on-device is
  NOT done. The final product must be superb, end-to-end complete, and usable.
- **Test on-device before EVERY deploy.** No build reaches Firebase until the
  changed path is verified working by the orchestrator in the emulator/device.
  Shipping an untested build that crashes (see orchestra/VIDEO_FIXES.md, the
  0.2.2 foreground-service crash) is the failure mode this rule exists to stop.
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

**v0.1.0-alpha SHIPPED** (2026-07-17). Loops 0-7 closed (0 research · 1 skeleton · 2 engine · 3 model-hub · 4 chat/MVP
· 5 characters · 6 voice · 7 vision). Plus a UX-HARDENING loop (v0.2.0) fixing
the on-device regressions the human found (invisible-model, version discipline,
download UX, discovery). Website live (Vercel + Pages). Every loop ships
app→FAD + web. Next: Loop 8 (image generation, stable-diffusion.cpp). Remaining:
8 imagine · 9 docs-RAG · 10 toolbox · 10.5 playground+AI-news · 11 polish+arena
· 12 website-gate · 13 distribution-CI (H3/H4) · 14 hardening+handover. CI pins
Flutter 3.41.2. OPEN: human retest of v0.2.0 on-device (does chat reply?).