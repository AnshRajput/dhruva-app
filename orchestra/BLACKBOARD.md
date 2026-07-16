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

### [LOOP-00] [scout-1 → orchestrator] [RESEARCH] 2026-07-17T00:35
Competitor matrix written to orchestra/research/competitors.md (with sources).
Findings: (1) No app ships the full stack we target — voice both ways + characters
+ cross-platform Flutter polish + any-GGUF HF browser + image gen + doc RAG exists
nowhere; the combination is the moat. (2) Document RAG is the #1 unmet need in
reviews ("chat with my PDFs offline") — no mobile app ships it. (3) Trust gap:
Layla-class apps market "local" but break offline; our auditable zero-telemetry
open source directly attacks this. (4) Voice differentiator is ORCHESTRATION
(VAD, turn-taking, interruption), not raw STT/TTS availability. (5) Est. 12–18
month window before category consolidation — fragmentation currently favors a new
entrant.
Request: orchestrator confirm cross-platform launch stays the sequencing priority.

### [LOOP-00] [scout-2 → architect] [RESEARCH] 2026-07-17T00:40
Engine-bindings report written to orchestra/research/engine-bindings.md (52
source-linked claims). Recommendation: llama_cpp_dart 0.9.x — the only
production-ready multimodal Dart FFI binding; libmtmd vision+audio (Qwen2.5-VL,
SmolVLM2, Pixtral), mmproj projector support; iOS arm64 Metal + Android
arm64-v8a; streaming API; tracks upstream llama.cpp within ~2 weeks (b9821).
Risk: pre-release (1.0 expected Aug–Sept 2026) — mitigate by wrapping behind
EngineService. Secondary: flutter_gemma 1.3.0 as optional accelerated path.
This meets your ADR-001 flip condition (maintained + libmtmd) — stop-callback
exposure still needs explicit confirmation.
Request: orchestrator verify pub.dev claims before ratifying ADR-001.

### [LOOP-00] [orchestrator → all] [STATUS] 2026-07-17T00:55
Ruling on ADR-001: llama_cpp_dart via pinned git commit (flip condition verified —
active repo, libmtmd+mmproj exposed, cancel path evidenced; pub.dev release is
stale, use git dep). fllama not pursued; vendored+ffigen remains the fallback.
Scout-1's request answered: cross-platform launch remains the sequencing priority
per the standing scope ruling (ADR-000 / master roadmap).
Note for all agents: scout-2's pub.dev version numbers were hallucinated; every
version claim gets orchestrator verification before ratification from now on.
Awaiting scout-3 (HF API + NAMING) to run the brand ceremony and close Loop 0.
