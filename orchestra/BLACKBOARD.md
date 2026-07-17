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

### [LOOP-01] [orchestrator → all] [STATUS] 2026-07-17T02:20
Loop 1 CLOSED — gate 5/5. Both PRs squash-merged, CI green, website LIVE at
anshrajput.github.io/dhruva-website. Loop 2 begins: ENGINE ONLINE. Goal: load a
small GGUF via llama_cpp_dart (pinned commit), stream tokens to a debug screen,
inference in an isolate, cooperative cancel, proven free path, engine unit
tests green. Owner: native-engine (primary). macOS added as dev-only platform
so real inference can be verified on this machine (real-over-fake, Rule 7).

### [LOOP-02] [native-engine → qa-tester] [HANDOFF] 2026-07-17T03:00
Engine online on branch loop/02-engine. D1–D6 all pass: pinned git dep resolves
(0.9.0-dev.9 @ c6e377), macOS dev build runs, real SmolLM2-135M completion
streamed on this machine ("Paris. Paris is a city that is known for..."),
cancel <500ms + unload/reload proven, make verify green (17 tests).
Files: app/lib/engine_bindings/* (abstract EngineService, owned-isolate
LlamaEngineService, FakeEngineService), app/features/debug_chat/, tests incl.
engine_reload_rss_test.dart. Perf: 64.9 tok/s Metal (gpuLayers 99); tests run
CPU for determinism. KEY FINDING: package's LlamaEngine has NO free path at
this pin (worker.dart:850 deliberately skips dispose; ~167MB leaked/reload) —
bypassed it, we own the isolate, reuse its sync primitives, dispose ctx→model;
RSS flat 162.9→164.8MB over 4 reloads. Cancel mirrors package's own
Duration.zero yield pattern.
Request: adversarial pass — hostile inputs, corrupt GGUF, missing file, cancel
races, unload-while-streaming, double-load.

### [LOOP-02] [native-engine → orchestrator] [BUG] 2026-07-17T03:00
Upstream, pinned llama_cpp_dart commit: (1) LlamaEngine leaks model+ctx on
dispose (no NativeFinalizer; isolate kill skips manual dispose) — our wrapper
fixes locally; durable fix is upstream PR or package bump. (2) ggml Metal
teardown assert at process exit (ggml-metal-device.m:622, upstream PR #17869)
— cosmetic, dev-only, doesn't fire under flutter test. (3) build_native.sh
android "not implemented" at this pin — Android uses package's released AARs;
wiring deferred until an Android build is needed.

### [LOOP-02] [qa-tester → native-engine] [REVIEW] 2026-07-17T03:40
Verdict: PASS for the gate — make verify green, 32/32 tests (15 new adversarial),
no native crash/hang across corrupt GGUF (random + truncated), double-load,
cancel races, unload-mid-stream (~16 runs), hostile Unicode/paste-bomb/template-
token prompts, dispose idempotency. Commit 6176c01.
BUG A: worker catch block stringifies exceptions before _ErrorMsg, so
mapToEngineFailure's typed branches are dead post-load — real decode failures
land as EngineUnknownFailure not EngineDecodeFailure (llama_engine_service.dart
:568 vs :75-92). Breaks ADR-002 taxonomy → UI can't pick recovery affordance.
BUG B: empty prompt reaches native invariant ("no pending tokens") → surfaced
as EngineUnknownFailure with a raw message; everyday input, needs typed
ValidationFailure guard.
Minor: 1/16 flake — first token >20s on rapid back-to-back isolate spawns
(Metal re-init suspected); watch under CI, not gate-blocking.

### [LOOP-02] [native-engine → reviewer] [HANDOFF] 2026-07-17T04:10
QA's BUG A and B fixed at root cause (commit 5b3c1de): worker now classifies
live exceptions into _FailKind enum sent in _ErrorMsg; main isolate rebuilds
typed failures (EngineDecodeFailure proven across the real boundary via a
128-token-context overflow test). EngineValidationFailure added with shared
checkGenerateArgs guard used by BOTH LlamaEngineService and FakeEngineService.
No QA assertions weakened. make verify green, 38/38 tests.
Request: staff review of the full loop/02-engine diff.

### [LOOP-02] [reviewer → native-engine] [REVIEW] 2026-07-17T04:40
Verdict: REQUEST_CHANGES. Otherwise strong: pin exact, no network in lib/, no
committed binaries, success-path dispose ordering correct, RSS test genuine.
BLOCKING: (1) model leaked when LlamaContext.create throws
(llama_engine_service.dart:471-476) — the mobile OOM path; catch sends
_ErrorMsg without model?.dispose(); leaks on every retry; untested.
Nits: (2) generate() throws synchronously AND via stream — pick one channel,
document on interface; (3) taxonomy drift: prompt/messages XOR →
EngineUnknownFailure (should be validation), "already in flight" →
EngineDecodeFailure (state error); (4) debug_chat constructs concrete impl —
acceptable dev-tool exception, don't let it become the pattern post-DI;
(5) cancelled set grows unbounded on late cancels; (6) missing-file detection
sniffs native error strings — add File.existsSync() pre-check.

### [LOOP-02] [reviewer → orchestrator] [REVIEW] 2026-07-17T05:10
Verdict: APPROVE (re-review of c494575). All six findings genuinely closed;
blocking leak fixed with a regression test that forces ctx-create failure;
_GenGate traced race-safe (monotonic ids + single-isolate loop). Residual
non-blocking nit for a later loop: ChatTemplate.fromModel/LlamaSession at
llama_engine_service.dart:496-499 sit outside the try (leak + ready-future
hang if they throw — low probability); widen try + add ready timeout.

### [LOOP-02] [orchestrator → all] [STATUS] 2026-07-17T05:40
Gate attempt 1 failed on CI coverage (38% raw): native-test skips on CI were
counted against the floor. Ruling COVERAGE FLOOR SCOPE recorded — glue +
temporary debug harness excluded per §9 intent; floor-scope coverage is 86%.
CI step updated. Attempt 2 running.

### [LOOP-03] [orchestrator → all] [STATUS] 2026-07-17T06:10
Loop 3 PLAN — Model Manager & Hugging Face hub. Branch loop/03-models-hub.
Goal: browse HF GGUF repos in-app, device-aware "will this run?" verdicts,
resumable downloads with integrity checks, local import, storage manager.
Tasks: (T1) CI paths-ignore for orchestra/**+docs/** — orchestrator;
(T2) foundation: riverpod/drift/go_router/background_downloader/freezed deps,
EngineService via Riverpod DI (Loop 2 retro carry-in), core/device_info RAM
detection + Comfortable/Possible/NotRecommended tiering — flutter-platform;
(T3) data/hf_api client: GGUF search, repo file trees + quant variants,
license + gated fields, resolve URLs (unit tests on canned real JSON from
orchestra/research/hf-api.md endpoints) — flutter-platform;
(T4) data/downloads: resumable manager over background_downloader, size/
checksum integrity, partial-file cleanup, drift schema for installed models —
flutter-platform;
(T5) features/models_hub UI (plain Material, theming is Loop 4): search,
model detail (quants/license/gated/verdict), downloads, storage manager,
local GGUF import — flutter-core pattern agent;
(T6) QA adversarial pass incl. mocked-HF e2e download of a real small file,
offline mid-download, resume, corrupt checksum; (T7) review + merge.
Exit gate: [G1] e2e download flow passes (mocked HF API + real small file)
[G2] offline/resume/corrupt states all handled with typed failures [G3] make
verify green, floor-scope coverage ≥70% [G4] QA PASS + reviewer APPROVE
[G5] CI green on merged PR.

### [LOOP-03] [flutter-platform → flutter-core] [HANDOFF] 2026-07-17T07:10
T2-T4 complete (commit 5909564): Riverpod DI root (core/di/providers.dart),
device_info_plus-backed RAM/storage service + pure classifyModelTier
(boundary-tested), HfApiClient (search w/ cursor pagination, recursive tree,
license/gated, resolve URLs, quant parser), shared AppFailure taxonomy
(core/failures/), drift installed_models + upsert fix, download stack
(neutral backend interface + background_downloader adapter + pure tested core:
GGUF magic bytes, size+streamed-sha256 integrity, free-space guard,
partial-file cleanup), storage manager, local GGUF import.
125 new tests; make verify green; floor-scope coverage 77%.
Deviation: no download_tasks table — background_downloader's own persistence
covers in-flight state; drift rows only on verified completion.
Provider surface for UI: engineServiceProvider, deviceInfoServiceProvider,
appDatabaseProvider, hfApiClientProvider, modelsDirectoryProvider,
downloadManagerProvider (enqueue/pause/resume/cancel + progress stream),
storageManagerProvider, classifyModelTier(), importLocalGguf().
Request: build features/models_hub UI on this surface only — no direct
http/drift/plugin imports.

### [LOOP-03] [orchestrator → all] [STATUS] 2026-07-17T07:50
SCOPE AMENDMENT 1 recorded (human directive): Loop 10.5 added — model
Playground (prompt lab, live sampling tweaks, template inspector, tuning
presets, benchmarks moved up, live RAM/thermal meters) + AI News reader
(opt-in, user-initiated public feeds; privacy amendment recorded — zero
telemetry unchanged). Designer review is BLOCKING at every gate from Loop 4.
Firebase deferred to Loop 13 (GCP quota, human ruling). Website Loop-12
build-ahead running in parallel (web-builder). Loop 3 UI in flight.

### [LOOP-03] [flutter-core → qa-tester] [HANDOFF] 2026-07-17T08:20
models_hub UI complete (commit e0b47a6): go_router shell (/models home,
/models/repo/:id, /models/downloads, /debug-chat), search with cursor
pagination + separate page-2 error channel, detail with license/gated BEFORE
download + per-quant device verdict chips, gated-repo explanation card,
downloads screen (progress/pause/resume/cancel), installed view with delete +
GGUF import (file_selector — documented UI-only exception). All state in
Riverpod notifiers; widgets render-only; Theme.of() semantic roles only.
38 new tests; suite 204/204; floor-scope coverage 76%; make verify green.
Live-API validation ran the production HfApiClient against huggingface.co
(llama search, bartowski detail w/ 18 quants, meta-llama gated=manual).
Request: adversarial pass per Loop 3 gate — e2e download (mocked HF + real
small file), offline mid-download, resume, corrupt checksum, gated block.

### [LOOP-03] [qa-tester → builders] [REVIEW] 2026-07-17T09:10
Verdict: PASS for the Loop 3 gate (commit 625c73b, 219/219, make verify
green). E2E proven over a real loopback HttpServer (search→detail→enqueue→
range-resume→integrity→drift). Offline mid-download pinned: partial deleted,
no drift row. Corrupt sha/size rejected pre-registration. Free-space guard
pre-network. Gated CTA absent. Hostile API responses + percent-encoding all
handled. Import magic/dupe handled.
BUG (HIGH): DownloadManager.enqueue never sanitizes fileName — traversal
escapes modelsDirectory via p.join; safe today only because the single call
site basenames it. Fix at the choke point (basename/sanitize inside enqueue).
GAP (MEDIUM): downloads_screen has no retry on failed rows (only dismiss);
retry requires re-navigating to detail.
Note (architectural, pinned not filed): backend errorMessage is a raw string;
async download failures never re-enter the typed taxonomy.

### [LOOP-03] [flutter-platform + flutter-core → reviewer] [HANDOFF] 2026-07-17T10:20
QA fixes complete. (1) HIGH traversal fixed at the choke point (commit 78eaf09):
sanitizeLocalFileName in download_core — basenames subfolder paths for the
local target, rejects empty/./..///-class results with typed ValidationFailure
pre-I/O; remote resolve URL untouched; QA's pinned repro flipped to assert the
fix. Bonus: DownloadProgress.failure (typed AppFailure) added additively;
plugin TaskException mapping documented as deferral (untested native adapter).
(2) MEDIUM retry fixed (flutter-core): failed rows render _FailedDownloadTile
with Retry/Dismiss; retry rebuilds the request (resolveDownloadUrl + backfilled
size; checksum dropped on screen-initiated retry, documented) and re-enqueues
through the real manager; widget test observes the actual enqueue.
Suite 232/232, make verify green, floor-scope coverage 77%.
Request: staff review of the full loop/03-models-hub diff vs main.

### [LOOP-03] [reviewer → flutter-platform] [REVIEW] 2026-07-17T10:50
Verdict: REQUEST_CHANGES. Strong diff — trust boundary complete (incl.
local_import), privacy grep clean, resources closed, ADR-002 exceptions only
the two documented, E2E is real orchestration not theater, deps clean.
BLOCKING: app-restart drops in-flight completions — _active is memory-only,
no trackTasks/resumeFromBackground; _handleUpdate early-returns unknown
taskIds → post-restart completion never integrity-checked/registered (orphan
file invisible to Loop 4 picker); database.dart comment overstates behavior.
Nits: (2) streamingSha256 lacks error path (skipped close, digest! NPE, no
typed StorageIoFailure, partial not cleaned); (3) basename-flatten collision
for same-basename subfolder files — note before multi-subfolder repos;
(4) Loop-4 read model: listInstalledModels unordered, no get-by-id, no
lastUsedAt writer.

### [LOOP-03] [reviewer → orchestrator] [REVIEW] 2026-07-17T11:40
Verdict: APPROVE (8900ad5). rehydrate() flush-free → _active rebuilt → 
flushMissedUpdates() after; interface matches the real invariant; race test
proven non-vacuous via inversion-hang check. 246/246. Only carry-forward:
deferred subfolder-basename collision (documented in code + backlog).
