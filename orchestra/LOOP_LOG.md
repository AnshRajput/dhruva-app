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
