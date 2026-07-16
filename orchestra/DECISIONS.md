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
