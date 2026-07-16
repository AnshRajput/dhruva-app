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
