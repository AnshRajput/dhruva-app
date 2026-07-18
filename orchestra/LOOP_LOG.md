# LOOP LOG

Roadmap (frozen launch scope): L0 research+identity · L1 skeleton+org · L2 engine
online · L3 model manager+HF hub · L4 chat · L5 characters · L6 voice · L7 vision ·
L8 imagine · L9 docs RAG · L10 toolbox · L11 polish · L12 website · L13 distribution ·
L14 hardening+handover. Then CONTINUOUS MODE.

---

## LOOP 0 — Deep research & identity (started 2026-07-17)
Goal: verified research digest, ADR-001/002/003, DHRUVA brand ceremony,
design-tokens.json, locked roadmap + MVP scope.
Exit gate:
1. Three scout RESEARCH reports on the blackboard with sources
2. ADR-001 (engine choice) and ADR-002 (app architecture) written
3. NAMING.md verification complete; name ratified in ADR-003
4. design-tokens.json committed at repo root
5. TASKS.md roadmap + MVP scope locked
Status: CLOSED 2026-07-17 — gate 5/5 on attempt 1.
Shipped: 3 research reports (orchestra/research/), NAMING.md, ADR-001/002/003
accepted, design-tokens.json, roadmap+MVP locked, both GitHub repos created and
pushed, agent roster in .claude/agents/.
Retro: (1) BIGGEST LESSON — haiku scouts hallucinate version numbers; every
version/package claim now requires orchestrator verification against pub.dev/
GitHub APIs before ratification (cost us one verification round on ADR-001; the
recommendation survived, the evidence didn't). (2) Reviewer critique of the
brand caught 6 real M3 completeness gaps — the critique-once ceremony step
earns its keep; keep adversarial review on every design artifact. (3) Running
designer/reviewer serially was the right call (shared file), but overlapping
Loop 1 scaffold work with the ceremony tail cost nothing — keep overlapping
non-conflicting work across loop boundaries. (4) Carry into Loop 1 prompts:
builders must consume design-tokens.json via the documented heightMultiplier
field, not recompute.

## LOOP 1 — Skeleton & org (2026-07-17)
Goal: both repos skeletoned, building, CI-gated, presentable.
Exit gate results (5/5, attempt 1):
1. flutter test green — PASS (local + CI)
2. flutter build apk succeeds — PASS (CI release build)
3. astro build succeeds — PASS (local + CI)
4. CI green on merged PR in BOTH repos — PASS (app#1, site#1 squash-merged)
5. README v1 + CLAUDE.md in both repos — PASS
Bonus: GitHub Pages LIVE at https://anshrajput.github.io/dhruva-website/ (200).
Shipped: Flutter scaffold (tech.appuinside.dhruva, strict lints, make verify),
app CI (format/analyze --fatal-infos/test+70% floor/android release/ios
no-codesign), Astro scaffold + Pages deploy pipeline, README v1, CONTRIBUTING,
issue templates, placeholder landing page.
Retro: (1) subosito/flutter-action + cache made CI fast enough — keep. (2) The
strict lint set caught real template debt (unsorted deps, import order) —
--fatal-infos from day 1 was right. (3) Placeholder page hardcodes two token
hexes (ponytail-marked) — Loop 12 must replace with token-fetch theming; risk
of drift accepted knowingly for 11 loops. (4) Carry into Loop 2: pin
llama_cpp_dart to an exact commit SHA in pubspec AND record it in DECISIONS.md.

## LOOP 2 — Engine online (2026-07-17)
Goal: real GGUF loads and streams through our abstraction, off root isolate,
working cancel, proven free path.
Exit gate results (attempt 2):
1. Debug chat streams completions on a desktop build — PASS (macOS dev target;
   real SmolLM2-135M, 64.9 tok/s Metal)
2. Engine unit tests green — PASS (39 tests: contract, adversarial QA,
   real-model smoke, RSS free-path incl. failed-ctx-create)
3. QA verdict — PASS (after BUG A/B fixes)
4. Reviewer verdict — APPROVE (after blocking leak fix)
5. CI green on merged PR — PASS (attempt 2; attempt 1 failed on coverage scope)
Shipped: EngineService abstraction + owned-isolate LlamaEngineService (typed
failure taxonomy across the isolate boundary, single stream error channel,
cooperative cancel via _GenGate, File-existence precheck), FakeEngineService,
debug chat harness, pinned llama_cpp_dart @ c6e377, macOS dev platform.
Retro: (1) BIGGEST LESSON — the pinned package's own LlamaEngine leaks
~167MB/reload; "verify the dependency's claims against its source" (Loop 0
lesson) paid off again at the code level: owning the isolate + reusing sync
primitives beat blind wrapping. (2) QA→fix→review→fix chain caught a real
mobile-OOM leak path the builder missed — the adversarial gate sequence is
worth its wall-clock. (3) Gate attempt 1 failure was self-inflicted: coverage
floor didn't implement §9's glue exclusion from day 1; scope rulings belong in
CI code the moment they're written down. (4) Docs-only pushes cancel in-flight
CI (concurrency group) — add paths-ignore for orchestra/** and docs/** in
Loop 3. (5) Carry into Loop 3: debug_chat's hard-wired concrete service made
it untestable — Loop 3+ features MUST take EngineService via Riverpod DI from
the first line.

## LOOP 3 — Model Manager & Hugging Face hub (2026-07-17)
Goal: browse HF GGUF repos in-app, device-aware verdicts, resumable verified
downloads, local import, storage manager.
Exit gate results (attempt 1 logically; 3 CI runs for env/target issues):
1. E2E download flow — PASS (real-socket localhost E2E over the real manager:
   search→detail→enqueue→range-resume→integrity→drift)
2. Offline/resume/corrupt states typed and tested — PASS
3. make verify + floor-scope coverage ≥70% — PASS (246 tests, 77%)
4. QA PASS + reviewer APPROVE — PASS (after 2 QA fixes + 2 review fix rounds)
5. CI green on merged PR — PASS
Shipped: DI root, device tiering, HfApiClient, drift store, DownloadManager
(sanitized choke point, restart rehydration with rebuild-before-flush
invariant, typed failures), storage manager, GGUF import, full models_hub UI
(license-before-download, verdict chips, retry affordance).
Retro: (1) BIGGEST LESSON — the reviewer caught the SAME bug twice at
different depths (restart orphan, then the fix's own flush-before-rebuild
race): ordering invariants around event streams need the invariant IN THE
INTERFACE CONTRACT, and a test that emits during the window; "verified
non-vacuous by inverting" is now the standard for race tests. (2) QA's
trust-boundary probe (path traversal) found a real gap the builders' 163
tests missed — adversarial QA stays mandatory. (3) Two CI environment
lessons: transient CocoaPods CDN failures (retry once before researching —
worked) and template deployment targets drifting from recorded decisions
(iOS 13.0 vs our 14+ floor) — decisions that imply build config must be
applied to build config the day they're made. (4) Carry into Loop 4: chat
consumes storageManager's ordered installed list + touchLastUsed; use
DownloadProgress.failure (typed) not errorMessage; designer gate is BLOCKING.

## LOOP 4 — Chat experience / MVP (2026-07-17) — v0.1.0-alpha SHIPPED
Goal: pick installed model → genuinely pleasant offline streaming chat. The MVP.
Exit gate (all met): MVP journey works on real engine (restart-persistence
proven) ✅ · designer SIGN-OFF (blocking) ✅ · QA PASS ✅ · reviewer APPROVE ✅ ·
CI green ✅ · v0.1.0-alpha tagged + distributed to internal-testers ✅
Shipped: full chat (streaming markdown/code, tok/s, reasoning collapse,
regenerate/edit, sampling sheet, folders/search, export), token-derived theme
+ bundled OFL fonts, Settings (clear-all + About page with ध्रुव + credit),
global download badge, recommended-for-device rail, Android AAR (chat-capable
APKs), engine multi-turn/seed/timeout. 463 tests, coverage 80.7%.
Beyond-scope this loop (human amendments 1-4): premium website live on Vercel
+ Pages, App Distribution pipeline proven, credit bar, continuous-ship rule.
Retro: (1) BIGGEST LESSON — three real-device/CI-only failures escaped 460+
green local tests: release-manifest INTERNET permission, Flutter version skew
(CI stable ran ahead of local, removed CupertinoPageTransitionsBuilder), iOS
deploy target. Local green != device/CI green. Actions: CI now pins Flutter to
local; distribute.sh exists; ADD to Loop 11 a "release-config audit" (manifest
perms, deploy targets, signing) and consider a smoke-install job. (2) The
human tester found the network bug in minutes — real-device distribution from
day one (amendment 4a) is worth its weight; keep shipping every loop.
(3) autoDispose on family providers is not optional on a memory-tiered app —
add to the architecture checklist so it's caught at BUILD not REVIEW.
(4) Six review/QA rounds (QA→fix→designer→fix→reviewer→fix) all found real
issues — the adversarial chain earns its cost on the flagship feature.

## LOOP 5 — Characters (2026-07-17)
Goal: create/edit/chat characters; 10 starters; community card import/export.
Exit gate (all met): CRUD+chat works, persona changes real-model behavior
(Captain Byte pirate vs neutral) ✅ · cards round-trip JSON+PNG ✅ · 10 starters
seeded ✅ · designer SIGN-OFF ✅ · QA PASS ✅ · reviewer APPROVE ✅ · CI green ✅
Shipped: drift v3 (characters + conversations.characterId, migration tested),
CharacterRepository + chatContextFor, TavernAI CharacterCard V2 interop
(JSON + pure-Dart PNG tEXt/iTXt chunk r/w, CRC32 pinned), gallery/create/edit/
detail UI, 10 built-in personas (region-safe guardrails), persona→engine
system-prompt binding (snapshotted at creation). 589 tests, coverage 79.8%.
Retro: (1) Untrusted-import trust boundary was the risk center — QA's HIGH
(sampling TypeError) + reviewer's zlib-bomb nit both lived there; lesson: any
"import a file from anywhere" feature gets an explicit adversarial-input pass
on EVERY field path, not just the happy parse. (2) Batching designer+QA
findings into one fix pass (vs serial) saved a round-trip — keep doing it when
both reviews land close together. (3) pumpAndSettle hangs on real dart:io
file I/O under the fake clock — established pattern now: unit-level repro for
I/O bugs, not settling widget tests. (4) Persona snapshot-at-creation (vs
live-link) was the right call — reviewer confirmed; document as the pattern
for Loop 7+ (vision/docs attaching context to a conversation).

## LOOP 6 — Voice (2026-07-18)
Goal: hold-to-talk STT, per-character TTS, hands-free conversation w/ barge-in.
Exit gate (all met): voice loop integration test (audio→transcript→chat→TTS) ✅
· voice models via Model Manager ✅ · hands-free turn-taking + barge-in ✅ ·
designer SIGN-OFF ✅ · QA PASS ✅ · reviewer APPROVE ✅ · CI green ✅
Shipped: sherpa_onnx 1.13.4 (STT+TTS+Silero VAD, real round-trip verified),
VoiceService w/ VAD-as-first-class-primitive, hold-to-talk composer, per-msg
TTS, hands-free state machine + barge-in, 4-model voice catalog (sha256-pinned)
via existing DownloadManager + zip-slip-guarded installer. 686 tests, cov 80.4%.
Retro: (1) BIGGEST LESSON — TWO mic-hot privacy races (dispose-mid-hold found
by QA, quick-tap-before-start found by reviewer) both slipped the builder AND
the layer that "fixed" the first one; async resource acquisition (mic/camera/
any capture) needs a release-requested pattern from the start, and tests that
DON'T await the acquire to expose the window. Add to arch checklist. (2)
Extending motion tokens (vs forcing a bad fit) kept the design system honest —
the right call when a real need doesn't match existing tokens. (3) Reviewer's
privacy-first lens on a capture feature earned its cost — the second race was
invisible to functional tests. (4) sherpa macOS codesign self-heal (R11) is a
dev-env quirk, not a product issue; on-device voice still needs a physical pass.

## UX-HARDENING LOOP (2026-07-18) — Amendments 5+6, shipped v0.2.0+21
Trigger: human tested distributed alpha on real Android — core broken (can't
chat, model needs restart to appear, no download feedback, "not usable").
Method change: unit-test-green was NOT proof; adopted real-component verification.
Diagnosis (4 parallel agents, orchestra/research/ux/): ROOT CAUSE = installed-
model providers never invalidated on download-complete → model invisible until
restart → can't start a chat / no model loads. SECOND root cause (why our first
hotfix "didn't work" on device): every build shipped as versionCode 1.0.0+1 →
Android kept the OLD APK on reinstall → user retested stale binaries.
Fixed + verified with REAL components on macOS: A1 invalidation (real
DownloadManager completion → model visible w/o restart, proven via real UI
E2E STEP1-5); real engine streams a real reply (unit test); Chat action carries
model (was landing in empty chat = "can't chat"); download-on-listing +
DownloadProgressRing (circular, ≥44px cancel, Semantics) + detail-tile feedback
+ OS notifications w/ progress + delete-on-listing + ranked/mobile/device-tiered
discovery + clear-all/new-chat refresh + first-run guidance. Version discipline:
0.2.0 + unique per-build number (git commit count); About shows version.
Riverpod KEPT (ruling upheld — all 4 diagnoses confirmed correct usage; the bug
was missing-invalidate, not the tool). make verify green (734 pass, 1 skip).
Retro: (1) BIGGEST LESSON — same versionCode across builds meant fixes never
reached the device; a real tester loop REQUIRES a monotonic build number from
day one. (2) unit tests with fakes read a provider directly and never proved the
real UI updates — the real DownloadManager→real-screen test caught what fakes
hid. (3) full-widget E2E can't pump the cross-isolate engine to a reply under
flutter_test — decompose: real-UI proves the state/visibility chain, real-engine
unit test proves the reply; device proves on-device inference. (4) OPEN: does
on-device arm64 inference reply? — awaiting human retest of 0.2.0+21.

## LOOP 7 — Vision (2026-07-18) — integrated onto v0.2.0
Goal: attach photos/screenshots to chat; on-device image Q&A; auto mmproj pairing.
Exit gate (all met): image→Q→A round trip (real SmolVLM: red→"Red.", blue→
"Blue.", "CAT"→"CAT") ✅ · mmproj pairing automatic ✅ · non-vision hides attach ✅
· designer SIGN-OFF ✅ · QA PASS ✅ · reviewer APPROVE ✅ · CI green ✅
Shipped: llama.cpp libmtmd via llama_cpp_dart (EngineLoadParams.mmprojPath,
ChatTurn.images, isMultimodal), drift v4 mmproj pairing + combined-size tier,
attach flow (gallery+camera, downscale, lightbox, extract-text), corrupt-image
+ GIF hardening. Merged cleanly with v0.2.0 hardening (both features intact).
819 tests. Parked mid-loop for the UX-hardening emergency, then integrated onto
the advanced main + all QA/designer fixes applied in one pass.
Retro: (1) Parking a mid-review loop to handle a critical user regression, then
integrating it onto the advanced main, worked — the merge was only 4 conflict
files and a clean schema v3→v4 stack; keep loops small enough that a later
rebase stays tractable. (2) Reviewer's merge-correctness focus (vs re-reviewing
the whole feature) was the right proportionate gate for an integration. (3)
Real vision test surviving the merge (re-run, not assumed) is what proved the
integration didn't silently break the feature.

## UX-CRASH-FIX loop (v0.2.3, 2026-07-18) — the video regression
Trigger: human recorded a screen video on build 0.2.2 (29) — app crashed 4–5×,
every download killed the app, no model ever installed, "really really
disappointed", "I don't want a dummy project". Analysed the video (52 frames +
audio transcript) into orchestra/VIDEO_FIXES.md.
Root cause (a regression I shipped in 0.2.2): the download fix
(Config.runInForeground = always) starts background_downloader's WorkManager
foreground service. On API 34+ it starts foreground with type dataSync, but the
app declared neither the FGS permissions NOR the dataSync foregroundServiceType
on androidx.work's SystemForegroundService → IllegalArgumentException
"foregroundServiceType 0x1 is not a subset of 0x0" → crash on every download.
Fix: add FOREGROUND_SERVICE + FOREGROUND_SERVICE_DATA_SYNC; merge
android:foregroundServiceType="dataSync" onto SystemForegroundService via
tools:node="merge". Shipped with the dio migration + model-detail rework
(recommended-download-first) that were already on loop/ux-dio-detail.
Verified END-TO-END on emulator (API 36, arm64) BY ME before shipping: browse →
one Recommended download → ring fills 1→48→100% → installs → chat replies
on-device at 1.0 tok/s. No crash. Shipped v0.2.3 (33) to Firebase.
Retro / the lesson that matters: (1) The permission fix ALONE still crashed —
the dataSync service-type merge was the other half. I only found it because I
drove the emulator and read the actual crash, not because I reasoned from
source. On-device verification is now a hard gate in CLAUDE.md, not a nicety.
(2) The original 0.2.2 bug shipped BECAUSE I uploaded to Firebase without
installing it and tapping Download once myself. Never again — "test on-device
before every deploy" is locked into the goal. (3) The human's real ask is
bigger than any single bug: real value, end-to-end, not a playground. That's
now the north-star in CLAUDE.md. Remaining video asks (UI-match-website,
per-variant benchmark, download ETA, in-app Playground+AI-news, value-highlight)
are queued as the next loop(s).

## UI-PARITY loop (v0.2.4 + v0.2.5, 2026-07-18) — the rest of the video
After the crash fix, the human asked to "complete all" remaining video points.
Ran parallel builders (chat/voice UI parity, benchmark/ETA/value, playground) —
a git-stash race between concurrent agents on ONE shared checkout crossed their
working trees (rescued to .rescue-foreign/). Lesson: do NOT run multiple agents
mutating the same repo without reliable worktree isolation; isolation:worktree
mis-targeted the sibling website repo here. Recovered deterministically:
committed A + C, integrated, dropped the half-broken playground from v0.2.4.
Shipped v0.2.4: dark theme default, chat/voice website parity, per-quant quality
chips, download ETA/speed, in-app + website value copy. Then a SINGLE sequential
agent (no concurrency = no collision) finished the rest -> v0.2.5: playground
two-model compare + AI-news (fixed a subscription-cancel deadlock that stranded
model B's load), voice re-detects installed models without restart, voice STT
accuracy (Silero maxSpeechDuration 5s->20s stopped chopping sentences mid-word),
generation persistence (in-app leave/reconnect verified; true background-while-
minimised deferred to a foreground service, RISKS R12). Each verified on the
emulator before shipping; make verify green (840 tests). Retro: (1) one agent at
a time on a shared repo, or nothing. (2) Ship the verified subset, defer the
unverified feature (playground held out of v0.2.4) rather than ship red. (3)
On-device screenshotting caught what tests can't (dark theme, nav tab, empty
states) — kept as the release gate.
