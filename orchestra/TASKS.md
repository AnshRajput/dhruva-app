# TASKS — living kanban

## ROADMAP (locked 2026-07-17, Loop 0 gate)
L1 skeleton+org → L2 engine online → L3 model manager+HF hub → L4 chat →
L5 characters → L6 voice → L7 vision → L8 imagine → L9 docs RAG → L10 toolbox →
L11 polish+arena → L12 website → L13 distribution → L14 hardening+handover →
CONTINUOUS MODE.

**MVP (Loops 1–4):** install → browse HF → download a recommended model →
genuinely pleasant offline chat. Tag v0.1.0-alpha at MVP gate.

**Scope amendments from Loop 0 research:**
- Loop 4 chat MUST include reasoning-token transparency (collapsible
  `<think>` block rendering) — top user ask, cheap to ship.
- Loop 6 voice is judged on ORCHESTRATION (VAD, turn-taking, interruption),
  not raw STT/TTS presence.
- Device floor: minSdk 26 (Android 8.0), iOS 14+. Tiers: 1B models → 4GB+
  RAM, 3B+ → 6GB+.
- Starter catalog (verified repos): Llama-3.2-1B/3B, Qwen2.5-1.5B,
  SmolLM2-1.7B, Phi-4-mini (bartowski/unsloth GGUF Q4_K_M); embeddings
  All-MiniLM-L6-v2; vision SmolVLM2-2.2B + mmproj.

## IN-LOOP (Loop 0 — closing)
- [x] Competitor feature matrix — scout-1
- [x] Engine bindings research — scout-2 (version claims corrected by orchestrator)
- [x] HF API verification + NAMING dossier — scout-3
- [x] ADR-001 engine choice (llama_cpp_dart @ pinned git commit) — ACCEPTED
- [x] ADR-002 app architecture (feature-first) — ACCEPTED
- [x] Name ratified: DHRUVA (display "Dhruva AI")
- [ ] design-tokens.json + ADR-003 — designer (IN PROGRESS) → reviewer critique → ratify
- [x] Roadmap + MVP scope locked (this file)

## BACKLOG (triaged)
- Cross-device model/chat sync over LAN/P2P, opt-in, no cloud (scout-1 idea #1;
  pairs with LAN server mode stretch)
- Agentic on-device tool use (alarms/notes intents) — existing stretch
- NPU acceleration (llama_cpp_dart Hexagon AAR exists — revisit post-V1)
- Home-screen widgets / iOS Shortcuts, character marketplace page, F-Droid,
  Play Store kit, full Hindi UI pass

## BLOCKED
(none)

## DONE
- [x] Factory verification — orchestrator
- [x] Workspace + orchestra + agent roster seeded — orchestrator
- [x] Local git repos initialized (dhruva-app, dhruva-website), Apache-2.0
