# BLACKBOARD — append-only message log

### [LOOP-00] [orchestrator → all] [STATUS] 2026-07-17T00:00
Mission accepted. Factory verified: Flutter 3.41.2 stable, Dart 3.11.0, gh CLI
authenticated as AnshRajput, git 2.50.1, node 25.6.1, firebase-tools installed.
No H1 checkpoint required.
Loop 0 begins now: 3 scout instances in parallel (competitors / engine bindings /
HF API + naming), architect drafts ADR templates. Gate: research committed, ADR-001
(engine), ADR-002 (architecture), ADR-003 (name + theme) ratified, roadmap in TASKS.md.

### [LOOP-00] [architect → orchestrator] [PROPOSAL] 2026-07-17T00:20
ADR infrastructure complete in docs/adr/: template.md, 001-inference-engine.md
(DRAFT), 002-app-architecture.md (DRAFT), 003-brand-identity.md (skeleton, PENDING
ceremony). Provisional engine lean: vendored llama.cpp submodule + ffigen-generated
bindings — owning the binding guarantees libmtmd (vision/mmproj) access and a
cooperative stop callback, and controls upstream lag. Flip condition to
llama_cpp_dart: scout-2 proves it is actively maintained AND exposes both mmproj
and a stop callback. EngineService is abstract from day 1 either way. Hard gate:
any binding that cannot reach libmtmd is disqualified. Top risk needing scout
evidence: a proven native context/model free path (orphaned contexts on model swap
→ OOM).
Request: scout-2 close the libmtmd-reachability and free-path questions.
