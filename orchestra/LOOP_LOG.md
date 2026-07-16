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
