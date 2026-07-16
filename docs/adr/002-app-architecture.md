# ADR-002 — App architecture: feature-first layering

- **Status:** ACCEPTED (2026-07-17, orchestrator review)
- **Date:** 2026-07-17
- **Deciders:** architect
- **Loop:** 0

## Context

Dhruva is a large single Flutter app spanning nine features (onboarding, models_hub,
chat, characters, voice, vision, toolbox, imagine, docs_chat) over one native
inference substrate. Without an enforced structure, features cross-import each other,
native FFI leaks into widgets, and the codebase becomes untestable. We fix the
layering, dependency direction, and testing floor before feature code starts.

## Options

- **A — Layer-first** (all repositories/, all widgets/, all providers/): familiar,
  but every feature change touches every top-level folder; poor locality.
- **B — Feature-first** (each feature owns its UI + state + local wiring; shared
  concerns in core/ and data/): strong locality, clear ownership, scales to the
  nine features. Chosen.
- **C — Full modular packages** (melos multi-package): maximum isolation, heavy
  tooling + build overhead — YAGNI for a single-team app at this stage.

## Decision

**Feature-first single package (B)** with a fixed dependency direction and an isolated
engine layer. Layout:

```
lib/
  core/            theme, router (go_router), di, device_info (RAM + chip tiering)
  engine_bindings/ FFI surface + isolate workers, behind abstract EngineService
  data/            drift db, repositories, hf_api client, download manager
  features/        onboarding, models_hub, chat, characters, voice, vision,
                   toolbox, imagine, docs_chat  (each: ui/ + state/ + own providers)
```

### Rules

- **Dependency direction:** `features → data → core`. One-way. A feature never imports
  another feature; shared logic moves *down* into data/ or core/. Enforced by a lint /
  import-boundary check in CI, not by convention alone.
- **engine_bindings is isolated.** Nothing imports FFI symbols directly. All access
  goes through the abstract `EngineService` (ADR-001); `data/` depends on the
  interface, `engine_bindings/` provides the implementation via DI. This keeps the
  ADR-001 engine choice swappable and the FFI crash surface contained.
- **State management (Riverpod):** all state in providers; **no business logic in
  widgets.** Widgets read providers and render — a widget may hold ephemeral UI state
  (controllers, focus) only. Repositories are the single source for data; providers
  compose them. No provider reaches into another feature's providers.
- **device tiering in core.** `device_info` reports RAM + chip class; features query it
  (via a provider) to gate model sizes and default context length — one place, not
  scattered heuristics.

### Error taxonomy

Sealed/`freezed` failure types, surfaced as typed results (no raw exceptions across
layers):

- `EngineFailure` — native load/decode/OOM (out-of-memory on model load).
- `StorageFailure` — drift / filesystem.
- `NetworkFailure` — hf_api / download (offline, gated repo, 4xx/5xx).
- `ValidationFailure` — bad user/model input.
- `UnknownFailure` — last resort, always logged.

Repositories map lower-layer errors into this taxonomy; UI maps taxonomy → user
message + recovery affordance (retry, free memory, pick smaller model).

## Testing pyramid

- **Unit** — repositories, providers, mappers, device tiering. The bulk.
- **Widget** — feature screens with mocked providers.
- **Integration** — one happy path per feature over a fake `EngineService` (no real
  native in CI); real-native smoke run manually / on-device.
- **Golden** — key screens + theme (light/dark) to catch visual regressions.
- **Floor:** 70% line coverage on `lib/`, enforced in CI. Below floor = red build.

## Consequences

- **Positive:** feature locality + clear ownership; FFI and engine choice fully
  isolated; testable by construction with a fake `EngineService`; import-boundary lint
  makes the dependency rule mechanical.
- **Negative / accepted cost:** some early boilerplate (abstract service, DI wiring,
  freezed failures) before the first feature feels productive; import-boundary tooling
  must be set up in Loop 1.
- **Follow-ups:** wire the import-boundary lint in CI; define `EngineService` interface
  alongside ADR-001; establish golden-test baseline once theme tokens land (ADR-003).
