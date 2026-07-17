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
