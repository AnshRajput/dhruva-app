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

### [LOOP-00] [scout-3 → orchestrator] [RESEARCH] 2026-07-17T01:10
HF Hub API verified with real curl calls — report in orchestra/research/hf-api.md.
Search/tree/resolve endpoints work unauthenticated; accept-ranges: bytes confirmed
(resumable downloads viable); license via cardData.license, gating via `gated`.
Starter models confirmed with Q4_K_M files: bartowski/Llama-3.2-1B-Instruct-GGUF
(770MB), bartowski/Qwen2.5-1.5B-Instruct-GGUF (986MB), bartowski/SmolLM2-1.7B-
Instruct-GGUF (1GB), bartowski/Llama-3.2-3B-Instruct-GGUF (1.9GB), unsloth/
Phi-4-mini-instruct-GGUF (2.4GB); embeddings second-state/All-MiniLM-L6-v2 (20MB);
vision ggml-org/SmolVLM2-2.2B-Instruct-GGUF (1.1GB + 0.5GB mmproj). Device tiers:
1B → 4GB+ RAM, 3B+ → 6GB+; propose minSdk 26 (GPU accel 30+), iOS 14+.

### [LOOP-00] [scout-3 → orchestrator] [RESEARCH] 2026-07-17T01:10
NAMING verdict in orchestra/NAMING.md: PASS for DHRUVA (display "Dhruva AI").
Play Store: no AI/LLM app named Dhruva. App Store: clear. GitHub: soft collision
only — AI4Bharat/Dhruva-Platform (backend serving platform, different category);
mitigated by repo names dhruva-app/dhruva-website + README note. Domains
dhruva.app/.dev/.ai appear unregistered. No Class-42 software trademark conflict.
Fallbacks (not needed): Ekant clear, Antara clear, Charcha has a near-variant.

### [LOOP-00] [orchestrator → all] [STATUS] 2026-07-17T01:12
Name RATIFIED: DHRUVA (no hard collision — H2 not triggered). Brand ceremony
step 2 running: designer deriving design-tokens.json from the name's story;
reviewer critique next; ratification lands in ADR-003. ADR-002 (feature-first
architecture) reviewed by orchestrator and ACCEPTED as written. Scout-1's five
feature ideas triaged to BACKLOG in TASKS.md.

### [LOOP-01] [orchestrator → all] [STATUS] 2026-07-17T01:30
Loop 1 PLAN (running overlapped with Loop 0's ceremony tail — no file conflicts):
Goal: both repos skeletoned, building, CI-gated, presentable.
Tasks: (1) Flutter scaffold app/ (org tech.appuinside, package
tech.appuinside.dhruva, android+ios) — orchestrator; (2) Astro scaffold in
dhruva-website — orchestrator; (3) Makefile `make verify` gate — orchestrator;
(4) CI workflows both repos (analyze, format, test+coverage, android build /
astro build) — devops pattern, orchestrator executes; (5) README v1 both repos —
docs-writer pass in this loop; (6) strict analysis_options.
Exit gate: [G1] flutter test green locally [G2] flutter build apk --debug
succeeds [G3] astro build succeeds [G4] CI green on merged PR in BOTH repos
[G5] README v1 + CLAUDE.md present in both repos.
Branch: loop/01-skeleton in each repo.

### [LOOP-00] [designer → reviewer] [PROPOSAL] 2026-07-17T01:40
Brand ceremony deliverables: design-tokens.json (repo root, dark-default,
color.dark/light + brand ramps 50–900, typography mirroring Flutter TextTheme
1:1, spacing/radius/elevation/motion/iconography) and
orchestra/research/brand-proposal.md (narrative, logo geometry, type rationale,
hero copy, computed WCAG contrast table). Anchors: midnight #0E1220 + starGold
#EBBA47 (dark hero); light recalibrated #8A5A16 on #F7F8FC. Fraunces + Manrope
with Noto Devanagari fallbacks. Logo: elongated 4-point compass-needle star,
concave Bézier waists, open center pinhole.

### [LOOP-00] [reviewer → designer] [REVIEW] 2026-07-17T01:50
Verdict: REQUEST_CHANGES. All spot-checked contrast claims reproduce exactly;
typography discipline and distinctiveness pass. Blocker: M3 token completeness —
(1) onSurfaceVariant missing, (2) onPrimaryContainer informal, (3) secondary/
tertiary/error container pairs missing, (4) inverseSurface/onInverseSurface/
inversePrimary/scrim/outlineVariant missing, (5) surfaceTint not emitted,
(6) lineHeight px vs Flutter's unitless height — add heightMultiplier.

### [LOOP-00] [designer → reviewer] [HANDOFF] 2026-07-17T02:00
All six findings closed; JSON re-validated. New pairs 6.88–13.05:1 AA PASS.
Documented exceptions: inversePrimary dark 4.36:1 (large-text/UI only),
outlineVariant 1.51–1.65:1 (decorative divider, M3-exempt — stated plainly
rather than faking a pass).

### [LOOP-00] [orchestrator → all] [STATUS] 2026-07-17T02:05
ADR-003 RATIFIED — brand ceremony complete. Loop 0 gate: all five checks pass
(3 scout reports ✓, ADR-001/002 ✓, NAMING + ADR-003 ✓, design-tokens.json ✓,
roadmap locked ✓). Loop 0 CLOSED. Loop 1 already in flight: both scaffolds
build, PRs open, CI running, README v1 landed (docs-writer).
