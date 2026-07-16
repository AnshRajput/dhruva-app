# ADR-001 — LLM inference engine binding

- **Status:** ACCEPTED (rev 1 — flip condition met, Option A chosen; see Decision)
- **Date:** 2026-07-17
- **Deciders:** architect (pending scout-2 evidence)
- **Loop:** 0

## Context

Dhruva runs GGUF LLMs 100% on-device on Android (arm64) and iOS (Metal), with
streaming chat, cooperative cancellation, and vision via llama.cpp `libmtmd`
(mmproj). The binding to llama.cpp is the load-bearing decision: it dictates our
upstream lag, our vision ceiling, and our crash surface. We must pick before any
engine code is written. Choice is reversible only at high cost (FFI surface leaks
into isolate workers and repositories), so we decide deliberately.

## Options

- **A — `llama_cpp_dart`** (pub package): Dart FFI bindings + prebuilt/buildable
  llama.cpp. Fastest start; we inherit the maintainer's release cadence and whatever
  `libmtmd` exposure they choose to surface.
- **B — `fllama`** (Flutter plugin): higher-level, Flutter-native plugin wrapping
  llama.cpp with platform build glue done. Least boilerplate; most opinionated,
  thickest abstraction between us and the C API — cancellation/vision access is
  whatever the plugin allows.
- **C — Vendored llama.cpp submodule + `ffigen`-generated bindings** (own it):
  pin an exact upstream commit, generate Dart bindings from `llama.h`/`mtmd.h`
  ourselves, own the CMake/podspec build. Maximum control and minimum upstream lag;
  we own the build matrix and the maintenance.

## Evaluation criteria

| Criterion | Why it matters | A | B | C |
|---|---|---|---|---|
| Upstream lag | llama.cpp moves daily; mmproj/quant support lands fast | ? | ? | **best** |
| iOS Metal + Android arm64 | non-negotiable target coverage | ? | ? | own it |
| Streaming + cancellation API | token callback + cooperative stop | ? | ? | full |
| `libmtmd` vision access | mmproj embed → decode path must be reachable | **gate** | **gate** | full |
| Memory-management surface | explicit ctx/model free, no leak on unload | ? | ? | full |
| Maintenance risk | who fixes a broken build at 3am | low | low | **on us** |
| License | must stay Apache-2.0-compatible (MIT llama.cpp) | ok | ok | ok |

`?` = **PENDING scout-2**: package version health, last-commit recency, and whether
A/B actually surface `libmtmd` symbols and a stop callback. The vision row is a hard
gate — an option that cannot reach mmproj is disqualified regardless of ergonomics.

## Architecture each implies

- **A / B:** `EngineService` (abstract) → adapter over the package's Dart API. Thin.
  Risk concentrated in whether the package's surface is wide enough; if it isn't, we
  fork it — which collapses into C anyway.
- **C:** `EngineService` → generated `bindings.dart` (ffigen) called from an isolate
  worker; we own `native/` submodule + build scripts. Widest surface, most build work.

## Decision

**Option A — `llama_cpp_dart`, consumed as a git dependency pinned to an exact
commit** (NOT the stale pub.dev release). The draft's flip condition was verified
2026-07-17 by the orchestrator against primary sources:

- **Actively maintained:** last commit 2026-06-18 (github.com/netdur/llama_cpp_dart)
  — "test(tool): add probe_cancel for the cancel-responsiveness regression (#105)",
  which also evidences a working cancellation path.
- **`libmtmd` surfaced:** `lib/src/multimodal/mtmd_bitmap.dart`, `mtmd_chunks.dart`;
  README documents `MultimodalParams(mmprojPath: ...)`, vision+audio via mtmd, and
  mtmd-enabled iOS/Android artifacts (incl. a Hexagon-NPU AAR for Snapdragon).
- **Mobile-first 0.9.x rewrite:** single-active-session, off-thread, iOS/Android
  packaging; llama.cpp vendored as a submodule tracking master.
- **Caveat found:** pub.dev latest is 0.2.2 (2026-01-02) — releases lag the repo,
  hence the pinned git dependency.

Accepted risks: pre-1.0 API drift (mitigated by `EngineService` wrapper),
single-active-session model (acceptable — matches our one-loaded-model UX; Model
Arena in Loop 11 must verify dual-session feasibility or run sequential turns).
**Fallback remains C** (vendor + ffigen) if the API surface blocks a core feature;
the abstraction keeps that flip cheap. B (fllama) is not pursued.

## Isolate / threading model (applies to any option)

- **Never on root isolate.** All model load, decode, and free run on a dedicated
  long-lived inference isolate. UI isolate only sends commands and receives events.
- **Streaming via `SendPort`.** The worker posts each decoded token as a message to
  the UI isolate's port; UI never blocks on native.
- **Cooperative cancellation.** A cancel flag (checked in the token loop / via the
  engine's abort callback) stops generation between tokens — no isolate kill,
  no half-freed native state.
- **One native context per loaded model, one proven free path.** Load → handle held
  by the worker; unload runs the full `free` sequence (ctx then model) and nulls the
  handle. Loading a second model either reuses or explicitly frees the first — no
  orphaned contexts, verified by a load/unload/reload leak check.

## Consequences

- **Positive:** vision + cancellation reachable by construction; upstream lag
  controllable; abstract `EngineService` keeps the choice reversible.
- **Negative / accepted cost (if C):** we own the iOS podspec + Android CMake build
  matrix and ffigen regeneration on upstream bumps.
- **Follow-ups:** scout-2 report closes the `?` rows; spike a load/unload/reload leak
  test as the memory-management proof; ADR-002 depends on `EngineService` shape.
