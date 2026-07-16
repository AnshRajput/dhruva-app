# DECISIONS — orchestrator rulings (ADR-style)

Format per entry: context → options → decision → why. Numbered, append-only.

## ADR-000 — Loop engineering constitution (2026-07-17)
Context: project kickoff per the master prompt.
Decision: PLAN→BUILD→TEST→REVIEW→REFLECT→COMMIT loops; agents talk through
orchestra/ files; 100% local inference (no cloud path, zero telemetry); Apache-2.0
open source from commit #1; trunk-based with loop branches + squash-merge; Firebase
for build distribution only. GitHub owner: AnshRajput. Creator identity:
Appu Inside Engineering.
Why: mandated by the master prompt; recorded here so every agent inherits it.

## ADR-001 — Inference engine binding: llama_cpp_dart @ pinned git commit (2026-07-17)
Context: architect drafted options (A llama_cpp_dart / B fllama / C vendored+ffigen)
with a flip-to-A condition; scout-2 recommended A but hallucinated pub.dev version
numbers, so the orchestrator re-verified against primary sources.
Decision: Option A, consumed as a git dependency pinned to an exact commit of
github.com/netdur/llama_cpp_dart (0.9.x mobile rewrite). Evidence: repo active
(2026-06-18), libmtmd/mmproj multimodal surfaced in lib/src/multimodal/ + README,
cancel-responsiveness regression test present, iOS Metal + Android arm64 (+Hexagon
NPU AAR). pub.dev release (0.2.2, Jan 2026) is stale — do NOT depend on it.
Why: meets the drafted flip condition; saves the build-matrix ownership cost of C.
EngineService stays abstract; fallback to C stays cheap. Full detail: docs/adr/001.
Lesson recorded: scout (haiku) version claims MUST be orchestrator-verified against
pub.dev/GitHub APIs before ratification.

## ADR-002 — App architecture: feature-first single package (2026-07-17)
Context: architect's draft; orchestrator reviewed.
Decision: ACCEPTED as written (docs/adr/002): features → data → core one-way
dependency; engine_bindings isolated behind abstract EngineService; Riverpod
providers only (no logic in widgets); freezed failure taxonomy; testing pyramid
with 70% coverage floor; import-boundary lint wired in Loop 1 CI.
Why: strong locality across nine features; keeps ADR-001 swappable; melos
multi-package rejected as YAGNI.

## NAMING — DHRUVA ratified (2026-07-17)
Context: scout-3 dossier (orchestra/NAMING.md): no hard store or trademark
collision; GitHub soft collision (AI4Bharat/Dhruva-Platform, different category).
Decision: DHRUVA stands; store display name "Dhruva AI"; repos dhruva-app /
dhruva-website; README carries a one-line disambiguation from AI4Bharat's
platform. H2 not triggered; fallbacks unused. Formal ratification in ADR-003
with the design tokens.

## DEVICE FLOOR (2026-07-17)
Decision: minSdk 26 / target latest, iOS 14+. Catalog tiers: 1B → 4GB+ RAM,
3-4B → 6GB+; tiering logic in core/device_info per ADR-002.
Why: scout-3 device research; llama.cpp GPU accel needs API 30+/iOS 14 Metal —
older devices fall back to CPU tiers.

## ADR-003 — Brand identity ratified (2026-07-17)
Context: ceremony ran per protocol — scout-3 verification (PASS, no hard
collision), designer derivation from the pole-star story, reviewer critique
(REQUEST_CHANGES on M3 completeness), designer fix pass.
Decision: DHRUVA / "Dhruva AI"; design-tokens.json at repo root is the single
canonical brand source for app AND website. Palette midnight+starGold (dark
hero); Fraunces+Manrope with Devanagari fallbacks; compass-needle star logo.
Two documented contrast exceptions (inversePrimary dark = large-text only;
outlineVariant = decorative, M3-exempt). Full detail: docs/adr/003.

## ENGINE PIN — llama_cpp_dart commit (2026-07-17, Loop 2)
Decision: pin llama_cpp_dart git dependency to commit
c6e37785835a189261fab28e53386e4e954f3e42 (main HEAD as of 2026-07-17).
Upgrades are their own PR with before/after benchmark numbers (per
native-engine charter). macOS added as a dev-only platform target so real
inference is verifiable on the build machine; release targets remain
Android + iOS only.
